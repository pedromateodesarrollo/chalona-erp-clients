# Quickstart — Cliente Fox (Visual FoxPro)

## Audiencia

Esta guía es para un **integrador** que quiere conectar su ERP en VFP con
la facturación electrónica de Chalona. Tú no hospedas nada — Chalona ya
corre el server-ecf y publica el motor. Tu ERP solo necesita el loader.

Si querés hospedar tu propio motor (forkear el patrón hot-reload para tu
producto), saltá al final: [Self-hosting (avanzado)](#self-hosting-avanzado).

## Pre-requisitos

- Visual FoxPro 9 instalado en la máquina del cliente
- Acceso de red al server-ecf (`https://ecf-service.vicortiz.com/` por defecto)
- Credenciales DGII (RNC, usuario, clave del portal de Chalona)

**No necesitás Postgres.** El motor vive en la BD de Chalona; tu ERP solo
hace HTTP contra el server-ecf.

## Concepto

```
[VFP cliente]  --HTTP-->  [server-ecf (Dart)]  --SQL-->  [Postgres Chalona]
chalona-ecf-loader.prg   ecf-service.vicortiz.com    data.fox_cliente_script
```

Solo un archivo vive en el ERP del cliente:

| Archivo | Qué hace |
|---|---|
| `chalona-ecf-loader.prg` | Mini-loader estático. La primera llamada (y cada vez que hay versión nueva) hace `MSXML2.XMLHTTP` POST a `https://<servidor>/fox_cliente_script`, recibe el motor `chalona-ecf.prg` en JSON, lo compila a `.fxp` único, hace `SET PROCEDURE TO ... ADDITIVE`, instancia `goChalonaEcf`. |

El motor (`chalona-ecf.prg`) **no** se distribuye con el cliente — se baja
del server-ecf en cada arranque y se actualiza en caliente cuando Chalona
publica una versión nueva.

## 1. Instalar el loader

Copia `chalona-ecf-loader.prg` desde este repo a la instalación VFP del
cliente.

## 2. Configurar (si tu ERP no usa `osis`)

ERPs sobre Vicortiz tienen un objeto público `osis` con `servidor_ecf`,
`usuario_sync`, `pass_sync`, `portal_dgii`, `dgii_multimoneda`. El loader
los lee automáticamente.

Si tu ERP no tiene `osis`, llamá `chalonaSetConfig(loCfg)` antes de la
primera invocación:

```foxpro
LOCAL loCfg
loCfg = CREATEOBJECT("Empty")
ADDPROPERTY(loCfg, "servidor_ecf", "https://ecf-service.vicortiz.com/")
ADDPROPERTY(loCfg, "usuario_sync", "tu_usuario@dominio.com")
ADDPROPERTY(loCfg, "pass_sync",    "tu_clave")
ADDPROPERTY(loCfg, "portal_dgii",  "testecf")  && testecf|ecf
ADDPROPERTY(loCfg, "dgii_multimoneda", "T")    && opcional
chalonaSetConfig(loCfg)
```

## 3. Usar

```foxpro
DO chalona-ecf-loader.prg

* Enviar un comprobante por su control en dbo.imtr / dbo.gastos
loResp = chalonaEnviaEcf("ABC1234")

IF loResp.ok
  ? "OK encf:", goChalonaEcf.curChalMae.encf
ELSE
  ? "Error:", loResp.message
ENDIF

* Sincronizar estados pendientes con DGII
loResp = chalonaSincronizaEstados()

* Descargar documentos por rango de fechas
loResp = chalonaDescargaDocumentosEcf("2026-01-01", "2026-01-31")
```

Eso es todo. El loader detecta versiones nuevas del motor automáticamente
en cada llamada.

## 4. ERP con tablas distintas (DBF, otro esquema)

El motor Fox incluye lógica SQL Server estándar (`dbo.imtr` / `dbo.gastos`
/ `dbo.imtrd` / `dbo.empresa` / `dbo.suplidor` / `dbo.clientes` /
`dbo.fiscal` / `dbo.mercs`). Si tu ERP no encaja con esa estructura, usás
la **capa de cursores**: tu código llena cursores VFP con shape rígido y
el motor lee/reescribe ahí.

```foxpro
DO chalona-ecf-loader.prg

* 1. Motor crea TODOS los cursores con shape rigido y vacios.
goChalonaEcf.CrearCursores()

* 2. Llena cursores con tus datos (de DBF, SQL Server custom, lo que sea).
*    Schema documentado en SCHEMA-CURSORES.md.
INSERT INTO curChalMae (fiscal, encf, control, fecha, valor, ...) VALUES (...)
INSERT INTO curChalDet (precio, cantidad, descrip, ...) VALUES (...)
INSERT INTO curChalEmp (rnc, nombre, direccion, iprecio) VALUES (...)
INSERT INTO curChalCli (extranjero_flag, rnc, nombre) VALUES (...)
* (curChalRef solo para NC/ND, curChalSup solo para gastos sin RNC, etc.)

* 3. Motor lee cursores, envia a DGII y REESCRIBE curChalMae con respuesta
*    (encf, estado, codigo_seguridad, fecha_firma, timbre, ...).
loResp = goChalonaEcf.EnviarDesdeCursores(lcCtrl)

* 4. Tu codigo lee curChalMae y persiste donde quieras (otra DBF, SQL, etc.).
SELECT curChalMae
GO TOP
* curChalMae.encf, curChalMae.estado, curChalMae.codigo_seguridad ...
```

Ver `fox/SCHEMA-CURSORES.md` para el contrato exacto de cada cursor
(columnas, tipos, largos). El shape es **petrificado** — Chalona nunca
rompe compatibilidad.

Para sync masivo de estados pendientes:

```foxpro
goChalonaEcf.CrearCursores()
* Llenar curChalonaEncfEnProceso con (control, encf, es_gastos) por cada pendiente
INSERT INTO curChalonaEncfEnProceso (control, encf, es_gastos) VALUES (...)
* Motor consulta DGII en lotes y reescribe el cursor con estado actualizado
loResp = goChalonaEcf.SincronizarDesdeCursor()
* Recorrer curChalonaEncfEnProceso y persistir
```

Ver `fox/examples/alberto-ecf-cliente.prg` — cliente completo de ejemplo
sobre DBF (no SQL Server) usando esta capa.

## Documentación de integración

[`chalona-ecf-integracion.html`](../fox/chalona-ecf-integracion.html)
tiene la referencia completa de la API: funciones, parámetros, errores.

## Gotchas VFP

- ⛔ **No usar `RETURN` dentro de bloques `TRY/CATCH`**: VFP no lo permite
  (error 2060). Usar un flag (`lcSalir = .T.`) y un `IF` después del `ENDTRY`.
- Los `.fxp` cacheados por VFP no se invalidan automáticamente. El loader
  resuelve esto generando nombres únicos por versión.
- En producción, los `.fxp` viejos quedan en disco. Limpiar periódicamente.

## Estructura del repo

```
fox/
├── chalona-ecf-loader.prg           # ← copiar al ERP del cliente
├── chalona-ecf.prg                  # motor (servido via HTTP por Chalona)
├── chalona-ecf-integracion.html     # docs API completa
├── SCHEMA-CURSORES.md               # contrato petrificado de cursores
├── publicar.sh                      # publisher (solo si self-hosting)
└── examples/
    ├── alberto-ecf-cliente.prg      # cliente sobre DBF (capa cursores)
    ├── ecf.prg                      # ejemplo simple SQL Server
    ├── cncfe_basedata.prg           # helpers ejemplo
    ├── cncfe_document.prg           # helpers ejemplo
    └── manual-api-rest.html         # alternativa REST sin loader
```

---

## Self-hosting (avanzado)

Solo si querés correr tu propio server-ecf y publicar tu propio motor
Fox (forkear el patrón). Caso típico: NO necesario para integradores.

### Pre-requisitos extra

- Postgres (mismo schema que server-ecf usa)
- `psql` y `python3` en el PATH

### 1. Aplicar schema

```bash
psql -h localhost -U postgres -d midb -f sql/schema.sql
```

### 2. Publicar tu primera versión

```bash
cd fox
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret \
  ./publicar.sh
```

Sin args = `entorno='test'`. Para producción: `./publicar.sh --produccion`.

### 3. Hot-reload

Modificá `chalona-ecf.prg`. Republicá con `./publicar.sh`. La próxima
llamada de tus clientes detecta la versión nueva y la activa.
