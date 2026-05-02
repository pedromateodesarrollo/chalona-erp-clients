// PoC: patrón loader Fox aplicado a Dart con dart_eval
//
// Demuestra:
//   1. Compilar fuente Dart a bytecode .evc (servidor)
//   2. Cliente envía request con versión, recibe "actualizar" si no coincide
//   3. Cliente baja bytes, los cachea en disco, instancia driver
//   4. Hot-swap: publicar v2 en servidor → próximo request dispara update transparente
//   5. Persistencia: segundo arranque reusa cache local

import 'dart:io';
import 'dart:typed_data';

import 'package:chalona_dart_driver/loader.dart';
import 'package:chalona_dart_driver/server_simulado.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/stdlib/core.dart';

void titulo(String t) => print('\n=== $t ===');

void main() async {
  // ---------- SERVIDOR (en producción: tu API + BD) ----------
  final servidor = ServidorSimulado();

  final fuenteV1 = File('driver_src/driver_v1.dart').readAsStringSync();
  final fuenteV2 = File('driver_src/driver_v2.dart').readAsStringSync();

  servidor.publicarDriver(version: 'v1', fuenteDart: fuenteV1);

  // ---------- CLIENTE ----------
  final cache = DriverCache(Directory('.cache_drivers'));
  DriverHandle? driverActivo;

  /// Reproduce el patrón Fox: enviar doc con versión local; si no matchea,
  /// bajar nueva versión y reintentar. Sin polling, sin push.
  Future<Object?> enviarConDriver(
    Map<String, Object?> doc,
    String funcion,
    List<Object?> args,
  ) async {
    var intentos = 0;
    while (intentos < 2) {
      intentos++;

      final versionLocal = driverActivo?.version ?? 'v0';
      final res = servidor.procesar(version: versionLocal, doc: doc);

      if (res['code'] == 'actualizar') {
        final nuevaVersion = res['version_actual'] as String;
        print('   [cliente] versión local "$versionLocal" desfasada → '
            'bajando "$nuevaVersion"');

        Uint8List bytes;
        if (cache.has(nuevaVersion)) {
          print('   [cliente] cache hit, leyendo de disco');
          bytes = cache.read(nuevaVersion);
        } else {
          bytes = servidor.descargar(nuevaVersion);
          cache.write(nuevaVersion, bytes);
          print('   [cliente] descargado ${bytes.length} bytes y cacheado');
        }

        driverActivo = cargarDriver(bytes: bytes, version: nuevaVersion);
        print('   [cliente] driver activo = ${driverActivo!.version} '
            '(sha256=${driverActivo!.hash.substring(0, 12)}...)');
        continue; // reintenta request
      }

      // matchea → ejecuta lógica del driver
      final salida = driverActivo!.call(funcion, args);
      return _unwrap(salida);
    }
    throw StateError('no convergió tras 2 intentos');
  }

  // ---------- ESCENARIO 1: arranque en frío, baja v1 ----------
  titulo('Escenario 1: arranque frío con v1 publicado');
  var r1 = await enviarConDriver(
    {'tipo': '31'},
    'procesar',
    [$String('factura-001')],
  );
  print('=> $r1');

  r1 = await enviarConDriver(
    {'tipo': '31'},
    'sumar',
    [40, 2],
  );
  print('=> sumar(40,2) = $r1');

  r1 = await enviarConDriver(
    {'tipo': '31'},
    'validarFactura',
    [$String('{"monto":100}')],
  );
  print('=> validarFactura(monto=100) = $r1');

  r1 = await enviarConDriver(
    {'tipo': '31'},
    'validarFactura',
    [$String('{"monto":-5}')],
  );
  print('=> validarFactura(monto=-5) = $r1');

  // ---------- ESCENARIO 2: servidor publica v2, cliente actualiza solo ----------
  titulo('Escenario 2: servidor publica v2 → next request hot-swap');
  servidor.publicarDriver(version: 'v2', fuenteDart: fuenteV2);

  var r2 = await enviarConDriver(
    {'tipo': '31'},
    'procesar',
    [$String('factura-002 con tres palabras')],
  );
  print('=> $r2');

  r2 = await enviarConDriver(
    {'tipo': '31'},
    'sumar',
    [40, 2],
  );
  print('=> sumar(40,2) = $r2  (v2 introduce +1 a propósito)');

  // v2 ahora exige rnc
  r2 = await enviarConDriver(
    {'tipo': '31'},
    'validarFactura',
    [$String('{"monto":100}')],
  );
  print('=> validarFactura(monto=100, sin rnc) = $r2');

  r2 = await enviarConDriver(
    {'tipo': '31'},
    'validarFactura',
    [$String('{"monto":100,"rnc":"131-86268-1"}')],
  );
  print('=> validarFactura(monto=100, rnc=131-86268-1) = $r2');

  // ---------- ESCENARIO 3: persistencia ----------
  titulo('Escenario 3: archivos cacheados en .cache_drivers/');
  final archivos = Directory('.cache_drivers').listSync();
  for (final f in archivos) {
    final stat = f.statSync();
    print('   ${f.path} (${stat.size} bytes)');
  }

  print('\n[OK] PoC completado.');
}

Object? _unwrap(Object? v) {
  if (v is $Value) return v.$reified;
  return v;
}
