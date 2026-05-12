// Motor v1 — controla TODA la lógica de comunicación con el API ecf-service.
//
// Cliente shell (EcfClient) baja este bytecode y delega cada operación de alto
// nivel (login, enviaEcf, consultaEstado, descargaXmls) al motor mediante un
// trampolín: motor devuelve qué request HTTP hacer, shell ejecuta, motor recibe
// la respuesta y decide siguiente paso (otro HTTP, terminar, fallar).
//
// Shell ↔ Motor protocol:
//   Input estadoJson:
//     {
//       "fnName":   "login" | "enviaEcf" | "consultaEstado" | "descargaXmls",
//       "args":     {...},                         // args del programador
//       "token":    "Bearer ..." | null,           // token actual del shell
//       "step":     0,                             // paso del flujo
//       "lastResp": {...} | null                   // respuesta HTTP previa
//     }
//
//   Output stepJson:
//     - {"kind":"http", "step":N+1, "endpoint":"...", "data":{...}, "useToken":bool}
//     - {"kind":"done", "result":{...}, "newToken":"..."?}
//     - {"kind":"fail", "code":"...", "data":{...}?}
//
// Para añadir una nueva operación, solo se modifica este archivo, se publica
// nueva versión a `data.dart_cliente_driver` y los clientes la bajan en el
// próximo lookup. Cliente shell no recompila.

import 'dart:convert';

String procesar(String estadoJson) {
  final estadoDyn = jsonDecode(estadoJson);
  if (estadoDyn == null || !(estadoDyn is Map)) {
    return _fail('motor.estado_invalido');
  }
  final estado = Map<String, Object?>.from(estadoDyn as Map);
  final fnName = _str(estado, 'fnName');
  final argsRaw = estado['args'];
  final args = argsRaw is Map
      ? Map<String, Object?>.from(argsRaw)
      : <String, Object?>{};
  final stepRaw = estado['step'];
  final step = stepRaw is num ? stepRaw.toInt() : 0;
  final lastRespRaw = estado['lastResp'];
  final lastResp = lastRespRaw is Map
      ? Map<String, Object?>.from(lastRespRaw)
      : null;

  if (fnName == 'login') {
    return _flowLogin(args, step, lastResp);
  } else if (fnName == 'enviaEcf') {
    return _flowEnviaEcf(args, step, lastResp);
  } else if (fnName == 'enviaEcfDesdeDoc') {
    return _flowEnviaEcfDesdeDoc(args, step, lastResp);
  } else if (fnName == 'consultaEstado') {
    return _flowConsultaEstado(args, step, lastResp);
  } else if (fnName == 'descargaXmls') {
    return _flowDescargaXmls(args, step, lastResp);
  } else if (fnName == 'anularRangos') {
    return _flowAnularRangos(args, step, lastResp);
  } else if (fnName == 'consultaApi') {
    return _flowConsultaApi(args, step, lastResp);
  }
  return _fail('motor.fn_desconocida', {'fnName': fnName});
}

// ---------------------------------------------------------------------------
// Anular rangos de e-NCF (servicio DGII AnulacionECF, vía server-ecf).
// args: { rnc, portal, tipo, rangos:[{desde,hasta},...] }
// ---------------------------------------------------------------------------
String _flowAnularRangos(
  Map<String, Object?> args,
  int step,
  Map<String, Object?>? lastResp,
) {
  if (step == 0) {
    final portal = _str(args, 'portal').trim();
    final tipo = _str(args, 'tipo').trim();
    final rangos = args['rangos'];
    if (portal != 'ecf' && portal != 'testecf' && portal != 'certecf') {
      return _fail('motor.anular_rangos.portal_invalido', {'portal': portal});
    }
    if (tipo.isEmpty) {
      return _fail('motor.anular_rangos.tipo_requerido');
    }
    if (rangos is! List || rangos.isEmpty) {
      return _fail('motor.anular_rangos.rangos_requeridos');
    }
    return _http('ecf_anular_rangos', {
      'portal': portal,
      'tipo': tipo,
      'rangos': rangos,
    }, useToken: true, nextStep: 1);
  }
  return _done(_respData(lastResp));
}

// ---------------------------------------------------------------------------
// Macro genérica: invoca cualquier endpoint del server-ecf sin necesidad de
// recompilar el shell. Toda función nueva del servidor se accede vía esta.
// args: { request:"endpoint_id", data:{...}, useToken:bool? (default true) }
// ---------------------------------------------------------------------------
String _flowConsultaApi(
  Map<String, Object?> args,
  int step,
  Map<String, Object?>? lastResp,
) {
  if (step == 0) {
    final endpoint = _str(args, 'request').trim();
    if (endpoint.isEmpty) {
      return _fail('motor.consulta_api.request_requerido');
    }
    final raw = args['data'];
    final data = raw is Map
        ? Map<String, Object?>.from(raw)
        : <String, Object?>{};
    final useTokenRaw = args['useToken'];
    final useToken = useTokenRaw is bool ? useTokenRaw : true;
    return _http(endpoint, data, useToken: useToken, nextStep: 1);
  }
  return _done(_respData(lastResp));
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------
String _flowLogin(
  Map<String, Object?> args,
  int step,
  Map<String, Object?>? lastResp,
) {
  if (step == 0) {
    final usuario = _str(args, 'usuario').trim();
    final clave = _str(args, 'clave');
    final appRaw = _str(args, 'app').trim();
    final app = appRaw.isEmpty ? 'ecf' : appRaw;
    if (usuario.isEmpty) return _fail('motor.login.usuario_requerido');
    if (clave.isEmpty) return _fail('motor.login.clave_requerida');
    return _http('sistema_login', {
      'app': app,
      'usuario': usuario,
      'clave': clave,
    }, useToken: false, nextStep: 1);
  }
  // step 1: tenemos respuesta del login
  final data = _respData(lastResp);
  final tokenStr = _str(data, 'token');
  final token = tokenStr.isEmpty ? null : tokenStr;
  return _done(data, newToken: token);
}

// ---------------------------------------------------------------------------
// Envía e-CF
// ---------------------------------------------------------------------------
String _flowEnviaEcf(
  Map<String, Object?> args,
  int step,
  Map<String, Object?>? lastResp,
) {
  if (step == 0) {
    final rnc = _str(args, 'rnc').trim();
    final portal = _str(args, 'portal').trim();
    final json = args['json'];
    if (rnc.isEmpty) return _fail('motor.envia_ecf.rnc_requerido');
    if (portal != 'ecf' && portal != 'testecf') {
      return _fail('motor.envia_ecf.portal_invalido', {'portal': portal});
    }
    if (json is! Map) {
      return _fail('motor.envia_ecf.json_requerido');
    }
    return _http('envia_ecf', {
      'rnc': rnc,
      'portal': portal,
      'json': json,
    }, useToken: true, nextStep: 1);
  }
  // step 1: respuesta del envío
  return _done(_respData(lastResp));
}

// ---------------------------------------------------------------------------
// Envía e-CF desde DocumentoEcf (formato cursores Fox).
// Motor mapea documento → payload DGII y dispara HTTP.
// ---------------------------------------------------------------------------
String _flowEnviaEcfDesdeDoc(
  Map<String, Object?> args,
  int step,
  Map<String, Object?>? lastResp,
) {
  if (step == 0) {
    final docRaw = args['documento'];
    final portal = _str(args, 'portal').trim();
    if (docRaw == null || !(docRaw is Map)) {
      return _fail('motor.envia_doc.documento_requerido');
    }
    if (portal != 'ecf' && portal != 'testecf') {
      return _fail('motor.envia_doc.portal_invalido', {'portal': portal});
    }
    final doc = Map<String, Object?>.from(docRaw as Map);

    // --- Validaciones mínimas ---
    final fiscal = _str(doc, 'fiscal').trim();
    if (fiscal.isEmpty) {
      return _fail('motor.envia_doc.fiscal_requerido');
    }
    if (fiscal != '31' && fiscal != '32' && fiscal != '33' && fiscal != '34') {
      return _fail('motor.envia_doc.tipo_no_soportado_aun', {'fiscal': fiscal});
    }

    final emisorRaw = doc['emisor'];
    final emisor = emisorRaw is Map
        ? Map<String, Object?>.from(emisorRaw)
        : null;
    if (emisor == null) return _fail('motor.envia_doc.emisor_requerido');
    final emisorRnc = _str(emisor, 'rnc').trim();
    if (emisorRnc.isEmpty) return _fail('motor.envia_doc.emisor_rnc_requerido');

    // tipo 31 requiere comprador identificado
    final compradorRaw = doc['comprador'];
    final comprador = compradorRaw is Map
        ? Map<String, Object?>.from(compradorRaw)
        : null;
    if (fiscal == '31' && comprador == null) {
      return _fail('motor.envia_doc.comprador_requerido_31');
    }

    final lineas = (doc['lineas'] as List?) ?? <Object?>[];
    if (lineas.isEmpty) return _fail('motor.envia_doc.sin_lineas');

    // --- Construir payload DGII ---
    final fechaEmision = _str(doc, 'fecha');
    final encf = _str(doc, 'encf');
    final moneda = _str(doc, 'moneda', 'DOP');
    final tasa = _numFromMap(doc, 'tasa', 1);

    final detallesItems = <Map<String, Object?>>[];
    var nLinea = 1;
    for (final lineaRaw in lineas) {
      if (lineaRaw is Map) {
        final l = Map<String, Object?>.from(lineaRaw);
        final cantidad = _numFromMap(l, 'cantidad', 0);
        final precio = _numFromMap(l, 'precio', 0);
        final monto = cantidad * precio;
        final esServicio = _numFromMap(l, 'mercs_servicio', 1).toInt() == 2;
        final itbisLinea = _numFromMap(l, 'itbis', 0);
        // IndicadorFacturacion DGII: '1' gravado tasa 18%, '2' tasa 16%,
        // '3' tasa 0% (exonerado), '4' exento.
        final indFact = itbisLinea > 0 ? '1' : '4';
        detallesItems.add({
          'NumeroLinea': nLinea.toString(),
          'IndicadorFacturacion': indFact,
          'NombreItem': _str(l, 'descrip'),
          'IndicadorBienoServicio': esServicio ? '2' : '1',
          'CantidadItem': _fmt4(cantidad),
          'PrecioUnitarioItem': _fmt2(precio),
          'MontoItem': _fmt2(monto),
        });
        nLinea++;
      }
    }

    // FechaVencimientoSecuencia: usar override del doc o default 31-12-2099.
    var fechaVenceSec = _str(doc, 'vence_fiscal');
    if (fechaVenceSec.isEmpty) {
      fechaVenceSec = '31-12-2099';
    }

    final idDoc = <String, Object?>{
      'TipoeCF': fiscal,
      'eNCF': encf,
      'FechaVencimientoSecuencia': fechaVenceSec,
    };
    if (fiscal == '31' || fiscal == '32' || fiscal == '33' || fiscal == '34') {
      idDoc['IndicadorMontoGravado'] = '0';
    }
    if (fiscal == '31') {
      idDoc['TipoIngresos'] = '01';
      idDoc['TipoPago'] = '1';
    }

    final emisorMap = <String, Object?>{
      'RNCEmisor': emisorRnc,
      'RazonSocialEmisor': _str(emisor, 'nombre'),
    };
    final emisorDir = _str(emisor, 'direccion');
    if (emisorDir.isNotEmpty) {
      emisorMap['DireccionEmisor'] = emisorDir;
    }
    emisorMap['FechaEmision'] = fechaEmision;

    final encabezado = <String, Object?>{
      'Version': '1.0',
      'IdDoc': idDoc,
      'Emisor': emisorMap,
    };

    if (comprador != null) {
      final compMap = <String, Object?>{};
      final compRnc = _str(comprador, 'rnc');
      if (compRnc.isNotEmpty) {
        compMap['RNCComprador'] = compRnc;
      }
      compMap['RazonSocialComprador'] = _str(comprador, 'nombre');
      encabezado['Comprador'] = compMap;
    }

    final totalDoc = _numFromMap(doc, 'total', 0);
    final itbisDoc = _numFromMap(doc, 'itbis', 0);
    final valorDoc = _numFromMap(doc, 'valor', 0);
    final montoGravado = valorDoc > 0 ? valorDoc : (totalDoc - itbisDoc);
    encabezado['Totales'] = <String, Object?>{
      'MontoGravadoTotal': _fmt2(montoGravado),
      'MontoGravadoI1': _fmt2(montoGravado),
      'ITBIS1': '18',
      'TotalITBIS': _fmt2(itbisDoc),
      'TotalITBIS1': _fmt2(itbisDoc),
      'MontoTotal': _fmt2(totalDoc),
    };

    if (moneda != 'DOP') {
      encabezado['OtraMoneda'] = <String, Object?>{
        'TipoMoneda': moneda,
        'TipoCambio': _fmt4(tasa),
      };
    }

    final payload = <String, Object?>{
      'Encabezado': encabezado,
      'DetallesItems': detallesItems,
    };

    return _http('envia_ecf', {
      'rnc': emisorRnc,
      'portal': portal,
      'json': payload,
    }, useToken: true, nextStep: 1);
  }

  // step 1: respuesta del envío. Motor proyecta data en formato cursor.
  final dataApi = _respData(lastResp);
  // Mapear back a campos cursor Fox-style:
  final out = <String, Object?>{
    'estado': dataApi['estado'],
    'estado_descripcion': dataApi['estado_descripcion'],
    'codigo_seguridad': dataApi['codigo_seguridad'],
    'fecha_firma': dataApi['fecha_firma'],
    'timbre': dataApi['timbre'],
    'secuencia_utilizada': dataApi['secuencia_utilizada'],
    'encf': dataApi['numero'],
    // Pass-through extras
    'id': dataApi['id'],
    'track_id': dataApi['track_id'],
    'tipo': dataApi['tipo'],
    'total': dataApi['total'],
    'fecha': dataApi['fecha'],
  };
  return _done(out);
}

// ---------------------------------------------------------------------------
// Consulta estado
// ---------------------------------------------------------------------------
String _flowConsultaEstado(
  Map<String, Object?> args,
  int step,
  Map<String, Object?>? lastResp,
) {
  if (step == 0) {
    final lista = args['comprobantes'];
    if (lista is! List) {
      return _fail('motor.consulta_estado.comprobantes_requeridos');
    }
    if (lista.length > 100) {
      return _fail('motor.consulta_estado.maximo_100', {'recibidos': lista.length});
    }
    return _http('consulta_estado', {
      'comprobantes': lista,
    }, useToken: true, nextStep: 1);
  }
  return _done(_respData(lastResp));
}

// ---------------------------------------------------------------------------
// Descarga XMLs
// ---------------------------------------------------------------------------
String _flowDescargaXmls(
  Map<String, Object?> args,
  int step,
  Map<String, Object?>? lastResp,
) {
  if (step == 0) {
    final fechaDesde = _str(args, 'fecha_desde').trim();
    final fechaHasta = _str(args, 'fecha_hasta').trim();
    if (!_isFechaYyyyMmDd(fechaDesde)) {
      return _fail('motor.descarga_xmls.fecha_desde_invalida', {'valor': fechaDesde});
    }
    if (!_isFechaYyyyMmDd(fechaHasta)) {
      return _fail('motor.descarga_xmls.fecha_hasta_invalida', {'valor': fechaHasta});
    }
    final tipos = args['tipos'];
    final data = <String, Object?>{
      'fecha_desde': fechaDesde,
      'fecha_hasta': fechaHasta,
    };
    if (tipos is List && tipos.isNotEmpty) data['tipos'] = tipos;
    return _http('ecf_documentos_list', data, useToken: true, nextStep: 1);
  }
  // step 1: shell ya extrajo files → motor solo devuelve data tal cual
  return _done(_respData(lastResp));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
Map<String, Object?> _respData(Map<String, Object?>? resp) {
  if (resp == null) return <String, Object?>{};
  final d = resp['data'];
  if (d is Map) return Map<String, Object?>.from(d);
  return <String, Object?>{};
}

String _http(
  String endpoint,
  Map<String, Object?> data, {
  required bool useToken,
  required int nextStep,
}) {
  return jsonEncode({
    'kind': 'http',
    'step': nextStep,
    'endpoint': endpoint,
    'data': data,
    'useToken': useToken,
  });
}

String _done(Map<String, Object?> result, {String? newToken}) {
  final out = <String, Object?>{
    'kind': 'done',
    'result': result,
  };
  if (newToken != null && newToken.isNotEmpty) {
    out['newToken'] = newToken;
  }
  return jsonEncode(out);
}

String _fail(String code, [Map<String, Object?>? data]) {
  return jsonEncode({
    'kind': 'fail',
    'code': code,
    'data': data ?? <String, Object?>{},
  });
}

/// Lee String de un Map evitando `as String?` (que revienta en dart_eval
/// cuando el key no existe). Devuelve `def` si null, no-String, o vacío
/// (cuando emptyAsDef=true).
String _str(Map<String, Object?> m, String key, [String def = '']) {
  final v = m[key];
  if (v == null) return def;
  if (v is String) return v;
  return v.toString();
}

double _numFromMap(Map<String, Object?> m, String key, double def) {
  final v = m[key];
  if (v == null) return def;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? def;
}

String _fmt2(double v) {
  final scaled = v * 100;
  final rounded = (scaled >= 0 ? scaled + 0.5 : scaled - 0.5).toInt();
  final neg = rounded < 0;
  final abs = neg ? -rounded : rounded;
  final entero = abs ~/ 100;
  final cent = abs % 100;
  final centStr = cent < 10 ? '0$cent' : '$cent';
  return (neg ? '-' : '') + '$entero.$centStr';
}

String _fmt4(double v) {
  final scaled = v * 10000;
  final rounded = (scaled >= 0 ? scaled + 0.5 : scaled - 0.5).toInt();
  final neg = rounded < 0;
  final abs = neg ? -rounded : rounded;
  final entero = abs ~/ 10000;
  final dec = abs % 10000;
  var decStr = '$dec';
  while (decStr.length < 4) {
    decStr = '0$decStr';
  }
  return (neg ? '-' : '') + '$entero.$decStr';
}

bool _isFechaYyyyMmDd(String s) {
  if (s.length != 10) return false;
  if (s[4] != '-' || s[7] != '-') return false;
  final y = int.tryParse(s.substring(0, 4));
  final m = int.tryParse(s.substring(5, 7));
  final d = int.tryParse(s.substring(8, 10));
  if (y == null || m == null || d == null) return false;
  if (y < 2020 || y > 2100) return false;
  if (m < 1 || m > 12) return false;
  if (d < 1 || d > 31) return false;
  return true;
}
