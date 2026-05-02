// Demo end-to-end contra BD test 5433.
//
// Pre-requisito: bin/actualiza-cliente-dart ya publicó al menos v1 con el
// driver_src/driver_ecf.dart actual. Esta demo:
//   1. Cliente arranca sin driver activo, hace lookup, baja v1, lo carga
//   2. Llama funciones reales de e-CF dentro del driver
//   3. Si publicas otra versión (corre el script de update en otra terminal),
//      próximo lookup detecta cambio y baja la nueva
//
// Ejecutar:
//   dart run bin/poc_postgres.dart

import 'package:chalona_dart_driver/loader.dart';
import 'package:chalona_dart_driver/postgres_source.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/stdlib/core.dart';

const _entorno = 'test';

Future<void> main() async {
  final source = PostgresDriverSource(
    host: 'localhost',
    port: 5433,
    database: 'test',
    username: 'pedro',
    password: 'camila',
    entorno: _entorno,
  );

  print('=== Demo BD test (5433) — entorno="$_entorno" ===\n');

  // 1. Lookup inicial
  print('[1] Lookup metadata del driver activo...');
  final meta = await source.lookup();
  if (meta == null) {
    print('   ✗ no hay driver publicado. Corre primero:');
    print('     bin/actualiza-cliente-dart');
    await source.close();
    return;
  }
  print('   $meta');

  // 2. Descarga
  print('\n[2] Descargando bytes...');
  final bytes = await source.descargar();
  print('   ${bytes.length} bytes recibidos (esperado ${meta.tamano})');
  if (bytes.length != meta.tamano) {
    throw StateError('tamaño no coincide');
  }

  // 3. Cargar en runtime
  print('\n[3] Cargando en dart_eval...');
  final h = cargarDriver(
    bytes: bytes,
    version: 'v${meta.version}',
  );
  if (h.hash != meta.hashSha256) {
    print('   ✗ hash local ${h.hash.substring(0, 12)}... '
        '!= servidor ${meta.hashSha256.substring(0, 12)}...');
    await source.close();
    return;
  }
  print('   ✓ hash verificado: ${h.hash.substring(0, 12)}...');

  // 4. Ejecutar lógica e-CF real desde el driver bajado de BD
  print('\n[4] Ejecutando lógica e-CF (proveniente de BD test)...');

  Object? r = h.call('isFechaDdMmYyyy', [$String('15-04-2026')]);
  print('   isFechaDdMmYyyy("15-04-2026") = ${_unwrap(r)}');

  r = h.call('isFechaDdMmYyyy', [$String('32-04-2026')]);
  print('   isFechaDdMmYyyy("32-04-2026") = ${_unwrap(r)}');

  r = h.call(
    'diasCalendarioEntreReferenciaYEmisionNc',
    [$String('01-04-2026'), $String('15-04-2026')],
  );
  print('   diasCalendario(01-04, 15-04) = ${_unwrap(r)}');

  r = h.call(
    'validarTopeNotaCredito',
    [$double(700), $double(400), $double(200)],
  );
  print('   validarTopeNotaCredito(NC=700, fac=400, ND=200) = ${_unwrap(r)}');

  // 5. Re-lookup: simula próximo request del cliente
  print('\n[5] Re-lookup tras unos segundos (simula próximo request)...');
  await Future.delayed(Duration(seconds: 1));
  final meta2 = await source.lookup();
  if (meta2 != null && meta2.version != meta.version) {
    print('   ⚡ versión cambió: v${meta.version} → v${meta2.version} '
        '(otra terminal publicó nuevo driver)');
  } else {
    print('   sin cambios (v${meta.version})');
  }

  await source.close();
  print('\n[OK] demo completada.');
}

Object? _unwrap(Object? v) {
  if (v is $Value) return v.$reified;
  return v;
}
