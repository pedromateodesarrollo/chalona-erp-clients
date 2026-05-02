# Quickstart — Cliente Fox (Visual FoxPro)

## Pre-requisitos

- Visual FoxPro 9 (cliente)
- Acceso de red al server-ecf (HTTP)
- Para publicar nuevas versiones del motor: Postgres con el [schema](../sql/schema.sql)
  aplicado del lado del **servidor** + `psql` y `python3` en el PATH

## Concepto

A diferencia de los clientes Dart/C#/TypeScript/Python (que se conectan a
Postgres directo), el cliente Fox usa una arquitectura HTTP:

```
[VFP cliente]  --HTTP-->  [server-ecf (Dart)]  --SQL-->  [Postgres]
chalona-ecf-loader.prg   ecf-service.vicortiz.com    data.fox_cliente_script
```

El cliente Fox tiene dos archivos:

| Archivo | Qué hace |
|---|---|
| `chalona-ecf-loader.prg` | Mini-loader estático en VFP. Pregunta al server-ecf por HTTP por la versión activa, baja el `.prg` si cambió, lo compila a `.fxp` único, hace `SET PROCEDURE`. |
| `chalona-ecf.prg` | Motor (cuerpo principal). Se descarga del server-ecf y se actualiza en caliente. Incluye lógica SQL Server por defecto + capa de cursores para ERPs distintos. |

El loader es el único que vive estático en la instalación VFP. El motor se
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

A diferencia de los clientes Dart/C#/TypeScript/Python, **el loader Fox NO se
conecta a Postgres**. Habla HTTP con el server-ecf (Dart) y este último es
quien consulta `data.fox_cliente_script` en Postgres.

Flujo del loader la primera vez (y en cada llamada):

1. `MSXML2.XMLHTTP` POST a `https://<servidor-ecf>/fox_cliente_script`
   con body `{"request":"fox_cliente_script","data":{"entorno":"test"}}`.
2. server-ecf consulta Postgres y responde JSON con `script` + `version`.
3. Si la versión local no coincide, el loader guarda el script como
   `chalona-ecf-<timestamp>.prg`, lo compila a `.fxp`.
4. `SET PROCEDURE TO chalona-ecf-<timestamp>.fxp ADDITIVE`.

A partir de ahí las llamadas a funciones del cliente (`chalonaEnviaEcf`,
`chalonaSincronizaEstados`, `chalonaDescargaDocumentosEcf`) resuelven al
código nuevo.

URL del servidor:
- Por defecto el loader usa `https://ecf-service.vicortiz.com/`.
- ERPs con `Public osis` (Vicortiz): se lee `osis.servidor_ecf` automáticamente.
- ERPs sin osis: llamar `chalonaSetConfig(loCfg)` con `loCfg.servidor_ecf`
  antes de la primera invocación.

## 4. Hot-reload

Modifica `chalona-ecf.prg`. Republica:

```bash
./publicar.sh
```

La próxima vez que el ERP del usuario llame al cliente, el loader detecta la
versión nueva y la activa. Sin reinstalar VFP, sin recompilar el ERP.

## Custom: ERP con tablas distintas

El motor Fox incluye lógica para ERPs sobre SQL Server con `dbo.imtr` /
`dbo.gastos` / `dbo.imtrd`. Si tu ERP es distinto (DBF, otras tablas,
otro motor) usás la **capa de cursores**: el motor crea cursores VFP
con shape rígido y vos los llenás con tus datos antes de enviar.

```foxpro
* Crear todos los cursores vacios (curChalMae, curChalDet, curChalEmp, ...).
goChalonaEcf.CrearCursores()

* Llenar cursores con tus datos (DBF, SQL, lo que sea).
* Schema documentado en SCHEMA-CURSORES.md.
INSERT INTO curChalMae (fiscal, encf, control, fecha, ...) VALUES (...)
INSERT INTO curChalDet (precio, cantidad, descrip, ...) VALUES (...)

* Motor lee cursores, envia a DGII y reescribe curChalMae con la respuesta.
loResp = goChalonaEcf.EnviarDesdeCursores(lcCtrl)

* Leer curChalMae actualizado y persistir donde quieras.
```

Ver `examples/alberto-ecf-cliente.prg` para un cliente completo sobre DBF.

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
├── chalona-ecf-loader.prg           # estatico en cliente (HTTP -> server-ecf)
├── chalona-ecf.prg                  # motor (se descarga via HTTP, hot-reload)
├── chalona-ecf-integracion.html     # docs API completa
├── SCHEMA-CURSORES.md               # contrato petrificado de cursores VFP
├── publicar.sh                      # publisher CLI (escribe a Postgres del server)
└── examples/
    ├── alberto-ecf-cliente.prg      # ejemplo de cliente sobre DBF (cursores)
    ├── ecf.prg                      # ejemplo de uso
    ├── cncfe_basedata.prg           # ejemplo
    ├── cncfe_document.prg           # ejemplo
    └── manual-api-rest.html         # alternativa REST sin loader
```
