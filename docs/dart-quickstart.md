# Quickstart — Cliente Dart

## Audiencia

Esta guía es para un **integrador** que quiere consumir el API Chalona ECF desde una app Dart / Flutter / Dart server.

Tú no hospedás Postgres ni publicás nada — Chalona ya lo hizo. Tu app solo hace HTTPS contra `https://ecf-service.vicortiz.com` y deja que el cliente shell + motor manejen todo.

## Pre-requisitos

- Dart SDK **3.4+**
- Acceso de red a `https://ecf-service.vicortiz.com` (puerto 443)
- Credenciales de usuario ECF (correo + clave) provistas por Chalona

**Sin Postgres.** Sin schema. Sin credenciales de base de datos.

## Instalación

`pubspec.yaml`:

```yaml
dependencies:
  dart_driver_poc:
    path: ../path/al/chalona-ecf/dart-driver
  # o (cuando esté en pub.dev):
  # dart_driver_poc: ^1.0.0
```

```bash
dart pub get
```

## Uso mínimo

```dart
import 'package:dart_driver_poc/ecf_client.dart';

Future<void> main() async {
  // Para producción:
  final client = EcfClient();  // baseUrl=https://ecf-service.vicortiz.com, motorEntorno='produccion'

  // 1. Login (obtiene token Bearer y lo guarda interno).
  await client.login('mi_correo@empresa.com', 'mi_clave');

  // 2. Construir un comprobante con datos de tu ERP.
  final doc = DocumentoEcf(
    fiscal: '31',                          // Factura Crédito Fiscal
    encf: 'E310000000001',                 // e-NCF asignado por tu lógica
    fecha: DateTime.now(),
    moneda: 'DOP',
    valor: 1000.00,
    itbis: 180.00,
    total: 1180.00,
    emisor: EmisorEcf(
      rnc: '131996035',
      nombre: 'Mi Empresa SRL',
      direccion: 'Calle Principal #1, Santo Domingo',
    ),
    comprador: CompradorEcf(
      rnc: '01800451302',                  // 9 dígitos (RNC) o 11 (cédula)
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

  print('estado:           ${enviado.estado}');           // 'Aceptado' / 'En Proceso'
  print('códigoSeguridad:  ${enviado.codigoSeguridad}');
  print('timbre:           ${enviado.timbre}');
  print('fechaFirma:       ${enviado.fechaFirma}');

  // 4. Persistir resultado en tu ERP (tu código).
  await miErp.actualizarFactura(controlInterno, enviado);

  // 5. Cerrar HTTP client.
  client.close();
}
```

## Cómo funciona internamente

1. Tu código → `client.enviaEcfDesde(doc, portal: 'testecf')`.
2. Cliente shell (`ecf_client.dart`) pasa el estado al motor estático (`motor.dart`).
3. Motor dice `{"kind":"http", "endpoint":"envia_ecf", ...}`.
4. Shell hace `POST /` a `https://ecf-service.vicortiz.com` con el payload y el token Bearer.
5. Server-ecf firma con certificado P12 de tu empresa, envía a DGII.
6. Respuesta vuelve: motor devuelve `{"kind":"done", "result":{...}}` → shell devuelve `DocumentoEcf` enriquecido.

El motor vive embebido estáticamente en `motor.dart` — no hay descarga dinámica
ni dependencia a Postgres.

## Tipos de comprobante

| TipoeCF | Descripción              |
|---------|--------------------------|
| `31`    | Factura Crédito Fiscal   |
| `32`    | Factura de Consumo       |
| `33`    | Nota de Débito           |
| `34`    | Nota de Crédito          |
| `41`    | Compras (con retenciones)|
| `43`    | Gastos Menores           |
| `44`    | Régimen Especial         |
| `45`    | Gubernamental            |
| `46`    | Exportación              |
| `47`    | Pagos al Exterior        |

Ver `chalona-ecf/dart-driver/README.md` para ejemplos por cada tipo (con/sin ITBIS, NC con tope, compras con retención ISR).

## Métodos del cliente

| Método                                  | Descripción                                              |
|-----------------------------------------|----------------------------------------------------------|
| `login(usuario, clave)`                 | Auth — guarda token Bearer interno.                       |
| `enviaEcfDesde(doc, portal)`            | Envía un `DocumentoEcf`; motor arma el payload.          |
| `enviaEcf(rnc, portal, json)`           | Envía con payload DGII completo armado por el integrador.|
| `consultaEstado(comprobantes)`          | Lista de hasta 100 e-NCFs → estado por cada uno.         |
| `descargaXmls(desde, hasta, {tipos})`   | ZIP con XMLs firmados del rango (YYYY-MM-DD).            |
| `clearToken()`                          | Limpia token (para forzar re-login).                     |
| `close()`                               | Cierra HTTP client.                                       |

## Manejo de errores

```dart
try {
  await client.enviaEcfDesde(doc, portal: 'testecf');
} on EcfApiError catch (e) {
  print('código: ${e.code}');
  print('detalle: ${e.data}');
  // p.ej. e.code == 'err.sistema_login.credenciales_invalidas'
  //       e.code == 'motor.envia_doc.fiscal_requerido'
  //       e.code == 'ecf.formato_rnc'
}
```

## Demo end-to-end

```bash
cd chalona-ecf/dart-driver
dart pub get
dart run bin/demo_envio.dart
```

Variables de entorno opcionales:

```bash
ECF_USER=mi@empresa.com
ECF_PASS=mi_clave
ECF_RNC_EMISOR=131996035
ECF_PORTAL=testecf                                   # 'testecf' o 'ecf'
# ECF_BASE_URL=http://localhost:3030                 # solo para self-hosting
```

## Self-hosting (avanzado)

Si querés levantar tu propio server-ecf:

1. Aplicar el schema de BD del monorepo Chalona.
2. Levantar `server_ecf` (ver `ecf/server/`).
3. Apuntar el cliente con `EcfClient(baseUrl: 'https://tu-dominio.com')`.

Para integradores normales esto **no aplica** — solo necesitás las credenciales de usuario.

## Referencias

- Cliente Dart: `chalona-ecf/dart-driver/README.md` (API completa + ejemplos por tipo).
- Arquitectura general: `chalona-ecf/docs/architecture.md`.
