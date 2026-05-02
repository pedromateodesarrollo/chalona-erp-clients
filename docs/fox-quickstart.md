# Quickstart — Cliente Fox (Visual FoxPro)

## Pre-requisitos

- Visual FoxPro 9 (cliente)
- Postgres con el [schema](../sql/schema.sql) aplicado
- `psql` y `python3` en el PATH (publisher los usa)

## Concepto

El cliente Fox tiene tres archivos:

| Archivo | Qué hace |
|---|---|
| `chalona-ecf-loader.prg` | Mini-loader: pregunta al servidor por la versión activa, baja el `.prg` si cambió, lo compila a `.fxp` único, hace `SET PROCEDURE`. |
| `chalona-ecf.prg` | Cuerpo principal del cliente. Es lo que se actualiza en caliente. |
| `chalona-ecf-driver-default.prg` | Driver default (interfaz con tu ERP). Reemplazable por el dev. |

El loader es el único que vive estático en la instalación VFP. El resto se
descarga al arrancar y se reemplaza cuando hay versión nueva.

## 1. Aplicar schema

```bash
psql -h localhost -U postgres -d midb -f ../sql/schema.sql
```

## 2. Publicar la primera versión

```bash
cd fox
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret \
./publicar.sh
```

Por defecto publica a `entorno='test'`. Para producción:

```bash
./publicar.sh --produccion
```

## 3. Setup en el cliente VFP

Copia `chalona-ecf-loader.prg` a la instalación VFP del usuario. Llama una
vez al arrancar tu ERP:

```foxpro
DO chalona-ecf-loader.prg
```

El loader hace lo siguiente la primera vez (y en cada llamada):

1. `SELECT fn.fox_cliente_script(jsonb)` con la versión local.
2. Si no coincide con la activa, descarga el script nuevo.
3. Lo guarda como `chalona-ecf-<timestamp>.prg`, lo compila a `.fxp`.
4. `SET PROCEDURE TO chalona-ecf-<timestamp>.fxp ADDITIVE`.

A partir de ahí las llamadas a funciones del cliente (`chalona_ecf_*`)
resuelven al código nuevo.

## 4. Hot-reload

Modifica `chalona-ecf.prg`. Republica:

```bash
./publicar.sh
```

La próxima vez que el ERP del usuario llame al cliente, el loader detecta la
versión nueva y la activa. Sin reinstalar VFP, sin recompilar el ERP.

## Driver custom

El driver default (`chalona-ecf-driver-default.prg`) provee la interfaz
genérica al ERP host. Si tu ERP tiene tablas con nombres distintos, escribes
tu propio driver e instancias antes de llamar a las funciones:

```foxpro
LOCAL loDriver
loDriver = CREATEOBJECT("MiDriverPersonalizado")
chalona_ecf_set_driver(loDriver)
chalona_ecf_emitir_factura(...)
```

Ver `examples/alberto-ecf-driver.prg` para un driver completo de ejemplo.

## Documentación de integración

[`chalona-ecf-integracion.html`](../fox/chalona-ecf-integracion.html) tiene
la referencia completa de la API del cliente Fox: funciones disponibles,
parámetros, contrato del driver, errores.

## Gotchas VFP

- ⛔ **No usar `RETURN` dentro de bloques `TRY/CATCH`**: VFP no lo permite.
  Usar un flag (`lcSalir = .T.`) y un `IF` después del `ENDTRY`.
- Los `.fxp` cacheados por VFP no se invalidan automáticamente. El loader
  resuelve esto generando nombres únicos por versión (`chalona-ecf-v9.fxp`).
- En producción, el `.fxp` viejo queda en disco. Limpiar periódicamente.

## Estructura

```
fox/
├── chalona-ecf-loader.prg           # estático en cliente
├── chalona-ecf.prg                  # cuerpo (se actualiza)
├── chalona-ecf-driver-default.prg   # driver default
├── chalona-ecf-integracion.html     # docs API completa
├── publicar.sh                      # publisher CLI
└── examples/
    ├── alberto-ecf-driver.prg       # ejemplo de driver custom
    ├── ecf.prg                      # ejemplo de uso
    ├── cncfe_basedata.prg           # ejemplo
    ├── cncfe_document.prg           # ejemplo
    └── manual-api-rest.html         # alternativa REST sin loader
```
