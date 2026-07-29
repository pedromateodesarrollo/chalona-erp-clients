# Protocolo HTTP — integrar en cualquier lenguaje (sin cliente)

> Guía de referencia para escribir tu propia integración e-CF **desde cero**,
> en un lenguaje para el que Chalona todavía no publica un cliente
> (Go, Java, PHP, Rust, Kotlin, etc.). Si tu lenguaje es Fox, Dart, C#,
> TypeScript, Node.js o Python, usá el cliente correspondiente — te ahorra
> todo esto. Ver [README](../README.md).

## Audiencia

Desarrolladores que integran un ERP con la plataforma e-CF de Chalona y **no**
quieren (o no pueden) usar los clientes ya publicados. Acá está el contrato HTTP
crudo: endpoints, autenticación, forma de los payloads y de las respuestas.

No hay librería que mantener ni motor que descargar. Vos mantenés el mapeo de
tus tablas al JSON e-CF y hablás HTTP directo con el servidor. (El mecanismo de
*hot-reload* de lógica que usan los otros clientes **no aplica** acá: tu código
es tuyo.)

## Transporte

Todo es **HTTP POST con cuerpo JSON** contra el servidor ECF:

| Entorno | URL base |
|---|---|
| Producción | `https://ecf-service.vicortiz.com` |
| Desarrollo local | `http://localhost:3030` |

Los paths cuelgan de la raíz: `POST /sistema_login`, `POST /envia_ecf`,
`POST /consulta_estado`.

## Contrato general

**Toda** respuesta tiene la misma envoltura:

```json
{ "ok": true, "message": "", "data": { ... } }
```

- `ok` (bool) — éxito o fallo.
- `message` (string) — vacío si `ok=true`; si `ok=false`, un **código de error**
  (ej. `validation.required`, `dgii.rechazo`, `ecf.envio_bloqueado`), no un texto
  libre. Traducí el código a mensaje de usuario de tu lado.
- `data` (object) — la carga útil.

Hay **dos formas de request** según el endpoint:

1. **Con envoltura** (`sistema_login`, `consulta_estado`):
   ```json
   { "request": "<endpoint>", "data": { ...parámetros... } }
   ```
2. **Cuerpo directo** (`envia_ecf`): sin envoltura `request`/`data`; los
   parámetros van al nivel raíz del cuerpo. El endpoint se toma del path.

Autenticación: header `Authorization: Bearer <token>` en toda llamada que no sea
el login.

---

## Paso 1 — Login

Obtené un token JWT.

```
POST /sistema_login
Content-Type: application/json

{
  "request": "sistema_login",
  "data": {
    "app": "ecf",
    "locale": "es",
    "usuario": "user@example.com",
    "clave": "••••••"
  }
}
```

Respuesta:

```json
{
  "ok": true,
  "message": "",
  "data": {
    "usuario": { "...": "..." },
    "empresa": { "...": "..." },
    "app": "ecf",
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
}
```

Guardá `data.token`. Lo mandás como `Authorization: Bearer <token>` en las
llamadas siguientes. El token identifica usuario + empresa; no necesitás enviar
`session` en el cuerpo — el servidor lo deriva del JWT.

> `app` es siempre `"ecf"` para este portal.

---

## Paso 2 — Enviar un comprobante

```
POST /envia_ecf
Content-Type: application/json
Authorization: Bearer <token>

{
  "locale": "es",
  "rnc": "131996035",
  "portal": "ecf",
  "json": { ...documento e-CF DGII... }
}
```

- `rnc` — RNC del emisor.
- `portal` — `"ecf"` (o el portal que uses).
- `json` — el documento e-CF completo (ver [forma del payload](#forma-del-payload-json)).
- `locale` — `"es"` para que los códigos de error vengan traducidos.

Respuesta (éxito):

```json
{
  "ok": true,
  "message": "",
  "data": {
    "numero": "E310000000003",
    "tipo": "31",
    "estado": "Aceptado",
    "estado_descripcion": "",
    "codigo_seguridad": "abc123",
    "fecha_firma": "2026-07-03T10:30:00",
    "timbre": "https://...",
    "secuencia_utilizada": true,
    "track_id": "..."
  }
}
```

Campos clave de `data`:

| Campo | Significado |
|---|---|
| `numero` | eNCF asignado/usado (ej. `E310000000003`) |
| `estado` | `Aceptado`, `Aceptado Condicional`, `En Proceso`, `Rechazado`, `Pendiente` |
| `estado_descripcion` | Detalle de DGII cuando no es `Aceptado` (observaciones / motivo de rechazo) |
| `codigo_seguridad` | 6 primeros chars del `SignatureValue` (para el QR/representación impresa) |
| `fecha_firma` | Timestamp de firma |
| `timbre` | URL del sello DGII |
| `secuencia_utilizada` | `true` si el eNCF quedó consumido (no reutilizable) |
| `track_id` | ID de rastreo en DGII |

Escribí `numero`, `estado`, `codigo_seguridad`, `fecha_firma` y `timbre` de
vuelta a tu ERP contra la factura que originó el envío.

---

## Forma del payload JSON

El objeto `json` es el documento e-CF con el formato oficial de la DGII. Estructura:

```
json
├── Encabezado
│   ├── Version                "1.0"
│   ├── IdDoc
│   │   ├── TipoeCF            "31".."47"
│   │   ├── eNCF              "E310000000003"  (13 chars: E + tipo + 10 dígitos)
│   │   ├── FechaVencimientoSecuencia  "dd-MM-yyyy"
│   │   ├── IndicadorMontoGravado      "0"|"1"
│   │   ├── IndicadorNotaCredito       "0"|"1"   (solo tipo 34)
│   │   ├── TipoIngresos      "01".."06"
│   │   ├── TipoPago          "1"=Contado "2"=Crédito "3"=Gratuito
│   │   └── TablaFormasPago   [ { FormaPago, MontoPago } ]  (opcional)
│   ├── Emisor
│   │   ├── RNCEmisor         (9 u 11 dígitos)
│   │   ├── RazonSocialEmisor
│   │   ├── DireccionEmisor   (máx 100 chars)
│   │   └── FechaEmision      "dd-MM-yyyy"  (requerido)
│   ├── Comprador             (requerido en 31/33/34; opcional en 32 RFCE < 250k)
│   │   ├── RNCComprador
│   │   ├── RazonSocialComprador
│   │   └── ...
│   └── Totales
│       ├── MontoGravadoTotal
│       ├── MontoGravadoI1    (alícuota 18%)
│       ├── ITBIS1            "18"
│       ├── TotalITBIS
│       ├── MontoExento
│       ├── MontoTotal
│       ├── TotalITBISRetenido    (obligatorio tipo 41 con retención)
│       └── TotalISRRetencion     (obligatorio tipo 41 con retención)
├── DetallesItems             [ ...líneas... ]
│   └── (cada ítem)
│       ├── NumeroLinea       "1", "2", ...
│       ├── IndicadorFacturacion  "1".."4"
│       ├── NombreItem
│       ├── IndicadorBienoServicio  "1"=Bien "2"=Servicio
│       ├── CantidadItem
│       ├── PrecioUnitarioItem
│       ├── MontoItem
│       └── Retencion         { IndicadorAgenteRetencionoPercepcion, MontoITBISRetenido, MontoISRRetenido }  (opcional)
├── DescuentosORecargos       [ ... ]  (opcional)
└── InformacionReferencia     (solo notas 33/34 — ver abajo)
```

Todos los montos van como **string con 2 decimales** (`"260000.00"`), y las
fechas como `"dd-MM-yyyy"`. Precios unitarios admiten 4 decimales.

### Ejemplo completo — tipo 31 (Factura Crédito Fiscal)

```json
{
  "Encabezado": {
    "Version": "1.0",
    "IdDoc": {
      "TipoeCF": "31",
      "eNCF": "E310000000003",
      "FechaVencimientoSecuencia": "31-12-2025",
      "IndicadorMontoGravado": "0",
      "TipoIngresos": "01",
      "TipoPago": "1"
    },
    "Emisor": {
      "RNCEmisor": "131996035",
      "RazonSocialEmisor": "DOCUMENTOS ELECTRONICOS DE 02",
      "NombreComercial": "DOCUMENTOS ELECTRONICOS DE 02",
      "DireccionEmisor": "AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA",
      "FechaEmision": "01-04-2020"
    },
    "Comprador": {
      "RNCComprador": "01800451302",
      "RazonSocialComprador": "DOCUMENTOS ELECTRONICOS DE 03",
      "DireccionComprador": "CALLE JACINTO DE LA CONCHA FELIZ",
      "MunicipioComprador": "010100",
      "ProvinciaComprador": "010000"
    },
    "Totales": {
      "MontoGravadoTotal": "260000.00",
      "MontoGravadoI1": "260000.00",
      "ITBIS1": "18",
      "TotalITBIS": "46800.00",
      "TotalITBIS1": "46800.00",
      "MontoTotal": "306800.00"
    }
  },
  "DetallesItems": [
    {
      "NumeroLinea": "1",
      "IndicadorFacturacion": "1",
      "NombreItem": "Caja de Dona",
      "IndicadorBienoServicio": "1",
      "CantidadItem": "1.00",
      "PrecioUnitarioItem": "260000.00",
      "MontoItem": "260000.00"
    }
  ]
}
```

### Diferencias por tipo

| | 31 Crédito Fiscal | 32 Consumo | 33 Nota Débito | 34 Nota Crédito |
|---|---|---|---|---|
| Comprador | Requerido | Opcional si RFCE (< RD$250k) | Requerido | Requerido |
| `InformacionReferencia` | No (se descarta) | No | **Obligatorio** | **Obligatorio** |
| `IndicadorNotaCredito` | — | — | — | Obligatorio (0 ≤30 días, 1 >30) |
| `CodigoModificacion` | 4/5 (si referencia) | — | 1/2/3 | 1/2/3 |

Las **notas (33/34)** llevan al nivel raíz del `json`:

```json
"InformacionReferencia": {
  "NCFModificado": "E320000000002",
  "FechaNCFModificado": "01-04-2020",
  "CodigoModificacion": "3"
}
```

- `NCFModificado` — el eNCF del comprobante que la nota modifica.
- `CodigoModificacion` — depende de si el NCF referenciado es electrónico o no;
  no asumas un valor por defecto.
- **Nota sobre Compras (41)**: si `NCFModificado` empieza con `E41…`, **omití
  `TipoIngresos`** — no aplica y DGII devuelve `Aceptado Condicional`.

> Los montos de una **nota de crédito (34)** no pueden exceder
> `total de la factura + suma de notas de débito (33)`.

### Multimoneda — facturar en dólares (u otra divisa)

La DGII exige que el comprobante viaje en **DOP**. Pero si tu ERP factura en
USD, no conviertas todo a pesos y listo: el documento quedaría sin rastro de la
divisa y la representación impresa no cuadraría con la factura de tu sistema.

Se mandan **los dos planos a la vez**:

| Plano | Dónde | Contenido |
|---|---|---|
| **DOP** (siempre) | `Totales`, `PrecioUnitarioItem`, `MontoItem`, `DescuentoMonto`, `MontoPago` | Montos convertidos a pesos. Es lo que DGII fiscaliza. |
| **Divisa** (condicional) | `Encabezado.OtraMoneda` + campos `…OtraMoneda` en cada línea | Los mismos montos, en la moneda original. |

Regla que el servidor valida **antes** de firmar: cada monto en divisa debe ser
igual a su par en DOP dividido entre `TipoCambio`. Si no cuadra, la respuesta
viene `ok:false` y el comprobante nunca sale hacia DGII.

#### Bloque `Encabezado.OtraMoneda`

```
Encabezado
└── OtraMoneda
    ├── TipoMoneda                        "USD"   (código ISO, catálogo DGII)
    ├── TipoCambio                        "60.5000"
    ├── MontoGravadoTotalOtraMoneda       ← Totales.MontoGravadoTotal ÷ tasa
    ├── MontoGravado1OtraMoneda           ← Totales.MontoGravadoI1  (18%)
    ├── MontoGravado2OtraMoneda           ← Totales.MontoGravadoI2  (16%)
    ├── MontoGravado3OtraMoneda           ← Totales.MontoGravadoI3  (0%)
    ├── MontoExentoOtraMoneda             ← Totales.MontoExento
    ├── TotalITBISOtraMoneda              ← Totales.TotalITBIS
    ├── TotalITBIS1OtraMoneda             ← Totales.TotalITBIS1
    ├── TotalITBIS2OtraMoneda             ← Totales.TotalITBIS2
    ├── TotalITBIS3OtraMoneda             ← Totales.TotalITBIS3
    ├── MontoImpuestoAdicionalOtraMoneda  ← Totales.MontoImpuestoAdicional
    └── MontoTotalOtraMoneda              ← Totales.MontoTotal
```

`TipoMoneda` tiene que estar en el catálogo DGII; fuera de él la DGII rechaza
con código **11204**:

```
BRL CAD CHF CHY COP DKK EUR GBP HTG JPY MXN NOK SCP SEK USD VEF XDR
```

El servidor normaliza los aliases comunes del dólar antes de validar
(`US`, `USA`, `US$`, `USD$`, `DOLAR`, `DOLARES`, `DOLLAR`, `DOLLARS` → `USD`) y
pasa el código a mayúsculas. Cualquier otro código desconocido corta el envío
con `err.ecf.tipo_moneda_invalido`.

#### Campos por línea — van **planos en el ítem**

En el XML que recibe la DGII estos campos viven dentro de un bloque
`<OtraMonedaDetalle>`, pero en el **JSON del API van directo sobre el ítem**. El
servidor arma el bloque XML por ti.

| Campo (en el ítem) | Par en DOP |
|---|---|
| `PrecioOtraMoneda` (4 dec.) | `PrecioUnitarioItem` |
| `DescuentoOtraMoneda` | `DescuentoMonto` |
| `RecargoOtraMoneda` | `RecargoMonto` |
| `MontoItemOtraMoneda` | `MontoItem` |

```jsonc
// ✅ correcto — planos en el ítem
{ "NumeroLinea": "1", "PrecioUnitarioItem": "7562.5000", "MontoItem": "75625.00",
  "PrecioOtraMoneda": "125.0000", "MontoItemOtraMoneda": "1250.00" }

// ❌ se ignora en silencio — el XML sale sin OtraMonedaDetalle
{ "NumeroLinea": "1", "PrecioUnitarioItem": "7562.5000", "MontoItem": "75625.00",
  "OtraMonedaDetalle": { "PrecioOtraMoneda": "125.0000", "MontoItemOtraMoneda": "1250.00" } }
```

#### Ejemplo completo — tipo 31 en USD, línea gravada + línea exenta

Factura de US$1,775.00 a tasa **60.5000** (= RD$107,387.50):

- Línea 1, gravada 18%: 10 × US$125.00 = US$1,250.00 → RD$75,625.00
- Línea 2, exenta (flete): 1 × US$300.00 = US$300.00 → RD$18,150.00
- ITBIS: US$225.00 → RD$13,612.50

Este es el objeto `json` que va dentro del cuerpo de `POST /envia_ecf`:

```json
{
  "Encabezado": {
    "Version": "1.0",
    "IdDoc": {
      "TipoeCF": "31",
      "eNCF": "E310000000045",
      "FechaVencimientoSecuencia": "31-12-2026",
      "IndicadorMontoGravado": "0",
      "TipoIngresos": "01",
      "TipoPago": "1",
      "TablaFormasPago": [
        { "FormaPago": "1", "MontoPago": "107387.50" }
      ]
    },
    "Emisor": {
      "RNCEmisor": "131996035",
      "RazonSocialEmisor": "EXPORTADORA DEL CARIBE, S.R.L.",
      "NombreComercial": "EXPORTADORA DEL CARIBE",
      "DireccionEmisor": "AUTOPISTA DUARTE KM 14, SANTIAGO",
      "FechaEmision": "27-07-2026"
    },
    "Comprador": {
      "RNCComprador": "130862346",
      "RazonSocialComprador": "IMPORTACIONES DEL ESTE, S.A.",
      "CorreoComprador": "compras@ejemplo.com",
      "DireccionComprador": "AV. ESPANA 45, SANTO DOMINGO ESTE"
    },
    "Totales": {
      "MontoGravadoTotal": "75625.00",
      "MontoGravadoI1": "75625.00",
      "ITBIS1": "18",
      "TotalITBIS": "13612.50",
      "TotalITBIS1": "13612.50",
      "MontoExento": "18150.00",
      "MontoTotal": "107387.50"
    },
    "OtraMoneda": {
      "TipoMoneda": "USD",
      "TipoCambio": "60.5000",
      "MontoGravadoTotalOtraMoneda": "1250.00",
      "MontoGravado1OtraMoneda": "1250.00",
      "MontoExentoOtraMoneda": "300.00",
      "TotalITBISOtraMoneda": "225.00",
      "TotalITBIS1OtraMoneda": "225.00",
      "MontoTotalOtraMoneda": "1775.00"
    }
  },
  "DetallesItems": [
    {
      "NumeroLinea": "1",
      "IndicadorFacturacion": "1",
      "NombreItem": "VALVULA DE BRONCE 2 PULG",
      "IndicadorBienoServicio": "1",
      "CantidadItem": "10.00",
      "UnidadMedida": "43",
      "PrecioUnitarioItem": "7562.5000",
      "MontoItem": "75625.00",
      "PrecioOtraMoneda": "125.0000",
      "MontoItemOtraMoneda": "1250.00"
    },
    {
      "NumeroLinea": "2",
      "IndicadorFacturacion": "4",
      "NombreItem": "FLETE INTERNACIONAL",
      "IndicadorBienoServicio": "2",
      "CantidadItem": "1.00",
      "UnidadMedida": "43",
      "PrecioUnitarioItem": "18150.0000",
      "MontoItem": "18150.00",
      "PrecioOtraMoneda": "300.0000",
      "MontoItemOtraMoneda": "300.00"
    }
  ]
}
```

Envío completo:

```bash
curl -s -X POST "$BASE/envia_ecf" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"locale":"es","rnc":"131996035","portal":"ecf","json": { ...el objeto de arriba... }}' | jq
```

La respuesta es la misma de cualquier `envia_ecf` (`estado`, `timbre`,
`codigo_seguridad`, `track_id`). El `total` del registro se guarda en **DOP**.

#### Cómo derivar los montos desde tu ERP

Partiendo del precio en divisa por línea:

```
precio_dop  = round(precio_divisa * tasa, 4)
monto_dop   = round(precio_dop * cantidad, 2)

MontoGravadoTotal = Σ monto_dop de líneas con IndicadorFacturacion 1|2|3
MontoExento       = Σ monto_dop de líneas con IndicadorFacturacion 4
TotalITBIS1       = round(MontoGravadoI1 * 0.18, 2)
MontoTotal        = MontoGravadoTotal + MontoExento + MontoNoFacturable
                    + TotalITBIS + MontoImpuestoAdicional
```

y después **cada campo de `OtraMoneda` sale de dividir su par en DOP entre la
misma tasa**, redondeado a 2 decimales. No los acumules por separado sumando las
líneas en divisa: arrastrar redondeos línea por línea es la causa más común de
descuadre.

> `TipoCambio` viaja al XML de la DGII con **2 decimales**. Si tu ERP maneja
> tasas de 4 decimales (ej. `58.0544`), la DGII validará contra `58.05`. Usa una
> tasa de 2 decimales, o verifica que los montos en divisa sigan cuadrando con
> la tasa redondeada.

#### Los 4 chequeos que corre el servidor antes de mandar a DGII

1. **Coherencia divisa ↔ DOP.** Cada `…OtraMoneda` se compara contra
   `<par en DOP> ÷ TipoCambio`. Tolerancia:
   `(número de líneas ÷ TipoCambio) + 0.01 por línea`.
2. **Segmentación gravado vs exento.** El error más repetido: acumular todo en
   `MontoGravadoTotalOtraMoneda` y omitir `MontoExentoOtraMoneda` cuando hay
   `MontoExento` en DOP. DGII lo rechaza con **11260**; acá se corta antes.
3. **`TotalITBISxOtraMoneda` condicional-obligatorio.** Si declaras
   `MontoGravado3OtraMoneda` (tasa 0%), tienes que enviar
   `TotalITBIS3OtraMoneda` **aunque valga `0.00`**; omitirlo produce rechazo
   DGII **11300**. Igual con `TotalITBISOtraMoneda` cuando hay algún gravado.
4. **Catálogo `TipoMoneda`** (arriba).

Respuesta típica cuando el exento no se segmentó en la divisa:

```json
{
  "ok": false,
  "message": "Los totales no coinciden con el detalle. MontoExentoOtraMoneda = MontoExento ÷ TipoCambio. Segmente el exento en OtraMoneda; no lo acumule en MontoGravadoTotalOtraMoneda (DGII 11260).",
  "data": {
    "errors": [
      {
        "error": "ecf.total_detalle_no_coincide",
        "path": "Encabezado.OtraMoneda.MontoExentoOtraMoneda",
        "sumaDetalle": 300.0,
        "total": 0.0,
        "tipoCambio": 60.5
      },
      {
        "error": "ecf.total_detalle_no_coincide",
        "path": "Encabezado.OtraMoneda.MontoGravadoTotalOtraMoneda",
        "sumaDetalle": 1250.0,
        "total": 1550.0,
        "tipoCambio": 60.5
      }
    ]
  }
}
```

Los errores de validación previa no traen un código único en `message`: ahí va
el mensaje del primer problema, y `data.errors` trae **todos** con su `path`.
Recórrelo completo antes de corregir.

#### Checklist multimoneda

- [ ] `Totales` y montos de línea en **DOP**; `OtraMoneda` y `…OtraMoneda` en la divisa.
- [ ] `TipoMoneda` en el catálogo DGII; `TipoCambio` > 0.
- [ ] Cada `…OtraMoneda` = su par en DOP ÷ `TipoCambio` (redondeo a 2 decimales).
- [ ] Exento segmentado: `MontoExentoOtraMoneda` presente si hay `MontoExento`.
- [ ] `TotalITBISxOtraMoneda` presente (aun en `0.00`) por cada `MontoGravadoxOtraMoneda`.
- [ ] Campos de línea **planos**, sin envolver en `OtraMonedaDetalle`.
- [ ] `MontoPago` de `TablaFormasPago` en DOP (no hay equivalente en divisa).

Aplica igual a los tipos **46 (Exportación)** y **47 (Pagos al Exterior)**, que
son los que más se facturan en divisa. En 46 las líneas van con
`IndicadorFacturacion: "3"` (ITBIS 0%), así que acuérdate del punto 3.

---

Plantilla oficial de los 10 tipos (31, 32, 33, 34, 41, 43, 44, 45, 46, 47) —
la misma que usa Chalona para certificación DGII:
[`api/lib/src/ecf/fixtures/documentos_certificacion_dgii.json`](../../../api/lib/src/ecf/fixtures/documentos_certificacion_dgii.json)
(en el repo `chalona-fsd`). Los clientes Python/Dart la embeben en su
`demo_envio` — mirá `python-driver/bin/demo_envio.py` como referencia de los
10 documentos completos.

---

## Paso 3 — Consultar estado

Para los comprobantes cuyo `estado` inicial no fue final (ej. `En Proceso`):

```
POST /consulta_estado
Content-Type: application/json
Authorization: Bearer <token>

{
  "request": "consulta_estado",
  "data": {
    "locale": "es",
    "comprobantes": ["E310000000003", "E320000000012"]
  }
}
```

Respuesta:

```json
{
  "ok": true,
  "message": "",
  "data": {
    "result": [
      { "encf": "E310000000003", "estado": "Aceptado", "codigo_seguridad": "abc123", "fecha_firma": "2026-07-03T10:30:00" }
    ]
  }
}
```

---

## Manejo de errores

Cuando `ok=false`, `message` trae un **código**. Los más comunes:

| Código | Qué pasó |
|---|---|
| `validation.required` | Falta un campo obligatorio en el payload |
| `dgii.rechazo` | DGII rechazó el comprobante (mirá `data` / `estado_descripcion`) |
| `ecf.envio_bloqueado` | El envío está bloqueado para esa empresa |
| `err.ejecutar.sin_acceso` | El token no tiene acceso al endpoint |
| `ecf_certificado.clave_incorrecta` | Clave del certificado de firma incorrecta |

Mandá siempre `locale: "es"` para recibir el `message` legible. No parsees el
texto: rutéalo por el código.

---

## Ejemplo end-to-end (curl)

```bash
BASE="https://ecf-service.vicortiz.com"

# 1. Login → token
TOKEN=$(curl -s -X POST "$BASE/sistema_login" \
  -H 'Content-Type: application/json' \
  -d '{"request":"sistema_login","data":{"app":"ecf","locale":"es","usuario":"USER","clave":"PASS"}}' \
  | jq -r '.data.token')

# 2. Enviar comprobante (doc.json = { "locale":"es","rnc":"...","portal":"ecf","json":{...} })
curl -s -X POST "$BASE/envia_ecf" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d @doc.json | jq

# 3. Consultar estado
curl -s -X POST "$BASE/consulta_estado" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"request":"consulta_estado","data":{"locale":"es","comprobantes":["E310000000003"]}}' | jq
```

---

## Checklist de integración

1. [ ] Login funciona, guardás el token y lo reusás.
2. [ ] Mapeás tus tablas (facturas, líneas, cliente) al JSON e-CF de arriba.
3. [ ] Enviás un tipo 31 contra el entorno de pruebas y recibís `Aceptado`.
4. [ ] Escribís `numero`, `estado`, `codigo_seguridad`, `fecha_firma`, `timbre`
       de vuelta a tu ERP.
5. [ ] Manejás `estado != Aceptado` (reintento / consulta_estado / mostrar
       `estado_descripcion`).
6. [ ] Cubrís notas (33/34) con `InformacionReferencia`.
7. [ ] Si facturás en divisa, cubrís
       [multimoneda](#multimoneda--facturar-en-dólares-u-otra-divisa)
       (`OtraMoneda` + campos de línea).
8. [ ] Probás los 10 tipos con la plantilla de certificación antes de producción.

Para arrancar el mapeo con ayuda de un agente de IA, instalá la skill
`driver-cliente` (ver [README](../README.md)) — te scaffoldea las queries
contra tus propias tablas.
