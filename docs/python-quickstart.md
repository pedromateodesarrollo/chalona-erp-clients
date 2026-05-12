# Quickstart — Cliente Python

## Audiencia

Esta guía es para un **integrador** que quiere enviar comprobantes e-CF
desde una app Python. Solo necesitás HTTPS contra `ecf-service.vicortiz.com`.

Sin Postgres. Sin schema. Sin credenciales de base de datos.

## Pre-requisitos

- Python 3.9+
- Acceso de red a `https://ecf-service.vicortiz.com` (puerto 443)
- Credenciales de usuario ECF (correo + clave) provistas por Chalona

## Instalación (opcional)

```bash
cd python-driver
pip install -e .
```

No es obligatorio — los scripts en `bin/` añaden `src/` al `sys.path`
automáticamente.

## Uso mínimo

```python
import sys
sys.path.insert(0, 'python-driver/src')

from chalona_driver.ecf_client import EcfClient, EcfApiError

client = EcfClient()  # base_url='https://ecf-service.vicortiz.com'

# 1. Login
client.login('mi_correo@empresa.com', 'mi_clave')

# 2. Enviar un comprobante con payload DGII
payload = {
    "Encabezado": {
        "Version": "1.0",
        "IdDoc": {
            "TipoeCF": "31",
            "eNCF": "E310000000001",       # '' para testecf (servidor genera)
            "FechaVencimientoSecuencia": "31-12-2099",
            "IndicadorMontoGravado": "0",
            "TipoIngresos": "01",
            "TipoPago": "1",
        },
        "Emisor": {
            "RNCEmisor": "131996035",
            "RazonSocialEmisor": "Mi Empresa SRL",
            "DireccionEmisor": "Calle Principal #1",
            "FechaEmision": "06-05-2026",
        },
        "Comprador": {
            "RNCComprador": "01800451302",
            "RazonSocialComprador": "Cliente SA",
        },
        "Totales": {
            "MontoGravadoTotal": "1000.00",
            "MontoGravadoI1": "1000.00",
            "ITBIS1": "18",
            "TotalITBIS": "180.00",
            "TotalITBIS1": "180.00",
            "MontoTotal": "1180.00",
        },
    },
    "DetallesItems": [
        {
            "NumeroLinea": "1",
            "IndicadorFacturacion": "1",
            "NombreItem": "Servicio de consultoría",
            "IndicadorBienoServicio": "2",
            "CantidadItem": "1.0000",
            "PrecioUnitarioItem": "1000.00",
            "MontoItem": "1000.00",
        }
    ],
}

try:
    r = client.envia_ecf(rnc='131996035', portal='testecf', json_doc=payload)
    print('estado:', r.get('estado'))      # 'Aceptado'
    print('eNCF:  ', r.get('numero'))
except EcfApiError as e:
    print('error:', e.code, e.data)
```

## Métodos del cliente

| Método | Descripción |
|---|---|
| `login(usuario, clave)` | Auth — guarda token Bearer interno. |
| `envia_ecf(rnc, portal, json_doc)` | Envía payload DGII completo. |
| `envia_ecf_desde_doc(documento, portal)` | Envía formato cursores (espejo Fox). |
| `consulta_estado(comprobantes)` | Lista de hasta 100 e-NCFs → estado. |
| `descarga_xmls(desde, hasta, tipos?)` | ZIP con XMLs firmados del rango. |
| `clear_token()` | Limpia token (forzar re-login). |

## Manejo de errores

```python
try:
    r = client.envia_ecf(rnc=rnc, portal='ecf', json_doc=payload)
except EcfApiError as e:
    print(e.code)    # ej: 'err.sistema_login.credenciales_invalidas'
                     #     'motor.envia_ecf.portal_invalido'
                     #     'ecf.formato_rnc'
    print(e.data)    # dict con detalle adicional
```

## Demo end-to-end (10 tipos, testecf)

```bash
cd python-driver
python3 bin/demo_envio.py
```

Envía los 10 tipos de comprobante (31-32-33-34-41-43-44-45-46-47) a `testecf`
usando la empresa de prueba Vicortiz. Salida esperada:

```
=== demo_certificacion (Python) ===
  baseUrl  : https://ecf-service.vicortiz.com
  usuario  : test@r131086268.com
  emisor   : 131086268 / Vicortiz Softwares srl
  portal   : testecf
  docs     : 10 comprobantes (eNCF generado por servidor)

-- Login...
   OK — empresa: Vicortiz Softwares srl

[1/10] Tipo 31  eNCF:
  OK  - estado: Aceptado  eNCF: E310000008xxx
...
=========================================
  RESUMEN: 10 ok / 0 fail (de 10)
=========================================
```

## Cómo funciona internamente

1. Tu código → `client.envia_ecf(...)`.
2. Shell (`ecf_client.py`) pasa el estado al motor estático (`motor.py`).
3. Motor dice `{"kind":"http", "endpoint":"envia_ecf", ...}`.
4. Shell hace `POST /` a `https://ecf-service.vicortiz.com` con token Bearer.
5. Server-ecf firma con certificado P12 de tu empresa, envía a DGII.
6. Respuesta vuelve: motor devuelve `{"kind":"done", "result":{...}}`.

El motor vive embebido estáticamente en `motor.py` — no hay descarga dinámica
ni dependencia a Postgres.

## Tipos de comprobante

| TipoeCF | Descripción |
|---|---|
| `31` | Factura Crédito Fiscal |
| `32` | Factura de Consumo |
| `33` | Nota de Débito |
| `34` | Nota de Crédito |
| `41` | Compras (con retenciones) |
| `43` | Gastos Menores |
| `44` | Régimen Especial |
| `45` | Gubernamental |
| `46` | Exportación |
| `47` | Pagos al Exterior |

## Clases tipadas por comprobante (opcional)

Para construir payloads con validación local antes de enviar, usar el submódulo
`chalona_driver.comprobantes`:

```python
from chalona_driver import EcfClient
from chalona_driver.comprobantes import (
    FacturaCreditoFiscal31, EmisorData, CompradorData, DetalleItem,
)

client = EcfClient()
client.login('mi_correo@empresa.com', 'mi_clave')

c = FacturaCreditoFiscal31()
c.encf = 'E310000000001'
c.fecha_emision = '06-05-2026'
c.emisor = EmisorData(rnc='131996035', razon_social='Mi SRL', direccion='Calle 1')
c.comprador = CompradorData(rnc='01800451302', razon_social='Cliente SA')
# ... detalles y totales

c.validate()                # lanza EcfValidationError si falta o malformado
r = c.enviar(client, rnc='131996035', portal='testecf')
```

Clases disponibles: `FacturaCreditoFiscal31`, `FacturaConsumo32`, `NotaDebito33`,
`NotaCredito34`, `Compras41`, `GastosMenores43`, `RegimenEspecial44`,
`Gubernamental45`, `Exportacion46`, `PagosExterior47`.

## Layout del cliente

```
python-driver/
├── pyproject.toml
├── src/chalona_driver/
│   ├── __init__.py
│   ├── motor.py          # motor estático — lógica de comunicación
│   ├── ecf_client.py     # shell HTTP + trampolín
│   ├── contract.py       # ABC ComprobanteDriver (validaciones)
│   ├── loader.py         # carga drivers de pre-validación vía exec()
│   ├── postgres_source.py
│   ├── compiler.py
│   ├── exceptions.py     # EcfValidationError (clases tipadas)
│   └── comprobantes/     # clases tipadas 31-34, 41-47 + validation.py
├── tests/                # unit (comprobantes) + integration (HTTP real)
└── bin/
    ├── demo_envio.py             # demo 10 tipos → testecf
    └── prueba_comprobantes_driver.py
```

## Referencias

- Arquitectura general: `docs/architecture.md`
- Demo Dart (equivalente): `dart-driver/bin/demo_envio.dart`
