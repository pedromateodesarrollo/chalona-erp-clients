# Consultar la factura que un suplidor le emitió a la empresa (ventana de gastos)

```foxpro
llOk = goChalonaEcf.RecibidoConsulta(tcNcf, tcRncEmisor [, tcCodigoSeguridad] [, tcCurCab] [, tcCurDet])
```

**Sin JSON**: deja dos cursores VFP listos y devuelve `.T.` si encontró la factura, `.F.` si no
(el porqué en `goChalonaEcf.RecibidoMensaje`, que es lo mismo que `curRecibidoCab.motivo`).
Los cursores se crean siempre, aunque dé `.F.`.

- `tcNcf` / `tcRncEmisor` (obligatorios): **e-NCF** de la factura del suplidor y **RNC del suplidor** (emisor).
  La empresa compradora es la de la sesión.
- `tcCodigoSeguridad` (opcional): los 6 caracteres que el suplidor imprime junto al QR. Solo hace falta
  si la factura no está en Chalona y hay que validarla en la DGII.
- `tcCurCab` / `tcCurDet` (opcionales): nombres de los cursores. Por omisión `curRecibidoCab` y `curRecibidoDet`.

El método vive en el script publicado (`chalona-ecf.prg`, llega solo al ERP). El loader trae además el
envoltorio `chalonaRecibidoConsulta(...)` con los mismos parámetros y el mismo retorno, que recarga el script
si el servidor lo da por desactualizado. Quien prefiera el JSON: `goChalonaEcf.RecibidoConsultaResp(tcNcf, tcRnc [, tcCod])`
→ `ChalonaResponse`, y `goChalonaEcf.RecibidoConsultaACursores(loResp [, tcCurCab] [, tcCurDet])` lo pasa a cursores.

## Ejemplo desde la ventana de GASTOS

```foxpro
* txtNcf / txtRncSuplidor: lo que digitó el usuario; txtCodSeg: código de seguridad del QR (opcional)
If goChalonaEcf.RecibidoConsulta(thisform.txtNcf.Value, thisform.txtRncSuplidor.Value, thisform.txtCodSeg.Value)
  Select curRecibidoCab
  thisform.txtFecha.Value  = curRecibidoCab.fecha               && tipo D
  thisform.txtTotal.Value  = curRecibidoCab.MontoTotal
  thisform.txtItbis.Value  = curRecibidoCab.TotalITBIS
  If curRecibidoCab.origen == "chalona_recibidos"
    thisform.txtSuplidor.Value = curRecibidoCab.emisor_nom
    thisform.txtGravado.Value  = curRecibidoCab.MontoGravadoTotal
    thisform.txtExento.Value   = curRecibidoCab.MontoExento
    thisform.txtItbisRet.Value = curRecibidoCab.TotalITBISRetenido
    thisform.txtIsrRet.Value   = curRecibidoCab.TotalISRRetencion
    Select curRecibidoDet                                       && un registro por renglón
    Scan
      * Insert Into mis_gastos_det (descripcion, cantidad, precio, monto) ;
      *   Values (curRecibidoDet.nombre, curRecibidoDet.cantidad, curRecibidoDet.precio, curRecibidoDet.monto)
    Endscan
  Else
    * origen = "dgii": SIN DETALLE (curRecibidoDet vacío), solo estado, MontoTotal, TotalITBIS y fechas
    MESSAGEBOX("Validada en la DGII (" + Alltrim(curRecibidoCab.dgii_estado) + "). " + curRecibidoCab.aviso)
  Endif
Else
  MESSAGEBOX(goChalonaEcf.RecibidoMensaje)   && p. ej. «…pida el código de seguridad al suplidor»
  If curRecibidoCab.requiere == "codigo_seguridad"
    thisform.txtCodSeg.SetFocus()
  Endif
Endif
```

Con otros nombres de cursor: `goChalonaEcf.RecibidoConsulta(lcNcf, lcRnc, "", "c_gcab", "c_gdet")`.

## Los cursores

**`curRecibidoCab`** (un registro):

| Grupo | Campos |
|---|---|
| Resultado | `encontrado` L, `origen` C(20) (`chalona_recibidos` · `dgii` · `ninguno`), `motivo` C(254), `sin_detalle` L, `aviso` C(120), `requiere` C(30) (`codigo_seguridad` si solo faltó el código) |
| Cabecera | `id` N, `numero` C(13), `tipo` C(2), `emisor` C(11), `emisor_nom` C(150), `comprador` C(11), `comprador_nom` C(150), `fecha` D, `fecha_firma` C(19), `tipo_pago` C(1), `fecha_venc_pago` D, `fecha_venc_sec` D, `moneda` C(3), `ncf_modificado` C(19), `estado` C(30) (estado en Chalona; si origen=dgii, el de la DGII), `aprobacion` N(1) (0 por decidir, 1 aprobado, 2 rechazado), `dgii_estado` C(30), `codigo_seguridad` C(6) |
| Totales (nombre DGII, N(16,2); `ITBIS1..3` son las tasas, N(5,2)) | `MontoGravadoTotal`, `MontoGravadoI1`, `MontoGravadoI2`, `MontoGravadoI3`, `MontoExento`, `ITBIS1`, `ITBIS2`, `ITBIS3`, `TotalITBIS`, `TotalITBIS1`, `TotalITBIS2`, `TotalITBIS3`, `MontoImpuestoAdicional`, `TotalITBISRetenido`, `TotalISRRetencion`, `TotalITBISPercepcion`, `TotalISRPercepcion`, `MontoNoFacturable`, `MontoPeriodo`, `SaldoAnterior`, `MontoAvancePago`, `ValorPagar`, `MontoTotal` |

Un total que el e-CF no trae queda en 0. Con `origen = "dgii"` solo se llenan `numero`, `tipo`, `emisor`, `comprador`,
`fecha`, `fecha_firma`, `estado`/`dgii_estado`, `codigo_seguridad`, `MontoTotal` y `TotalITBIS`.

**`curRecibidoDet`** (un registro por renglón; vacío si `origen <> "chalona_recibidos"`): `linea` N(5), `nombre` C(120),
`descrip` M, `bien_serv` N(1) (1 bien, 2 servicio), `ind_itbis` N(2) (indicador de facturación), `cantidad` N(16,4),
`unidad` C(10), `precio` N(18,6), `descuento` N(16,2), `recargo` N(16,2), `monto` N(16,2), `itbis_ret` N(16,2), `isr_ret` N(16,2).

## De dónde sale el dato (`data.origen`, siempre viene)

| `origen` | Qué es | Qué trae |
|---|---|---|
| `chalona_recibidos` | El suplidor depositó su e-CF en el servicio de recepción de Chalona (`/fe/recepcion`). | **Todo**: `cabecera` (emisor, comprador, fecha, tipo, total, moneda, tipo de pago, firma), `totales` (gravado, exento, ITBIS, retenciones…) y `renglones` (nombre, cantidad, precio, descuento, monto, indicador ITBIS, retenciones por línea). `sin_detalle = .F.` |
| `dgii` | No está en Chalona; se validó en la DGII **como comprador**. | **Sin detalle**: `sin_detalle = .T.`, `aviso = "Sin detalle: solo validación DGII"`. Solo `dgii.estado_por_codigo`: estado (Aceptado…), `montoTotal`, `totalITBIS`, `fechaEmision`, `fechaFirma`, RNC emisor/comprador, e-NCF. **Exige `tcCodigoSeguridad`**. |
| `ninguno` | No se pudo. | `dgii_error` dice por qué. `requiere = "codigo_seguridad"` si solo faltó el código. |

### Qué permite la DGII a un comprador (verificado en producción, 2026-11-07, empresa 2)
- **ConsultaTrackIds / ConsultaResultado** (con el token de la empresa): solo el emisor o su delegado. Como comprador contesta
  código 2: «El RNC del token no está autorizado a consultar el trackid de este e-NCF… delegado por el emisor». **No sirve.**
- **ConsultaEstado** (`consultaestado/api/consultas/estado`, con token): `RncEmisor + ENCF + CodigoSeguridad (+ RncComprador)`.
  **Sí funciona al comprador**, pero necesita el **código de seguridad**: los 6 caracteres que salen impresos junto al
  QR/timbre de la factura del suplidor. Devuelve `codigo, estado, rncEmisor, ncfElectronico, montoTotal, totalITBIS,
  fechaEmision, fechaFirma, rncComprador, codigoSeguridad`.
- **ConsultaTimbre** (página pública, sin token): mismos datos que el QR (necesita fecha de emisión, monto y firma además del código); HTML con el estado.
- Ninguno da renglones, descripciones, retenciones ni datos del suplidor más allá del RNC. **El detalle de una factura ajena solo existe si el suplidor la envía a Chalona.**


Endpoint: Postgres `fn.ecf_recibido_consulta` (sql/1856); la caída a la DGII la hace el middleware `EcfRecibidoConsulta` de sf.
