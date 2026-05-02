import 'dart:typed_data';

import 'loader.dart';

/// Servidor simulado: guarda versión actual del driver + bytes.
/// En producción esto sería Postgres / CDN / S3.
class ServidorSimulado {
  String _versionActual = 'v0';
  Uint8List _bytesActuales = Uint8List(0);

  String get versionActual => _versionActual;

  /// Publica nueva versión del driver (recompila fuente).
  void publicarDriver({required String version, required String fuenteDart}) {
    _versionActual = version;
    _bytesActuales = compilarDriver(fuenteDart: fuenteDart);
  }

  /// Endpoint estilo Fox: cliente envía documento + versión.
  /// Si versión coincide, procesa. Si no, devuelve "actualizar".
  Map<String, Object?> procesar({
    required String version,
    required Map<String, Object?> doc,
  }) {
    if (version != _versionActual) {
      return {
        'ok': false,
        'code': 'actualizar',
        'version_actual': _versionActual,
        'bytes_size': _bytesActuales.length,
      };
    }
    return {'ok': true, 'doc': doc};
  }

  /// Endpoint para bajar bytes de una versión.
  Uint8List descargar(String version) {
    if (version != _versionActual) {
      throw StateError('versión $version no es la actual ($_versionActual)');
    }
    return _bytesActuales;
  }
}
