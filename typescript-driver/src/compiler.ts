// Compila TypeScript fuente del driver a JS source ejecutable en sandbox vm.
// Estrategia: tsc transpile-only → CommonJS, luego envolver en IIFE que asigna
// la clase exportada a __exports (la global del sandbox).

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

function resolverTsc(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  // dist/src/compiler.js → dist → typescript-driver → node_modules/.bin/tsc
  const candidatos = [
    path.resolve(here, '../../node_modules/.bin/tsc'),
    path.resolve(here, '../../../node_modules/.bin/tsc'),
  ];
  for (const c of candidatos) if (fs.existsSync(c)) return c;
  return 'tsc';
}

export function compilarDriver(fuenteTs: string): string {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chalona-ts-driver-'));
  try {
    const inFile = path.join(tmpDir, 'driver.ts');
    const outFile = path.join(tmpDir, 'driver.js');
    fs.writeFileSync(inFile, fs.readFileSync(fuenteTs, 'utf-8'), 'utf-8');

    const r = spawnSync(resolverTsc(), [
      '--target', 'ES2022',
      '--module', 'commonjs',
      '--moduleResolution', 'node',
      '--strict',
      '--esModuleInterop',
      '--skipLibCheck',
      '--removeComments',
      '--outDir', tmpDir,
      inFile,
    ], { encoding: 'utf-8' });
    if (r.status !== 0) {
      throw new Error(`tsc falló:\n${r.stdout}\n${r.stderr}`);
    }

    const js = fs.readFileSync(outFile, 'utf-8');
    // Envolver: el JS compilado por tsc usa "exports" y "module.exports".
    // En el sandbox vm, definimos exports y module locales y al final volcamos
    // exports a __exports (la global accesible desde el loader).
    return [
      '(function () {',
      '  var module = { exports: {} };',
      '  var exports = module.exports;',
      js,
      '  for (var k in module.exports) { __exports[k] = module.exports[k]; }',
      '  if (module.exports.default !== undefined) { __exports.default = module.exports.default; }',
      '})();',
    ].join('\n');
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}
