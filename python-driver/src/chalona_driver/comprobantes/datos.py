"""Estructuras de datos para recolección mínima de comprobantes e-CF."""

from dataclasses import dataclass, field


@dataclass
class EmisorData:
    """Datos del emisor (obligatorios: rnc, razon_social, direccion, fecha_emision)."""

    rnc: str = ""
    razon_social: str = ""
    direccion: str = ""
    fecha_emision: str = ""
    nombre_comercial: str = ""
    municipio: str = ""
    provincia: str = ""
    telefonos: list[str] = field(default_factory=list)
    correo: str = ""


@dataclass
class CompradorData:
    """Datos del comprador (rnc o identificador_extranjero, razon_social)."""

    rnc: str = ""
    identificador_extranjero: str = ""
    razon_social: str = ""
    contacto: str = ""
    correo: str = ""
    direccion: str = ""
    municipio: str = ""
    provincia: str = ""


@dataclass
class RetencionItem:
    """Retención a nivel ítem (tipos 41, 47)."""

    monto_itbis_retenido: float = 0.0
    monto_isr_retenido: float = 0.0


@dataclass
class DetalleItem:
    """Una línea del detalle (obligatorios según tipo)."""

    numero_linea: int = 0
    nombre_item: str = ""
    indicador_facturacion: int = 1  # 0-4
    indicador_bien_servicio: int = 1  # 1=bien, 2=servicio
    cantidad: float = 0.0
    precio_unitario: float = 0.0
    monto_item: float = 0.0
    unidad_medida: str = ""
    retencion: RetencionItem | None = None


@dataclass
class InformacionReferencia:
    """Referencia para notas de crédito/débito (tipos 33, 34)."""

    ncf_modificado: str = ""
    fecha_ncf_modificado: str = ""
    codigo_modificacion: str = ""  # "1","2","3","4"
