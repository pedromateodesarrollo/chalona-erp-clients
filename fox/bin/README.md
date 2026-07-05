# demo_envio (Fox)

Demo standalone del cliente Fox ECF: envia 10 comprobantes (tipos
31-32-33-34-41-43-44-45-46-47) al portal `testecf` usando la **capa de
cursores** del motor (`CrearCursores` + `EnviarDesdeCursores`). El demo
llena los cursores públicos (`curChalMae`, `curChalDet`, `curChalEmp`,
`curChalCli`, `curChalRef`) en memoria y el motor envía a DGII.

No requiere SQL Server ni acceso a DBFs: todos los datos del comprobante
se construyen en el script.

Equivalente conceptual al `demo_envio.dart` (`ecf/clients/dart-driver/bin/`)
y `demo_envio.py` (`ecf/clients/python-driver/bin/`).

## Configuración

- Emisor: Vicortiz Softwares srl (RNC `131086268`)
- Usuario: `test@r131086268.com` / clave `1234`
- Portal: `testecf` (pruebas DGII)
- Base URL: `https://ecf-service.vicortiz.com`

Edita las constantes al inicio de `demo_envio.prg` para apuntar a otro
emisor o servidor.

## Cómo correr (Windows + VFP9)

```cmd
cd ecf\clients\fox\bin
"C:\Program Files (x86)\Microsoft Visual FoxPro 9\vfp9.exe" -t -clauncher.fpw
type demo_envio.log
```

Salida esperada en `demo_envio.log`:

```
=== demo_envio (Fox) ===
  ...
-- Login...
   OK - token recibido (...)

[1/10] Tipo 31
  OK  - estado: ...  eNCF: E31...
[2/10] Tipo 32
  OK  - estado: ...  eNCF: E32...
...

=========================================
  RESUMEN: 10 ok / 0 fail (de 10)
=========================================
  OK   Tipo 31  E31...  estado=...
  ...
```

## Archivos

| Archivo | Rol |
|---|---|
| `demo_envio.prg` | Script principal: login + loop 10 envíos |
| `launcher.fpw` | Config VFP headless (`SCREEN=OFF`, ejecuta demo) |
| `docs/doc_NN.json` | 10 comprobantes base (uno por tipo) |

Los JSON en `docs/` provienen de `documentos_certificacion_dgii` (mismos que
usan los demos Dart/Python). Datos del emisor del JSON original
(`DOCUMENTOS ELECTRONICOS DE 02` / RNC `131996035`) se reemplazan en runtime
con los del emisor configurado al inicio del `.prg`.
