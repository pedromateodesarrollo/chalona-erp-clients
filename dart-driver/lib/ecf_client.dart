// Cliente HTTP para el API ecf-service. Espejo de Fox: el cliente shell es
// delgado y baja un *motor* (bytecode `.evc`) que controla TODA la lógica de
// comunicación + reglas. Cambios en el motor (validaciones, payload, nuevos
// flujos) se publican y se aplican sin recompilar el cliente.
//
// Métodos públicos:
//   - login(usuario, clave)
//   - enviaEcf(rnc, portal, json)
//   - consultaEstado(comprobantes)
//   - descargaXmls(fechaDesde, fechaHasta, {tipos})
//
// Internamente, cada método llama `_dispatch(fnName, args)` que:
//   1. Asegura motor cargado (`_ensureMotor`).
//   2. Trampolín: motor.procesar(estadoJson) devuelve {kind:'http'|'done'|'fail'}.
//   3. Si http → shell ejecuta POST y alimenta respuesta al motor.
//   4. Si done → devuelve `result` (y guarda `newToken` si vino).
//   5. Si fail → lanza `EcfApiError`.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:http/http.dart' as http;

import 'documento_ecf.dart';
import 'loader.dart';

export 'documento_ecf.dart';

// ---------------------------------------------------------------------------
// Tipos públicos
// ---------------------------------------------------------------------------

/// Excepción cuando el API o el motor devuelve un fallo.
class EcfApiError implements Exception {
  final String code;
  final Map<String, dynamic> data;
  final int? statusCode;
  EcfApiError(this.code, [this.data = const {}, this.statusCode]);

  @override
  String toString() =>
      'EcfApiError(code=$code'
      '${statusCode != null ? ', status=$statusCode' : ''}'
      '${data.isNotEmpty ? ', data=$data' : ''})';
}

/// Metadata del motor publicado en el servidor (bytecode `.evc`).
class MotorMeta {
  final int version;
  final String entorno;
  final String hashSha256;
  final int tamano;

  MotorMeta({
    required this.version,
    required this.entorno,
    required this.hashSha256,
    required this.tamano,
  });

  factory MotorMeta.fromJson(Map<String, Object?> j) => MotorMeta(
    version: (j['version'] as num).toInt(),
    entorno: j['entorno'] as String,
    hashSha256: j['hash_sha256'] as String,
    tamano: (j['tamano'] as num).toInt(),
  );

  @override
  String toString() =>
      'MotorMeta(v=$version entorno=$entorno tam=$tamano '
      'sha=${hashSha256.substring(0, 12)}...)';
}

/// Archivo recibido en una respuesta (p.ej. ZIP de XMLs en `descargaXmls`).
class EcfFile {
  final String fileName;
  final Uint8List bytes;
  EcfFile({required this.fileName, required this.bytes});
}

/// Resultado de [EcfClient.descargaXmls]: data + archivos.
class EcfDescargaXmlsResult {
  final Map<String, dynamic> data;
  final List<EcfFile> files;
  EcfDescargaXmlsResult({required this.data, required this.files});
}

/// Resultado interno de un dispatch (datos + archivos del último HTTP, si hubo).
class _DispatchResult {
  final Map<String, dynamic> result;
  final List<EcfFile> files;
  _DispatchResult({required this.result, required this.files});
}

// ---------------------------------------------------------------------------
// EcfClient
// ---------------------------------------------------------------------------

/// Cliente HTTP shell para `ecf-service`. Toda la lógica concreta vive en el
/// *motor* (`dart_cliente_driver` bytecode) que se baja vía HTTP en el primer
/// uso (lazy) y queda en memoria.
class EcfClient {
  final String baseUrl;
  final String motorEntorno;
  String? _token;
  final http.Client _http;
  final Duration timeout;

  // Motor lazy
  DriverHandle? _motor;
  MotorMeta? _motorMeta;

  EcfClient({
    String baseUrl = 'https://ecf-service.vicortiz.com',
    String motorEntorno = 'produccion',
    String? token,
    Duration timeout = const Duration(seconds: 60),
    http.Client? httpClient,
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       motorEntorno = motorEntorno,
       _token = token,
       _http = httpClient ?? http.Client(),
       timeout = timeout;

  /// Token actual (incluye prefijo `Bearer `). Disponible tras [login].
  String? get token => _token;

  /// Limpia el token (para forzar re-login).
  void clearToken() => _token = null;

  /// Metadata del motor cargado (null si aún no se hizo `ensureMotor`).
  MotorMeta? get motorMeta => _motorMeta;

  /// Cierra el cliente HTTP subyacente.
  void close() => _http.close();

  // ===========================================================================
  // API pública: métodos high-level (delegan al motor via _dispatch)
  // ===========================================================================

  /// Autentica usuario y guarda token interno. Devuelve `data` del login.
  Future<Map<String, dynamic>> login(
    String usuario,
    String clave, {
    String app = 'ecf',
  }) async {
    final r = await _dispatch('login', {
      'usuario': usuario,
      'clave': clave,
      'app': app,
    });
    return r.result;
  }

  /// Envía un e-CF a la DGII pasando el payload DGII completo (`json`).
  /// Requiere [login] previo. Usar este método si ya tienes el payload con
  /// estructura DGII (`Encabezado`, `DetallesItems`, etc.) listo.
  /// Si trabajas con `DocumentoEcf`, usa [enviaEcfDesde] para que el motor
  /// arme el payload por ti.
  Future<Map<String, dynamic>> enviaEcf({
    required String rnc,
    required String portal,
    required Map<String, dynamic> json,
  }) async {
    final r = await _dispatch('enviaEcf', {
      'rnc': rnc,
      'portal': portal,
      'json': json,
    });
    return r.result;
  }

  /// Envía un [DocumentoEcf] (formato espejo de cursores Fox). El motor mapea
  /// el documento al payload DGII, lo envía y devuelve el mismo documento
  /// enriquecido con campos de resultado (`encf`, `estado`, `codigoSeguridad`,
  /// `timbre`, `fechaFirma`, `secuenciaUtilizada`).
  ///
  /// - [portal]: `'ecf'` (producción DGII) o `'testecf'` (pruebas DGII).
  Future<DocumentoEcf> enviaEcfDesde(
    DocumentoEcf documento, {
    required String portal,
  }) async {
    // Validación anticipada: prefijo eNCF debe coincidir con TipoeCF (DGII error 75).
    final encfVal = documento.encf?.trim() ?? '';
    final fiscalVal = documento.fiscal.trim();
    if (encfVal.isNotEmpty && fiscalVal.isNotEmpty) {
      final prefijoCorrecto = 'E$fiscalVal';
      if (!encfVal.startsWith(prefijoCorrecto)) {
        throw ArgumentError(
          'eNCF "$encfVal" no coincide con TipoeCF $fiscalVal '
          '(prefijo esperado: $prefijoCorrecto). DGII error 75.',
        );
      }
    }
    final r = await _dispatch('enviaEcfDesdeDoc', {
      'documento': documento.toMap(),
      'portal': portal,
    });
    // Enriquecer el documento original con campos de resultado.
    final res = r.result;
    documento.encf = (res['encf'] as String?) ?? documento.encf;
    documento.estado = res['estado'] as String?;
    documento.estadoDescripcion = res['estado_descripcion'] as String?;
    documento.codigoSeguridad = res['codigo_seguridad'] as String?;
    documento.fechaFirma = res['fecha_firma'] as String?;
    documento.timbre = res['timbre'] as String?;
    final secU = res['secuencia_utilizada'];
    if (secU is bool) {
      documento.secuenciaUtilizada = secU;
    } else if (secU is num) {
      documento.secuenciaUtilizada = secU.toInt() != 0;
    }
    documento.momento = res['momento'] as String?;
    documento.respuestaMensajes = res['respuesta_mensajes'] as String?;
    return documento;
  }

  /// Consulta estado de e-NCFs (máx 100).
  Future<List<dynamic>> consultaEstado(List<String> comprobantes) async {
    final r = await _dispatch('consultaEstado', {
      'comprobantes': comprobantes,
    });
    return (r.result['result'] as List?) ?? const [];
  }

  /// Descarga ZIP con XMLs de un rango (formato YYYY-MM-DD).
  Future<EcfDescargaXmlsResult> descargaXmls({
    required String fechaDesde,
    required String fechaHasta,
    List<String>? tipos,
  }) async {
    final r = await _dispatch('descargaXmls', {
      'fecha_desde': fechaDesde,
      'fecha_hasta': fechaHasta,
      if (tipos != null && tipos.isNotEmpty) 'tipos': tipos,
    });
    return EcfDescargaXmlsResult(data: r.result, files: r.files);
  }

  // ===========================================================================
  // Motor (público, sin token)
  // ===========================================================================

  /// Devuelve metadata del motor activo (versión, hash, tamaño). Sin bytes.
  Future<MotorMeta?> lookupMotor({String? entorno}) async {
    try {
      final raw = await _httpPost(
        'dart_cliente_driver_lookup',
        {'entorno': entorno ?? motorEntorno},
        useToken: false,
      );
      final data = (raw['data'] as Map).cast<String, Object?>();
      return MotorMeta.fromJson(data);
    } on EcfApiError catch (e) {
      if (e.code == 'dart_cliente_driver.no_disponible') return null;
      rethrow;
    }
  }

  /// Descarga bytes del motor.
  Future<Uint8List> descargarMotor({String? entorno, int? version}) async {
    final raw = await _httpPost(
      'dart_cliente_driver_descargar',
      {
        'entorno': entorno ?? motorEntorno,
        if (version != null) 'version': version.toString(),
      },
      useToken: false,
    );
    final data = (raw['data'] as Map).cast<String, Object?>();
    final b64Raw = (data['bytes_b64'] as String?) ?? '';
    final b64 = b64Raw.replaceAll(RegExp(r'\s'), '');
    return base64Decode(b64);
  }

  /// Asegura que el motor esté cargado en memoria. Si ya está, no hace nada.
  /// Si la versión activa cambió, vuelve a bajarlo (no implementado aquí: el
  /// usuario puede llamar `clearMotor()` y llamar de nuevo).
  Future<void> ensureMotor() async {
    if (_motor != null) return;
    final meta = await lookupMotor();
    if (meta == null) {
      throw EcfApiError('motor.no_disponible', {'entorno': motorEntorno});
    }
    final bytes = await descargarMotor();
    final h = cargarDriver(bytes: bytes, version: 'v${meta.version}');
    if (h.hash != meta.hashSha256) {
      throw EcfApiError('motor.hash_mismatch', {
        'esperado': meta.hashSha256,
        'recibido': h.hash,
      });
    }
    _motor = h;
    _motorMeta = meta;
  }

  /// Descarga el motor en memoria. Útil para forzar re-fetch.
  void clearMotor() {
    _motor = null;
    _motorMeta = null;
  }

  // ===========================================================================
  // Trampolín shell ↔ motor
  // ===========================================================================

  Future<_DispatchResult> _dispatch(
    String fnName,
    Map<String, dynamic> args,
  ) async {
    // Auto-update: si en mitad del flow detectamos motor.version_desactualizada,
    // recargamos motor y reiniciamos desde step 0. Limitamos reintentos para
    // evitar loops si server y BD están desincronizados.
    var reintentos = 0;
    while (true) {
      try {
        return await _dispatchOnce(fnName, args);
      } on EcfApiError catch (e) {
        if (e.code == 'dart_cliente_driver.version_desactualizada' &&
            reintentos < 1) {
          reintentos++;
          // Forzar re-fetch del motor desde el server.
          clearMotor();
          continue;
        }
        rethrow;
      }
    }
  }

  Future<_DispatchResult> _dispatchOnce(
    String fnName,
    Map<String, dynamic> args,
  ) async {
    await ensureMotor();
    final motor = _motor!;

    Map<String, Object?>? lastResp;
    List<EcfFile> lastFiles = const [];
    int step = 0;

    while (true) {
      final estado = <String, Object?>{
        'fnName': fnName,
        'args': args,
        'token': _token,
        'step': step,
        'lastResp': lastResp,
      };
      final raw = motor.call('procesar', [$String(jsonEncode(estado))]);
      final stepJson = (raw is $Value ? raw.$reified : raw) as String;
      final stepMap = jsonDecode(stepJson) as Map<String, dynamic>;
      final kind = stepMap['kind'];

      if (kind == 'done') {
        final result =
            (stepMap['result'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
        final newToken = stepMap['newToken'] as String?;
        if (newToken != null && newToken.isNotEmpty) {
          _token = newToken;
        }
        return _DispatchResult(result: result, files: lastFiles);
      }

      if (kind == 'fail') {
        final code = (stepMap['code'] as String?) ?? 'motor.error_desconocido';
        final dataErr =
            (stepMap['data'] as Map?)?.cast<String, dynamic>() ?? {};
        throw EcfApiError(code, dataErr);
      }

      if (kind == 'http') {
        final endpoint = stepMap['endpoint'] as String;
        final data =
            (stepMap['data'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
        final useToken = stepMap['useToken'] != false;
        step = (stepMap['step'] as num?)?.toInt() ?? (step + 1);

        final respFull = await _httpPost(endpoint, data, useToken: useToken);
        lastFiles = _parseFiles(respFull);
        lastResp = {
          'ok': respFull['ok'],
          'message': respFull['message'],
          'data': respFull['data'],
        };
        continue;
      }

      throw EcfApiError('motor.kind_desconocido', {'kind': kind?.toString()});
    }
  }

  // ===========================================================================
  // HTTP de bajo nivel (usado por motor lookup/descargar y por el trampolín)
  // ===========================================================================

  Future<Map<String, dynamic>> _httpPost(
    String endpoint,
    Map<String, dynamic> data, {
    required bool useToken,
  }) async {
    final url = Uri.parse('$baseUrl/');
    // Inyectar versión + entorno del motor en cada request para que el server
    // detecte motor desactualizado (código `dart_cliente_driver.version_desactualizada`).
    // Excepción: las llamadas al propio endpoint de driver (lookup/descargar)
    // no inyectan versión — provocaría loop.
    final esMotorEndpoint = endpoint == 'dart_cliente_driver_lookup' ||
        endpoint == 'dart_cliente_driver_descargar';
    final dataConVersion = <String, dynamic>{...data};
    if (!esMotorEndpoint && _motorMeta != null) {
      dataConVersion['dart_driver_version'] = _motorMeta!.version;
      dataConVersion['dart_driver_entorno'] = _motorMeta!.entorno;
    }
    final body = jsonEncode({'request': endpoint, 'data': dataConVersion});
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (useToken && _token != null) {
      headers['Authorization'] = _token!;
    }

    late http.Response resp;
    try {
      resp = await _http
          .post(url, headers: headers, body: body)
          .timeout(timeout);
    } catch (e) {
      throw EcfApiError('http.error', {'detail': e.toString()});
    }

    Map<String, dynamic> out;
    try {
      out = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw EcfApiError(
        'respuesta_no_json',
        {
          'text': resp.body.length > 500
              ? resp.body.substring(0, 500)
              : resp.body,
        },
        resp.statusCode,
      );
    }

    final ok = out['ok'] == true;
    if (!ok) {
      final msg = (out['message'] as String?) ?? 'error_desconocido';
      final dataErr = (out['data'] as Map?)?.cast<String, dynamic>() ?? {};
      throw EcfApiError(msg, dataErr, resp.statusCode);
    }
    return out;
  }

  List<EcfFile> _parseFiles(Map<String, dynamic> respFull) {
    final raw = respFull['files'];
    if (raw is! List) return const [];
    final out = <EcfFile>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, Object?>.from(item);
      final name = (m['fileName'] as String?)?.trim() ?? '';
      final b64Raw = (m['content'] as String?) ?? '';
      if (name.isEmpty || b64Raw.isEmpty) continue;
      final b64 = b64Raw.replaceAll(RegExp(r'\s'), '');
      out.add(EcfFile(fileName: name, bytes: base64Decode(b64)));
    }
    return out;
  }
}
