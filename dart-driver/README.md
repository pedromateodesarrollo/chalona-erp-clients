# Cliente Dart — Chalona ECF

Cliente HTTP en Dart para el API **ecf-service** (comprobantes fiscales electrónicos e-CF, DGII República Dominicana).

El cliente es un **shell delgado** que descarga dinámicamente un **motor** (bytecode `.evc`) desde el servidor. El motor controla TODA la lógica de comunicación, validación y construcción de payloads DGII. Cuando se publica una nueva versión del motor, los clientes existentes la bajan automáticamente sin recompilar.

> **Sin Postgres directo.** Todo viaja por HTTPS contra `https://ecf-service.vicortiz.com`. No hace falta configurar credenciales de base de datos en el integrador.

---

## Instalación

`pubspec.yaml`:

```yaml
dependencies:
  dart_driver_poc:
    path: ../path/al/dart-driver   # o publicado en pub.dev
```

```bash
dart pub get
```

---

## Uso mínimo

```dart
import 'package:dart_driver_poc/ecf_client.dart';

Future<void> main() async {
  final client = EcfClient(
    baseUrl: 'https://ecf-service.vicortiz.com',  // default
    motorEntorno: 'produccion',                    // default
  );

  // 1. Login (obtiene token Bearer y lo guarda interno).
  await client.login('mi_correo@empresa.com', 'mi_clave');

  // 2. Construir documento (espejo de cursores Fox).
  final doc = DocumentoEcf(
    fiscal: '31',                                  // Factura Crédito Fiscal
    encf: 'E310000000001',                         // e-NCF asignado por integrador
    fecha: DateTime.now(),
    moneda: 'DOP',
    valor: 1000.00,                                // subtotal gravado
    itbis: 180.00,                                 // ITBIS 18% sobre 1000
    total: 1180.00,
    emisor: EmisorEcf(
      rnc: '131996035',
      nombre: 'Mi Empresa SRL',
      direccion: 'Calle Principal #1, Santo Domingo',
    ),
    comprador: CompradorEcf(
      rnc: '01800451302',                          // RNC 9 dígitos o cédula 11
      nombre: 'Cliente SA',
    ),
    lineas: [
      LineaEcf(
        descripcion: 'Servicio de consultoría',
        cantidad: 1,
        precio: 1000.00,
        itbis: 180.00,
        itbisTasa: 18,
        esServicio: true,
      ),
    ],
  );

  // 3. Enviar a DGII (motor arma payload + firma + envía).
  final enviado = await client.enviaEcfDesde(doc, portal: 'testecf');
  print(enviado.estado);             // 'Aceptado' / 'En Proceso'
  print(enviado.codigoSeguridad);
  print(enviado.timbre);

  // 4. Cerrar HTTP client.
  client.close();
}
```

---

## Tipos de comprobante soportados (motor v1)

| TipoeCF | Descripción                | Estado motor v1 |
|---------|----------------------------|-----------------|
| 31      | Factura Crédito Fiscal     | ✓               |
| 32      | Factura de Consumo         | ✓               |
| 33      | Nota de Débito             | ✓               |
| 34      | Nota de Crédito            | ✓               |
| 41–47   | Compras/Gastos/Especiales  | (en motor v2)   |

---

## Ejemplos por tipo

### Tipo 31 — Factura Crédito Fiscal con ITBIS

```dart
final doc = DocumentoEcf(
  fiscal: '31',
  encf: 'E310000000001',
  fecha: DateTime.now(),
  moneda: 'DOP',
  valor: 5000.00,
  itbis: 900.00,
  total: 5900.00,
  emisor: EmisorEcf(rnc: '131996035', nombre: 'Mi SRL', direccion: 'Av. 1'),
  comprador: CompradorEcf(rnc: '01800451302', nombre: 'Cliente SA'),
  lineas: [
    LineaEcf(
      descripcion: 'Producto A',
      cantidad: 5,
      precio: 1000.00,
      itbis: 900.00,
      itbisTasa: 18,
      esServicio: false,
    ),
  ],
);
```

### Tipo 31 — Item exento (sin ITBIS)

Para items exentos, dejar `itbis: 0`. El motor pone `IndicadorFacturacion='4'` (exento).

```dart
LineaEcf(
  descripcion: 'Servicio educativo (exento)',
  cantidad: 1,
  precio: 5000.00,
  itbis: 0,                  // 0 → exento
  itbisTasa: 0,
  esServicio: true,
)
```

### Tipo 32 — Factura de Consumo (sin RNC comprador, monto chico)

```dart
final doc = DocumentoEcf(
  fiscal: '32',
  encf: 'E320000000001',
  fecha: DateTime.now(),
  total: 1180.00,
  valor: 1000.00,
  itbis: 180.00,
  emisor: EmisorEcf(rnc: '131996035', nombre: 'Mi SRL', direccion: 'Av. 1'),
  // comprador opcional para tipo 32 con monto < 250,000
  lineas: [
    LineaEcf(
      descripcion: 'Producto B',
      cantidad: 1,
      precio: 1000.00,
      itbis: 180.00,
      itbisTasa: 18,
    ),
  ],
);
```

> **Importante:** tipo 32 con `MontoTotal >= RD$250,000` requiere comprador identificado (manual RFCE DGII 2026).

### Tipo 33 — Nota de Débito (referencia a factura previa)

```dart
final doc = DocumentoEcf(
  fiscal: '33',
  encf: 'E330000000001',
  fecha: DateTime.now(),
  total: 200.00,
  valor: 169.49,
  itbis: 30.51,
  dgiiCodMod: 1,                            // código modificación DGII
  comentario: 'Cargo adicional por flete',
  emisor: EmisorEcf(rnc: '131996035', nombre: 'Mi SRL', direccion: 'Av. 1'),
  comprador: CompradorEcf(rnc: '01800451302', nombre: 'Cliente SA'),
  referencias: [
    ReferenciaEcf(
      encf: 'E310000000001',                 // factura referenciada
      fecha: DateTime(2026, 4, 1),
    ),
  ],
  lineas: [
    LineaEcf(
      descripcion: 'Cargo adicional flete',
      cantidad: 1,
      precio: 169.49,
      itbis: 30.51,
      itbisTasa: 18,
    ),
  ],
);
```

### Tipo 34 — Nota de Crédito

```dart
final doc = DocumentoEcf(
  fiscal: '34',
  encf: 'E340000000001',
  fecha: DateTime.now(),
  total: 590.00,                            // tope: total_factura + suma_ND
  valor: 500.00,
  itbis: 90.00,
  dgiiCodMod: 1,                            // 1=anulación, 2=devolución, ...
  comentario: 'Devolución parcial',
  emisor: EmisorEcf(rnc: '131996035', nombre: 'Mi SRL', direccion: 'Av. 1'),
  comprador: CompradorEcf(rnc: '01800451302', nombre: 'Cliente SA'),
  referencias: [
    ReferenciaEcf(encf: 'E310000000001', fecha: DateTime(2026, 4, 1)),
  ],
  lineas: [
    LineaEcf(descripcion: 'Producto devuelto', cantidad: 1, precio: 500.00,
             itbis: 90.00, itbisTasa: 18),
  ],
);
```

> **Tope NC (validado en server):** `total_factura_referenciada + suma_notas_debito_referenciadas`. Si excede, la DGII rechaza.

### Compras (tipo 41) con retenciones — *plan v2*

> **Nota:** en motor v1 los tipos 41–47 NO están construidos aún. Plan motor v2:

```dart
// Compra a suplidor con retención ISR + ITBIS
final compra = DocumentoEcf(
  fiscal: '41',
  encf: 'E410000000001',
  fecha: DateTime.now(),
  total: 11800.00,
  valor: 10000.00,
  itbis: 1800.00,
  itbisRetenido: 1800.00,                   // retención ITBIS 100%
  isrRetenido: 200.00,                      // retención ISR 2%
  emisor: EmisorEcf(rnc: '131996035', nombre: 'Mi SRL', direccion: 'Av. 1'),
  suplidor: SuplidorEcf(rnc: '101000123', nombre: 'Suplidor SA'),
  lineas: [
    LineaEcf(
      descripcion: 'Servicio profesional',
      cantidad: 1,
      precio: 10000.00,
      itbis: 1800.00,
      itbisTasa: 18,
      itbisRetenido: 1800.00,
      isrRetenido: 200.00,
      esServicio: true,
    ),
  ],
);
```

---

## API completa de `EcfClient`

| Método                     | Descripción                                                |
|----------------------------|------------------------------------------------------------|
| `login(usuario, clave)`    | Auth — guarda token Bearer interno.                         |
| `enviaEcfDesde(doc, portal)` | Envía un `DocumentoEcf` (motor arma payload).             |
| `enviaEcf(rnc, portal, json)` | Envía con payload DGII completo armado por el integrador. |
| `consultaEstado(comprobantes)` | Lista de hasta 100 e-NCFs → estado por cada uno.       |
| `descargaXmls(desde, hasta, {tipos})` | ZIP con XMLs firmados del rango.                |
| `lookupMotor({entorno})`   | Metadata del motor activo (versión, hash, tamaño).         |
| `descargarMotor({entorno, version})` | Bytes del motor (uso interno).                   |
| `ensureMotor()`            | Lazy load del motor (si no está en memoria).               |
| `clearMotor()`             | Forzar re-fetch en próxima llamada.                        |
| `clearToken()`             | Limpia token (forzar re-login).                             |
| `close()`                  | Cierra HTTP client.                                         |

---

## Manejo de errores

Todos los errores se lanzan como `EcfApiError`:

```dart
try {
  await client.enviaEcfDesde(doc, portal: 'testecf');
} on EcfApiError catch (e) {
  print('código: ${e.code}');           // p.ej. 'motor.envia_doc.fiscal_requerido'
  print('data:   ${e.data}');           // detalles
  print('status: ${e.statusCode}');     // status HTTP si aplica
}
```

Códigos comunes:

| Código                                          | Causa                                    |
|-------------------------------------------------|------------------------------------------|
| `err.sistema_login.credenciales_invalidas`      | Login con clave incorrecta.              |
| `motor.envia_doc.fiscal_requerido`              | Falta `documento.fiscal`.                |
| `motor.envia_doc.emisor_rnc_requerido`          | Falta RNC del emisor.                    |
| `motor.envia_doc.comprador_requerido_31`        | Tipo 31 sin comprador.                   |
| `motor.envia_doc.sin_lineas`                    | Documento sin líneas.                    |
| `dart_cliente_driver.version_desactualizada`    | Motor obsoleto — el shell auto-recarga.  |
| `motor.no_disponible`                           | No hay motor publicado para ese entorno. |

---

## Auto-actualización del motor

El shell envía `dart_driver_version` y `dart_driver_entorno` en cada request HTTP. Si el server detecta que la versión del cliente no coincide con la activa, devuelve `dart_cliente_driver.version_desactualizada`. El shell:

1. Llama `clearMotor()`.
2. Reintenta `_dispatch` desde `step=0` (motor descarga la nueva versión).
3. Continúa el flujo con el motor nuevo.

Sin intervención del programador.

---

## Demo end-to-end

```bash
# Contra producción (default):
dart run bin/demo_envio.dart

# Contra server-ecf local (BD test):
ECF_BASE_URL=http://localhost:3030 dart run bin/demo_envio.dart

# Override creds / RNC:
ECF_USER=user@x.com ECF_PASS=clave ECF_RNC_EMISOR=131996035 \
  dart run bin/demo_envio.dart
```

---

## Estructura interna

```
ecf/clients/dart-driver/
├── lib/
│   ├── ecf_client.dart      # shell HTTP + trampolín shell↔motor
│   ├── documento_ecf.dart   # DocumentoEcf, EmisorEcf, CompradorEcf, etc.
│   └── loader.dart          # runtime dart_eval
├── driver_src/
│   └── motor_v1.dart        # código fuente del motor (se compila a .evc)
├── bin/
│   ├── compilar.dart        # compila motor source → bytecode
│   └── demo_envio.dart      # ejecutable demo
└── pubspec.yaml             # deps: dart_eval, crypto, http
```

---

## Publicar nueva versión del motor

Después de modificar `driver_src/motor_v1.dart`:

```bash
# BD test 5433 (entorno=test):
bin/actualiza-cliente-dart --fuente=ecf/clients/dart-driver/driver_src/motor_v1.dart

# BD producción 5432 (entorno=produccion):
bin/actualiza-cliente-dart --produccion --fuente=ecf/clients/dart-driver/driver_src/motor_v1.dart
```

Los clientes existentes detectarán la nueva versión en su próximo request HTTP (vía mecanismo de auto-actualización).

---

## Ver también

- Guía completa del API ecf-service: `api/lib/src/ecf/guia-api-ecf-service.md`
- Memoria de diseño: `project_clientes_dart_csharp_drivers.md`
- Skill: `.claude/skills/driver-cliente/SKILL.md`
