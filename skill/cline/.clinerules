# Convención: integración Chalona ECF

Cuando el usuario pida integrar Chalona ECF con su ERP, seguir esta guía exactamente.



# /driver-cliente — Guía interactiva de integración ECF

Esta skill ayuda a un integrador (o al asistente que trabaja con él) a integrar **su ERP** con el cliente Chalona ECF. El cliente es un **shell delgado** que descarga dinámicamente un **motor** desde el server; el motor controla toda la lógica de comunicación con la DGII. El integrador solo arma `DocumentoEcf` con datos de su ERP y los pasa al cliente — no implementa lógica de DGII.

Cuando el usuario invoque esta skill, aplicar las tres fases en orden:

1. **Explicar la arquitectura** (corto, una vez) — qué es el cliente, qué es el motor, hot-reload.
2. **Levantar requisitos** — preguntar progresivamente sobre el ERP del integrador.
3. **Generar el código de integración** — adapter en el lenguaje del integrador que toma datos de su ERP y construye `DocumentoEcf`.

No avanzar a la fase 2 hasta confirmar que el integrador entendió la fase 1. No avanzar a la fase 3 hasta tener todas las respuestas críticas.

## Fase 1 — Explicar la arquitectura

Presentar este resumen exacto (el integrador puede no conocer el sistema):

### Dos piezas del lado de Chalona

- **Cliente shell** (lo escribe Chalona, lo distribuye al integrador):
  - Librería en el lenguaje del integrador (Dart, C#, TypeScript, Python, Fox).
  - Hace HTTP contra `https://ecf-service.vicortiz.com`.
  - Métodos públicos: `login`, `enviaEcfDesde(documento, portal)`, `consultaEstado(...)`, `descargaXmls(...)`.
  - Es delgado: NO contiene reglas de DGII; solo HTTP + trampolín al motor.
- **Motor** (lo escribe Chalona, vive en BD del server, hot-reload):
  - Bytecode/source que el cliente shell descarga al primer uso.
  - Decide qué request HTTP hacer, arma payload DGII, valida, parsea respuesta.
  - Versiones por entorno (`test` / `produccion`); cliente envía `<lang>_driver_version` en cada request y server rechaza si está desactualizada → cliente baja la nueva automáticamente.
  - Bug fix o cambio DGII = nueva versión del motor; clientes existentes la heredan sin recompilar.

### Lo que hace el integrador

Una sola cosa: **construir `DocumentoEcf` a partir de los datos de su ERP**.

```dart
// Ejemplo Dart — el integrador lee de SUS tablas y arma esto:
final doc = DocumentoEcf(
  fiscal: '31',                        // tipo de comprobante
  encf: 'E310000000001',               // e-NCF asignado por su lógica
  fecha: DateTime.now(),
  total: 1180.00, valor: 1000.00, itbis: 180.00, moneda: 'DOP',
  emisor: EmisorEcf(rnc: '...', nombre: '...', direccion: '...'),
  comprador: CompradorEcf(rnc: '...', nombre: '...'),
  lineas: [LineaEcf(descripcion: '...', cantidad: 1, precio: 1000, itbis: 180)],
);

await client.enviaEcfDesde(doc, portal: 'testecf');
```

Después del envío, el integrador toma los campos de resultado del documento (`encf`, `estado`, `codigoSeguridad`, `timbre`, `fechaFirma`) y los persiste a sus propias tablas como guste. El cliente shell NO escribe en la BD del integrador — devuelve datos, el integrador decide dónde guardarlos.

### Hot-reload del motor

El motor vive en Postgres (tabla `data.<lang>_cliente_driver`). El cliente shell:

1. Al primer uso (lazy): `lookupMotor(entorno)` → versión activa + sha256.
2. `descargarMotor(entorno)` → bytes.
3. Verifica sha256 y carga en runtime sandbox del lenguaje.
4. En cada request HTTP envía `<lang>_driver_version` y `<lang>_driver_entorno`.
5. Si server responde `<lang>_cliente_driver.version_desactualizada` → shell descarga la nueva versión y reintenta.

El integrador **no** baja motor manualmente. Lo hace el shell.

### Lenguajes ya soportados

| Lenguaje  | Runtime motor                                            | Carpeta del repo            |
|-----------|----------------------------------------------------------|-----------------------------|
| Fox (VFP) | `.prg` temporal + `SET PROCEDURE`                        | `chalona-ecf/fox/`          |
| Dart      | `dart_eval` interpreta `.evc`                            | `chalona-ecf/dart-driver/`  |
| C# / .NET | `AssemblyLoadContext.LoadFromStream` (`.dll` Roslyn)     | `chalona-ecf/csharp/`       |
| TypeScript| `node:vm` sandbox (JS source)                            | `chalona-ecf/typescript-driver/` |
| Python    | `exec()` en namespace aislado (`.py` source)             | `chalona-ecf/python-driver/`|

Repo público: `github.com/pedromateodesarrollo/chalona-erp-clients`.

### Modelo `DocumentoEcf` (común a todos los lenguajes)

Estructura espejo de cursores Fox. Campos principales:

| Campo                | Tipo            | Descripción                              |
|----------------------|-----------------|------------------------------------------|
| `fiscal`             | String          | Tipo: `31`, `32`, `33`, `34`, `41`–`47`  |
| `encf`               | String?         | e-NCF asignado por integrador            |
| `fecha`              | DateTime        | Fecha emisión                            |
| `valor`              | double          | Subtotal gravado                          |
| `itbis`              | double          | ITBIS                                    |
| `total`              | double          | Total                                    |
| `moneda`             | String          | `DOP`, `USD`, …                          |
| `tasa`               | double          | Tasa cambio si moneda ≠ DOP              |
| `itbisRetenido`      | double          | Retención ITBIS (compras/gastos)         |
| `isrRetenido`        | double          | Retención ISR (compras/gastos)           |
| `dgiiCodMod`         | int?            | Código modificación NC/ND                |
| `emisor`             | `EmisorEcf`     | rnc, nombre, direccion                   |
| `comprador`          | `CompradorEcf?` | rnc, nombre, extranjero                  |
| `suplidor`           | `SuplidorEcf?`  | tipos 41/43/44/47                        |
| `lineas`             | `List<LineaEcf>`| detalle items                            |
| `referencias`        | `List<ReferenciaEcf>` | NC/ND apuntan a factura(s) previa(s)|

Resultado tras `enviaEcfDesde()`: el motor llena `estado`, `estadoDescripcion`, `codigoSeguridad`, `fechaFirma`, `timbre`, `secuenciaUtilizada`.

Después de explicar esto, **preguntar**: "¿Quieres que recorramos juntas las preguntas de diseño para tu ERP, o prefieres ver primero un ejemplo en algún lenguaje?"

## Fase 2 — Levantamiento (preguntas en orden)

Hacer las preguntas de a una o en bloques pequeños. Registrar respuestas claramente para usarlas en fase 3. Si el integrador ya respondió algo en la conversación previa, no repreguntar.

### Bloque A — Lenguaje y entorno

1. ¿En qué lenguaje vas a integrar? (Fox / Dart / C# / TypeScript / Python / otro — si "otro", confirmar y ver `project_proceso_nuevo_cliente_lenguaje.md`).
2. ¿Tu ERP corre en un solo proceso largo (servidor) o desktop multi-usuario (Fox-style)?
3. ¿Vas a usar el cliente sincrónicamente al guardar (un envío a la vez) o también necesitas sync masivo (procesar pendientes en batch)?

### Bloque B — Base de datos del ERP

4. ¿Qué motor de base de datos usa tu ERP? (SQL Server / PostgreSQL / MySQL / MariaDB / Oracle / DBF / SQLite / MongoDB / API REST)
5. ¿Cómo se conecta tu aplicación hoy? (cadena de conexión, ODBC, ORM)

### Bloque C — Maestro de comprobantes de venta

6. ¿En qué tabla(s) viven los **comprobantes de venta** que se van a emitir como e-CF? Nombre de tabla y columna que actúa como clave.
7. Listar columnas equivalentes a:
   - fecha del documento
   - rnc/identificación del cliente
   - nombre, dirección
   - tipo (31/32/33/34) — ¿el ERP ya lo guarda? ¿se deduce?
   - subtotal, itbis, descuento, retenciones, total
   - moneda, tasa de cambio
   - referencia a factura previa (NC/ND)

### Bloque D — Detalle de líneas de venta

8. Tabla y columnas mínimas: cantidad, precio, descripción, indicador servicio/bien, itbis, tasa itbis.

### Bloque E — Compras / gastos (si aplica — tipos 41/43/44/47)

9. ¿Tabla de compras separada o flag en maestro de venta?
10. Columnas para retenciones: `itbis_retenido`, `isr_retenido`.
11. Tabla de suplidores (rnc, nombre, flag extranjero).

### Bloque F — Maestros auxiliares

12. Tabla empresa emisora (rnc, nombre, dirección, indicador precio).
13. Tabla clientes — cómo obtener rnc + nombre + extranjero por código.
14. Secuencias fiscales — dónde está la fecha vencimiento por tipo (`FechaVencimientoSecuencia`).

### Bloque G — Referencias (NC/ND)

15. Cuando se emite NC (34) o ND (33), ¿cómo se enlaza con factura original? (columna que apunta al control del documento referenciado o al e-NCF previo).

### Bloque H — Persistencia de respuesta DGII

16. Después del `enviaEcfDesde()`, ¿dónde guardas estos campos?
    - `encf` (e-NCF asignado)
    - `estado` (`Aceptado`, `En Proceso`, `Rechazado`, …)
    - `estadoDescripcion`
    - `codigoSeguridad`
    - `fechaFirma`
    - `timbre` (URL)
    - `secuenciaUtilizada` (bool)
17. ¿Quieres tabla aparte para errores de envío o columna en el mismo maestro?

### Bloque I — Sync masivo (si aplica)

18. ¿Cómo manejas locks hoy? (advisory lock Postgres, sp_getapplock SQL Server, file lock).
19. ¿Cómo identificas registros pendientes? (estado/columna específica + condición).

Cuando se complete el bloque que corresponda al alcance del integrador, **resumir las respuestas y confirmar antes de generar código**.

## Fase 3 — Generar código de integración

Producir un **adapter** en el lenguaje elegido con:

- Función o método `armarDocumentoEcf(controlOnumero)` que:
  - Lee maestro/detalle/empresa/cliente/suplidor/referencia desde tablas del ERP.
  - Devuelve un `DocumentoEcf` listo para `enviaEcfDesde()`.
- Función `persistirRespuesta(documentoEnviado)`:
  - Toma el `DocumentoEcf` enriquecido (con `encf`, `estado`, `timbre`, …) y hace UPDATE en las tablas del ERP.
- Si aplica: función `procesarPendientes()` que:
  - Lockea, lista pendientes del ERP, llama `consultaEstado(...)`, persiste resultados.
- Imports/dependencias mínimas. Comentarios `TODO:` solo donde falte info del integrador.

Patrón de salida (adaptar al lenguaje):

```dart
// Dart — adapter del integrador
import 'package:dart_driver_poc/ecf_client.dart';

class MiErpEcfAdapter {
  final EcfClient client;
  final MyDb db;
  MiErpEcfAdapter(this.client, this.db);

  Future<DocumentoEcf> armarDocumento(String controlVenta) async {
    final m = await db.query('SELECT * FROM <tabla_venta> WHERE <pk> = ?', [controlVenta]);
    final lineas = await db.query('SELECT * FROM <tabla_lineas> WHERE <fk> = ?', [controlVenta]);
    final cli = await db.query('SELECT rnc, nombre FROM <tabla_clientes> WHERE id = ?', [m.cliente_id]);
    // ... mapeo según respuestas del integrador ...
    return DocumentoEcf(
      fiscal: <derivar de m.tipo o m.flag>,
      encf: m.encf,
      fecha: m.fecha,
      // etc.
    );
  }

  Future<void> emitir(String controlVenta) async {
    final doc = await armarDocumento(controlVenta);
    final enviado = await client.enviaEcfDesde(doc, portal: 'testecf');
    await db.execute('''
      UPDATE <tabla_venta> SET
        encf = ?, estado = ?, timbre = ?, codigo_seguridad = ?, fecha_firma = ?
      WHERE <pk> = ?
    ''', [enviado.encf, enviado.estado, enviado.timbre,
          enviado.codigoSeguridad, enviado.fechaFirma, controlVenta]);
  }

  Future<void> procesarPendientes() async {
    final pendientes = await db.query("SELECT encf FROM <tabla_venta> WHERE estado = 'En Proceso'");
    final res = await client.consultaEstado(pendientes.map((r) => r.encf).toList());
    // persistir cada resultado en su fila
  }
}
```

Si el integrador eligió un lenguaje **nuevo** (no en la lista de los 5), avisar que primero hay que sumar el lenguaje al sistema (ver `MEMORY.md` → `project_proceso_nuevo_cliente_lenguaje.md`, 10 pasos: SQL para tabla `data.<lang>_cliente_driver`, fns lookup/descargar/publicar, extender `fn.ejecutar`, loader, compilador, publicador, CLI test, sync repo público).

## Reglas operativas

- **Siempre español** salvo que el integrador escriba en otro idioma.
- **No inventar nombres de tabla/columna**: si falta dato, dejar `TODO:` y seguir.
- **No asumir motor de BD del integrador**: hasta no preguntar, no escribir SQL.
- **El integrador NO escribe lógica DGII**: validación de tipo 32 sin comprador, pre-validación de fecha, tope NC, manual RFCE — todo eso lo hace el motor. Si el integrador pregunta por esa lógica, decirle que el motor lo hace por él.
- **Recordar Fase 1 DGII**: tipo 32 (Consumo) NO usa polling asíncrono. Si el integrador propone diseño con polling de estado en 32, advertir.
- **Confirmar BD destino antes de publicar motor**: si el trabajo escala a publicar nueva versión del motor, exigir declarar `test 5433` o `produccion 5432` antes de ejecutar.
- **No exponer credenciales BD del integrador en el cliente**: el cliente shell solo habla HTTP a `ecf-service.vicortiz.com`. Las credenciales BD del integrador son de su problema, nunca tocan el cliente Chalona.

## Referencias

- Cliente Dart de referencia: `chalona-ecf/dart-driver/README.md` (ejemplos por tipo + API completa).
- Manual integración Fox: `chalona-ecf/fox/chalona-ecf-integracion.html`.
- Manual API REST Alberto (Fox): `chalona-ecf/fox/alberto/manual-api-rest.html`.
- Quickstarts por lenguaje: `chalona-ecf/docs/{dart,csharp,typescript,python,fox}-quickstart.md`.
