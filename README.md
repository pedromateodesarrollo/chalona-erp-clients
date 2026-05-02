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

### Opción B — Manual (consumir motor de Chalona)

Para integradores. **No requiere aplicar schema ni publicar nada** — el
motor lo publica Chalona. Solo necesitás credenciales de acceso al server.

| Cliente | Cómo se conecta | Doc |
|---|---|---|
| Fox | HTTP a server-ecf (Chalona) | [fox-quickstart.md](docs/fox-quickstart.md) |
| Dart | Postgres directo (host/credenciales provistos por Chalona) | [dart-quickstart.md](docs/dart-quickstart.md) |
| C# | Postgres directo | [csharp-quickstart.md](docs/csharp-quickstart.md) |
| TypeScript | Postgres directo | [typescript-quickstart.md](docs/typescript-quickstart.md) |
| Python | Postgres directo | [python-quickstart.md](docs/python-quickstart.md) |

Cada quickstart incluye al final una sección "Self-hosting (avanzado)"
para quien quiera correr su propio motor (forkear el patrón). Caso
típico: NO necesario para integradores Chalona.

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

### Option B — Manual (consume Chalona's engine)

For integrators. **No need to apply schema or publish anything** —
Chalona publishes the engine. You just need server credentials.

| Client | Connects via | Doc |
|---|---|---|
| Fox | HTTP to Chalona's server-ecf | [fox-quickstart.md](docs/fox-quickstart.md) |
| Dart | Direct Postgres (host/creds provided by Chalona) | [dart-quickstart.md](docs/dart-quickstart.md) |
| C# | Direct Postgres | [csharp-quickstart.md](docs/csharp-quickstart.md) |
| TypeScript | Direct Postgres | [typescript-quickstart.md](docs/typescript-quickstart.md) |
| Python | Direct Postgres | [python-quickstart.md](docs/python-quickstart.md) |

Each quickstart ends with a "Self-hosting (advanced)" section for
forking the hot-reload pattern to host your own engine. Typically NOT
needed for Chalona integrators.

## License

[MIT](LICENSE)
