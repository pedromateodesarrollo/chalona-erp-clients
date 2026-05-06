"""Motor v1 — lógica de comunicación con ecf-service (estático).

Antes el motor se descargaba dinámicamente desde Postgres vía exec().
Ahora vive embebido estáticamente: EcfClient llama procesar() directo.

Shell ↔ Motor protocol:
  Input estadoJson:
    {
      "fnName":   "login" | "enviaEcf" | "enviaEcfDesdeDoc" |
                  "consultaEstado" | "descargaXmls",
      "args":     {...},
      "token":    "Bearer ..." | null,
      "step":     0,
      "lastResp": {...} | null
    }
  Output stepJson:
    - {"kind":"http", "step":N+1, "endpoint":"...", "data":{...}, "useToken":bool}
    - {"kind":"done", "result":{...}, "newToken":"..."?}
    - {"kind":"fail", "code":"...", "data":{...}}
"""
import json


def procesar(estado_json: str) -> str:
    try:
        estado = json.loads(estado_json)
    except Exception:
        return _fail('motor.estado_invalido')
    if not isinstance(estado, dict):
        return _fail('motor.estado_invalido')

    fn_name = _str(estado, 'fnName')
    args_raw = estado.get('args')
    args: dict = dict(args_raw) if isinstance(args_raw, dict) else {}
    step_raw = estado.get('step')
    step: int = int(step_raw) if isinstance(step_raw, (int, float)) else 0
    last_resp_raw = estado.get('lastResp')
    last_resp = dict(last_resp_raw) if isinstance(last_resp_raw, dict) else None

    if fn_name == 'login':
        return _flow_login(args, step, last_resp)
    if fn_name == 'enviaEcf':
        return _flow_envia_ecf(args, step, last_resp)
    if fn_name == 'enviaEcfDesdeDoc':
        return _flow_envia_ecf_desde_doc(args, step, last_resp)
    if fn_name == 'consultaEstado':
        return _flow_consulta_estado(args, step, last_resp)
    if fn_name == 'descargaXmls':
        return _flow_descarga_xmls(args, step, last_resp)
    return _fail('motor.fn_desconocida', {'fnName': fn_name})


# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------
def _flow_login(args, step, last_resp):
    if step == 0:
        usuario = _str(args, 'usuario').strip()
        clave = _str(args, 'clave')
        app_raw = _str(args, 'app').strip()
        app = app_raw if app_raw else 'ecf'
        if not usuario:
            return _fail('motor.login.usuario_requerido')
        if not clave:
            return _fail('motor.login.clave_requerida')
        return _http('sistema_login', {'app': app, 'usuario': usuario, 'clave': clave},
                     use_token=False, next_step=1)
    data = _resp_data(last_resp)
    token_str = _str(data, 'token')
    token = token_str if token_str else None
    return _done(data, new_token=token)


# ---------------------------------------------------------------------------
# Envía e-CF (payload DGII ya construido)
# ---------------------------------------------------------------------------
def _flow_envia_ecf(args, step, last_resp):
    if step == 0:
        rnc = _str(args, 'rnc').strip()
        portal = _str(args, 'portal').strip()
        json_doc = args.get('json')
        if not rnc:
            return _fail('motor.envia_ecf.rnc_requerido')
        if portal not in ('ecf', 'testecf'):
            return _fail('motor.envia_ecf.portal_invalido', {'portal': portal})
        if not isinstance(json_doc, dict):
            return _fail('motor.envia_ecf.json_requerido')
        return _http('envia_ecf', {'rnc': rnc, 'portal': portal, 'json': json_doc},
                     use_token=True, next_step=1)
    return _done(_resp_data(last_resp))


# ---------------------------------------------------------------------------
# Envía e-CF desde DocumentoEcf (formato cursores Fox)
# ---------------------------------------------------------------------------
def _flow_envia_ecf_desde_doc(args, step, last_resp):
    if step == 0:
        doc_raw = args.get('documento')
        portal = _str(args, 'portal').strip()
        if not isinstance(doc_raw, dict):
            return _fail('motor.envia_doc.documento_requerido')
        if portal not in ('ecf', 'testecf'):
            return _fail('motor.envia_doc.portal_invalido', {'portal': portal})
        doc = dict(doc_raw)

        fiscal = _str(doc, 'fiscal').strip()
        if not fiscal:
            return _fail('motor.envia_doc.fiscal_requerido')
        if fiscal not in ('31', '32', '33', '34'):
            return _fail('motor.envia_doc.tipo_no_soportado_aun', {'fiscal': fiscal})

        emisor_raw = doc.get('emisor')
        emisor = dict(emisor_raw) if isinstance(emisor_raw, dict) else None
        if emisor is None:
            return _fail('motor.envia_doc.emisor_requerido')
        emisor_rnc = _str(emisor, 'rnc').strip()
        if not emisor_rnc:
            return _fail('motor.envia_doc.emisor_rnc_requerido')

        comprador_raw = doc.get('comprador')
        comprador = dict(comprador_raw) if isinstance(comprador_raw, dict) else None
        if fiscal == '31' and comprador is None:
            return _fail('motor.envia_doc.comprador_requerido_31')

        lineas = doc.get('lineas') or []
        if not lineas:
            return _fail('motor.envia_doc.sin_lineas')

        fecha_emision = _str(doc, 'fecha')
        encf = _str(doc, 'encf')
        moneda = _str(doc, 'moneda') or 'DOP'
        tasa = _num(doc, 'tasa', 1.0)

        detalles_items = []
        n_linea = 1
        for linea_raw in lineas:
            if isinstance(linea_raw, dict):
                ln = dict(linea_raw)
                cantidad = _num(ln, 'cantidad', 0.0)
                precio = _num(ln, 'precio', 0.0)
                monto = cantidad * precio
                es_servicio = int(_num(ln, 'mercs_servicio', 1.0)) == 2
                itbis_linea = _num(ln, 'itbis', 0.0)
                ind_fact = '1' if itbis_linea > 0 else '4'
                detalles_items.append({
                    'NumeroLinea': str(n_linea),
                    'IndicadorFacturacion': ind_fact,
                    'NombreItem': _str(ln, 'descrip'),
                    'IndicadorBienoServicio': '2' if es_servicio else '1',
                    'CantidadItem': _fmt4(cantidad),
                    'PrecioUnitarioItem': _fmt2(precio),
                    'MontoItem': _fmt2(monto),
                })
                n_linea += 1

        fecha_vence_sec = _str(doc, 'vence_fiscal') or '31-12-2099'

        id_doc: dict = {
            'TipoeCF': fiscal,
            'eNCF': encf,
            'FechaVencimientoSecuencia': fecha_vence_sec,
        }
        if fiscal in ('31', '32', '33', '34'):
            id_doc['IndicadorMontoGravado'] = '0'
        if fiscal == '31':
            id_doc['TipoIngresos'] = '01'
            id_doc['TipoPago'] = '1'

        emisor_map: dict = {
            'RNCEmisor': emisor_rnc,
            'RazonSocialEmisor': _str(emisor, 'nombre'),
        }
        emisor_dir = _str(emisor, 'direccion')
        if emisor_dir:
            emisor_map['DireccionEmisor'] = emisor_dir
        emisor_map['FechaEmision'] = fecha_emision

        encabezado: dict = {
            'Version': '1.0',
            'IdDoc': id_doc,
            'Emisor': emisor_map,
        }
        if comprador:
            comp_map: dict = {}
            comp_rnc = _str(comprador, 'rnc')
            if comp_rnc:
                comp_map['RNCComprador'] = comp_rnc
            comp_map['RazonSocialComprador'] = _str(comprador, 'nombre')
            encabezado['Comprador'] = comp_map

        total_doc = _num(doc, 'total', 0.0)
        itbis_doc = _num(doc, 'itbis', 0.0)
        valor_doc = _num(doc, 'valor', 0.0)
        monto_gravado = valor_doc if valor_doc > 0 else (total_doc - itbis_doc)
        encabezado['Totales'] = {
            'MontoGravadoTotal': _fmt2(monto_gravado),
            'MontoGravadoI1': _fmt2(monto_gravado),
            'ITBIS1': '18',
            'TotalITBIS': _fmt2(itbis_doc),
            'TotalITBIS1': _fmt2(itbis_doc),
            'MontoTotal': _fmt2(total_doc),
        }
        if moneda != 'DOP':
            encabezado['OtraMoneda'] = {
                'TipoMoneda': moneda,
                'TipoCambio': _fmt4(tasa),
            }

        payload = {'Encabezado': encabezado, 'DetallesItems': detalles_items}
        return _http('envia_ecf', {'rnc': emisor_rnc, 'portal': portal, 'json': payload},
                     use_token=True, next_step=1)

    data_api = _resp_data(last_resp)
    return _done({
        'estado': data_api.get('estado'),
        'estado_descripcion': data_api.get('estado_descripcion'),
        'codigo_seguridad': data_api.get('codigo_seguridad'),
        'fecha_firma': data_api.get('fecha_firma'),
        'timbre': data_api.get('timbre'),
        'secuencia_utilizada': data_api.get('secuencia_utilizada'),
        'encf': data_api.get('numero'),
        'id': data_api.get('id'),
        'track_id': data_api.get('track_id'),
        'tipo': data_api.get('tipo'),
        'total': data_api.get('total'),
        'fecha': data_api.get('fecha'),
    })


# ---------------------------------------------------------------------------
# Consulta estado
# ---------------------------------------------------------------------------
def _flow_consulta_estado(args, step, last_resp):
    if step == 0:
        lista = args.get('comprobantes')
        if not isinstance(lista, list):
            return _fail('motor.consulta_estado.comprobantes_requeridos')
        if len(lista) > 100:
            return _fail('motor.consulta_estado.maximo_100', {'recibidos': len(lista)})
        return _http('consulta_estado', {'comprobantes': lista}, use_token=True, next_step=1)
    return _done(_resp_data(last_resp))


# ---------------------------------------------------------------------------
# Descarga XMLs
# ---------------------------------------------------------------------------
def _flow_descarga_xmls(args, step, last_resp):
    if step == 0:
        fecha_desde = _str(args, 'fecha_desde').strip()
        fecha_hasta = _str(args, 'fecha_hasta').strip()
        if not _is_fecha_yyyy_mm_dd(fecha_desde):
            return _fail('motor.descarga_xmls.fecha_desde_invalida', {'valor': fecha_desde})
        if not _is_fecha_yyyy_mm_dd(fecha_hasta):
            return _fail('motor.descarga_xmls.fecha_hasta_invalida', {'valor': fecha_hasta})
        tipos = args.get('tipos')
        data: dict = {'fecha_desde': fecha_desde, 'fecha_hasta': fecha_hasta}
        if isinstance(tipos, list) and tipos:
            data['tipos'] = tipos
        return _http('ecf_documentos_list', data, use_token=True, next_step=1)
    return _done(_resp_data(last_resp))


# ---------------------------------------------------------------------------
# Helpers internos
# ---------------------------------------------------------------------------
def _resp_data(resp):
    if resp is None:
        return {}
    d = resp.get('data')
    return dict(d) if isinstance(d, dict) else {}


def _http(endpoint: str, data: dict, *, use_token: bool, next_step: int) -> str:
    return json.dumps({'kind': 'http', 'step': next_step, 'endpoint': endpoint,
                       'data': data, 'useToken': use_token})


def _done(result: dict, *, new_token=None) -> str:
    out: dict = {'kind': 'done', 'result': result}
    if new_token:
        out['newToken'] = new_token
    return json.dumps(out)


def _fail(code: str, data=None) -> str:
    return json.dumps({'kind': 'fail', 'code': code, 'data': data or {}})


def _str(m: dict, key: str, default: str = '') -> str:
    v = m.get(key)
    if v is None:
        return default
    return str(v)


def _num(m: dict, key: str, default: float) -> float:
    v = m.get(key)
    if v is None:
        return default
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def _fmt2(v: float) -> str:
    scaled = v * 100
    rounded = int(scaled + 0.5) if scaled >= 0 else int(scaled - 0.5)
    neg = rounded < 0
    abs_val = -rounded if neg else rounded
    entero = abs_val // 100
    cent = abs_val % 100
    return ('-' if neg else '') + f'{entero}.{cent:02d}'


def _fmt4(v: float) -> str:
    scaled = v * 10000
    rounded = int(scaled + 0.5) if scaled >= 0 else int(scaled - 0.5)
    neg = rounded < 0
    abs_val = -rounded if neg else rounded
    entero = abs_val // 10000
    dec = abs_val % 10000
    return ('-' if neg else '') + f'{entero}.{dec:04d}'


def _is_fecha_yyyy_mm_dd(s: str) -> bool:
    if len(s) != 10:
        return False
    if s[4] != '-' or s[7] != '-':
        return False
    try:
        y = int(s[0:4])
        m = int(s[5:7])
        d = int(s[8:10])
    except ValueError:
        return False
    return 2020 <= y <= 2100 and 1 <= m <= 12 and 1 <= d <= 31
