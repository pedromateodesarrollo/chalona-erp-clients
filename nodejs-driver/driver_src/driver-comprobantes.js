// Driver Node.js de prueba — pre-validación de comprobantes e-CF.
// Espejo de TypeScript driver-comprobantes.ts, C# DriverComprobantes.cs,
// Python driver_comprobantes.py, Fox driver_prueba_comprobantes_v2.prg.
// JS source UTF-8 publicado en data.nodejs_cliente_driver.
//
// El loader busca la primera clase exportada que cumpla el contrato:
//   - propiedad `version` (string)
//   - método `preValidar(comprobante) -> { ok, errores }`
//
// Asigna a __exports.default — el sandbox del loader lee de ahí.

class DriverV1 {
  constructor() {
    this.version = 'v1';
  }

  preValidar(c) {
    const errores = [];
    const tipo = c.tipo == null ? null : String(c.tipo);
    const fecha = c.fecha_emision == null ? null : String(c.fecha_emision);
    const rncEmi = c.rnc_emisor == null ? null : String(c.rnc_emisor);
    const rncCom = c.rnc_comprador == null ? null : String(c.rnc_comprador);
    const monto = num(c.monto_total);
    const totalFactura = num(c.total_factura_referenciada);
    const sumaNd = num(c.suma_nd_referenciadas);

    if (!tipo) errores.push('tipo requerido');
    else if (!['31', '32', '33', '34'].includes(tipo))
      errores.push('tipo inválido: ' + tipo + ' (debe ser 31, 32, 33 o 34)');

    if (!fecha) errores.push('fecha_emision requerida');
    else if (!fechaValida(fecha))
      errores.push('fecha_emision inválida: "' + fecha + '" (esperado dd-MM-yyyy)');

    if (!rncEmi) errores.push('rnc_emisor requerido');
    else if (!rncValido(rncEmi))
      errores.push('rnc_emisor inválido: "' + rncEmi + '" (9 u 11 dígitos)');

    if (monto === null) errores.push('monto_total requerido');
    else if (monto <= 0) errores.push('monto_total debe ser > 0 (actual: ' + monto + ')');

    if (tipo === '31') {
      if (!rncCom) errores.push('rnc_comprador requerido para tipo 31 (Crédito Fiscal)');
      else if (!rncValido(rncCom)) errores.push('rnc_comprador inválido: "' + rncCom + '"');
    }

    if (tipo === '32' && monto !== null && monto >= 250000)
      errores.push('tipo 32 con monto >= 250000 requiere comprador identificado (manual RFCE)');

    if (tipo === '34' && monto !== null) {
      const tf = totalFactura == null ? 0 : totalFactura;
      const sn = sumaNd == null ? 0 : sumaNd;
      const tope = tf + sn;
      if (monto > tope)
        errores.push('NC excede tope: monto ' + monto + ' > tope ' + tope + ' (factura=' + tf + ' + ND=' + sn + ')');
    }

    return { ok: errores.length === 0, errores: errores };
  }
}

function num(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'string') {
    const p = Number(v);
    return Number.isFinite(p) ? p : null;
  }
  return null;
}

function fechaValida(s) {
  const p = s.split('-');
  if (p.length !== 3) return false;
  const d = Number(p[0]);
  const m = Number(p[1]);
  const y = Number(p[2]);
  if (!Number.isInteger(d) || !Number.isInteger(m) || !Number.isInteger(y)) return false;
  if (m < 1 || m > 12) return false;
  if (d < 1 || d > 31) return false;
  if (y < 2020 || y > 2100) return false;
  return true;
}

function rncValido(rnc) {
  if (rnc.length !== 9 && rnc.length !== 11) return false;
  return /^\d+$/.test(rnc);
}

__exports.default = DriverV1;
