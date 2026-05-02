// Contrato que el driver descargado debe implementar.
// El loader busca la primera clase que lo implemente dentro del módulo cargado
// (export default o export named). Espejo de IComprobanteDriver (C#) y
// ComprobanteDriver (Dart).

export interface ComprobanteDriver {
  readonly version: string;
  preValidar(comprobante: Record<string, unknown>): { ok: boolean; errores: string[] };
}
