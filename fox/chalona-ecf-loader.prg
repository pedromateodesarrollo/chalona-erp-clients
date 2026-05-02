*------------------------------------------------------------
* Chalona ECF - Loader (bootstrap).
* Instalar este archivo localmente en lugar de chalona-ecf.prg.
* Descarga la programacion desde el servidor (fox_cliente_script),
* la compila e instancia goChalonaEcf.
*
* Config:
*   ERPs con Public osis (Vicortiz): se lee automaticamente al instanciar.
*   ERPs sin osis (Alberto/otros): llamar chalonaSetConfig(loCfg) antes
*   de cualquier chalonaEnviaEcf/chalonaSincronizaEstados/etc. loCfg debe
*   exponer servidor_ecf, usuario_sync, pass_sync, portal_dgii,
*   dgii_multimoneda (todas como cadenas).
*   Si no hay osis ni cfg, URL/entorno caen al hardcoded.
*------------------------------------------------------------

* chalonaSetConfig(loCfg) -> inyecta el objeto de configuracion y dispara
* la descarga + carga del motor (_ChalonaLoaderInit). Tras esta llamada,
* goChalonaEcf esta listo y se puede invocar chalonaEnviaEcf/etc.
* Retorna .T. si el motor quedo cargado, .F. si la descarga fallo.
Function chalonaSetConfig
  Lparameters toCfg
  If Vartype(toCfg) # "O"
    Return .F.
  Endif
  Public goChalonaEcfCfg
  goChalonaEcfCfg = toCfg
  If Type("goChalonaEcf") = "O" And !Isnull(goChalonaEcf) ;
      And Pemstatus(goChalonaEcf, "SetConfig", 5)
    goChalonaEcf.SetConfig(toCfg)
  Endif
  Return _ChalonaLoaderInit()
Endfunc

* chalonaVersionCliente() -> version numerica del script cargado (0 si fallo la descarga)
Function chalonaVersionCliente
  If !_ChalonaLoaderInit()
    Return 0
  Endif
  Return gcChalonaFoxVersion
Endfunc

* chalonaEnviaEcf(tcControl) -> ChalonaResponse
Function chalonaEnviaEcf
  Parameters tcControl
  If !_ChalonaLoaderInit()
    Return _ChalonaLoaderFail("fox_cliente.script_no_disponible")
  Endif
  Local loResp
  loResp = goChalonaEcf.Enviar(tcControl)
  If _ChalonaLoaderEsVersionDesact(loResp)
    If _ChalonaLoaderDescargar()
      loResp = goChalonaEcf.Enviar(tcControl)
    Endif
  Endif
  Return loResp
Endfunc

* chalonaSincronizaEstados() -> ChalonaResponse
Function chalonaSincronizaEstados
  If !_ChalonaLoaderInit()
    Return _ChalonaLoaderFail("fox_cliente.script_no_disponible")
  Endif
  Local loResp
  loResp = goChalonaEcf.SincronizarEstadosEnProceso()
  If _ChalonaLoaderEsVersionDesact(loResp)
    If _ChalonaLoaderDescargar()
      loResp = goChalonaEcf.SincronizarEstadosEnProceso()
    Endif
  Endif
  Return loResp
Endfunc

* chalonaDescargaDocumentosEcf(tcFechaDesde, tcFechaHasta [, tcTiposJson]) -> ChalonaResponse
Function chalonaDescargaDocumentosEcf
  Lparameters tcFechaDesde, tcFechaHasta, tcTiposJson
  If !_ChalonaLoaderInit()
    Return _ChalonaLoaderFail("fox_cliente.script_no_disponible")
  Endif
  Local loResp
  loResp = goChalonaEcf.DescargarDocumentos(tcFechaDesde, tcFechaHasta, tcTiposJson)
  If _ChalonaLoaderEsVersionDesact(loResp)
    If _ChalonaLoaderDescargar()
      loResp = goChalonaEcf.DescargarDocumentos(tcFechaDesde, tcFechaHasta, tcTiposJson)
    Endif
  Endif
  Return loResp
Endfunc

*------------------------------------------------------------
* Internals del loader
*------------------------------------------------------------

* Garantiza que goChalonaEcf este listo; retorna .T. si ya esta cargado
Function _ChalonaLoaderInit
  If Type("goChalonaEcf") = "O" And !Isnull(goChalonaEcf)
    Return .T.
  Endif
  Return _ChalonaLoaderDescargar()
Endfunc

* Descarga script, EXECSCRIPT retorna ChalonaEcf, guarda en goChalonaEcf
Function _ChalonaLoaderDescargar
  Local lcUrl, lcEntorno, lcReq, loHttp, lcRawBody
  Local liVersion, lcScriptEsc, lcScript, loEcf
  Public gcChalonaLoaderError
  gcChalonaLoaderError = ""

  lcUrl     = _ChalonaLoaderResolverUrl()
  lcEntorno = _ChalonaLoaderResolverEntorno()

  lcReq = '{"request":"fox_cliente_script","data":{"entorno":"' + lcEntorno + '"}}'

  loHttp = Createobject("MSXML2.XMLHTTP")
  loHttp.open("POST", lcUrl + "fox_cliente_script", .F.)
  loHttp.setRequestHeader("Content-Type", "application/json")
  Local llHttpOk
  llHttpOk = .T.
  TRY
    loHttp.send(lcReq)
  CATCH TO loEx
    gcChalonaLoaderError = "HTTP error: " + Transform(loEx.Message)
    llHttpOk = .F.
  ENDTRY
  If !llHttpOk
    Return .F.
  Endif
  lcRawBody = Nvl(loHttp.responseText, "")
  loHttp = .Null.

  If Empty(Alltrim(lcRawBody))
    gcChalonaLoaderError = "Respuesta vacía del servidor (" + lcUrl + ")"
    Return .F.
  Endif
  If Atc('"ok":true', lcRawBody) = 0
    gcChalonaLoaderError = "Servidor respondió ok=false: " + Left(lcRawBody, 200)
    Return .F.
  Endif

  lcScriptEsc = Strextract(lcRawBody, '"script":"', '","version":', 1, 0)
  liVersion   = Val(Alltrim(Strextract(lcRawBody, '"version":', '}', 1, 0)))

  If Empty(lcScriptEsc)
    gcChalonaLoaderError = "No se pudo extraer el script del JSON"
    Return .F.
  Endif
  If liVersion = 0
    gcChalonaLoaderError = "Versión inválida en respuesta"
    Return .F.
  Endif

  lcScript = _ChalonaLoaderUnescapeJson(lcScriptEsc)

  * Si ya habia un objeto cargado, sacar su .fxp de la lista antes de cargar el nuevo
  If Type("goChalonaEcf") = "O" And !Isnull(goChalonaEcf) And Pemstatus(goChalonaEcf, "source", 5)
    _ChalonaLoaderRemoverProcedure(goChalonaEcf.source)
    goChalonaEcf = .Null.
  Endif

  * Nombre unico en directorio temporal para evitar conflictos de concurrencia
  Local lcBase, loEcf
  lcBase = Addbs(Sys(2023)) + Sys(2015)
  Strtofile(lcScript, lcBase + ".prg")
  Compile (lcBase + ".prg")
  Set Procedure To (lcBase + ".fxp") Additive
  loEcf = Createobject("ChalonaEcf")

  If Vartype(loEcf) # "O"
    gcChalonaLoaderError = "Createobject('ChalonaEcf') falló tras compilar script"
    Return .F.
  Endif

  * Inyectar config si chalonaSetConfig() fue llamada antes
  If Type("goChalonaEcfCfg") = "O" And !Isnull(goChalonaEcfCfg) ;
      And Pemstatus(loEcf, "SetConfig", 5)
    loEcf.SetConfig(goChalonaEcfCfg)
  Endif

  AddProperty(loEcf, "source", lcBase + ".fxp")

  Public goChalonaEcf
  Public gcChalonaFoxVersion
  Public gcChalonaFoxEntorno
  goChalonaEcf        = loEcf
  gcChalonaFoxVersion = liVersion
  gcChalonaFoxEntorno = lcEntorno

  Return .T.
Endfunc

* Elimina un .fxp de la lista SET PROCEDURE y la reconstruye sin el
Function _ChalonaLoaderRemoverProcedure
  Lparameters lcOldFxp
  Local lcCurProc, lnCount, i, lcPath, llFirst
  Local Array laProcs[1]
  lcCurProc = Set("PROCEDURE")
  If Empty(Alltrim(lcCurProc))
    Return
  Endif
  lnCount = Alines(laProcs, lcCurProc, 5, ",")
  llFirst = .T.
  For i = 1 To lnCount
    lcPath = Alltrim(laProcs[i])
    If Empty(lcPath) Or Lower(lcPath) == Lower(Alltrim(lcOldFxp))
      Loop
    Endif
    If llFirst
      Set Procedure To (lcPath)
      llFirst = .F.
    Else
      Set Procedure To (lcPath) Additive
    Endif
  Endfor
  If llFirst
    Set Procedure To
  Endif
Endfunc

* Desescapa una cadena JSON: \n -> salto de linea, \" -> ", \\ -> \, etc.
Function _ChalonaLoaderUnescapeJson
  Lparameters tc
  Local lc
  lc = tc
  lc = Strtran(lc, '\\', Chr(1))
  lc = Strtran(lc, '\r\n', Chr(13)+Chr(10))
  lc = Strtran(lc, '\n', Chr(10))
  lc = Strtran(lc, '\r', Chr(13))
  lc = Strtran(lc, '\t', Chr(9))
  lc = Strtran(lc, '\"', '"')
  lc = Strtran(lc, '\/', '/')
  lc = Strtran(lc, Chr(1), '\')
  Return lc
Endfunc

Function _ChalonaLoaderEsVersionDesact
  Lparameters loResp
  If Vartype(loResp) # "O" Or loResp.ok
    Return .F.
  Endif
  * Checar mensaje crudo primero (servidor sin traduccion)
  If Alltrim(Nvl(loResp.message, "")) = "fox_cliente.version_desactualizada"
    Return .T.
  Endif
  * failCode pone el codigo crudo en data.errors[0].code aunque message venga traducido
  Return Atc('"fox_cliente.version_desactualizada"', Nvl(loResp.rawBody, "")) > 0
Endfunc

* Fallo rapido con ChalonaResponse minimo (sin depender del script descargado)
Function _ChalonaLoaderFail
  Lparameters tcMessage
  Local lo, lcMsg, lcDetalle
  lcMsg = Nvl(tcMessage, "fox_cliente.error")
  lcDetalle = ""
  If Type("gcChalonaLoaderError") = "C" And !Empty(Nvl(gcChalonaLoaderError, ""))
    lcDetalle = Chr(13)+Chr(10) + gcChalonaLoaderError
  Endif
  Messagebox(lcMsg + lcDetalle, 16, "Chalona ECF - Error al cargar script")
  lo = Createobject("Empty")
  AddProperty(lo, "ok", .F.)
  AddProperty(lo, "message", lcMsg)
  AddProperty(lo, "data", "")
  AddProperty(lo, "rawBody", "")
  Return lo
Endfunc

* URL hardcoded del servidor ECF cuando no hay cfg ni osis
#Define CHALONA_LOADER_URL_DEFAULT  "https://ecf-service.vicortiz.com/"

* Resuelve la URL base del servidor ECF.
* Prioridad: goChalonaEcfCfg.servidor_ecf -> osis.servidor_ecf -> hardcoded.
Function _ChalonaLoaderResolverUrl
  Local lcUrl
  lcUrl = ""
  If Type("goChalonaEcfCfg") = "O" And !Isnull(goChalonaEcfCfg) ;
      And Pemstatus(goChalonaEcfCfg, "servidor_ecf", 5)
    lcUrl = Alltrim(Nvl(goChalonaEcfCfg.servidor_ecf, ""))
  Endif
  If Empty(lcUrl) And Type("osis") = "O" And Pemstatus(osis, "servidor_ecf", 5)
    lcUrl = Alltrim(Nvl(osis.servidor_ecf, ""))
  Endif
  If Empty(lcUrl)
    lcUrl = CHALONA_LOADER_URL_DEFAULT
  Endif
  If Right(lcUrl, 1) # "/"
    lcUrl = lcUrl + "/"
  Endif
  Return lcUrl
Endfunc

* Detecta entorno (produccion|test).
* Prioridad: goChalonaEcfCfg.portal_dgii -> osis.portal_dgii -> "produccion".
Function _ChalonaLoaderResolverEntorno
  Local lcPortal
  lcPortal = ""
  If Type("goChalonaEcfCfg") = "O" And !Isnull(goChalonaEcfCfg) ;
      And Pemstatus(goChalonaEcfCfg, "portal_dgii", 5)
    lcPortal = Lower(Alltrim(Nvl(goChalonaEcfCfg.portal_dgii, "")))
  Endif
  If Empty(lcPortal) And Type("osis") = "O" And Pemstatus(osis, "portal_dgii", 5)
    lcPortal = Lower(Alltrim(Nvl(osis.portal_dgii, "")))
  Endif
  Return Iif(Atc("testecf", lcPortal) > 0 Or lcPortal = "test", "test", "produccion")
Endfunc

