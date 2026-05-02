// CLI: compila driver_src/<nombre>.ts → JS source y lo escribe a stdout o archivo.
// Uso: node dist/bin/compilar.js <fuente.ts> [salida.js]

import * as fs from 'node:fs';
import * as crypto from 'node:crypto';
import { compilarDriver } from '../src/compiler.js';

const [, , fuente, salida] = process.argv;
if (!fuente) {
  console.error('Uso: compilar.js <fuente.ts> [salida.js]');
  process.exit(1);
}
if (!fs.existsSync(fuente)) {
  console.error(`No existe: ${fuente}`);
  process.exit(1);
}

const js = compilarDriver(fuente);
const hash = crypto.createHash('sha256').update(js, 'utf-8').digest('hex');

if (salida) {
  fs.writeFileSync(salida, js, 'utf-8');
  process.stderr.write(`compilado: ${js.length} bytes  sha256=${hash.slice(0, 12)}...\n`);
} else {
  process.stdout.write(js);
}
