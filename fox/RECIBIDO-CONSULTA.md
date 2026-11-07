# Consultar la factura que un suplidor le emitió a la empresa (ventana de gastos)

`chalonaRecibidoConsulta(tcNcf, tcRncEmisor [, tcCodigoSeguridad])` → `ChalonaResponse`
(método `goChalonaEcf.RecibidoConsulta`, en el script publicado: llega sin tocar el ERP; el
envoltorio `chalonaRecibidoConsulta` está en `chalona-ecf-loader.prg`, el que ya instala el cliente).
Sin el envoltorio también sirve: `chalonaConsultaApi("ecf_recibido_consulta", '{"numero":"E31…","emisor":"101…"}')`.

Los dos primeros son obligatorios: **e-NCF** de la factura del suplidor y **RNC del suplidor** (emisor).
La empresa compradora es la de la sesión.

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

## Ejemplo desde la ventana de GASTOS

```foxpro
* tcNcf / tcRnc: lo que el usuario digitó; tcCod: código de seguridad del QR (opcional)
loResp = chalonaRecibidoConsulta(thisform.txtNcf.Value, thisform.txtRncSuplidor.Value, thisform.txtCodSeg.Value)
If goChalonaEcf.RecibidoConsultaACursores(loResp)       && crea curRecibidoCab y curRecibidoRen
  Select curRecibidoCab
  Do Case
    Case curRecibidoCab.origen == "chalona_recibidos"
      thisform.txtSuplidor.Value = curRecibidoCab.emisor_nom
      thisform.txtFecha.Value    = Date(Val(Left(curRecibidoCab.fecha,4)), Val(Substr(curRecibidoCab.fecha,6,2)), Val(Right(curRecibidoCab.fecha,2)))
      thisform.txtTotal.Value    = curRecibidoCab.total
      thisform.txtItbis.Value    = curRecibidoCab.itbis
      Select curRecibidoRen                              && renglones para el detalle del gasto
    Case curRecibidoCab.origen == "dgii"
      * SIN DETALLE: solo se puede validar monto / ITBIS / estado
      MESSAGEBOX("Validada en la DGII (" + curRecibidoCab.dgii_est + "), total " + ;
        TRANSFORM(curRecibidoCab.total) + ". " + curRecibidoCab.aviso)
  Endcase
Else
  MESSAGEBOX(curRecibidoCab.mensaje)   && p. ej. «…pida el código de seguridad al suplidor»
Endif
```

`curRecibidoCab` (un registro): origen, sin_detalle, aviso, encontrado, numero, emisor, emisor_nom, tipo, fecha, total, gravado,
exento, itbis, itbis_ret, isr_ret, estado, dgii_est, mensaje. `curRecibidoRen`: linea, nombre, descrip, cantidad, unidad, precio,
descuento, monto, ind_itbis, itbis_ret, isr_ret.

Endpoint (Postgres `fn.ecf_recibido_consulta`, sql/1856; la caída a la DGII la hace el middleware `EcfRecibidoConsulta` de sf).
