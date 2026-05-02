// PostgresDriverSource: lookup + descarga del driver Dart desde data.dart_cliente_driver.
// Reemplaza ServidorSimulado con conexión real.
//
// Uso típico:
//   final source = PostgresDriverSource(
//     host: 'localhost', port: 5433, database: 'test',
//     username: 'pedro', password: 'camila',
//     entorno: 'test',
//   );
//   final meta = await source.lookup();
//   if (meta.version != driverActivo?.version) {
//     final bytes = await source.descargar(meta.version);
//     // ... cargar en runtime
//   }

import 'dart:convert';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';

class DriverMeta {
  final int version;
  final String entorno;
  final String hashSha256;
  final int tamano;

  DriverMeta({
    required this.version,
    required this.entorno,
    required this.hashSha256,
    required this.tamano,
  });

  factory DriverMeta.fromJson(Map<String, Object?> j) => DriverMeta(
        version: (j['version'] as num).toInt(),
        entorno: j['entorno'] as String,
        hashSha256: j['hash_sha256'] as String,
        tamano: (j['tamano'] as num).toInt(),
      );

  @override
  String toString() =>
      'DriverMeta(v=$version entorno=$entorno tam=$tamano sha=${hashSha256.substring(0, 12)}...)';
}

class PostgresDriverSource {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final String entorno;

  Connection? _conn;

  PostgresDriverSource({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.entorno,
  }) {
    if (entorno != 'test' && entorno != 'produccion') {
      throw ArgumentError('entorno debe ser test o produccion');
    }
  }

  Future<Connection> _connect() async {
    if (_conn != null) return _conn!;
    _conn = await Connection.open(
      Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    return _conn!;
  }

  Future<void> close() async {
    await _conn?.close();
    _conn = null;
  }

  /// Llamada barata: devuelve metadata (versión, hash, tamaño). Sin bytes.
  Future<DriverMeta?> lookup() async {
    final c = await _connect();
    final r = await c.execute(
      r"""
      SELECT ok, message, data::text
      FROM fn.dart_cliente_driver_lookup(jsonb_build_object(
        'session', jsonb_build_object('trusted', true),
        'entorno', $1::text
      ))
      """,
      parameters: [entorno],
    );
    final row = r.first;
    final ok = row[0] as bool;
    final message = row[1] as String;
    final dataJson = row[2] as String;
    if (!ok) {
      if (message == 'dart_cliente_driver.no_disponible') return null;
      throw StateError('lookup falló: $message');
    }
    final data = jsonDecode(dataJson) as Map<String, Object?>;
    return DriverMeta.fromJson(data);
  }

  /// Llamada cara: descarga bytes de la versión activa (o específica).
  Future<Uint8List> descargar({int? version}) async {
    final c = await _connect();
    final r = await c.execute(
      r"""
      SELECT ok, message, data::text
      FROM fn.dart_cliente_driver_descargar(jsonb_build_object(
        'session', jsonb_build_object('trusted', true),
        'entorno', $1::text,
        'version', $2::text
      ))
      """,
      parameters: [entorno, version?.toString() ?? ''],
    );
    final row = r.first;
    final ok = row[0] as bool;
    final message = row[1] as String;
    final dataJson = row[2] as String;
    if (!ok) throw StateError('descarga falló: $message');
    final data = jsonDecode(dataJson) as Map<String, Object?>;
    // Postgres encode(..., 'base64') intercala '\n' cada 76 chars
    final b64 = (data['bytes_b64'] as String).replaceAll(RegExp(r'\s'), '');
    return base64Decode(b64);
  }
}
