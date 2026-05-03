using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using EcfClient.Exceptions;

namespace EcfClient;

/// <summary>Cliente para login, envío de comprobantes e-CF y consulta de estado.</summary>
public class EcfClient
{
    private const string DefaultBaseUrl = "https://ecf-service.vicortiz.com";
    private static readonly JsonSerializerOptions SerializeOptions = new() { PropertyNamingPolicy = null };
    private readonly HttpClient _httpClient;
    private string? _token;

    public string BaseUrl { get; }

    public EcfClient(string? baseUrl = null, string? token = null, HttpClient? httpClient = null)
    {
        BaseUrl = (baseUrl ?? DefaultBaseUrl).TrimEnd('/');
        _token = token;
        _httpClient = httpClient ?? new HttpClient();
        _httpClient.BaseAddress = new Uri(BaseUrl + "/");
        _httpClient.DefaultRequestHeaders.TryAddWithoutValidation("Content-Type", "application/json");
    }

    private async Task<JsonNode?> RequestAsync(string endpoint, object data, bool useToken = true, CancellationToken cancellationToken = default)
    {
        var body = new Dictionary<string, object?> { ["request"] = endpoint, ["data"] = data };
        using var request = new HttpRequestMessage(HttpMethod.Post, "");
        request.Content = new StringContent(JsonSerializer.Serialize(body, SerializeOptions), Encoding.UTF8, "application/json");
        if (useToken && !string.IsNullOrEmpty(_token))
            request.Headers.TryAddWithoutValidation("Authorization", _token);

        var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var raw = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);

        var root = JsonNode.Parse(raw) as JsonObject;
        if (root == null || !root.TryGetPropertyValue("ok", out var okVal) || okVal?.GetValue<bool>() != true)
        {
            var message = root?.TryGetPropertyValue("message", out var m) == true ? m?.GetValue<string>() ?? "error_desconocido" : "error_desconocido";
            Dictionary<string, object?>? dataObj = null;
            if (root?.TryGetPropertyValue("data", out var d) == true && d is JsonObject dataObjNode)
                dataObj = JsonSerializer.Deserialize<Dictionary<string, object?>>(dataObjNode.ToJsonString());
            throw new EcfApiException(message, dataObj ?? new Dictionary<string, object?>());
        }
        return root.TryGetPropertyValue("data", out var dataProp) ? dataProp : null;
    }

    /// <summary>Autentica y guarda el token en el cliente. Devuelve data (app, usuario, empresa, token).</summary>
    public async Task<JsonNode?> LoginAsync(string usuario, string clave, string aplicacion = "ecf_service", CancellationToken cancellationToken = default)
    {
        var data = new Dictionary<string, object?> { ["aplicacion"] = aplicacion, ["usuario"] = usuario, ["clave"] = clave };
        var result = await RequestAsync("sistema_login", data, useToken: false, cancellationToken).ConfigureAwait(false);
        if (result is JsonObject obj && obj.TryGetPropertyValue("token", out var tokenVal))
            _token = tokenVal?.GetValue<string>();
        return result;
    }

    /// <summary>Envía un comprobante e-CF. Requiere haber hecho login. Devuelve data del registro.</summary>
    public async Task<JsonNode?> EnviaEcfAsync(string rnc, string portal, object jsonPayload, CancellationToken cancellationToken = default)
    {
        var data = new Dictionary<string, object?> { ["rnc"] = rnc, ["portal"] = portal, ["json"] = jsonPayload };
        return await RequestAsync("envia_ecf", data, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    /// <summary>Consulta estado de comprobantes por lista de e-NCF. Máximo 100. Devuelve data['result'].</summary>
    public async Task<JsonNode?> ConsultaEstadoAsync(IReadOnlyList<string> comprobantes, CancellationToken cancellationToken = default)
    {
        if (comprobantes.Count > 100)
            throw new ArgumentException("Máximo 100 comprobantes por petición", nameof(comprobantes));
        var data = new Dictionary<string, object?> { ["comprobantes"] = comprobantes };
        var result = await RequestAsync("consulta_estado", data, cancellationToken: cancellationToken).ConfigureAwait(false);
        return result is JsonObject o && o.TryGetPropertyValue("result", out var r) ? r : null;
    }
}
