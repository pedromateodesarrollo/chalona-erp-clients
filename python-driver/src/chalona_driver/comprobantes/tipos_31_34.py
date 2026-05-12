"""Comprobantes tipo 31 (FCF), 32 (Consumo), 33 (Nota Débito), 34 (Nota Crédito)."""

from .base import ComprobanteBase
from .datos import InformacionReferencia


class FacturaCreditoFiscal31(ComprobanteBase):
    """Factura de Crédito Fiscal (tipo 31)."""

    tipo_ecf = 31

    def __init__(self) -> None:
        super().__init__()
        self.monto_gravado_total = 0.0
        self.monto_gravado_i1 = 0.0
        self.itbis1 = 18
        self.total_itbis = 0.0
        self.total_itbis1 = 0.0
        self.monto_total = 0.0

    def _build_id_doc(self) -> dict:
        d = super()._build_id_doc()
        d["FechaVencimientoSecuencia"] = (self.fecha_vencimiento_secuencia or "").strip()
        d["IndicadorMontoGravado"] = str(self.indicador_monto_gravado)
        return d

    def _build_totales(self) -> dict:
        return {
            "MontoGravadoTotal": f"{self.monto_gravado_total:.2f}",
            "MontoGravadoI1": f"{self.monto_gravado_i1:.2f}",
            "ITBIS1": str(self.itbis1),
            "TotalITBIS": f"{self.total_itbis:.2f}",
            "TotalITBIS1": f"{self.total_itbis1:.2f}",
            "MontoTotal": f"{self.monto_total:.2f}",
        }


class FacturaConsumo32(ComprobanteBase):
    """Factura de Consumo (tipo 32). RFCE si MontoTotal < 250_000."""

    tipo_ecf = 32

    def __init__(self) -> None:
        super().__init__()
        self.monto_gravado_total = 0.0
        self.monto_gravado_i1 = 0.0
        self.itbis1 = 18
        self.total_itbis = 0.0
        self.total_itbis1 = 0.0
        self.monto_total = 0.0

    @property
    def monto_total_val(self) -> float:
        return self.monto_total

    def _build_id_doc(self) -> dict:
        d = super()._build_id_doc()
        if self.monto_total >= 250_000:
            d["FechaVencimientoSecuencia"] = (self.fecha_vencimiento_secuencia or "").strip()
        d["IndicadorMontoGravado"] = str(self.indicador_monto_gravado)
        return d

    def _build_totales(self) -> dict:
        return {
            "MontoGravadoTotal": f"{self.monto_gravado_total:.2f}",
            "MontoGravadoI1": f"{self.monto_gravado_i1:.2f}",
            "ITBIS1": str(self.itbis1),
            "TotalITBIS": f"{self.total_itbis:.2f}",
            "TotalITBIS1": f"{self.total_itbis1:.2f}",
            "MontoTotal": f"{self.monto_total:.2f}",
        }


class NotaDebito33(ComprobanteBase):
    """Nota de Débito (tipo 33). Requiere InformacionReferencia."""

    tipo_ecf = 33

    def __init__(self) -> None:
        super().__init__()
        self.monto_exento = 0.0
        self.monto_total = 0.0
        self._info_ref = InformacionReferencia()

    def _build_id_doc(self) -> dict:
        d = super()._build_id_doc()
        d["FechaVencimientoSecuencia"] = (self.fecha_vencimiento_secuencia or "").strip()
        return d

    def _build_totales(self) -> dict:
        return {
            "MontoExento": f"{self.monto_exento:.2f}",
            "MontoTotal": f"{self.monto_total:.2f}",
        }

    def _informacion_referencia(self) -> InformacionReferencia:
        return self._info_ref


class NotaCredito34(ComprobanteBase):
    """Nota de Crédito (tipo 34). Requiere InformacionReferencia."""

    tipo_ecf = 34

    def __init__(self) -> None:
        super().__init__()
        self.monto_exento = 0.0
        self.monto_total = 0.0
        self._info_ref = InformacionReferencia()

    def _build_id_doc(self) -> dict:
        d = super()._build_id_doc()
        d["FechaVencimientoSecuencia"] = (self.fecha_vencimiento_secuencia or "").strip()
        return d

    def _build_totales(self) -> dict:
        return {
            "MontoExento": f"{self.monto_exento:.2f}",
            "MontoTotal": f"{self.monto_total:.2f}",
        }

    def _informacion_referencia(self) -> InformacionReferencia:
        return self._info_ref
