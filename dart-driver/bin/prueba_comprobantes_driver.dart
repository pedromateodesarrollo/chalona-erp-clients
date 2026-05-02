// prueba_comprobantes_driver.dart
//
// Demuestra cómo un programa cliente delega la pre-validación de comprobantes
// e-CF a un driver bajado dinámicamente desde BD test (data.dart_cliente_driver).
//
// Cliente AOT no contiene reglas de validación: las baja del servidor. Si
// publicas un driver nuevo, el próximo arranque (o re-lookup) lo trae sin
// recompilar el cliente.
//
// Uso:
//   dart run bin/prueba_comprobantes_driver.dart [RNC]
//   RNC default: 133084503

import 'dart:convert';

import 'package:chalona_dart_driver/loader.dart';
import 'package:chalona_dart_driver/postgres_source.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/stdlib/core.dart';

const _entorno = 'test';

List<Map<String, Object?>> _construirCasos(String rnc) => [
  {
    '__caso': 'Factura crédito fiscal OK',
    'tipo': '31',
    'fecha_emision': '15-04-2026',
    'rnc_emisor': rnc,
    'rnc_comprador': '101000001',
    'monto_total': 5000.00,
  },
  {
    '__caso': 'Factura crédito fiscal sin RNC comprador',
    'tipo': '31',
    'fecha_emision': '15-04-2026',
    'rnc_emisor': rnc,
    'monto_total': 5000.00,
  },
  {
    '__caso': 'Factura consumo (32) chiquita OK',
    'tipo': '32',
    'fecha_emision': '15-04-2026',
    'rnc_emisor': rnc,
    'monto_total': 1500.00,
  },
  {
    '__caso': 'Factura consumo (32) >= 250k sin comprador (debe rechazar v2)',
    'tipo': '32',
    'fecha_emision': '15-04-2026',
    'rnc_emisor': rnc,
    'monto_total': 350000.00,
  },
  {
    '__caso': 'Nota crédito (34) dentro de tope',
    'tipo': '34',
    'fecha_emision': '15-04-2026',
    'rnc_emisor': rnc,
    'rnc_comprador': '101000001',
    'monto_total': 500.00,
    'total_factura_referenciada': 400.00,
    'suma_nd_referenciadas': 200.00,
  },
  {
    '__caso': 'Nota crédito (34) excede tope',
    'tipo': '34',
    'fecha_emision': '15-04-2026',
    'rnc_emisor': rnc,
    'rnc_comprador': '101000001',
    'monto_total': 700.00,
    'total_factura_referenciada': 400.00,
    'suma_nd_referenciadas': 200.00,
  },
  {
    '__caso': 'Tipo inválido (40)',
    'tipo': '40',
    'fecha_emision': '15-04-2026',
    'rnc_emisor': rnc,
    'monto_total': 100.00,
  },
  {
    '__caso': 'Fecha mal formateada',
    'tipo': '31',
    'fecha_emision': '2026/04/15',
    'rnc_emisor': rnc,
    'rnc_comprador': '101000001',
    'monto_total': 100.00,
  },
  {
    '__caso': 'RNC emisor con letras',
    'tipo': '31',
    'fecha_emision': '15-04-2026',
    'rnc_emisor': 'ABC1933X2',
    'rnc_comprador': '101000001',
    'monto_total': 100.00,
  },
];

Future<void> main(List<String> args) async {
  final rnc = args.isNotEmpty ? args[0] : '133084503';
  final casos = _construirCasos(rnc);

  final source = PostgresDriverSource(
    host: 'localhost',
    port: 5433,
    database: 'test',
    username: 'pedro',
    password: 'camila',
    entorno: _entorno,
  );

  print('=== prueba-comprobantes-driver — entorno="$_entorno" (BD test 5433) ===');

  final meta = await source.lookup();
  if (meta == null) {
    print('✗ no hay driver activo. Publica uno con:');
    print('   bin/actualiza-cliente-dart');
    await source.close();
    return;
  }

  print('Driver activo: $meta\n');
  final bytes = await source.descargar();
  final h = cargarDriver(bytes: bytes, version: 'v${meta.version}');
  if (h.hash != meta.hashSha256) {
    throw StateError('hash mismatch');
  }

  // Procesar cada caso
  var aceptados = 0;
  var rechazados = 0;

  for (var i = 0; i < casos.length; i++) {
    final caso = casos[i];
    final label = caso['__caso'] as String;
    final comp = Map<String, Object?>.from(caso)..remove('__caso');
    final json = jsonEncode(comp);

    final raw = h.call('preValidar', [$String(json)]);
    final resJson = (raw is $Value ? raw.$reified : raw) as String;
    final res = jsonDecode(resJson) as Map<String, Object?>;
    final ok = res['ok'] as bool;
    final errores = (res['errores'] as List).cast<String>();

    if (ok) {
      aceptados++;
      print('[${i + 1}] ✓ $label');
    } else {
      rechazados++;
      print('[${i + 1}] ✗ $label');
      for (final e in errores) {
        print('       · $e');
      }
    }
  }

  print('\n--- Resumen ---');
  print('Driver: ${meta.entorno} v${meta.version}');
  print('Aceptados : $aceptados');
  print('Rechazados: $rechazados');
  print('Total     : ${casos.length}');

  await source.close();
}
