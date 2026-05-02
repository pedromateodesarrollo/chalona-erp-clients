"""Driver Python de prueba — pre-validación de comprobantes e-CF.

Espejo de DriverComprobantes.cs (C#), driver-comprobantes.ts (TS), y
driver_prueba_comprobantes_v2.dart. Source .py se publica en
data.python_cliente_driver y el cliente lo descarga + ejecuta vía exec()
en namespace aislado.

Importante: el loader inyecta `ComprobanteDriver` en el namespace antes de
exec(). NO importar chalona_driver.contract aquí — falla en el cliente
descargado porque no necesariamente tiene el paquete instalado.
"""
from typing import Any, Mapping


class DriverV1(ComprobanteDriver):  # type: ignore[name-defined]  # noqa: F821 — inyectado por loader
    @property
    def version(self) -> str:
        return "v1"

    def pre_validar(self, c: Mapping[str, Any]) -> tuple[bool, list[str]]:
        errores: list[str] = []

        tipo = self._s(c.get("tipo"))
        fecha = self._s(c.get("fecha_emision"))
        rnc_emi = self._s(c.get("rnc_emisor"))
        rnc_com = self._s(c.get("rnc_comprador"))
        monto = self._n(c.get("monto_total"))
        total_factura = self._n(c.get("total_factura_referenciada"))
        suma_nd = self._n(c.get("suma_nd_referenciadas"))

        if not tipo:
            errores.append("tipo requerido")
        elif tipo not in ("31", "32", "33", "34"):
            errores.append(f"tipo inválido: {tipo} (debe ser 31, 32, 33 o 34)")

        if not fecha:
            errores.append("fecha_emision requerida")
        elif not self._fecha_valida(fecha):
            errores.append(f'fecha_emision inválida: "{fecha}" (esperado dd-MM-yyyy)')

        if not rnc_emi:
            errores.append("rnc_emisor requerido")
        elif not self._rnc_valido(rnc_emi):
            errores.append(f'rnc_emisor inválido: "{rnc_emi}" (9 u 11 dígitos)')

        if monto is None:
            errores.append("monto_total requerido")
        elif monto <= 0:
            errores.append(f"monto_total debe ser > 0 (actual: {monto})")

        if tipo == "31":
            if not rnc_com:
                errores.append("rnc_comprador requerido para tipo 31 (Crédito Fiscal)")
            elif not self._rnc_valido(rnc_com):
                errores.append(f'rnc_comprador inválido: "{rnc_com}"')

        if tipo == "32" and monto is not None and monto >= 250000:
            errores.append("tipo 32 con monto >= 250000 requiere comprador identificado (manual RFCE)")

        if tipo == "34" and monto is not None:
            tf = total_factura or 0
            sn = suma_nd or 0
            tope = tf + sn
            if monto > tope:
                errores.append(f"NC excede tope: monto {monto} > tope {tope} (factura={tf} + ND={sn})")

        return (len(errores) == 0, errores)

    @staticmethod
    def _s(v: Any) -> str:
        if v is None:
            return ""
        return str(v)

    @staticmethod
    def _n(v: Any):
        if v is None:
            return None
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _fecha_valida(s: str) -> bool:
        p = s.split("-")
        if len(p) != 3:
            return False
        try:
            d, m, y = int(p[0]), int(p[1]), int(p[2])
        except ValueError:
            return False
        if not (1 <= m <= 12):
            return False
        if not (1 <= d <= 31):
            return False
        if not (2020 <= y <= 2100):
            return False
        return True

    @staticmethod
    def _rnc_valido(rnc: str) -> bool:
        if len(rnc) not in (9, 11):
            return False
        return rnc.isdigit()
