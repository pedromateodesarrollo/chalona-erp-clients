"""Lookup + descarga del driver Python desde data.python_cliente_driver via psql.

Sin dep psycopg — usa subprocess + psql binary, mismo patrón de
bin/actualiza-cliente-* y del driver TypeScript.
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
from dataclasses import dataclass
from typing import Optional


@dataclass
class PgConn:
    host: str
    port: int
    database: str
    user: str
    password: str


@dataclass
class DriverMeta:
    version: int
    entorno: str
    hash_sha256: str
    tamano: int


class PostgresDriverSource:
    def __init__(self, conn: PgConn, entorno: str):
        if entorno not in ("test", "produccion"):
            raise ValueError(f"entorno inválido: {entorno} (test|produccion)")
        self.conn = conn
        self.entorno = entorno

    def _psql(self, sql: str) -> str:
        env = {**os.environ, "PGPASSWORD": self.conn.password}
        r = subprocess.run(
            [
                "psql",
                "-h", self.conn.host,
                "-p", str(self.conn.port),
                "-U", self.conn.user,
                "-d", self.conn.database,
                "-v", "ON_ERROR_STOP=1",
                "-t", "-A", "-X", "-q",
            ],
            input=sql, env=env, capture_output=True, text=True,
        )
        if r.returncode != 0:
            raise RuntimeError(f"psql falló: {r.stderr.strip()}")
        return r.stdout.strip()

    def lookup(self) -> Optional[DriverMeta]:
        sql = f"""SELECT (row_to_json(x.*))::text FROM (
          SELECT ok, message, data
          FROM fn.python_cliente_driver_lookup(jsonb_build_object(
            'session', jsonb_build_object('trusted', true),
            'entorno', '{self.entorno}'
          ))
        ) x;"""
        row = json.loads(self._psql(sql))
        if not row["ok"]:
            if row["message"] == "python_cliente_driver.no_disponible":
                return None
            raise RuntimeError(f"lookup falló: {row['message']}")
        d = row["data"]
        return DriverMeta(
            version=d["version"], entorno=d["entorno"],
            hash_sha256=d["hash_sha256"], tamano=d["tamano"],
        )

    def descargar(self, version: Optional[int] = None) -> bytes:
        ver_lit = "''" if version is None else f"'{version}'"
        sql = f"""SELECT (row_to_json(x.*))::text FROM (
          SELECT ok, message, data
          FROM fn.python_cliente_driver_descargar(jsonb_build_object(
            'session', jsonb_build_object('trusted', true),
            'entorno', '{self.entorno}',
            'version', {ver_lit}
          ))
        ) x;"""
        row = json.loads(self._psql(sql))
        if not row["ok"]:
            raise RuntimeError(f"descarga falló: {row['message']}")
        return base64.b64decode(row["data"]["bytes_b64"])

    def publicar(self, source_bytes: bytes, hash_sha256: str, notas: Optional[str] = None) -> dict:
        b64 = base64.b64encode(source_bytes).decode("ascii")
        notas_frag = ""
        if notas:
            notas_esc = notas.replace("'", "''")
            notas_frag = f", 'notas', '{notas_esc}'"
        sql = f"""SELECT (row_to_json(x.*))::text FROM (
          SELECT ok, message, data
          FROM fn.python_cliente_driver_publicar(jsonb_build_object(
            'session',     jsonb_build_object('trusted', true),
            'entorno',     '{self.entorno}',
            'hash_sha256', '{hash_sha256}'
            {notas_frag},
            'bytes_b64',   $CHALONA_BYTES${b64}$CHALONA_BYTES$
          ))
        ) x;"""
        row = json.loads(self._psql(sql))
        if not row["ok"]:
            raise RuntimeError(f"publicar falló: {row['message']}")
        return row["data"]
