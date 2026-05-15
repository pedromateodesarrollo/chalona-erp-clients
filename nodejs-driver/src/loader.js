// Loader: carga JS source descargado desde Postgres y devuelve instancia del driver.
//
// Usa node:vm con sandbox controlado (sin require, fs, ni globals de Node).
// El driver debe asignarse a __exports.default o a alguna propiedad de __exports
// como función/clase constructora. Mirror del loader TS pero sin transpile —
// el JS sube tal cual, igual que Fox sube .prg interpretado.

import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as vm from 'node:vm';

export class DriverHandle {
  constructor(version, hashSha256, instancia) {
    this.version = version;
    this.hashSha256 = hashSha256;
    this.instancia = instancia;
  }

  static cargar(jsSource, version) {
    const hash = crypto.createHash('sha256').update(jsSource, 'utf-8').digest('hex');

    const sandbox = {
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
      __exports: {},
    };
    vm.createContext(sandbox);

    const script = new vm.Script(jsSource, { filename: `nodejs-driver-${version}.js` });
    script.runInContext(sandbox, { timeout: 5000 });

    const exports = sandbox.__exports;
    const candidato = exports.default ?? Object.values(exports).find((v) => typeof v === 'function');
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
  constructor(directorio) {
    this.directorio = directorio;
    fs.mkdirSync(directorio, { recursive: true });
  }
  archivo(v) { return path.join(this.directorio, `driver-${v}.js`); }
  tiene(v) { return fs.existsSync(this.archivo(v)); }
  leer(v) { return fs.readFileSync(this.archivo(v), 'utf-8'); }
  guardar(v, src) { fs.writeFileSync(this.archivo(v), src, 'utf-8'); }
}
