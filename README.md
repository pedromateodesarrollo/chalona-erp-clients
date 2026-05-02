# Chalona ERP Clients

Clientes oficiales para integrar tu ERP con la plataforma de facturación
electrónica (e-CF) de Chalona, con **hot-reload de lógica**: el comportamiento
del cliente se actualiza desde el servidor sin que el usuario reinstale ni
reinicie nada.

> 🇺🇸 [English version below](#english)

---

## Patrón

Un cliente tradicional incluye toda su lógica de validación/transformación
hardcodeada en el binario. Cuando hay un bug, hay que redistribuirlo a todos
los usuarios. Esto duele especialmente si:

- La app está publicada en una App Store con tiempos de revisión.
- Hay muchos clientes con instalaciones on-premise.
- El cliente es un binario compilado distribuido a usuarios finales.

**Solución (igual a un loader)**:

1. Cada request del cliente al servidor incluye su versión local.
2. Si la versión no coincide con la activa en el servidor, este responde
   `version_desactualizada` con metadata de la versión nueva.
3. El cliente baja la nueva lógica, la carga en caliente, y reintenta el
   request.
4. El usuario nunca se entera.

Sin polling. Sin push notifications. Sin instaladores. La lógica viaja con la
data.

```
                     ┌──────────────┐
   POST /endpoint    │   Servidor   │
   { doc, ver: 7 } ─→│              │
                     │ activa = 9   │
                     └──────┬───────┘
                            │ 409 { version_actual: 9, ... }
                            ▼
                     ┌──────────────┐
                     │   Cliente    │  baja v9, carga, reintenta
                     │              │
                     └──────────────┘
```

## Contenido

| Carpeta | Para |
|---|---|
| [`fox/`](fox/) | Cliente Visual FoxPro — para ERPs legados que ya corren en VFP |
| [`dart-driver/`](dart-driver/) | Cliente Dart — para apps modernas (Flutter / Dart server / CLI) |
| [`csharp/`](csharp/) | Cliente C# / .NET — Roslyn + AssemblyLoadContext, hot-swap real con `Unload()` |
| [`typescript-driver/`](typescript-driver/) | Cliente TypeScript — JS source via `node:vm` sandbox, sin deps de runtime |
| [`python-driver/`](python-driver/) | Cliente Python — `.py` source via `exec()` en namespace aislado, stdlib only |
| [`sql/`](sql/) | Schema Postgres standalone (tablas + funciones) |
| [`docs/`](docs/) | Arquitectura, quickstarts, limitaciones |

## Cómo empezar

### Opción A — Asistido por agente de IA (recomendado)

Instalá la skill **`driver-cliente`** en tu agente y dejá que él:

1. Te pregunte tu lenguaje y motor de BD.
2. Descargue **solo** el cliente que te conviene de este repo.
3. Te lleve por las preguntas de diseño (clientes, facturas, compras,
   suplidores, escritura de respuesta DGII).
4. Genere el driver concreto con queries scaffolded contra **tus** tablas.

Instalación según tu agente (una sola línea desde la raíz de tu repo):

| Agente | Comando |
|---|---|
| Claude Code | `mkdir -p .claude/skills/driver-cliente && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/driver-cliente/SKILL.md -o .claude/skills/driver-cliente/SKILL.md` |
| Cursor | `mkdir -p .cursor/rules && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/cursor/driver-cliente.mdc -o .cursor/rules/driver-cliente.mdc` |
| Windsurf | `curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/windsurf/.windsurfrules -o .windsurfrules` |
| GitHub Copilot | `mkdir -p .github && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/copilot/copilot-instructions.md -o .github/copilot-instructions.md` |
| Copilot Chat | `mkdir -p .github/prompts && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/copilot-prompts/driver-cliente.prompt.md -o .github/prompts/driver-cliente.prompt.md` |
| Aider | `curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/aider/CONVENTIONS.md -o CONVENTIONS.md` |
| Continue.dev | `mkdir -p .continue/prompts && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/continue/driver-cliente.prompt.md -o .continue/prompts/driver-cliente.prompt.md` |
| Cline | `curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/cline/.clinerules -o .clinerules` |
| Zed | `mkdir -p .zed && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/zed/driver-cliente.md -o .zed/driver-cliente.md` |

Detalles + cómo invocarla en cada agente en
[docs/install-skill.md](docs/install-skill.md).

Después decí `/driver-cliente` o "quiero integrar chalona con mi ERP".

### Opción B — Manual

#### 1. Aplicar schema en Postgres

```bash
psql -h localhost -U postgres -d midb -f sql/schema.sql
```

Crea las tablas `data.fox_cliente_script` y `data.dart_cliente_driver` más
las funciones de lookup/descarga/publicación.

#### 2. Cliente Fox

Ver [docs/fox-quickstart.md](docs/fox-quickstart.md).

```bash
cd fox
PG_HOST=localhost PG_DB=midb ./publicar.sh
```

#### 3. Cliente Dart

Ver [docs/dart-quickstart.md](docs/dart-quickstart.md).

```bash
cd dart-driver
dart pub get
PG_HOST=localhost PG_DB=midb ./publicar.sh
dart run bin/poc_postgres.dart
```

#### 4. Cliente C#

Ver [docs/csharp-quickstart.md](docs/csharp-quickstart.md).

```bash
cd csharp
dotnet build
PG_HOST=localhost PG_DB=midb ./publicar.sh
dotnet run --project src/ChalonaCsDriver.Cli
```

#### 5. Cliente TypeScript

Ver [docs/typescript-quickstart.md](docs/typescript-quickstart.md).

```bash
cd typescript-driver
PG_HOST=localhost PG_DB=midb ./publicar.sh
PG_HOST=localhost PG_DB=midb ENTORNO=test \
  node dist/bin/prueba-comprobantes-driver.js
```

#### 6. Cliente Python

Ver [docs/python-quickstart.md](docs/python-quickstart.md).

```bash
cd python-driver
PG_HOST=localhost PG_DB=midb ./publicar.sh
PG_HOST=localhost PG_DB=midb ENTORNO=test \
  python3 bin/prueba_comprobantes_driver.py
```

## Arquitectura

Lectura más profunda en [docs/architecture.md](docs/architecture.md):

- Patrón "version-on-request"
- Hot-swap atómico
- Cache local de versiones
- Verificación de hash SHA256
- Trade-offs de cada lenguaje (Fox interpretado vs Dart AOT con `dart_eval`)

## Limitaciones del cliente Dart

`dart_eval` (intérprete de bytecode) implementa solo un subset de Dart.
Si vas a meter lógica nueva al driver, lee
[docs/dart-eval-limitations.md](docs/dart-eval-limitations.md) primero.

Resumen rápido:

- ✓ Sintaxis Dart clase/método/async/generics
- ✓ `dart:core`, `dart:async`, `dart:math`
- ✗ `dart:mirrors`, `dart:ffi`, `dart:io` directo (bridges manuales)
- ✗ `num.round()` (usa `.toInt()` con offset)
- ⚠ `num` como tipo de parámetro causa boxing inconsistente — usa `int` o `double` específico

## Licencia

[MIT](LICENSE)

---

# English

Official clients to integrate your ERP with Chalona's electronic invoicing
(e-CF) platform, featuring **runtime hot-reload of logic**: the client's
behavior updates from the server with no reinstall or restart.

## Pattern

A traditional client bakes all validation/transformation logic into the
binary. Bug fixes require redistributing it to every user. That hurts
especially when:

- The app ships through an app store with review windows.
- Many customers run on-premise installs.
- The client is a compiled binary distributed to end users.

**Solution (loader pattern)**:

1. Each request includes the client's local version.
2. If it doesn't match the active version on the server, the server replies
   `version_desactualizada` with the new version's metadata.
3. The client downloads the new logic, hot-loads it, and retries the request.
4. The end user never notices.

No polling. No push notifications. No installers. Logic ships with data.

## Layout

| Folder | What for |
|---|---|
| `fox/` | Visual FoxPro client — for legacy ERPs already on VFP |
| `dart-driver/` | Dart client — for modern apps (Flutter / Dart server / CLI) |
| `csharp/` | C# / .NET client — Roslyn + AssemblyLoadContext, real `Unload()` hot-swap |
| `typescript-driver/` | TypeScript client — JS source via `node:vm` sandbox, no runtime deps |
| `python-driver/` | Python client — `.py` source via `exec()` in isolated namespace, stdlib only |
| `sql/` | Standalone Postgres schema (tables + functions) |
| `docs/` | Architecture, quickstarts, limitations |

## Getting started

### Option A — AI-agent assisted (recommended)

Install the **`driver-cliente`** skill into your AI agent of choice and let
it pick + download the right client, walk you through design questions, and
scaffold a driver against **your** tables.

Supported: Claude Code, Cursor, Windsurf, GitHub Copilot, Copilot Chat,
Aider, Continue.dev, Cline, Zed. See full per-agent install commands in
[docs/install-skill.md](docs/install-skill.md).

Quick install for Claude Code:

```bash
mkdir -p .claude/skills/driver-cliente \
  && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/driver-cliente/SKILL.md \
       -o .claude/skills/driver-cliente/SKILL.md
```

Then: `/driver-cliente` or "I want to integrate chalona with my ERP".

### Option B — Manual

```bash
# 1. Apply schema
psql -h localhost -U postgres -d mydb -f sql/schema.sql

# 2. Publish a driver (Fox)
cd fox && PG_HOST=localhost PG_DB=mydb ./publicar.sh

# 3. Publish a driver (Dart)
cd dart-driver && dart pub get
PG_HOST=localhost PG_DB=mydb ./publicar.sh
dart run bin/poc_postgres.dart

# 4. Publish a driver (C#)
cd csharp && dotnet build
PG_HOST=localhost PG_DB=mydb ./publicar.sh
dotnet run --project src/ChalonaCsDriver.Cli

# 5. Publish a driver (TypeScript)
cd typescript-driver
PG_HOST=localhost PG_DB=mydb ./publicar.sh
PG_HOST=localhost PG_DB=mydb ENTORNO=test \
  node dist/bin/prueba-comprobantes-driver.js

# 6. Publish a driver (Python)
cd python-driver
PG_HOST=localhost PG_DB=mydb ./publicar.sh
PG_HOST=localhost PG_DB=mydb ENTORNO=test \
  python3 bin/prueba_comprobantes_driver.py
```

See [`docs/`](docs/) for details and trade-offs.

## License

[MIT](LICENSE)
