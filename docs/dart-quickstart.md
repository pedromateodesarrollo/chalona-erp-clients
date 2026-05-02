# Quickstart — Cliente Dart

## Pre-requisitos

- Dart SDK 3.4+
- Postgres con el [schema](../sql/schema.sql) aplicado
- `psql` y `python3` en el PATH (publisher los usa)

## 1. Instalar dependencias

```bash
cd dart-driver
dart pub get
```

## 2. Aplicar schema (una vez)

```bash
psql -h localhost -U postgres -d midb -f ../sql/schema.sql
```

## 3. Publicar el primer driver

`driver_src/driver_ecf.dart` contiene la lógica del driver (validadores e-CF
puros como ejemplo). Compila y publica con:

```bash
PG_HOST=localhost PG_PORT=5432 PG_DB=midb \
PG_USER=postgres PG_PASS=secret \
./publicar.sh
```

Esto:

1. Compila `driver_src/driver_ecf.dart` → bytecode `.evc` con `dart_eval`.
2. Calcula sha256 sobre los bytes.
3. Llama `fn.dart_cliente_driver_publicar` (que verifica el hash server-side).
4. Inserta como versión nueva activa en `entorno='test'`.

Para publicar a `entorno='produccion'` agrega `--produccion`:

```bash
PG_HOST=... ./publicar.sh --produccion
```

Para publicar otro archivo de driver:

```bash
./publicar.sh --fuente=driver_src/driver_prueba_comprobantes_v2.dart
```

## 4. Correr el cliente demo

```bash
dart run bin/poc_postgres.dart
```

Salida esperada:

```
=== Demo BD test (5433) — entorno="test" ===

[1] Lookup metadata del driver activo...
   DriverMeta(v=1 entorno=test tam=11770 sha=e49b4aedb005...)

[2] Descargando bytes...
   11770 bytes recibidos (esperado 11770)

[3] Cargando en dart_eval...
   ✓ hash verificado: e49b4aedb005...

[4] Ejecutando lógica e-CF (proveniente de BD test)...
   isFechaDdMmYyyy("15-04-2026") = true
   isFechaDdMmYyyy("32-04-2026") = false
   ...
```

## 5. Ver el hot-reload en acción

Modifica `driver_src/driver_ecf.dart` (cambia una constante, agrega una regla).
Republica:

```bash
./publicar.sh
```

Re-corre el cliente:

```bash
dart run bin/poc_postgres.dart
```

El cliente baja la versión nueva y aplica las reglas nuevas — sin recompilar
el binario AOT.

## Demos incluidas

| Archivo | Qué demuestra |
|---|---|
| `bin/poc.dart` | Hot-swap entre dos drivers en memoria (sin BD) |
| `bin/test_ecf.dart` | Lógica real de validador e-CF en `dart_eval` (sin BD) |
| `bin/poc_postgres.dart` | End-to-end contra Postgres (lookup + descarga + ejecución) |
| `bin/prueba_comprobantes_driver.dart` | Cliente que valida 9 comprobantes mock contra el driver activo |
| `bin/compilar.dart` | Helper para compilar `.dart` → `.evc` |

## Estructura del cliente

```
dart-driver/
├── pubspec.yaml
├── publicar.sh                   # CLI de publicación
├── lib/
│   ├── loader.dart               # compilar/cargar/cache
│   └── postgres_source.dart      # cliente Postgres (lookup + descarga)
├── bin/
│   ├── poc.dart                  # demo standalone
│   ├── poc_postgres.dart         # demo end-to-end con BD
│   ├── test_ecf.dart             # validación e-CF real en eval
│   ├── prueba_comprobantes_driver.dart
│   └── compilar.dart
└── driver_src/
    ├── driver_ecf.dart                  # validadores e-CF puros
    ├── driver_v1.dart                   # demo hot-swap v1
    ├── driver_v2.dart                   # demo hot-swap v2
    ├── driver_prueba_comprobantes_v1.dart   # validación laxa
    └── driver_prueba_comprobantes_v2.dart   # validación estricta
```

## Integrar el patrón en tu app

Pseudocódigo:

```dart
import 'package:chalona_dart_driver/loader.dart';
import 'package:chalona_dart_driver/postgres_source.dart';

final source = PostgresDriverSource(
  host: '...', port: 5432, database: '...',
  username: '...', password: '...',
  entorno: 'produccion',
);

DriverHandle? driver;

Future<dynamic> ejecutar(String fn, List<Object?> args) async {
  // Asegurar driver fresco
  final meta = await source.lookup();
  if (meta == null) throw 'no driver';
  if (driver?.version != 'v${meta.version}') {
    final bytes = await source.descargar();
    driver = cargarDriver(bytes: bytes, version: 'v${meta.version}');
    if (driver!.hash != meta.hashSha256) throw 'hash mismatch';
  }
  return driver!.call(fn, args);
}
```

En producción agrega: cache local en disco, retry con backoff, fallback al
driver cacheado si el lookup falla por red.

## Limitaciones

Antes de meter lógica al driver, lee
[`dart-eval-limitations.md`](dart-eval-limitations.md). El intérprete soporta
la mayor parte de Dart pero hay gaps importantes (ej. `num.round()` no está,
`num` como tipo de parámetro tiene boxing inconsistente).
