# Instalar la skill `driver-cliente` en tu agente de IA

Esta guía instala la **misma skill `driver-cliente`** en distintos agentes de
IA. La skill detecta tu lenguaje y BD, descarga sólo el cliente que te
conviene, te lleva por las preguntas de diseño y genera el driver concreto
contra **tus** tablas.

## ¿Cuál usás?

| Agente | Comando de instalación |
|---|---|
| Claude Code | [Claude Code](#claude-code) |
| Cursor | [Cursor](#cursor) |
| Windsurf | [Windsurf](#windsurf) |
| GitHub Copilot | [Copilot](#github-copilot) |
| Copilot Chat (slash prompts) | [Copilot Chat](#copilot-chat-slash-prompts) |
| Aider | [Aider](#aider) |
| Continue.dev | [Continue.dev](#continuedev) |
| Cline | [Cline](#cline) |
| Zed | [Zed](#zed) |
| Otro / sin agente | [Guía estática](#guia-estatica) |

Todos los comandos se corren desde la **raíz del repo donde vas a integrar
Chalona ECF**.

---

## Claude Code

```bash
mkdir -p .claude/skills/driver-cliente \
  && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/driver-cliente/SKILL.md \
       -o .claude/skills/driver-cliente/SKILL.md
```

Uso: en Claude Code, decí `/driver-cliente` o "quiero integrar chalona con mi
ERP".

## Cursor

```bash
mkdir -p .cursor/rules \
  && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/cursor/driver-cliente.mdc \
       -o .cursor/rules/driver-cliente.mdc
```

Uso: Cursor activará la regla cuando detecte triggers en tu prompt
("integrar chalona", "instalar cliente", etc.).

## Windsurf

```bash
curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/windsurf/.windsurfrules \
  -o .windsurfrules
```

Versión condensada (≤6000 chars) por límite de Windsurf. Activa en cada turno.

## GitHub Copilot

Instrucciones persistentes en todo el repo:

```bash
mkdir -p .github \
  && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/copilot/copilot-instructions.md \
       -o .github/copilot-instructions.md
```

Si ya tenés `copilot-instructions.md`, hacé append en vez de overwrite:

```bash
curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/copilot/copilot-instructions.md \
  >> .github/copilot-instructions.md
```

## Copilot Chat (slash prompts)

```bash
mkdir -p .github/prompts \
  && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/copilot-prompts/driver-cliente.prompt.md \
       -o .github/prompts/driver-cliente.prompt.md
```

Uso: en Copilot Chat, escribí `/driver-cliente`.

## Aider

```bash
curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/aider/CONVENTIONS.md \
  -o CONVENTIONS.md
```

Uso: lanzá aider con `--read CONVENTIONS.md` (o agregalo a tu
`.aider.conf.yml`).

## Continue.dev

```bash
mkdir -p .continue/prompts \
  && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/continue/driver-cliente.prompt.md \
       -o .continue/prompts/driver-cliente.prompt.md
```

Uso: en Continue, escribí `/driver-cliente`.

## Cline

```bash
curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/cline/.clinerules \
  -o .clinerules
```

Activa en cada turno.

## Zed

Si usás `.zed/ai.md` para reglas del proyecto:

```bash
mkdir -p .zed \
  && curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/zed/driver-cliente.md \
       -o .zed/driver-cliente.md
```

Uso: agregá la entrada como Prompt Library en Zed (Settings → AI → Prompt
Library) o referenciala manualmente en el chat.

## Guía estática

Si no usás agente de IA, descargá la skill como guía de lectura:

```bash
curl -fsSL https://raw.githubusercontent.com/pedromateodesarrollo/chalona-erp-clients/main/skill/driver-cliente/SKILL.md \
  -o GUIA-INTEGRACION.md
```

Estructura:
- Fase 0 — qué subcarpeta del repo descargar y cómo
- Fase 1 — cómo funciona el sistema (motor + driver + hot-reload)
- Fase 2 — qué preguntas responder sobre tus tablas
- Fase 3 — qué shape tiene el driver final

---

## Actualizaciones

La skill se versiona junto al repo público. Para refrescar, repetí el comando
de instalación correspondiente — sobreescribe el archivo local.

Considerá committearla a tu repo para que tu equipo la tenga al alcance sin
volver a descargar.
