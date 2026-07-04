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
7. [ ] Probás los 10 tipos con la plantilla de certificación antes de producción.

Para arrancar el mapeo con ayuda de un agente de IA, instalá la skill
`driver-cliente` (ver [README](../README.md)) — te scaffoldea las queries
contra tus propias tablas.
