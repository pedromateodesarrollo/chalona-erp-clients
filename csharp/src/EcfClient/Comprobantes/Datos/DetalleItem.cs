namespace EcfClient.Comprobantes.Datos;

/// <summary>Una línea del detalle (obligatorios según tipo).</summary>
public class DetalleItem
{
    public int NumeroLinea { get; set; }
    public string NombreItem { get; set; } = "";
    public int IndicadorFacturacion { get; set; } = 1; // 0-4
    public int IndicadorBienServicio { get; set; } = 1; // 1=bien, 2=servicio
    public double Cantidad { get; set; }
    public double PrecioUnitario { get; set; }
    public double MontoItem { get; set; }
    public string UnidadMedida { get; set; } = "";
    public RetencionItem? Retencion { get; set; }
}
