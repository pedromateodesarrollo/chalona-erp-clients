*------------------------------------------------------------
* Ejemplo: mandar una factura por WhatsApp desde un ERP en FoxPro.
*
*   DO ejemplo-whatsapp.prg WITH "cst_...", "18095551234", "C:\facturas\FT-000123.pdf"
*
* Pruebelo primero mandandose el mensaje a su propio numero.
*------------------------------------------------------------
Lparameters tcToken, tcNumero, tcPdf

Local loWa, loR, lnI, loItem

Set Procedure To chalona-whatsapp.prg Additive

loWa = Createobject("ChalonaWhatsapp", tcToken)

* 1. El numero de la empresa (agente): conectado y vinculado.
loR = loWa.Agentes()
If !loR.ok
  Messagebox(loR.mensaje, 16, "WhatsApp")
  Return
Endif
For Each loItem In loR.lista
  ? "Agente", loItem.id, loItem.nombre, loItem.numero, ;
    Iif(loItem.conectado, "conectado", "DESCONECTADO"), Iif(loItem.vinculado, "vinculado", "SIN VINCULAR")
Endfor

* 2. Un texto. El control (aqui "FT-000123-aviso") evita mandarlo dos veces.
loR = loWa.EnviarTexto(tcNumero, "Buenos dias. Le enviamos su factura FT-000123.", "FT-000123-aviso")
If !loR.ok
  Messagebox(loR.mensaje, 16, "WhatsApp")
  Return
Endif
? "Texto en cola, id", loR.id, loR.estado, Iif(loR.repetido, "(ya se habia mandado)", "")

* 3. El PDF, con su pie.
If !Empty(Nvl(tcPdf, ""))
  loR = loWa.EnviarArchivo(tcNumero, tcPdf, "Factura FT-000123", "FT-000123-pdf")
  If !loR.ok
    Messagebox(loR.mensaje, 16, "WhatsApp")
    Return
  Endif
  ? "PDF en cola, id", loR.id

  * 4. Esperar a que salga (en un ERP real esto se consulta despues, no se espera).
  For lnI = 1 To 20
    Inkey(3)
    loR = loWa.Estado(loR.id)
    ? "Estado:", loR.estado
    If !Inlist(loR.estado, "pendiente", "enviando")
      Exit
    Endif
  Endfor
  If loR.estado == "fallido"
    ? "No salio:", loR.registro.error
  Endif
Endif

* 5. Respuestas nuevas (guarde .ultimo_id para la proxima vez).
loR = loWa.RespuestasACursor("curWaRespuestas", 0)
If loR.ok
  Select curWaRespuestas
  Browse Nowait
  ? "Ultima respuesta leida:", loR.ultimo_id
Endif
