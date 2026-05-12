"""Comprobantes tipo 41 (Compras), 43 (Gastos Menores), 44 (Régimen Especial), 45 (Gubernamental), 46 (Exportación), 47 (Pagos Exterior)."""

from .base import ComprobanteBase
from .datos import InformacionReferencia


class Compras41(ComprobanteBase):
    """Compras con retenciones (tipo 41)."""

    tipo_ecf = 41

    def __init__(self) -> None:
        super().__init__()
        self.monto_gravado_total = 0.0
        self.monto_gravado_i1 = 0.0
        self.itbis1 = 18
        self.total_itbis = 0.0
        self.total_itbis1 = 0.0
        self.monto_total = 0.0
        self.valor_pagar = 0.0
        self.total_itbis_retenido = 0.0
        self.total_isr_retencion = 0.0

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
            "ValorPagar": f"{self.valor_pagar:.2f}",
            "TotalITBISRetenido": f"{self.total_itbis_retenido:.2f}",
            "TotalISRRetencion": f"{self.total_isr_retencion:.2f}",
        }


class GastosMenores43(ComprobanteBase):
    """Gastos Menores (tipo 43). Sin comprador obligatorio, ítems exentos."""

    tipo_ecf = 43

    def __init__(self) -> None:
        super().__init__()
        self.monto_exento = 0.0
        self.monto_total = 0.0

    def _build_id_doc(self) -> dict:
        d = super()._build_id_doc()
        d["FechaVencimientoSecuencia"] = (self.fecha_vencimiento_secuencia or "").strip()
        return d

    def _build_totales(self) -> dict:
        return {
            "MontoExento": f"{self.monto_exento:.2f}",
            "MontoTotal": f"{self.monto_total:.2f}",
        }


class RegimenEspecial44(ComprobanteBase):
    """Régimen Especial (tipo 44). Comprador con IdentificadorExtranjero."""

    tipo_ecf = 44

    def __init__(self) -> None:
        super().__init__()
        self.monto_exento = 0.0
        self.monto_total = 0.0
        self.valor_pagar = 0.0

    def _build_id_doc(self) -> dict:
        d = super()._build_id_doc()
        d["FechaVencimientoSecuencia"] = (self.fecha_vencimiento_secuencia or "").strip()
        return d

    def _build_totales(self) -> dict:
        return {
            "MontoExento": f"{self.monto_exento:.2f}",
            "MontoTotal": f"{self.monto_total:.2f}",
            "ValorPagar": f"{self.valor_pagar:.2f}",
        }


class Gubernamental45(ComprobanteBase):
    """Gubernamental (tipo 45)."""

    tipo_ecf = 45

    def __init__(self) -> None:
        super().__init__()
        self.monto_gravado_total = 0.0
        self.monto_gravado_i1 = 0.0
        self.itbis1 = 18
        self.total_itbis = 0.0
        self.total_itbis1 = 0.0
        self.monto_total = 0.0
        self.valor_pagar = 0.0

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
            "ValorPagar": f"{self.valor_pagar:.2f}",
        }


class Exportacion46(ComprobanteBase):
    """Exportación (tipo 46). IndicadorFacturacion 3 (ITBIS 0)."""

    tipo_ecf = 46

    def __init__(self) -> None:
        super().__init__()
        self.monto_gravado_i3 = 0.0
        self.total_itbis3 = 0.0
        self.monto_total = 0.0

    def _build_id_doc(self) -> dict:
        d = super()._build_id_doc()
        d["FechaVencimientoSecuencia"] = (self.fecha_vencimiento_secuencia or "").strip()
        return d

    def _build_totales(self) -> dict:
        return {
            "MontoGravadoTotal": f"{self.monto_gravado_i3:.2f}",
            "MontoGravadoI3": f"{self.monto_gravado_i3:.2f}",
            "ITBIS3": "0",
            "TotalITBIS": "0.00",
            "TotalITBIS3": f"{self.total_itbis3:.2f}",
            "MontoTotal": f"{self.monto_total:.2f}",
        }


class PagosExterior47(ComprobanteBase):
    """Pagos al Exterior (tipo 47). Comprador IdentificadorExtranjero, ítems servicio."""

    tipo_ecf = 47

    def __init__(self) -> None:
        super().__init__()
        self.monto_exento = 0.0
        self.monto_total = 0.0
        self.total_isr_retencion = 0.0

    def _build_id_doc(self) -> dict:
        d = super()._build_id_doc()
        d["FechaVencimientoSecuencia"] = (self.fecha_vencimiento_secuencia or "").strip()
        return d

    def _build_totales(self) -> dict:
        return {
            "MontoExento": f"{self.monto_exento:.2f}",
            "MontoTotal": f"{self.monto_total:.2f}",
            "TotalISRRetencion": f"{self.total_isr_retencion:.2f}",
        }
