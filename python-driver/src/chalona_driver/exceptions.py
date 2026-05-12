"""Excepción complementaria del driver Python.

`EcfApiError` se define en `ecf_client.py` (errores del API HTTP).
`EcfValidationError` se usa para validación local de comprobantes antes de envío.
"""


class EcfValidationError(Exception):
    """Error de validación local antes de enviar (clases tipadas de comprobantes)."""

    def __init__(self, message: str, errors: list[dict] | None = None):
        super().__init__(message)
        self.message = message
        self.errors = errors or []

    def __str__(self) -> str:
        return self.message
