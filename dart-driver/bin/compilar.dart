// Compila un archivo .dart de driver a bytecode .evc.
// Uso: dart run bin/compilar.dart <fuente.dart> <salida.evc>

import 'dart:io';

import 'package:chalona_dart_driver/loader.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Uso: compilar.dart <fuente.dart> <salida.evc>');
    exit(2);
  }
  final fuente = File(args[0]).readAsStringSync();
  final bytes = compilarDriver(fuenteDart: fuente);
  File(args[1]).writeAsBytesSync(bytes);
  stderr.writeln('   ${bytes.length} bytes → ${args[1]}');
}
