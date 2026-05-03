namespace EcfClient.Comprobantes.Datos;

/// <summary>Referencia para notas de crédito/débito (tipos 33, 34).</summary>
public class InformacionReferencia
{
    public string NcfModificado { get; set; } = "";
    public string FechaNcfModificado { get; set; } = "";
    public string CodigoModificacion { get; set; } = ""; // "1","2","3","4"
}
