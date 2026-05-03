using System.Text.Json.Nodes;
using EcfClient.Comprobantes.Datos;
using EcfClient.Exceptions;

namespace EcfClient.Comprobantes;

/// <summary>Base para comprobantes e-CF. Subclases definen TipoEcf, Totales e IdDoc específico.</summary>
public abstract class ComprobanteBase
{
    public abstract int TipoEcf { get; }
    public virtual string Version { get; set; } = "1.0";

    public EmisorData Emisor { get; } = new();
    public CompradorData Comprador { get; } = new();
    public IList<DetalleItem> Items { get; } = new List<DetalleItem>();

    public string ENcf { get; set; } = "";
    public string FechaEmision { get; set; } = "";
    public string FechaVencimientoSecuencia { get; set; } = "";
    public int TipoPago { get; set; } = 1; // 1=Contado, 2=Crédito, 3=Gratuito
    public int TipoIngresos { get; set; } = 1; // 01-06
    public int IndicadorMontoGravado { get; set; }

    protected static string Trim(string? s) => s?.Trim() ?? "";

    protected virtual Dictionary<string, object?> BuildEmisor()
    {
        var e = Emisor;
        var out_ = new Dictionary<string, object?>
        {
            ["RNCEmisor"] = Trim(e.Rnc),
            ["RazonSocialEmisor"] = Trim(e.RazonSocial),
            ["DireccionEmisor"] = Trim(e.Direccion),
            ["FechaEmision"] = Trim(e.FechaEmision)
        };
        if (!string.IsNullOrWhiteSpace(e.NombreComercial)) out_["NombreComercial"] = e.NombreComercial.Trim();
        if (!string.IsNullOrWhiteSpace(e.Municipio)) out_["Municipio"] = e.Municipio.Trim();
        if (!string.IsNullOrWhiteSpace(e.Provincia)) out_["Provincia"] = e.Provincia.Trim();
        if (e.Telefonos?.Count > 0) out_["TablaTelefonoEmisor"] = e.Telefonos;
        if (!string.IsNullOrWhiteSpace(e.Correo)) out_["CorreoEmisor"] = e.Correo.Trim();
        return out_;
    }

    protected virtual Dictionary<string, object?> BuildComprador()
    {
        var c = Comprador;
        var out_ = new Dictionary<string, object?>
        {
            ["RNCComprador"] = Trim(c.Rnc),
            ["RazonSocialComprador"] = Trim(c.RazonSocial)
        };
        if (!string.IsNullOrWhiteSpace(c.IdentificadorExtranjero)) out_["IdentificadorExtranjero"] = c.IdentificadorExtranjero.Trim();
        if (!string.IsNullOrWhiteSpace(c.Contacto)) out_["ContactoComprador"] = c.Contacto.Trim();
        if (!string.IsNullOrWhiteSpace(c.Correo)) out_["CorreoComprador"] = c.Correo.Trim();
        if (!string.IsNullOrWhiteSpace(c.Direccion)) out_["DireccionComprador"] = c.Direccion.Trim();
        if (!string.IsNullOrWhiteSpace(c.Municipio)) out_["MunicipioComprador"] = c.Municipio.Trim();
        if (!string.IsNullOrWhiteSpace(c.Provincia)) out_["ProvinciaComprador"] = c.Provincia.Trim();
        return out_;
    }

    protected virtual IList<Dictionary<string, object?>> BuildDetalles()
    {
        var list = new List<Dictionary<string, object?>>();
        foreach (var it in Items)
        {
            var row = new Dictionary<string, object?>
            {
                ["NumeroLinea"] = it.NumeroLinea.ToString(),
                ["NombreItem"] = Trim(it.NombreItem),
                ["IndicadorFacturacion"] = it.IndicadorFacturacion.ToString(),
                ["IndicadorBienoServicio"] = it.IndicadorBienServicio.ToString(),
                ["CantidadItem"] = it.Cantidad.ToString("F2"),
                ["PrecioUnitarioItem"] = it.PrecioUnitario.ToString("F2"),
                ["MontoItem"] = it.MontoItem.ToString("F2")
            };
            if (!string.IsNullOrWhiteSpace(it.UnidadMedida)) row["UnidadMedida"] = it.UnidadMedida.Trim();
            if (it.Retencion != null)
                row["Retencion"] = new Dictionary<string, object?>
                {
                    ["IndicadorAgenteRetencionoPercepcion"] = "1",
                    ["MontoITBISRetenido"] = it.Retencion.MontoItbisRetenido.ToString("F2"),
                    ["MontoISRRetenido"] = it.Retencion.MontoIsrRetenido.ToString("F2")
                };
            list.Add(row);
        }
        return list;
    }

    protected virtual Dictionary<string, object?> BuildIdDoc()
    {
        return new Dictionary<string, object?>
        {
            ["TipoeCF"] = TipoEcf.ToString(),
            ["eNCF"] = Trim(ENcf),
            ["FechaVencimientoSecuencia"] = Trim(FechaVencimientoSecuencia),
            ["TipoPago"] = TipoPago.ToString(),
            ["TipoIngresos"] = TipoIngresos.ToString("D2")
        };
    }

    protected abstract Dictionary<string, object?> BuildTotales();

    protected virtual InformacionReferencia? BuildInformacionReferencia() => null;

    /// <summary>Construye el JSON completo para envia_ecf.</summary>
    public Dictionary<string, object?> ToPayload()
    {
        var encabezado = new Dictionary<string, object?>
        {
            ["Version"] = Version,
            ["IdDoc"] = BuildIdDoc(),
            ["Emisor"] = BuildEmisor(),
            ["Comprador"] = BuildComprador(),
            ["Totales"] = BuildTotales()
        };
        var payload = new Dictionary<string, object?>
        {
            ["Encabezado"] = encabezado,
            ["DetallesItems"] = BuildDetalles()
        };
        var info = BuildInformacionReferencia();
        if (info != null)
            payload["InformacionReferencia"] = new Dictionary<string, object?>
            {
                ["NCFModificado"] = Trim(info.NcfModificado),
                ["FechaNCFModificado"] = Trim(info.FechaNcfModificado),
                ["CodigoModificacion"] = Trim(info.CodigoModificacion)
            };
        return payload;
    }

    /// <summary>Valida campos obligatorios y reglas por tipo. Lanza EcfValidationException.</summary>
    public virtual void Validate()
    {
        Validation.ValidarEncf(ENcf);
        var exigirDireccion = true;
        if (TipoEcf == 32 && GetMontoTotalVal() < 250_000)
            exigirDireccion = false; // RFCE
        Validation.ValidarEmisor(Emisor, exigirDireccion);
        var obligatorioComprador = TipoEcf != 43;
        Validation.ValidarComprador(Comprador, obligatorioComprador);
        Validation.ValidarItems(Items, TipoEcf);
        if (TipoEcf is 33 or 34)
        {
            var info = BuildInformacionReferencia();
            if (info == null)
                throw new EcfValidationException("InformacionReferencia requerida para tipo 33/34", new[] { new ValidationError("InformacionReferencia", "ecf.requerido") });
            Validation.ValidarInformacionReferencia(info);
        }
        ValidateExtra();
    }

    protected virtual double GetMontoTotalVal() => 0;

    protected virtual void ValidateExtra() { }

    /// <summary>Valida y envía el comprobante. Devuelve data de la respuesta.</summary>
    public async Task<JsonNode?> EnviarAsync(EcfClient client, string rnc, string portal, CancellationToken cancellationToken = default)
    {
        Validate();
        return await client.EnviaEcfAsync(rnc, portal, ToPayload(), cancellationToken).ConfigureAwait(false);
    }
}
