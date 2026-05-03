using System.Text.RegularExpressions;
using EcfClient.Comprobantes.Datos;
using EcfClient.Exceptions;

namespace EcfClient.Comprobantes;

internal static class Validation
{
    private static readonly Regex FechaDdMmYyyy = new(@"^\d{2}-\d{2}-\d{4}$", RegexOptions.Compiled);

    private static bool IsFechaDdMmYyyy(string? s)
    {
        if (string.IsNullOrWhiteSpace(s) || !FechaDdMmYyyy.Match(s.Trim()).Success) return false;
        var parts = s.Trim().Split('-');
        if (parts.Length != 3) return false;
        if (!int.TryParse(parts[0], out var d) || !int.TryParse(parts[1], out var m) || !int.TryParse(parts[2], out var y))
            return false;
        return m >= 1 && m <= 12 && d >= 1 && d <= 31 && y >= 1900 && y <= 2100;
    }

    private static bool IsRncCedulaValid(string? val)
    {
        if (string.IsNullOrWhiteSpace(val)) return false;
        var digits = Regex.Replace(val, @"\D", "");
        return digits.Length is 9 or 11;
    }

    internal static void ValidarFecha(string path, string? valor, bool obligatorio = true)
    {
        if (string.IsNullOrWhiteSpace(valor))
        {
            if (obligatorio)
                throw new EcfValidationException($"Campo requerido: {path}", new[] { new ValidationError(path, "ecf.requerido") });
            return;
        }
        if (!IsFechaDdMmYyyy(valor))
            throw new EcfValidationException($"Formato fecha inválido (dd-MM-yyyy): {path}",
                new[] { new ValidationError(path, "ecf.formato_fecha", new Dictionary<string, object?> { ["valor"] = valor }) });
    }

    internal static void ValidarRnc(string path, string? valor, bool obligatorio = true)
    {
        if (string.IsNullOrWhiteSpace(valor))
        {
            if (obligatorio)
                throw new EcfValidationException($"Campo requerido: {path}", new[] { new ValidationError(path, "ecf.requerido") });
            return;
        }
        if (!IsRncCedulaValid(valor))
            throw new EcfValidationException($"RNC o cédula con formato inválido: {path}", new[] { new ValidationError(path, "ecf.formato_rnc") });
    }

    internal static void ValidarEncf(string? encf)
    {
        if (string.IsNullOrWhiteSpace(encf))
            throw new EcfValidationException("eNCF requerido", new[] { new ValidationError("Encabezado.IdDoc.eNCF", "ecf.requerido") });
        if (encf.Trim().Length > 13)
            throw new EcfValidationException("eNCF longitud máxima 13", new[] { new ValidationError("Encabezado.IdDoc.eNCF", "ecf.largo_maximo", new Dictionary<string, object?> { ["max"] = 13 }) });
    }

    internal static void ValidarEmisor(EmisorData emisor, bool exigirDireccion = true)
    {
        ValidarRnc("Encabezado.Emisor.RNCEmisor", emisor.Rnc);
        if (string.IsNullOrWhiteSpace(emisor.RazonSocial))
            throw new EcfValidationException("RazonSocialEmisor requerido", new[] { new ValidationError("Encabezado.Emisor.RazonSocialEmisor", "ecf.requerido") });
        if (emisor.RazonSocial.Trim().Length > 150)
            throw new EcfValidationException("RazonSocialEmisor máximo 150 caracteres", new[] { new ValidationError("Encabezado.Emisor.RazonSocialEmisor", "ecf.largo_maximo", new Dictionary<string, object?> { ["max"] = 150 }) });
        if (exigirDireccion && string.IsNullOrWhiteSpace(emisor.Direccion))
            throw new EcfValidationException("DireccionEmisor requerido", new[] { new ValidationError("Encabezado.Emisor.DireccionEmisor", "ecf.requerido") });
        if (!string.IsNullOrWhiteSpace(emisor.Direccion) && emisor.Direccion.Trim().Length > 100)
            throw new EcfValidationException("DireccionEmisor máximo 100 caracteres", new[] { new ValidationError("Encabezado.Emisor.DireccionEmisor", "ecf.largo_maximo", new Dictionary<string, object?> { ["max"] = 100 }) });
        ValidarFecha("Encabezado.Emisor.FechaEmision", emisor.FechaEmision);
    }

    internal static void ValidarComprador(CompradorData comprador, bool obligatorioComprador = true)
    {
        if (string.IsNullOrWhiteSpace(comprador.RazonSocial))
        {
            if (obligatorioComprador)
                throw new EcfValidationException("RazonSocialComprador requerido", new[] { new ValidationError("Encabezado.Comprador.RazonSocialComprador", "ecf.requerido") });
            return;
        }
        if (!string.IsNullOrWhiteSpace(comprador.Rnc) && !IsRncCedulaValid(comprador.Rnc))
            throw new EcfValidationException("RNCComprador formato inválido", new[] { new ValidationError("Encabezado.Comprador.RNCComprador", "ecf.formato_rnc") });
        var rncOk = (comprador.Rnc ?? "").Trim();
        var idExt = (comprador.IdentificadorExtranjero ?? "").Trim();
        if (!string.IsNullOrWhiteSpace(comprador.RazonSocial) && string.IsNullOrEmpty(rncOk) && string.IsNullOrEmpty(idExt))
            throw new EcfValidationException("RNC o IdentificadorExtranjero requerido cuando hay Comprador", new[] { new ValidationError("Encabezado.Comprador.RNCComprador", "ecf.requerido") });
    }

    internal static void ValidarItems(IList<DetalleItem> items, int tipoEcf)
    {
        if (items == null || items.Count == 0)
            throw new EcfValidationException("Al menos un ítem en DetallesItems", new[] { new ValidationError("DetallesItems", "ecf.detalle_al_menos_uno") });
        for (var i = 0; i < items.Count; i++)
        {
            var it = items[i];
            var prefix = $"DetallesItems[{i}]";
            if (it.NumeroLinea < 1 || it.NumeroLinea > 10000)
                throw new EcfValidationException($"NumeroLinea 1-10000: {prefix}", new[] { new ValidationError($"{prefix}.NumeroLinea", "ecf.rango_numero_linea") });
            if (string.IsNullOrWhiteSpace(it.NombreItem))
                throw new EcfValidationException($"NombreItem requerido: {prefix}", new[] { new ValidationError($"{prefix}.NombreItem", "ecf.requerido") });
            if (it.NombreItem.Trim().Length > 80)
                throw new EcfValidationException($"NombreItem máximo 80: {prefix}", new[] { new ValidationError($"{prefix}.NombreItem", "ecf.largo_maximo") });
            if (it.IndicadorFacturacion < 0 || it.IndicadorFacturacion > 4)
                throw new EcfValidationException($"IndicadorFacturacion 0-4: {prefix}", new[] { new ValidationError($"{prefix}.IndicadorFacturacion", "ecf.valor_no_permitido") });
            if (tipoEcf is 43 or 44 or 47 && it.IndicadorFacturacion != 4)
                throw new EcfValidationException($"Tipo {tipoEcf} requiere IndicadorFacturacion 4: {prefix}", new[] { new ValidationError($"{prefix}.IndicadorFacturacion", "ecf.indicador_facturacion_tipo_ecf") });
            if (tipoEcf == 46 && it.IndicadorFacturacion != 3)
                throw new EcfValidationException("Tipo 46 requiere IndicadorFacturacion 3: " + prefix, new[] { new ValidationError($"{prefix}.IndicadorFacturacion", "ecf.indicador_facturacion_tipo_ecf") });
            if (it.IndicadorBienServicio is not 1 and not 2)
                throw new EcfValidationException($"IndicadorBienoServicio 1 o 2: {prefix}", new[] { new ValidationError($"{prefix}.IndicadorBienoServicio", "ecf.valor_no_permitido") });
            if (tipoEcf == 47 && it.IndicadorBienServicio != 2)
                throw new EcfValidationException("Tipo 47 requiere IndicadorBienoServicio 2: " + prefix, new[] { new ValidationError($"{prefix}.IndicadorBienoServicio", "ecf.indicador_bien_servicio_tipo_47") });
            if (it.Cantidad <= 0)
                throw new EcfValidationException($"CantidadItem > 0: {prefix}", new[] { new ValidationError($"{prefix}.CantidadItem", "ecf.mayor_cero") });
            if (it.PrecioUnitario < 0 || it.MontoItem < 0)
                throw new EcfValidationException($"PrecioUnitario/MontoItem no negativos: {prefix}", new[] { new ValidationError($"{prefix}.MontoItem", "ecf.valor_no_negativo") });
        }
    }

    internal static void ValidarInformacionReferencia(InformacionReferencia info)
    {
        if (string.IsNullOrWhiteSpace(info.NcfModificado))
            throw new EcfValidationException("NCFModificado requerido para tipo 33/34", new[] { new ValidationError("InformacionReferencia.NCFModificado", "ecf.requerido") });
        ValidarFecha("InformacionReferencia.FechaNCFModificado", info.FechaNcfModificado);
        var cod = (info.CodigoModificacion ?? "").Trim();
        if (string.IsNullOrEmpty(cod) || (cod != "1" && cod != "2" && cod != "3" && cod != "4"))
            throw new EcfValidationException("CodigoModificacion debe ser 1, 2, 3 o 4", new[] { new ValidationError("InformacionReferencia.CodigoModificacion", "ecf.valor_no_permitido") });
    }
}
