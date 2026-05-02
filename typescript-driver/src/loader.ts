// Carga JS source descargado desde Postgres y devuelve instancia del driver.
// Usa node:vm con sandbox controlado: el driver NO tiene acceso a require, fs,
// ni globals de Node. Solo a console y APIs JS estándar.
//
// Diferencia con C# (AssemblyLoadContext): aquí no hay Unload real — V8 retiene
// los Script compilados hasta GC. Para hot-swap, descartar el handle y dejar
// que GC libere.

import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as vm from 'node:vm';
import type { ComprobanteDriver } from './contract.js';

export class DriverHandle {
  constructor(
    public readonly version: string,
    public readonly hashSha256: string,
    public readonly instancia: ComprobanteDriver,
  ) {}

  static cargar(jsSource: string, version: string): DriverHandle {
    const hash = crypto.createHash('sha256').update(jsSource, 'utf-8').digest('hex');

    // Sandbox mínimo: console + JSON + Math + Date (puros). Sin require, fs, etc.
    const sandbox: Record<string, unknown> = {
      console,
      JSON,
      Math,
      Date,
      Number,
      String,
      Boolean,
      Array,
      Object,
      RegExp,
      Map,
      Set,
      Error,
      __exports: {} as Record<string, unknown>,
    };
    vm.createContext(sandbox);

    // El driver compilado debe asignar la clase a __exports.default o
    // __exports.<NombreClase>. tsc emite ESM/CommonJS — el compilar.ts lo
    // envuelve para que use __exports.
    const script = new vm.Script(jsSource, { filename: `driver-${version}.js` });
    script.runInContext(sandbox, { timeout: 5000 });

    const exports = sandbox.__exports as Record<string, unknown>;
    const candidato = (exports.default ?? Object.values(exports).find((v) => typeof v === 'function')) as
      | (new () => ComprobanteDriver)
      | undefined;
    if (!candidato) {
      throw new Error('No se encontró clase exportada que implemente ComprobanteDriver');
    }
    const inst = new candidato();
    if (typeof inst.preValidar !== 'function' || typeof inst.version !== 'string') {
      throw new Error('La clase cargada no implementa ComprobanteDriver (falta preValidar o version)');
    }
    return new DriverHandle(version, hash, inst);
  }
}

export class DriverCache {
  constructor(public readonly directorio: string) {
    fs.mkdirSync(directorio, { recursive: true });
  }
  private archivo(v: string): string { return path.join(this.directorio, `driver-${v}.js`); }
  tiene(v: string): boolean { return fs.existsSync(this.archivo(v)); }
  leer(v: string): string { return fs.readFileSync(this.archivo(v), 'utf-8'); }
  guardar(v: string, src: string): void { fs.writeFileSync(this.archivo(v), src, 'utf-8'); }
}
