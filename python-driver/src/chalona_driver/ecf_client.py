"""Cliente HTTP para ecf-service. Toda la lógica de comunicación vive en motor.py.

Métodos públicos:
  - login(usuario, clave)
  - envia_ecf(rnc, portal, json_doc)
  - envia_ecf_desde_doc(documento, portal)
  - consulta_estado(comprobantes)
  - descarga_xmls(fecha_desde, fecha_hasta, tipos?)

Internamente, cada método llama _dispatch(fn_name, args) que:
  1. Llama procesar(estado_json) del motor estático.
  2. Si http → shell ejecuta POST y alimenta respuesta al motor.
  3. Si done → devuelve result (y guarda newToken si vino).
  4. Si fail → lanza EcfApiError.
"""
import json
import urllib.error
import urllib.request
from typing import Any, Optional

from .motor import procesar


class EcfApiError(Exception):
    def __init__(self, code: str, data: Optional[dict] = None, status_code: Optional[int] = None):
        self.code = code
        self.data = data or {}
        self.status_code = status_code

    def __str__(self) -> str:
        parts = [f'EcfApiError(code={self.code}']
        if self.status_code is not None:
            parts.append(f', status={self.status_code}')
        if self.data:
            parts.append(f', data={self.data}')
        return ''.join(parts) + ')'


class EcfClient:
    def __init__(
        self,
        base_url: str = 'https://ecf-service.vicortiz.com',
        token: Optional[str] = None,
        timeout: int = 60,
    ):
        self._base_url = base_url.rstrip('/')
        self._token = token
        self._timeout = timeout

    @property
    def token(self) -> Optional[str]:
        return self._token

    def clear_token(self) -> None:
        self._token = None

    def login(self, usuario: str, clave: str, app: str = 'ecf') -> dict:
        return self._dispatch('login', {'usuario': usuario, 'clave': clave, 'app': app})

    def envia_ecf(self, rnc: str, portal: str, json_doc: dict) -> dict:
        return self._dispatch('enviaEcf', {'rnc': rnc, 'portal': portal, 'json': json_doc})

    def envia_ecf_desde_doc(self, documento: dict, portal: str) -> dict:
        return self._dispatch('enviaEcfDesdeDoc', {'documento': documento, 'portal': portal})

    def consulta_estado(self, comprobantes: list) -> list:
        r = self._dispatch('consultaEstado', {'comprobantes': comprobantes})
        return r.get('result') or []

    def descarga_xmls(
        self,
        fecha_desde: str,
        fecha_hasta: str,
        tipos: Optional[list] = None,
    ) -> dict:
        args: dict = {'fecha_desde': fecha_desde, 'fecha_hasta': fecha_hasta}
        if tipos:
            args['tipos'] = tipos
        return self._dispatch('descargaXmls', args)

    # ---------------------------------------------------------------------------
    # Trampolín shell ↔ motor
    # ---------------------------------------------------------------------------
    def _dispatch(self, fn_name: str, args: dict) -> dict:
        last_resp: Optional[dict] = None
        step = 0

        while True:
            estado = {
                'fnName': fn_name,
                'args': args,
                'token': self._token,
                'step': step,
                'lastResp': last_resp,
            }
            step_json = procesar(json.dumps(estado))
            step_map: dict = json.loads(step_json)
            kind = step_map.get('kind')

            if kind == 'done':
                result = step_map.get('result') or {}
                new_token = step_map.get('newToken')
                if new_token:
                    self._token = new_token
                return result

            if kind == 'fail':
                code = step_map.get('code') or 'motor.error_desconocido'
                data_err = step_map.get('data') or {}
                raise EcfApiError(code, data_err)

            if kind == 'http':
                endpoint: str = step_map['endpoint']
                data: dict = step_map.get('data') or {}
                use_token: bool = step_map.get('useToken', True)
                step = step_map.get('step', step + 1)

                resp_full = self._http_post(endpoint, data, use_token=use_token)
                last_resp = {
                    'ok': resp_full.get('ok'),
                    'message': resp_full.get('message'),
                    'data': resp_full.get('data'),
                }
                continue

            raise EcfApiError('motor.kind_desconocido', {'kind': str(kind)})

    # ---------------------------------------------------------------------------
    # HTTP de bajo nivel
    # ---------------------------------------------------------------------------
    def _http_post(self, endpoint: str, data: dict, *, use_token: bool) -> dict:
        url = f'{self._base_url}/'
        body = json.dumps({'request': endpoint, 'data': data}).encode('utf-8')
        headers: dict = {'Content-Type': 'application/json'}
        if use_token and self._token:
            headers['Authorization'] = self._token

        req = urllib.request.Request(url, data=body, headers=headers, method='POST')
        raw = ''
        status_code = 200

        try:
            with urllib.request.urlopen(req, timeout=self._timeout) as resp:
                raw = resp.read().decode('utf-8')
                status_code = resp.status
        except urllib.error.HTTPError as e:
            try:
                raw = e.read().decode('utf-8')
            except Exception:
                raise EcfApiError('http.error', {'detail': f'HTTP {e.code}'}, e.code)
            status_code = e.code
        except urllib.error.URLError as e:
            raise EcfApiError('http.error', {'detail': str(e.reason)})
        except Exception as e:
            raise EcfApiError('http.error', {'detail': str(e)})

        try:
            out: Any = json.loads(raw)
        except Exception:
            raise EcfApiError('respuesta_no_json', {'text': raw[:500]}, status_code)

        if not isinstance(out, dict) or out.get('ok') is not True:
            msg = (out.get('message') if isinstance(out, dict) else None) or 'error_desconocido'
            data_err = (out.get('data') if isinstance(out, dict) else None) or {}
            raise EcfApiError(msg, data_err, status_code)

        return out
