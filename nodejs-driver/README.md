# @chalona/nodejs-driver

Cliente **Node.js puro** (JavaScript, sin TypeScript ni compilación) para e-CF
con hot-reload via Postgres. Espejo de `fox/`, `dart-driver/`, `csharp-driver/`,
`typescript-driver/` y `python-driver/`.

Patrón: el cliente trae el `loader` estático; el `motor` (driver-comprobantes.js)
vive en `data.nodejs_cliente_driver` y se baja en runtime. Cada request del
cliente incluye su versión; si Chalona publica una nueva, `fn.ejecutar` responde
`nodejs_cliente_driver.version_desactualizada` con la versión activa, el cliente
descarga, hot-swappea y reintenta.

## Por qué un cliente Node.js separado del de TypeScript

`typescript-driver` requiere `tsc` para transpilar antes de publicar. `nodejs-driver`
acepta JavaScript directo — el `.js` sube tal cual a la BD, igual que Fox sube
`.prg` interpretado. Útil para:

- Equipos en Node puro sin TypeScript.
- Lambdas / scripts donde no querés un paso de build.
- Drivers escritos a mano que ya son JS válido.

## Quickstart

```bash
PG_HOST=<host> PG_PORT=<port> PG_DB=<db> PG_USER=<u> PG_PASS=<p> ENTORNO=test \
  node bin/prueba-comprobantes-driver.js
```

Doc completa: [`docs/nodejs-quickstart.md`](../docs/nodejs-quickstart.md).

## Layout

```
nodejs-driver/
├── package.json                          # ESM, zero deps
├── publicar.sh                           # solo si self-hosting
├── src/
│   ├── contract.js
│   ├── loader.js                         # DriverHandle + DriverCache
│   └── postgres-source.js                # psql subprocess wrapper
├── bin/
│   ├── publicar.js                       # CLI sube .js a Postgres
│   └── prueba-comprobantes-driver.js     # demo end-to-end (9 casos)
└── driver_src/
    └── driver-comprobantes.js            # motor v1
```

## Tests

```bash
ENTORNO=test PG_HOST=localhost PG_PORT=5433 PG_DB=test PG_USER=pedro PG_PASS=camila \
  node bin/prueba-comprobantes-driver.js
# 9 pasaron, 0 fallaron
```

Mismo set de 9 casos que TS / Python / C# / Dart / Fox.

## Engine

Node.js 20+. Zero deps de runtime — sólo `node:vm`, `node:crypto`, `node:fs`,
`node:child_process` (para invocar `psql`).
