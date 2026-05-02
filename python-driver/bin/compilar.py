#!/usr/bin/env python3
"""CLI: empaca driver_src/<nombre>.py → bytes UTF-8 a archivo o stdout.

Uso: compilar.py <fuente.py> [salida]
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

# Permite ejecutar sin instalar el paquete
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from chalona_driver.compiler import compilar_driver  # noqa: E402


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("Uso: compilar.py <fuente.py> [salida]\n")
        sys.exit(1)
    fuente = sys.argv[1]
    salida = sys.argv[2] if len(sys.argv) > 2 else None

    bytes_out = compilar_driver(fuente)
    h = hashlib.sha256(bytes_out).hexdigest()
    if salida:
        Path(salida).write_bytes(bytes_out)
        sys.stderr.write(f"compilado: {len(bytes_out)} bytes  sha256={h[:12]}...\n")
    else:
        sys.stdout.buffer.write(bytes_out)


if __name__ == "__main__":
    main()
