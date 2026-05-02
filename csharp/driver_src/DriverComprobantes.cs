// Driver C# de prueba — pre-validación de comprobantes e-CF.
// Espejo del driver_prueba_comprobantes_v2.dart pero en C# completo, sin
// limitaciones de subset.
//
// Esta fuente .cs se compila a un ensamblado .dll (bytes IL) vía Roslyn,
// se publica en data.cs_cliente_driver, y el cliente C# lo descarga y
// carga vía AssemblyLoadContext.

using System;
using System.Collections.Generic;
using System.Globalization;
using ChalonaCsDriver;

namespace ChalonaCsDriver.DriverDinamico;

public sealed class DriverV2 : IComprobanteDriver
{
    public string Version => "v2";

    public (bool Ok, IReadOnlyList<string> Errores) PreValidar(IReadOnlyDictionary<string, object?> c)
    {
        var errores = new List<string>();

        var tipo = c.TryGetValue("tipo", out var t) ? t?.ToString() : null;
        var fecha = c.TryGetValue("fecha_emision", out var f) ? f?.ToString() : null;
        var rncEmi = c.TryGetValue("rnc_emisor", out var re) ? re?.ToString() : null;
        var rncCom = c.TryGetValue("rnc_comprador", out var rc) ? rc?.ToString() : null;
        var monto = TryNum(c, "monto_total");
        var totalFactura = TryNum(c, "total_factura_referenciada");
        var sumaNd = TryNum(c, "suma_nd_referenciadas");

        // tipo
        if (string.IsNullOrEmpty(tipo))
            errores.Add("tipo requerido");
        else if (tipo is not ("31" or "32" or "33" or "34"))
            errores.Add($"tipo inválido: {tipo} (debe ser 31, 32, 33 o 34)");

        // fecha
        if (string.IsNullOrEmpty(fecha))
            errores.Add("fecha_emision requerida");
        else if (!FechaValida(fecha))
            errores.Add($"fecha_emision inválida: \"{fecha}\" (esperado dd-MM-yyyy)");

        // RNC emisor
        if (string.IsNullOrEmpty(rncEmi))
            errores.Add("rnc_emisor requerido");
        else if (!RncValido(rncEmi))
            errores.Add($"rnc_emisor inválido: \"{rncEmi}\" (9 u 11 dígitos)");

        // monto
        if (monto is null)
            errores.Add("monto_total requerido");
        else if (monto <= 0)
            errores.Add($"monto_total debe ser > 0 (actual: {monto})");

        // tipo 31: requiere RNC comprador
        if (tipo == "31")
        {
            if (string.IsNullOrEmpty(rncCom))
                errores.Add("rnc_comprador requerido para tipo 31 (Crédito Fiscal)");
            else if (!RncValido(rncCom))
                errores.Add($"rnc_comprador inválido: \"{rncCom}\"");
        }

        // tipo 32 manual RFCE: monto < 250000
        if (tipo == "32" && monto is decimal m32 && m32 >= 250000)
            errores.Add("tipo 32 con monto >= 250000 requiere comprador identificado (manual RFCE)");

        // tipo 34 (NC): tope = total_factura + suma_nd
        if (tipo == "34" && monto is decimal m34)
        {
            var tf = totalFactura ?? 0;
            var sn = sumaNd ?? 0;
            var tope = tf + sn;
            if (m34 > tope)
                errores.Add($"NC excede tope: monto {m34} > tope {tope} (factura={tf} + ND={sn})");
        }

        return (errores.Count == 0, errores);
    }

    private static decimal? TryNum(IReadOnlyDictionary<string, object?> d, string k)
    {
        if (!d.TryGetValue(k, out var v) || v is null) return null;
        return v switch
        {
            decimal m => m,
            double dd => (decimal)dd,
            float ff => (decimal)ff,
            int i => i,
            long l => l,
            string s when decimal.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var p) => p,
            _ => null,
        };
    }

    private static bool FechaValida(string s)
    {
        var p = s.Split('-');
        if (p.Length != 3) return false;
        if (!int.TryParse(p[0], out var d)) return false;
        if (!int.TryParse(p[1], out var m)) return false;
        if (!int.TryParse(p[2], out var y)) return false;
        if (m < 1 || m > 12) return false;
        if (d < 1 || d > 31) return false;
        if (y < 2020 || y > 2100) return false;
        return true;
    }

    private static bool RncValido(string rnc)
    {
        if (rnc.Length != 9 && rnc.Length != 11) return false;
        foreach (var ch in rnc)
            if (ch < '0' || ch > '9') return false;
        return true;
    }
}
