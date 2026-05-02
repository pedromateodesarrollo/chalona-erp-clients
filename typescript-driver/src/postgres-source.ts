// Lookup + descarga del driver TypeScript desde data.ts_cliente_driver via psql.
// Usa subprocess (sin dep node-postgres) — espejo del patrón de actualiza-cliente-*.

import { spawnSync } from 'node:child_process';

export interface DriverMeta {
  version: number;
  entorno: string;
  hashSha256: string;
  tamano: number;
}

export interface PgConn {
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
}

export class PostgresDriverSource {
  constructor(
    private readonly conn: PgConn,
    public readonly entorno: 'test' | 'produccion',
  ) {
    if (entorno !== 'test' && entorno !== 'produccion') {
      throw new Error(`entorno inválido: ${entorno} (debe ser test|produccion)`);
    }
  }

  private psql(sql: string): string {
    const r = spawnSync(
      'psql',
      ['-h', this.conn.host, '-p', String(this.conn.port), '-U', this.conn.user,
        '-d', this.conn.database, '-v', 'ON_ERROR_STOP=1', '-t', '-A', '-X', '-q'],
      { input: sql, env: { ...process.env, PGPASSWORD: this.conn.password }, encoding: 'utf-8' },
    );
    if (r.status !== 0) throw new Error(`psql falló: ${r.stderr.trim()}`);
    return r.stdout.trim();
  }

  async lookup(): Promise<DriverMeta | null> {
    const sql = `SELECT (row_to_json(x.*))::text FROM (
      SELECT ok, message, data
      FROM fn.ts_cliente_driver_lookup(jsonb_build_object(
        'session', jsonb_build_object('trusted', true),
        'entorno', '${this.entorno}'
      ))
    ) x;`;
    const raw = this.psql(sql);
    const row = JSON.parse(raw) as { ok: boolean; message: string; data: any };
    if (!row.ok) {
      if (row.message === 'ts_cliente_driver.no_disponible') return null;
      throw new Error(`lookup falló: ${row.message}`);
    }
    return {
      version: row.data.version,
      entorno: row.data.entorno,
      hashSha256: row.data.hash_sha256,
      tamano: row.data.tamano,
    };
  }

  async descargar(version?: number): Promise<Uint8Array> {
    const verLit = version === undefined ? "''" : `'${version}'`;
    const sql = `SELECT (row_to_json(x.*))::text FROM (
      SELECT ok, message, data
      FROM fn.ts_cliente_driver_descargar(jsonb_build_object(
        'session', jsonb_build_object('trusted', true),
        'entorno', '${this.entorno}',
        'version', ${verLit}
      ))
    ) x;`;
    const raw = this.psql(sql);
    const row = JSON.parse(raw) as { ok: boolean; message: string; data: any };
    if (!row.ok) throw new Error(`descarga falló: ${row.message}`);
    return Buffer.from(row.data.bytes_b64, 'base64');
  }

  async publicar(bytes: Uint8Array, hashSha256: string, notas?: string): Promise<{ id: number; version: number }> {
    const b64 = Buffer.from(bytes).toString('base64');
    const notasFrag = notas ? `, 'notas', '${notas.replace(/'/g, "''")}'` : '';
    // Bytes via dollar-quoted string para evitar escapes
    const sql = `SELECT (row_to_json(x.*))::text FROM (
      SELECT ok, message, data
      FROM fn.ts_cliente_driver_publicar(jsonb_build_object(
        'session',     jsonb_build_object('trusted', true),
        'entorno',     '${this.entorno}',
        'hash_sha256', '${hashSha256}'
        ${notasFrag},
        'bytes_b64',   $CHALONA_BYTES$${b64}$CHALONA_BYTES$
      ))
    ) x;`;
    const raw = this.psql(sql);
    const row = JSON.parse(raw) as { ok: boolean; message: string; data: any };
    if (!row.ok) throw new Error(`publicar falló: ${row.message}`);
    return { id: row.data.id, version: row.data.version };
  }
}
