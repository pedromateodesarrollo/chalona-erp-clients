namespace EcfClient.Comprobantes;

/// <summary>Compras con retenciones (tipo 41).</summary>
public class Compras41 : ComprobanteBase
{
    public override int TipoEcf => 41;

    public double MontoGravadoTotal { get; set; }
    public double MontoGravadoI1 { get; set; }
    public int Itbis1 { get; set; } = 18;
    public double TotalItbis { get; set; }
    public double TotalItbis1 { get; set; }
    public double MontoTotal { get; set; }
    public double ValorPagar { get; set; }
    public double TotalItbisRetenido { get; set; }
    public double TotalIsrRetencion { get; set; }

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
        ["MontoTotal"] = MontoTotal.ToString("F2"),
        ["ValorPagar"] = ValorPagar.ToString("F2"),
        ["TotalITBISRetenido"] = TotalItbisRetenido.ToString("F2"),
        ["TotalISRRetencion"] = TotalIsrRetencion.ToString("F2")
    };
}

/// <summary>Gastos Menores (tipo 43). Sin comprador obligatorio, ítems exentos.</summary>
public class GastosMenores43 : ComprobanteBase
{
    public override int TipoEcf => 43;

    public double MontoExento { get; set; }
    public double MontoTotal { get; set; }

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
}

/// <summary>Régimen Especial (tipo 44). Comprador con IdentificadorExtranjero.</summary>
public class RegimenEspecial44 : ComprobanteBase
{
    public override int TipoEcf => 44;

    public double MontoExento { get; set; }
    public double MontoTotal { get; set; }
    public double ValorPagar { get; set; }

    protected override Dictionary<string, object?> BuildIdDoc()
    {
        var d = base.BuildIdDoc();
        d["FechaVencimientoSecuencia"] = Trim(FechaVencimientoSecuencia);
        return d;
    }

    protected override Dictionary<string, object?> BuildTotales() => new()
    {
        ["MontoExento"] = MontoExento.ToString("F2"),
        ["MontoTotal"] = MontoTotal.ToString("F2"),
        ["ValorPagar"] = ValorPagar.ToString("F2")
    };
}

/// <summary>Gubernamental (tipo 45).</summary>
public class Gubernamental45 : ComprobanteBase
{
    public override int TipoEcf => 45;

    public double MontoGravadoTotal { get; set; }
    public double MontoGravadoI1 { get; set; }
    public int Itbis1 { get; set; } = 18;
    public double TotalItbis { get; set; }
    public double TotalItbis1 { get; set; }
    public double MontoTotal { get; set; }
    public double ValorPagar { get; set; }

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
        ["MontoTotal"] = MontoTotal.ToString("F2"),
        ["ValorPagar"] = ValorPagar.ToString("F2")
    };
}

/// <summary>Exportación (tipo 46). IndicadorFacturacion 3 (ITBIS 0).</summary>
public class Exportacion46 : ComprobanteBase
{
    public override int TipoEcf => 46;

    public double MontoGravadoI3 { get; set; }
    public double TotalItbis3 { get; set; }
    public double MontoTotal { get; set; }

    protected override Dictionary<string, object?> BuildIdDoc()
    {
        var d = base.BuildIdDoc();
        d["FechaVencimientoSecuencia"] = Trim(FechaVencimientoSecuencia);
        return d;
    }

    protected override Dictionary<string, object?> BuildTotales() => new()
    {
        ["MontoGravadoTotal"] = MontoGravadoI3.ToString("F2"),
        ["MontoGravadoI3"] = MontoGravadoI3.ToString("F2"),
        ["ITBIS3"] = "0",
        ["TotalITBIS"] = "0.00",
        ["TotalITBIS3"] = TotalItbis3.ToString("F2"),
        ["MontoTotal"] = MontoTotal.ToString("F2")
    };
}

/// <summary>Pagos al Exterior (tipo 47). Comprador IdentificadorExtranjero, ítems servicio.</summary>
public class PagosExterior47 : ComprobanteBase
{
    public override int TipoEcf => 47;

    public double MontoExento { get; set; }
    public double MontoTotal { get; set; }
    public double TotalIsrRetencion { get; set; }

    protected override Dictionary<string, object?> BuildIdDoc()
    {
        var d = base.BuildIdDoc();
        d["FechaVencimientoSecuencia"] = Trim(FechaVencimientoSecuencia);
        return d;
    }

    protected override Dictionary<string, object?> BuildTotales() => new()
    {
        ["MontoExento"] = MontoExento.ToString("F2"),
        ["MontoTotal"] = MontoTotal.ToString("F2"),
        ["TotalISRRetencion"] = TotalIsrRetencion.ToString("F2")
    };
}
