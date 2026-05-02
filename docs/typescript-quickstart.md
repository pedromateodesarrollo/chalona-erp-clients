# Quickstart — Cliente TypeScript

## Audiencia

Esta guía es para un **integrador** que quiere consumir el motor
TypeScript hot-reload publicado por Chalona desde una app Node. Tú no
hospedás Postgres ni publicás nada — Chalona ya lo hizo. Tu app solo
se conecta a la BD de Chalona y baja el driver.

Si querés hospedar tu propio motor (forkear el patrón hot-reload para
tu producto), saltá al final: [Self-hosting (avanzado)](#self-hosting-avanzado).

## Pre-requisitos

- Node.js 20+
- Acceso de red a la BD Postgres de Chalona (host, port, db, user, pass —
  provistos por Chalona)

**No necesitás aplicar schema ni publicar nada.** El motor vive en la BD
de Chalona y se baja a tu app via lookup.

## Mecanismo

V8 no expone bytecode portable, así que el "bytecode" es **JS source
UTF-8** transpilado por `tsc`. El cliente lo ejecuta con `node:vm`:

- `vm.Script` compila el JS una vez, lo ejecuta en un sandbox.
- El sandbox **no tiene** `require`, `fs`, `process`, `child_process` ni
  globals de Node — solo `console`, `JSON`, `Math`, `Date`, primitivos.
- Hot-swap = descartar el handle y dejar GC liberar (similar a Dart).

Trade-off: source en lugar de bytecode (~3-15 KB), zero dependencias
de runtime.

## 1. Instalar

```bash
cd typescript-driver
npm install
./node_modules/.bin/tsc -p tsconfig.json
```

## 2. Configurar conexión y usar

```typescript
import { PostgresDriverSource } from '@chalona/typescript-driver/dist/src/postgres-source.js';
import { DriverHandle } from '@chalona/typescript-driver/dist/src/loader.js';

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

let driver: DriverHandle | null = null;

async function validarComprobante(doc: Record<string, unknown>): Promise<boolean> {
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
en `loader.ts`), retry con backoff, fallback al driver cacheado.

## 3. Demo CLI

```bash
PG_HOST=<host> PG_DB=<db> PG_USER=<u> PG_PASS=<p> ENTORNO=test \
  node dist/bin/prueba-comprobantes-driver.js
```

Salida esperada:

```
== Lookup driver TS @ test
   activo: v1  3287 bytes  sha256=8aea1399a069...
   cargado: instancia.version='v1'

== Casos:
   [OK  ] tipo 31 OK
   [OK  ] tipo 32 OK monto bajo
   [OK  ] tipo invalido errores=["tipo invalido: 99 ..."]
   ...

9 pasaron, 0 fallaron
```

## Contrato del driver

El driver descargado exporta (por default o named) una clase que
implementa:

```typescript
interface ComprobanteDriver {
  readonly version: string;
  preValidar(c: Record<string, unknown>): { ok: boolean; errores: string[] };
}
```

El loader busca primero `__exports.default`, luego cualquier export que
sea una función/constructor.

## Sandbox — qué tiene y qué no

**Disponible:** `console`, `JSON`, `Math`, `Date`, `Number`, `String`,
`Boolean`, `Array`, `Object`, `RegExp`, `Map`, `Set`, `Error`.

**No disponible:** `require`, `import`, `fs`, `process`,
`child_process`, `Buffer` global, `setTimeout`/`setInterval`, ni
cualquier API de Node.

Si tu driver necesita APIs externas, exponlas como **bridges** en el
sandbox (extender el objeto pasado a `vm.createContext`).

## Limitaciones

- **No bytecode portable**: ship JS source — visible en la BD si alguien
  consulta `data.ts_cliente_driver.bytes`. Considéralo público.
- **No hot-unload real**: V8 retiene los `Script` compilados hasta GC.
  En long-running processes, descartar el handle viejo libera la
  instancia anterior por GC.
- **Sin `eval` ni `new Function` interno** del driver — el sandbox
  bloquea importar dinámicamente otro código.

## Layout del cliente

```
typescript-driver/
├── package.json
├── tsconfig.json
├── publicar.sh                         # solo si self-hosting
├── src/
│   ├── contract.ts                     # interface ComprobanteDriver
│   ├── loader.ts                       # DriverHandle.cargar() + cache
│   ├── postgres-source.ts              # lookup/descargar via psql
│   └── compiler.ts                     # tsc → CommonJS + IIFE
├── bin/
│   ├── compilar.ts                     # CLI: .ts → JS source bytes
│   └── prueba-comprobantes-driver.ts
└── driver_src/                         # solo si self-hosting
    └── driver-comprobantes.ts
```

---

## Self-hosting (avanzado)

Solo si querés hospedar tu propio motor.

### Pre-requisitos extra

- Postgres con el [schema](../sql/schema.sql) aplicado
- `psql` y `python3` en el PATH

### 1. Aplicar schema

```bash
psql -h localhost -U postgres -d midb -f ../sql/schema.sql
```

Crea `data.ts_cliente_driver` + `fn.ts_cliente_driver_lookup/descargar/publicar`.

### 2. Publicar

```bash
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret \
  ./publicar.sh
```

Compila `driver_src/driver-comprobantes.ts` → JS, envuelve en IIFE para
sandbox, calcula sha256, llama `fn.ts_cliente_driver_publicar`, inserta
activo en `entorno='test'`.

Producción: `./publicar.sh --produccion`. Otra fuente:
`./publicar.sh --fuente=driver_src/X.ts`.

### 3. Hot-reload

Modificá el driver fuente. Republicá. Próxima llamada del cliente baja
versión nueva.
