// Motor C# v1 — puerto de motor_v1.dart (Dart client).
//
// Controla TODA la lógica de comunicación con ecf-service via trampolín.
// El shell (EcfClient) descarga este DLL, lo carga en memoria y delega
// cada operación a Procesar(estadoJson).
//
// Para añadir o modificar flujos: editar este archivo, publicar nueva versión
// (publicar.sh) y los clientes la bajan automáticamente en el próximo arranque.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using ChalonaCsDriver;

public sealed class MotorEcfV1 : IMotorEcf
{
    public string Version => "v1";

    public string Procesar(string estadoJson)
    {
        try
        {
            using var doc = JsonDocument.Parse(estadoJson);
            var root = doc.RootElement;
            var fnName = Str(root, "fnName");
            var args = root.TryGetProperty("args", out var a) ? a : default;
            var step = root.TryGetProperty("step", out var s) && s.ValueKind == JsonValueKind.Number
                ? s.GetInt32() : 0;
            JsonElement? lastResp = root.TryGetProperty("lastResp", out var lr) &&
                lr.ValueKind != JsonValueKind.Null ? lr : null;

            return fnName switch
            {
                "login" => FlowLogin(args, step, lastResp),
                "enviaEcf" => FlowEnviaEcf(args, step, lastResp),
                "enviaEcfDesdeDoc" => FlowEnviaEcfDesdeDoc(args, step, lastResp),
                "consultaEstado" => FlowConsultaEstado(args, step, lastResp),
                "descargaXmls" => FlowDescargaXmls(args, step, lastResp),
                _ => Fail("motor.fn_desconocida", new JsonObject { ["fnName"] = fnName }),
            };
        }
        catch (Exception ex)
        {
            return Fail("motor.error_interno", new JsonObject { ["detail"] = ex.Message });
        }
    }

    // ---------------------------------------------------------------------------
    // Login
    // ---------------------------------------------------------------------------
    private static string FlowLogin(JsonElement args, int step, JsonElement? lastResp)
    {
        if (step == 0)
        {
            var usuario = Str(args, "usuario").Trim();
            var clave = Str(args, "clave");
            var app = Str(args, "app").Trim();
            if (app.Length == 0) app = "ecf";
            if (usuario.Length == 0) return Fail("motor.login.usuario_requerido");
            if (clave.Length == 0) return Fail("motor.login.clave_requerida");
            return Http("sistema_login", new JsonObject
            {
                ["app"] = app,
                ["usuario"] = usuario,
                ["clave"] = clave,
            }, useToken: false, nextStep: 1);
        }
        var data = RespData(lastResp);
        var token = Str(data, "token");
        return Done(data, newToken: token.Length > 0 ? token : null);
    }

    // ---------------------------------------------------------------------------
    // Envía e-CF (payload DGII ya construido)
    // ---------------------------------------------------------------------------
    private static string FlowEnviaEcf(JsonElement args, int step, JsonElement? lastResp)
    {
        if (step == 0)
        {
            var rnc = Str(args, "rnc").Trim();
            var portal = Str(args, "portal").Trim();
            if (rnc.Length == 0) return Fail("motor.envia_ecf.rnc_requerido");
            if (portal != "ecf" && portal != "testecf")
                return Fail("motor.envia_ecf.portal_invalido", new JsonObject { ["portal"] = portal });
            if (!args.TryGetProperty("json", out var jsonEl) || jsonEl.ValueKind != JsonValueKind.Object)
                return Fail("motor.envia_ecf.json_requerido");
            return Http("envia_ecf", new JsonObject
            {
                ["rnc"] = rnc,
                ["portal"] = portal,
                ["json"] = JsonNode.Parse(jsonEl.GetRawText()),
            }, useToken: true, nextStep: 1);
        }
        return Done(RespData(lastResp));
    }

    // ---------------------------------------------------------------------------
    // Envía e-CF desde DocumentoEcf (formato cursores Fox)
    // ---------------------------------------------------------------------------
    private static string FlowEnviaEcfDesdeDoc(JsonElement args, int step, JsonElement? lastResp)
    {
        if (step == 0)
        {
            if (!args.TryGetProperty("documento", out var docEl) || docEl.ValueKind != JsonValueKind.Object)
                return Fail("motor.envia_doc.documento_requerido");
            var portal = Str(args, "portal").Trim();
            if (portal != "ecf" && portal != "testecf")
                return Fail("motor.envia_doc.portal_invalido", new JsonObject { ["portal"] = portal });

            var fiscal = Str(docEl, "fiscal").Trim();
            if (fiscal.Length == 0) return Fail("motor.envia_doc.fiscal_requerido");
            if (fiscal is not ("31" or "32" or "33" or "34"))
                return Fail("motor.envia_doc.tipo_no_soportado_aun", new JsonObject { ["fiscal"] = fiscal });

            if (!docEl.TryGetProperty("emisor", out var emisorEl) || emisorEl.ValueKind != JsonValueKind.Object)
                return Fail("motor.envia_doc.emisor_requerido");
            var emisorRnc = Str(emisorEl, "rnc").Trim();
            if (emisorRnc.Length == 0) return Fail("motor.envia_doc.emisor_rnc_requerido");

            var tieneComprador = docEl.TryGetProperty("comprador", out var compradorEl)
                && compradorEl.ValueKind == JsonValueKind.Object;
            if (fiscal == "31" && !tieneComprador)
                return Fail("motor.envia_doc.comprador_requerido_31");

            if (!docEl.TryGetProperty("lineas", out var lineasEl) || lineasEl.ValueKind != JsonValueKind.Array)
                return Fail("motor.envia_doc.sin_lineas");
            var lineasArr = lineasEl.EnumerateArray().ToList();
            if (lineasArr.Count == 0) return Fail("motor.envia_doc.sin_lineas");

            // Construir payload DGII
            var fechaEmision = Str(docEl, "fecha");
            var encf = Str(docEl, "encf");
            var moneda = Str(docEl, "moneda", "DOP");
            var tasa = NumEl(docEl, "tasa", 1);

            var detallesItems = new JsonArray();
            var nLinea = 1;
            foreach (var lineaEl in lineasArr)
            {
                var cantidad = NumEl(lineaEl, "cantidad", 0);
                var precio = NumEl(lineaEl, "precio", 0);
                var monto = cantidad * precio;
                var esServicio = (int)NumEl(lineaEl, "mercs_servicio", 1) == 2;
                var itbisLinea = NumEl(lineaEl, "itbis", 0);
                var indFact = itbisLinea > 0 ? "1" : "4";
                detallesItems.Add(new JsonObject
                {
                    ["NumeroLinea"] = nLinea.ToString(),
                    ["IndicadorFacturacion"] = indFact,
                    ["NombreItem"] = Str(lineaEl, "descrip"),
                    ["IndicadorBienoServicio"] = esServicio ? "2" : "1",
                    ["CantidadItem"] = Fmt4(cantidad),
                    ["PrecioUnitarioItem"] = Fmt2(precio),
                    ["MontoItem"] = Fmt2(monto),
                });
                nLinea++;
            }

            var fechaVenceSec = Str(docEl, "vence_fiscal").Trim();
            if (fechaVenceSec.Length == 0) fechaVenceSec = "31-12-2099";

            var idDoc = new JsonObject
            {
                ["TipoeCF"] = fiscal,
                ["eNCF"] = encf,
                ["FechaVencimientoSecuencia"] = fechaVenceSec,
                ["IndicadorMontoGravado"] = "0",
            };
            if (fiscal == "31")
            {
                idDoc["TipoIngresos"] = "01";
                idDoc["TipoPago"] = "1";
            }

            var emisorMap = new JsonObject
            {
                ["RNCEmisor"] = emisorRnc,
                ["RazonSocialEmisor"] = Str(emisorEl, "nombre"),
                ["FechaEmision"] = fechaEmision,
            };
            var emisorDir = Str(emisorEl, "nombre");
            var emisorDirVal = Str(emisorEl, "direccion");
            if (emisorDirVal.Length > 0) emisorMap["DireccionEmisor"] = emisorDirVal;

            var encabezado = new JsonObject
            {
                ["Version"] = "1.0",
                ["IdDoc"] = idDoc,
                ["Emisor"] = emisorMap,
            };

            if (tieneComprador)
            {
                var compMap = new JsonObject();
                var compRnc = Str(compradorEl, "rnc").Trim();
                if (compRnc.Length > 0) compMap["RNCComprador"] = compRnc;
                compMap["RazonSocialComprador"] = Str(compradorEl, "nombre");
                encabezado["Comprador"] = compMap;
            }

            var totalDoc = NumEl(docEl, "total", 0);
            var itbisDoc = NumEl(docEl, "itbis", 0);
            var valorDoc = NumEl(docEl, "valor", 0);
            var montoGravado = valorDoc > 0 ? valorDoc : (totalDoc - itbisDoc);
            encabezado["Totales"] = new JsonObject
            {
                ["MontoGravadoTotal"] = Fmt2(montoGravado),
                ["MontoGravadoI1"] = Fmt2(montoGravado),
                ["ITBIS1"] = "18",
                ["TotalITBIS"] = Fmt2(itbisDoc),
                ["TotalITBIS1"] = Fmt2(itbisDoc),
                ["MontoTotal"] = Fmt2(totalDoc),
            };

            if (moneda != "DOP")
            {
                encabezado["OtraMoneda"] = new JsonObject
                {
                    ["TipoMoneda"] = moneda,
                    ["TipoCambio"] = Fmt4(tasa),
                };
            }

            var payload = new JsonObject
            {
                ["Encabezado"] = encabezado,
                ["DetallesItems"] = detallesItems,
            };

            return Http("envia_ecf", new JsonObject
            {
                ["rnc"] = emisorRnc,
                ["portal"] = portal,
                ["json"] = payload,
            }, useToken: true, nextStep: 1);
        }

        var dataApi = RespData(lastResp);
        var out_ = new JsonObject();
        CopyStr(dataApi, out_, "estado");
        CopyStr(dataApi, out_, "estado_descripcion");
        CopyStr(dataApi, out_, "codigo_seguridad");
        CopyStr(dataApi, out_, "fecha_firma");
        CopyStr(dataApi, out_, "timbre");
        CopyAny(dataApi, out_, "secuencia_utilizada");
        // encf viene como "numero" en la respuesta del servidor
        if (dataApi.TryGetProperty("numero", out var num)) out_["encf"] = num.ValueKind == JsonValueKind.String ? num.GetString() : null;
        CopyAny(dataApi, out_, "id");
        CopyStr(dataApi, out_, "track_id");
        CopyAny(dataApi, out_, "tipo");
        CopyAny(dataApi, out_, "total");
        CopyStr(dataApi, out_, "fecha");
        return Done(out_);
    }

    // ---------------------------------------------------------------------------
    // Consulta estado
    // ---------------------------------------------------------------------------
    private static string FlowConsultaEstado(JsonElement args, int step, JsonElement? lastResp)
    {
        if (step == 0)
        {
            if (!args.TryGetProperty("comprobantes", out var lista) || lista.ValueKind != JsonValueKind.Array)
                return Fail("motor.consulta_estado.comprobantes_requeridos");
            var count = lista.GetArrayLength();
            if (count > 100)
                return Fail("motor.consulta_estado.maximo_100", new JsonObject { ["recibidos"] = count });
            return Http("consulta_estado",
                new JsonObject { ["comprobantes"] = JsonNode.Parse(lista.GetRawText()) },
                useToken: true, nextStep: 1);
        }
        return Done(RespData(lastResp));
    }

    // ---------------------------------------------------------------------------
    // Descarga XMLs
    // ---------------------------------------------------------------------------
    private static string FlowDescargaXmls(JsonElement args, int step, JsonElement? lastResp)
    {
        if (step == 0)
        {
            var fechaDesde = Str(args, "fecha_desde").Trim();
            var fechaHasta = Str(args, "fecha_hasta").Trim();
            if (!IsFechaYyyyMmDd(fechaDesde))
                return Fail("motor.descarga_xmls.fecha_desde_invalida", new JsonObject { ["valor"] = fechaDesde });
            if (!IsFechaYyyyMmDd(fechaHasta))
                return Fail("motor.descarga_xmls.fecha_hasta_invalida", new JsonObject { ["valor"] = fechaHasta });
            var data = new JsonObject
            {
                ["fecha_desde"] = fechaDesde,
                ["fecha_hasta"] = fechaHasta,
            };
            if (args.TryGetProperty("tipos", out var tipos) && tipos.ValueKind == JsonValueKind.Array && tipos.GetArrayLength() > 0)
                data["tipos"] = JsonNode.Parse(tipos.GetRawText());
            return Http("ecf_documentos_list", data, useToken: true, nextStep: 1);
        }
        return Done(RespData(lastResp));
    }

    // ---------------------------------------------------------------------------
    // Helpers de protocolo
    // ---------------------------------------------------------------------------
    private static string Http(string endpoint, JsonObject data, bool useToken, int nextStep)
        => new JsonObject
        {
            ["kind"] = "http",
            ["step"] = nextStep,
            ["endpoint"] = endpoint,
            ["data"] = data,
            ["useToken"] = useToken,
        }.ToJsonString();

    private static string Done(JsonElement data, string? newToken = null)
    {
        var o = new JsonObject { ["kind"] = "done" };
        var result = JsonNode.Parse(data.GetRawText());
        o["result"] = result;
        if (!string.IsNullOrEmpty(newToken)) o["newToken"] = newToken;
        return o.ToJsonString();
    }

    private static string Done(JsonObject result, string? newToken = null)
    {
        var o = new JsonObject { ["kind"] = "done", ["result"] = result };
        if (!string.IsNullOrEmpty(newToken)) o["newToken"] = newToken;
        return o.ToJsonString();
    }

    private static string Fail(string code, JsonObject? data = null)
        => new JsonObject
        {
            ["kind"] = "fail",
            ["code"] = code,
            ["data"] = data ?? new JsonObject(),
        }.ToJsonString();

    // ---------------------------------------------------------------------------
    // Helpers de lectura
    // ---------------------------------------------------------------------------
    private static JsonElement RespData(JsonElement? lastResp)
    {
        if (lastResp is null) return default;
        if (lastResp.Value.ValueKind != JsonValueKind.Object) return default;
        return lastResp.Value.TryGetProperty("data", out var d) ? d : default;
    }

    private static string Str(JsonElement m, string key, string def = "")
    {
        if (m.ValueKind != JsonValueKind.Object) return def;
        if (!m.TryGetProperty(key, out var v)) return def;
        return v.ValueKind switch
        {
            JsonValueKind.String => v.GetString() ?? def,
            JsonValueKind.Null => def,
            _ => v.ToString(),
        };
    }

    private static double NumEl(JsonElement m, string key, double def = 0)
    {
        if (m.ValueKind != JsonValueKind.Object) return def;
        if (!m.TryGetProperty(key, out var v)) return def;
        return v.ValueKind == JsonValueKind.Number ? v.GetDouble() : def;
    }

    private static void CopyStr(JsonElement src, JsonObject dst, string key)
    {
        if (src.ValueKind == JsonValueKind.Object && src.TryGetProperty(key, out var v))
            dst[key] = v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    }

    private static void CopyAny(JsonElement src, JsonObject dst, string key)
    {
        if (src.ValueKind == JsonValueKind.Object && src.TryGetProperty(key, out var v))
            dst[key] = JsonNode.Parse(v.GetRawText());
    }

    private static string Fmt2(double v)
    {
        var rounded = (long)Math.Round(v * 100, MidpointRounding.AwayFromZero);
        var neg = rounded < 0;
        var abs = neg ? -rounded : rounded;
        return (neg ? "-" : "") + $"{abs / 100}.{abs % 100:D2}";
    }

    private static string Fmt4(double v)
    {
        var rounded = (long)Math.Round(v * 10000, MidpointRounding.AwayFromZero);
        var neg = rounded < 0;
        var abs = neg ? -rounded : rounded;
        return (neg ? "-" : "") + $"{abs / 10000}.{abs % 10000:D4}";
    }

    private static bool IsFechaYyyyMmDd(string s)
    {
        if (s.Length != 10 || s[4] != '-' || s[7] != '-') return false;
        return int.TryParse(s[..4], out var y) && int.TryParse(s[5..7], out var m)
            && int.TryParse(s[8..10], out var d)
            && y >= 2020 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31;
    }
}
