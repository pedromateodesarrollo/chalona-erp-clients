"""Fixtures para tests: base_url, credenciales desde env, cliente con/sin login."""

import os

import pytest

from chalona_driver import EcfClient


def _base_url() -> str:
    return os.environ.get("ECF_API_URL", "http://localhost:3030")


def _user() -> str:
    return os.environ.get("ECF_TEST_USER", "test@r133193312.com")


def _password() -> str:
    return os.environ.get("ECF_TEST_PASSWORD", "1234")


def _rnc() -> str:
    return os.environ.get("ECF_TEST_RNC", "133193312")


def _portal() -> str:
    return os.environ.get("ECF_TEST_PORTAL", "testecf")


@pytest.fixture
def base_url() -> str:
    return _base_url()


@pytest.fixture
def ecf_client(base_url: str) -> EcfClient:
    return EcfClient(base_url=base_url)


@pytest.fixture
def ecf_client_logged_in(ecf_client: EcfClient) -> EcfClient:
    """Cliente ya autenticado (login con credenciales de env)."""
    ecf_client.login(_user(), _password())
    return ecf_client


@pytest.fixture
def rnc() -> str:
    return _rnc()


@pytest.fixture
def portal() -> str:
    return _portal()
