// Lookup + descarga + publicación del driver Node.js desde data.nodejs_cliente_driver
// vía psql subprocess (sin deps de runtime — espejo del patrón typescript/python).

import { spawnSync } from 'node:child_process';
import { Buffer } from 'node:buffer';

export class PostgresDriverSource {
  constructor(conn, entorno) {
    if (entorno !== 'test' && entorno !== 'produccion') {
      throw new Error(`entorno inválido: ${entorno} (debe ser test|produccion)`);
    }
    this.conn = conn;
    this.entorno = entorno;
  }

  psql(sql) {
    const r = spawnSync(
      'psql',
      ['-h', this.conn.host, '-p', String(this.conn.port), '-U', this.conn.user,
        '-d', this.conn.database, '-v', 'ON_ERROR_STOP=1', '-t', '-A', '-X', '-q'],
      { input: sql, env: { ...process.env, PGPASSWORD: this.conn.password }, encoding: 'utf-8' },
    );
    if (r.status !== 0) throw new Error(`psql falló: ${r.stderr.trim()}`);
    return r.stdout.trim();
  }

  async lookup() {
    const sql = `SELECT (row_to_json(x.*))::text FROM (
      SELECT ok, message, data
      FROM fn.nodejs_cliente_driver_lookup(jsonb_build_object(
        'session', jsonb_build_object('trusted', true),
        'entorno', '${this.entorno}'
      ))
    ) x;`;
    const raw = this.psql(sql);
    const row = JSON.parse(raw);
    if (!row.ok) {
      if (row.message === 'nodejs_cliente_driver.no_disponible') return null;
      throw new Error(`lookup falló: ${row.message}`);
    }
    return {
      version: row.data.version,
      entorno: row.data.entorno,
      hashSha256: row.data.hash_sha256,
      tamano: row.data.tamano,
    };
  }

  async descargar(version) {
    const verLit = version === undefined ? "''" : `'${version}'`;
    const sql = `SELECT (row_to_json(x.*))::text FROM (
      SELECT ok, message, data
      FROM fn.nodejs_cliente_driver_descargar(jsonb_build_object(
        'session', jsonb_build_object('trusted', true),
        'entorno', '${this.entorno}',
        'version', ${verLit}
      ))
    ) x;`;
    const raw = this.psql(sql);
    const row = JSON.parse(raw);
    if (!row.ok) throw new Error(`descarga falló: ${row.message}`);
    return Buffer.from(row.data.bytes_b64, 'base64');
  }

  async publicar(bytes, hashSha256, notas) {
    const b64 = Buffer.from(bytes).toString('base64');
    const notasFrag = notas ? `, 'notas', '${notas.replace(/'/g, "''")}'` : '';
    const sql = `SELECT (row_to_json(x.*))::text FROM (
      SELECT ok, message, data
      FROM fn.nodejs_cliente_driver_publicar(jsonb_build_object(
        'session',     jsonb_build_object('trusted', true),
        'entorno',     '${this.entorno}',
        'hash_sha256', '${hashSha256}'
        ${notasFrag},
        'bytes_b64',   $CHALONA_BYTES$${b64}$CHALONA_BYTES$
      ))
    ) x;`;
    const raw = this.psql(sql);
    const row = JSON.parse(raw);
    if (!row.ok) throw new Error(`publicar falló: ${row.message}`);
    return { id: row.data.id, version: row.data.version };
  }
}
