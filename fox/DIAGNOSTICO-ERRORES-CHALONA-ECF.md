# Diagnóstico de errores — Chalona ECF (chalona-ecf.prg)

Documento para **adjuntar o pegar completo** (más los datos de la sección “Información a recopilar”) cuando se necesite determinar qué está fallando.

---

## 1. Contexto del flujo

1. El cliente Fox **no envía primero** el comprobante al API: antes arma el JSON en memoria leyendo **SQL Server** con `SELECT` simples (ya **no** se usa el procedimiento `dbo.ecf2json` para armar el JSON).
2. Si esa fase falla, puede mostrarse un código heredado **`sql.ecf2json.error`** aunque **no** se esté llamando a `ecf2json` en la base.
3. Si el armado del JSON va bien, se hace **HTTP POST** al API (`envia_ecf`, etc.) con token de sesión.

---

## 2. Códigos de error relevantes (fase “armar JSON en Fox”)

| Código / mensaje en pantalla | Significado técnico |
|------------------------------|---------------------|
| **`sql.ecf2json.error`** | `ChalonaEcfBuildDocJsonFox` devolvió **`.Null.`**: **alguna consulta SQL falló** al ejecutarse (`ChalonaEcfExecSql` → `Sqlexec` o `Request` devolvió falso). **No** significa “no hay fila en imtr”. |
| **`ecf2json.vacio`** | El SQL **sí ejecutó**, pero **no hay fila** en `dbo.imtr` para el `control` indicado (o el resultado principal queda vacío). Equivale más a “no encuentro el documento”. |
| **`json.sin_rnc_emisor`** | El JSON se armó pero **no se pudo extraer** `RNCEmisor` del texto (datos de empresa / JSON mal formado). |
| **`control requerido`** | Se llamó al envío sin `control`. |
| **`login.fallo`** | No se obtuvo token (credenciales, API, red). |
| **`usuario/clave requeridos`** / **`portal requerido`** | Faltan datos de configuración en el objeto Chalona Ecf. |

Para errores **después** del POST (respuesta del API), el mensaje suele ser otro código o texto que devuelve el servidor; puede abrirse el formulario largo de error con detalle.

---

## 3. Consultas SQL que ejecuta `ChalonaEcfBuildDocJsonFox` (en orden)

Sustituir `'CONTROL_AQUI'` por el control del documento (ej. `010000CK8S`).

1. **Cabecera del documento**  
   `SELECT * FROM dbo.imtr WHERE control = 'CONTROL_AQUI'`

2. **Vencimiento de secuencia** (solo si `imtr.fiscal` no está vacío)  
   `SELECT TOP 1 vencimiento FROM dbo.fiscal WHERE codigo = '<valor de imtr.fiscal>'`

3. **Datos del emisor (empresa)** — **sin filtro por control**  
   `SELECT TOP 1 rnc, nombre, direccion FROM dbo.empresa`

4. **Cliente / extranjero** (solo si `imtr.entidad` no está vacío)  
   `SELECT TOP 1 extranjero FROM dbo.clientes WHERE codigo = '<imtr.entidad>'`

5. **Documento de referencia** (solo si `imtr.ocontrol` no está vacío)  
   `SELECT TOP 1 encf, fecha FROM dbo.imtr WHERE control = '<imtr.ocontrol>'`

6. **Detalle + mercancías**  
   ```sql
   SELECT d.*, m.nombre AS mercs_nombre, ISNULL(m.servicio, 0) AS mercs_servicio
   FROM dbo.imtrd d
   LEFT JOIN dbo.mercs m ON m.codigo = d.merc
   WHERE d.control = 'CONTROL_AQUI'
   ```

**Nota:** Cualquier fallo en los pasos 1–6 con retorno **`.Null.`** en Fox produce **`sql.ecf2json.error`**. El paso que falle en **SSMS** con el mismo usuario/conexión suele ser el culpable.

---

## 4. Archivos de log junto al ejecutable

| Archivo | Uso |
|---------|-----|
| **`chalona-ecf-ultimo-error.txt`** | Errores de configuración / conexión / escritura de archivo de conexión, etc. |
| **`chalona-ecf-ultimo-run.txt`** | Trazas append de ejecuciones (ej. `GUARDAR_CONEXION ok`). |

Si el fallo es solo **`sql.ecf2json.error`** en mitad de `Enviar`, a veces **no** queda rastro en estos `.txt`; ahí importa **AERROR** o **SQL Server**.

---

## 5. Información a recopilar (copiar y rellenar)

Pegar esto rellenado junto con este documento:

```
=== Entorno ===
- Modo: [ ] EXE standalone (SQLSTRINGCONNECT)  [ ] PRG dentro del ERP (Request)
- Versión / fecha del chalona-ecf.prg o EXE (si se sabe):
- SQL Server versión / edición (si se sabe):

=== Error en pantalla ===
- Título del MessageBox:
- Texto completo (incl. línea "Control: ..." si aparece):
- Código exacto (ej. sql.ecf2json.error):

=== Documento ===
- control:

=== Logs ===
- Contenido reciente de chalona-ecf-ultimo-error.txt (o "no existe / vacío"):
- Contenido reciente de chalona-ecf-ultimo-run.txt (opcional):

=== Visual FoxPro — AERROR ===
Tras reproducir el error, en la ventana de comandos:
  DIMENSION la[1]
  ? AERROR(la)
  LIST MEMORY LIKE la
Pegar salida (mensaje nativo SQL/ODBC si aparece):

=== SQL Server (mismo usuario que el ERP) ===
- Resultado de: SELECT * FROM dbo.imtr WHERE control = '...'
  [ ] 1 fila  [ ] 0 filas  [ ] error (pegar mensaje)
- Si hubo error, ¿en qué consulta de la sección 3 falló? (pegar mensaje SSMS)

=== Red / API (solo si el error NO es sql.ecf2json.error) ===
- URL base del API (ini / configuración):
- ¿Otros envíos funcionan con el mismo equipo?
```

---

## 6. Árbol rápido de decisión

- **`sql.ecf2json.error`** → Prioridad: **diagnóstico SQL** (paso 3 de este doc + AERROR + SSMS).  
- **`ecf2json.vacio`** → Prioridad: **datos**: ¿existe `imtr` para ese `control`?  
- **`login.fallo`** → Prioridad: **API**, credenciales, URL, TLS, firewall.  
- Mensaje con texto del **servidor / DGII** → Revisar respuesta HTTP y formulario de detalle.

---

## 7. Referencia en código (repositorio)

- Construcción del JSON: función **`ChalonaEcfBuildDocJsonFox`** en `chalona-ecf.prg`.  
- Retorno **`sql.ecf2json.error`**: procedimiento **`Enviar`** de la clase **`ChalonaEcf`**, cuando `Isnull(lcDocJson)` tras `ChalonaEcfBuildDocJsonFox(tcControl)`.  
- Ejecución SQL: **`ChalonaEcfExecSql`** (modo standalone: `ChalonaEcfSqlExec` / `Sqlexec`; integrado: `Request`).

---

*Última actualización del documento: alineado con el flujo “JSON en Fox, sin dbo.ecf2json” descrito en los comentarios de `chalona-ecf.prg`.*
