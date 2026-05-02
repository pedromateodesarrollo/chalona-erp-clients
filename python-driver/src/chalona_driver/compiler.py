"""Empaca .py source del driver para publicar.

Python no compila a bytecode portable (.pyc varía por versión de intérprete),
así que el "compilar" es: validar sintaxis + retornar source UTF-8 bytes.
"""
from __future__ import annotations

import ast
from pathlib import Path


def compilar_driver(fuente_py: str) -> bytes:
    src = Path(fuente_py).read_text(encoding="utf-8")
    # Validar sintaxis fail-fast
    ast.parse(src, filename=fuente_py)
    return src.encode("utf-8")
