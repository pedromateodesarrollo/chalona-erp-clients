// Driver C# v1 — validación mínima (espejo del v1 Dart).
// Solo verifica:
//   - tipo de comprobante (31, 32, 33, 34)
//   - fecha emisión formato dd-MM-yyyy

using System;
using System.Collections.Generic;
using ChalonaCsDriver;

namespace ChalonaCsDriver.DriverDinamico;

public sealed class DriverV1 : IComprobanteDriver
{
    public string Version => "v1";

    public (bool Ok, IReadOnlyList<string> Errores) PreValidar(IReadOnlyDictionary<string, object?> c)
    {
        var errores = new List<string>();
        var tipo = c.TryGetValue("tipo", out var t) ? t?.ToString() : null;
        var fecha = c.TryGetValue("fecha_emision", out var f) ? f?.ToString() : null;

        if (string.IsNullOrEmpty(tipo))
            errores.Add("tipo requerido");
        else if (tipo is not ("31" or "32" or "33" or "34"))
            errores.Add($"tipo inválido: {tipo} (debe ser 31, 32, 33 o 34)");

        if (string.IsNullOrEmpty(fecha))
            errores.Add("fecha_emision requerida");
        else if (!FechaValida(fecha))
            errores.Add($"fecha_emision inválida: \"{fecha}\" (esperado dd-MM-yyyy)");

        return (errores.Count == 0, errores);
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
}
