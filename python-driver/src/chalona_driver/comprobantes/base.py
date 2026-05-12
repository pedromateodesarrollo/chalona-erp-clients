"""Clase base para comprobantes e-CF. Subclases por tipo 31-47."""

from __future__ import annotations

from chalona_driver.exceptions import EcfValidationError

from .datos import CompradorData, DetalleItem, EmisorData, InformacionReferencia
from . import validation


class ComprobanteBase:
    """Base para comprobantes. Subclases definen tipo_ecf, Totales e IdDoc específico."""

    tipo_ecf: int = 0
    version: str = "1.0"

    def __init__(self) -> None:
        self.emisor = EmisorData()
        self.comprador = CompradorData()
        self.items: list[DetalleItem] = []
        self.encf = ""
        self.fecha_emision = ""
        self.fecha_vencimiento_secuencia = ""
        self.tipo_pago = 1  # 1=Contado, 2=Crédito, 3=Gratuito
        self.tipo_ingresos = 1  # 01-06
        self.indicador_monto_gravado = 0  # 0|1 cuando aplique

    def _build_emisor(self) -> dict:
        e = self.emisor
        out = {
            "RNCEmisor": (e.rnc or "").strip(),
            "RazonSocialEmisor": (e.razon_social or "").strip(),
            "DireccionEmisor": (e.direccion or "").strip(),
            "FechaEmision": (e.fecha_emision or "").strip(),
        }
        if e.nombre_comercial:
            out["NombreComercial"] = e.nombre_comercial.strip()
        if e.municipio:
            out["Municipio"] = e.municipio.strip()
        if e.provincia:
            out["Provincia"] = e.provincia.strip()
        if e.telefonos:
            out["TablaTelefonoEmisor"] = e.telefonos
        if e.correo:
            out["CorreoEmisor"] = e.correo.strip()
        return out

    def _build_comprador(self) -> dict:
        c = self.comprador
        out = {
            "RNCComprador": (c.rnc or "").strip(),
            "RazonSocialComprador": (c.razon_social or "").strip(),
        }
        if c.identificador_extranjero:
            out["IdentificadorExtranjero"] = c.identificador_extranjero.strip()
        if c.contacto:
            out["ContactoComprador"] = c.contacto.strip()
        if c.correo:
            out["CorreoComprador"] = c.correo.strip()
        if c.direccion:
            out["DireccionComprador"] = c.direccion.strip()
        if c.municipio:
            out["MunicipioComprador"] = c.municipio.strip()
        if c.provincia:
            out["ProvinciaComprador"] = c.provincia.strip()
        return out

    def _build_detalles(self) -> list[dict]:
        out = []
        for it in self.items:
            row = {
                "NumeroLinea": str(it.numero_linea),
                "NombreItem": (it.nombre_item or "").strip(),
                "IndicadorFacturacion": str(it.indicador_facturacion),
                "IndicadorBienoServicio": str(it.indicador_bien_servicio),
                "CantidadItem": f"{it.cantidad:.2f}",
                "PrecioUnitarioItem": f"{it.precio_unitario:.2f}",
                "MontoItem": f"{it.monto_item:.2f}",
            }
            if it.unidad_medida:
                row["UnidadMedida"] = it.unidad_medida.strip()
            if it.retencion:
                row["Retencion"] = {
                    "IndicadorAgenteRetencionoPercepcion": "1",
                    "MontoITBISRetenido": f"{it.retencion.monto_itbis_retenido:.2f}",
                    "MontoISRRetenido": f"{it.retencion.monto_isr_retenido:.2f}",
                }
            out.append(row)
        return out

    def _build_id_doc(self) -> dict:
        """Override en subclases. Por defecto campos comunes."""
        return {
            "TipoeCF": str(self.tipo_ecf),
            "eNCF": (self.encf or "").strip(),
            "FechaVencimientoSecuencia": (self.fecha_vencimiento_secuencia or "").strip(),
            "TipoPago": str(self.tipo_pago),
            "TipoIngresos": f"{self.tipo_ingresos:02d}",
        }

    def _build_totales(self) -> dict:
        """Override en subclases."""
        return {}

    def _informacion_referencia(self) -> InformacionReferencia | None:
        """Override en 33/34."""
        return None

    def to_payload(self) -> dict:
        """Construye el JSON completo para envia_ecf."""
        encabezado = {
            "Version": self.version,
            "IdDoc": self._build_id_doc(),
            "Emisor": self._build_emisor(),
            "Comprador": self._build_comprador(),
            "Totales": self._build_totales(),
        }
        payload = {"Encabezado": encabezado, "DetallesItems": self._build_detalles()}
        info = self._informacion_referencia()
        if info is not None:
            payload["InformacionReferencia"] = {
                "NCFModificado": (info.ncf_modificado or "").strip(),
                "FechaNCFModificado": (info.fecha_ncf_modificado or "").strip(),
                "CodigoModificacion": (info.codigo_modificacion or "").strip(),
            }
        return payload

    def validate(self) -> None:
        """Valida campos obligatorios y reglas por tipo. Lanza EcfValidationError."""
        validation.validar_encf(self.encf)
        exigir_direccion = True
        if self.tipo_ecf == 32 and getattr(self, "monto_total", 0) < 250_000:
            exigir_direccion = False  # RFCE
        validation.validar_emisor(self.emisor, exigir_direccion=exigir_direccion)
        obligatorio_comprador = self.tipo_ecf != 43
        validation.validar_comprador(self.comprador, obligatorio_comprador=obligatorio_comprador)
        validation.validar_items(self.items, self.tipo_ecf)
        if self.tipo_ecf in (33, 34):
            info = self._informacion_referencia()
            if info is None:
                raise EcfValidationError("InformacionReferencia requerida para tipo 33/34", [{"path": "InformacionReferencia", "code": "ecf.requerido"}])
            validation.validar_informacion_referencia(info)
        self._validate_extra()

    def _validate_extra(self) -> None:
        """Override en subclases para validaciones adicionales (totales, etc.)."""
        pass

    def enviar(self, client: "EcfClient", rnc: str, portal: str) -> dict:
        """Valida y envía el comprobante. Devuelve data de la respuesta."""
        from chalona_driver import EcfClient

        self.validate()
        return client.envia_ecf(rnc, portal, self.to_payload())
