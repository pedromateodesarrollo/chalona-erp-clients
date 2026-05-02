# Quickstart — Cliente TypeScript

## Pre-requisitos

- Node.js 20+
- Postgres con el [schema](../sql/schema.sql) aplicado
- `psql` y `python3` en el PATH (publisher los usa)

## Diferencia respecto a otros clientes

V8 no expone bytecode portable para distribución, así que el "bytecode" es
**JS source UTF-8** transpilado por `tsc` desde TypeScript. El cliente lo
ejecuta con `node:vm`:

- `vm.Script` compila el JS una vez, lo ejecuta en un sandbox.
- El sandbox **no tiene** `require`, `fs`, `process`, `child_process` ni
  globals de Node — solo `console`, `JSON`, `Math`, `Date`, primitivos.
- Hot-swap = descartar el handle y dejar GC liberar (sin `Unload()` real
  como C#, similar a `dart_eval` en Dart).

Trade-off: source en lugar de bytecode (~3-15 KB texto vs binario denso),
pero zero dependencias de runtime.

## Layout

```
typescript-driver/
├── package.json                        # devDeps: typescript, @types/node
├── tsconfig.json
├── publicar.sh                         # publisher CLI
├── src/
│   ├── contract.ts                     # interface ComprobanteDriver
│   ├── loader.ts                       # DriverHandle.cargar() + cache
│   ├── postgres-source.ts              # lookup/descargar/publicar via psql
│   └── compiler.ts                     # tsc → CommonJS + IIFE wrapper
├── bin/
│   ├── compilar.ts                     # CLI: .ts → JS source bytes
│   └── prueba-comprobantes-driver.ts   # demo CLI: 9 casos de prueba
└── driver_src/
    └── driver-comprobantes.ts          # driver con validación e-CF
```

## 1. Aplicar schema

```bash
psql -h localhost -U postgres -d midb -f ../sql/schema.sql
```

Crea `data.ts_cliente_driver` + `fn.ts_cliente_driver_lookup/descargar/publicar`.

## 2. Instalar deps + build

```bash
cd typescript-driver
npm install
./node_modules/.bin/tsc -p tsconfig.json
```

`publicar.sh` hace `npm install` automático en el primer run.

## 3. Publicar el driver

```bash
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret \
./publicar.sh
```

Esto:

1. Compila `driver_src/driver-comprobantes.ts` con tsc → JS source.
2. Envuelve en IIFE para sandbox vm (define `module`/`exports` locales).
3. Calcula sha256.
4. Llama `fn.ts_cliente_driver_publicar` (verifica hash server-side).
5. Inserta como versión activa en `entorno='test'`.

Producción: `./publicar.sh --produccion`. Otra fuente: `./publicar.sh --fuente=driver_src/X.ts`.

## 4. Correr el cliente de prueba

```bash
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret ENTORNO=test \
node dist/bin/prueba-comprobantes-driver.js
```

Salida esperada:

```
== Lookup driver TS @ test (localhost:5432/midb)
   activo: v1  3287 bytes  sha256=8aea1399a069...
   cargado: instancia.version='v1'

== Casos:
   [OK  ] tipo 31 OK
   [OK  ] tipo 32 OK monto bajo
   [OK  ] tipo inválido errores=["tipo inválido: 99 (debe ser 31, 32, 33 o 34)"]
   ...

9 pasaron, 0 fallaron
```

## 5. Hot-reload en acción

Modifica `driver_src/driver-comprobantes.ts` (cambia una regla, agrega
validación). Republica:

```bash
./publicar.sh
```

Re-corre el cliente — baja la versión nueva sin reinstalar nada.

## Integrar en tu app

```typescript
import { PostgresDriverSource } from '@chalona/typescript-driver/dist/src/postgres-source.js';
import { DriverHandle } from '@chalona/typescript-driver/dist/src/loader.js';

const source = new PostgresDriverSource(
  { host: 'localhost', port: 5432, database: 'midb', user: 'u', password: 'p' },
  'produccion'
);

let driver: DriverHandle | null = null;

async function validarComprobante(doc: Record<string, unknown>): Promise<boolean> {
  const meta = await source.lookup();
  if (!meta) throw new Error('no driver');

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

En producción agrega:

- Cache local en disco entre arranques (`DriverCache` en `loader.ts`)
- Retry con backoff si lookup falla por red
- Fallback a último driver cacheado si el server está caído

## Contrato del driver

El driver descargado debe exportar (por default o named export) una clase
que implemente:

```typescript
interface ComprobanteDriver {
  readonly version: string;
  preValidar(c: Record<string, unknown>): { ok: boolean; errores: string[] };
}
```

El loader busca primero `__exports.default`, luego cualquier export que sea
una función/constructor.

## Sandbox — qué tiene y qué no

**Disponible:** `console`, `JSON`, `Math`, `Date`, `Number`, `String`,
`Boolean`, `Array`, `Object`, `RegExp`, `Map`, `Set`, `Error`.

**No disponible:** `require`, `import`, `fs`, `process`, `child_process`,
`Buffer` global, `setTimeout`/`setInterval`, ni cualquier API de Node.

Si necesitas APIs externas en tu driver, exponlas como **bridges** en el
sandbox (extender el objeto pasado a `vm.createContext`).

## Limitaciones

- **No bytecode portable**: ship JS source — visible en la BD si alguien
  consulta `data.ts_cliente_driver.bytes`. Considéralo público.
- **No hot-unload real**: V8 retiene los `Script` compilados hasta GC.
  En long-running processes, descarta el handle viejo y deja que la
  instancia anterior se libere por GC.
- **Sin `eval` ni `new Function` interno** del driver — el sandbox bloquea
  importar dinámicamente otro código.
