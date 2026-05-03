// Modelo de comprobante e-CF — espejo de la estructura de cursores Fox
// y del DocumentoEcf del cliente Dart.
//
// El programador llena un DocumentoEcf con datos de su ERP y lo pasa a
// EcfClient.EnviaEcfDesde(). El motor (DLL bajado) lo recibe serializado,
// valida, arma el payload DGII, lo envía y devuelve el documento enriquecido
// con campos de resultado (Encf, Estado, Timbre, etc.).

using System.Globalization;
using System.Text.Json.Nodes;

namespace ChalonaCsDriver;

/// Documento e-CF (encabezado + colecciones).
public sealed class DocumentoEcf
{
    // ---- Identificación ----
    /// Tipo de comprobante DGII: 31=Cred.Fiscal, 32=Consumo, 33=ND, 34=NC.
    public string Fiscal { get; set; } = "";
    public string? Encf { get; set; }
    public string? Ncf { get; set; }
    public string? Control { get; set; }
    public DateTime Fecha { get; set; } = DateTime.Today;

    // ---- Montos ----
    public double Valor { get; set; }
    public double Descuento { get; set; }
    public double Itbis { get; set; }
    public double Total { get; set; }
    public double Tasa { get; set; } = 1;
    public string Moneda { get; set; } = "DOP";

    // ---- Retenciones ----
    public double ItbisRetenido { get; set; }
    public double IsrRetenido { get; set; }

    // ---- Para NC/ND (33, 34) ----
    public int? DgiiCodMod { get; set; }
    public DateTime? FechaVencEcf { get; set; }
    public int? DiasReferencia { get; set; }
    public string? Comentario { get; set; }

    // ---- Resultado del envío (lo llena el motor) ----
    public string? Estado { get; set; }
    public string? EstadoDescripcion { get; set; }
    public string? CodigoSeguridad { get; set; }
    public string? FechaFirma { get; set; }
    public string? Timbre { get; set; }
    public bool? SecuenciaUtilizada { get; set; }
    public string? Momento { get; set; }
    public string? RespuestaMensajes { get; set; }

    // ---- Relacionados ----
    public EmisorEcf Emisor { get; set; } = new();
    public CompradorEcf? Comprador { get; set; }
    public SuplidorEcf? Suplidor { get; set; }
    public List<LineaEcf> Lineas { get; set; } = [];
    public List<ReferenciaEcf> Referencias { get; set; } = [];
    public DateTime? FechaVenceFiscal { get; set; }

    /// Serializa a JsonObject con misma forma que cursores Fox / Dart.
    public JsonObject ToJsonObject()
    {
        var o = new JsonObject
        {
            ["fiscal"] = Fiscal,
            ["fecha"] = FmtDate(Fecha),
            ["valor"] = Valor,
            ["descuento"] = Descuento,
            ["itbis"] = Itbis,
            ["total"] = Total,
            ["tasa"] = Tasa,
            ["moneda"] = Moneda,
            ["itbisr"] = ItbisRetenido,
            ["isr"] = IsrRetenido,
            ["emisor"] = Emisor.ToJsonObject(),
        };
        if (Encf is not null) o["encf"] = Encf;
        if (Ncf is not null) o["ncf"] = Ncf;
        if (Control is not null) o["control"] = Control;
        if (DgiiCodMod is not null) o["dgii_codmod"] = DgiiCodMod;
        if (FechaVencEcf is not null) o["fechavencencf"] = FmtDate(FechaVencEcf.Value);
        if (DiasReferencia is not null) o["diascr"] = DiasReferencia;
        if (Comentario is not null) o["comentario"] = Comentario;
        if (Estado is not null) o["estado"] = Estado;
        if (EstadoDescripcion is not null) o["estado_descripcion"] = EstadoDescripcion;
        if (CodigoSeguridad is not null) o["codigo_seguridad"] = CodigoSeguridad;
        if (FechaFirma is not null) o["fecha_firma"] = FechaFirma;
        if (Timbre is not null) o["timbre"] = Timbre;
        if (SecuenciaUtilizada is not null) o["secuencia_utilizada"] = SecuenciaUtilizada.Value ? 1 : 0;
        if (Momento is not null) o["momento"] = Momento;
        if (RespuestaMensajes is not null) o["respuesta_mensajes"] = RespuestaMensajes;
        if (Comprador is not null) o["comprador"] = Comprador.ToJsonObject();
        if (Suplidor is not null) o["suplidor"] = Suplidor.ToJsonObject();
        if (FechaVenceFiscal is not null) o["vence_fiscal"] = FmtDate(FechaVenceFiscal.Value);
        var lineas = new JsonArray();
        foreach (var l in Lineas) lineas.Add(l.ToJsonObject());
        o["lineas"] = lineas;
        if (Referencias.Count > 0)
        {
            var refs = new JsonArray();
            foreach (var r in Referencias) refs.Add(r.ToJsonObject());
            o["referencias"] = refs;
        }
        return o;
    }

    internal static string FmtDate(DateTime d) =>
        $"{d.Day:D2}-{d.Month:D2}-{d.Year}";
}

public sealed class EmisorEcf
{
    public string Rnc { get; set; } = "";
    public string Nombre { get; set; } = "";
    public string Direccion { get; set; } = "";
    public int IndicadorPrecio { get; set; }

    public JsonObject ToJsonObject() => new()
    {
        ["rnc"] = Rnc,
        ["nombre"] = Nombre,
        ["direccion"] = Direccion,
        ["iprecio"] = IndicadorPrecio,
    };
}

public sealed class CompradorEcf
{
    public string Nombre { get; set; } = "";
    public string? Rnc { get; set; }
    public bool Extranjero { get; set; }

    public JsonObject ToJsonObject()
    {
        var o = new JsonObject
        {
            ["nombre"] = Nombre,
            ["extranjero_flag"] = Extranjero ? 1 : 0,
        };
        if (Rnc is not null) o["rnc"] = Rnc;
        return o;
    }
}

public sealed class SuplidorEcf
{
    public string Rnc { get; set; } = "";
    public string Nombre { get; set; } = "";

    public JsonObject ToJsonObject() => new()
    {
        ["rnc"] = Rnc,
        ["nombre"] = Nombre,
    };
}

public sealed class LineaEcf
{
    public string Descripcion { get; set; } = "";
    public double Cantidad { get; set; }
    public double Precio { get; set; }
    public string? MercsNombre { get; set; }
    public bool EsServicio { get; set; }
    public double Itbis { get; set; }
    public double ItbisTasa { get; set; } = 18;
    public double ItbisRetenido { get; set; }
    public double IsrRetenido { get; set; }

    public JsonObject ToJsonObject()
    {
        var o = new JsonObject
        {
            ["descrip"] = Descripcion,
            ["cantidad"] = Cantidad,
            ["precio"] = Precio,
            ["mercs_servicio"] = EsServicio ? 2 : 1,
            ["itbis"] = Itbis,
            ["itbis_tasa"] = ItbisTasa,
            ["itbis_retenido"] = ItbisRetenido,
            ["isr_retenido"] = IsrRetenido,
        };
        if (MercsNombre is not null) o["mercs_nombre"] = MercsNombre;
        return o;
    }
}

public sealed class ReferenciaEcf
{
    public string Encf { get; set; } = "";
    public DateTime Fecha { get; set; }

    public JsonObject ToJsonObject() => new()
    {
        ["encf"] = Encf,
        ["fecha"] = DocumentoEcf.FmtDate(Fecha),
    };
}
