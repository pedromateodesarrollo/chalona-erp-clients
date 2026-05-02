#!/usr/bin/env python3
"""CLI prueba: descarga driver Python activo, lo carga, valida casos.

Configura conexión vía env:
  PG_HOST=localhost PG_PORT=5432 PG_DB=midb PG_USER=postgres PG_PASS=secret \\
  ENTORNO=test python3 bin/prueba_comprobantes_driver.py
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from chalona_driver import PostgresDriverSource, PgConn, DriverHandle  # noqa: E402


def main():
    conn = PgConn(
        host=os.environ.get("PG_HOST", "localhost"),
        port=int(os.environ.get("PG_PORT", "5432")),
        database=os.environ.get("PG_DB", "postgres"),
        user=os.environ.get("PG_USER", "postgres"),
        password=os.environ.get("PG_PASS", "postgres"),
    )
    entorno = os.environ.get("ENTORNO", "test")

    casos = [
        ("tipo 31 OK", {"tipo": "31", "fecha_emision": "15-01-2026", "rnc_emisor": "131086268",
                         "rnc_comprador": "101000001", "monto_total": 1000}, True),
        ("tipo 32 OK monto bajo", {"tipo": "32", "fecha_emision": "15-01-2026",
                                    "rnc_emisor": "131086268", "monto_total": 5000}, True),
        ("tipo inválido", {"tipo": "99", "fecha_emision": "15-01-2026",
                            "rnc_emisor": "131086268", "monto_total": 100}, False),
        ("fecha inválida", {"tipo": "31", "fecha_emision": "2026-01-15",
                             "rnc_emisor": "131086268", "rnc_comprador": "101000001",
                             "monto_total": 100}, False),
        ("tipo 31 sin RNC comprador", {"tipo": "31", "fecha_emision": "15-01-2026",
                                        "rnc_emisor": "131086268", "monto_total": 100}, False),
        ("tipo 32 manual RFCE excedido", {"tipo": "32", "fecha_emision": "15-01-2026",
                                           "rnc_emisor": "131086268", "monto_total": 300000}, False),
        ("NC excede tope", {"tipo": "34", "fecha_emision": "15-01-2026",
                             "rnc_emisor": "131086268", "rnc_comprador": "101000001",
                             "monto_total": 5000, "total_factura_referenciada": 1000,
                             "suma_nd_referenciadas": 500}, False),
        ("NC dentro de tope", {"tipo": "34", "fecha_emision": "15-01-2026",
                                "rnc_emisor": "131086268", "rnc_comprador": "101000001",
                                "monto_total": 1500, "total_factura_referenciada": 1000,
                                "suma_nd_referenciadas": 500}, True),
        ("monto cero", {"tipo": "32", "fecha_emision": "15-01-2026",
                         "rnc_emisor": "131086268", "monto_total": 0}, False),
    ]

    src = PostgresDriverSource(conn, entorno)
    print(f"== Lookup driver Python @ {entorno} ({conn.host}:{conn.port}/{conn.database})")
    meta = src.lookup()
    if meta is None:
        sys.stderr.write(f"No hay driver Python activo en {entorno}\n")
        sys.exit(1)
    print(f"   activo: v{meta.version}  {meta.tamano} bytes  sha256={meta.hash_sha256[:12]}...")

    bytes_drv = src.descargar()
    handle = DriverHandle.cargar(bytes_drv, str(meta.version))
    print(f"   cargado: instancia.version='{handle.instancia.version}'")

    print(f"\n== Casos:")
    pasaron = fallaron = 0
    for nombre, comp, esperado in casos:
        ok, errs = handle.instancia.pre_validar(comp)
        match = ok == esperado
        marca = "OK  " if match else "FAIL"
        if esperado:
            detalle = "" if ok else f" errores={errs}"
        else:
            detalle = " (esperaba fallo)" if ok else f" errores={errs}"
        print(f"   [{marca}] {nombre}{detalle}")
        if match:
            pasaron += 1
        else:
            fallaron += 1
    print(f"\n{pasaron} pasaron, {fallaron} fallaron")
    sys.exit(0 if fallaron == 0 else 1)


if __name__ == "__main__":
    main()
