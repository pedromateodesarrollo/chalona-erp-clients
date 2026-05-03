// Cliente HTTP shell para ecf-service. Espejo del cliente Dart.
//
// El cliente shell es delgado: descarga un *motor* (DLL compilado dinámicamente)
// desde el servidor al arrancar y delega toda la lógica a él via trampolín.
//
// Métodos públicos: Login, EnviaEcf, EnviaEcfDesde, ConsultaEstado, DescargaXmls
//
// Trampolín: motor.Procesar(estadoJson) devuelve {kind:"http"|"done"|"fail"}.
//   - http  → shell ejecuta POST y alimenta respuesta al motor
//   - done  → devuelve result (guarda newToken si vino)
//   - fail  → lanza EcfApiError

using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ChalonaCsDriver;

// ---------------------------------------------------------------------------
// Tipos públicos
// ---------------------------------------------------------------------------

public sealed class EcfApiError(string code, IReadOnlyDictionary<string, object?>? data = null, int? statusCode = null)
    : Exception($"EcfApiError(code={code}{(statusCode is int s ? $", status={s}" : "")})")
{
    public string Code { get; } = code;
    public new IReadOnlyDictionary<string, object?> Data { get; } = data ?? new Dictionary<string, object?>();
    public int? StatusCode { get; } = statusCode;
}

public sealed record MotorMeta(int Version, string Entorno, string HashSha256, int Tamano);

public sealed record EcfFile(string FileName, byte[] Bytes);

// ---------------------------------------------------------------------------
// EcfClient
// ---------------------------------------------------------------------------

public sealed class EcfClient : IAsyncDisposable
{
    private readonly string _baseUrl;
    private readonly string _motorEntorno;
    private readonly HttpClient _http;
    private readonly TimeSpan _timeout;
    private string? _token;

    // Motor lazy
    private DriverHandle? _motor;
    private MotorMeta? _motorMeta;

    public EcfClient(
        string baseUrl = "https://ecf-service.vicortiz.com",
        string motorEntorno = "produccion",
        string? token = null,
        TimeSpan? timeout = null,
        HttpClient? httpClient = null)
    {
        _baseUrl = baseUrl.TrimEnd('/');
        _motorEntorno = motorEntorno;
        _token = token;
        _timeout = timeout ?? TimeSpan.FromSeconds(60);
        _http = httpClient ?? new HttpClient();
    }

    public string? Token => _token;
    public MotorMeta? MotorMeta => _motorMeta;
    public void ClearToken() => _token = null;

    // ===========================================================================
    // API pública
    // ===========================================================================

    public async Task<Dictionary<string, object?>> LoginAsync(
        string usuario, string clave, string app = "ecf")
    {
        var r = await DispatchAsync("login", new JsonObject
        {
            ["usuario"] = usuario,
            ["clave"] = clave,
            ["app"] = app,
        });
        return r.Result;
    }

    public async Task<Dictionary<string, object?>> EnviaEcfAsync(
        string rnc, string portal, JsonObject json)
    {
        var r = await DispatchAsync("enviaEcf", new JsonObject
        {
            ["rnc"] = rnc,
            ["portal"] = portal,
            ["json"] = json,
        });
        return r.Result;
    }

    public async Task<DocumentoEcf> EnviaEcfDesdeAsync(
        DocumentoEcf documento, string portal)
    {
        var encfVal = documento.Encf?.Trim() ?? "";
        var fiscalVal = documento.Fiscal.Trim();
        if (encfVal.Length > 0 && fiscalVal.Length > 0)
        {
            var prefijo = $"E{fiscalVal}";
            if (!encfVal.StartsWith(prefijo, StringComparison.Ordinal))
                throw new ArgumentException(
                    $"eNCF \"{encfVal}\" no coincide con TipoeCF {fiscalVal} " +
                    $"(prefijo esperado: {prefijo}). DGII error 75.");
        }
        var r = await DispatchAsync("enviaEcfDesdeDoc", new JsonObject
        {
            ["documento"] = documento.ToJsonObject(),
            ["portal"] = portal,
        });
        var res = r.Result;
        if (res.TryGetValue("encf", out var encf) && encf is string encfStr)
            documento.Encf = encfStr;
        if (res.TryGetValue("estado", out var est)) documento.Estado = est as string;
        if (res.TryGetValue("estado_descripcion", out var ed)) documento.EstadoDescripcion = ed as string;
        if (res.TryGetValue("codigo_seguridad", out var cs)) documento.CodigoSeguridad = cs as string;
        if (res.TryGetValue("fecha_firma", out var ff)) documento.FechaFirma = ff as string;
        if (res.TryGetValue("timbre", out var tb)) documento.Timbre = tb as string;
        if (res.TryGetValue("secuencia_utilizada", out var su))
            documento.SecuenciaUtilizada = su switch
            {
                bool b => b,
                long l => l != 0,
                int i => i != 0,
                _ => null,
            };
        if (res.TryGetValue("momento", out var mo)) documento.Momento = mo as string;
        if (res.TryGetValue("respuesta_mensajes", out var rm)) documento.RespuestaMensajes = rm as string;
        return documento;
    }

    public async Task<List<object?>> ConsultaEstadoAsync(IEnumerable<string> comprobantes)
    {
        var lista = new JsonArray();
        foreach (var c in comprobantes) lista.Add(c);
        var r = await DispatchAsync("consultaEstado", new JsonObject { ["comprobantes"] = lista });
        if (r.Result.TryGetValue("result", out var raw) && raw is List<object?> list)
            return list;
        return [];
    }

    public async Task<(Dictionary<string, object?> Data, IReadOnlyList<EcfFile> Files)> DescargaXmlsAsync(
        string fechaDesde, string fechaHasta, IEnumerable<string>? tipos = null)
    {
        var args = new JsonObject
        {
            ["fecha_desde"] = fechaDesde,
            ["fecha_hasta"] = fechaHasta,
        };
        var tiposList = tipos?.ToList() ?? [];
        if (tiposList.Count > 0)
        {
            var arr = new JsonArray();
            foreach (var t in tiposList) arr.Add(t);
            args["tipos"] = arr;
        }
        var r = await DispatchAsync("descargaXmls", args);
        return (r.Result, r.Files);
    }

    // ===========================================================================
    // Motor
    // ===========================================================================

    public async Task<MotorMeta?> LookupMotorAsync(string? entorno = null)
    {
        try
        {
            var raw = await HttpPostAsync(
                "cs_cliente_driver_lookup",
                new JsonObject { ["entorno"] = entorno ?? _motorEntorno },
                useToken: false);
            var data = raw["data"]?.AsObject() ?? new JsonObject();
            return new MotorMeta(
                Version: data["version"]?.GetValue<int>() ?? 0,
                Entorno: data["entorno"]?.GetValue<string>() ?? "",
                HashSha256: data["hash_sha256"]?.GetValue<string>() ?? "",
                Tamano: data["tamano"]?.GetValue<int>() ?? 0);
        }
        catch (EcfApiError e) when (e.Code == "cs_cliente_driver.no_disponible")
        {
            return null;
        }
    }

    public async Task<byte[]> DescargarMotorAsync(string? entorno = null, int? version = null)
    {
        var args = new JsonObject { ["entorno"] = entorno ?? _motorEntorno };
        if (version is int v) args["version"] = v.ToString();
        var raw = await HttpPostAsync("cs_cliente_driver_descargar", args, useToken: false);
        var data = raw["data"]?.AsObject() ?? new JsonObject();
        var b64 = data["bytes_b64"]?.GetValue<string>() ?? "";
        b64 = b64.Replace("\n", "").Replace("\r", "").Replace(" ", "");
        return Convert.FromBase64String(b64);
    }

    public async Task EnsureMotorAsync()
    {
        if (_motor != null) return;
        var meta = await LookupMotorAsync();
        if (meta is null)
            throw new EcfApiError("motor.no_disponible", new Dictionary<string, object?> { ["entorno"] = _motorEntorno });
        var bytes = await DescargarMotorAsync();
        var handle = DriverHandle.Cargar(bytes, $"v{meta.Version}");
        if (!handle.HashSha256.Equals(meta.HashSha256, StringComparison.OrdinalIgnoreCase))
            throw new EcfApiError("motor.hash_mismatch", new Dictionary<string, object?>
            {
                ["esperado"] = meta.HashSha256,
                ["recibido"] = handle.HashSha256,
            });
        _motor = handle;
        _motorMeta = meta;
    }

    public void ClearMotor()
    {
        _motor?.Dispose();
        _motor = null;
        _motorMeta = null;
    }

    // ===========================================================================
    // Trampolín
    // ===========================================================================

    private sealed record DispatchResult(Dictionary<string, object?> Result, IReadOnlyList<EcfFile> Files);

    private async Task<DispatchResult> DispatchAsync(string fnName, JsonObject args)
    {
        var reintentos = 0;
        while (true)
        {
            try
            {
                return await DispatchOnceAsync(fnName, args);
            }
            catch (EcfApiError e) when (
                e.Code == "cs_cliente_driver.version_desactualizada" && reintentos < 1)
            {
                reintentos++;
                ClearMotor();
            }
        }
    }

    private async Task<DispatchResult> DispatchOnceAsync(string fnName, JsonObject args)
    {
        await EnsureMotorAsync();
        var motor = _motor!;

        JsonObject? lastResp = null;
        IReadOnlyList<EcfFile> lastFiles = [];
        int step = 0;

        while (true)
        {
            var estado = new JsonObject
            {
                ["fnName"] = fnName,
                ["args"] = args.DeepClone(),
                ["token"] = _token,
                ["step"] = step,
                ["lastResp"] = lastResp?.DeepClone(),
            };
            var stepJson = motor.Instancia.Procesar(estado.ToJsonString());
            var stepMap = JsonNode.Parse(stepJson)?.AsObject()
                ?? throw new EcfApiError("motor.respuesta_invalida");
            var kind = stepMap["kind"]?.GetValue<string>();

            if (kind == "done")
            {
                var result = ParseResultDict(stepMap["result"]);
                var newToken = stepMap["newToken"]?.GetValue<string>();
                if (!string.IsNullOrEmpty(newToken)) _token = newToken;
                return new DispatchResult(result, lastFiles);
            }

            if (kind == "fail")
            {
                var code = stepMap["code"]?.GetValue<string>() ?? "motor.error_desconocido";
                throw new EcfApiError(code);
            }

            if (kind == "http")
            {
                var endpoint = stepMap["endpoint"]?.GetValue<string>() ?? "";
                var data = stepMap["data"]?.AsObject() ?? new JsonObject();
                var useToken = stepMap["useToken"]?.GetValue<bool>() ?? true;
                step = stepMap["step"]?.GetValue<int>() ?? (step + 1);

                var respFull = await HttpPostAsync(endpoint, data, useToken: useToken);
                lastFiles = ParseFiles(respFull);
                lastResp = new JsonObject
                {
                    ["ok"] = respFull["ok"]?.DeepClone(),
                    ["message"] = respFull["message"]?.DeepClone(),
                    ["data"] = respFull["data"]?.DeepClone(),
                };
                continue;
            }

            throw new EcfApiError("motor.kind_desconocido", new Dictionary<string, object?> { ["kind"] = kind });
        }
    }

    // ===========================================================================
    // HTTP bajo nivel
    // ===========================================================================

    private async Task<JsonObject> HttpPostAsync(
        string endpoint, JsonObject data, bool useToken)
    {
        var esMotorEndpoint = endpoint is "cs_cliente_driver_lookup" or "cs_cliente_driver_descargar";
        var dataConVersion = data.DeepClone().AsObject();
        if (!esMotorEndpoint && _motorMeta is not null)
        {
            dataConVersion["cs_driver_version"] = _motorMeta.Version;
            dataConVersion["cs_driver_entorno"] = _motorMeta.Entorno;
        }
        var body = new JsonObject
        {
            ["request"] = endpoint,
            ["data"] = dataConVersion,
        }.ToJsonString();

        using var req = new HttpRequestMessage(HttpMethod.Post, $"{_baseUrl}/")
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };
        if (useToken && _token is not null)
            req.Headers.Authorization = AuthenticationHeaderValue.Parse(_token);

        using var cts = new CancellationTokenSource(_timeout);
        HttpResponseMessage resp;
        try
        {
            resp = await _http.SendAsync(req, cts.Token);
        }
        catch (Exception ex)
        {
            throw new EcfApiError("http.error", new Dictionary<string, object?> { ["detail"] = ex.Message });
        }

        string bodyText;
        try { bodyText = await resp.Content.ReadAsStringAsync(); }
        catch (Exception ex)
        {
            throw new EcfApiError("http.lectura_error", new Dictionary<string, object?> { ["detail"] = ex.Message });
        }

        JsonObject out_;
        try
        {
            out_ = JsonNode.Parse(bodyText)?.AsObject()
                ?? throw new InvalidOperationException("null");
        }
        catch
        {
            var preview = bodyText.Length > 500 ? bodyText[..500] : bodyText;
            throw new EcfApiError("respuesta_no_json",
                new Dictionary<string, object?> { ["text"] = preview },
                (int)resp.StatusCode);
        }

        var ok = out_["ok"]?.GetValue<bool>() ?? false;
        if (!ok)
        {
            var msg = out_["message"]?.GetValue<string>() ?? "error_desconocido";
            throw new EcfApiError(msg, statusCode: (int)resp.StatusCode);
        }
        return out_;
    }

    private static IReadOnlyList<EcfFile> ParseFiles(JsonObject respFull)
    {
        if (respFull["files"] is not JsonArray arr) return [];
        var out_ = new List<EcfFile>();
        foreach (var item in arr)
        {
            if (item is not JsonObject m) continue;
            var name = m["fileName"]?.GetValue<string>()?.Trim() ?? "";
            var b64Raw = m["content"]?.GetValue<string>() ?? "";
            if (name.Length == 0 || b64Raw.Length == 0) continue;
            var b64 = b64Raw.Replace("\n", "").Replace("\r", "").Replace(" ", "");
            out_.Add(new EcfFile(name, Convert.FromBase64String(b64)));
        }
        return out_;
    }

    private static Dictionary<string, object?> ParseResultDict(JsonNode? node)
    {
        if (node is not JsonObject obj) return [];
        using var doc = JsonDocument.Parse(obj.ToJsonString());
        return JsonElementToDict(doc.RootElement);
    }

    private static Dictionary<string, object?> JsonElementToDict(JsonElement el)
    {
        var d = new Dictionary<string, object?>();
        foreach (var prop in el.EnumerateObject())
            d[prop.Name] = JsonElementToObject(prop.Value);
        return d;
    }

    private static object? JsonElementToObject(JsonElement el) => el.ValueKind switch
    {
        JsonValueKind.String => el.GetString(),
        JsonValueKind.Number when el.TryGetInt64(out var l) => l,
        JsonValueKind.Number => el.GetDouble(),
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.Null => null,
        JsonValueKind.Object => JsonElementToDict(el),
        JsonValueKind.Array => el.EnumerateArray().Select(JsonElementToObject).ToList(),
        _ => el.ToString(),
    };

    public async ValueTask DisposeAsync()
    {
        ClearMotor();
        _http.Dispose();
        await ValueTask.CompletedTask;
    }
}
