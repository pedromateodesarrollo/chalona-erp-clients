// Cliente HTTP para el API ecf-service.
//
// Métodos públicos:
//   - login(usuario, clave)
//   - enviaEcf(rnc, portal, json)
//   - enviaEcfDesde(documento, portal)
//   - consultaEstado(comprobantes)
//   - descargaXmls(fechaDesde, fechaHasta, {tipos})
//
// Internamente, cada método llama _dispatch(fnName, args) que:
//   1. Llama procesar(estadoJson) del motor estático.
//   2. Si http → shell ejecuta POST y alimenta respuesta al motor.
//   3. Si done → devuelve result (y guarda newToken si vino).
//   4. Si fail → lanza EcfApiError.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'documento_ecf.dart';
import 'motor.dart';

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

class _DispatchResult {
  final Map<String, dynamic> result;
  final List<EcfFile> files;
  _DispatchResult({required this.result, required this.files});
}

// ---------------------------------------------------------------------------
// EcfClient
// ---------------------------------------------------------------------------

/// Cliente HTTP para `ecf-service`. Toda la lógica concreta vive en [motor.dart].
class EcfClient {
  final String baseUrl;
  String? _token;
  final http.Client _http;
  final Duration timeout;

  EcfClient({
    String baseUrl = 'https://ecf-service.vicortiz.com',
    String? token,
    Duration timeout = const Duration(seconds: 60),
    http.Client? httpClient,
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _token = token,
       _http = httpClient ?? http.Client(),
       timeout = timeout;

  /// Token actual (incluye prefijo `Bearer `). Disponible tras [login].
  String? get token => _token;

  /// Limpia el token (para forzar re-login).
  void clearToken() => _token = null;

  /// Cierra el cliente HTTP subyacente.
  void close() => _http.close();

  // ===========================================================================
  // API pública
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

  /// Envía un [DocumentoEcf] (formato espejo de cursores Fox).
  Future<DocumentoEcf> enviaEcfDesde(
    DocumentoEcf documento, {
    required String portal,
  }) async {
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
  // Trampolín shell ↔ motor
  // ===========================================================================

  Future<_DispatchResult> _dispatch(
    String fnName,
    Map<String, dynamic> args,
  ) async {
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
      final stepJson = procesar(jsonEncode(estado));
      final stepMap = jsonDecode(stepJson) as Map<String, dynamic>;
      final kind = stepMap['kind'];

      if (kind == 'done') {
        final result =
            (stepMap['result'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
        final newToken = stepMap['newToken'] as String?;
        if (newToken != null && newToken.isNotEmpty) _token = newToken;
        return _DispatchResult(result: result, files: lastFiles);
      }

      if (kind == 'fail') {
        final code =
            (stepMap['code'] as String?) ?? 'motor.error_desconocido';
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
  // HTTP de bajo nivel
  // ===========================================================================

  Future<Map<String, dynamic>> _httpPost(
    String endpoint,
    Map<String, dynamic> data, {
    required bool useToken,
  }) async {
    final url = Uri.parse('$baseUrl/');
    final body = jsonEncode({'request': endpoint, 'data': data});
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (useToken && _token != null) headers['Authorization'] = _token!;

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

    if (out['ok'] != true) {
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
