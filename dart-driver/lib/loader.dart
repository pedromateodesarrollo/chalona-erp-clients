import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dart_eval/dart_eval.dart';

/// Resultado de cargar un driver.
class DriverHandle {
  final String version;
  final String hash;
  final Runtime runtime;
  final String packageUri;

  DriverHandle({
    required this.version,
    required this.hash,
    required this.runtime,
    required this.packageUri,
  });

  /// Llama una función top-level del driver.
  Object? call(String functionName, List<Object?> args) {
    return runtime.executeLib(packageUri, functionName, args);
  }
}

/// Compila código Dart fuente a bytecode .evc.
/// Esto correría normalmente en el servidor cuando se publica una versión.
Uint8List compilarDriver({
  required String fuenteDart,
  String packageName = 'driver',
  String fileName = 'main.dart',
}) {
  final compiler = Compiler();
  final program = compiler.compile({
    packageName: {fileName: fuenteDart},
  });
  return program.write();
}

/// Carga bytes de driver en runtime fresco.
DriverHandle cargarDriver({
  required Uint8List bytes,
  required String version,
  String packageName = 'driver',
  String fileName = 'main.dart',
}) {
  final hash = sha256.convert(bytes).toString();
  final runtime = Runtime(ByteData.sublistView(bytes));
  return DriverHandle(
    version: version,
    hash: hash,
    runtime: runtime,
    packageUri: 'package:$packageName/$fileName',
  );
}

/// Cache local de drivers descargados (simula disco/CDN del cliente).
class DriverCache {
  final Directory dir;
  DriverCache(this.dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  File _file(String version) => File('${dir.path}/driver-$version.evc');

  bool has(String version) => _file(version).existsSync();

  Uint8List read(String version) => _file(version).readAsBytesSync();

  void write(String version, Uint8List bytes) {
    _file(version).writeAsBytesSync(bytes);
  }
}
