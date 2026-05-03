namespace ChalonaCsDriver;

/// <summary>
/// Contrato que el driver descargado debe implementar. La clase host invoca esta
/// interfaz vía reflexión sobre la instancia cargada desde el ensamblado dinámico.
///
/// El driver del lado servidor declara una clase pública (cualquier nombre) que
/// implemente esta interfaz. El loader busca el primer tipo que la implemente.
/// </summary>
public interface IComprobanteDriver
{
    /// <summary>Versión legible del driver — "v1", "v2", etc. Solo para logs.</summary>
    string Version { get; }

    /// <summary>
    /// Pre-valida un comprobante antes de enviarlo al servidor.
    /// Devuelve <c>(ok, errores)</c> donde errores es lista vacía si todo OK.
    /// </summary>
    (bool Ok, IReadOnlyList<string> Errores) PreValidar(IReadOnlyDictionary<string, object?> comprobante);
}
