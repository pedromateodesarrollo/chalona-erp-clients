"""Tests de comprobantes: validación, to_payload, e integración usando las clases."""

import os
import time

import pytest

from chalona_driver import EcfApiError, EcfClient, EcfValidationError
from chalona_driver.comprobantes import (
    DetalleItem,
    EmisorData,
    CompradorData,
    FacturaCreditoFiscal31,
)


def test_factura_31_to_payload_estructura() -> None:
    """to_payload() tiene Encabezado (Version, IdDoc, Emisor, Comprador, Totales) y DetallesItems."""
    c = FacturaCreditoFiscal31()
    c.encf = "E310000000001"
    c.fecha_emision = "01-04-2020"
    c.fecha_vencimiento_secuencia = "31-12-2025"
    c.emisor = EmisorData(rnc="131996035", razon_social="Emisor", direccion="Dir", fecha_emision="01-04-2020")
    c.comprador = CompradorData(rnc="01800451302", razon_social="Comprador")
    c.items = [
        DetalleItem(numero_linea=1, nombre_item="Item", indicador_facturacion=1, indicador_bien_servicio=1, cantidad=1, precio_unitario=100, monto_item=100),
    ]
    c.monto_gravado_total = 100
    c.monto_gravado_i1 = 100
    c.total_itbis = 18
    c.total_itbis1 = 18
    c.monto_total = 118
    payload = c.to_payload()
    assert "Encabezado" in payload
    assert payload["Encabezado"]["Version"] == "1.0"
    assert payload["Encabezado"]["IdDoc"]["TipoeCF"] == "31"
    assert payload["Encabezado"]["IdDoc"]["eNCF"] == "E310000000001"
    assert payload["Encabezado"]["Emisor"]["RNCEmisor"] == "131996035"
    assert payload["Encabezado"]["Totales"]["MontoTotal"] == "118.00"
    assert len(payload["DetallesItems"]) == 1
    assert payload["DetallesItems"][0]["NombreItem"] == "Item"


def test_factura_31_validate_encf_vacio_lanza() -> None:
    """validate() con eNCF vacío lanza EcfValidationError."""
    c = FacturaCreditoFiscal31()
    c.emisor = EmisorData(rnc="131996035", razon_social="E", direccion="D", fecha_emision="01-04-2020")
    c.comprador = CompradorData(rnc="01800451302", razon_social="C")
    c.items = [DetalleItem(numero_linea=1, nombre_item="X", indicador_facturacion=1, indicador_bien_servicio=1, cantidad=1, precio_unitario=10, monto_item=10)]
    c.monto_total = 10
    c.monto_gravado_total = 10
    c.monto_gravado_i1 = 10
    c.total_itbis = 1.8
    c.total_itbis1 = 1.8
    with pytest.raises(EcfValidationError) as exc:
        c.validate()
    assert "eNCF" in exc.value.message or "requerido" in exc.value.message.lower()


def test_factura_31_validate_sin_items_lanza() -> None:
    """validate() sin ítems lanza EcfValidationError."""
    c = FacturaCreditoFiscal31()
    c.encf = "E310000000001"
    c.fecha_emision = "01-04-2020"
    c.emisor = EmisorData(rnc="131996035", razon_social="E", direccion="D", fecha_emision="01-04-2020")
    c.comprador = CompradorData(rnc="01800451302", razon_social="C")
    c.items = []
    c.monto_total = 0
    c.monto_gravado_total = 0
    c.monto_gravado_i1 = 0
    c.total_itbis = 0
    c.total_itbis1 = 0
    with pytest.raises(EcfValidationError) as exc:
        c.validate()
    assert "ítem" in exc.value.message.lower() or "DetallesItems" in exc.value.message


@pytest.mark.integration
def test_envio_con_clases_factura_31(
    ecf_client_logged_in: EcfClient,
    rnc: str,
    portal: str,
) -> None:
    """Integración: FacturaCreditoFiscal31 con datos mínimos y enviar(client, rnc, portal)."""
    encf = f"E31{int(time.time()) % 10_000_000_000:010d}"
    c = FacturaCreditoFiscal31()
    c.encf = encf
    c.fecha_emision = "01-04-2020"
    c.fecha_vencimiento_secuencia = "31-12-2025"
    c.emisor = EmisorData(
        rnc=rnc,
        razon_social="Emisor prueba",
        direccion="Direccion prueba",
        fecha_emision="01-04-2020",
    )
    c.comprador = CompradorData(
        rnc="01800451302",
        razon_social="Comprador prueba",
    )
    c.items = [
        DetalleItem(
            numero_linea=1,
            nombre_item="Item prueba",
            indicador_facturacion=1,
            indicador_bien_servicio=1,
            cantidad=1.0,
            precio_unitario=1000.0,
            monto_item=1000.0,
        ),
    ]
    c.monto_gravado_total = 1000.0
    c.monto_gravado_i1 = 1000.0
    c.total_itbis = 180.0
    c.total_itbis1 = 180.0
    c.monto_total = 1180.0
    data = c.enviar(ecf_client_logged_in, rnc, portal)
    assert "estado" in data
    assert data.get("numero") == encf
