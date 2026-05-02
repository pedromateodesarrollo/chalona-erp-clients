# Schema de cursores Chalona ECF (Fox)

**Contrato petrificado.** Una vez publicado, NUNCA cambiar nombres de cursor, nombres de columna, tipos ni largos. Solo permitido: agregar columnas nuevas al final (motor las lee con `Type("col") # "U"`, integrador viejo las ignora).

Estos cursores los crea el motor cuando el cliente llama `goChalonaEcf.CrearCursores()`. Vienen vacíos. El cliente los llena con sus datos (DBF / SQL Server / DBF mixto / lo que sea) y luego invoca:

- `goChalonaEcf.EnviarDesdeCursores(tcControl)` — motor lee, envía a DGII, **reescribe `curChalMae`** con la respuesta.
- `goChalonaEcf.SincronizarDesdeCursor()` — motor lee `curChalonaEncfEnProceso`, consulta DGII, **reescribe el mismo cursor** con el estado actualizado.
- `goChalonaEcf.DescargarDocumentosACursor(tcDesde, tcHasta, tcTiposJson)` — motor poblea `curChalDescarga`.

El cliente recorre el cursor reescrito y persiste donde quiera (no es responsabilidad del motor).

---

## curChalMae — cabecera del comprobante

```fox
Create Cursor curChalMae ;
  (fiscal              C(2),    && "31"/"32"/"33"/"34"/"41"/"43" (TipoeCF)
   encf                C(20),   && e-NCF (ventas y NC). Motor lo reescribe tras envia_ecf.
   ncf                 C(20),   && NCF (gastos)
   control             C(40),   && identificador del documento en el ERP
   fecha               D,       && FechaEmision
   valor               N(18,2), && monto base sin descuento ni ITBIS
   descuento           N(18,2),
   itbis               N(18,2),
   total               N(18,2),
   tasa                N(18,4), && >=1; 1 = sin cambio (multiplicador)
   moneda              C(10),   && DOP/USD/EUR/etc.
   rnc                 C(20),   && RNC comprador (ventas) o suplidor (gastos)
   nombre              C(150),
   entidad             C(20),   && código cliente/suplidor en el ERP
   ocontrol            C(40),   && referencia para NC/ND
   fechavencencf       D,       && FechaVencimientoSecuencia (obligatoria 31/33/41/43-47)
   dgii_codmod         N(2),    && CodigoModificacion DGII (1-5)
   itbisr              N(18,2), && ITBIS retenido (gastos)
   isr                 N(18,2), && ISR retenido (gastos)
   diascr              N(5,0),  && días crédito; 0 = TipoPago 1 (contado), >0 = 2 (crédito)
   comentario          C(200),  && gastos: texto del item sintético
   referencia          C(40),
   doc                 C(40),
   numero              C(40),
   * --- Writeback (motor reescribe tras envia_ecf) ---
   estado              C(200),
   estado_descripcion  C(500),
   codigo_seguridad    C(200),
   fecha_firma         C(100),
   timbre              C(500),
   secuencia_utilizada N(1),
   momento             C(50),
   respuesta_mensajes  C(500))
```

**Reglas de llenado:**
- Cliente puede dejar `encf` vacío en ventas si DGII asigna; motor lo reescribe.
- En gastos (41/43) usar `ncf`. `encf` debe quedar vacío.
- `tasa < 1` se trata como 1.
- `moneda` vacía o "DOP"/"RD"/"RD$"/"PESO" → no multimoneda.
- `dgii_codmod` 0 o fuera de 1-5 → motor asume 3.
- Cols writeback se dejan vacías; motor las llena.
- Una sola fila por llamada `EnviarDesdeCursores(ctrl)`.

---

## curChalDet — líneas del comprobante

```fox
Create Cursor curChalDet ;
  (precio             N(18,6),
   cantidad           N(18,4),
   descrip            C(200),
   mercs_nombre       C(200),
   mercs_servicio     N(2),    && 0/1 = mercancía, 2 = servicio
   itbis              N(18,2), && opcional: ITBIS por línea (override por-línea de IndicadorFacturacion)
   itbis_retenido     N(18,2), && opcional
   isr_retenido       N(18,2)) && opcional
```

**Reglas:**
- Una fila por línea del comprobante.
- En gastos (41/43) el motor sintetiza una sola línea — `curChalDet` debe quedar vacío.
- Líneas con `MontoItem` calculado en 0 son saltadas por el motor.
- Si `itbis` no está en la fila, motor usa la cabecera para decidir IndicadorFacturacion por línea.

---

## curChalEmp — datos del emisor

```fox
Create Cursor curChalEmp ;
  (rnc       C(20),
   nombre    C(150),
   direccion C(200),
   iprecio   N(1))     && 1 = precios incluyen ITBIS, 0 = sin ITBIS
```

Una sola fila. Si vacío, motor falla con `ecf.empresa.no_disponible`.

---

## curChalCli — tercero (cliente o suplidor)

```fox
Create Cursor curChalCli ;
  (extranjero_flag N(1),     && 1 = extranjero, 0 = local
   rnc             C(20),    && opcional; fallback si curChalMae.rnc vacío (ventas)
   nombre          C(150))   && opcional; fallback si curChalMae.nombre vacío (ventas)
```

Una fila o vacío. Si `extranjero_flag = 0` y `curChalMae.rnc` no es identificador fiscal RD válido, motor lo trata como extranjero automáticamente.

---

## curChalRef — referencia (NC/ND/FCF con doc previo)

```fox
Create Cursor curChalRef ;
  (encf  C(20),  && e-NCF del documento referenciado
   fecha D)      && fecha del documento referenciado
```

Una fila o vacío. Aplicable a:
- Tipo 34 (NC): obligatorio.
- Tipo 33 (ND): opcional.
- Tipo 31 (FCF) si `curChalMae.ocontrol` no vacío y `dgii_codmod ∈ (4, 5)`.
- Otros tipos (32, 41, 43, 44, 45, 46, 47): omitir, motor ignora.

---

## curChalFis — fecha de vencimiento por tipo

```fox
Create Cursor curChalFis (vence D)
```

Una fila o vacío. Si `curChalMae.fechavencencf` está vacío, motor cae a este cursor. Si ambos vacíos para tipos 31/33/41/43-47 → falla `ecf.iddoc.fecha_vencimiento_requerida`.

---

## curChalSup — RNC/nombre del suplidor (gastos sin RNC en maestro)

```fox
Create Cursor curChalSup ;
  (rnc    C(20),
   nombre C(150))
```

Una fila o vacío. Solo se consulta si `curChalMae.rnc` está vacío en gastos (41/43).

---

## curChalonaEncfEnProceso — pendientes para sincronización

```fox
Create Cursor curChalonaEncfEnProceso ;
  (control             C(40),
   encf                C(20),
   es_gastos           L,
   * --- Writeback (motor reescribe tras consulta_estado) ---
   numero              C(20),
   estado              C(200),
   estado_descripcion  C(500),
   codigo_seguridad    C(200),
   fecha_firma         C(100),
   timbre              C(500),
   secuencia_utilizada N(1),
   momento             C(50))
```

Cliente llena `control`, `encf`, `es_gastos`. Motor consulta DGII en lotes de 100 y reescribe las cols writeback fila por fila.

---

## curChalDescarga — documentos descargados de DGII

```fox
Create Cursor curChalDescarga ;
  (zip_path C(260))   && ruta absoluta del .zip generado
```

Motor llena después de `DescargarDocumentosACursor(tcDesde, tcHasta, tcTiposJson)`. Una fila con la ruta del ZIP descargado.

---

## Convenciones generales

- Todos los cursores son **locales** (Create Cursor), no SQL — escritura libre por cliente y motor.
- Motor crea con `CrearCursores()`; si ya existían, los cierra (`Use In ...`) y recrea.
- El cliente NO debe modificar el shape — solo `INSERT INTO` o lectura.
- Cols opcionales tienen valor 0/"" en filas no llenas — motor decide qué hacer.
- Multimoneda: motor lee `curChalMae.tasa` y `curChalMae.moneda`; no requiere cursor adicional.
