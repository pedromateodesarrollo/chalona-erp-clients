"""Carga .py source descargado desde Postgres y devuelve instancia del driver.

Usa exec() en namespace dict aislado (ns). El driver descargado NO debe
intentar imports de chalona_driver.contract — el loader inyecta la clase
ComprobanteDriver directamente al ns para que las definiciones del driver
puedan heredar de ella.
"""
from __future__ import annotations

import hashlib
import inspect
import os
from pathlib import Path
from typing import Any

from .contract import ComprobanteDriver


class DriverHandle:
    def __init__(self, version: str, hash_sha256: str, instancia: ComprobanteDriver):
        self.version = version
        self.hash_sha256 = hash_sha256
        self.instancia = instancia

    @classmethod
    def cargar(cls, source: bytes, version: str) -> "DriverHandle":
        if isinstance(source, bytes):
            text = source.decode("utf-8")
        else:
            text = source
        h = hashlib.sha256(text.encode("utf-8")).hexdigest()

        # Namespace aislado con la base inyectada
        ns: dict[str, Any] = {
            "__name__": f"chalona_driver_dinamico_{version}",
            "__builtins__": __builtins__,
            "ComprobanteDriver": ComprobanteDriver,
        }
        compiled = compile(text, f"<driver-{version}>", "exec")
        exec(compiled, ns)

        candidato = None
        for name, obj in ns.items():
            if name.startswith("_") or name == "ComprobanteDriver":
                continue
            if inspect.isclass(obj) and issubclass(obj, ComprobanteDriver) and obj is not ComprobanteDriver:
                candidato = obj
                break
        if candidato is None:
            raise RuntimeError("No se encontró clase que herede de ComprobanteDriver")
        inst = candidato()
        return cls(version, h, inst)


class DriverCache:
    def __init__(self, directorio: str):
        self.directorio = Path(directorio)
        self.directorio.mkdir(parents=True, exist_ok=True)

    def _archivo(self, v: str) -> Path:
        return self.directorio / f"driver-{v}.py"

    def tiene(self, v: str) -> bool:
        return self._archivo(v).exists()

    def leer(self, v: str) -> bytes:
        return self._archivo(v).read_bytes()

    def guardar(self, v: str, src: bytes) -> None:
        self._archivo(v).write_bytes(src)
