# Quickstart — Cliente Dart

## Audiencia

Esta guía es para un **integrador** que quiere consumir el motor Dart
hot-reload publicado por Chalona desde una app Dart / Flutter / Dart server.
Tú no hospedás Postgres ni publicás nada — Chalona ya lo hizo. Tu app
solo se conecta a la BD de Chalona y baja el driver.

Si querés hospedar tu propio motor (forkear el patrón hot-reload para tu
producto), saltá al final: [Self-hosting (avanzado)](#self-hosting-avanzado).

## Pre-requisitos

- Dart SDK 3.4+
- Acceso de red a la BD Postgres de Chalona (host, port, db, user, pass —
  provistos por Chalona)

**No necesitás aplicar schema ni publicar nada.** El motor vive en la BD
de Chalona y se baja a tu app via lookup.

## 1. Instalar dependencias

```bash
cd dart-driver
dart pub get
```

## 2. Configurar conexión

```dart
import 'package:chalona_dart_driver/loader.dart';
import 'package:chalona_dart_driver/postgres_source.dart';

final source = PostgresDriverSource(
  host:     '<host_provisto_por_chalona>',
  port:     5432,
  database: '<db_provista>',
  username: '<usuario_provisto>',
  password: '<clave_provista>',
  entorno:  'test',   // o 'produccion'
);
```

## 3. Bajar el driver y usarlo

```dart
DriverHandle? driver;

Future<dynamic> ejecutar(String fn, List<Object?> args) async {
  final meta = await source.lookup();
  if (meta == null) throw StateError('no driver activo');
  if (driver?.version != 'v${meta.version}') {
    final bytes = await source.descargar();
    driver = cargarDriver(bytes: bytes, version: 'v${meta.version}');
    if (driver!.hash != meta.hashSha256) throw StateError('hash mismatch');
  }
  return driver!.call(fn, args);
}

// Pre-validar un comprobante e-CF
final res = await ejecutar('preValidar', [comprobanteJson]);
```

En producción agregá: cache local en disco, retry con backoff, fallback
al driver cacheado si el lookup falla por red.

## Demos incluidas

```bash
dart run bin/poc_postgres.dart                  # end-to-end contra Postgres
dart run bin/prueba_comprobantes_driver.dart    # 9 comprobantes mock vs driver
dart run bin/poc.dart                            # hot-swap en memoria (sin BD)
dart run bin/test_ecf.dart                       # validador e-CF en eval (sin BD)
```

## Estructura del cliente

```
dart-driver/
├── pubspec.yaml
├── publicar.sh                   # solo si self-hosting
├── lib/
│   ├── loader.dart               # compilar/cargar/cache
│   └── postgres_source.dart      # cliente Postgres (lookup + descarga)
├── bin/
│   ├── poc.dart
│   ├── poc_postgres.dart
│   ├── test_ecf.dart
│   ├── prueba_comprobantes_driver.dart
│   └── compilar.dart
└── driver_src/                   # solo relevante si self-hosting
    ├── driver_ecf.dart
    ├── driver_v1.dart
    ├── driver_v2.dart
    ├── driver_prueba_comprobantes_v1.dart
    └── driver_prueba_comprobantes_v2.dart
```

## Limitaciones

Antes de meter lógica al driver (solo aplica si self-hosting), lee
[`dart-eval-limitations.md`](dart-eval-limitations.md). El intérprete
soporta la mayor parte de Dart pero hay gaps (ej. `num.round()` no está,
`num` como tipo de parámetro tiene boxing inconsistente).

---

## Self-hosting (avanzado)

Solo si querés hospedar tu propio motor. Caso típico: NO necesario para
integradores Chalona.

### Pre-requisitos extra

- Postgres con el [schema](../sql/schema.sql) aplicado
- `psql` y `python3` en el PATH

### 1. Aplicar schema

```bash
psql -h localhost -U postgres -d midb -f ../sql/schema.sql
```

### 2. Publicar la primera versión

`driver_src/driver_ecf.dart` contiene la lógica del driver (validadores
e-CF puros). Compilá y publicá con:

```bash
PG_HOST=localhost PG_PORT=5432 PG_DB=midb \
PG_USER=postgres PG_PASS=secret \
  ./publicar.sh
```

Esto:
1. Compila `driver_src/driver_ecf.dart` → bytecode `.evc` con `dart_eval`
2. Calcula sha256
3. Llama `fn.dart_cliente_driver_publicar` (verifica hash server-side)
4. Inserta como versión activa en `entorno='test'`

Para producción: `./publicar.sh --produccion`. Para otro driver fuente:
`./publicar.sh --fuente=driver_src/driver_prueba_comprobantes_v2.dart`.

### 3. Hot-reload

Modificá el driver fuente. Republicá. La próxima llamada del cliente
detecta la versión nueva y la baja.
