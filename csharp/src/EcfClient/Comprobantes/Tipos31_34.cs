using EcfClient.Comprobantes.Datos;

namespace EcfClient.Comprobantes;

/// <summary>Factura de Crédito Fiscal (tipo 31).</summary>
public class FacturaCreditoFiscal31 : ComprobanteBase
{
    public override int TipoEcf => 31;

    public double MontoGravadoTotal { get; set; }
    public double MontoGravadoI1 { get; set; }
    public int Itbis1 { get; set; } = 18;
    public double TotalItbis { get; set; }
    public double TotalItbis1 { get; set; }
    public double MontoTotal { get; set; }
    protected override double GetMontoTotalVal() => MontoTotal;

    protected override Dictionary<string, object?> BuildIdDoc()
    {
        var d = base.BuildIdDoc();
        d["FechaVencimientoSecuencia"] = Trim(FechaVencimientoSecuencia);
        d["IndicadorMontoGravado"] = IndicadorMontoGravado.ToString();
        return d;
    }

    protected override Dictionary<string, object?> BuildTotales() => new()
    {
        ["MontoGravadoTotal"] = MontoGravadoTotal.ToString("F2"),
        ["MontoGravadoI1"] = MontoGravadoI1.ToString("F2"),
        ["ITBIS1"] = Itbis1.ToString(),
        ["TotalITBIS"] = TotalItbis.ToString("F2"),
        ["TotalITBIS1"] = TotalItbis1.ToString("F2"),
        ["MontoTotal"] = MontoTotal.ToString("F2")
    };
}

/// <summary>Factura de Consumo (tipo 32). RFCE si MontoTotal &lt; 250_000.</summary>
public class FacturaConsumo32 : ComprobanteBase
{
    public override int TipoEcf => 32;

    public double MontoGravadoTotal { get; set; }
    public double MontoGravadoI1 { get; set; }
    public int Itbis1 { get; set; } = 18;
    public double TotalItbis { get; set; }
    public double TotalItbis1 { get; set; }
    public double MontoTotal { get; set; }
    protected override double GetMontoTotalVal() => MontoTotal;

    protected override Dictionary<string, object?> BuildIdDoc()
    {
        var d = base.BuildIdDoc();
        if (MontoTotal >= 250_000)
            d["FechaVencimientoSecuencia"] = Trim(FechaVencimientoSecuencia);
        d["IndicadorMontoGravado"] = IndicadorMontoGravado.ToString();
        return d;
    }

    protected override Dictionary<string, object?> BuildTotales() => new()
    {
        ["MontoGravadoTotal"] = MontoGravadoTotal.ToString("F2"),
        ["MontoGravadoI1"] = MontoGravadoI1.ToString("F2"),
        ["ITBIS1"] = Itbis1.ToString(),
        ["TotalITBIS"] = TotalItbis.ToString("F2"),
        ["TotalITBIS1"] = TotalItbis1.ToString("F2"),
        ["MontoTotal"] = MontoTotal.ToString("F2")
    };
}

/// <summary>Nota de Débito (tipo 33). Requiere InformacionReferencia.</summary>
public class NotaDebito33 : ComprobanteBase
{
    public override int TipoEcf => 33;
    private readonly InformacionReferencia _infoRef = new();

    public double MontoExento { get; set; }
    public double MontoTotal { get; set; }

    public InformacionReferencia InformacionReferencia => _infoRef;

    protected override Dictionary<string, object?> BuildIdDoc()
    {
        var d = base.BuildIdDoc();
        d["FechaVencimientoSecuencia"] = Trim(FechaVencimientoSecuencia);
        return d;
    }

    protected override Dictionary<string, object?> BuildTotales() => new()
    {
        ["MontoExento"] = MontoExento.ToString("F2"),
        ["MontoTotal"] = MontoTotal.ToString("F2")
    };

    protected override InformacionReferencia? BuildInformacionReferencia() => _infoRef;
}

/// <summary>Nota de Crédito (tipo 34). Requiere InformacionReferencia.</summary>
public class NotaCredito34 : ComprobanteBase
{
    public override int TipoEcf => 34;
    private readonly InformacionReferencia _infoRef = new();

    public double MontoExento { get; set; }
    public double MontoTotal { get; set; }

    public InformacionReferencia InformacionReferencia => _infoRef;

    protected override Dictionary<string, object?> BuildIdDoc()
    {
        var d = base.BuildIdDoc();
        d["FechaVencimientoSecuencia"] = Trim(FechaVencimientoSecuencia);
        return d;
    }

    protected override Dictionary<string, object?> BuildTotales() => new()
    {
        ["MontoExento"] = MontoExento.ToString("F2"),
        ["MontoTotal"] = MontoTotal.ToString("F2")
    };

    protected override InformacionReferencia? BuildInformacionReferencia() => _infoRef;
}
