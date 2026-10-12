*------------------------------------------------------------
* Chalona WhatsApp - cliente Visual FoxPro (VFP 9).
*
* Manda WhatsApp desde el numero de la empresa por el API de Chalona
* (https://whatsapp.chalonasoft.com): texto, y archivos (PDF de una
* factura, fotos, documentos) con el texto como pie. Consulta el estado de
* cada envio y lee las respuestas de los clientes.
*
* Uso minimo:
*   Set Procedure To chalona-whatsapp.prg Additive
*   loWa = Createobject("ChalonaWhatsapp", "cst_...")   && token de la cuenta de servicio
*   loR  = loWa.EnviarArchivo("8095551234", "C:\facturas\FT-000123.pdf", ;
*            "Le enviamos su factura FT-000123.", "FT-000123")
*   If !loR.ok
*     Messagebox(loR.mensaje, 16, "WhatsApp")
*   Endif
*
* Guia completa (endpoints, estados, codigos de error, ejemplos):
*   README.md de esta misma carpeta.
*
* Reglas del archivo (para quien lo toque):
*   - Autocontenido: no depende de chalona-ecf.prg ni de ninguna libreria.
*     Todo lo publico se llama ChalonaWa* / _ChalonaWa* para no chocar con
*     el ERP ni con el cliente ECF cargados en el mismo SET PROCEDURE.
*   - Nada de RETURN dentro de TRY/CATCH (VFP no lo permite): se usa una
*     variable y se sale despues del ENDTRY.
*   - Solo ASCII en el codigo: VFP lee el .prg en la pagina de codigos de
*     Windows y un acento en UTF-8 sale como basura en los mensajes.
*------------------------------------------------------------

#Define CHALONA_WA_VERSION   "1.0.0"
#Define CHALONA_WA_URL       "https://whatsapp.chalonasoft.com/api/"
* El servidor acepta hasta 16 MB, pero el archivo viaja en base64 dentro de un
* texto de VFP, que no pasa con seguridad de ~16 millones de caracteres.
#Define CHALONA_WA_MAX_BYTES 10485760

Define Class ChalonaWhatsapp As Custom

  BaseUrl = CHALONA_WA_URL
  Token   = ""
  * Agente (numero vinculado) por el que sale. 0 = el unico activo de la empresa;
  * si la empresa tiene mas de uno, hay que decir cual (ver Agentes()).
  Agente  = 0
  * Componente HTTP. MSXML2.XMLHTTP usa la configuracion de internet de
  * Windows (la misma del cliente ECF). En un servidor sin IE configurado
  * puede ir "MSXML2.ServerXMLHTTP.6.0".
  ComponenteHttp = "MSXML2.XMLHTTP"
  * Cuerpo de la ultima peticion, sin el base64 del archivo (para un log).
  UltimaPeticion = ""

  Procedure Init
    Lparameters tcToken, tcBaseUrl
    If Vartype(tcToken) = "C"
      This.Token = Alltrim(tcToken)
    Endif
    If Vartype(tcBaseUrl) = "C" And !Empty(tcBaseUrl)
      This.BaseUrl = Alltrim(tcBaseUrl)
    Endif
  Endproc

  *----------------------------------------------------------
  * Envios. Devuelven un ChalonaWaRespuesta; si ok, .id y .estado
  * ("pendiente": quedo en la cola; sale en segundos o minutos).
  *
  * tcControl (opcional, pero recomendado): llave del envio en TU sistema,
  * p.ej. "FT-000123" o "FT-000123-pdf". Repetir el envio con el mismo
  * control NO manda otro mensaje: devuelve el que ya existe (.repetido = .T.).
  * Asi un reintento tras un corte de red no le llega dos veces al cliente.
  *----------------------------------------------------------

  Function EnviarTexto
    Lparameters tcNumero, tcTexto, tcControl
    Return This.Enviar(tcNumero, tcTexto, "", tcControl)
  Endfunc

  * tcRuta: archivo en disco. tcTexto va como pie del archivo (puede ir vacio).
  * tcNombre: nombre con que lo ve el cliente (por defecto, el del archivo).
  * Fotos (jpg, png, webp) salen como imagen; lo demas, como documento.
  Function EnviarArchivo
    Lparameters tcNumero, tcRuta, tcTexto, tcControl, tcNombre
    Return This.Enviar(tcNumero, tcTexto, tcRuta, tcControl, tcNombre)
  Endfunc

  Function Enviar
    Lparameters tcNumero, tcTexto, tcRuta, tcControl, tcNombre, tcMime
    Local lcNumero, lcTexto, lcRuta, lcNombre, lcMime, lcBase64, lcCuerpo, lcLog
    Local lcErr, lnBytes, loEx, loR, laArch[1]

    lcNumero = _ChalonaWaNumero(tcNumero)
    lcTexto  = Iif(Vartype(tcTexto) = "C", Alltrim(tcTexto), "")
    lcRuta   = Iif(Vartype(tcRuta) = "C", Alltrim(tcRuta), "")
    lcBase64 = ""
    lcErr    = ""

    If Empty(lcNumero)
      Return ChalonaWaRespuestaError("whatsapp.numero_invalido", ;
        "El numero no es valido. Va con codigo de pais, por ejemplo 18095551234.")
    Endif
    If Empty(lcRuta) And Empty(lcTexto)
      Return ChalonaWaRespuestaError("whatsapp.texto_requerido", "Falta el texto del mensaje.")
    Endif

    If !Empty(lcRuta)
      If !File(lcRuta)
        Return ChalonaWaRespuestaError("archivo.no_existe", "No existe el archivo: " + lcRuta)
      Endif
      lcNombre = Iif(Vartype(tcNombre) = "C" And !Empty(tcNombre), Alltrim(tcNombre), Justfname(lcRuta))
      lcMime   = Iif(Vartype(tcMime) = "C" And !Empty(tcMime), Alltrim(tcMime), ChalonaWaMime(lcNombre))
      lnBytes  = 0
      Try
        lnBytes = Adir(laArch, lcRuta)
        lnBytes = Iif(lnBytes > 0, laArch[1, 2], 0)
        If lnBytes > CHALONA_WA_MAX_BYTES
          lcErr = "archivo.muy_grande"
        Else
          lcBase64 = Strconv(Filetostr(lcRuta), 13)
        Endif
      Catch To loEx
        lcErr = "archivo.no_se_pudo_leer: " + loEx.Message
      Endtry
      Do Case
        Case lcErr == "archivo.muy_grande"
          Return ChalonaWaRespuestaError(lcErr, "El archivo pesa " + Transform(Round(lnBytes / 1048576, 1)) + ;
            " MB; el maximo es " + Transform(Int(CHALONA_WA_MAX_BYTES / 1048576)) + " MB.")
        Case !Empty(lcErr)
          Return ChalonaWaRespuestaError("archivo.no_se_pudo_leer", "No se pudo leer " + lcRuta + " (" + lcErr + ")")
        Case Empty(lcBase64)
          Return ChalonaWaRespuestaError("archivo.vacio", "El archivo esta vacio: " + lcRuta)
      Endcase
    Endif

    * El cuerpo se arma en dos partes para poder dejar en UltimaPeticion la
    * version sin el base64 (que puede ser de megas).
    lcCuerpo = '{"a":"' + lcNumero + '"'
    If !Empty(lcTexto)
      lcCuerpo = lcCuerpo + ',"texto":"' + ChalonaWaJsonTexto(lcTexto) + '"'
    Endif
    If Vartype(tcControl) = "C" And !Empty(tcControl)
      lcCuerpo = lcCuerpo + ',"control":"' + ChalonaWaJsonTexto(Alltrim(tcControl)) + '"'
    Endif
    If This.Agente > 0
      lcCuerpo = lcCuerpo + ',"agente":' + Transform(Int(This.Agente))
    Endif
    If Empty(lcBase64)
      lcLog = lcCuerpo + '}'
      lcCuerpo = lcLog
    Else
      lcLog = lcCuerpo + ',"archivo":{"nombre":"' + ChalonaWaJsonTexto(lcNombre) + '","mime":"' + lcMime + ;
        '","data":"(' + Transform(lnBytes) + ' bytes)"}}'
      lcCuerpo = lcCuerpo + ',"archivo":{"nombre":"' + ChalonaWaJsonTexto(lcNombre) + '","mime":"' + lcMime + ;
        '","data":"' + lcBase64 + '"}}'
      lcBase64 = ""
    Endif

    loR = This._Post("whatsapp_enviar", lcCuerpo, lcLog)
    lcCuerpo = ""
    This._LlenarRegistro(loR)
    Return loR
  Endfunc

  *----------------------------------------------------------
  * Estado de un envio: por el id que devolvio Enviar, o por tu control.
  * .estado: pendiente | enviando | enviado | fallido | incierto | cancelado
  *   fallido  = no salio (.registro.error dice por que: sin_whatsapp = ese
  *              numero no tiene WhatsApp; whatsapp_desconectado = la PC del
  *              agente no estaba conectada a WhatsApp).
  *   incierto = se le entrego al agente y no confirmo: PUDO haber salido. No
  *              se reintenta solo; revisalo antes de mandarlo otra vez.
  *----------------------------------------------------------
  Function Estado
    Lparameters tnId
    Local loR
    loR = This._Post("whatsapp_mensaje_select", '{"id":' + Transform(Int(Val(Transform(tnId)))) + '}')
    This._LlenarRegistro(loR)
    Return loR
  Endfunc

  Function EstadoPorControl
    Lparameters tcControl
    Local loR
    loR = This._Post("whatsapp_mensaje_select", '{"control":"' + ChalonaWaJsonTexto(Alltrim(Nvl(tcControl, ""))) + '"}')
    This._LlenarRegistro(loR)
    Return loR
  Endfunc

  * Lo enviado, del mas nuevo al mas viejo. Todos los filtros son opcionales.
  * tcDesde/tcHasta: fecha ISO, p.ej. "2026-10-01". .lista = Collection.
  Function Mensajes
    Lparameters tcNumero, tcEstado, tcDesde, tcHasta, tnLimite, tnSaltar
    Local lcCuerpo, loR
    lcCuerpo = '{"limit":' + Transform(Iif(Vartype(tnLimite) = "N" And tnLimite > 0, Int(tnLimite), 50)) + ;
      ',"offset":' + Transform(Iif(Vartype(tnSaltar) = "N", Int(tnSaltar), 0))
    lcCuerpo = lcCuerpo + _ChalonaWaParam("a", _ChalonaWaNumero(tcNumero)) + _ChalonaWaParam("estado", tcEstado) + ;
      _ChalonaWaParam("desde", tcDesde) + _ChalonaWaParam("hasta", tcHasta)
    If This.Agente > 0
      lcCuerpo = lcCuerpo + ',"agente":' + Transform(Int(This.Agente))
    Endif
    loR = This._Post("whatsapp_mensaje_select", lcCuerpo + '}')
    This._LlenarLista(loR)
    Return loR
  Endfunc

  * Un mensaje que todavia no salio (pendiente) se puede cancelar.
  Function Cancelar
    Lparameters tnId
    Local loR
    loR = This._Post("whatsapp_mensaje_cancelar", '{"id":' + Transform(Int(Val(Transform(tnId)))) + '}')
    This._LlenarRegistro(loR)
    Return loR
  Endfunc

  *----------------------------------------------------------
  * Respuestas de los clientes. Solo se guardan las de chats a los que se les
  * escribio desde Chalona en los ultimos 30 dias.
  *
  * Para leer solo lo nuevo: guarda .ultimo_id y pasalo como tnDespuesDe en
  * la siguiente llamada (0 = las mas recientes). Vienen de la mas nueva a la
  * mas vieja; con tnDespuesDe son las tnLimite MAS VIEJAS despues de ese id,
  * asi que repitiendo hasta que .lista venga vacia no se salta ninguna.
  *----------------------------------------------------------
  Function Respuestas
    Lparameters tnDespuesDe, tcNumero, tnLimite
    Local lcCuerpo, loR, loItem
    lcCuerpo = '{"limit":' + Transform(Iif(Vartype(tnLimite) = "N" And tnLimite > 0, Int(tnLimite), 50))
    If Vartype(tnDespuesDe) = "N" And tnDespuesDe > 0
      lcCuerpo = lcCuerpo + ',"despues_de":' + Transform(Int(tnDespuesDe))
    Endif
    lcCuerpo = lcCuerpo + _ChalonaWaParam("de", _ChalonaWaNumero(tcNumero))
    If This.Agente > 0
      lcCuerpo = lcCuerpo + ',"agente":' + Transform(Int(This.Agente))
    Endif
    loR = This._Post("whatsapp_recibido_select", lcCuerpo + '}')
    This._LlenarLista(loR)
    loR.ultimo_id = Iif(Vartype(tnDespuesDe) = "N", tnDespuesDe, 0)
    If !Isnull(loR.lista)
      For Each loItem In loR.lista
        If _ChalonaWaProp(loItem, "id", 0) > loR.ultimo_id
          loR.ultimo_id = loItem.id
        Endif
      Endfor
    Endif
    Return loR
  Endfunc

  * Lo mismo que Respuestas, en un cursor (id, de, nombre, texto, tipo, hora).
  Function RespuestasACursor
    Lparameters tcCursor, tnDespuesDe, tcNumero, tnLimite
    Local loR, loItem
    loR = This.Respuestas(tnDespuesDe, tcNumero, tnLimite)
    Create Cursor (tcCursor) (id I, de C(20), nombre C(120), texto M, tipo C(20), hora C(32), agente I)
    If loR.ok And !Isnull(loR.lista)
      For Each loItem In loR.lista
        Insert Into (tcCursor) (id, de, nombre, texto, tipo, hora, agente) Values ( ;
          _ChalonaWaProp(loItem, "id", 0), _ChalonaWaProp(loItem, "de", ""), _ChalonaWaProp(loItem, "nombre", ""), ;
          _ChalonaWaProp(loItem, "texto", ""), _ChalonaWaProp(loItem, "tipo", ""), _ChalonaWaProp(loItem, "hora", ""), ;
          _ChalonaWaProp(loItem, "agente", 0))
      Endfor
      Go Top In (tcCursor)
    Endif
    Return loR
  Endfunc

  * Los agentes (numeros vinculados) de la empresa: id, nombre, numero,
  * conectado, vinculado y lo de hoy (enviados, en cola, fallidos).
  Function Agentes
    Local loR
    loR = This._Post("whatsapp_agente_select", '{}')
    This._LlenarLista(loR)
    Return loR
  Endfunc

  *----------------------------------------------------------
  * Internos
  *----------------------------------------------------------

  Function _Post
    Lparameters tcEndpoint, tcCuerpo, tcLog
    Local loHttp, lcUrl, lcCuerpo, lcResp, lnStatus, lcErr, loEx

    If Empty(This.Token)
      Return ChalonaWaRespuestaError("token.vacio", "Falta el token de la cuenta de servicio (cst_...).")
    Endif
    lcUrl = Alltrim(This.BaseUrl)
    If Right(lcUrl, 1) # "/"
      lcUrl = lcUrl + "/"
    Endif
    lcUrl = lcUrl + tcEndpoint
    * locale: el servidor devuelve el mensaje de error ya en espanol.
    lcCuerpo = Left(tcCuerpo, Len(tcCuerpo) - 1) + Iif(Len(tcCuerpo) > 2, ",", "") + ;
      '"locale":"es","cliente":"fox-whatsapp ' + CHALONA_WA_VERSION + '"}'
    This.UltimaPeticion = Iif(Vartype(tcLog) = "C", tcLog, tcCuerpo)

    lcResp   = ""
    lnStatus = 0
    lcErr    = ""
    loHttp   = .Null.
    Try
      loHttp = Createobject(This.ComponenteHttp)
      loHttp.open("POST", lcUrl, .F.)
      loHttp.setRequestHeader("Content-Type", "application/json; charset=utf-8")
      loHttp.setRequestHeader("Authorization", "Bearer " + This.Token)
      loHttp.send(lcCuerpo)
      lnStatus = loHttp.status
      If Vartype(loHttp.responseText) = "C"
        lcResp = loHttp.responseText
      Endif
    Catch To loEx
      lcErr = loEx.Message
    Endtry
    loHttp = .Null.
    lcCuerpo = ""

    If !Empty(lcErr)
      Return ChalonaWaRespuestaError("http.sin_respuesta", ;
        "No se pudo hablar con el servidor de WhatsApp (" + lcUrl + "): " + lcErr)
    Endif
    Return ChalonaWaRespuestaDeCuerpo(lcResp, lnStatus)
  Endfunc

  * Si el resultado es un mensaje (o una lista de uno), lo deja en .registro,
  * .id y .estado.
  Procedure _LlenarRegistro
    Lparameters loR
    Local loRes
    If !loR.ok Or Vartype(loR.data) # "O" Or !Pemstatus(loR.data, "result", 5)
      Return
    Endif
    loRes = loR.data.result
    If _ChalonaWaEsLista(loRes)
      loR.lista = loRes
      If loRes.Count = 0
        loR.ok = .F.
        loR.codigo = "whatsapp.mensaje_no_encontrado"
        loR.mensaje = "No se encontro ese mensaje."
        Return
      Endif
      loRes = loRes.Item(1)
    Endif
    If Vartype(loRes) = "O"
      loR.registro = loRes
      loR.id = _ChalonaWaProp(loRes, "id", 0)
      loR.estado = _ChalonaWaProp(loRes, "estado", "")
    Endif
    If Pemstatus(loR.data, "repetido", 5)
      loR.repetido = (loR.data.repetido = .T.)
    Endif
  Endproc

  Procedure _LlenarLista
    Lparameters loR
    If loR.ok And Vartype(loR.data) = "O" And Pemstatus(loR.data, "result", 5) And Vartype(loR.data.result) = "O"
      loR.lista = loR.data.result
      If Pemstatus(loR.data, "total", 5)
        loR.total = loR.data.total
      Else
        loR.total = loR.lista.Count
      Endif
    Endif
  Endproc

Enddefine

*------------------------------------------------------------
* Respuesta de cada llamada.
*   ok        .T. / .F.
*   codigo    codigo del error (whatsapp.tope_dia, ...); vacio si ok
*   mensaje   el error en espanol, para mostrarlo tal cual
*   data      lo que devolvio el servidor, como objeto (Empty / Collection)
*   registro  el mensaje (en Enviar, Estado, Cancelar)
*   id, estado
*   repetido  .T. si el control ya existia y no se mando otra vez
*   lista     Collection (Mensajes, Respuestas, Agentes)
*   total, ultimo_id
*   http_status, crudo (el JSON tal como llego)
*------------------------------------------------------------
Define Class ChalonaWaRespuesta As Custom
  ok          = .F.
  codigo      = ""
  mensaje     = ""
  data        = .Null.
  registro    = .Null.
  id          = 0
  estado      = ""
  repetido    = .F.
  lista       = .Null.
  total       = 0
  ultimo_id   = 0
  http_status = 0
  crudo       = ""
Enddefine

Function ChalonaWaRespuestaError
  Lparameters tcCodigo, tcMensaje
  Local loR
  loR = Createobject("ChalonaWaRespuesta")
  loR.ok = .F.
  loR.codigo = tcCodigo
  loR.mensaje = Iif(Empty(Nvl(tcMensaje, "")), tcCodigo, tcMensaje)
  Return loR
Endfunc

Function ChalonaWaRespuestaDeCuerpo
  Lparameters tcCuerpo, tnStatus
  Local loR, loJson, lcErr, loEx
  loR = Createobject("ChalonaWaRespuesta")
  loR.http_status = Nvl(tnStatus, 0)
  loR.crudo = Nvl(tcCuerpo, "")
  loJson = .Null.
  lcErr = ""
  If Left(Alltrim(loR.crudo), 1) == "{"
    Try
      loJson = ChalonaWaJsonLeer(loR.crudo)
    Catch To loEx
      lcErr = loEx.Message
    Endtry
  Endif
  If Vartype(loJson) # "O" Or !Pemstatus(loJson, "ok", 5)
    Do Case
      Case loR.http_status = 429
        loR.codigo = "http.429"
        loR.mensaje = "Demasiadas peticiones seguidas al servidor de WhatsApp; espere unos segundos y repita."
      Case loR.http_status = 413
        loR.codigo = "http.413"
        loR.mensaje = "El archivo es demasiado grande para el servidor."
      Otherwise
        loR.codigo = "http.respuesta_invalida"
        loR.mensaje = "El servidor de WhatsApp contesto algo que no se entiende (HTTP " + ;
          Transform(loR.http_status) + ")" + Iif(Empty(lcErr), "", ": " + lcErr)
    Endcase
    Return loR
  Endif

  loR.ok = (loJson.ok = .T.)
  If Pemstatus(loJson, "data", 5)
    loR.data = loJson.data
  Endif
  If !loR.ok
    loR.mensaje = Iif(Pemstatus(loJson, "message", 5) And Vartype(loJson.message) = "C", loJson.message, "")
    loR.codigo = loR.mensaje
    If Vartype(loR.data) = "O" And Pemstatus(loR.data, "message_code", 5) And Vartype(loR.data.message_code) = "C"
      loR.codigo = loR.data.message_code
    Endif
    * Los errores de la sesion vienen sin traducir.
    Do Case
      Case Atc("err.sistema_token_login", loR.codigo) = 1
        loR.mensaje = "El token no es valido, esta revocado o vencio. Pida uno nuevo a su proveedor."
      Case Atc("err.ejecutar", loR.codigo) = 1
        loR.mensaje = "La cuenta de servicio no tiene permiso para esto (" + loR.codigo + ")."
      Case Empty(loR.mensaje)
        loR.mensaje = "Error sin mensaje (HTTP " + Transform(loR.http_status) + ")."
    Endcase
  Endif
  Return loR
Endfunc

*------------------------------------------------------------
* Ayudantes
*------------------------------------------------------------

* Solo los digitos. Un numero dominicano de 10 digitos (809/829/849) va tal
* cual: el servidor le pone el 1. Fuera de RD, con su codigo de pais.
Function _ChalonaWaNumero
  Lparameters tcNumero
  Local lc, i, c, lcOut
  lc = Alltrim(Transform(Nvl(tcNumero, "")))
  lcOut = ""
  For i = 1 To Len(lc)
    c = Substr(lc, i, 1)
    If Isdigit(c)
      lcOut = lcOut + c
    Endif
  Endfor
  Return lcOut
Endfunc

Function _ChalonaWaParam
  Lparameters tcNombre, tcValor
  If Vartype(tcValor) # "C" Or Empty(tcValor)
    Return ""
  Endif
  Return ',"' + tcNombre + '":"' + ChalonaWaJsonTexto(Alltrim(tcValor)) + '"'
Endfunc

* .T. si es una Collection (lo que da un arreglo JSON). Un Empty no tiene BaseClass.
Function _ChalonaWaEsLista
  Lparameters toObj
  If Vartype(toObj) # "O" Or !Pemstatus(toObj, "BaseClass", 5)
    Return .F.
  Endif
  Return Lower(toObj.BaseClass) == "collection"
Endfunc

Function _ChalonaWaProp
  Lparameters toObj, tcProp, tuDefecto
  If Vartype(toObj) = "O" And Pemstatus(toObj, tcProp, 5)
    Return Nvl(Evaluate("toObj." + tcProp), tuDefecto)
  Endif
  Return tuDefecto
Endfunc

Function ChalonaWaMime
  Lparameters tcNombre
  Local lcExt
  lcExt = Lower(Justext(Nvl(tcNombre, "")))
  Do Case
    Case lcExt == "pdf"
      Return "application/pdf"
    Case Inlist(lcExt, "jpg", "jpeg")
      Return "image/jpeg"
    Case lcExt == "png"
      Return "image/png"
    Case lcExt == "webp"
      Return "image/webp"
    Case lcExt == "gif"
      Return "image/gif"
    Case lcExt == "xlsx"
      Return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    Case lcExt == "xls"
      Return "application/vnd.ms-excel"
    Case lcExt == "docx"
      Return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    Case lcExt == "doc"
      Return "application/msword"
    Case lcExt == "txt"
      Return "text/plain"
    Case lcExt == "csv"
      Return "text/csv"
    Case lcExt == "xml"
      Return "application/xml"
    Case lcExt == "zip"
      Return "application/zip"
    Case lcExt == "mp4"
      Return "video/mp4"
  Endcase
  Return "application/octet-stream"
Endfunc

* Texto -> contenido de una cadena JSON (sin las comillas).
Function ChalonaWaJsonTexto
  Lparameters tc
  Local lc, i
  lc = Nvl(tc, "")
  lc = Strtran(lc, "\", "\\")
  lc = Strtran(lc, '"', '\"')
  lc = Strtran(lc, Chr(13) + Chr(10), "\n")
  lc = Strtran(lc, Chr(13), "\n")
  lc = Strtran(lc, Chr(10), "\n")
  lc = Strtran(lc, Chr(9), "\t")
  For i = 0 To 31
    If Chr(i) $ lc
      lc = Strtran(lc, Chr(i), "")
    Endif
  Endfor
  Return lc
Endfunc

*------------------------------------------------------------
* Lector de JSON: objeto -> Empty con propiedades, arreglo -> Collection,
* texto -> C, numero -> N, true/false -> L, null -> .Null.
* Un nombre de propiedad que VFP no acepta se normaliza (letras, digitos y _).
*------------------------------------------------------------
Function ChalonaWaJsonLeer
  Lparameters tcJson
  Local loP
  loP = Createobject("ChalonaWaJsonLector", tcJson)
  Return loP.Valor()
Endfunc

Define Class ChalonaWaJsonLector As Custom
  cJson = ""
  nPos  = 1
  nLen  = 0
  cPunto = "."

  Procedure Init
    Lparameters tcJson
    This.cJson = Nvl(tcJson, "")
    This.nLen = Len(This.cJson)
    This.nPos = 1
    This.cPunto = Set("Point")
  Endproc

  Procedure Espacios
    Do While This.nPos <= This.nLen And Substr(This.cJson, This.nPos, 1) $ " " + Chr(9) + Chr(10) + Chr(13)
      This.nPos = This.nPos + 1
    Enddo
  Endproc

  Function Valor
    Local c
    This.Espacios()
    c = Substr(This.cJson, This.nPos, 1)
    Do Case
      Case c == "{"
        Return This.Objeto()
      Case c == "["
        Return This.Arreglo()
      Case c == '"'
        Return This.Texto()
      Case Substr(This.cJson, This.nPos, 4) == "true"
        This.nPos = This.nPos + 4
        Return .T.
      Case Substr(This.cJson, This.nPos, 5) == "false"
        This.nPos = This.nPos + 5
        Return .F.
      Case Substr(This.cJson, This.nPos, 4) == "null"
        This.nPos = This.nPos + 4
        Return .Null.
    Endcase
    Return This.Numero()
  Endfunc

  Function Objeto
    Local loObj, lcClave, luValor
    loObj = Createobject("Empty")
    This.nPos = This.nPos + 1
    This.Espacios()
    If Substr(This.cJson, This.nPos, 1) == "}"
      This.nPos = This.nPos + 1
      Return loObj
    Endif
    Do While This.nPos <= This.nLen
      This.Espacios()
      lcClave = _ChalonaWaNombreVfp(This.Texto())
      This.Espacios()
      This.nPos = This.nPos + 1 && :
      luValor = This.Valor()
      If !Empty(lcClave) And !Pemstatus(loObj, lcClave, 5)
        AddProperty(loObj, lcClave, luValor)
      Endif
      This.Espacios()
      If Substr(This.cJson, This.nPos, 1) == ","
        This.nPos = This.nPos + 1
      Else
        This.nPos = This.nPos + 1 && }
        Exit
      Endif
    Enddo
    Return loObj
  Endfunc

  Function Arreglo
    Local loCol
    loCol = Createobject("Collection")
    This.nPos = This.nPos + 1
    This.Espacios()
    If Substr(This.cJson, This.nPos, 1) == "]"
      This.nPos = This.nPos + 1
      Return loCol
    Endif
    Do While This.nPos <= This.nLen
      loCol.Add(This.Valor())
      This.Espacios()
      If Substr(This.cJson, This.nPos, 1) == ","
        This.nPos = This.nPos + 1
      Else
        This.nPos = This.nPos + 1 && ]
        Exit
      Endif
    Enddo
    Return loCol
  Endfunc

  Function Texto
    Local lcOut, c, lnIni, lnCod
    lcOut = ""
    This.nPos = This.nPos + 1 && comilla de apertura
    lnIni = This.nPos
    Do While This.nPos <= This.nLen
      c = Substr(This.cJson, This.nPos, 1)
      Do Case
        Case c == '"'
          lcOut = lcOut + Substr(This.cJson, lnIni, This.nPos - lnIni)
          This.nPos = This.nPos + 1
          Exit
        Case c == "\"
          lcOut = lcOut + Substr(This.cJson, lnIni, This.nPos - lnIni)
          c = Substr(This.cJson, This.nPos + 1, 1)
          This.nPos = This.nPos + 2
          Do Case
            Case c == "n"
              lcOut = lcOut + Chr(13) + Chr(10)
            Case c == "r"
            Case c == "t"
              lcOut = lcOut + Chr(9)
            Case c == "b" Or c == "f"
            Case c == "u"
              lnCod = Evaluate("0x" + Substr(This.cJson, This.nPos, 4))
              This.nPos = This.nPos + 4
              If lnCod < 128
                lcOut = lcOut + Chr(lnCod)
              Else
                * UTF-16 -> pagina de codigos de Windows (lo que no exista sale como ?).
                lcOut = lcOut + Strconv(Chr(Bitand(lnCod, 255)) + Chr(Bitrshift(lnCod, 8)), 6)
              Endif
            Otherwise
              lcOut = lcOut + c && \" \\ \/
          Endcase
          lnIni = This.nPos
        Otherwise
          This.nPos = This.nPos + 1
      Endcase
    Enddo
    Return lcOut
  Endfunc

  Function Numero
    Local lnIni, lc
    lnIni = This.nPos
    Do While This.nPos <= This.nLen And Substr(This.cJson, This.nPos, 1) $ "+-0123456789.eE"
      This.nPos = This.nPos + 1
    Enddo
    lc = Substr(This.cJson, lnIni, This.nPos - lnIni)
    If This.nPos = lnIni
      * Algo que no es JSON: se avanza para no quedar en un ciclo.
      This.nPos = This.nPos + 1
      Return .Null.
    Endif
    If This.cPunto # "."
      lc = Strtran(lc, ".", This.cPunto)
    Endif
    Return Val(lc)
  Endfunc
Enddefine

Function _ChalonaWaNombreVfp
  Lparameters tcNombre
  Local lc, i, c, lcOut
  lc = Nvl(tcNombre, "")
  lcOut = ""
  For i = 1 To Len(lc)
    c = Substr(lc, i, 1)
    lcOut = lcOut + Iif(Between(Asc(Upper(c)), 65, 90) Or Isdigit(c) Or c == "_", c, "_")
  Endfor
  If Isdigit(Left(lcOut, 1))
    lcOut = "_" + lcOut
  Endif
  Return Left(lcOut, 128)
Endfunc
