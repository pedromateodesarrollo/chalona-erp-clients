"""Contrato que el driver descargado debe implementar.

El loader busca la primera clase concreta del namespace cargado que sea
subclase de ComprobanteDriver. Espejo de IComprobanteDriver (C#) y
ComprobanteDriver (Dart/TS).
"""
from abc import ABC, abstractmethod
from typing import Any, Mapping


class ComprobanteDriver(ABC):
    @property
    @abstractmethod
    def version(self) -> str:
        """Versión legible del driver — 'v1', 'v2', etc. Solo logs."""

    @abstractmethod
    def pre_validar(self, comprobante: Mapping[str, Any]) -> tuple[bool, list[str]]:
        """Pre-valida un comprobante. Devuelve (ok, errores)."""
