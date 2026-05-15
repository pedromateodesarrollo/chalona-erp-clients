#!/usr/bin/env node
// Publica una versión nueva del driver Node.js (JS source UTF-8) en
// data.nodejs_cliente_driver. Sin compilación — el .js sube tal cual.
//
// Uso:
//   node bin/publicar.js                         # entorno=test, default driver_src/driver-comprobantes.js
//   node bin/publicar.js --produccion            # entorno=produccion
//   node bin/publicar.js --fuente=otro.js
//   PG_HOST=... PG_PASS=... node bin/publicar.js

import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { PostgresDriverSource } from '../src/postgres-source.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const driverDir = path.resolve(__dirname, '..');
const fuenteDefault = path.join(driverDir, 'driver_src', 'driver-comprobantes.js');

let entorno = 'test';
let fuente = '';
for (const arg of process.argv.slice(2)) {
  if (arg === '--produccion') entorno = 'produccion';
  else if (arg === '--test')  entorno = 'test';
  else if (arg.startsWith('--fuente=')) fuente = arg.slice('--fuente='.length);
  else if (arg === '-h' || arg === '--help') {
    console.log('Uso: node bin/publicar.js [--produccion|--test] [--fuente=<archivo.js>]');
    process.exit(0);
  } else {
    console.error(`arg desconocido: ${arg}`);
    process.exit(1);
  }
}
if (!fuente) fuente = fuenteDefault;
if (!fs.existsSync(fuente) && fs.existsSync(path.join(driverDir, fuente))) {
  fuente = path.join(driverDir, fuente);
}
if (!fs.existsSync(fuente)) {
  console.error(`ERROR: no se encontró ${fuente}`);
  process.exit(1);
}

const conn = {
  host: process.env.PG_HOST ?? 'localhost',
  port: Number(process.env.PG_PORT ?? '5432'),
  database: process.env.PG_DB ?? 'postgres',
  user: process.env.PG_USER ?? 'postgres',
  password: process.env.PG_PASS ?? 'postgres',
};

const bytes = fs.readFileSync(fuente);
const hash = crypto.createHash('sha256').update(bytes).digest('hex');
console.log(`== JS source: ${bytes.length} bytes  sha256=${hash.slice(0, 12)}...`);
console.log(`== Publicando → entorno='${entorno}' (BD ${conn.database} en ${conn.host}:${conn.port})`);

const src = new PostgresDriverSource(conn, entorno);
const r = await src.publicar(bytes, hash, process.env.NOTAS);
console.log(`   v${r.version} activo (id=${r.id})`);
