# Quickstart — Cliente Node.js (puro JS)

## Audiencia

Esta guía es para un **integrador** que quiere consumir el motor Node.js
hot-reload publicado por Chalona desde una app Node sin TypeScript. Tu app
solo se conecta a la BD de Chalona y baja el driver — Chalona ya publicó el
motor.

Si querés hospedar tu propio motor (forkear el patrón hot-reload), saltá al
final: [Self-hosting (avanzado)](#self-hosting-avanzado).

## Diferencia con `typescript-driver`

| | typescript-driver | nodejs-driver |
|---|---|---|
| Lenguaje del motor | TypeScript (transpilado con `tsc`) | JavaScript puro |
| Paso de compilación al publicar | `tsc` → JS → IIFE wrap | ninguno: el `.js` sube tal cual |
| Deps de runtime | ninguna (solo `node:vm`) | ninguna (solo `node:vm`) |
| Tabla Postgres | `data.ts_cliente_driver` | `data.nodejs_cliente_driver` |
| Pensado para | Equipos que ya usan TS | Equipos en Node puro, scripts, Lambdas mini |

Mismo loader pattern (vm.Script en sandbox aislado), distintas tablas e
independencia de versiones.

## Pre-requisitos

- Node.js 20+
- Acceso de red a la BD Postgres de Chalona (host, port, db, user, pass —
  provistos por Chalona)

**No necesitás aplicar schema ni publicar nada.** El motor vive en la BD de
Chalona y se baja a tu app via lookup.

## Mecanismo

Igual a `typescript-driver` pero sin transpile: V8 ejecuta JS source directo
con `vm.Script` en sandbox sin `require`, `fs`, `process`, ni globals de
Node. Hot-swap = descartar el handle y dejar GC liberar.

Trade-off: JS source visible en la BD (~3 KB), zero dependencias de runtime,
zero compilación al publicar.

## 1. Instalar

```bash
cd nodejs-driver
# no hay npm install — no hay deps
```

## 2. Configurar conexión y usar

```javascript
import { PostgresDriverSource } from '@chalona/nodejs-driver/src/postgres-source.js';
import { DriverHandle } from '@chalona/nodejs-driver/src/loader.js';
import { Buffer } from 'node:buffer';

const source = new PostgresDriverSource(
  {
    host:     '<host_provisto_por_chalona>',
    port:     5432,
    database: '<db_provista>',
    user:     '<usuario_provisto>',
    password: '<clave_provista>',
  },
  'test'   // o 'produccion'
);

let driver = null;

async function validarComprobante(doc) {
  const meta = await source.lookup();
  if (!meta) throw new Error('no driver activo');

  if (driver?.version !== `v${meta.version}`) {
    const bytes = await source.descargar();
    const js = Buffer.from(bytes).toString('utf-8');
    driver = DriverHandle.cargar(js, `v${meta.version}`);
    if (driver.hashSha256 !== meta.hashSha256) throw new Error('hash mismatch');
  }

  const { ok } = driver.instancia.preValidar(doc);
  return ok;
}
```

En producción agregá: cache local en disco entre arranques (`DriverCache`
en `loader.js`), retry con backoff, fallback al driver cacheado.

## 3. Demo CLI

```bash
PG_HOST=<host> PG_PORT=<port> PG_DB=<db> PG_USER=<u> PG_PASS=<p> ENTORNO=test \
  node bin/prueba-comprobantes-driver.js
```

Salida esperada:

```
== Lookup driver Node.js @ test
   activo: v1  3295 bytes  sha256=296314d8ef3f...
   cargado: instancia.version='v1'

== Casos:
   [OK  ] tipo 31 OK
   [OK  ] tipo 32 OK monto bajo
   [OK  ] tipo inválido errores=["tipo inválido: 99 ..."]
   [OK  ] fecha inválida errores=["fecha_emision inválida: ..."]
   [OK  ] tipo 31 sin RNC comprador errores=["rnc_comprador requerido ..."]
   [OK  ] tipo 32 manual RFCE excedido errores=["tipo 32 con monto >= 250000 ..."]
   [OK  ] NC excede tope errores=["NC excede tope: monto 5000 ..."]
   [OK  ] NC dentro de tope
   [OK  ] monto cero errores=["monto_total debe ser > 0 ..."]

9 pasaron, 0 fallaron
```

## Contrato del driver

El driver descargado asigna a `__exports.default` (o cualquier named export
que sea constructor) una clase con:

```javascript
class DriverV1 {
  version = 'v1';
  preValidar(comprobante) {
    return { ok: true, errores: [] };
  }
}
__exports.default = DriverV1;
```

El loader busca primero `__exports.default`, luego cualquier export que
sea una función/constructor.

## Sandbox — qué tiene y qué no

**Disponible:** `console`, `JSON`, `Math`, `Date`, `Number`, `String`,
`Boolean`, `Array`, `Object`, `RegExp`, `Map`, `Set`, `Error`.

**No disponible:** `require`, `import`, `fs`, `process`,
`child_process`, `Buffer` global, `setTimeout`/`setInterval`, ni cualquier
API de Node.

Si tu driver necesita APIs externas, exponlas como **bridges** en el
sandbox (extender el objeto pasado a `vm.createContext` en `src/loader.js`).

## Limitaciones

- **No bytecode portable**: ship JS source — visible en la BD si alguien
  consulta `data.nodejs_cliente_driver.bytes`. Considéralo público.
- **No hot-unload real**: V8 retiene los `Script` compilados hasta GC.
  Descartar el handle viejo libera la instancia anterior por GC.
- **Sin `eval` ni `new Function`** dentro del driver — el sandbox no
  expone esos constructores.

## Layout del cliente

```
nodejs-driver/
├── package.json                          # ESM, zero deps
├── publicar.sh                           # solo si self-hosting
├── src/
│   ├── contract.js                       # doc del contrato
│   ├── loader.js                         # DriverHandle.cargar() + DriverCache
│   └── postgres-source.js                # lookup/descargar/publicar via psql
├── bin/
│   ├── publicar.js                       # CLI: sube .js a Postgres
│   └── prueba-comprobantes-driver.js     # demo end-to-end
└── driver_src/                           # solo si self-hosting
    └── driver-comprobantes.js
```

---

## Self-hosting (avanzado)

Solo si querés hospedar tu propio motor.

### Pre-requisitos extra

- Postgres con el [schema](../sql/schema.sql) aplicado
- `psql` en el PATH

### 1. Aplicar schema

```bash
psql -h localhost -U postgres -d midb -f ../sql/schema.sql
```

Crea `data.nodejs_cliente_driver` + `fn.nodejs_cliente_driver_lookup/descargar/publicar`.

### 2. Publicar

```bash
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret \
  ./publicar.sh
```

Lee `driver_src/driver-comprobantes.js`, calcula sha256, llama
`fn.nodejs_cliente_driver_publicar`, inserta activo en `entorno='test'`.

Producción: `./publicar.sh --produccion`. Otra fuente:
`./publicar.sh --fuente=driver_src/X.js`.

### 3. Hot-reload

Modificá el driver fuente. Republicá. Próxima llamada del cliente baja
versión nueva.

### 4. Validación de versión en `fn.ejecutar`

Si el cliente incluye `nodejs_driver_version` + `nodejs_driver_entorno` en
los params del request, `fn.ejecutar` valida contra la versión activa y
devuelve `nodejs_cliente_driver.version_desactualizada` si hay desajuste,
para que el cliente baje la nueva versión y reintente.
