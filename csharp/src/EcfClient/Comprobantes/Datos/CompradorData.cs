namespace EcfClient.Comprobantes.Datos;

/// <summary>Datos del comprador (Rnc o IdentificadorExtranjero, RazonSocial).</summary>
public class CompradorData
{
    public string Rnc { get; set; } = "";
    public string IdentificadorExtranjero { get; set; } = "";
    public string RazonSocial { get; set; } = "";
    public string Contacto { get; set; } = "";
    public string Correo { get; set; } = "";
    public string Direccion { get; set; } = "";
    public string Municipio { get; set; } = "";
    public string Provincia { get; set; } = "";
}
