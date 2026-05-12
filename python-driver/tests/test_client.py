"""Tests del cliente HTTP (API directa): login, envia_ecf con dict, consulta_estado."""

import json
import os
import time

import pytest

from chalona_driver import EcfApiError, EcfClient


def _payload_tipo_31(rnc: str, encf: str) -> dict:
    with open(__file__.replace("test_client.py", "fixtures/doc_tipo_31.json")) as f:
        data = json.load(f)
    data["Encabezado"]["IdDoc"]["eNCF"] = encf
    data["Encabezado"]["Emisor"]["RNCEmisor"] = rnc
    return data


@pytest.mark.integration
def test_login_ok(ecf_client: EcfClient, base_url: str) -> None:
    """Login exitoso: token guardado y data con app, usuario, empresa, token."""
    user = os.environ.get("ECF_TEST_USER", "test@r133193312.com")
    password = os.environ.get("ECF_TEST_PASSWORD", "1234")
    data = ecf_client.login(user, password)
    assert "token" in data
    assert ecf_client._token == data["token"]
    assert data.get("app") == "ecf_service"
    assert "usuario" in data
    assert "empresa" in data


@pytest.mark.integration
def test_login_invalid(ecf_client: EcfClient) -> None:
    """Login con clave incorrecta lanza EcfApiError."""
    with pytest.raises(EcfApiError) as exc_info:
        ecf_client.login("nobody@test.com", "wrong")
    assert "credenciales" in exc_info.value.message.lower() or "invalid" in exc_info.value.message.lower()


@pytest.mark.integration
def test_envia_ecf_ok(ecf_client_logged_in: EcfClient, rnc: str, portal: str) -> None:
    """Envío con payload dict y eNCF único devuelve estado."""
    encf = f"E31{int(time.time()) % 10_000_000_000:010d}"
    payload = _payload_tipo_31(rnc, encf)
    data = ecf_client_logged_in.envia_ecf(rnc, portal, payload)
    assert "estado" in data
    assert data.get("numero") == encf


@pytest.mark.integration
def test_consulta_estado_ok(
    ecf_client_logged_in: EcfClient,
    rnc: str,
    portal: str,
) -> None:
    """Tras enviar un comprobante, consulta_estado lo devuelve."""
    encf = f"E31{int(time.time()) % 10_000_000_000:010d}"
    payload = _payload_tipo_31(rnc, encf)
    ecf_client_logged_in.envia_ecf(rnc, portal, payload)
    result = ecf_client_logged_in.consulta_estado([encf])
    assert isinstance(result, list)
    found = [r for r in result if r.get("numero") == encf]
    assert len(found) >= 1
    assert "estado" in found[0]


@pytest.mark.integration
def test_envia_ecf_sin_token(ecf_client: EcfClient, rnc: str, portal: str) -> None:
    """envia_ecf sin login debe fallar (sin_acceso o 401)."""
    payload = _payload_tipo_31(rnc, "E310000000099")
    with pytest.raises(EcfApiError):
        ecf_client.envia_ecf(rnc, portal, payload)


# test_consulta_estado_max_100 removido: en el driver motor-estático el límite
# de 100 lo valida el motor (EcfApiError code=motor.consulta_estado.maximo_100),
# no el cliente. Cubierto por test_client_max_100 (integration).
