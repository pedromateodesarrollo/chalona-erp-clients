*-----------------------------------------------------------------------------
* ChalonaEcfDriverSqlServer  (driver por defecto)
*
* Driver de datos para chalona-ecf.prg cuando el ERP corre sobre SQL Server
* y los e-CF se construyen desde dbo.imtr / dbo.gastos / dbo.imtrd, etc.
*
* CONTRATO (cualquier driver alternativo debe implementar estos mÃ©todos
* con la misma firma; VFP es duck-typed, no hace falta heredar).
*
* NOTA VFP: en LParameters, los parÃ¡metros omitidos llegan como .F. (no .Null.).
* Los mÃ©todos defienden con Vartype() al inicio antes de operar como string/lÃ³gico.
*
* Lecturas (retornan nombre de cursor; el motor selecciona y lee):
*   CargarMaestro(tcControl)               -> "curChalMae"
*       Cursor con cabecera del documento. Shape de dbo.imtr o dbo.gastos.
*       Si el control no existe: cursor vacÃ­o (Reccount=0) o "" si falla.
*   EsGastos(tcControl)                    -> .T./.F.
*       True cuando el maestro proviene de gastos (compras 41/43).
*   CargarDetalle(tcControl)               -> "curChalDet"
*       Cursor con lÃ­neas. Cols mÃ­nimas usadas por el motor:
*       cantidad, precio, descrip, mercs_nombre, mercs_servicio (0/1/2),
*       indicador_facturacion (opt), itbis_retenido (opt), isr_retenido (opt).
*       En gastos el motor sintetiza el detalle y NO llama esto.
*   CargarFiscalVence(tcTipoEcf)           -> "curChalFis"   (col: vence)
*   CargarEmpresa()                        -> "curChalEmp"   (rnc, nombre, direccion, iprecio)
*   CargarSuplidorRncNombre(tcCodigo)      -> "curChalSup"   (rnc, nombre)   * para gastos sin RNC
*   CargarTerceroExtranjero(tcCodigo, tlEsGastos) -> "curChalCli"
*       Ventas: extranjero_flag, rnc, nombre (de dbo.clientes).
*       Compras: solo extranjero_flag (de dbo.suplidor).
*   CargarReferenciaImtr(tcOcontrol)       -> "curChalRef"   (encf, fecha)
*
* Origen del control:
*   ContarOrigen(tcControl)                -> objeto Empty con .imtr (n) y .gastos (n)
*
* Sync respuesta envÃ­o (escritura):
*   GuardarRespuestaEnvio(tcControl, loData, tlEsGastos)        -> .T./.F.
*   MarcarErrorEnvio(tcControl, tcMensaje, tlEsGastos)          -> .T./.F.
*       loData = Vartype "O" con propiedades:
*         numero, estado, momento (ISO), estado_descripcion,
*         codigo_seguridad, fecha_firma, timbre, secuencia_utilizada (bool/0/1).
*       Persistencia: en gastos numero->ncf; en imtr numero->encf.
*
* Sync masivo de estados:
*   SyncIntentarLock()                     -> int (lock_result; <0 ya tomado)
*   SyncLiberarLock()
*   SyncListarPendientes()                 -> "curChalonaEncfEnProceso" (control, encf)
*   SyncListarDuplicados()                 -> "curChalDup" (control)
*
* Helpers requeridos en el ambiente (definidos en chalona-ecf.prg):
*   Request(tcSql [, tcAlias])
*   _ChalonaSqlQuote(tc), _ChalonaSqlQuoteN(tc), _ChalonaSqlNullableN(tc)
*   _ChalonaSecuenciaUtilizadaSqlBit(loData), ChalonaEcfUseInIfUsed(tcCur)
*   _ChalonaIsoSinZona(tc), _ChalonaIsoParaSqlDatetime(tc)
*   _ChalonaImtrAcotarRespuestaMensajes(tc), _ChalonaEcfMensajeErrorImtr(loResp)
*   ChalonaEcfLogError(tcMsg, tcControl, tcExtra)
*-----------------------------------------------------------------------------

Define Class ChalonaEcfDriverSqlServer As Custom

  *-------------------------------------------------------------------------
  * Maestro: imtr (ventas) o gastos (compras). Fallback automÃ¡tico.
  Function CargarMaestro
    Lparameters tcControl
    Local lcQ, lcSql
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    lcQ = _ChalonaSqlQuote(Alltrim(tcControl))
    ChalonaEcfUseInIfUsed("curChalMae")
    lcSql = "SELECT * FROM dbo.imtr WHERE control = " + lcQ
    If !Request(lcSql, "curChalMae")
      ChalonaEcfLogError("SQL: imtr (maestro)", tcControl, lcSql)
      Return ""
    Endif
    If Used("curChalMae") And Reccount("curChalMae") >= 1
      Return "curChalMae"
    Endif
    * Fallback gastos
    ChalonaEcfUseInIfUsed("curChalMae")
    lcSql = "SELECT * FROM dbo.gastos WHERE control = " + lcQ
    If !Request(lcSql, "curChalMae")
      ChalonaEcfLogError("SQL: gastos (maestro)", tcControl, lcSql)
      Return ""
    Endif
    Return "curChalMae"
  Endfunc

  *-------------------------------------------------------------------------
  * .T. si maestro vino de gastos. Llamar despuÃ©s de CargarMaestro.
  * Estrategia barata: contar en gastos con el mismo control.
  Function EsGastos
    Lparameters tcControl
    Local lcQ, lcSql, llRes
    llRes = .F.
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    lcQ = _ChalonaSqlQuote(Alltrim(tcControl))
    lcSql = "SELECT COUNT(1) AS c FROM dbo.gastos WHERE control = " + lcQ
    ChalonaEcfUseInIfUsed("curChalEsGastos")
    If Request(lcSql, "curChalEsGastos") And Used("curChalEsGastos") And Reccount("curChalEsGastos") > 0
      Select curChalEsGastos
      Go Top
      llRes = (0 + Nvl(c, 0)) > 0
    Endif
    ChalonaEcfUseInIfUsed("curChalEsGastos")
    Return llRes
  Endfunc

  *-------------------------------------------------------------------------
  * Detalle de imtr (ventas). En gastos el motor sintetiza, no llama esto.
  Function CargarDetalle
    Lparameters tcControl
    Local lcQ, lcSql
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    lcQ = _ChalonaSqlQuote(Alltrim(tcControl))
    ChalonaEcfUseInIfUsed("curChalDet")
    lcSql = "SELECT d.*, m.nombre AS mercs_nombre, ISNULL(m.servicio, 0) AS mercs_servicio " + ;
            "FROM dbo.imtrd d LEFT JOIN dbo.mercs m ON m.codigo = d.merc WHERE d.control = " + lcQ
    If !Request(lcSql, "curChalDet")
      ChalonaEcfLogError("SQL: imtrd+mercs (detalle)", tcControl, lcSql)
      Return ""
    Endif
    Return "curChalDet"
  Endfunc

  *-------------------------------------------------------------------------
  Function CargarFiscalVence
    Lparameters tcTipoEcf
    Local lcSql
    If Vartype(tcTipoEcf) # "C"
      tcTipoEcf = ""
    Endif
    ChalonaEcfUseInIfUsed("curChalFis")
    lcSql = "SELECT TOP 1 vence FROM dbo.fiscal WHERE codigo = " + _ChalonaSqlQuote(Alltrim(tcTipoEcf))
    If !Request(lcSql, "curChalFis")
      ChalonaEcfLogError("SQL: fiscal (vencimiento)", tcTipoEcf, lcSql)
      Return ""
    Endif
    Return "curChalFis"
  Endfunc

  *-------------------------------------------------------------------------
  Function CargarEmpresa
    Local lcSql
    ChalonaEcfUseInIfUsed("curChalEmp")
    lcSql = "SELECT TOP 1 rnc, nombre, direccion, iprecio FROM dbo.empresa"
    If !Request(lcSql, "curChalEmp")
      ChalonaEcfLogError("SQL: empresa (emisor)", "", lcSql)
      Return ""
    Endif
    Return "curChalEmp"
  Endfunc

  *-------------------------------------------------------------------------
  * Para gastos sin RNC en maestro: completarlo desde dbo.suplidor.
  Function CargarSuplidorRncNombre
    Lparameters tcCodigo
    Local lcSql
    If Vartype(tcCodigo) # "C"
      tcCodigo = ""
    Endif
    ChalonaEcfUseInIfUsed("curChalSup")
    lcSql = "SELECT TOP 1 rnc, nombre FROM dbo.suplidor WHERE codigo = " + _ChalonaSqlQuote(Alltrim(tcCodigo))
    If !Request(lcSql, "curChalSup")
      ChalonaEcfLogError("SQL: suplidor (rnc/nombre)", tcCodigo, lcSql)
      Return ""
    Endif
    Return "curChalSup"
  Endfunc

  *-------------------------------------------------------------------------
  * Tercero (cliente o suplidor) para flag de extranjero.
  *   tlEsGastos = .T. -> dbo.suplidor (solo extranjero_flag)
  *   tlEsGastos = .F. -> dbo.clientes (extranjero_flag, rnc, nombre)
  Function CargarTerceroExtranjero
    Lparameters tcCodigo, tlEsGastos
    Local lcSql, lcCod
    If Vartype(tcCodigo) # "C"
      tcCodigo = ""
    Endif
    If Vartype(tlEsGastos) # "L"
      tlEsGastos = .F.
    Endif
    lcCod = _ChalonaSqlQuote(Alltrim(tcCodigo))
    ChalonaEcfUseInIfUsed("curChalCli")
    If tlEsGastos
      lcSql = "SELECT TOP 1 ISNULL(extranjero, 0) AS extranjero_flag FROM dbo.suplidor WHERE codigo = " + lcCod
    Else
      lcSql = "SELECT TOP 1 ISNULL(extranjero, 0) AS extranjero_flag, rnc, nombre FROM dbo.clientes WHERE codigo = " + lcCod
    Endif
    If !Request(lcSql, "curChalCli")
      ChalonaEcfLogError("SQL: tercero (extranjero)", tcCodigo, lcSql)
      Return ""
    Endif
    Return "curChalCli"
  Endfunc

  *-------------------------------------------------------------------------
  * Lookup del NCF referenciado en imtr (para CodigoModificacion NC/ND).
  Function CargarReferenciaImtr
    Lparameters tcOcontrol
    Local lcSql
    If Vartype(tcOcontrol) # "C"
      tcOcontrol = ""
    Endif
    ChalonaEcfUseInIfUsed("curChalRef")
    lcSql = "SELECT TOP 1 encf, fecha FROM dbo.imtr WHERE control = " + _ChalonaSqlQuote(Alltrim(tcOcontrol))
    If !Request(lcSql, "curChalRef")
      ChalonaEcfLogError("SQL: imtr (referencia)", tcOcontrol, lcSql)
      Return ""
    Endif
    Return "curChalRef"
  Endfunc

  *-------------------------------------------------------------------------
  * Origen del control: cuÃ¡ntas filas existen en imtr y gastos.
  Function ContarOrigen
    Lparameters tcControl
    Local lcQ, lcSql, loRes
    loRes = Createobject("Empty")
    AddProperty(loRes, "imtr", 0)
    AddProperty(loRes, "gastos", 0)
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    lcQ = _ChalonaSqlQuote(Alltrim(tcControl))
    ChalonaEcfUseInIfUsed("curChalDocOrigen")
    lcSql = "SELECT " + ;
            "  (SELECT COUNT(1) FROM dbo.imtr WHERE control = " + lcQ + ") AS c_imtr, " + ;
            "  (SELECT COUNT(1) FROM dbo.gastos WHERE control = " + lcQ + ") AS c_gastos;"
    If !Request(lcSql, "curChalDocOrigen")
      ChalonaEcfLogError("SQL: doc origen (imtr/gastos)", tcControl, lcSql)
      ChalonaEcfUseInIfUsed("curChalDocOrigen")
      Return loRes
    Endif
    If Used("curChalDocOrigen") And Reccount("curChalDocOrigen") > 0
      Select curChalDocOrigen
      Go Top
      loRes.imtr = 0 + Nvl(c_imtr, 0)
      loRes.gastos = 0 + Nvl(c_gastos, 0)
    Endif
    ChalonaEcfUseInIfUsed("curChalDocOrigen")
    Return loRes
  Endfunc

  *-------------------------------------------------------------------------
  * Persistir respuesta exitosa de DGII en imtr o gastos.
  Function GuardarRespuestaEnvio
    Lparameters tcControl, loData, tlEsGastos
    Local lcExec, lcNumero, lcEstado, lcMoment, lcMsg, lcCod, lcFf, lcTimb, lcSecBit
    Local llOk, lcCol, lcTabla, lcMomCol, lnLargoMsg

    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    If Vartype(tlEsGastos) # "L"
      tlEsGastos = .F.
    Endif
    If Empty(tcControl) Or Vartype(loData) # "O"
      Return .F.
    Endif

    lcNumero = ""
    If PemStatus(loData, "numero", 5)
      lcNumero = Alltrim(Transform(loData.numero))
    Endif
    If Empty(lcNumero)
      Return .F.
    Endif

    lcEstado = ""
    If PemStatus(loData, "estado", 5)
      lcEstado = Alltrim(Transform(loData.estado))
    Endif
    If Empty(lcEstado) And PemStatus(loData, "estado_descripcion", 5)
      lcEstado = Alltrim(Transform(loData.estado_descripcion))
    Endif
    If Len(lcEstado) > 200
      lcEstado = Left(lcEstado, 200)
    Endif

    lcMoment = ""
    If PemStatus(loData, "momento", 5)
      lcMoment = Alltrim(Transform(loData.momento))
    Endif
    lcMoment = _ChalonaIsoSinZona(lcMoment)
    lcMoment = _ChalonaIsoParaSqlDatetime(lcMoment)
    If Len(lcMoment) > 100
      lcMoment = Left(lcMoment, 100)
    Endif
    lcMoment = Left(lcMoment, 19)

    lcMsg = ""
    If PemStatus(loData, "estado_descripcion", 5)
      lcMsg = Alltrim(Transform(loData.estado_descripcion))
    Endif
    lcMsg = _ChalonaImtrAcotarRespuestaMensajes(lcMsg)

    lcCod = ""
    If PemStatus(loData, "codigo_seguridad", 5)
      lcCod = Alltrim(Transform(loData.codigo_seguridad))
    Endif
    If Len(lcCod) > 200
      lcCod = Left(lcCod, 200)
    Endif

    lcFf = ""
    If PemStatus(loData, "fecha_firma", 5)
      lcFf = Alltrim(Transform(loData.fecha_firma))
    Endif
    If Len(lcFf) > 100
      lcFf = Left(lcFf, 100)
    Endif

    lcTimb = ""
    If PemStatus(loData, "timbre", 5)
      lcTimb = Alltrim(Transform(loData.timbre))
    Endif

    lcSecBit = _ChalonaSecuenciaUtilizadaSqlBit(loData)

    If tlEsGastos
      lcTabla = "dbo.gastos"
      lcCol   = "ncf"
      lcMomCol = "_updated"
      lnLargoMsg = 250
    Else
      lcTabla = "dbo.imtr"
      lcCol   = "encf"
      lcMomCol = "respuesta_fechaRecepcion"
      lnLargoMsg = 254
    Endif

    lcExec = "UPDATE " + lcTabla + " SET " + ;
      lcCol + " = CASE " + ;
      "  WHEN NULLIF(LTRIM(RTRIM(" + _ChalonaSqlQuoteN(lcNumero) + ")), N'') IS NOT NULL " + ;
      "  THEN LTRIM(RTRIM(" + _ChalonaSqlQuoteN(lcNumero) + ")) " + ;
      "  ELSE " + lcCol + " END, " + ;
      "respuesta_estado = " + _ChalonaSqlNullableN(lcEstado) + ", " + ;
      "respuesta_secuenciaUtilizada = " + lcSecBit + ", " + ;
      "respuesta_mensajes = CASE " + ;
      "  WHEN " + _ChalonaSqlNullableN(lcMsg) + " IS NULL THEN NULL " + ;
      "  ELSE LEFT(LTRIM(RTRIM(" + _ChalonaSqlNullableN(lcMsg) + ")), " + Transform(lnLargoMsg) + ") END, " + ;
      "respuesta_codigo_seguridad = NULLIF(LTRIM(RTRIM(" + _ChalonaSqlNullableN(lcCod) + ")), N''), " + ;
      "respuesta_timbre = " + _ChalonaSqlNullableN(lcTimb) + ", " + ;
      "respuesta_fecha_firma = " + _ChalonaSqlNullableN(lcFf) + ", " + ;
      lcMomCol + " = CASE " + ;
      "  WHEN " + _ChalonaSqlNullableN(lcMoment) + " IS NULL THEN " + lcMomCol + " " + ;
      "  WHEN ISDATE(" + _ChalonaSqlNullableN(lcMoment) + ") = 0 THEN " + lcMomCol + " " + ;
      "  ELSE CONVERT(datetime, " + _ChalonaSqlNullableN(lcMoment) + ", 120) END " + ;
      "WHERE control = " + _ChalonaSqlQuote(tcControl)

    llOk = Request(lcExec)
    If !llOk
      ChalonaEcfLogError("SQL: " + lcTabla + " UPDATE (sync respuesta)", tcControl, lcExec)
    Endif
    Return llOk
  Endfunc

  *-------------------------------------------------------------------------
  * Marcar error de envio (solo respuesta_mensajes).
  Function MarcarErrorEnvio
    Lparameters tcControl, tcMensaje, tlEsGastos
    Local lcExec, llOk, lcTabla, lnLargoMsg
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    If Vartype(tcMensaje) # "C"
      tcMensaje = ""
    Endif
    If Vartype(tlEsGastos) # "L"
      tlEsGastos = .F.
    Endif
    If Empty(tcControl) Or Empty(Alltrim(tcMensaje))
      Return .F.
    Endif
    If tlEsGastos
      lcTabla = "dbo.gastos"
      lnLargoMsg = 250
    Else
      lcTabla = "dbo.imtr"
      lnLargoMsg = 254
    Endif
    lcExec = "UPDATE " + lcTabla + " SET respuesta_mensajes = " + ;
      "CASE " + ;
      "  WHEN " + _ChalonaSqlNullableN(tcMensaje) + " IS NULL THEN NULL " + ;
      "  ELSE LEFT(LTRIM(RTRIM(" + _ChalonaSqlNullableN(tcMensaje) + ")), " + Transform(lnLargoMsg) + ") END " + ;
      "WHERE control = " + _ChalonaSqlQuote(tcControl)
    llOk = Request(lcExec)
    If !llOk
      ChalonaEcfLogError("SQL: " + lcTabla + " UPDATE (marca error)", tcControl, lcExec)
    Endif
    Return llOk
  Endfunc

  *-------------------------------------------------------------------------
  * Mutex de sincronizaciÃ³n masiva (sp_getapplock).
  Function SyncIntentarLock
    Local lcMutexCur, lnLockRes
    lcMutexCur = "curChalonaMutex"
    lnLockRes = -99
    ChalonaEcfUseInIfUsed(lcMutexCur)
    If !Request( ;
        "DECLARE @r int; " + ;
        "EXEC @r = sp_getapplock " + ;
        "  @Resource = N'ChalonaEcf_SincronizarEstadosEnProceso', " + ;
        "  @LockMode = N'Exclusive', " + ;
        "  @LockOwner = N'Session', " + ;
        "  @LockTimeout = 0; " + ;
        "SELECT CAST(@r AS int) AS lock_result;", ;
        lcMutexCur)
      Return -99
    Endif
    If Used(lcMutexCur) And Reccount(lcMutexCur) > 0
      Select (lcMutexCur)
      lnLockRes = 0 + lock_result
    Endif
    ChalonaEcfUseInIfUsed(lcMutexCur)
    Return lnLockRes
  Endfunc

  Procedure SyncLiberarLock
    Request( ;
        "EXEC sp_releaseapplock " + ;
        "  @Resource = N'ChalonaEcf_SincronizarEstadosEnProceso', " + ;
        "  @LockOwner = N'Session';")
  Endproc

  *-------------------------------------------------------------------------
  Function SyncListarPendientes
    Local lcCur
    lcCur = "curChalonaEncfEnProceso"
    ChalonaEcfUseInIfUsed(lcCur)
    If !Request( ;
        "SELECT " + ;
        "  LTRIM(RTRIM(i.control)) AS control, " + ;
        "  LTRIM(RTRIM(i.encf)) AS encf " + ;
        "FROM dbo.imtr AS i " + ;
        "WHERE LOWER(LTRIM(RTRIM(ISNULL(i.respuesta_estado, N'')))) = N'en proceso' " + ;
        "  AND NULLIF(LTRIM(RTRIM(i.encf)), N'') IS NOT NULL " + ;
        "UNION ALL " + ;
        "SELECT " + ;
        "  LTRIM(RTRIM(g.control)) AS control, " + ;
        "  LTRIM(RTRIM(g.ncf)) AS encf " + ;
        "FROM dbo.gastos AS g " + ;
        "WHERE LOWER(LTRIM(RTRIM(ISNULL(g.respuesta_estado, N'')))) = N'en proceso' " + ;
        "  AND NULLIF(LTRIM(RTRIM(g.ncf)), N'') IS NOT NULL;", ;
        lcCur)
      Return ""
    Endif
    Return lcCur
  Endfunc

  *-------------------------------------------------------------------------
  Function SyncListarDuplicados
    Local lcCur
    lcCur = "curChalDup"
    ChalonaEcfUseInIfUsed(lcCur)
    If !Request( ;
        "SELECT t.control " + ;
        "FROM (" + ;
        "  SELECT LTRIM(RTRIM(i.control)) AS control FROM dbo.imtr AS i " + ;
        "  WHERE LOWER(LTRIM(RTRIM(ISNULL(i.respuesta_estado, N'')))) = N'en proceso' " + ;
        "    AND NULLIF(LTRIM(RTRIM(i.encf)), N'') IS NOT NULL " + ;
        "  UNION ALL " + ;
        "  SELECT LTRIM(RTRIM(g.control)) AS control FROM dbo.gastos AS g " + ;
        "  WHERE LOWER(LTRIM(RTRIM(ISNULL(g.respuesta_estado, N'')))) = N'en proceso' " + ;
        "    AND NULLIF(LTRIM(RTRIM(g.ncf)), N'') IS NOT NULL " + ;
        ") AS t " + ;
        "GROUP BY t.control " + ;
        "HAVING COUNT(1) > 1;", ;
        lcCur)
      Return ""
    Endif
    Return lcCur
  Endfunc

EndDefine
