namespace ChalonaCsDriver;

/// Contrato del motor dinámico descargado desde el servidor.
/// El motor controla TODO el flujo de comunicación mediante trampolín:
/// recibe estado JSON, devuelve instrucción JSON (kind: http|done|fail).
///
/// Shell ↔ Motor protocol
///   Input  estadoJson: {"fnName","args","token","step","lastResp"}
///   Output stepJson:
///     {"kind":"http",  "step":N,"endpoint":"...","data":{...},"useToken":bool}
///     {"kind":"done",  "result":{...},           "newToken":"..."?}
///     {"kind":"fail",  "code":"...","data":{...}}
public interface IMotorEcf
{
    string Version { get; }
    string Procesar(string estadoJson);
}
