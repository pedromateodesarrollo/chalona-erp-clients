"""Validación de comprobantes e-CF según manual DGII. Lanza EcfValidationError."""

import re

from chalona_driver.exceptions import EcfValidationError

_FECHA_DD_MM_YYYY = re.compile(r"^\d{2}-\d{2}-\d{4}$")


def _is_fecha_dd_mm_yyyy(s: str) -> bool:
    if not s or not _FECHA_DD_MM_YYYY.match(s.strip()):
        return False
    parts = s.strip().split("-")
    d, m, y = int(parts[0]), int(parts[1]), int(parts[2])
    if m < 1 or m > 12 or d < 1 or d > 31 or y < 1900 or y > 2100:
        return False
    return True


def _is_rnc_cedula_valid(val: str) -> bool:
    """RNC o cédula RD: solo dígitos, 9 u 11 caracteres."""
    if not val:
        return False
    digits = re.sub(r"\D", "", val)
    return len(digits) in (9, 11)


def validar_fecha(path: str, valor: str, obligatorio: bool = True) -> None:
    if not valor or not valor.strip():
        if obligatorio:
            raise EcfValidationError(f"Campo requerido: {path}", [{"path": path, "code": "ecf.requerido"}])
        return
    if not _is_fecha_dd_mm_yyyy(valor):
        raise EcfValidationError(
            f"Formato fecha inválido (dd-MM-yyyy): {path}",
            [{"path": path, "code": "ecf.formato_fecha", "valor": valor}],
        )


def validar_rnc(path: str, valor: str, obligatorio: bool = True) -> None:
    if not valor or not valor.strip():
        if obligatorio:
            raise EcfValidationError(f"Campo requerido: {path}", [{"path": path, "code": "ecf.requerido"}])
        return
    if not _is_rnc_cedula_valid(valor):
        raise EcfValidationError(
            f"RNC o cédula con formato inválido: {path}",
            [{"path": path, "code": "ecf.formato_rnc"}],
        )


def validar_encf(encf: str) -> None:
    if not encf or not encf.strip():
        raise EcfValidationError(
            "eNCF requerido",
            [{"path": "Encabezado.IdDoc.eNCF", "code": "ecf.requerido"}],
        )
    if len(encf.strip()) > 13:
        raise EcfValidationError(
            "eNCF longitud máxima 13",
            [{"path": "Encabezado.IdDoc.eNCF", "code": "ecf.largo_maximo", "max": 13}],
        )


def validar_emisor(emisor: "EmisorData", exigir_direccion: bool = True) -> None:
    validar_rnc("Encabezado.Emisor.RNCEmisor", emisor.rnc)
    if not emisor.razon_social or not emisor.razon_social.strip():
        raise EcfValidationError(
            "RazonSocialEmisor requerido",
            [{"path": "Encabezado.Emisor.RazonSocialEmisor", "code": "ecf.requerido"}],
        )
    if len(emisor.razon_social.strip()) > 150:
        raise EcfValidationError(
            "RazonSocialEmisor máximo 150 caracteres",
            [{"path": "Encabezado.Emisor.RazonSocialEmisor", "code": "ecf.largo_maximo", "max": 150}],
        )
    if exigir_direccion and (not emisor.direccion or not emisor.direccion.strip()):
        raise EcfValidationError(
            "DireccionEmisor requerido",
            [{"path": "Encabezado.Emisor.DireccionEmisor", "code": "ecf.requerido"}],
        )
    if emisor.direccion and len(emisor.direccion.strip()) > 100:
        raise EcfValidationError(
            "DireccionEmisor máximo 100 caracteres",
            [{"path": "Encabezado.Emisor.DireccionEmisor", "code": "ecf.largo_maximo", "max": 100}],
        )
    validar_fecha("Encabezado.Emisor.FechaEmision", emisor.fecha_emision)


def validar_comprador(comprador: "CompradorData", obligatorio_comprador: bool = True) -> None:
    if not comprador.razon_social or not comprador.razon_social.strip():
        if obligatorio_comprador:
            raise EcfValidationError(
                "RazonSocialComprador requerido",
                [{"path": "Encabezado.Comprador.RazonSocialComprador", "code": "ecf.requerido"}],
            )
        return
    if comprador.rnc and not _is_rnc_cedula_valid(comprador.rnc):
        raise EcfValidationError(
            "RNCComprador formato inválido",
            [{"path": "Encabezado.Comprador.RNCComprador", "code": "ecf.formato_rnc"}],
        )
    rnc_ok = (comprador.rnc or "").strip()
    id_ext = (comprador.identificador_extranjero or "").strip()
    if comprador.razon_social.strip() and not rnc_ok and not id_ext:
        raise EcfValidationError(
            "RNC o IdentificadorExtranjero requerido cuando hay Comprador",
            [{"path": "Encabezado.Comprador.RNCComprador", "code": "ecf.requerido"}],
        )


def validar_items(items: list["DetalleItem"], tipo_ecf: int) -> None:
    from .datos import DetalleItem

    if not items:
        raise EcfValidationError(
            "Al menos un ítem en DetallesItems",
            [{"path": "DetallesItems", "code": "ecf.detalle_al_menos_uno"}],
        )
    indicadores_fact = (0, 1, 2, 3, 4)
    indicadores_bien = (1, 2)
    for i, it in enumerate(items):
        prefix = f"DetallesItems[{i}]"
        if it.numero_linea < 1 or it.numero_linea > 10000:
            raise EcfValidationError(
                f"NumeroLinea 1-10000: {prefix}",
                [{"path": f"{prefix}.NumeroLinea", "code": "ecf.rango_numero_linea"}],
            )
        if not it.nombre_item or not it.nombre_item.strip():
            raise EcfValidationError(f"NombreItem requerido: {prefix}", [{"path": f"{prefix}.NombreItem", "code": "ecf.requerido"}])
        if it.nombre_item and len(it.nombre_item.strip()) > 80:
            raise EcfValidationError(f"NombreItem máximo 80: {prefix}", [{"path": f"{prefix}.NombreItem", "code": "ecf.largo_maximo"}])
        if it.indicador_facturacion not in indicadores_fact:
            raise EcfValidationError(
                f"IndicadorFacturacion 0-4: {prefix}",
                [{"path": f"{prefix}.IndicadorFacturacion", "code": "ecf.valor_no_permitido"}],
            )
        if tipo_ecf in (43, 44, 47) and it.indicador_facturacion != 4:
            raise EcfValidationError(
                f"Tipo {tipo_ecf} requiere IndicadorFacturacion 4: {prefix}",
                [{"path": f"{prefix}.IndicadorFacturacion", "code": "ecf.indicador_facturacion_tipo_ecf"}],
            )
        if tipo_ecf == 46 and it.indicador_facturacion != 3:
            raise EcfValidationError(
                f"Tipo 46 requiere IndicadorFacturacion 3: {prefix}",
                [{"path": f"{prefix}.IndicadorFacturacion", "code": "ecf.indicador_facturacion_tipo_ecf"}],
            )
        if it.indicador_bien_servicio not in indicadores_bien:
            raise EcfValidationError(
                f"IndicadorBienoServicio 1 o 2: {prefix}",
                [{"path": f"{prefix}.IndicadorBienoServicio", "code": "ecf.valor_no_permitido"}],
            )
        if tipo_ecf == 47 and it.indicador_bien_servicio != 2:
            raise EcfValidationError(
                f"Tipo 47 requiere IndicadorBienoServicio 2: {prefix}",
                [{"path": f"{prefix}.IndicadorBienoServicio", "code": "ecf.indicador_bien_servicio_tipo_47"}],
            )
        if it.cantidad <= 0:
            raise EcfValidationError(f"CantidadItem > 0: {prefix}", [{"path": f"{prefix}.CantidadItem", "code": "ecf.mayor_cero"}])
        if it.precio_unitario < 0 or it.monto_item < 0:
            raise EcfValidationError(
                f"PrecioUnitario/MontoItem no negativos: {prefix}",
                [{"path": f"{prefix}.MontoItem", "code": "ecf.valor_no_negativo"}],
            )


def validar_informacion_referencia(info: "InformacionReferencia") -> None:
    from .datos import InformacionReferencia

    if not info.ncf_modificado or not info.ncf_modificado.strip():
        raise EcfValidationError(
            "NCFModificado requerido para tipo 33/34",
            [{"path": "InformacionReferencia.NCFModificado", "code": "ecf.requerido"}],
        )
    validar_fecha("InformacionReferencia.FechaNCFModificado", info.fecha_ncf_modificado)
    if not info.codigo_modificacion or info.codigo_modificacion.strip() not in ("1", "2", "3", "4"):
        raise EcfValidationError(
            "CodigoModificacion debe ser 1, 2, 3 o 4",
            [{"path": "InformacionReferencia.CodigoModificacion", "code": "ecf.valor_no_permitido"}],
        )
