#!/usr/bin/env node
// Demo end-to-end: descarga driver Node.js activo, lo carga en sandbox vm,
// corre batería de casos. Igual a fox/dart/cs/ts/python.
//
// Uso:
//   PG_HOST=localhost PG_PORT=5433 PG_DB=test PG_USER=pedro PG_PASS=camila \
//     ENTORNO=test node bin/prueba-comprobantes-driver.js

import { PostgresDriverSource } from '../src/postgres-source.js';
import { DriverHandle } from '../src/loader.js';
import { Buffer } from 'node:buffer';

const conn = {
  host: process.env.PG_HOST ?? 'localhost',
  port: Number(process.env.PG_PORT ?? '5432'),
  database: process.env.PG_DB ?? 'postgres',
  user: process.env.PG_USER ?? 'postgres',
  password: process.env.PG_PASS ?? 'postgres',
};
const entorno = process.env.ENTORNO ?? 'test';

const casos = [
  { nombre: 'tipo 31 OK',
    comprobante: { tipo: '31', fecha_emision: '15-01-2026', rnc_emisor: '131086268', rnc_comprador: '101000001', monto_total: 1000 },
    esperado_ok: true },
  { nombre: 'tipo 32 OK monto bajo',
    comprobante: { tipo: '32', fecha_emision: '15-01-2026', rnc_emisor: '131086268', monto_total: 5000 },
    esperado_ok: true },
  { nombre: 'tipo inválido',
    comprobante: { tipo: '99', fecha_emision: '15-01-2026', rnc_emisor: '131086268', monto_total: 100 },
    esperado_ok: false },
  { nombre: 'fecha inválida',
    comprobante: { tipo: '31', fecha_emision: '2026-01-15', rnc_emisor: '131086268', rnc_comprador: '101000001', monto_total: 100 },
    esperado_ok: false },
  { nombre: 'tipo 31 sin RNC comprador',
    comprobante: { tipo: '31', fecha_emision: '15-01-2026', rnc_emisor: '131086268', monto_total: 100 },
    esperado_ok: false },
  { nombre: 'tipo 32 manual RFCE excedido',
    comprobante: { tipo: '32', fecha_emision: '15-01-2026', rnc_emisor: '131086268', monto_total: 300000 },
    esperado_ok: false },
  { nombre: 'NC excede tope',
    comprobante: { tipo: '34', fecha_emision: '15-01-2026', rnc_emisor: '131086268', rnc_comprador: '101000001', monto_total: 5000, total_factura_referenciada: 1000, suma_nd_referenciadas: 500 },
    esperado_ok: false },
  { nombre: 'NC dentro de tope',
    comprobante: { tipo: '34', fecha_emision: '15-01-2026', rnc_emisor: '131086268', rnc_comprador: '101000001', monto_total: 1500, total_factura_referenciada: 1000, suma_nd_referenciadas: 500 },
    esperado_ok: true },
  { nombre: 'monto cero',
    comprobante: { tipo: '32', fecha_emision: '15-01-2026', rnc_emisor: '131086268', monto_total: 0 },
    esperado_ok: false },
];

async function main() {
  const src = new PostgresDriverSource(conn, entorno);
  console.log(`== Lookup driver Node.js @ ${entorno} (${conn.host}:${conn.port}/${conn.database})`);
  const meta = await src.lookup();
  if (!meta) {
    console.error(`No hay driver Node.js activo en ${entorno}`);
    process.exit(1);
  }
  console.log(`   activo: v${meta.version}  ${meta.tamano} bytes  sha256=${meta.hashSha256.slice(0, 12)}...`);

  const bytes = await src.descargar();
  const jsSource = Buffer.from(bytes).toString('utf-8');
  const handle = DriverHandle.cargar(jsSource, String(meta.version));
  console.log(`   cargado: instancia.version='${handle.instancia.version}'`);

  console.log(`\n== Casos:`);
  let pass = 0, fail = 0;
  for (const caso of casos) {
    const r = handle.instancia.preValidar(caso.comprobante);
    const ok = r.ok === caso.esperado_ok;
    const mark = ok ? 'OK  ' : 'FAIL';
    const detalle = caso.esperado_ok
      ? (r.ok ? '' : ` errores=${JSON.stringify(r.errores)}`)
      : (r.ok ? ' (esperaba fallo)' : ` errores=${JSON.stringify(r.errores)}`);
    console.log(`   [${mark}] ${caso.nombre}${detalle}`);
    if (ok) pass++; else fail++;
  }
  console.log(`\n${pass} pasaron, ${fail} fallaron`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
