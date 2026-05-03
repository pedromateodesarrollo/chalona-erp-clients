namespace EcfClient.Comprobantes.Datos;

/// <summary>Datos del emisor (obligatorios: Rnc, RazonSocial, Direccion, FechaEmision).</summary>
public class EmisorData
{
    public string Rnc { get; set; } = "";
    public string RazonSocial { get; set; } = "";
    public string Direccion { get; set; } = "";
    public string FechaEmision { get; set; } = "";
    public string NombreComercial { get; set; } = "";
    public string Municipio { get; set; } = "";
    public string Provincia { get; set; } = "";
    public IList<string> Telefonos { get; set; } = new List<string>();
    public string Correo { get; set; } = "";
}
