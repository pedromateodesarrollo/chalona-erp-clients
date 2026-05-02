// Test de viabilidad: compilar lógica REAL de ecf.validator.dart con dart_eval.

import 'dart:io';

import 'package:chalona_dart_driver/loader.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/stdlib/core.dart';

void main() {
  final fuente = File('driver_src/driver_ecf.dart').readAsStringSync();

  print('Compilando lógica e-CF real (subset puro de ecf.validator.dart)...');
  final bytes = compilarDriver(fuenteDart: fuente);
  print('OK — bytecode: ${bytes.length} bytes\n');

  final h = cargarDriver(bytes: bytes, version: 'ecf-test');

  void caso(String label, String fn, List<Object?> args) {
    final r = h.call(fn, args);
    final unwrap = r is $Value ? r.$reified : r;
    print('  $label = $unwrap');
  }

  print('isFechaDdMmYyyy:');
  caso('"15-04-2026"', 'isFechaDdMmYyyy', [$String('15-04-2026')]);
  caso('"32-04-2026"', 'isFechaDdMmYyyy', [$String('32-04-2026')]);
  caso('"15-13-2026"', 'isFechaDdMmYyyy', [$String('15-13-2026')]);
  caso('"15/04/2026"', 'isFechaDdMmYyyy', [$String('15/04/2026')]);

  print('\ndiasCalendarioEntreReferenciaYEmisionNc:');
  caso('ref=01-04-2026 emi=15-04-2026',
      'diasCalendarioEntreReferenciaYEmisionNc',
      [$String('01-04-2026'), $String('15-04-2026')]);
  caso('ref=15-04-2026 emi=01-04-2026 (NC anterior!)',
      'diasCalendarioEntreReferenciaYEmisionNc',
      [$String('15-04-2026'), $String('01-04-2026')]);

  print('\nfechaEsMayorOIgual:');
  caso('"15-04-2026" >= "01-04-2026"', 'fechaEsMayorOIgual',
      [$String('15-04-2026'), $String('01-04-2026')]);
  caso('"01-04-2026" >= "15-04-2026"', 'fechaEsMayorOIgual',
      [$String('01-04-2026'), $String('15-04-2026')]);

  print('\nmontoEsCeroEnCentavos:');
  caso('0.001', 'montoEsCeroEnCentavos', [$double(0.001)]);
  caso('0.01', 'montoEsCeroEnCentavos', [$double(0.01)]);

  print('\ncoincideConTolerancia:');
  caso('100.0 vs 100.05 tol=0.1', 'coincideConTolerancia',
      [100.0, 100.05, 0.1]);
  caso('100.0 vs 101.0 tol=0.1', 'coincideConTolerancia',
      [100.0, 101.0, 0.1]);

  print('\nvalidarTopeNotaCredito (regla DGII tipo 34):');
  caso('NC=500 factura=400 ND=200 (OK, tope=600)',
      'validarTopeNotaCredito',
      [$double(500), $double(400), $double(200)]);
  caso('NC=700 factura=400 ND=200 (excede)',
      'validarTopeNotaCredito',
      [$double(700), $double(400), $double(200)]);

  print('\n[OK] lógica real e-CF ejecutada en dart_eval sin modificación.');
}
