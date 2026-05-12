

*------------------------------------------------------------
* Chalona ECF en FoxPro (modulo integrado en el ERP).
* SQL Server estandar (dbo.imtr / dbo.gastos / dbo.imtrd / dbo.empresa /
*   dbo.suplidor / dbo.clientes / dbo.fiscal / dbo.mercs): logica embebida en
*   los metodos privados _Cargar*, _Guardar*, _Sync* de la clase ChalonaEcf.
*   Integrador SQL Server estandar usa goChalonaEcf.Enviar(ctrl) tal cual.
* Otros origenes (DBF, otro esquema, etc.): integrador llama
*   goChalonaEcf.CrearCursores() + llena cursores + EnviarDesdeCursores(ctrl)
*   o SincronizarDesdeCursor(). Ver SCHEMA-CURSORES.md.
* Config: motor agnostico - opera contra un objeto loCfg con servidor_ecf,
*   usuario_sync, pass_sync, portal_dgii, dgii_multimoneda. Inyectable via
*   loEcf.SetConfig(loCfg). Default: ChalonaEcfConfigDesdeOsis() lee Public osis.
* JSON DGII armado en Fox, sistema_login, envia_ecf / consulta_estado.
* Sincronizar estados en proceso: lock SQL Server sp_getapplock; otra
*   instancia activa => ok=.T., omitido_por_mutex.
* Este archivo se sirve desde el servidor via HTTP (POST /fox_cliente_script)
* y lo carga chalona-ecf-loader.prg: el loader instancia ChalonaEcf
* (goChalonaEcf) y expone las funciones top-level chalonaEnviaEcf /
* chalonaSincronizaEstados / chalonaDescargaDocumentosEcf.
*------------------------------------------------------------

*------------------------------------------------------------
* JSON e-CF (DGII): mismo contrato que dbo.ecf2json, armado en Fox para SQL Server
* sin funciones escalares ni FOR JSON (compatibilidad con motores viejos / ediciones limitadas).
*------------------------------------------------------------

Procedure ChalonaEcfUseInIfUsed
  Lparameters tcAlias
  If Used(tcAlias)
    Use In (tcAlias)
  Endif
Endproc

* Variable publica opcional para suprimir Messagebox + form de error de envio.
* Util para debugging desde una sesion automatizada (Claude / scripts) que no
* puede atender popups. Por defecto ausente -> UI normal. Setear:
*   PUBLIC glChalonaEcfSilenciarUi
*   glChalonaEcfSilenciarUi = .T.
Function _ChalonaEcfUiSilenciada
  Return Type("glChalonaEcfSilenciarUi") = "L" And glChalonaEcfSilenciarUi
Endfunc

Procedure ChalonaEcfCleanupCursorsImtrJson
  ChalonaEcfUseInIfUsed("curChalMae")
  ChalonaEcfUseInIfUsed("curChalDet")
  ChalonaEcfUseInIfUsed("curChalFis")
  ChalonaEcfUseInIfUsed("curChalEmp")
  ChalonaEcfUseInIfUsed("curChalCli")
  ChalonaEcfUseInIfUsed("curChalRef")
Endproc

Function _ChalonaEcfNormalizeTexto
  Lparameters tc
  Local lc
  lc = Nvl(tc, "")
  If Vartype(lc) # "C"
    lc = Transform(lc)
  Endif
  If Empty(lc)
    Return ""
  Endif
  lc = Strtran(lc, Chr(13) + Chr(10), " ")
  lc = Strtran(lc, Chr(13), " ")
  lc = Strtran(lc, Chr(10), " ")
  lc = Strtran(lc, Chr(9), " ")
  * Comillas tipogrÃ¡ficas (Windows-1252): evitar CHR(>255) en VFP
  lc = Strtran(lc, Chr(147), '"') && â€œ
  lc = Strtran(lc, Chr(148), '"') && ï¿½?
  lc = Strtran(lc, Chr(146), "'") && â€™
  Return lc
Endfunc


* Hooks de log (integrado: sin escritura a disco; el ERP puede reemplazar estas funciones).
Function ChalonaEcfLogError
  Lparameters tcStep, tcControl, tcSql
  Return
Endfunc

Function ChalonaEcfLogException
  Lparameters tcStep, tcControl, toEx, tcExtra
  Local lcMsg, lcProc, lcLine, lcDetails, lcAll
  lcMsg = ""
  lcProc = ""
  lcLine = ""
  lcDetails = ""
  Try
    If Vartype(toEx) = "O"
      If PemStatus(toEx, "Message", 5)
        lcMsg = Transform(toEx.Message)
      Endif
      If PemStatus(toEx, "Procedure", 5)
        lcProc = Transform(toEx.Procedure)
      Endif
      If PemStatus(toEx, "LineNo", 5)
        lcLine = Transform(toEx.LineNo)
      Endif
      If PemStatus(toEx, "Details", 5)
        lcDetails = Transform(toEx.Details)
      Endif
    Endif
  Catch
  Endtry
  lcAll = "Step=" + Transform(Nvl(tcStep, "")) + ;
    "; Control=" + Transform(Nvl(tcControl, "")) + ;
    "; Proc=" + lcProc + ;
    "; Line=" + lcLine + ;
    "; Msg=" + lcMsg + ;
    Iif(Empty(Alltrim(Nvl(tcExtra, ""))), "", "; Extra=" + Transform(tcExtra)) + ;
    Iif(Empty(Alltrim(Nvl(lcDetails, ""))), "", "; Details=" + lcDetails)
  Public gcChalonaEcfLastException
  gcChalonaEcfLastException = lcAll
  Return
Endfunc

Function ChalonaEcfSaveUltimoJson
  Lparameters tcControl, tcJson
  Return
Endfunc

Function _ChalonaEcfLimpiaCadenaNumerica
  Lparameters tc
  Local lc, i, ln
  Local loEx, lcOut

  lc = Nvl(tc, "")
  If Vartype(lc) # "C"
    lc = Transform(lc)
  Endif
  lc = Alltrim(lc)
  If Empty(lc)
    Return ""
  Endif

  * En VFP, CHR() solo soporta 0..255. Evitar CHR(>255) para no lanzar error no manejado.
  * Limpiamos lo que tÃ­picamente llega en nÃºmeros desde ODBC: NBSP (160), TAB (9) y espacios.
  lcOut = lc
  Try
    lcOut = Strtran(lcOut, Chr(160), "")
    lcOut = Strtran(lcOut, Chr(9), "")
    lcOut = Strtran(lcOut, " ", "")
  Catch To loEx
    ChalonaEcfLogException("UNHANDLED: _ChalonaEcfLimpiaCadenaNumerica", "", loEx, "")
    lcOut = lc
  Endtry

  Return lcOut
Endfunc

Function _ChalonaEcfStrToDecimal
  Lparameters tc
  Local lc
  lc = _ChalonaEcfLimpiaCadenaNumerica(Transform(Nvl(tc, "")))
  If Empty(lc) Or !IsNumeric(lc)
    Return 0
  Endif
  Return Val(lc)
Endfunc

Function _ChalonaEcfNzNum
  Lparameters tu
  Do Case
  Case Vartype(tu) = "N"
    Return tu
  Case Vartype(tu) = "L"
    Return Iif(tu, 1, 0)
  Case Vartype(tu) = "C"
    Return Val(Alltrim(tu))
  Otherwise
    Return 0
  Endcase
Endfunc

Function _ChalonaEcfFmtDdMmYy
  Lparameters td
  Local ld
  If Type("td") = "U" Or Isnull(td)
    Return ""
  Endif
  Do Case
  Case Vartype(td) = "D"
    ld = td
  Case Vartype(td) = "T"
    ld = Ttod(td)
  Case Vartype(td) = "C"
    ld = Ctod(Alltrim(td))
  Otherwise
    Return ""
  Endcase
  If Empty(ld)
    Return ""
  Endif
  Return Padl(Day(ld), 2, "0") + "-" + Padl(Month(ld), 2, "0") + "-" + Transform(Year(ld))
Endfunc

Function _ChalonaEcfJsonNum
  Lparameters tn, lnDec
  Return Ltrim(Str(Round(_ChalonaEcfNzNum(tn), lnDec), 24, lnDec))
Endfunc

* RNC (9 digitos) o cedula (11): valida digito verificador.
* Si no encaja o d�gito inv�lido ? IdentificadorExtranjero (ej. pasaporte, RNC extranjero).
Function _ChalonaEcfEsIdentificadorFiscalRD
  Lparameters tcId
  Local lc, lcDig, i, ln, ch, lnSum, lnPeso, lnN, lnEsp
  lc = Alltrim(Nvl(tcId, ""))
  If Empty(lc)
    Return .F.
  Endif
  lcDig = ""
  For i = 1 To Len(lc)
    ch = Substr(lc, i, 1)
    If ch >= "0" And ch <= "9"
      lcDig = lcDig + ch
    Endif
  Endfor
  ln = Len(lcDig)
  Do Case
  Case ln = 9
    * RNC empresarial: pesos 7,9,8,6,5,4,3,2 sobre los primeros 8 d�gitos.
    * d�gito esperado = (10 - (suma % 11)) % 9 + 1
    lnSum = 0
    lnSum = lnSum + Val(Substr(lcDig,1,1)) * 7
    lnSum = lnSum + Val(Substr(lcDig,2,1)) * 9
    lnSum = lnSum + Val(Substr(lcDig,3,1)) * 8
    lnSum = lnSum + Val(Substr(lcDig,4,1)) * 6
    lnSum = lnSum + Val(Substr(lcDig,5,1)) * 5
    lnSum = lnSum + Val(Substr(lcDig,6,1)) * 4
    lnSum = lnSum + Val(Substr(lcDig,7,1)) * 3
    lnSum = lnSum + Val(Substr(lcDig,8,1)) * 2
    lnEsp = Mod(10 - Mod(lnSum, 11), 9) + 1
    Return (lnEsp = Val(Substr(lcDig,9,1)))
  Case ln = 11
    * C�dula JCE: pesos alternados 1,2 sobre los primeros 10 d�gitos.
    * Si producto > 9 restar 9. d�gito esperado = (10 - (suma % 10)) % 10
    lnSum = 0
    For i = 1 To 10
      lnPeso = Iif(Mod(i, 2) = 1, 1, 2)
      lnN = Val(Substr(lcDig, i, 1)) * lnPeso
      If lnN > 9
        lnN = lnN - 9
      Endif
      lnSum = lnSum + lnN
    Endfor
    lnEsp = Mod(10 - Mod(lnSum, 10), 10)
    Return (lnEsp = Val(Substr(lcDig,11,1)))
  Otherwise
    Return .F.
  Endcase
Endfunc

* Retorno: .Null. = fallo SQL; "" = sin fila imtr; cadena = JSON raiz listo para envia_ecf.
Function ChalonaEcfBuildDocJsonFox
  Lparameters tcControl, toCfg
  * Lee los cursores curChal* (que deben estar pre-poblados, ya sea via
  * Enviar(ctrl) -> _PoblarCursoresDesdeImtr (path SQL Server) o via el
  * integrador llamando CrearCursores + INSERT INTO directo).
  * No hace Request() — esta funcion es puro armado de JSON desde cursores.
  * toCfg: objeto de configuración (ChalonaEcfCfgProp). Si no llega, se asume
  * que las flags como dgii_multimoneda están vacías.
  Local lcQ, lcSql, lcJson, lnTotalBruto, lnLn, lcDet, lcSep
  Local lcTipoeCF, lcEncf, ldFecEmi, lnDiasCr, lnValor, lnDescMae, lnItbis, lnTotal
  Local lcMaeRnc, lcMaeNombre, lcEntidad, lcOcontrol
  Local ldFecVen, lcFecVen, lcEmpRnc, lcEmpNom, lcEmpDir, lnExtranjero
  Local lcRefEncf, ldRefFec, lcInfRef, lcIdDoc, lcEmisor, lcComp, lcTot
  Local lnP, lnC, lnBruto, lnDescLin, lnMontoItem, lcNomItem, lcDescItem, lnIndBS
  Local lcSubDesc, lcFLP, lnTipoPago, lnItbis1
  Local loEx
  Local lcOut, llNull, llCorrigeTexto, lnCodMod, llOmitirRef
  Local lnIprecio, lnIndicadorMontoGravado, lnFactorIprecio
  Local lnTipoEcf, lnBaseGrav, lnIndFact, lnIndFactLin, lnDiasNcRef, lcIndicadorNotaCredito, lnTolerancia, lnItbisEsperado, llDetTieneItbis, lnItbisLineaVal
  Local lnPropina, lnPropinaOM
  Local lnSumGravadoI1, lnSumExento, lnSumItbisI1, lnSumGravadoI3, lnSumTotalDet, lnItbisLin
  Local lnSumGravadoI1OM, lnSumExentoOM, lnSumItbisI1OM, lnSumGravadoI3OM
  Local lnGravI1Final, lnItbisI1Final, lnTotalFinal
  * Con IndicadorMontoGravado=1: totales de cabecera alineados a la suma del detalle (ITBIS incluido en lÃ­nea).
  Local lnSumMontoItems, lnFactorItbis
  * Factor imtr.tasa: multiplicador >= 1 (1 = sin cambio). Precios, lÃ­neas y totales DGII.
  Local lnTasaFactor
  * Multimoneda DGII: si Cfg.dgii_multimoneda="T", imtr.moneda es divisa extranjera (no DOP/RD/RD$/PESO)
  * y la tasa > 1, se envÃ­a el bloque OtraMoneda con los montos en moneda extranjera; los Totales DGII
  * siguen en DOP (montoÃ—tasa). Si dgii_multimoneda=.F., moneda local/vacÃ­a o tasa=1, comportamiento
  * legacy (todo Ã— tasa, sin OtraMoneda). DGII rechaza TipoMoneda="RD" (11204): el XSD sÃ³lo enumera divisas.
  Local llMultiMoneda, lcMoneda
  Local lnValorOM, lnDescMaeOM, lnItbisOM, lnTotalOM, lnItbisRetOM, lnIsrOM
  Local lnBaseGravOM, lnSumMontoItemsOM, lcOtraMoneda
  Local lnBaseGravO, lnItbisO, lnTotalO
  Local lcDetOM, lnPOM, lnDescLinOM, lnMontoItemOM, lnBrutoOM, lnDescLinOMloc
  * Origen del documento: imtr (ventas) o gastos (compras). En gastos el eNCF vive en ncf y no hay detalle.
  Local llEsGastos
  * Para gastos: id de suplidor (para extranjero) y texto para item sintÃ©tico.
  Local lcSuplidorId, lcItemTxt, lnBaseSinItbis
  Local lnItbisRet, lnIsr, lcRetencion41, lnPos, lcInsRet
  * Campos de texto de gastos capturados desde el maestro (evita depender del SELECT activo).
  Local lcGastoComentario, lcGastoReferencia, lcGastoDoc, lcGastoNumero
  * Para reportar al llamador el motivo del .Null. (los hooks de log pueden estar vacíos).
  Local lcBuildErr

  lcOut = ""
  llNull = .F.
  llEsGastos = .F.
  lcBuildErr = ""
  Public gcChalonaEcfBuildDocError
  gcChalonaEcfBuildDocError = ""
  lcGastoComentario = ""
  lcGastoReferencia = ""
  lcGastoDoc = ""
  lcGastoNumero = ""

  Try
    Do While .T.
      tcControl = Alltrim(Nvl(tcControl, ""))
      If Empty(tcControl)
        lcOut = ""
        Exit
      Endif
      lcQ = _ChalonaSqlQuote(tcControl)

      * Cursores deben estar pre-poblados. Si curChalMae vacio, abortar.
      If !Used("curChalMae") Or Reccount("curChalMae") < 1
        lcOut = ""
        Exit
      Endif
      Select curChalMae
      Go Top
      * Origen: derivado del fiscal (41/43 = gastos).
      llEsGastos = Inlist(Int(Val(Alltrim(Transform(Nvl(fiscal, ""))))), 41, 43)

  Select curChalMae
  Go Top
  lcTipoeCF = Alltrim(Transform(fiscal))
  * Compras (gastos): solo se permiten tipos 41 y 43.
  If llEsGastos And !Inlist(Int(Val(lcTipoeCF)), 41, 43)
    ChalonaEcfLogError("ECF: gastos solo permite TipoeCF 41/43 (viene " + lcTipoeCF + ")", tcControl, "")
    gcChalonaEcfBuildDocError = "ecf.gastos.tipo_no_permitido"
    llNull = .T.
    Exit
  Endif
  If llEsGastos
    lcEncf = Alltrim(Transform(Nvl(ncf, "")))
    * Capturar textos del maestro de gastos para el item sintÃ©tico (sin depender del área seleccionada luego).
    If Type("curChalMae.comentario") # "U"
      lcGastoComentario = Alltrim(Transform(Nvl(comentario, "")))
    Endif
    If Type("curChalMae.referencia") # "U"
      lcGastoReferencia = Alltrim(Transform(Nvl(referencia, "")))
    Endif
    If Type("curChalMae.doc") # "U"
      lcGastoDoc = Alltrim(Transform(Nvl(doc, "")))
    Endif
    If Type("curChalMae.numero") # "U"
      lcGastoNumero = Alltrim(Transform(Nvl(numero, "")))
    Endif
  Else
    lcEncf = Alltrim(Transform(Nvl(encf, "")))
  Endif
  * Validar prefijo eNCF coincide con TipoeCF (DGII error 75).
  * eNCF debe comenzar con "E" + TipoeCF (ej: TipoeCF=32 → E32...).
  If !Empty(lcEncf) And !Empty(lcTipoeCF)
    If Left(lcEncf, 1 + Len(Alltrim(lcTipoeCF))) # "E" + Alltrim(lcTipoeCF)
      ChalonaEcfLogError("ECF: eNCF '" + lcEncf + "' no coincide con TipoeCF " + lcTipoeCF + " (prefijo esperado: E" + Alltrim(lcTipoeCF) + "). DGII error 75.", tcControl, "")
      gcChalonaEcfBuildDocError = "ecf.encf_tipo_no_coincide"
      llNull = .T.
      Exit
    Endif
  Endif
  ldFecEmi = fecha
  lnDiasCr = _ChalonaEcfNzNum(diascr)
  lnValor = _ChalonaEcfNzNum(valor)
  lnDescMae = _ChalonaEcfNzNum(descuento)
  lnItbis = _ChalonaEcfNzNum(itbis)
  lnTotal = _ChalonaEcfNzNum(total)
  * tasa en imtr: factor multiplicativo sobre montos (>=1; 1=sin cambio). Si falta o <1 -> 1.
  lnTasaFactor = 1
  If Type("tasa") != "U"
    lnTasaFactor = _ChalonaEcfNzNum(tasa)
  Endif
  If lnTasaFactor < 1
    lnTasaFactor = 1
  Endif
  * Multimoneda DGII: requiere Cfg.dgii_multimoneda="T" AND imtr.moneda no vacía y distinta del peso local.
  * Captura los montos crudos (ya en moneda extranjera) ANTES de multiplicar por la tasa: van en OtraMoneda.
  * Aliases del peso dominicano que NUNCA disparan multimoneda (DGII no acepta TipoMoneda local en OtraMoneda).
  lcMoneda = ""
  If Type("moneda") != "U"
    lcMoneda = Upper(Alltrim(Transform(Nvl(moneda, ""))))
  Endif
  llMultiMoneda = .F.
  If Upper(Alltrim(ChalonaEcfCfgProp("dgii_multimoneda", toCfg))) == "T" ;
      And !Empty(lcMoneda) ;
      And !Inlist(lcMoneda, "DOP", "RD", "RD$", "PESO", "PESOS", "PESO DOMINICANO") ;
      And lnTasaFactor > 1
    llMultiMoneda = .T.
  Endif
  lnValorOM = Round(lnValor, 2)
  lnDescMaeOM = Round(lnDescMae, 2)
  lnItbisOM = Round(lnItbis, 2)
  lnTotalOM = Round(lnTotal, 2)
  lnValor = Round(lnValor * lnTasaFactor, 2)
  lnDescMae = Round(lnDescMae * lnTasaFactor, 2)
  lnItbis = Round(lnItbis * lnTasaFactor, 2)
  lnTotal = Round(lnTotal * lnTasaFactor, 2)
  * Retenciones en compras (41): gastos.itbisr (ITBIS retenido), isr (ISR); fallback itbir si existe.
  lnItbisRet = 0
  lnIsr = 0
  lnItbisRetOM = 0
  lnIsrOM = 0
  If Type("itbisr") != "U"
    lnItbisRetOM = Round(_ChalonaEcfNzNum(itbisr), 2)
    lnItbisRet = Round(lnItbisRetOM * lnTasaFactor, 2)
  Else
    If Type("itbir") != "U"
      lnItbisRetOM = Round(_ChalonaEcfNzNum(itbir), 2)
      lnItbisRet = Round(lnItbisRetOM * lnTasaFactor, 2)
    Endif
  Endif
  If Type("isr") != "U"
    lnIsrOM = Round(_ChalonaEcfNzNum(isr), 2)
    lnIsr = Round(lnIsrOM * lnTasaFactor, 2)
  Endif
  lnPropina = 0
  lnPropinaOM = 0
  If Type("propina") != "U"
    lnPropinaOM = Round(_ChalonaEcfNzNum(propina), 2)
    lnPropina = Round(lnPropinaOM * lnTasaFactor, 2)
  Endif
  * Convencion: cuando existe campo propina separado, imtr.total NO la incluye.
  * Sumar al lnTotal para que MontoTotal = base + itbis + propina (DGII espera
  * MontoTotal = MontoGravadoTotal + TotalITBIS + MontoImpuestoAdicional + ...).
  If lnPropina > 0
    lnTotal = Round(lnTotal + lnPropina, 2)
    lnTotalOM = Round(lnTotalOM + lnPropinaOM, 2)
  Endif
  lcMaeRnc = Alltrim(Transform(Nvl(rnc, "")))
  lcMaeNombre = Alltrim(Transform(Nvl(nombre, "")))
  lcEntidad = Alltrim(Transform(Nvl(entidad, "")))
  lcOcontrol = Alltrim(Transform(Nvl(ocontrol, "")))

  * En gastos a veces el RNC no viene en la fila; buscarlo en suplidor para cumplir RNCComprador requerido.
  If llEsGastos And Empty(Alltrim(lcMaeRnc)) And !Empty(Alltrim(lcEntidad))
    If Used("curChalSup") And Reccount("curChalSup") > 0
      Select curChalSup
      Go Top
      If Type("curChalSup.rnc") # "U"
        lcMaeRnc = Alltrim(Transform(Nvl(rnc, "")))
      Endif
      If Empty(Alltrim(lcMaeNombre)) And Type("curChalSup.nombre") # "U"
        lcMaeNombre = Alltrim(Transform(Nvl(nombre, "")))
      Endif
    Endif
    ChalonaEcfUseInIfUsed("curChalSup")
  Endif

  * FechaVencimientoSecuencia (IdDoc): 1) imtr.fechavencencf si tiene valor; 2) si no, fiscal.vence por tipo.
  ldFecVen = .Null.
  lcFecVen = ""
  If Type("fechavencencf") != "U"
    lcFecVen = _ChalonaEcfFmtDdMmYy(fechavencencf)
  Endif
  If Empty(Alltrim(lcFecVen)) And !Empty(lcTipoeCF)
    If Used("curChalFis") And Reccount("curChalFis") > 0
      Select curChalFis
      Go Top
      ldFecVen = vence
      lcFecVen = _ChalonaEcfFmtDdMmYy(ldFecVen)
    Endif
  Endif

  * XSD DGII (IdDoc): FechaVencimientoSecuencia obligatoria dd-MM-yyyy para TipoeCF 31,33,41,43-47.
  * Si falta en imtr.fechavencencf y en dbo.fiscal.vence, el XML con etiqueta vacia falla en DGII (codigo 1 formato invalido).
  If Inlist(Int(Val(lcTipoeCF)), 31, 33, 41, 43, 44, 45, 46, 47) ;
      And Empty(Alltrim(lcFecVen))
    ChalonaEcfLogError("ECF: FechaVencimientoSecuencia obligatoria sin fecha (imtr.fechavencencf o dbo.fiscal.vence para tipo " + lcTipoeCF + ")", tcControl, "")
    gcChalonaEcfBuildDocError = "ecf.iddoc.fecha_vencimiento_requerida"
    llNull = .T.
    Exit
  Endif

  lcEmpRnc = ""
  lcEmpNom = ""
  lcEmpDir = ""
      lnIprecio = 0
  If Used("curChalEmp") And Reccount("curChalEmp") > 0
    Select curChalEmp
    Go Top
    lcEmpRnc = Alltrim(Transform(Nvl(rnc, "")))
    lcEmpNom = Alltrim(Transform(Nvl(nombre, "")))
    lcEmpDir = Alltrim(Transform(Nvl(direccion, "")))
        * iprecio (bit): 1 => precio incluye ITBIS
        If Type("curChalEmp.iprecio") # "U"
          Do Case
          Case Vartype(iprecio) = "L"
            lnIprecio = Iif(iprecio, 1, 0)
          Otherwise
            lnIprecio = _ChalonaEcfNzNum(iprecio)
          Endcase
        Endif
  Endif

  lnExtranjero = 0
  If !Empty(lcEntidad)
    If llEsGastos
      * Compras: tercero es suplidor. extranjero vive en curChalCli.
      lcSuplidorId = lcEntidad
      If Used("curChalCli") And Reccount("curChalCli") > 0
        Select curChalCli
        Go Top
        lnExtranjero = _ChalonaEcfNzNum(extranjero_flag)
      Endif
    Else
      * Ventas: tercero viene de curChalCli (cliente).
      If Used("curChalCli") And Reccount("curChalCli") > 0
        Select curChalCli
        Go Top
        lnExtranjero = _ChalonaEcfNzNum(extranjero_flag)
        * Fallback: si imtr no trae rnc/nombre del comprador, buscarlos en dbo.clientes.
        If Empty(Alltrim(lcMaeRnc)) And Type("curChalCli.rnc") # "U"
          lcMaeRnc = Alltrim(Transform(Nvl(rnc, "")))
        Endif
        If Empty(Alltrim(lcMaeNombre)) And Type("curChalCli.nombre") # "U"
          lcMaeNombre = Alltrim(Transform(Nvl(nombre, "")))
        Endif
      Endif
    Endif
  Endif
  * Sin flag en BD: id que no es RNC/cedula RD -> DGII rechaza RNCComprador; usar IdentificadorExtranjero.
  If lnExtranjero = 0 And !Empty(Alltrim(lcMaeRnc)) And !_ChalonaEcfEsIdentificadorFiscalRD(lcMaeRnc)
    lnExtranjero = 1
  Endif

  lcRefEncf = ""
  ldRefFec = .Null.
  lcInfRef = "null"
  * CodigoModificacion DGII: 2=solo correcciÃ³n de texto (montos cero). 3=ajuste/descuento con montos (NC/ND tÃ­picas con imtrd).
  * Antes se forzaba 2 siempre → devoluciones con cantidad/precio quedaban mal. Default 3; 2 solo si imtr.dgii_codmod=2 (columna opcional).
  lnCodMod = 3
  If !Empty(lcOcontrol)
    Select curChalMae
    Go Top
    If Type("dgii_codmod") != "U"
      lnCodMod = Int(_ChalonaEcfNzNum(dgii_codmod))
    Endif
    If lnCodMod < 1 Or lnCodMod > 5
      lnCodMod = 3
    Endif
    * Codigos 1/2/3 SOLO aplican a NC/ND (33/34). Cualquier otro tipo con esos valores → DGII rechaza 613.
    * Tipo 31 (FCF): forzar 4; luego se ajusta a 5 si el NCF referenciado es FC electronica (E32).
    * Tipos 41/43/44/45/46/47: InformacionReferencia/CodigoModificacion no aplica → omitir referencia.
    llOmitirRef = .F.
    If !Inlist(Int(Val(lcTipoeCF)), 33, 34) And Inlist(lnCodMod, 1, 2, 3)
      If Int(Val(lcTipoeCF)) = 31
        lnCodMod = 4
      Else
        llOmitirRef = .T.
      Endif
    Endif
    If !llOmitirRef
      If Used("curChalRef") And Reccount("curChalRef") > 0
        Select curChalRef
        Go Top
        lcRefEncf = Alltrim(Transform(Nvl(encf, "")))
        ldRefFec = fecha
        * Tipo 31: InformacionReferencia solo es valida en dos casos:
        *   - NCF referenciado NO empieza con E (papel/contingencia) → codigo 4.
        *   - NCF referenciado es Factura Consumo Electronica (E32...) → codigo 5.
        * Si el referenciado es cualquier otro e-CF (E31, E46, etc.) la DGII rechaza
        * con error 613 ("no pueden reemplazarse entre ellos"). En ese caso omitir referencia.
        If Int(Val(lcTipoeCF)) = 31 And lnCodMod = 4
          If Left(lcRefEncf, 1) = "E"
            If Left(lcRefEncf, 3) = "E32"
              lnCodMod = 5
            Else
              * e-CF electronico que no es FC: referencia no aplica para tipo 31.
              lcRefEncf = ""
              ldRefFec   = .Null.
            Endif
          Endif
        Endif
        If !Empty(lcRefEncf)
          lcInfRef = "{" + '"NCFModificado":"' + _JsonEscape(lcRefEncf) + '",' + ;
            '"FechaNCFModificado":"' + _JsonEscape(_ChalonaEcfFmtDdMmYy(ldRefFec)) + '",' + ;
            '"CodigoModificacion":' + Transform(lnCodMod) + "}"
        Endif
      Endif
    Endif
  Endif
  * Solo con cÃ³digo 2: totales/lÃ­neas en cero (DGII 645). Con 3/1/4 se envÃ­a el detalle real de imtrd.
  llCorrigeTexto = (lcInfRef <> "null") And (lnCodMod = 2)

  If llEsGastos
    * Gastos no tiene detalle: cursor sintÃ©tico de 1 línea para cumplir XSD (CantidadItem > 0).
    ChalonaEcfUseInIfUsed("curChalDet")
    Create Cursor curChalDet ;
      (precio N(18, 6), cantidad N(18, 4), descrip C(200), mercs_nombre C(200), mercs_servicio N(10, 0))
    Append Blank In curChalDet
    Replace mercs_servicio With 2 In curChalDet
    * Texto de item: comentario / referencia / doc-numero.
    lcItemTxt = lcGastoComentario
    If Empty(lcItemTxt)
      lcItemTxt = lcGastoReferencia
    Endif
    If Empty(lcItemTxt)
      lcItemTxt = Alltrim(Nvl(lcGastoDoc, "")) + " " + Alltrim(Nvl(lcGastoNumero, ""))
    Endif
    Replace descrip With Left(lcItemTxt, 200) In curChalDet
    Replace mercs_nombre With Left(lcItemTxt, 200) In curChalDet
    Replace cantidad With 1 In curChalDet
    * Monto mínimo DGII para 1 línea: base=(valor-descuento).
    * Con ITBIS: si empresa.iprecio=1 -> IndicadorMontoGravado=1 (línea en bruto con ITBIS); precio=total/tasa.
    * Si iprecio=0 -> IndicadorMontoGravado=0 (línea sin ITBIS); precio=base/tasa para alinear MontoItem con MontoGravadoI1.
    lnBaseSinItbis = Round((lnValor - lnDescMae), 2)
    If lnItbis # 0
      If lnIprecio = 1
        Replace precio With Round(Iif(lnTasaFactor = 0, lnTotal, (lnTotal / lnTasaFactor)), 6) In curChalDet
      Else
        Replace precio With Round(Iif(lnTasaFactor = 0, lnBaseSinItbis, (lnBaseSinItbis / lnTasaFactor)), 6) In curChalDet
      Endif
    Else
      Replace precio With Round(Iif(lnTasaFactor = 0, lnBaseSinItbis, (lnBaseSinItbis / lnTasaFactor)), 6) In curChalDet
    Endif
  Endif
  * (Ventas: curChalDet debe estar pre-poblado por _PoblarCursoresDesdeImtr o por el integrador.)

  lnTotalBruto = 0
  If Used("curChalDet") And Reccount("curChalDet") > 0
    Select curChalDet
    Scan
      lnP = Round(_ChalonaEcfStrToDecimal(Transform(precio)) * lnTasaFactor / Iif(lnIprecio=1 And lnItbis#0, 1.18, 1), 6)
      lnC = _ChalonaEcfStrToDecimal(Transform(cantidad))
      lnTotalBruto = lnTotalBruto + Round(lnP * lnC, 2)
    Endscan
  Endif

  * ITBIS tasa en cabecera / IndicadorFacturacion (antes de IdDoc: hace falta para armar Totales y detalle).
  If lnItbis = 0
    lnItbis1 = 0
  Else
    lnItbis1 = 18
  Endif
  lnFactorIprecio = Iif(lnIprecio = 1 And lnItbis1 > 0, 1 + lnItbis1 / 100, 1)
  lnTipoEcf = Val(lcTipoeCF)
  lnBaseGrav = lnValor - lnDescMae
  Do Case
  Case lnTipoEcf = 43 Or lnTipoEcf = 44 Or lnTipoEcf = 47
    lnIndFact = 4
  Case lnTipoEcf = 46
    lnIndFact = Iif(lnItbis = 0, 3, 1)
  Case lnItbis = 0
    lnIndFact = 4
  Otherwise
    lnIndFact = 1
  Endcase

  * Tipos 41/43 (salvo CodigoModificacion 2 / corrige texto): MontoTotal debe ser > 0.
  * La DGII rechaza comprobantes con totales en cero (p. ej. error 1960 en MontoExento para tipo 43).
  If !llCorrigeTexto And (lnTipoEcf = 41 Or lnTipoEcf = 43) And lnTotal <= 0
    ChalonaEcfLogError("ECF: TipoeCF 41/43 requiere MontoTotal > 0", tcControl, "")
    gcChalonaEcfBuildDocError = "ecf.monto_total_mayor_cero_compras_gastos"
    llNull = .T.
    Exit
  Endif

  If lnDiasCr > 0
    lnTipoPago = 2
    Do Case
    Case (Vartype(ldFecEmi) = "D" Or Vartype(ldFecEmi) = "T") And !Empty(ldFecEmi) And !Isnull(ldFecEmi)
      lcFLP = '"' + _JsonEscape(_ChalonaEcfFmtDdMmYy(ldFecEmi + lnDiasCr)) + '"'
    Otherwise
      lcFLP = "null"
    Endcase
  Else
    lnTipoPago = 1
    lcFLP = "null"
  Endif

      * IndicadorMontoGravado: siempre 0 (precios en detalle son base sin ITBIS).
      * Cuando iprecio=1 los precios del ERP vienen con ITBIS; se dividen por lnFactorIprecio
      * antes de usarlos, así el detalle queda en base y IndicadorMontoGravado se mantiene en 0.
      lnIndicadorMontoGravado = 0

  * Si precio incluye ITBIS (IndicadorMontoGravado=1), el validador del API compara MontoGravadoI1 con
  * suma(MontoItem de lÃ­neas I1) / (1+ITBIS1/100). Los totales del maestro (valor-itbis) suelen ser base sin ITBIS
  * y no coinciden con ese criterio; se recalculan cabecera desde el detalle antes de armar Totales.
  lnSumMontoItems = 0
  lnSumMontoItemsOM = 0
  If !llCorrigeTexto And lnIndicadorMontoGravado = 1 And lnIndFact = 1
    If Used("curChalDet") And Reccount("curChalDet") > 0
      Select curChalDet
      Scan
        lnP = Round(_ChalonaEcfStrToDecimal(Transform(precio)) * lnTasaFactor, 6)
        lnC = _ChalonaEcfStrToDecimal(Transform(cantidad))
        lnBruto = Round(lnP * lnC, 2)
        lnDescLin = 0
        If lnDescMae # 0 And lnTotalBruto # 0
          lnDescLin = Round(lnDescMae * lnBruto / lnTotalBruto, 2)
        Endif
        lnMontoItem = Round(lnBruto - lnDescLin, 2)
        lnSumMontoItems = lnSumMontoItems + lnMontoItem
        If llMultiMoneda
          lnBrutoOM = Round(_ChalonaEcfStrToDecimal(Transform(precio)) * lnC, 2)
          lnDescLinOMloc = Iif(lnDescMaeOM = 0 Or lnTotalBruto = 0, 0, Round(lnDescMaeOM * lnBruto / lnTotalBruto, 2))
          lnSumMontoItemsOM = lnSumMontoItemsOM + Round(lnBrutoOM - lnDescLinOMloc, 2)
        Endif
      Endscan
    Endif
  Endif

  * Acumular Totales desde el detalle por IndicadorFacturacion. Solo aplica a la rama Otherwise
  * de lcTot (tipos no 43/44/47/46 con itbis != 0). Para tipos especiales se ignora.
  lnSumGravadoI1 = 0
  lnSumExento = 0
  lnSumItbisI1 = 0
  lnSumGravadoI3 = 0
  lnSumTotalDet = 0
  lnSumGravadoI1OM = 0
  lnSumExentoOM = 0
  lnSumItbisI1OM = 0
  lnSumGravadoI3OM = 0
  * Default: si curChalDet no esta o ya estamos en corrige_texto, asumir cabecera como criterio (lnItbis).
  llDetTieneItbis = .F.
  If Used("curChalDet") And Reccount("curChalDet") > 0
    Select curChalDet
    llDetTieneItbis = (Type("itbis") != "U")
  Endif
  If !llCorrigeTexto And Used("curChalDet") And Reccount("curChalDet") > 0
    Select curChalDet
    Scan
      lnP = Round(_ChalonaEcfStrToDecimal(Transform(precio)) * lnTasaFactor / lnFactorIprecio, 6)
      lnC = _ChalonaEcfStrToDecimal(Transform(cantidad))
      lnBruto = Round(lnP * lnC, 2)
      lnDescLin = 0
      If lnDescMae # 0 And lnTotalBruto # 0
        lnDescLin = Round(lnDescMae * lnBruto / lnTotalBruto, 2)
      Endif
      lnMontoItem = Round(lnBruto - lnDescLin, 2)
      * Saltar lineas con monto 0 (ruido del ERP: cantidad sin precio o precio sin cantidad).
      * Si quedan en detalle generan inconsistencias (p.ej. IF=4 con monto 0 -> DGII 1960 MontoExento).
      If lnMontoItem = 0
        Loop
      Endif
      * ITBIS sobre el MONTO NETO (con descuento aplicado), no sobre el bruto.
      * imtrd.itbis viene calculado por el ERP sobre el bruto: produce TotalITBIS1 inflado y rechazo DGII 11014.
      lnItbisLin = Round(lnMontoItem * lnItbis1 / 100, 2)
      If llDetTieneItbis
        lnItbisLineaVal = _ChalonaEcfNzNum(itbis)
      Else
        lnItbisLineaVal = Iif(lnItbis > 0, 1, 0)
      Endif
      * itbis_tasa por linea (override DGII): >0 fuerza gravado, 0 con itbis=0 => exento.
      Local lnTasaLin
      lnTasaLin = Iif(Type("itbis_tasa") # "U", _ChalonaEcfNzNum(itbis_tasa), 0)
      lnSumTotalDet = lnSumTotalDet + lnMontoItem
      Do Case
      Case lnTipoEcf = 43 Or lnTipoEcf = 44 Or lnTipoEcf = 47
        lnSumExento = lnSumExento + lnMontoItem
      Case lnTipoEcf = 46
        If lnItbis = 0
          lnSumGravadoI3 = lnSumGravadoI3 + lnMontoItem
        Else
          lnSumGravadoI1 = lnSumGravadoI1 + lnMontoItem
          lnSumItbisI1 = lnSumItbisI1 + lnItbisLin
        Endif
      Case lnTasaLin > 0
        lnSumGravadoI1 = lnSumGravadoI1 + lnMontoItem
        lnSumItbisI1 = lnSumItbisI1 + lnItbisLin
      Case lnItbisLineaVal = 0
        lnSumExento = lnSumExento + lnMontoItem
      Otherwise
        lnSumGravadoI1 = lnSumGravadoI1 + lnMontoItem
        lnSumItbisI1 = lnSumItbisI1 + lnItbisLin
      Endcase
      If llMultiMoneda
        lnBrutoOM = Round(_ChalonaEcfStrToDecimal(Transform(precio)) / lnFactorIprecio * lnC, 2)
        lnDescLinOMloc = Iif(lnDescMaeOM = 0 Or lnTotalBruto = 0, 0, Round(lnDescMaeOM * lnBruto / lnTotalBruto, 2))
        lnMontoItemOMloc = Round(lnBrutoOM - lnDescLinOMloc, 2)
        lnItbisLinOM = Round(lnMontoItemOMloc * lnItbis1 / 100, 2)
        Do Case
        Case lnTipoEcf = 43 Or lnTipoEcf = 44 Or lnTipoEcf = 47
          lnSumExentoOM = lnSumExentoOM + lnMontoItemOMloc
        Case lnTipoEcf = 46
          If lnItbis = 0
            lnSumGravadoI3OM = lnSumGravadoI3OM + lnMontoItemOMloc
          Else
            lnSumGravadoI1OM = lnSumGravadoI1OM + lnMontoItemOMloc
            lnSumItbisI1OM = lnSumItbisI1OM + lnItbisLinOM
          Endif
        Case lnItbisLineaVal = 0
          lnSumExentoOM = lnSumExentoOM + lnMontoItemOMloc
        Otherwise
          lnSumGravadoI1OM = lnSumGravadoI1OM + lnMontoItemOMloc
          lnSumItbisI1OM = lnSumItbisI1OM + lnItbisLinOM
        Endcase
      Endif
    Endscan
  Endif

  * IndicadorNotaCredito (34, DGII/XSD): 0 si han pasado <=30 d�as calendario desde la factura referenciada (FechaNCFModificado) hasta la emisi�n de la NC; 1 si >30.
  * Tipo 34 EXIGE ambas fechas; sin ellas no se puede calcular y enviar 0 por defecto produce rechazo DGII 156.
  * En VFP, (DateTime - DateTime) devuelve SEGUNDOS; usar TTOD() para d�as calendario igual al c�lculo del API.
  lcIndicadorNotaCredito = ""
  lnDiasNcRef = 0
  If Val(lcTipoeCF) = 34
    If !((Vartype(ldRefFec) = "D" Or Vartype(ldRefFec) = "T") And !Empty(ldRefFec) And !Isnull(ldRefFec))
      ChalonaEcfLogError("NC tipo 34: FechaNCFModificado vacia (imtr.fecha del NCF referenciado)", tcControl, "")
      gcChalonaEcfBuildDocError = "ecf.nc34.fecha_ncf_modificado_requerida"
      llNull = .T.
      Exit
    Endif
    If !((Vartype(ldFecEmi) = "D" Or Vartype(ldFecEmi) = "T") And !Empty(ldFecEmi) And !Isnull(ldFecEmi))
      ChalonaEcfLogError("NC tipo 34: FechaEmision vacia", tcControl, "")
      gcChalonaEcfBuildDocError = "ecf.nc34.fecha_emision_requerida"
      llNull = .T.
      Exit
    Endif
    lnDiasNcRef = Iif(Vartype(ldFecEmi)="T", Ttod(ldFecEmi), ldFecEmi) - Iif(Vartype(ldRefFec)="T", Ttod(ldRefFec), ldRefFec)
    lcIndicadorNotaCredito = Iif(lnDiasNcRef > 30, '"IndicadorNotaCredito":1,', '"IndicadorNotaCredito":0,')
  Endif

  lcIdDoc = "{" + '"TipoeCF":"' + _JsonEscape(lcTipoeCF) + '",' + ;
    '"eNCF":"' + _JsonEscape(lcEncf) + '",' + ;
    lcIndicadorNotaCredito + ;
    '"FechaVencimientoSecuencia":"' + _JsonEscape(lcFecVen) + '",' + ;
        '"IndicadorMontoGravado":' + Transform(lnIndicadorMontoGravado) + "," + ;
    '"TipoIngresos":"01",' + ;
    '"TipoPago":' + Transform(lnTipoPago) + "," + ;
    '"FechaLimitePago":' + lcFLP + "}"

  lcEmisor = "{" + '"RNCEmisor":"' + _JsonEscape(_ChalonaEcfNormalizeTexto(lcEmpRnc)) + '",' + ;
    '"RazonSocialEmisor":"' + _JsonEscape(_ChalonaEcfNormalizeTexto(lcEmpNom)) + '",' + ;
    '"NombreComercial":"' + _JsonEscape(_ChalonaEcfNormalizeTexto(lcEmpNom)) + '",' + ;
    '"DireccionEmisor":"' + _JsonEscape(_ChalonaEcfNormalizeTexto(lcEmpDir)) + '",' + ;
    '"FechaEmision":"' + _JsonEscape(_ChalonaEcfFmtDdMmYy(ldFecEmi)) + '"}'

  * Comprador extranjero: usar IdentificadorExtranjero y dejar RNCComprador vacÃ­o.
  lcComp = "{" + '"RNCComprador":"' + _JsonEscape(Iif(lnExtranjero = 0, _ChalonaEcfNormalizeTexto(lcMaeRnc), "")) + '",' + ;
    '"IdentificadorExtranjero":"' + _JsonEscape(Iif(lnExtranjero = 0, "", _ChalonaEcfNormalizeTexto(lcMaeRnc))) + '",' + ;
    '"RazonSocialComprador":"' + _JsonEscape(_ChalonaEcfNormalizeTexto(lcMaeNombre)) + '"}'

  If llCorrigeTexto
    lcTot = "{" + ;
      '"MontoGravadoTotal":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"MontoGravadoI1":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"MontoGravadoI2":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"MontoGravadoI3":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"MontoExento":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"TotalITBIS":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"ITBIS1":0,"ITBIS2":0,"ITBIS3":0,' + ;
      '"TotalITBIS1":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"TotalITBIS2":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"TotalITBIS3":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"MontoTotal":' + _ChalonaEcfJsonNum(0, 2) + "}"
  Else
  Do Case
  Case lnTipoEcf = 43 Or lnTipoEcf = 44 Or lnTipoEcf = 47
    * Puede venir 43 con ITBIS (p. ej. compras desde gastos). Solo tratar como exento si itbis=0.
    If lnItbis = 0
      lcTot = "{" + ;
        '"MontoGravadoTotal":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoGravadoI1":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoGravadoI2":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoGravadoI3":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoExento":' + _ChalonaEcfJsonNum(lnBaseGrav, 2) + "," + ;
        '"TotalITBIS":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"ITBIS1":0,"ITBIS2":0,"ITBIS3":0,' + ;
        '"TotalITBIS1":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"TotalITBIS2":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"TotalITBIS3":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoTotal":' + _ChalonaEcfJsonNum(lnTotal, 2) + "}"
    Else
      lcTot = "{" + ;
        '"MontoGravadoTotal":' + _ChalonaEcfJsonNum(lnBaseGrav, 2) + "," + ;
        '"MontoGravadoI1":' + _ChalonaEcfJsonNum(lnBaseGrav, 2) + "," + ;
        '"TotalITBIS":' + _ChalonaEcfJsonNum(lnItbis, 2) + "," + ;
        '"ITBIS1":' + Transform(Iif(lnItbis = 0, 0, lnItbis1)) + "," + ;
        '"TotalITBIS1":' + _ChalonaEcfJsonNum(lnItbis, 2) + "," + ;
        '"MontoTotal":' + _ChalonaEcfJsonNum(lnTotal, 2) + "}"
    Endif
  Case lnTipoEcf = 46
    If lnItbis = 0
      * Nota 51 DGII: tasa cero -> MontoGravadoI3, no MontoGravadoI1.
      lcTot = "{" + ;
        '"MontoGravadoTotal":' + _ChalonaEcfJsonNum(lnBaseGrav, 2) + "," + ;
        '"MontoGravadoI1":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoGravadoI2":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoGravadoI3":' + _ChalonaEcfJsonNum(lnBaseGrav, 2) + "," + ;
        '"MontoExento":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"TotalITBIS":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"ITBIS1":0,"ITBIS2":0,"ITBIS3":0,' + ;
        '"TotalITBIS1":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"TotalITBIS2":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"TotalITBIS3":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoTotal":' + _ChalonaEcfJsonNum(lnTotal, 2) + "}"
    Else
      * Con ITBIS: slot 1 (ITBIS1). MontoGravadoI1*ITBIS1/100 = TotalITBIS1 (DGII 11004).
      lcTot = "{" + ;
        '"MontoGravadoTotal":' + _ChalonaEcfJsonNum(lnBaseGrav, 2) + "," + ;
        '"MontoGravadoI1":' + _ChalonaEcfJsonNum(lnBaseGrav, 2) + "," + ;
        '"MontoGravadoI2":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoGravadoI3":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoExento":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"TotalITBIS":' + _ChalonaEcfJsonNum(lnItbis, 2) + "," + ;
        '"ITBIS1":' + Transform(lnItbis1) + "," + ;
        '"ITBIS2":0,"ITBIS3":0,' + ;
        '"TotalITBIS1":' + _ChalonaEcfJsonNum(lnItbis, 2) + "," + ;
        '"TotalITBIS2":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"TotalITBIS3":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoTotal":' + _ChalonaEcfJsonNum(lnTotal, 2) + "}"
    Endif
  Case lnItbis = 0
    * Si el detalle suma exento, usar la suma (cabecera valor puede estar en 0).
    Local lnExentoFinal, lnTotalFinalCab
    lnExentoFinal = Iif(lnSumExento > 0, lnSumExento, lnBaseGrav)
    lnTotalFinalCab = Iif(lnSumExento > 0, lnSumExento, lnTotal)
    lcTot = "{" + ;
      '"MontoGravadoTotal":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"MontoGravadoI1":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"MontoGravadoI2":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"MontoGravadoI3":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"MontoExento":' + _ChalonaEcfJsonNum(lnExentoFinal, 2) + "," + ;
      '"TotalITBIS":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"ITBIS1":0,"ITBIS2":0,"ITBIS3":0,' + ;
      '"TotalITBIS1":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"TotalITBIS2":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"TotalITBIS3":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
      '"MontoTotal":' + _ChalonaEcfJsonNum(lnTotalFinalCab, 2) + "}"
  Otherwise
    If lnIndicadorMontoGravado = 1 And lnSumMontoItems > 0 And lnItbis1 > 0
      lnFactorItbis = 1 + (lnItbis1 / 100)
      lnBaseGrav = Round(lnSumMontoItems / lnFactorItbis, 2)
      lnItbis = Round(lnSumMontoItems - lnBaseGrav, 2)
      lnTotal = Round(lnSumMontoItems, 2)
      If llMultiMoneda And lnSumMontoItemsOM > 0
        lnItbisOM = Round(lnSumMontoItemsOM - Round(lnSumMontoItemsOM / lnFactorItbis, 2), 2)
        lnTotalOM = Round(lnSumMontoItemsOM, 2)
      Endif
    Endif
    * Totales desde detalle (acumuladores por IndicadorFacturacion). Si el SCAN no acumuló nada
    * (sin detalle), caer al cálculo legacy desde maestro.
    If lnSumGravadoI1 + lnSumExento > 0
      * Con IndicadorMontoGravado=1 el MontoItem viene con ITBIS incluido: hay que removerlo
      * para MontoGravadoI1 y derivar TotalITBIS1 = base con ITBIS - base sin ITBIS.
      lnGravI1Final = lnSumGravadoI1
      lnItbisI1Final = lnSumItbisI1
      lnTotalFinal = Round(lnSumGravadoI1 + lnSumExento + lnSumItbisI1 + lnPropina, 2)
      If lnIndicadorMontoGravado = 1 And lnItbis1 > 0 And lnSumGravadoI1 > 0
        lnFactorItbis = 1 + (lnItbis1 / 100)
        lnGravI1Final = Round(lnSumGravadoI1 / lnFactorItbis, 2)
        lnItbisI1Final = Round(lnSumGravadoI1 - lnGravI1Final, 2)
        lnTotalFinal = Round(lnSumGravadoI1 + lnSumExento + lnPropina, 2)
      Endif
      lcTot = "{" + ;
        '"MontoGravadoTotal":' + _ChalonaEcfJsonNum(lnGravI1Final, 2) + "," + ;
        '"MontoGravadoI1":' + _ChalonaEcfJsonNum(lnGravI1Final, 2) + "," + ;
        Iif(lnSumExento > 0, '"MontoExento":' + _ChalonaEcfJsonNum(lnSumExento, 2) + ",", "") + ;
        '"TotalITBIS":' + _ChalonaEcfJsonNum(lnItbisI1Final, 2) + "," + ;
        '"ITBIS1":' + Transform(lnItbis1) + "," + ;
        '"TotalITBIS1":' + _ChalonaEcfJsonNum(lnItbisI1Final, 2) + "," + ;
        '"MontoTotal":' + _ChalonaEcfJsonNum(lnTotalFinal, 2) + "}"
    Else
      lcTot = "{" + ;
        '"MontoGravadoTotal":' + _ChalonaEcfJsonNum(lnBaseGrav, 2) + "," + ;
        '"MontoGravadoI1":' + _ChalonaEcfJsonNum(lnBaseGrav, 2) + "," + ;
        '"TotalITBIS":' + _ChalonaEcfJsonNum(lnItbis, 2) + "," + ;
        '"ITBIS1":' + Transform(lnItbis1) + "," + ;
        '"TotalITBIS1":' + _ChalonaEcfJsonNum(lnItbis, 2) + "," + ;
        '"MontoTotal":' + _ChalonaEcfJsonNum(lnTotal, 2) + "}"
    Endif
  Endcase
  Endif

  * Propina legal (codigo 001): si imtr.propina existe y > 0, inyectar MontoImpuestoAdicional antes de MontoTotal.
  If lnPropina > 0 And !llCorrigeTexto
    lnPos = At('"MontoTotal":', lcTot)
    If lnPos > 0
      lcTot = Left(lcTot, lnPos - 1) + '"MontoImpuestoAdicional":' + _ChalonaEcfJsonNum(lnPropina, 2) + "," + Substr(lcTot, lnPos)
    Endif
  Endif

  * TipoeCF 41: totales de retenci�n solo si >0 (DGII 11160 si TotalITBISRetenido=0 informado junto a ISR).
  If lnTipoEcf = 41 And !llCorrigeTexto
    lcInsRet = ""
    If lnItbisRet # 0
      lcInsRet = lcInsRet + '"TotalITBISRetenido":' + _ChalonaEcfJsonNum(lnItbisRet, 2) + ","
    Endif
    If lnIsr # 0
      lcInsRet = lcInsRet + '"TotalISRRetencion":' + _ChalonaEcfJsonNum(lnIsr, 2) + ","
    Endif
    If !Empty(lcInsRet)
      lnPos = At('"MontoTotal":', lcTot)
      If lnPos > 0
        lcTot = Left(lcTot, lnPos - 1) + lcInsRet + Substr(lcTot, lnPos)
      Endif
    Endif
  Endif

  lcRetencion41 = ""
  If lnTipoEcf = 41
    lcRetencion41 = '"Retencion":{"IndicadorAgenteRetencionoPercepcion":1'
    If lnItbisRet # 0
      lcRetencion41 = lcRetencion41 + ',"MontoITBISRetenido":' + _ChalonaEcfJsonNum(lnItbisRet, 2)
    Endif
    If lnIsr # 0
      lcRetencion41 = lcRetencion41 + ',"MontoISRRetenido":' + _ChalonaEcfJsonNum(lnIsr, 2)
    Endif
    lcRetencion41 = lcRetencion41 + "},"
  Endif

  * Bloque OtraMoneda (XSD DGII): pareja en moneda extranjera de Totales.
  * Se omite con CodigoModificacion=2 (corrige texto) porque DGII exige todos los montos en cero.
  * Los montos vienen directamente de los valores originales en moneda extranjera (lnValorOM, lnItbisOM, lnTotalOM).
  lcOtraMoneda = ""
  If llMultiMoneda And !llCorrigeTexto
    lnBaseGravO = Round(lnValorOM - lnDescMaeOM, 2)
    lnItbisO = lnItbisOM
    lnTotalO = lnTotalOM
    Do Case
    * Orden de campos: igual al XSD DGII (MontoGravadoTotal → Gravado1/2/3 → Exento →
    *   TotalITBIS → TotalITBIS1/2/3 → ImpuestoAdicional → MontoTotal).
    Case (lnTipoEcf = 43 Or lnTipoEcf = 44 Or lnTipoEcf = 47) And lnItbis = 0
      lcOtraMoneda = '"OtraMoneda":{' + ;
        '"TipoMoneda":"' + _JsonEscape(lcMoneda) + '",' + ;
        '"TipoCambio":' + _ChalonaEcfJsonNum(lnTasaFactor, 4) + "," + ;
        '"MontoExentoOtraMoneda":' + _ChalonaEcfJsonNum(lnBaseGravO, 2) + "," + ;
        '"MontoTotalOtraMoneda":' + _ChalonaEcfJsonNum(lnTotalO, 2) + ;
        "}"
    Case lnTipoEcf = 46
      lcOtraMoneda = '"OtraMoneda":{' + ;
        '"TipoMoneda":"' + _JsonEscape(lcMoneda) + '",' + ;
        '"TipoCambio":' + _ChalonaEcfJsonNum(lnTasaFactor, 4) + "," + ;
        '"MontoGravadoTotalOtraMoneda":' + _ChalonaEcfJsonNum(lnBaseGravO, 2) + "," + ;
        '"MontoGravado3OtraMoneda":' + _ChalonaEcfJsonNum(lnBaseGravO, 2) + "," + ;
        '"TotalITBISOtraMoneda":' + _ChalonaEcfJsonNum(lnItbisO, 2) + "," + ;
        '"TotalITBIS3OtraMoneda":' + _ChalonaEcfJsonNum(lnItbisO, 2) + "," + ;
        '"MontoTotalOtraMoneda":' + _ChalonaEcfJsonNum(lnTotalO, 2) + ;
        "}"
    Case lnItbis = 0
      lcOtraMoneda = '"OtraMoneda":{' + ;
        '"TipoMoneda":"' + _JsonEscape(lcMoneda) + '",' + ;
        '"TipoCambio":' + _ChalonaEcfJsonNum(lnTasaFactor, 4) + "," + ;
        '"MontoExentoOtraMoneda":' + _ChalonaEcfJsonNum(lnBaseGravO, 2) + "," + ;
        '"MontoTotalOtraMoneda":' + _ChalonaEcfJsonNum(lnTotalO, 2) + ;
        "}"
    Otherwise
      lcOtraMoneda = '"OtraMoneda":{' + ;
        '"TipoMoneda":"' + _JsonEscape(lcMoneda) + '",' + ;
        '"TipoCambio":' + _ChalonaEcfJsonNum(lnTasaFactor, 4) + "," + ;
        '"MontoGravadoTotalOtraMoneda":' + _ChalonaEcfJsonNum(lnBaseGravO, 2) + "," + ;
        '"MontoGravado1OtraMoneda":' + _ChalonaEcfJsonNum(lnBaseGravO, 2) + "," + ;
        '"TotalITBISOtraMoneda":' + _ChalonaEcfJsonNum(lnItbisO, 2) + "," + ;
        '"TotalITBIS1OtraMoneda":' + _ChalonaEcfJsonNum(lnItbisO, 2) + "," + ;
        '"MontoTotalOtraMoneda":' + _ChalonaEcfJsonNum(lnTotalO, 2) + ;
        "}"
    Endcase
  Endif

  lcJson = "{" + '"Version":"1.0",' + ;
    '"IdDoc":' + lcIdDoc + "," + ;
    '"Emisor":' + lcEmisor + "," + ;
    '"Comprador":' + lcComp + "," + ;
    '"Totales":' + lcTot + ;
    Iif(Empty(lcOtraMoneda), "", "," + lcOtraMoneda) + ;
    "}"

  lcDet = "["
  lnLn = 0
  lcSep = ""
  If llCorrigeTexto
    * Una lÃ­nea: textos corregidos, montos en cero; CantidadItem=1 (XSD DGII exige > 0, no admite 0).
    If Used("curChalDet") And Reccount("curChalDet") > 0
      Select curChalDet
      Go Top
      lcDescItem = Alltrim(Transform(Nvl(descrip, "")))
      If !Empty(lcDescItem)
        lcNomItem = _ChalonaEcfNormalizeTexto(lcDescItem)
      Else
        lcNomItem = _ChalonaEcfNormalizeTexto(Alltrim(Transform(Nvl(mercs_nombre, ""))))
      Endif
      lcNomItem = Left(lcNomItem, 80)
      lcDescItem = _ChalonaEcfNormalizeTexto(lcDescItem)
      * Tipo 41: IndicadorBienoServicio derivado de ISR (bien si ISR=0, servicio si ISR>0).
      * Evita inconsistencia DGII 272: mercs_servicio puede estar mal en el catálogo.
      If lnTipoEcf = 41
        lnIndBS = Iif(lnIsr > 0, 2, 1)
      Else
        lnIndBS = Iif(_ChalonaEcfNzNum(mercs_servicio) = 0, 1, 2)
      Endif
      lcDet = lcDet + "{" + ;
        '"NumeroLinea":1,' + ;
        '"IndicadorFacturacion":' + Transform(lnIndFact) + "," + lcRetencion41 + ;
        '"NombreItem":"' + _JsonEscape(lcNomItem) + '",' + ;
        '"IndicadorBienoServicio":' + Transform(lnIndBS) + "," + ;
        '"DescripcionItem":"' + _JsonEscape(lcDescItem) + '",' + ;
        '"CantidadItem":' + _ChalonaEcfJsonNum(1, 4) + "," + ;
        '"PrecioUnitarioItem":' + _ChalonaEcfJsonNum(0, 6) + "," + ;
        '"DescuentoMonto":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoItem":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"TablaSubDescuento":null}'
    Else
      lcDet = lcDet + "{" + ;
        '"NumeroLinea":1,' + ;
        '"IndicadorFacturacion":' + Transform(lnIndFact) + "," + lcRetencion41 + ;
        '"NombreItem":"",' + ;
        '"IndicadorBienoServicio":1,' + ;
        '"DescripcionItem":"",' + ;
        '"CantidadItem":' + _ChalonaEcfJsonNum(1, 4) + "," + ;
        '"PrecioUnitarioItem":' + _ChalonaEcfJsonNum(0, 6) + "," + ;
        '"DescuentoMonto":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"MontoItem":' + _ChalonaEcfJsonNum(0, 2) + "," + ;
        '"TablaSubDescuento":null}'
    Endif
  Else
    If Used("curChalDet") And Reccount("curChalDet") > 0
      Select curChalDet
      Scan
        lnP = Round(_ChalonaEcfStrToDecimal(Transform(precio)) * lnTasaFactor / lnFactorIprecio, 6)
        lnC = _ChalonaEcfStrToDecimal(Transform(cantidad))
        lnBruto = Round(lnP * lnC, 2)
        lnDescLin = 0
        If lnDescMae # 0 And lnTotalBruto # 0
          lnDescLin = Round(lnDescMae * lnBruto / lnTotalBruto, 2)
        Endif
        lnMontoItem = Round(lnBruto - lnDescLin, 2)
        * Coherente con el primer scan (totales): saltar lineas con monto 0.
        If lnMontoItem = 0
          Loop
        Endif
        lnLn = lnLn + 1
        lcDescItem = Alltrim(Transform(Nvl(descrip, "")))
        If !Empty(lcDescItem)
          lcNomItem = _ChalonaEcfNormalizeTexto(lcDescItem)
        Else
          lcNomItem = _ChalonaEcfNormalizeTexto(Alltrim(Transform(Nvl(mercs_nombre, ""))))
        Endif
        lcNomItem = Left(lcNomItem, 80)
        lcDescItem = _ChalonaEcfNormalizeTexto(lcDescItem)
        * Tipo 41: IndicadorBienoServicio derivado de ISR (bien si ISR=0, servicio si ISR>0).
        If lnTipoEcf = 41
          lnIndBS = Iif(lnIsr > 0, 2, 1)
        Else
          lnIndBS = Iif(_ChalonaEcfNzNum(mercs_servicio) = 0, 1, 2)
        Endif
        * IndicadorFacturacion por línea: tipos con override fijo (43/44/47=4, 46=3) lo usan;
        * resto: 4 si la línea no tiene ITBIS (imtrd.itbis=0 o columna ausente con cabecera exenta), 1 si lo tiene.
        If llDetTieneItbis
          lnItbisLineaVal = _ChalonaEcfNzNum(itbis)
        Else
          lnItbisLineaVal = Iif(lnItbis > 0, 1, 0)
        Endif
        * itbis_tasa por linea: 18=>I1, 16=>I2, >0 sin match => I1 (gravado tasa principal).
        Local lnTasaLinIF
        lnTasaLinIF = Iif(Type("itbis_tasa") # "U", _ChalonaEcfNzNum(itbis_tasa), 0)
        Do Case
        Case lnTipoEcf = 43 Or lnTipoEcf = 44 Or lnTipoEcf = 47
          lnIndFactLin = 4
        Case lnTipoEcf = 46
          lnIndFactLin = Iif(lnItbis = 0, 3, 1)
        Case lnTasaLinIF = 16
          lnIndFactLin = 2
        Case lnTasaLinIF > 0
          lnIndFactLin = 1
        Case lnItbisLineaVal = 0
          lnIndFactLin = 4
        Otherwise
          lnIndFactLin = 1
        Endcase
        If lnDescLin = 0
          lcSubDesc = "null"
        Else
          lcSubDesc = '[{"TipoSubDescuento":"$","MontoSubDescuento":' + _ChalonaEcfJsonNum(lnDescLin, 2) + "}]"
        Endif
        * OtraMonedaDetalle (XSD pág. 43): bloque por línea con la versión en moneda extranjera.
        lcDetOM = ""
        If llMultiMoneda
          lnPOM = Round(_ChalonaEcfStrToDecimal(Transform(precio)), 4)
          lnDescLinOM = Round(lnDescLin / lnTasaFactor, 2)
          lnMontoItemOM = Round(lnMontoItem / lnTasaFactor, 2)
          lcDetOM = ',"OtraMonedaDetalle":{' + ;
            '"PrecioOtraMoneda":' + _ChalonaEcfJsonNum(lnPOM, 4) + "," + ;
            Iif(lnDescLinOM = 0, "", '"DescuentoOtraMoneda":' + _ChalonaEcfJsonNum(lnDescLinOM, 2) + ",") + ;
            '"MontoItemOtraMoneda":' + _ChalonaEcfJsonNum(lnMontoItemOM, 2) + ;
            "}"
        Endif
        lcDet = lcDet + lcSep + "{" + ;
          '"NumeroLinea":' + Transform(lnLn) + "," + ;
          '"IndicadorFacturacion":' + Transform(lnIndFactLin) + "," + lcRetencion41 + ;
          '"NombreItem":"' + _JsonEscape(lcNomItem) + '",' + ;
          '"IndicadorBienoServicio":' + Transform(lnIndBS) + "," + ;
          '"DescripcionItem":"' + _JsonEscape(lcDescItem) + '",' + ;
          '"CantidadItem":' + _ChalonaEcfJsonNum(lnC, 4) + "," + ;
          '"PrecioUnitarioItem":' + _ChalonaEcfJsonNum(lnP, 6) + "," + ;
          '"DescuentoMonto":' + _ChalonaEcfJsonNum(lnDescLin, 2) + "," + ;
          '"MontoItem":' + _ChalonaEcfJsonNum(lnMontoItem, 2) + lcDetOM + "," + ;
          '"TablaSubDescuento":' + lcSubDesc + "}"
        lcSep = ","
      Endscan
    Endif
  Endif
  lcDet = lcDet + "]"

  lcJson = "{" + '"Encabezado":' + lcJson + "," + '"DetallesItems":' + lcDet + "," + ;
    '"InformacionReferencia":' + lcInfRef + "}"

  ChalonaEcfCleanupCursorsImtrJson()
  lcOut = lcJson
  Exit
    Enddo
  Catch To loEx
    ChalonaEcfLogException("UNHANDLED: ChalonaEcfBuildDocJsonFox", tcControl, loEx, "")
    ChalonaEcfCleanupCursorsImtrJson()
    If Type("gcChalonaEcfBuildDocError") = "C" And Empty(Alltrim(Nvl(gcChalonaEcfBuildDocError, "")))
      gcChalonaEcfBuildDocError = "ecf.build.unhandled_exception"
    Endif
    llNull = .T.
  Endtry

  If llNull
    Return .Null.
  Endif
  Return lcOut
Endfunc


*============================================================
* Clase ChalonaEcf: helper de alto nivel para ECF
* - Usuario/clave/portal/BaseUrl desde Public osis al Init
* - _Login: hace sistema_login y guarda Token
* - Enviar: arma JSON en Fox (imtr/imtrd) y envÃƒÆ’Ã‚Â­a con envia_ecf
* - ConsultarEstado: consulta estado por lista de e-NCF (consulta_estado)
* - SincronizarEstadosEnProceso: candado SQL (sp_getapplock Session); solo una instancia
*   ejecuta el sync a la vez. Al terminar bien o al fallar (API/SQL) se libera el candado
*   para que otra instancia pueda tomarlo en el prÃƒÆ’Ã‚Â³ximo intento. Si el candado estÃƒÆ’Ã‚Â¡ ocupado,
*   ok=.T. con omitido_por_mutex (sin error).
*   _SyncListarPendientes/_SyncListarDuplicados, lotes de 100 e-NCF a consulta_estado, _GuardarRespuestaEnvio.
*   Requiere la misma conexiÃƒÆ’Ã‚Â³n SQL durante todo el mÃƒÆ’Ã‚Â©todo (Request habitual).
*============================================================
Define Class ChalonaEcf As Custom

  *BaseUrl = "https://ecf-service.vicortiz.com/"
  * Init: This.Cfg.servidor_ecf (inyectado vía SetConfig() o default desde osis).
  BaseUrl = "http://192.168.1.3:3030/"
  Usuario = ""
  Clave   = ""
  Portal  = ""
  Token   = ""
  * Objeto de configuración. Inyectable con SetConfig(). Si no se inyecta,
  * Init lo arma con ChalonaEcfConfigDesdeOsis() como default.
  * Debe exponer: servidor_ecf, usuario_sync, pass_sync, portal_dgii,
  * dgii_multimoneda (todas como cadenas).
  Cfg = .Null.
  * .T. cuando SetConfig() fue llamada con cfg externo; .F. = default desde osis (se re-lee en vivo).
  CfgEsExterna = .F.
  * Si .F., Enviar no abre el formulario largo; igual se muestra MESSAGEBOX breve si hay error.
  MostrarFormularioError = .T.

  * Constructor: credenciales y URL desde This.Cfg.
  * Si nadie inyectó vía SetConfig() antes de Init, se arma desde Public osis.
  Procedure Init
    Local lcUrl
    If Isnull(This.Cfg)
      This.Cfg = ChalonaEcfConfigDesdeOsis()
    Endif
    This.Usuario = ChalonaEcfCfgProp("usuario_sync", This.Cfg)
    This.Clave   = ChalonaEcfCfgProp("pass_sync",    This.Cfg)
    This.Portal  = Lower(ChalonaEcfCfgProp("portal_dgii", This.Cfg))
    This.Token   = ""
    lcUrl = Alltrim(ChalonaEcfCfgProp("servidor_ecf", This.Cfg))
    If !Empty(lcUrl)
      This.BaseUrl = lcUrl
    Endif
  Endproc

  * Inyecta el objeto de configuración. Llamar inmediatamente después de
  * Createobject("ChalonaEcf"). Re-aplica credenciales y BaseUrl al setear.
  Procedure SetConfig
    Lparameters toCfg
    Local lcUrl
    If Vartype(toCfg) # "O"
      Return
    Endif
    This.Cfg = toCfg
    This.CfgEsExterna = .T.
    This.Usuario = ChalonaEcfCfgProp("usuario_sync", This.Cfg)
    This.Clave   = ChalonaEcfCfgProp("pass_sync",    This.Cfg)
    This.Portal  = Lower(ChalonaEcfCfgProp("portal_dgii", This.Cfg))
    lcUrl = Alltrim(ChalonaEcfCfgProp("servidor_ecf", This.Cfg))
    If !Empty(lcUrl)
      This.BaseUrl = lcUrl
    Endif
  Endproc

  * Portal en vivo: si cfg fue inyectada externamente usa This.Cfg; si no, lee osis en el momento.
  * Evita que cambios en osis.portal_dgii post-init queden ignorados.
  Function _PortalActual
    Local lcP
    lcP = ""
    If This.CfgEsExterna
      lcP = Lower(ChalonaEcfCfgProp("portal_dgii", This.Cfg))
    Else
      If Type("osis") = "O" And Pemstatus(osis, "portal_dgii", 5)
        lcP = Lower(Alltrim(Nvl(osis.portal_dgii, "")))
      Endif
    Endif
    Return Iif(Empty(lcP), This.Portal, lcP)
  Endfunc

  * Normaliza BaseUrl (siempre termina en /)
  Function GetBaseUrl
    Local lcBaseUrl
    lcBaseUrl = This.BaseUrl
    If Right(lcBaseUrl, 1) # "/"
      lcBaseUrl = lcBaseUrl + "/"
    Endif
    Return lcBaseUrl
  Endfunc

  * Login en API: sistema_login -> Token
  Procedure _Login
    Local lcUsuario, lcClave, lcPortal, lcBaseUrl
    Local lcLoginReq, loLogin, lcToken

    lcUsuario = This.Usuario
    lcClave   = This.Clave
    lcPortal  = This._PortalActual()

    If Empty(lcUsuario) Or Empty(lcClave)
      This.Token = ""
      Return
    Endif
    If Empty(lcPortal)
      This.Token = ""
      Return
    Endif

    lcBaseUrl = This.GetBaseUrl()

    lcLoginReq = '{'
    lcLoginReq = lcLoginReq + '"request":"sistema_login",'
    lcLoginReq = lcLoginReq + '"data":{'
    lcLoginReq = lcLoginReq + '"app":"ecf",'
    lcLoginReq = lcLoginReq + '"locale":"es",'
    lcLoginReq = lcLoginReq + '"usuario":"' + _JsonEscape(lcUsuario) + '",'
    lcLoginReq = lcLoginReq + '"clave":"' + _JsonEscape(lcClave) + '"'
    lcLoginReq = lcLoginReq + '}}'

    loLogin = This._HttpPostJson(lcBaseUrl + "sistema_login", lcLoginReq, "")
    If !loLogin.ok
      This.Token = ""
      Return
    Endif

    lcToken = Alltrim(Strextract(loLogin.rawBody, '"token":"', '"', 1, 3))
    If Empty(lcToken)
      This.Token = ""
      Return
    Endif

    This.Token = lcToken
  Endproc

  * Al fallar Enviar: imtr.respuesta_mensajes (si hay control), MESSAGEBOX breve, form opcional.
  Procedure _EnviarFin
    Lparameters loResp, tcControl
    Local lcMsg, lcBox
    If Vartype(loResp) = "O" ;
        And !loResp.ok ;
        And !Empty(Nvl(tcControl, ""))
      * Persistir mensaje de error en el documento (imtr o gastos).
      This._DocMarcaErrorEnvio(tcControl, loResp)
    Endif
    If Vartype(loResp) = "O" And !loResp.ok And !_ChalonaEcfUiSilenciada()
      lcMsg = _ChalonaEcfMensajeErrorImtr(loResp)
      lcBox = lcMsg
      If !Empty(Nvl(tcControl, ""))
        lcBox = "Control: " + Alltrim(tcControl) + Chr(13) + Chr(10) + lcBox
      Endif
      Messagebox(lcBox, 16, "Chalona ECF - Error de envio")
    Endif
    If This.MostrarFormularioError ;
        And Vartype(loResp) = "O" ;
        And !loResp.ok ;
        And !_ChalonaEcfUiSilenciada()
      ChalonaMostrarErrorEnvioEcf(loResp, tcControl)
    Endif
    Return loResp
  Endproc

  * Enviar comprobante: usa This.Usuario/Clave/Portal y Token interno
  Procedure Enviar
    Parameters tcControl
    Local lcUsuario, lcClave, lcPortal, lcBaseUrl
    Local lcDocJson, lcRncEmisor
    Local lcSendReq, loOut
    Local loEx
    Local loResp
    Local llVersionDesact

    lcSendReq = ""
    llVersionDesact = .F.
    tcControl = Iif(Vartype(tcControl) = "C", Alltrim(tcControl), "")
    If Empty(tcControl)
      Return This._EnviarFin(ChalonaResponseNew(.F., "control requerido", "", ""), tcControl)
    Endif

    Try
      loResp = ChalonaResponseNew(.F., "error.no_manejado", "", "")

      Do While .T.
        * Hacer login (actualiza This.Token)
        This._Login()
        If Empty(This.Token)
          ChalonaEcfLogError("LOGIN: token vacÃ­o", tcControl, "")
          loResp = ChalonaResponseNew(.F., "login.fallo", "", "")
          Exit
        Endif

        lcUsuario = This.Usuario
        lcClave   = This.Clave
        lcPortal  = This._PortalActual()

        If Empty(lcUsuario) Or Empty(lcClave)
          loResp = ChalonaResponseNew(.F., "usuario/clave requeridos", "", "")
          Exit
        Endif
        If Empty(lcPortal)
          loResp = ChalonaResponseNew(.F., "portal requerido", "", "")
          Exit
        Endif

        lcBaseUrl = This.GetBaseUrl()

        * Path SQL Server: poblar cursores rigid via Request a dbo.imtr/gastos/etc.
        This.CrearCursores()
        This._PoblarCursoresDesdeImtr(tcControl)

        * Armar JSON desde cursores ya poblados.
        lcDocJson = ChalonaEcfBuildDocJsonFox(tcControl, This.Cfg)
        If Isnull(lcDocJson)
          ChalonaEcfLogError("JSON: ChalonaEcfBuildDocJsonFox devolviÃ³ .Null.", tcControl, "")
          If Type("gcChalonaEcfBuildDocError") = "C" And !Empty(Alltrim(Nvl(gcChalonaEcfBuildDocError, "")))
            loResp = ChalonaResponseNew(.F., gcChalonaEcfBuildDocError, "", "")
          Else
            loResp = ChalonaResponseNew(.F., "sql.ecf2json.error", "", "")
          Endif
          If Type("gcChalonaEcfLastException") = "C" And !Empty(Alltrim(Nvl(gcChalonaEcfLastException, "")))
            loData = Createobject("Empty")
            AddProperty(loData, "detail", gcChalonaEcfLastException)
            loResp.data = loData
          Endif
          Exit
        Endif
        If Empty(lcDocJson)
          ChalonaEcfLogError("JSON: documento vacÃ­o", tcControl, "")
          loResp = ChalonaResponseNew(.F., "ecf2json.vacio", "", "")
          Exit
        Endif
        ChalonaEcfSaveUltimoJson(tcControl, lcDocJson)

        lcRncEmisor = Alltrim(Strextract(lcDocJson, '"RNCEmisor":"', '"', 1, 3))
        If Empty(lcRncEmisor)
          loResp = ChalonaResponseNew(.F., "json.sin_rnc_emisor", "", lcDocJson)
          Exit
        Endif

        * --- envia_ecf: cuerpo DIRECTO (sin wrapper "data") ---
        * Evitar TEXTMERGE para lcDocJson: puede truncar expansiones largas (~4096).
        * Construir el body con concatenaciÃ³n, preservando lcDocJson (memo) sin ALLTRIM/NVL.
        lcSendReq = ;
          '{"locale":"es","rnc":"' + _JsonEscape(lcRncEmisor) + ;
          '","portal":"' + _JsonEscape(lcPortal) + ;
          '","json":' + lcDocJson + ;
          '}'

        loOut = This._HttpPostJson(lcBaseUrl + "envia_ecf", lcSendReq, This.Token)
        If Vartype(loOut) # "O"
          ChalonaEcfLogError("HTTP: _HttpPostJson devolviÃ³ no-objeto", tcControl, lcBaseUrl + "envia_ecf")
          loResp = ChalonaResponseNew(.F., "http.error", "", "")
          Exit
        Endif

        * Si es version_desactualizada, marcar y salir: el loader hace retry transparente
        * (no Return dentro de TRY: VFP error 2060). Se salta _EnviarFin afuera del Try.
        If PemStatus(loOut, "ok", 5) And !loOut.ok ;
            And Atc('"fox_cliente.version_desactualizada"', Nvl(loOut.rawBody, "")) > 0
          llVersionDesact = .T.
          loResp = loOut
          Exit
        Endif

        If PemStatus(loOut, "ok", 5) And !loOut.ok
          ChalonaEcfLogError("HTTP: envia_ecf ok=.F.", tcControl, lcBaseUrl + "envia_ecf")
        Endif

        loResp = loOut
        If loOut.ok And Vartype(loOut.data) = "O"
          This._DocSyncRespuestaEnvio(tcControl, loOut.data)
        Endif
        Exit
      Enddo
    Catch To loEx
      ChalonaEcfLogException("UNHANDLED: Enviar", tcControl, loEx, "")
      loResp = ChalonaResponseNew(.F., "error.no_manejado", "", "")
    Endtry
    * Adjuntar al objeto de error el JSON/cuerpo que se envio a envia_ecf (si ya se armo).
    If Vartype(loResp) = "O" ;
        And PemStatus(loResp, "requestBody", 5) ;
        And Empty(Alltrim(Nvl(loResp.requestBody, ""))) ;
        And Not Empty(Nvl(lcSendReq, ""))
      loResp.requestBody = lcSendReq
    Endif
    * version_desactualizada: bypass _EnviarFin (sin Messagebox/persist). Loader reintenta.
    If llVersionDesact
      Return loResp
    Endif
    Return This._EnviarFin(loResp, tcControl)
  Endproc

  * Determinar origen del control: imtr / gastos / ambiguous / "".
  * Delega el conteo al driver (ContarOrigen).
  Function _DocOrigen
    Lparameters tcControl
    Local loRes, lnImtr, lnGastos
    tcControl = Iif(Vartype(tcControl) = "C", Alltrim(tcControl), "")
    If Empty(tcControl)
      Return ""
    Endif
    loRes = This._ContarOrigen(tcControl)
    lnImtr = 0 + Nvl(loRes.imtr, 0)
    lnGastos = 0 + Nvl(loRes.gastos, 0)
    If (lnImtr + lnGastos) > 1
      ChalonaEcfLogError("ECF: control duplicado en imtr/gastos", tcControl, "c_imtr=" + Transform(lnImtr) + ", c_gastos=" + Transform(lnGastos))
      Return "ambiguous"
    Endif
    If lnImtr = 1
      Return "imtr"
    Endif
    If lnGastos = 1
      Return "gastos"
    Endif
    Return ""
  Endfunc

  * Tras envia_ecf exitoso: persistir respuesta DGII en imtr o gastos (según el control).
  * Delega la persistencia al driver (GuardarRespuestaEnvio).
  Procedure _DocSyncRespuestaEnvio
    Lparameters tcControl, loData
    Local lcOrigen, llEsGastos
    lcOrigen = This._DocOrigen(tcControl)
    Do Case
    Case lcOrigen == "ambiguous"
      ChalonaEcfLogError("ECF: no se puede sincronizar respuesta; control ambiguo", tcControl, "")
      Return
    Case lcOrigen == "gastos"
      llEsGastos = .T.
    Otherwise
      * imtr o "" (no identificado) -> imtr por compatibilidad.
      llEsGastos = .F.
    Endcase
    This._GuardarRespuestaEnvio(tcControl, loData, llEsGastos)
  Endproc

  * Error de envio: persistir respuesta_mensajes en imtr o gastos.
  * Delega la persistencia al driver (MarcarErrorEnvio).
  Procedure _DocMarcaErrorEnvio
    Lparameters tcControl, loResp
    Local lcOrigen, llEsGastos, lcMsg
    lcOrigen = This._DocOrigen(tcControl)
    Do Case
    Case lcOrigen == "ambiguous"
      ChalonaEcfLogError("ECF: no se puede marcar error; control ambiguo", tcControl, "")
      Return
    Case lcOrigen == "gastos"
      llEsGastos = .T.
    Otherwise
      llEsGastos = .F.
    Endcase
    lcMsg = _ChalonaEcfMensajeErrorImtr(loResp)
    If Empty(Alltrim(Nvl(lcMsg, "")))
      Return
    Endif
    This._MarcarErrorEnvio(tcControl, lcMsg, llEsGastos)
  Endproc


  * Consultar estado de comprobantes por e-NCF (consulta_estado).
  * tcComprobantesJson debe venir como JSON de arreglo: ["E31...","E31..."]
  Procedure ConsultarEstado
    Lparameters tcComprobantesJson
    Local lcComprobantesJson, lcBaseUrl
    Local lcReq, loOut

    * Normalizar JSON de comprobantes (espera algo como ["E31...","E31..."])
    lcComprobantesJson = Iif(Vartype(tcComprobantesJson) = "C", Alltrim(tcComprobantesJson), "")
    If Empty(lcComprobantesJson)
      Return ChalonaResponseNew(.F., "comprobantes_requeridos", "", "")
    Endif

    * Hacer login (actualiza This.Token)
    This._Login()
    If Empty(This.Token)
      Return ChalonaResponseNew(.F., "login.fallo", "", "")
    Endif

    lcBaseUrl = This.GetBaseUrl()

    * Llamar consulta_estado vÃƒÆ’Ã‚Â­a contrato estÃƒÆ’Ã‚Â¡ndar (request+data) en la raÃƒÆ’Ã‚Â­z
    * data.comprobantes: JSON de arreglo con e-NCF (ya viene armado)
    lcReq = '{'
    lcReq = lcReq + '"request":"consulta_estado",'
    lcReq = lcReq + '"data":{'
    lcReq = lcReq + '"locale":"es",'
    lcReq = lcReq + '"comprobantes":' + lcComprobantesJson
    lcReq = lcReq + '}}'

    * Para funciones genÃƒÆ’Ã‚Â©ricas usamos la raÃƒÆ’Ã‚Â­z como endpoint HTTP y request en el body
    loOut = This._HttpPostJson(lcBaseUrl, lcReq, This.Token)
    Return loOut
  Endproc

  * ConsultaApi(tcRequest, tcDataJson) -> ChalonaResponse
  *
  * Macro genérica para invocar cualquier endpoint del servidor ECF sin necesidad
  * de recompilar el loader. Permite que aparezcan funciones nuevas en el motor
  * dinámico (este script publicado en data.fox_cliente_script) y que cualquier
  * ERP las invoque vía chalonaConsultaApi() sin tocar su .prg local.
  *
  *   tcRequest   : Nombre del endpoint registrado en server-ecf
  *                 (ej: "ecf_anular_rangos", "ecf_anular_rangos_lista",
  *                 "consulta_estado", "ecf_registro_select", etc.).
  *   tcDataJson  : Objeto JSON con los parámetros del endpoint. Vacío => "{}".
  *                 Si pasa una cadena vacía o "{}", se manda data:{"locale":"es"}.
  *                 El campo "locale" se agrega si no viene.
  *
  * Respuesta: ChalonaResponse (.ok, .message, .data, .rawBody).
  Procedure ConsultaApi
    Lparameters tcRequest, tcDataJson
    Local lcRequest, lcDataJson, lcBaseUrl, lcReq, loOut, lcDataInner

    lcRequest  = Iif(Vartype(tcRequest)  = "C", Alltrim(tcRequest),  "")
    lcDataJson = Iif(Vartype(tcDataJson) = "C", Alltrim(tcDataJson), "")

    If Empty(lcRequest)
      Return ChalonaResponseNew(.F., "err.consulta_api.request_requerido", "", "")
    Endif

    This._Login()
    If Empty(This.Token)
      Return ChalonaResponseNew(.F., "login.fallo", "", "")
    Endif

    lcBaseUrl = This.GetBaseUrl()

    * Permitir tcDataJson vacío o un objeto JSON ya armado. Se inyecta locale="es"
    * si no viene en el JSON original.
    If Empty(lcDataJson) Or lcDataJson == "{}"
      lcDataInner = '"locale":"es"'
    Else
      * Quitar { y } extremos para poder concatenar locale si falta.
      Local lcTrim
      lcTrim = lcDataJson
      If Left(lcTrim, 1) = "{"
        lcTrim = Substr(lcTrim, 2)
      Endif
      If Right(lcTrim, 1) = "}"
        lcTrim = Left(lcTrim, Len(lcTrim) - 1)
      Endif
      lcTrim = Alltrim(lcTrim)
      If Atc('"locale"', lcTrim) = 0
        If Empty(lcTrim)
          lcDataInner = '"locale":"es"'
        Else
          lcDataInner = '"locale":"es",' + lcTrim
        Endif
      Else
        lcDataInner = lcTrim
      Endif
    Endif

    lcReq = '{"request":"' + _JsonEscape(lcRequest) + '","data":{' + lcDataInner + '}}'

    loOut = This._HttpPostJson(lcBaseUrl, lcReq, This.Token)
    Return loOut
  Endproc

  * AnularRangos(tcTipo, tcRangosJson) -> ChalonaResponse
  *
  * Anula rangos de e-NCF no utilizados ante la DGII (servicio AnulacionECF).
  *   tcTipo        : TipoeCF DGII como string. Ej "31", "32", "33", "34", "41", "43"..."47".
  *   tcRangosJson  : JSON array de rangos. Ej:
  *                   '[{"desde":"1","hasta":"10"},{"desde":"25","hasta":"25"}]'
  *
  * Una llamada = un XML ANECF firmado = un TipoeCF. Para anular varios tipos,
  * llamar este metodo una vez por tipo.
  *
  * El servidor valida primero contra data.ecf (NCF emitido / pendiente) y
  * data.ecf_anulacion (rangos ya anulados); si hay conflictos no recuperables,
  * la llamada falla antes de enviar a DGII.
  *
  * Respuesta exitosa (loResp.data): { id, estado, codigo, cantidad,
  *   rangos_anulados:[...], rangos_rechazados:[...], mensajes:[...] }.
  * estado: "Aceptado" | "Aceptado Parcial" | "Rechazado" | "Error".
  Procedure AnularRangos
    Lparameters tcTipo, tcRangosJson
    Local lcTipo, lcRangos, lcBaseUrl, lcReq, loOut

    lcTipo   = Iif(Vartype(tcTipo) = "C", Alltrim(tcTipo), "")
    lcRangos = Iif(Vartype(tcRangosJson) = "C", Alltrim(tcRangosJson), "")

    If Empty(lcTipo)
      Return ChalonaResponseNew(.F., "err.ecf_anulacion.tipo_no_soportado", "", "")
    Endif
    If Empty(lcRangos)
      Return ChalonaResponseNew(.F., "err.ecf_anulacion.rangos_requeridos", "", "")
    Endif

    This._Login()
    If Empty(This.Token)
      Return ChalonaResponseNew(.F., "login.fallo", "", "")
    Endif

    lcBaseUrl = This.GetBaseUrl()

    lcReq = '{'
    lcReq = lcReq + '"request":"ecf_anular_rangos",'
    lcReq = lcReq + '"data":{'
    lcReq = lcReq + '"locale":"es",'
    lcReq = lcReq + '"portal":"' + _JsonEscape(This._PortalActual()) + '",'
    lcReq = lcReq + '"tipo":"' + _JsonEscape(lcTipo) + '",'
    lcReq = lcReq + '"rangos":' + lcRangos
    lcReq = lcReq + '}}'

    loOut = This._HttpPostJson(lcBaseUrl, lcReq, This.Token)
    Return loOut
  Endproc

  * AnularRangosArr(tcTipo, taRangos) -> ChalonaResponse
  *
  * Variante que recibe un array Fox 2D: taRangos(N, 2). Cada fila = (desde, hasta).
  * Lo serializa a JSON y delega en AnularRangos().
  *   DIMENSION laRangos(2, 2)
  *   laRangos(1,1) = "1"
  *   laRangos(1,2) = "10"
  *   laRangos(2,1) = "25"
  *   laRangos(2,2) = "25"
  *   loResp = goChalonaEcf.AnularRangosArr("31", @laRangos)
  Procedure AnularRangosArr
    Lparameters tcTipo, taRangos
    Local lnFilas, lnI, lcJson, lcDesde, lcHasta

    If Vartype(taRangos) # "A"
      Return ChalonaResponseNew(.F., "err.ecf_anulacion.rangos_requeridos", "", "")
    Endif

    lnFilas = Alen(taRangos, 1)
    If lnFilas <= 0
      Return ChalonaResponseNew(.F., "err.ecf_anulacion.rangos_requeridos", "", "")
    Endif

    lcJson = "["
    For lnI = 1 To lnFilas
      lcDesde = Transform(Iif(Vartype(taRangos(lnI, 1)) = "C", Alltrim(taRangos(lnI, 1)), Transform(taRangos(lnI, 1))))
      lcHasta = Transform(Iif(Vartype(taRangos(lnI, 2)) = "C", Alltrim(taRangos(lnI, 2)), Transform(taRangos(lnI, 2))))
      If lnI > 1
        lcJson = lcJson + ","
      Endif
      lcJson = lcJson + '{"desde":"' + _JsonEscape(lcDesde) + '","hasta":"' + _JsonEscape(lcHasta) + '"}'
    Endfor
    lcJson = lcJson + "]"

    Return This.AnularRangos(tcTipo, lcJson)
  Endproc

  * Recuperar estados "En Proceso" en imtr. Candado = una instancia activa por vez;
  * no es proceso residente: una llamada, sync o salida inmediata si el lock esta ocupado.
  * al salir (exito o fallo intermedio) se libera el candado para la proxima corrida.
  * 1) chalona_ecf_sync_estados_mutex_try (LockTimeout 0, sin espera). lock_result < 0 -> omitido_por_mutex.
  * 2) chalona_imtr_list_encf_en_proceso -> curChalonaEncfEnProceso
  * 3) Lotes de 100 e-NCF a consulta_estado; chalona_imtr_sync_respuesta_envio por fila.
  * 4) chalona_ecf_sync_estados_mutex_release si se obtuvo candado (siempre antes del Return).
  *    DO WHILE .T. ... EXIT: VFP no permite RETURN dentro de TRY/FINALLY (error 2060).
  Function SincronizarEstadosEnProceso
    Local lcCur, lnTot, lnI, lnStart, lnEnd, j, k
    Local lcJson, loRet, loData, loResult, loItem
    Local lcNum, tcCtrl, lnUpd, loFinal, loSum
    Local laEncf, laCtrl
    Local llGotLock, lnLockRes
    Local llAbortSync

    lcCur = "curChalonaEncfEnProceso"
    llGotLock = .F.

    * Candado (mutex) delegado al driver.
    lnLockRes = This._SyncIntentarLock()
    If lnLockRes = -99
      Return ChalonaResponseNew(.F., "sql.chalona_ecf_sync_estados_mutex_try.error", "", "")
    Endif
    If lnLockRes < 0
      loFinal = Createobject("ChalonaResponse")
      loFinal.ok = .T.
      loFinal.message = ""
      loFinal.rawBody = ""
      loSum = Createobject("Empty")
      AddProperty(loSum, "consultados", 0)
      AddProperty(loSum, "sincronizados", 0)
      AddProperty(loSum, "omitido_por_mutex", .T.)
      AddProperty(loSum, "lock_result", lnLockRes)
      loFinal.data = loSum
      Return loFinal
    Endif
    llGotLock = .T.

    Do While .T.
    * Listado de pendientes "en proceso" (delegado al driver).
    lcCur = This._SyncListarPendientes()
    If Empty(Alltrim(lcCur))
      loFinal = ChalonaResponseNew(.F., "sql.chalona_imtr_list_encf_en_proceso.error", "", "")
      Exit
    Endif
    If !Used(lcCur)
      loFinal = ChalonaResponseNew(.F., "sql.cursor.no_existe", lcCur, "")
      Exit
    Endif

    * Validar: no debe venir el mismo control en imtr y gastos (delegado al driver).
    Local lcCurDup
    lcCurDup = This._SyncListarDuplicados()
    If Empty(Alltrim(lcCurDup))
      loFinal = ChalonaResponseNew(.F., "sql.chalona_ecf_list_duplicados_en_proceso.error", "", "")
      Exit
    Endif
    If Used(lcCurDup) And Reccount(lcCurDup) > 0
      Select (lcCurDup)
      Go Top
      loFinal = ChalonaResponseNew(.F., "ecf.control_duplicado_en_imtr_y_gastos", Alltrim(Transform(control)), "")
      Exit
    Endif

    Select (lcCur)
    lnTot = Reccount()
    If lnTot < 1
      loFinal = Createobject("ChalonaResponse")
      loFinal.ok = .T.
      loFinal.message = ""
      loFinal.rawBody = ""
      loSum = Createobject("Empty")
      AddProperty(loSum, "consultados", 0)
      AddProperty(loSum, "sincronizados", 0)
      AddProperty(loSum, "omitido_por_mutex", .F.)
      loFinal.data = loSum
      Exit
    Endif

    Dimension laEncf[lnTot], laCtrl[lnTot]
    lnI = 0
    Scan
      lnI = lnI + 1
      laEncf[lnI] = Alltrim(Transform(encf))
      laCtrl[lnI] = Alltrim(Transform(control))
    Endscan

    lnUpd = 0
    llAbortSync = .F.
    For lnStart = 1 To lnTot Step 100
      lnEnd = Min(lnStart + 99, lnTot)
      lcJson = "["
      For j = lnStart To lnEnd
        If j > lnStart
          lcJson = lcJson + ","
        Endif
        lcJson = lcJson + '"' + _JsonEscape(laEncf[j]) + '"'
      Endfor
      lcJson = lcJson + "]"

      loRet = This.ConsultarEstado(lcJson)
      If !loRet.ok
        loFinal = loRet
        llAbortSync = .T.
        Exit
      Endif

      loData = loRet.data
      If Vartype(loData) # "O" Or !PemStatus(loData, "result", 5)
        Loop
      Endif
      loResult = loData.result
      If Vartype(loResult) # "O"
        Loop
      Endif

      For k = 1 To loResult.Count
        loItem = loResult.Item(k)
        If Vartype(loItem) # "O"
          Loop
        Endif
        lcNum = ""
        If PemStatus(loItem, "numero", 5)
          lcNum = Alltrim(Transform(loItem.numero))
        Endif
        If Empty(lcNum)
          Loop
        Endif

        * Localizar fila en cursor por encf y rellenar campos de respuesta.
        * El driver decide al final, en SyncFinalizar(), que hacer con esos datos.
        Select (lcCur)
        Locate For Upper(Alltrim(encf)) == Upper(lcNum)
        If Found()
          Replace ;
            numero               With lcNum, ;
            estado               With Left(Alltrim(Transform(Iif(PemStatus(loItem, "estado", 5), loItem.estado, ""))), 200), ;
            estado_descripcion   With Left(Alltrim(Transform(Iif(PemStatus(loItem, "estado_descripcion", 5), loItem.estado_descripcion, ""))), 500), ;
            codigo_seguridad     With Left(Alltrim(Transform(Iif(PemStatus(loItem, "codigo_seguridad", 5), loItem.codigo_seguridad, ""))), 200), ;
            fecha_firma          With Left(Alltrim(Transform(Iif(PemStatus(loItem, "fecha_firma", 5), loItem.fecha_firma, ""))), 100), ;
            timbre               With Alltrim(Transform(Iif(PemStatus(loItem, "timbre", 5), loItem.timbre, ""))), ;
            secuencia_utilizada  With Iif(PemStatus(loItem, "secuencia_utilizada", 5) And loItem.secuencia_utilizada, 1, 0), ;
            momento              With Left(Alltrim(Transform(Iif(PemStatus(loItem, "momento", 5), loItem.momento, ""))), 50)
          lnUpd = lnUpd + 1
        Endif
      Next k
    Next lnStart

    If llAbortSync
      Exit
    Endif

    * Persistencia de los resultados del cursor en dbo.imtr/dbo.gastos.
    This._SyncFinalizar()

    loFinal = Createobject("ChalonaResponse")
    loFinal.ok = .T.
    loFinal.message = ""
    loFinal.rawBody = ""
    loSum = Createobject("Empty")
    AddProperty(loSum, "consultados", lnTot)
    AddProperty(loSum, "sincronizados", lnUpd)
    AddProperty(loSum, "omitido_por_mutex", .F.)
    loFinal.data = loSum
    Exit
    Enddo

    If llGotLock
      This._SyncLiberarLock()
    Endif
    Return loFinal
  Endfunc

  * Descargar documentos ECF por rango de fechas (ecf_documentos_list).
  * tcFechaDesde, tcFechaHasta: "YYYY-MM-DD" (obligatorias).
  * tcTiposJson: JSON array opcional, p. ej. '["31","32","34"]'. Vacio = todos los tipos.
  * Abre dialogo GETFILE('zip') para elegir destino; si el usuario cancela, retorna ok=.T., message="cancelado".
  * Al terminar bien, guarda un ZIP con el JSON de los documentos y retorna ok=.T.
  Procedure DescargarDocumentos
    Lparameters tcFechaDesde, tcFechaHasta, tcTiposJson
    Local lcFechaDesde, lcFechaHasta, lcTiposJson, lcBaseUrl
    Local lcReq, loOut
    Local lcZipPath, lcTempResp, lcTempPs1
    Local lnH, loShell, lcQ

    * Pedir destino antes de consultar; si cancela, salir sin llamar al API
    lcZipPath = Getfile('zip', 'Guardar documentos ECF')
    If Empty(Alltrim(lcZipPath))
      Return ChalonaResponseNew(.T., "cancelado", "", "")
    Endif
    If Lower(Right(Alltrim(lcZipPath), 4)) # ".zip"
      lcZipPath = Alltrim(lcZipPath) + ".zip"
    Endif

    lcFechaDesde = Iif(Vartype(tcFechaDesde) = "C", Alltrim(tcFechaDesde), "")
    lcFechaHasta = Iif(Vartype(tcFechaHasta) = "C", Alltrim(tcFechaHasta), "")
    lcTiposJson  = Iif(Vartype(tcTiposJson)  = "C", Alltrim(tcTiposJson),  "")

    If Empty(lcFechaDesde)
      Return ChalonaResponseNew(.F., "err.ecf_documentos.fecha_desde_requerida", "", "")
    Endif
    If Empty(lcFechaHasta)
      Return ChalonaResponseNew(.F., "err.ecf_documentos.fecha_hasta_requerida", "", "")
    Endif

    This._Login()
    If Empty(This.Token)
      Return ChalonaResponseNew(.F., "login.fallo", "", "")
    Endif

    lcBaseUrl = This.GetBaseUrl()

    lcReq = '{'
    lcReq = lcReq + '"request":"ecf_documentos_list",'
    lcReq = lcReq + '"data":{'
    lcReq = lcReq + '"locale":"es",'
    lcReq = lcReq + '"fecha_desde":"' + _JsonEscape(lcFechaDesde) + '",'
    lcReq = lcReq + '"fecha_hasta":"' + _JsonEscape(lcFechaHasta) + '"'
    If !Empty(lcTiposJson)
      lcReq = lcReq + ',"tipos":' + lcTiposJson
    Endif
    lcReq = lcReq + '}}'

    loOut = This._HttpPostJson(lcBaseUrl, lcReq, This.Token)
    If Vartype(loOut) # "O" Or !loOut.ok
      Return loOut
    Endif

    * El servidor devuelve el ZIP en files[0].content (base64).
    * Guardar el rawBody en un archivo temporal y decodificar con PowerShell.
    lcTempResp = Addbs(Sys(2023)) + "chalona_ecf_resp.json"
    lnH = Fcreate(lcTempResp)
    If lnH < 0
      Return ChalonaResponseNew(.F., "err.ecf_documentos.error_archivo_temp", "", "")
    Endif
    Fwrite(lnH, loOut.rawBody)
    Fclose(lnH)

    * Script PowerShell: lee el JSON de respuesta, extrae files[0].content (base64) y lo escribe como ZIP
    lcTempPs1 = Addbs(Sys(2023)) + "chalona_ecf_zip.ps1"
    lnH = Fcreate(lcTempPs1)
    Fputs(lnH, "$resp = Get-Content -Raw -Path '" + lcTempResp + "' | ConvertFrom-Json")
    Fputs(lnH, "$b64  = $resp.files[0].content")
    Fputs(lnH, "$zip  = '" + lcZipPath + "'")
    Fputs(lnH, "$bytes = [System.Convert]::FromBase64String($b64)")
    Fputs(lnH, "[System.IO.File]::WriteAllBytes($zip, $bytes)")
    Fclose(lnH)

    lcQ = Chr(34)
    loShell = Createobject("WScript.Shell")
    loShell.Run("powershell -NoProfile -ExecutionPolicy Bypass -File " + lcQ + lcTempPs1 + lcQ, 0, .T.)

    * Limpiar temporales
    If File(lcTempResp)
      Erase (lcTempResp)
    Endif
    If File(lcTempPs1)
      Erase (lcTempPs1)
    Endif

    Return loOut
  Endproc

  * HTTP POST JSON -> ChalonaResponse. Mismo patron que cliente ERP: MSXML2.XMLHTTP, open sync, send, responseText.
  * Sin Try/Catch aqui (evita diferencias de runtime); sin filtrar status HTTP: el JSON trae ok true/false.
  Procedure _HttpPostJson
    Lparameters tcUrl, tcBody, tcToken
    Local loHttp, lcResp, lcT, lcBody, lnLastBrace
    * Inyectar fox_version + fox_entorno cuando el loader los tiene (validacion de version)
    lcBody = Nvl(tcBody, "")
    If Type("gcChalonaFoxVersion") = "N" And gcChalonaFoxVersion > 0 ;
        And Type("gcChalonaFoxEntorno") = "C"
      lnLastBrace = Rat("}", lcBody)
      If lnLastBrace > 0
        lcBody = Left(lcBody, lnLastBrace - 1) + ;
          ',"fox_version":' + Transform(Int(gcChalonaFoxVersion)) + ;
          ',"fox_entorno":"' + gcChalonaFoxEntorno + '"}'
      Endif
    Endif
    lcT = Alltrim(Nvl(tcToken, ""))
    loHttp = Createobject("MSXML2.XMLHTTP")
    loHttp.open("POST", tcUrl, .F.)
    loHttp.setRequestHeader("Content-Type", "application/json")
    If !Empty(lcT)
      If Lower(Left(lcT, 7)) = "bearer "
        loHttp.setRequestHeader("Authorization", lcT)
      Else
        loHttp.setRequestHeader("Authorization", "Bearer " + lcT)
      Endif
    Endif
	TRY
	    loHttp.send(lcBody)
    CATCH WHEN .t.
    ENDTRY
    lcResp = ""
    If Vartype(loHttp.responseText) = "C"
      lcResp = loHttp.responseText
    Endif
    loHttp = .Null.
    Return ChalonaResponseFromApiBody(lcResp)
  Endproc

  *==========================================================================
  * Capa de cursores publica (nueva mecanica para integradores no-SqlServer).
  *==========================================================================

  * Crea TODOS los cursores vacios con shape rigido. Ver SCHEMA-CURSORES.md.
  * Llamar antes de EnviarDesdeCursores / SincronizarDesdeCursor /
  * DescargarDocumentosACursor cuando el integrador llena los cursores el mismo.
  Procedure CrearCursores
    ChalonaEcfUseInIfUsed("curChalMae")
    Create Cursor curChalMae ;
      (fiscal              C(2), ;
       encf                C(20), ;
       ncf                 C(20), ;
       control             C(40), ;
       fecha               D, ;
       valor               N(18,2), ;
       descuento           N(18,2), ;
       itbis               N(18,2), ;
       total               N(18,2), ;
       tasa                N(18,4), ;
       moneda              C(10), ;
       rnc                 C(20), ;
       nombre              C(150), ;
       entidad             C(20), ;
       ocontrol            C(40), ;
       fechavencencf       D, ;
       dgii_codmod         N(2), ;
       itbisr              N(18,2), ;
       isr                 N(18,2), ;
       propina             N(18,2), ;
       diascr              N(5,0), ;
       comentario          C(200), ;
       referencia          C(40), ;
       doc                 C(40), ;
       numero              C(40), ;
       estado              C(200), ;
       estado_descripcion  M, ;
       codigo_seguridad    C(200), ;
       fecha_firma         C(100), ;
       timbre              M, ;
       secuencia_utilizada N(1), ;
       momento             C(50), ;
       respuesta_mensajes  M)

    ChalonaEcfUseInIfUsed("curChalDet")
    Create Cursor curChalDet ;
      (precio         N(18,6), ;
       cantidad       N(18,4), ;
       descrip        C(200), ;
       mercs_nombre   C(200), ;
       mercs_servicio N(2), ;
       itbis          N(18,2), ;
       itbis_tasa     N(5,2), ;
       itbis_retenido N(18,2), ;
       isr_retenido   N(18,2))

    ChalonaEcfUseInIfUsed("curChalEmp")
    Create Cursor curChalEmp ;
      (rnc       C(20), ;
       nombre    C(150), ;
       direccion C(200), ;
       iprecio   N(1))

    ChalonaEcfUseInIfUsed("curChalCli")
    Create Cursor curChalCli ;
      (extranjero_flag N(1), ;
       rnc             C(20), ;
       nombre          C(150))

    ChalonaEcfUseInIfUsed("curChalRef")
    Create Cursor curChalRef ;
      (encf  C(20), ;
       fecha D)

    ChalonaEcfUseInIfUsed("curChalFis")
    Create Cursor curChalFis (vence D)

    ChalonaEcfUseInIfUsed("curChalSup")
    Create Cursor curChalSup ;
      (rnc    C(20), ;
       nombre C(150))

    ChalonaEcfUseInIfUsed("curChalonaEncfEnProceso")
    Create Cursor curChalonaEncfEnProceso ;
      (control             C(40), ;
       encf                C(20), ;
       es_gastos           L, ;
       numero              C(20), ;
       estado              C(200), ;
       estado_descripcion  M, ;
       codigo_seguridad    C(200), ;
       fecha_firma         C(100), ;
       timbre              M, ;
       secuencia_utilizada N(1), ;
       momento             C(50))

    ChalonaEcfUseInIfUsed("curChalDescarga")
    Create Cursor curChalDescarga (zip_path C(254))
  Endproc

  *--------------------------------------------------------------------------
  * Lee cursores ya poblados (curChalMae, curChalDet, curChalEmp, ...),
  * arma el JSON DGII, lo envia a /envia_ecf y reescribe curChalMae con la
  * respuesta (encf, estado, codigo_seguridad, fecha_firma, timbre, ...).
  * No persiste en BD del cliente -> integrador lee curChalMae y guarda el mismo.
  Procedure EnviarDesdeCursores
    Lparameters tcControl
    Local lcUsuario, lcClave, lcPortal, lcBaseUrl
    Local lcDocJson, lcRncEmisor, lcSendReq, loOut, loEx, loResp, loData
    Local llVersionDesact

    lcSendReq = ""
    llVersionDesact = .F.
    tcControl = Iif(Vartype(tcControl) = "C", Alltrim(tcControl), "")
    If Empty(tcControl)
      Return ChalonaResponseNew(.F., "control requerido", "", "")
    Endif

    Try
      loResp = ChalonaResponseNew(.F., "error.no_manejado", "", "")
      Do While .T.
        This._Login()
        If Empty(This.Token)
          ChalonaEcfLogError("LOGIN: token vacio (cursores)", tcControl, "")
          loResp = ChalonaResponseNew(.F., "login.fallo", "", "")
          Exit
        Endif
        lcUsuario = This.Usuario
        lcClave   = This.Clave
        lcPortal  = This._PortalActual()
        If Empty(lcUsuario) Or Empty(lcClave) Or Empty(lcPortal)
          loResp = ChalonaResponseNew(.F., "credenciales.requeridas", "", "")
          Exit
        Endif
        lcBaseUrl = This.GetBaseUrl()

        lcDocJson = ChalonaEcfBuildDocJsonFox(tcControl, This.Cfg)
        If Isnull(lcDocJson)
          If Type("gcChalonaEcfBuildDocError") = "C" And !Empty(Alltrim(Nvl(gcChalonaEcfBuildDocError, "")))
            loResp = ChalonaResponseNew(.F., gcChalonaEcfBuildDocError, "", "")
          Else
            loResp = ChalonaResponseNew(.F., "ecf.build.error", "", "")
          Endif
          Exit
        Endif
        If Empty(lcDocJson)
          loResp = ChalonaResponseNew(.F., "ecf.build.vacio", "", "")
          Exit
        Endif
        ChalonaEcfSaveUltimoJson(tcControl, lcDocJson)

        lcRncEmisor = Alltrim(Strextract(lcDocJson, '"RNCEmisor":"', '"', 1, 3))
        If Empty(lcRncEmisor)
          loResp = ChalonaResponseNew(.F., "json.sin_rnc_emisor", "", lcDocJson)
          Exit
        Endif

        lcSendReq = ;
          '{"locale":"es","rnc":"' + _JsonEscape(lcRncEmisor) + ;
          '","portal":"' + _JsonEscape(lcPortal) + ;
          '","json":' + lcDocJson + ;
          '}'

        loOut = This._HttpPostJson(lcBaseUrl + "envia_ecf", lcSendReq, This.Token)
        If Vartype(loOut) # "O"
          loResp = ChalonaResponseNew(.F., "http.error", "", "")
          Exit
        Endif

        If PemStatus(loOut, "ok", 5) And !loOut.ok ;
            And Atc('"fox_cliente.version_desactualizada"', Nvl(loOut.rawBody, "")) > 0
          llVersionDesact = .T.
          loResp = loOut
          Exit
        Endif

        loResp = loOut
        If loOut.ok And Vartype(loOut.data) = "O"
          This._ActualizarCurChalMaeConRespuesta(loOut.data)
        Endif
        Exit
      Enddo
    Catch To loEx
      ChalonaEcfLogException("UNHANDLED: EnviarDesdeCursores", tcControl, loEx, "")
      loResp = ChalonaResponseNew(.F., "error.no_manejado", "", "")
    Endtry

    If Vartype(loResp) = "O" ;
        And PemStatus(loResp, "requestBody", 5) ;
        And Empty(Alltrim(Nvl(loResp.requestBody, ""))) ;
        And Not Empty(Nvl(lcSendReq, ""))
      loResp.requestBody = lcSendReq
    Endif

    * UI de error: form con boton copiar + Messagebox breve. Se omite en
    * version_desactualizada (loader hace retry transparente) y cuando
    * glChalonaEcfSilenciarUi=.T. (modo debug, sin popups).
    If Vartype(loResp) = "O" And !loResp.ok And !llVersionDesact And !_ChalonaEcfUiSilenciada()
      Local lcMsg, lcBox
      lcMsg = _ChalonaEcfMensajeErrorImtr(loResp)
      lcBox = lcMsg
      If !Empty(Nvl(tcControl, ""))
        lcBox = "Control: " + Alltrim(tcControl) + Chr(13) + Chr(10) + lcBox
      Endif
      Messagebox(lcBox, 16, "Chalona ECF - Error de envio")
    Endif
    If This.MostrarFormularioError ;
        And Vartype(loResp) = "O" ;
        And !loResp.ok ;
        And !llVersionDesact ;
        And !_ChalonaEcfUiSilenciada()
      ChalonaMostrarErrorEnvioEcf(loResp, tcControl)
    Endif

    Return loResp
  Endproc

  *--------------------------------------------------------------------------
  * Toma curChalonaEncfEnProceso (que el integrador lleno con control+encf+es_gastos),
  * consulta DGII en lotes de 100 y reescribe el mismo cursor con estado
  * actualizado. No persiste en BD del cliente. Sin lock (integrador maneja
  * concurrencia el mismo si aplica).
  Function SincronizarDesdeCursor
    Local lcCur, lnTot, lnI, lnStart, lnEnd, j, k
    Local lcJson, loRet, loData, loResult, loItem, lcNum, lnUpd
    Local laEncf, laCtrl
    Local loFinal, loSum

    lcCur = "curChalonaEncfEnProceso"
    If !Used(lcCur)
      Return ChalonaResponseNew(.F., "sync.cursor.no_existe", lcCur, "")
    Endif
    Select (lcCur)
    lnTot = Reccount()
    If lnTot < 1
      loFinal = Createobject("ChalonaResponse")
      loFinal.ok = .T.
      loFinal.message = ""
      loFinal.rawBody = ""
      loSum = Createobject("Empty")
      AddProperty(loSum, "consultados", 0)
      AddProperty(loSum, "sincronizados", 0)
      loFinal.data = loSum
      Return loFinal
    Endif

    Dimension laEncf[lnTot], laCtrl[lnTot]
    lnI = 0
    Scan
      lnI = lnI + 1
      laEncf[lnI] = Alltrim(Transform(encf))
      laCtrl[lnI] = Alltrim(Transform(control))
    Endscan

    lnUpd = 0
    For lnStart = 1 To lnTot Step 100
      lnEnd = Min(lnStart + 99, lnTot)
      lcJson = "["
      For j = lnStart To lnEnd
        If j > lnStart
          lcJson = lcJson + ","
        Endif
        lcJson = lcJson + '"' + _JsonEscape(laEncf[j]) + '"'
      Endfor
      lcJson = lcJson + "]"

      loRet = This.ConsultarEstado(lcJson)
      If !loRet.ok
        Return loRet
      Endif

      loData = loRet.data
      If Vartype(loData) # "O" Or !PemStatus(loData, "result", 5)
        Loop
      Endif
      loResult = loData.result
      If Vartype(loResult) # "O"
        Loop
      Endif

      For k = 1 To loResult.Count
        loItem = loResult.Item(k)
        If Vartype(loItem) # "O"
          Loop
        Endif
        lcNum = ""
        If PemStatus(loItem, "numero", 5)
          lcNum = Alltrim(Transform(loItem.numero))
        Endif
        If Empty(lcNum)
          Loop
        Endif
        Select (lcCur)
        Locate For Upper(Alltrim(encf)) == Upper(lcNum)
        If Found()
          Replace ;
            numero               With lcNum, ;
            estado               With Left(Alltrim(Transform(Iif(PemStatus(loItem, "estado", 5), loItem.estado, ""))), 200), ;
            estado_descripcion   With Left(Alltrim(Transform(Iif(PemStatus(loItem, "estado_descripcion", 5), loItem.estado_descripcion, ""))), 500), ;
            codigo_seguridad     With Left(Alltrim(Transform(Iif(PemStatus(loItem, "codigo_seguridad", 5), loItem.codigo_seguridad, ""))), 200), ;
            fecha_firma          With Left(Alltrim(Transform(Iif(PemStatus(loItem, "fecha_firma", 5), loItem.fecha_firma, ""))), 100), ;
            timbre               With Alltrim(Transform(Iif(PemStatus(loItem, "timbre", 5), loItem.timbre, ""))), ;
            secuencia_utilizada  With Iif(PemStatus(loItem, "secuencia_utilizada", 5) And loItem.secuencia_utilizada, 1, 0), ;
            momento              With Left(Alltrim(Transform(Iif(PemStatus(loItem, "momento", 5), loItem.momento, ""))), 50)
          lnUpd = lnUpd + 1
        Endif
      Next k
    Next lnStart

    loFinal = Createobject("ChalonaResponse")
    loFinal.ok = .T.
    loFinal.message = ""
    loFinal.rawBody = ""
    loSum = Createobject("Empty")
    AddProperty(loSum, "consultados", lnTot)
    AddProperty(loSum, "sincronizados", lnUpd)
    loFinal.data = loSum
    Return loFinal
  Endfunc

  *--------------------------------------------------------------------------
  * Wrapper: invoca DescargarDocumentos y deja el path del ZIP en
  * curChalDescarga.zip_path (ademas del retorno).
  Procedure DescargarDocumentosACursor
    Lparameters tcFechaDesde, tcFechaHasta, tcTiposJson
    Local loResp, lcZip
    loResp = This.DescargarDocumentos(tcFechaDesde, tcFechaHasta, tcTiposJson)
    If Vartype(loResp) = "O" And loResp.ok ;
        And Used("curChalDescarga")
      lcZip = ""
      If PemStatus(loResp, "data", 5) And Vartype(loResp.data) = "O" ;
          And PemStatus(loResp.data, "zip_path", 5)
        lcZip = Alltrim(Transform(Nvl(loResp.data.zip_path, "")))
      Endif
      Select curChalDescarga
      If Reccount() = 0
        Append Blank
      Endif
      Replace zip_path With Left(lcZip, 260)
    Endif
    Return loResp
  Endproc

  *==========================================================================
  * Helpers privados — escriben/leen cursores con shape conocido.
  *==========================================================================

  * Despues de envia_ecf exitoso, copia campos de la respuesta DGII a curChalMae.
  Procedure _ActualizarCurChalMaeConRespuesta
    Lparameters loData
    If Vartype(loData) # "O" Or !Used("curChalMae") Or Reccount("curChalMae") < 1
      Return
    Endif
    Local lcNumero, lcEstado, lcEstadoDes, lcCod, lcFf, lcTimb, lcMom, lnSec
    lcNumero = Iif(PemStatus(loData, "numero", 5), Alltrim(Transform(loData.numero)), "")
    lcEstado = Iif(PemStatus(loData, "estado", 5), Alltrim(Transform(loData.estado)), "")
    lcEstadoDes = Iif(PemStatus(loData, "estado_descripcion", 5), Alltrim(Transform(loData.estado_descripcion)), "")
    lcCod = Iif(PemStatus(loData, "codigo_seguridad", 5), Alltrim(Transform(loData.codigo_seguridad)), "")
    lcFf = Iif(PemStatus(loData, "fecha_firma", 5), Alltrim(Transform(loData.fecha_firma)), "")
    lcTimb = Iif(PemStatus(loData, "timbre", 5), Alltrim(Transform(loData.timbre)), "")
    lcMom = Iif(PemStatus(loData, "momento", 5), Alltrim(Transform(loData.momento)), "")
    lnSec = Iif(PemStatus(loData, "secuencia_utilizada", 5) And loData.secuencia_utilizada, 1, 0)

    Select curChalMae
    Go Top
    * Si es ventas (encf vacio y numero retornado) -> setear encf;
    * en gastos motor reescribe ncf.
    If Type("curChalMae.encf") # "U" And Empty(Alltrim(Nvl(encf, ""))) ;
        And !Empty(lcNumero)
      Replace encf With Left(lcNumero, 20)
    Endif
    If Type("curChalMae.ncf") # "U" And !Empty(lcNumero) ;
        And Empty(Alltrim(Nvl(ncf, "")))
      Replace ncf With Left(lcNumero, 20)
    Endif
    If Type("curChalMae.estado") # "U"
      Replace estado With Left(lcEstado, 200)
    Endif
    If Type("curChalMae.estado_descripcion") # "U"
      Replace estado_descripcion With Left(lcEstadoDes, 500)
    Endif
    If Type("curChalMae.codigo_seguridad") # "U"
      Replace codigo_seguridad With Left(lcCod, 200)
    Endif
    If Type("curChalMae.fecha_firma") # "U"
      Replace fecha_firma With Left(lcFf, 100)
    Endif
    If Type("curChalMae.timbre") # "U"
      Replace timbre With Left(lcTimb, 500)
    Endif
    If Type("curChalMae.secuencia_utilizada") # "U"
      Replace secuencia_utilizada With lnSec
    Endif
    If Type("curChalMae.momento") # "U"
      Replace momento With Left(lcMom, 50)
    Endif
  Endproc

  *==========================================================================
  * Lectura de datos del ERP SQL Server (antes ChalonaEcfDriverSqlServer).
  * Embebido en el motor: el integrador con SQL Server estandar (dbo.imtr,
  * dbo.gastos, dbo.imtrd, etc.) llama Enviar(ctrl) y estos metodos hacen
  * Request() para llenar los cursores. Integradores con otro origen NO
  * llaman Enviar; usan CrearCursores+EnviarDesdeCursores.
  *==========================================================================

  * Helpers SQL Server: cada uno hace Request a un cursor RAW y luego
  * INSERT INTO el cursor rigido (creado por CrearCursores). Asi todo el
  * motor (path Enviar(ctrl) y path EnviarDesdeCursores) trabaja sobre
  * el mismo shape petrificado documentado en SCHEMA-CURSORES.md.
  *
  * Si el rigid cursor no existe (caso defensivo), se invoca CrearCursores.

  *--------------------------------------------------------------------------
  * Orquesta la carga completa via Request: maestro, detalle, empresa,
  * tercero, suplidor (gastos sin RNC), fiscal vence, referencia.
  * Solo se llama desde Enviar(ctrl) (path SQL Server). EnviarDesdeCursores
  * NO llama esto — los cursores ya vienen llenos por el integrador.
  Procedure _PoblarCursoresDesdeImtr
    Lparameters tcControl
    Local llEsGastos, lcTipo, lcEntidad, lcOcontrol, lcRncMae, ldFecVence

    * 1. Maestro (imtr o gastos)
    If Empty(Alltrim(This._CargarMaestro(tcControl)))
      Return
    Endif
    If !Used("curChalMae") Or Reccount("curChalMae") < 1
      Return
    Endif
    Select curChalMae
    Go Top
    lcTipo     = Alltrim(Transform(Nvl(fiscal, "")))
    lcEntidad  = Alltrim(Transform(Nvl(entidad, "")))
    lcOcontrol = Alltrim(Transform(Nvl(ocontrol, "")))
    lcRncMae   = Alltrim(Transform(Nvl(rnc, "")))
    ldFecVence = Iif(Inlist(Type("fechavencencf"), "D", "T"), ;
                      Iif(Type("fechavencencf")="T", Ttod(fechavencencf), fechavencencf), ;
                      {/})
    llEsGastos = Inlist(Int(Val(lcTipo)), 41, 43)

    * 2. Detalle (solo ventas; gastos sintetiza adentro de BuildDoc)
    If !llEsGastos
      This._CargarDetalle(tcControl)
    Endif

    * 3. Empresa emisora
    This._CargarEmpresa()

    * 4. Tercero (cliente o suplidor) si entidad no vacia
    If !Empty(lcEntidad)
      This._CargarTerceroExtranjero(lcEntidad, llEsGastos)
    Endif

    * 5. Suplidor RNC (solo gastos sin RNC en maestro)
    If llEsGastos And Empty(lcRncMae) And !Empty(lcEntidad)
      This._CargarSuplidorRncNombre(lcEntidad)
    Endif

    * 6. Fiscal vence (solo si fechavencencf vacio)
    If (Empty(ldFecVence) Or Isnull(ldFecVence)) And !Empty(lcTipo)
      This._CargarFiscalVence(lcTipo)
    Endif

    * 7. Referencia (NC/ND/FCF con doc previo) si ocontrol no vacio
    If !Empty(lcOcontrol)
      This._CargarReferenciaImtr(lcOcontrol)
    Endif
  Endproc

  Function _CargarMaestro
    Lparameters tcControl
    Local lcQ, lcSql, lcRaw, llFound
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    lcQ = _ChalonaSqlQuote(Alltrim(tcControl))
    lcRaw = "curChalMaeRaw"

    * imtr primero
    ChalonaEcfUseInIfUsed(lcRaw)
    lcSql = "SELECT * FROM dbo.imtr WHERE control = " + lcQ
    llFound = .F.
    If Request(lcSql, lcRaw) And Used(lcRaw) And Reccount(lcRaw) >= 1
      llFound = .T.
    Endif

    * Fallback gastos
    If !llFound
      ChalonaEcfUseInIfUsed(lcRaw)
      lcSql = "SELECT * FROM dbo.gastos WHERE control = " + lcQ
      If Request(lcSql, lcRaw) And Used(lcRaw) And Reccount(lcRaw) >= 1
        llFound = .T.
      Endif
    Endif

    If !llFound
      ChalonaEcfLogError("SQL: maestro (imtr/gastos)", tcControl, lcSql)
      ChalonaEcfUseInIfUsed(lcRaw)
      Return ""
    Endif

    If !Used("curChalMae")
      This.CrearCursores()
    Endif
    Select curChalMae
    Zap

    Select (lcRaw)
    Go Top
    Local lcFiscal, lcEncf, lcNcf, lcCtrlCol, ldFecha, lnValor, lnDesc, lnItbis
    Local lnTotal, lnTasa, lcMoneda, lcRnc, lcNombre, lcEntidad, lcOcontrol
    Local ldFechaVenc, lnCodMod, lnItbisr, lnIsr, lnDiascr, lnPropina
    Local lcComentario, lcReferencia, lcDoc, lcNumero
    lcFiscal     = Iif(Type("fiscal") # "U", Alltrim(Transform(Nvl(fiscal, ""))), "")
    lcEncf       = Iif(Type("encf") # "U", Alltrim(Transform(Nvl(encf, ""))), "")
    lcNcf        = Iif(Type("ncf") # "U", Alltrim(Transform(Nvl(ncf, ""))), "")
    lcCtrlCol    = Iif(Type("control") # "U", Alltrim(Transform(Nvl(control, ""))), tcControl)
    ldFecha      = Iif(Inlist(Type("fecha"), "D", "T"), Iif(Type("fecha")="T", Ttod(fecha), fecha), {/})
    lnValor      = Iif(Type("valor") # "U", _ChalonaEcfNzNum(valor), 0)
    lnDesc       = Iif(Type("descuento") # "U", _ChalonaEcfNzNum(descuento), 0)
    lnItbis      = Iif(Type("itbis") # "U", _ChalonaEcfNzNum(itbis), 0)
    lnTotal      = Iif(Type("total") # "U", _ChalonaEcfNzNum(total), 0)
    lnTasa       = Iif(Type("tasa") # "U", _ChalonaEcfNzNum(tasa), 1)
    If lnTasa < 1
      lnTasa = 1
    Endif
    lcMoneda     = Iif(Type("moneda") # "U", Alltrim(Transform(Nvl(moneda, ""))), "")
    lcRnc        = Iif(Type("rnc") # "U", Alltrim(Transform(Nvl(rnc, ""))), "")
    lcNombre     = Iif(Type("nombre") # "U", Alltrim(Transform(Nvl(nombre, ""))), "")
    lcEntidad    = Iif(Type("entidad") # "U", Alltrim(Transform(Nvl(entidad, ""))), "")
    lcOcontrol   = Iif(Type("ocontrol") # "U", Alltrim(Transform(Nvl(ocontrol, ""))), "")
    ldFechaVenc  = Iif(Inlist(Type("fechavencencf"), "D", "T"), Iif(Type("fechavencencf")="T", Ttod(fechavencencf), fechavencencf), {/})
    lnCodMod     = Iif(Type("dgii_codmod") # "U", _ChalonaEcfNzNum(dgii_codmod), 0)
    lnItbisr     = Iif(Type("itbisr") # "U", _ChalonaEcfNzNum(itbisr), Iif(Type("itbir") # "U", _ChalonaEcfNzNum(itbir), 0))
    lnIsr        = Iif(Type("isr") # "U", _ChalonaEcfNzNum(isr), 0)
    lnPropina    = Iif(Type("propina") # "U", _ChalonaEcfNzNum(propina), 0)
    lnDiascr     = Iif(Type("diascr") # "U", _ChalonaEcfNzNum(diascr), 0)
    lcComentario = Iif(Type("comentario") # "U", Alltrim(Transform(Nvl(comentario, ""))), "")
    lcReferencia = Iif(Type("referencia") # "U", Alltrim(Transform(Nvl(referencia, ""))), "")
    lcDoc        = Iif(Type("doc") # "U", Alltrim(Transform(Nvl(doc, ""))), "")
    lcNumero     = Iif(Type("numero") # "U", Alltrim(Transform(Nvl(numero, ""))), "")

    Insert Into curChalMae ;
      (fiscal, encf, ncf, control, fecha, valor, descuento, itbis, total, ;
       tasa, moneda, rnc, nombre, entidad, ocontrol, fechavencencf, dgii_codmod, ;
       itbisr, isr, propina, diascr, comentario, referencia, doc, numero) ;
      Values ( ;
       Left(lcFiscal, 2), Left(lcEncf, 20), Left(lcNcf, 20), Left(lcCtrlCol, 40), ;
       ldFecha, lnValor, lnDesc, lnItbis, lnTotal, ;
       lnTasa, Left(lcMoneda, 10), Left(lcRnc, 20), Left(lcNombre, 150), ;
       Left(lcEntidad, 20), Left(lcOcontrol, 40), ldFechaVenc, lnCodMod, ;
       lnItbisr, lnIsr, lnPropina, lnDiascr, ;
       Left(lcComentario, 200), Left(lcReferencia, 40), Left(lcDoc, 40), Left(lcNumero, 40))

    ChalonaEcfUseInIfUsed(lcRaw)
    Select curChalMae
    Return "curChalMae"
  Endfunc

  Function _CargarDetalle
    Lparameters tcControl
    Local lcQ, lcSql, lcRaw
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    lcQ = _ChalonaSqlQuote(Alltrim(tcControl))
    lcRaw = "curChalDetRaw"
    ChalonaEcfUseInIfUsed(lcRaw)
    lcSql = "SELECT d.*, m.nombre AS mercs_nombre, ISNULL(m.servicio, 0) AS mercs_servicio " + ;
            "FROM dbo.imtrd d LEFT JOIN dbo.mercs m ON m.codigo = d.merc WHERE d.control = " + lcQ
    If !Request(lcSql, lcRaw)
      ChalonaEcfLogError("SQL: imtrd+mercs (detalle)", tcControl, lcSql)
      Return ""
    Endif

    If !Used("curChalDet")
      This.CrearCursores()
    Endif
    Select curChalDet
    Zap

    Local lnPrecio, lnCantidad, lcDescrip, lcMercsNombre, lnMercsServicio
    Local lnItbisLin, lnItbisTasa, lnItbisRet, lnIsrRet
    Select (lcRaw)
    Scan
      lnPrecio        = Iif(Type("precio") # "U", _ChalonaEcfNzNum(precio), 0)
      lnCantidad      = Iif(Type("cantidad") # "U", _ChalonaEcfNzNum(cantidad), 0)
      lcDescrip       = Iif(Type("descrip") # "U", Alltrim(Transform(Nvl(descrip, ""))), "")
      lcMercsNombre   = Iif(Type("mercs_nombre") # "U", Alltrim(Transform(Nvl(mercs_nombre, ""))), "")
      lnMercsServicio = Iif(Type("mercs_servicio") # "U", _ChalonaEcfNzNum(mercs_servicio), 0)
      lnItbisLin      = Iif(Type("itbis") # "U", _ChalonaEcfNzNum(itbis), 0)
      * itbisporc en imtrd o itbis_tasa en otros esquemas; 0 si ninguno.
      lnItbisTasa     = Iif(Type("itbis_tasa") # "U", _ChalonaEcfNzNum(itbis_tasa), ;
                             Iif(Type("itbisporc") # "U", _ChalonaEcfNzNum(itbisporc), 0))
      lnItbisRet      = Iif(Type("itbis_retenido") # "U", _ChalonaEcfNzNum(itbis_retenido), 0)
      lnIsrRet        = Iif(Type("isr_retenido") # "U", _ChalonaEcfNzNum(isr_retenido), 0)
      Insert Into curChalDet ;
        (precio, cantidad, descrip, mercs_nombre, mercs_servicio, itbis, itbis_tasa, itbis_retenido, isr_retenido) ;
        Values (lnPrecio, lnCantidad, Left(lcDescrip, 200), Left(lcMercsNombre, 200), lnMercsServicio, lnItbisLin, lnItbisTasa, lnItbisRet, lnIsrRet)
    Endscan

    ChalonaEcfUseInIfUsed(lcRaw)
    Select curChalDet
    Return "curChalDet"
  Endfunc

  Function _CargarFiscalVence
    Lparameters tcTipoEcf
    Local lcSql, lcRaw, ldVence
    If Vartype(tcTipoEcf) # "C"
      tcTipoEcf = ""
    Endif
    lcRaw = "curChalFisRaw"
    ChalonaEcfUseInIfUsed(lcRaw)
    lcSql = "SELECT TOP 1 vence FROM dbo.fiscal WHERE codigo = " + _ChalonaSqlQuote(Alltrim(tcTipoEcf))
    If !Request(lcSql, lcRaw)
      ChalonaEcfLogError("SQL: fiscal (vencimiento)", tcTipoEcf, lcSql)
      Return ""
    Endif
    If !Used("curChalFis")
      This.CrearCursores()
    Endif
    Select curChalFis
    Zap
    If Used(lcRaw) And Reccount(lcRaw) > 0
      Select (lcRaw)
      Go Top
      ldVence = Iif(Inlist(Type("vence"), "D", "T"), Iif(Type("vence")="T", Ttod(vence), vence), {/})
      Insert Into curChalFis (vence) Values (ldVence)
    Endif
    ChalonaEcfUseInIfUsed(lcRaw)
    Select curChalFis
    Return "curChalFis"
  Endfunc

  Function _CargarEmpresa
    Local lcSql, lcRaw
    Local lcRnc, lcNombre, lcDir, lnIprecio
    lcRaw = "curChalEmpRaw"
    ChalonaEcfUseInIfUsed(lcRaw)
    lcSql = "SELECT TOP 1 rnc, nombre, direccion, iprecio FROM dbo.empresa"
    If !Request(lcSql, lcRaw)
      ChalonaEcfLogError("SQL: empresa (emisor)", "", lcSql)
      Return ""
    Endif
    If !Used("curChalEmp")
      This.CrearCursores()
    Endif
    Select curChalEmp
    Zap
    If Used(lcRaw) And Reccount(lcRaw) > 0
      Select (lcRaw)
      Go Top
      lcRnc     = Iif(Type("rnc") # "U", Alltrim(Transform(Nvl(rnc, ""))), "")
      lcNombre  = Iif(Type("nombre") # "U", Alltrim(Transform(Nvl(nombre, ""))), "")
      lcDir     = Iif(Type("direccion") # "U", Alltrim(Transform(Nvl(direccion, ""))), "")
      lnIprecio = Iif(Vartype(iprecio) = "L", Iif(iprecio, 1, 0), Iif(Type("iprecio") # "U", _ChalonaEcfNzNum(iprecio), 0))
      Insert Into curChalEmp (rnc, nombre, direccion, iprecio) ;
        Values (Left(lcRnc, 20), Left(lcNombre, 150), Left(lcDir, 200), lnIprecio)
    Endif
    ChalonaEcfUseInIfUsed(lcRaw)
    Select curChalEmp
    Return "curChalEmp"
  Endfunc

  Function _CargarSuplidorRncNombre
    Lparameters tcCodigo
    Local lcSql, lcRaw, lcRnc, lcNombre
    If Vartype(tcCodigo) # "C"
      tcCodigo = ""
    Endif
    lcRaw = "curChalSupRaw"
    ChalonaEcfUseInIfUsed(lcRaw)
    lcSql = "SELECT TOP 1 rnc, nombre FROM dbo.suplidor WHERE codigo = " + _ChalonaSqlQuote(Alltrim(tcCodigo))
    If !Request(lcSql, lcRaw)
      ChalonaEcfLogError("SQL: suplidor (rnc/nombre)", tcCodigo, lcSql)
      Return ""
    Endif
    If !Used("curChalSup")
      This.CrearCursores()
    Endif
    Select curChalSup
    Zap
    If Used(lcRaw) And Reccount(lcRaw) > 0
      Select (lcRaw)
      Go Top
      lcRnc    = Iif(Type("rnc") # "U", Alltrim(Transform(Nvl(rnc, ""))), "")
      lcNombre = Iif(Type("nombre") # "U", Alltrim(Transform(Nvl(nombre, ""))), "")
      Insert Into curChalSup (rnc, nombre) ;
        Values (Left(lcRnc, 20), Left(lcNombre, 150))
    Endif
    ChalonaEcfUseInIfUsed(lcRaw)
    Select curChalSup
    Return "curChalSup"
  Endfunc

  Function _CargarTerceroExtranjero
    Lparameters tcCodigo, tlEsGastos
    Local lcSql, lcCod, lcRaw, lnExtFlag, lcRnc, lcNombre
    If Vartype(tcCodigo) # "C"
      tcCodigo = ""
    Endif
    If Vartype(tlEsGastos) # "L"
      tlEsGastos = .F.
    Endif
    lcCod = _ChalonaSqlQuote(Alltrim(tcCodigo))
    lcRaw = "curChalCliRaw"
    ChalonaEcfUseInIfUsed(lcRaw)
    If tlEsGastos
      lcSql = "SELECT TOP 1 ISNULL(extranjero, 0) AS extranjero_flag, '' AS rnc, '' AS nombre FROM dbo.suplidor WHERE codigo = " + lcCod
    Else
      lcSql = "SELECT TOP 1 ISNULL(extranjero, 0) AS extranjero_flag, rnc, nombre FROM dbo.clientes WHERE codigo = " + lcCod
    Endif
    If !Request(lcSql, lcRaw)
      ChalonaEcfLogError("SQL: tercero (extranjero)", tcCodigo, lcSql)
      Return ""
    Endif
    If !Used("curChalCli")
      This.CrearCursores()
    Endif
    Select curChalCli
    Zap
    If Used(lcRaw) And Reccount(lcRaw) > 0
      Select (lcRaw)
      Go Top
      lnExtFlag = Iif(Type("extranjero_flag") # "U", _ChalonaEcfNzNum(extranjero_flag), 0)
      lcRnc     = Iif(Type("rnc") # "U", Alltrim(Transform(Nvl(rnc, ""))), "")
      lcNombre  = Iif(Type("nombre") # "U", Alltrim(Transform(Nvl(nombre, ""))), "")
      Insert Into curChalCli (extranjero_flag, rnc, nombre) ;
        Values (lnExtFlag, Left(lcRnc, 20), Left(lcNombre, 150))
    Endif
    ChalonaEcfUseInIfUsed(lcRaw)
    Select curChalCli
    Return "curChalCli"
  Endfunc

  Function _CargarReferenciaImtr
    Lparameters tcOcontrol
    Local lcSql, lcRaw, lcRefEncf, ldRefFecha
    If Vartype(tcOcontrol) # "C"
      tcOcontrol = ""
    Endif
    lcRaw = "curChalRefRaw"
    ChalonaEcfUseInIfUsed(lcRaw)
    lcSql = "SELECT TOP 1 encf, fecha FROM dbo.imtr WHERE control = " + _ChalonaSqlQuote(Alltrim(tcOcontrol))
    If !Request(lcSql, lcRaw)
      ChalonaEcfLogError("SQL: imtr (referencia)", tcOcontrol, lcSql)
      Return ""
    Endif
    If !Used("curChalRef")
      This.CrearCursores()
    Endif
    Select curChalRef
    Zap
    If Used(lcRaw) And Reccount(lcRaw) > 0
      Select (lcRaw)
      Go Top
      lcRefEncf  = Iif(Type("encf") # "U", Alltrim(Transform(Nvl(encf, ""))), "")
      ldRefFecha = Iif(Inlist(Type("fecha"), "D", "T"), Iif(Type("fecha")="T", Ttod(fecha), fecha), {/})
      Insert Into curChalRef (encf, fecha) Values (Left(lcRefEncf, 20), ldRefFecha)
    Endif
    ChalonaEcfUseInIfUsed(lcRaw)
    Select curChalRef
    Return "curChalRef"
  Endfunc

  Function _ContarOrigen
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

  Function _GuardarRespuestaEnvio
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

  Function _MarcarErrorEnvio
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

  Function _SyncIntentarLock
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

  Procedure _SyncLiberarLock
    Request( ;
        "EXEC sp_releaseapplock " + ;
        "  @Resource = N'ChalonaEcf_SincronizarEstadosEnProceso', " + ;
        "  @LockOwner = N'Session';")
  Endproc

  Function _SyncListarPendientes
    Local lcCur, lcRaw
    lcCur = "curChalonaEncfEnProceso"
    lcRaw = "curChalonaEncfRaw"
    ChalonaEcfUseInIfUsed(lcCur)
    ChalonaEcfUseInIfUsed(lcRaw)
    If !Request( ;
        "SELECT " + ;
        "  LTRIM(RTRIM(i.control)) AS control, " + ;
        "  LTRIM(RTRIM(i.encf)) AS encf, " + ;
        "  CAST(0 AS bit) AS es_gastos " + ;
        "FROM dbo.imtr AS i " + ;
        "WHERE LOWER(LTRIM(RTRIM(ISNULL(i.respuesta_estado, N'')))) = N'en proceso' " + ;
        "  AND NULLIF(LTRIM(RTRIM(i.encf)), N'') IS NOT NULL " + ;
        "UNION ALL " + ;
        "SELECT " + ;
        "  LTRIM(RTRIM(g.control)), LTRIM(RTRIM(g.ncf)), CAST(1 AS bit) " + ;
        "FROM dbo.gastos AS g " + ;
        "WHERE LOWER(LTRIM(RTRIM(ISNULL(g.respuesta_estado, N'')))) = N'en proceso' " + ;
        "  AND NULLIF(LTRIM(RTRIM(g.ncf)), N'') IS NOT NULL;", ;
        lcRaw)
      Return ""
    Endif
    Create Cursor (lcCur) ;
      (control C(40), encf C(20), es_gastos L, ;
       numero C(20), estado C(200), estado_descripcion M, ;
       codigo_seguridad C(200), fecha_firma C(100), timbre M, ;
       secuencia_utilizada N(1), momento C(50))
    Select (lcRaw)
    Scan
      Insert Into (lcCur) (control, encf, es_gastos) ;
        Values (Alltrim(Transform(control)), Alltrim(Transform(encf)), ;
                Iif(Vartype(es_gastos) = "L", es_gastos, (0 + Nvl(es_gastos, 0)) > 0))
    Endscan
    ChalonaEcfUseInIfUsed(lcRaw)
    Select (lcCur)
    Return lcCur
  Endfunc

  Function _SyncFinalizar
    Local lcCur, loData, lnSel
    lcCur = "curChalonaEncfEnProceso"
    If !Used(lcCur)
      Return .T.
    Endif
    lnSel = Select()
    Select (lcCur)
    Scan For !Empty(Alltrim(numero))
      loData = Createobject("Empty")
      AddProperty(loData, "numero", Alltrim(numero))
      AddProperty(loData, "estado", Alltrim(estado))
      AddProperty(loData, "estado_descripcion", Alltrim(estado_descripcion))
      AddProperty(loData, "codigo_seguridad", Alltrim(codigo_seguridad))
      AddProperty(loData, "fecha_firma", Alltrim(fecha_firma))
      AddProperty(loData, "timbre", Alltrim(timbre))
      AddProperty(loData, "secuencia_utilizada", Iif(secuencia_utilizada = 1, .T., .F.))
      AddProperty(loData, "momento", Alltrim(momento))
      This._GuardarRespuestaEnvio(Alltrim(control), loData, es_gastos)
    Endscan
    Select (lnSel)
    Return .T.
  Endfunc

  Function _SyncListarDuplicados
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

Enddefine

*------------------------------------------------------------
* Clase ChalonaResponse: objeto de resultado con helpers
*------------------------------------------------------------
Define Class ChalonaResponse As Custom
  ok      = .F.
  message = ""
  data    = ""
  rawBody = ""
  * Cuerpo HTTP enviado al API (p. ej. envia_ecf); para mostrar en resumen de error.
  requestBody = ""

  * Crear un cursor con la informaciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n de los errores
  * Espera que This.data.errors sea un Collection de objetos
  * con al menos la propiedad "code" y opcionalmente "params" (objeto).
  *
  * Uso:
  *   loResp = chalonaEnviaEcf(control)
  *   IF loResp.ErrorsToCursor("curChalonaErrors")
  *     SELECT curChalonaErrors
  *     BROWSE
  *   ENDIF
  Procedure ErrorsToCursor
    Lparameters tcCursorName
    Local lcCur, loData, loErrors, i, loErr
    Local lcCode, lcParamsStr

    * tcCursorName no viene como NULL sino como .F. si no se pasÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³;
    * validar tipo antes de aplicar Alltrim.
    lcCur = Iif(Vartype(tcCursorName) = "C" And Not Empty(tcCursorName), ;
      Alltrim(tcCursorName), ;
      "curChalonaErrors")

    loData = This.data
    If Vartype(loData) # "O"
      * No es objeto: no hay lista de errores; intentamos crear un cursor con un solo error
      RETURN This._ErrorsToCursorFromSingle(lcCur)
    Endif

    If PemStatus(loData, "errors", 5)
      loErrors = loData.errors
    Else
      * No hay data.errors: caso de error ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âºnico (message_code)
      RETURN This._ErrorsToCursorFromSingle(lcCur)
    Endif

    If Vartype(loErrors) # "O"
      RETURN This._ErrorsToCursorFromSingle(lcCur)
    Endif

    * Cerrar cursor si ya existe
    If Used(lcCur)
      Select (lcCur)
      Use In (lcCur)
    Endif

    * Un registro por error: code + params serializado plano
    Create Cursor (lcCur) (code C(200), params C(254))

    For i = 1 To loErrors.Count
      loErr = loErrors.Item(i)
      If Vartype(loErr) # "O"
        Loop
      Endif

      lcCode      = ""
      lcParamsStr = ""

      * code: preferir .code; si no existe, usar .error (como en ecf)
      If PemStatus(loErr, "code", 5)
        lcCode = Transform(loErr.code)
      Else
        If PemStatus(loErr, "error", 5)
          lcCode = Transform(loErr.error)
        Endif
      Endif

      * params -> "k1=v1; k2=v2"
      * Caso 1: objeto .params explÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­cito (contrato Chalona)
      If PemStatus(loErr, "params", 5) And Vartype(loErr.params) = "O"
        Local laMembers[1], lnMembers, j, lcName, uVal, lcValStr
        lnMembers = AMEMBERS(laMembers, loErr.params, 0) && solo propiedades
        For j = 1 To lnMembers
          lcName = laMembers[j]
          uVal   = loErr.params.&lcName
          Do Case
            Case Vartype(uVal) = "C"
              lcValStr = uVal
            Case Vartype(uVal) = "N"
              lcValStr = Transform(uVal)
            Case Vartype(uVal) = "L"
              lcValStr = Iif(uVal, "true", "false")
            Case Vartype(uVal) = "U"
              lcValStr = ""
            Otherwise
              lcValStr = "<obj>"
          Endcase

          If Not Empty(Alltrim(lcValStr))
            If Empty(lcParamsStr)
              lcParamsStr = lcName + "=" + lcValStr
            Else
              lcParamsStr = lcParamsStr + "; " + lcName + "=" + lcValStr
            Endif
          Endif
        Endfor
      Else
        * Caso 2: no hay .params; serializar propiedades del propio error
        Local laMembers2[1], lnMembers2, k, lcName2, uVal2, lcValStr2
        lnMembers2 = AMEMBERS(laMembers2, loErr, 0)
        For k = 1 To lnMembers2
          lcName2 = laMembers2[k]
          * Omitir campos de texto principales
          If Upper(lcName2) $ "ERROR,MENSAJE"
            Loop
          Endif
          uVal2 = loErr.&lcName2
          Do Case
            Case Vartype(uVal2) = "C"
              lcValStr2 = uVal2
            Case Vartype(uVal2) = "N"
              lcValStr2 = Transform(uVal2)
            Case Vartype(uVal2) = "L"
              lcValStr2 = Iif(uVal2, "true", "false")
            Case Vartype(uVal2) = "U"
              lcValStr2 = ""
            Otherwise
              lcValStr2 = "<obj>"
          Endcase

          If Not Empty(Alltrim(lcValStr2))
            If Empty(lcParamsStr)
              lcParamsStr = lcName2 + "=" + lcValStr2
            Else
              lcParamsStr = lcParamsStr + "; " + lcName2 + "=" + lcValStr2
            Endif
          Endif
        Endfor
      Endif

      Insert Into (lcCur) (code, params) Values (lcCode, lcParamsStr)
    Endfor

    Return .T.
  Endproc

  * Caso alterno: no hay data.errors; usar message_code / message para un solo registro
  Procedure _ErrorsToCursorFromSingle
    Lparameters tcCursorName
    Local lcCur, lcCode, lcParamsStr, loDataLocal

    lcCur = Iif(Vartype(tcCursorName) = "C" And Not Empty(tcCursorName), ;
      Alltrim(tcCursorName), ;
      "curChalonaErrors")

    * Cerrar cursor si ya existe
    If Used(lcCur)
      Select (lcCur)
      Use In (lcCur)
    Endif

    Create Cursor (lcCur) (code C(200), params C(254))

    lcCode      = ""
    lcParamsStr = ""

    loDataLocal = This.data

    * Prioridad: data.message_code -> data.code -> message
    If Vartype(loDataLocal) = "O"
      If PemStatus(loDataLocal, "message_code", 5)
        lcCode = Transform(loDataLocal.message_code)
      Else
        If PemStatus(loDataLocal, "code", 5)
          lcCode = Transform(loDataLocal.code)
        Endif
      Endif
    Endif

    If Empty(lcCode)
      lcCode = Transform(This.message)
    Endif

    Insert Into (lcCur) (code, params) Values (lcCode, lcParamsStr)

    Return .T.
  Endproc

  * Decodificar un documento base64 (UTF-8) de This.data.files a un cursor
  *
  * Uso tÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­pico:
  *   * Supone que This.data.files es Collection de objetos con propiedad .data (base64)
  *   IF loResp.DocumentToCursor(1, "curEcfXml")
  *     SELECT curEcfXml
  *     BROWSE
  *   ENDIF
  *
  * tnFileIndex: ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­ndice 1-based en la colecciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n files (por defecto 1)
  * tcCursorName: nombre del cursor destino (por defecto "curChalonaXml")
  Procedure DocumentToCursor
    Lparameters tnFileIndex, tcCursorName
    Local lnIdx, lcCur, loData, loFiles, loFile

    lnIdx = Iif(Vartype(tnFileIndex) = "N" And tnFileIndex > 0, tnFileIndex, 1)
    lcCur = Iif(Vartype(tcCursorName) = "C" And Not Empty(tcCursorName), ;
      Alltrim(tcCursorName), ;
      "curChalonaXml")

    loData = This.data
    If Vartype(loData) # "O"
      Return .F.
    Endif

    If !PemStatus(loData, "files", 5)
      Return .F.
    Endif

    loFiles = loData.files
    If Vartype(loFiles) # "O"
      Return .F.
    Endif

    If lnIdx < 1 Or lnIdx > loFiles.Count
      Return .F.
    Endif

    loFile = loFiles.Item(lnIdx)
    If Vartype(loFile) # "O" Or !PemStatus(loFile, "data", 5)
      Return .F.
    Endif

    Return This._Base64ToCursorInternal(loFile, lcCur)
  Endproc

  * Helper interno: decodifica base64 UTF-8 a cursor con metadatos
  Procedure _Base64ToCursorInternal
    Lparameters toFile, tcCursorName
    Local lcCur, lcB64, lcBin, lcText
    Local loData
    Local lcId, lcPortal, lcEmisor, lcComprador, lcTipo, lcNumero
    Local lcEstado, lcEstadoDesc
    Local lcFecha, lcMomento, lcAfecta, lcTotal, lcSecUtil, lcTimbre
    Local lcFechaFirma, lcTrackId

    lcCur = Iif(Vartype(tcCursorName) = "C" And Not Empty(tcCursorName), ;
      Alltrim(tcCursorName), ;
      "curChalonaXml")

    If Vartype(toFile) # "O" Or !PemStatus(toFile, "data", 5)
      Return .F.
    Endif

    * Metadatos desde This.data (respuesta del API)
    loData = This.data
    If Vartype(loData) = "O"
      lcId         = Iif(PemStatus(loData, "id", 5), ;
        Transform(loData.id), "")
      lcPortal     = Iif(PemStatus(loData, "portal", 5), ;
        Transform(loData.portal), "")
      lcEmisor     = Iif(PemStatus(loData, "emisor", 5), ;
        Transform(loData.emisor), "")
      lcComprador  = Iif(PemStatus(loData, "comprador", 5), ;
        Transform(loData.comprador), "")
      lcTipo       = Iif(PemStatus(loData, "tipo", 5), ;
        Transform(loData.tipo), "")
      lcNumero     = Iif(PemStatus(loData, "numero", 5), ;
        Transform(loData.numero), "")
      lcEstado     = Iif(PemStatus(loData, "estado", 5), ;
        Transform(loData.estado), "")
      lcEstadoDesc = Iif(PemStatus(loData, "estado_descripcion", 5), ;
        Transform(loData.estado_descripcion), "")
      lcFecha      = Iif(PemStatus(loData, "fecha", 5), ;
        Transform(loData.fecha), "")
      lcMomento    = Iif(PemStatus(loData, "momento", 5), ;
        Transform(loData.momento), "")
      lcAfecta     = Iif(PemStatus(loData, "afecta", 5), ;
        Transform(loData.afecta), "")
      lcTotal      = Iif(PemStatus(loData, "total", 5), ;
        Transform(loData.total), "")
      lcSecUtil    = Iif(PemStatus(loData, "secuencia_utilizada", 5), ;
        Transform(loData.secuencia_utilizada), "")
      lcTimbre     = Iif(PemStatus(loData, "timbre", 5), ;
        Transform(loData.timbre), "")
      lcFechaFirma = Iif(PemStatus(loData, "fecha_firma", 5), ;
        Transform(loData.fecha_firma), "")
      lcTrackId    = Iif(PemStatus(loData, "track_id", 5), ;
        Transform(loData.track_id), "")
    Else
      lcId = lcPortal = lcEmisor = lcComprador = lcTipo = lcNumero = ""
      lcEstado = lcEstadoDesc = lcFecha = lcMomento = lcAfecta = ""
      lcTotal = lcSecUtil = lcTimbre = lcFechaFirma = lcTrackId = ""
    Endif

    * Cerrar cursor si ya existe
    If Used(lcCur)
      Select (lcCur)
      Use In (lcCur)
    Endif

    * Quitar posibles saltos de lÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­nea en el base64
    lcB64 = Chrtran(Alltrim(toFile.data), Chr(13) + Chr(10), "")
    lcB64 = Chrtran(lcB64, Chr(13), "")
    lcB64 = Chrtran(lcB64, Chr(10), "")

    * Base64 -> binario (string de bytes)
    lcBin = Strconv(lcB64, 14) && 14 = base64 -> binario

    * Binario UTF-8 -> texto Unicode (FoxPro)
    lcText = Strconv(lcBin, 9) && 9 = UTF-8 -> Unicode

    * Cursor alineado con columnas de negocio del registro e-CF (orden estable).
    Create Cursor (lcCur) ;
      (id C(10), portal C(20), emisor C(20), comprador C(30), ;
       tipo C(4), numero C(20), ;
       estado C(20), estado_descripcion C(200), ;
       fecha C(20), momento C(40), afecta C(40), ;
       total C(20), secuencia_utilizada C(10), ;
       timbre C(200), fecha_firma C(40), track_id C(40), ;
       documento M)
    Insert Into (lcCur) ;
      (id, portal, emisor, comprador, tipo, numero, estado, estado_descripcion, ;
       fecha, momento, afecta, total, secuencia_utilizada, ;
       timbre, fecha_firma, track_id, documento) ;
      Values ;
      (lcId, lcPortal, lcEmisor, lcComprador, lcTipo, lcNumero, ;
       lcEstado, lcEstadoDesc, ;
       lcFecha, lcMomento, lcAfecta, lcTotal, lcSecUtil, ;
       lcTimbre, lcFechaFirma, lcTrackId, lcText)

    Return .T.
  Endproc

Enddefine

*------------------------------------------------------------
* Botones del formulario de error (VFP no permite This.cmd.Click = [...]).
*------------------------------------------------------------
Define Class ChalonaBtnCopiarErrorEcf As CommandButton
  Procedure Click
    _cliptext = Thisform.cCuerpo
  Endproc
Enddefine

Define Class ChalonaBtnCerrarErrorEcf As CommandButton
  Procedure Click
    Thisform.Release()
  Endproc
Enddefine

*------------------------------------------------------------
* Formulario modal con texto legible cuando falla el envio (evita MESSAGEBOX).
*------------------------------------------------------------
Define Class ChalonaFormErrorEnvioEcf As Form
  Caption = "Envio de e-CF no completado"
  Width = 580
  Height = 440
  AutoCenter = .T.
  BorderStyle = 2
  MaxButton = .F.
  MinButton = .F.
  Closable = .T.
  WindowType = 1

  Procedure Init
    Lparameters tcTexto
    Local lcText
    lcText = Nvl(tcTexto, "")
    This.AddProperty("cCuerpo", "")
    This.cCuerpo = lcText

    This.AddObject("lblIntro", "Label")
    With This.lblIntro
      .Caption = ;
        "El comprobante no pudo enviarse. Revise el texto siguiente. " + ;
        "Puede usar 'Copiar todo' para pegarlo en un correo o ticket de soporte."
      .Left = 12
      .Top = 10
      .Width = Thisform.Width - 24
      .Height = 44
      .WordWrap = .T.
      .FontSize = 9
    Endwith

    This.AddObject("edDetalle", "EditBox")
    With This.edDetalle
      .Left = 12
      .Top = 58
      .Width = Thisform.Width - 24
      .Height = Thisform.Height - 58 - 48
      .ReadOnly = .T.
      .ScrollBars = 2
      .FontName = "Consolas"
      .FontSize = 9
      .Value = lcText
    Endwith

    This.AddObject("cmdCopiar", "ChalonaBtnCopiarErrorEcf")
    With This.cmdCopiar
      .Caption = "Copiar todo"
      .Left = 12
      .Top = Thisform.Height - 40
      .Width = 110
      .Height = 28
    Endwith

    This.AddObject("cmdCerrar", "ChalonaBtnCerrarErrorEcf")
    With This.cmdCerrar
      .Caption = "Cerrar"
      .Left = Thisform.Width - 12 - .Width
      .Top = Thisform.Height - 40
      .Width = 100
      .Height = 28
      .Default = .T.
    Endwith
    this.SetAll('visible',.t.)
  Endproc

Enddefine

* imtr.respuesta_mensajes es C(254): normaliza saltos de linea y recorta. Unico campo para mensaje en documento.
Function _ChalonaImtrAcotarRespuestaMensajes
  Lparameters tcMsg
  Local lc
  lc = Alltrim(Transform(Nvl(tcMsg, "")))
  lc = Chrtran(lc, Chr(13), " ")
  lc = Chrtran(lc, Chr(10), " ")
  lc = Alltrim(lc)
  If Len(lc) > 254
    lc = Left(lc, 254)
  Endif
  Return lc
Endfunc

* Texto para imtr.respuesta_mensajes ante error de API/validacion (mismo limite 254).
Function _ChalonaEcfMensajeErrorImtr
  Lparameters loResp
  Local lc, loData, lcExtra
  If Vartype(loResp) # "O"
    Return _ChalonaImtrAcotarRespuestaMensajes("Sin respuesta valida")
  Endif
  lc = ""
  If Pemstatus(loResp, "message", 5)
    lc = Alltrim(Transform(loResp.message))
  Endif
  loData = .Null.
  If Pemstatus(loResp, "data", 5) And Vartype(loResp.data) = "O"
    loData = loResp.data
  Endif
  If Vartype(loData) = "O"
    If Pemstatus(loData, "detail", 5)
      lcExtra = Alltrim(Transform(loData.detail))
      If !Empty(lcExtra)
        If !Empty(lc)
          lc = lc + ": "
        Endif
        lc = lc + lcExtra
      Endif
    Endif
    If Empty(lc) And Pemstatus(loData, "message_code", 5)
      lc = Alltrim(Transform(loData.message_code))
    Endif
  Endif
  If Empty(lc)
    lc = "Error envio ECF"
  Endif
  Return _ChalonaImtrAcotarRespuestaMensajes(lc)
Endfunc

* Arma texto explicativo + errores estructurados + recorte de raw JSON
Function _ChalonaTextoErrorEnvioEcf
  Lparameters loResp, tcControl
  Local lc, loData, lcRaw, lcCur, lnRows, lcReq

  If Vartype(loResp) # "O"
    Return "No se obtuvo una respuesta valida del servidor."
  Endif

  lc = ""
  lc = lc + Replicate("=", 55) + Chr(13) + Chr(10)
  lc = lc + "  Comprobante fiscal electronico (e-CF)" + Chr(13) + Chr(10)
  lc = lc + Replicate("=", 55) + Chr(13) + Chr(10)
  lc = lc + Chr(13) + Chr(10)

  If Not Empty(Nvl(tcControl, ""))
    lc = lc + "Documento en su sistema (control): " + Alltrim(tcControl) + Chr(13) + Chr(10)
    lc = lc + Chr(13) + Chr(10)
  Endif

  lc = lc + "QUE OCURRIO" + Chr(13) + Chr(10)
  lc = lc + Replicate("-", 50) + Chr(13) + Chr(10)
  If PemStatus(loResp, "message", 5) And Not Empty(Alltrim(Transform(loResp.message)))
    lc = lc + Alltrim(Transform(loResp.message)) + Chr(13) + Chr(10)
  Else
    lc = lc + "El servidor no devolvio un mensaje descriptivo." + Chr(13) + Chr(10)
  Endif

  loData = .Null.
  If PemStatus(loResp, "data", 5) And Vartype(loResp.data) = "O"
    loData = loResp.data
  Endif

  If Vartype(loData) = "O"
    If PemStatus(loData, "message_code", 5) And Not Empty(Alltrim(Transform(loData.message_code)))
      lc = lc + Chr(13) + Chr(10) + "Codigo de referencia (tecnico): " + ;
        Alltrim(Transform(loData.message_code)) + Chr(13) + Chr(10)
    Endif
    If PemStatus(loData, "detail", 5) And Not Empty(Alltrim(Transform(loData.detail)))
      lc = lc + "Detalle: " + Alltrim(Transform(loData.detail)) + Chr(13) + Chr(10)
    Endif
  Endif

  lcCur = "_chalona_err_ui"
  If loResp.ErrorsToCursor(lcCur)
    If Used(lcCur)
      Select (lcCur)
      Count To lnRows
      If lnRows > 0
        lc = lc + Chr(13) + Chr(10) + "DETALLE ADICIONAL" + Chr(13) + Chr(10)
        lc = lc + Replicate("-", 50) + Chr(13) + Chr(10)
        Scan
          lc = lc + "- " + Alltrim(code)
          If Not Empty(Alltrim(params))
            lc = lc + "  |  " + Alltrim(params)
          Endif
          lc = lc + Chr(13) + Chr(10)
        Endscan
      Endif
      Use In (lcCur)
    Endif
  Endif

  * Peticion HTTP enviada (locale, rnc, portal, json del e-CF) para reproducir en soporte.
  If PemStatus(loResp, "requestBody", 5)
    Do Case
      Case Vartype(loResp.requestBody) = "C"
        lcReq = loResp.requestBody
      Otherwise
        lcReq = Transform(loResp.requestBody)
    Endcase
    lcReq = Alltrim(lcReq)
    If Not Empty(lcReq)
      If Len(lcReq) > 150000
        lcReq = Left(lcReq, 150000) + Chr(13) + Chr(10) + "... (JSON enviado recortado)"
      Endif
      lc = lc + Chr(13) + Chr(10) + "JSON ENVIADO AL API (cuerpo del POST envia_ecf)" + Chr(13) + Chr(10)
      lc = lc + Replicate("-", 50) + Chr(13) + Chr(10)
      lc = lc + lcReq + Chr(13) + Chr(10)
    Endif
  Endif

  If PemStatus(loResp, "rawBody", 5)
    lcRaw = Transform(loResp.rawBody)
    lcRaw = Alltrim(lcRaw)
    If Not Empty(lcRaw)
      If Len(lcRaw) > 4000
        lcRaw = Left(lcRaw, 4000) + Chr(13) + Chr(10) + "... (respuesta recortada)"
      Endif
      lc = lc + Chr(13) + Chr(10) + "RESPUESTA TECNICA (para soporte)" + Chr(13) + Chr(10)
      lc = lc + Replicate("-", 50) + Chr(13) + Chr(10)
      lc = lc + lcRaw + Chr(13) + Chr(10)
    Endif
  Endif

  lc = lc + Chr(13) + Chr(10) + Replicate("-", 50) + Chr(13) + Chr(10)
  lc = lc + "Si el error se repite, copie este texto completo y envielo a soporte " + ;
    "indicando el control del documento y la fecha/hora del intento."

  Return lc
Endfunc

* Muestra formulario modal con el error (llamar si !loResp.ok).
Function ChalonaMostrarErrorEnvioEcf
  Lparameters loResp, tcControl
  Local lcTxt, loF
  If Vartype(loResp) = "O" And loResp.ok
    Return
  Endif
  lcTxt = _ChalonaTextoErrorEnvioEcf(loResp, tcControl)
  loF = Createobject("ChalonaFormErrorEnvioEcf", lcTxt)
  loF.Show(1)
Endfunc

* Helper para instanciar ChalonaResponse desde las funciones
Function ChalonaResponseNew
  Lparameters tlOk, tcMessage, tcDataJson, tcRaw
  Local lo
  lo = Createobject("ChalonaResponse")
  lo.ok      = tlOk
  lo.message = Nvl(tcMessage, "")
  lo.data    = Nvl(tcDataJson, "")
  lo.rawBody = Nvl(tcRaw, "")
  Return lo
Endfunc

*------------------------------------------------------------
* Parsear body JSON de la API y convertir data en objeto
*------------------------------------------------------------
Function ChalonaResponseFromApiBody
  Lparameters tcBody
  Local lc, llOk, lcMsg, lcDataJson, loResp, uParsed
  lc = Nvl(tcBody, "")
  If Empty(Alltrim(lc))
    Return ChalonaResponseNew(.F., "response.error.empty_body", "", "")
  Endif

  * ok: si aparece false, queda .F.
  llOk = .F.
  If Atc('"ok":true', lc) > 0
    llOk = .T.
  Endif
  If Atc('"ok":false', lc) > 0
    llOk = .F.
  Endif

  lcMsg      = _ChalonaExtractJsonString(lc, "message")
  lcDataJson = _ChalonaExtractJsonValue(lc, "data")

  * Objeto base de respuesta (como antes, data todavÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­a como JSON/string)
  loResp = ChalonaResponseNew(llOk, lcMsg, lcDataJson, lc)

  * Intentar parsear recursivamente lcDataJson:
  * - Objetos {...} -> Empty con propiedades
  * - Arreglos [...] -> Collection con elementos
  * - Escalares -> nÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âºmero / lÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³gico / string / .Null.
  uParsed = _ChalonaJsonParseValue(lcDataJson)

  * Si el parser devuelve algo distinto de string vacÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­o, usarlo como data
  Do Case
    Case Vartype(uParsed) = "O"
      loResp.data = uParsed
    Case Vartype(uParsed) = "N"
      loResp.data = uParsed
    Case Vartype(uParsed) = "L"
      loResp.data = uParsed
    Case Vartype(uParsed) = "C"
      * Si el parser decidio que es string real, lo ponemos; si fallo y devolvio "",
      * nos quedamos con el JSON crudo original que ya tenia loResp.data
      If Not Empty(uParsed)
        loResp.data = uParsed
      Endif
    Case Vartype(uParsed) = "U"
      * Sin cambios, se queda el JSON crudo
  Endcase

  Return loResp
Endfunc

*------------------------------------------------------------
* JSON simple recursivo: valor / objeto / arreglo
*------------------------------------------------------------
Function _ChalonaJsonParseValue
  Lparameters tcJson
  Local lc, c0, cLast
  lc = Alltrim(Nvl(tcJson, ""))
  If Empty(lc)
    Return ""
  Endif

  c0    = Left(lc, 1)
  cLast = Right(lc, 1)

  * Objeto
  If c0 = "{" And cLast = "}"
    Return _ChalonaJsonParseObject(lc)
  Endif

  * Arreglo
  If c0 = "[" And cLast = "]"
    Return _ChalonaJsonParseArray(lc)
  Endif

  * String con comillas
  If c0 = '"' And cLast = '"'
    Local lcInner
    lcInner = Substr(lc, 2, Len(lc) - 2)
    lcInner = Strtran(lcInner, '\"', '"')
    lcInner = Strtran(lcInner, '\\', '\')
    lcInner = Strtran(lcInner, '\n', Chr(13) + Chr(10))
    Return lcInner
  Endif

  * null
  If Upper(lc) == "NULL"
    Return .Null.
  Endif

  * Booleanos
  If Upper(lc) == "TRUE"
    Return .T.
  Endif
  If Upper(lc) == "FALSE"
    Return .F.
  Endif

  * NÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âºmero (int / float)
  If IsNumeric(lc)
    Return Val(lc)
  Endif

  * Cualquier otra cosa, string crudo
  Return lc
Endfunc

*------------------------------------------------------------
* JSON objeto: {"key": value, ...} -> Empty con propiedades
*------------------------------------------------------------
Function _ChalonaJsonParseObject
  Lparameters tcJson
  Local lc, nLen, i, c, cPrev, llInStr, lnDepth
  Local lcInner, lcCurrent, lnPairs, laPairs[1]
  Local loObj

  lc = Alltrim(Nvl(tcJson, ""))
  If Len(lc) < 2
    Return ""
  Endif

  * Quitar llaves exteriores
  lcInner = Substr(lc, 2, Len(lc) - 2)

  nLen      = Len(lcInner)
  cPrev     = ""
  llInStr   = .F.
  lnDepth   = 0
  lcCurrent = ""
  lnPairs   = 0

  For i = 1 To nLen
    c = Substr(lcInner, i, 1)

    * Estado de comillas
    If c = '"' And cPrev # "\" 
      llInStr = !llInStr
    Endif

    * Profundidad de objetos/arreglos internos
    If !llInStr
      Do Case
        Case c $ "{["
          lnDepth = lnDepth + 1
        Case c $ "}]"
          lnDepth = lnDepth - 1
      Endcase
    Endif

    If !llInStr And lnDepth = 0 And c = ","
      * Fin de un par key:value
      lnPairs = lnPairs + 1
      Dimension laPairs[Max(1, lnPairs)]
      laPairs[lnPairs] = Alltrim(lcCurrent)
      lcCurrent = ""
    Else
      lcCurrent = lcCurrent + c
    Endif

    cPrev = c
  Endfor

  * ÃƒÆ’Ã†â€™Ãƒâ€¦Ã‚Â¡ltimo par (si quedÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³ algo)
  If Not Empty(Alltrim(lcCurrent))
    lnPairs = lnPairs + 1
    Dimension laPairs[Max(1, lnPairs)]
    laPairs[lnPairs] = Alltrim(lcCurrent)
  Endif

  loObj = Createobject("Empty")

  For i = 1 To lnPairs
    lcCurrent = laPairs[i]
    If Empty(lcCurrent)
      Loop
    Endif

    * Separar key : value
    Local nSep, lcKey, lcVal, uVal
    nSep = At(":", lcCurrent)
    If nSep = 0
      Loop
    Endif

    lcKey = Left(lcCurrent, nSep - 1)
    lcVal = Ltrim(Substr(lcCurrent, nSep + 1))

    * Limpiar comillas de la clave
    lcKey = Alltrim(lcKey)
    If Left(lcKey, 1) = '"' And Right(lcKey, 1) = '"'
      lcKey = Substr(lcKey, 2, Len(lcKey) - 2)
    Endif
    lcKey = Alltrim(lcKey)

    If Empty(lcKey)
      Loop
    Endif

    * Parsear valor recursivamente
    uVal = _ChalonaJsonParseValue(lcVal)
    AddProperty(loObj, lcKey, uVal)
  Endfor

  Return loObj
Endfunc

*------------------------------------------------------------
* JSON arreglo: [ value1, value2, ... ] -> Collection
*------------------------------------------------------------
Function _ChalonaJsonParseArray
  Lparameters tcJson
  Local lc, nLen, i, c, cPrev, llInStr, lnDepth
  Local lcInner, lcCurrent, lnItems, laItems[1]
  Local loCol

  lc = Alltrim(Nvl(tcJson, ""))
  If Len(lc) < 2
    Return ""
  Endif

  * Quitar corchetes exteriores
  lcInner = Substr(lc, 2, Len(lc) - 2)

  nLen      = Len(lcInner)
  cPrev     = ""
  llInStr   = .F.
  lnDepth   = 0
  lcCurrent = ""
  lnItems   = 0

  For i = 1 To nLen
    c = Substr(lcInner, i, 1)

    * Estado de comillas
    If c = '"' And cPrev # "\" 
      llInStr = !llInStr
    Endif

    * Profundidad de objetos/arreglos internos
    If !llInStr
      Do Case
        Case c $ "{["
          lnDepth = lnDepth + 1
        Case c $ "}]"
          lnDepth = lnDepth - 1
      Endcase
    Endif

    If !llInStr And lnDepth = 0 And c = ","
      * Fin de un elemento
      lnItems = lnItems + 1
      Dimension laItems[Max(1, lnItems)]
      laItems[lnItems] = Alltrim(lcCurrent)
      lcCurrent = ""
    Else
      lcCurrent = lcCurrent + c
    Endif

    cPrev = c
  Endfor

  * ÃƒÆ’Ã†â€™Ãƒâ€¦Ã‚Â¡ltimo elemento (si quedÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³ algo)
  If Not Empty(Alltrim(lcCurrent))
    lnItems = lnItems + 1
    Dimension laItems[Max(1, lnItems)]
    laItems[lnItems] = Alltrim(lcCurrent)
  Endif

  loCol = Createobject("Collection")

  For i = 1 To lnItems
    lcCurrent = laItems[i]
    If Empty(lcCurrent)
      Loop
    Endif
    loCol.Add(_ChalonaJsonParseValue(lcCurrent))
  Endfor

  Return loCol
Endfunc

Function _ChalonaExtractJsonString
  Lparameters tcJson, tcKey
  Local lcPat, n, lc
  lcPat = '"' + Lower(tcKey) + '":"'
  n = Atc(lcPat, Lower(tcJson))
  If n = 0
    Return ""
  Endif
  lc = Substr(tcJson, n + Len(lcPat))
  Return Strextract(lc, "", '"', 1, 1)
Endfunc

Function _ChalonaExtractJsonValue
  Lparameters tcJson, tcKey
  Local n, lcRest, c0, i, nLen, nDepth, c, lcOut, lInStr, cPrev
  n = Atc('"' + Lower(tcKey) + '":', Lower(tcJson))
  If n = 0
    Return ""
  Endif
  lcRest = Substr(tcJson, n)
  n = At(":", lcRest)
  If n = 0
    Return ""
  Endif
  lcRest = Ltrim(Substr(lcRest, n + 1))
  If Empty(lcRest)
    Return ""
  Endif
  c0 = Left(lcRest, 1)
  If !(c0 $ "{[")
    If c0 = '"'
      Return '"' + Strextract(lcRest, '"', '"', 2, 1) + '"'
    Endif
    Return Strextract(Alltrim(lcRest) + ",", "", ",", 1, 1)
  Endif
  nLen = Len(lcRest)
  nDepth = 0
  lInStr = .F.
  cPrev = ""
  lcOut = ""
  For i = 1 To nLen
    c = Substr(lcRest, i, 1)
    If !lInStr And c = '"'
      lInStr = .T.
    Else
      If lInStr And c = '"' And cPrev # "\"
        lInStr = .F.
      Endif
    Endif
    If !lInStr
      Do Case
        Case c $ "{["
          nDepth = nDepth + 1
        Case c $ "}]"
          nDepth = nDepth - 1
      Endcase
    Endif
    lcOut = lcOut + c
    If nDepth = 0
      Exit
    Endif
    cPrev = c
  Endfor
  Return lcOut
Endfunc

* Literales para EXEC dinÃƒÆ’Ã‚Â¡mico vÃƒÆ’Ã‚Â­a Request (SQL Server)
Function _ChalonaSqlQuote
  Lparameters tc
  Return "'" + Strtran(Nvl(tc, ""), "'", "''") + "'"
Endfunc

Function _ChalonaSqlQuoteN
  Lparameters tc
  Return "N'" + Strtran(Nvl(tc, ""), "'", "''") + "'"
Endfunc

* VacÃƒÆ’Ã‚Â­o -> NULL en T-SQL; si no, N'...'
Function _ChalonaSqlNullableN
  Lparameters tc
  If Empty(Nvl(tc, ""))
    Return "NULL"
  Endif
  Return _ChalonaSqlQuoteN(tc)
Endfunc

* data.secuencia_utilizada -> 0/1 o NULL si no viene
Function _ChalonaSecuenciaUtilizadaSqlBit
  Lparameters loData
  Local u
  If Vartype(loData) # "O" Or !PemStatus(loData, "secuencia_utilizada", 5)
    Return "NULL"
  Endif
  u = loData.secuencia_utilizada
  Do Case
    Case Vartype(u) = "L"
      Return Iif(u, "1", "0")
    Case Vartype(u) = "N"
      Return Iif(Val(Transform(u)) # 0, "1", "0")
    Case Vartype(u) = "C"
      Return Iif(Lower(Alltrim(u)) $ "true,1,t,yes", "1", "0")
    Otherwise
      Return "NULL"
  Endcase
Endfunc

* ISO 8601 -> sin zona horaria (quitar Z / +00:00 / -04:00)
Function _ChalonaIsoSinZona
  Lparameters tc
  Local lc, lnPos, lnPos2
  lc = Alltrim(Nvl(tc, ""))
  If Empty(lc)
    Return ""
  Endif

  * quitar 'Z'
  lc = Strtran(lc, "Z", "")
  lc = Strtran(lc, "z", "")

  * cortar en +hh:mm si existe
  lnPos = At("+", lc)
  If lnPos > 0
    lc = Left(lc, lnPos - 1)
  Else
    * cortar en -hh:mm (buscar desde despuÃƒÆ’Ã‚Â©s del tiempo para no cortar la fecha YYYY-MM-DD)
    lnPos2 = At("-", Substr(lc, 20))
    If lnPos2 > 0
      lc = Left(lc, 19 + (lnPos2 - 1))
    Endif
  Endif

  Return Alltrim(lc)
Endfunc

* ISO 8601 -> SQL Server datetime (string) "YYYY-MM-DD HH:MM:SS"
* - Reemplaza 'T' por espacio
* - Quita fracciones de segundo (microsegundos) y cualquier resto
* - Devuelve "" si no tiene forma mÃ­nima esperada
Function _ChalonaIsoParaSqlDatetime
  Lparameters tc
  Local lc
  lc = Alltrim(Nvl(tc, ""))
  If Empty(lc)
    Return ""
  Endif
  * El input ideal ya viene sin zona via _ChalonaIsoSinZona; aun asÃ­ toleramos si lo llaman directo.
  lc = _ChalonaIsoSinZona(lc)
  lc = Strtran(lc, "T", " ")
  lc = Strtran(lc, "t", " ")
  * Tomar solo "YYYY-MM-DD HH:MM:SS"
  If Len(lc) < 19
    Return ""
  Endif
  lc = Left(lc, 19)
  * Chequeo mÃ­nimo de separadores
  If Substr(lc, 5, 1) # "-" Or Substr(lc, 8, 1) # "-" Or Substr(lc, 11, 1) # " "
    Return ""
  Endif
  If Substr(lc, 14, 1) # ":" Or Substr(lc, 17, 1) # ":"
    Return ""
  Endif
  Return lc
Endfunc

Function _JsonEscape
  Lparameters tc
  Local lc, i
  lc = Nvl(tc, "")
  lc = Strtran(lc, "\", "\\")
  lc = Strtran(lc, '"', '\"')
  lc = Strtran(lc, Chr(13) + Chr(10), "\n")
  lc = Strtran(lc, Chr(13), "\n")
  lc = Strtran(lc, Chr(10), "\n")
  lc = Strtran(lc, Chr(9), "\t")
  * Eliminar otros chars de control (0x01-0x08, 0x0B, 0x0C, 0x0E-0x1F) que rompen JSON.
  For i = 1 To 31
    Do Case
      Case i = 9 Or i = 10 Or i = 13
        * ya manejados
      Otherwise
        If Chr(i) $ lc
          lc = Strtran(lc, Chr(i), "")
        Endif
    Endcase
  Endfor
  Return lc
Endfunc

Function IsNumeric
  Lparameters tcValor
  Local lc, lnLen, i, c, llDot

  lc = Alltrim(Transform(Nvl(tcValor, "")))
  If Empty(lc)
    Return .F.
  Endif

  lnLen = Len(lc)
  llDot = .F.

  For i = 1 To lnLen
    c = Substr(lc, i, 1)

    * Signo al inicio
    If i = 1 And c $ "+-"
      Loop
    Endif

    * Punto decimal (solo uno)
    If c = "."
      If llDot
        Return .F.
      Else
        llDot = .T.
        Loop
      Endif
    Endif

    * El resto deben ser dÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­gitos
    If !Isdigit(c)
      Return .F.
    Endif
  Endfor

  Return .T.
Endfunc


*------------------------------------------------------------
* Config ECF: motor agnóstico — opera contra un objeto loCfg.
* Helpers para construir el objeto desde Public osis (default Vicortiz).
*------------------------------------------------------------

* Lee una propiedad del objeto de configuración como cadena.
* toCfg debe exponer servidor_ecf, usuario_sync, pass_sync, portal_dgii,
* dgii_multimoneda. Devuelve "" si toCfg no es objeto, prop vacía o no existe.
Function ChalonaEcfCfgProp
  Lparameters tcProp, toCfg
  Local u
  tcProp = Lower(Alltrim(Nvl(tcProp, "")))
  If Vartype(toCfg) # "O" Or Empty(tcProp)
    Return ""
  Endif
  If !Pemstatus(toCfg, tcProp, 5)
    Return ""
  Endif
  Do Case
  Case tcProp == "servidor_ecf"
    u = toCfg.servidor_ecf
  Case tcProp == "usuario_sync"
    u = toCfg.usuario_sync
  Case tcProp == "pass_sync"
    u = toCfg.pass_sync
  Case tcProp == "portal_dgii"
    u = toCfg.portal_dgii
  Case tcProp == "dgii_multimoneda"
    u = toCfg.dgii_multimoneda
  Otherwise
    Return ""
  Endcase
  Do Case
  Case Vartype(u) = "C" Or Vartype(u) = "M"
    Return Alltrim(u)
  Case Vartype(u) = "L"
    Return Iif(u, "T", "F")
  Otherwise
    Return Alltrim(Transform(u))
  Endcase
Endfunc


* Construye objeto de config leyendo Public osis (default ERP Vicortiz).
* ERPs sin osis deben construir su propio objeto e inyectarlo con SetConfig().
Function ChalonaEcfConfigDesdeOsis
  Local lo
  lo = Createobject("Empty")
  AddProperty(lo, "servidor_ecf",     "")
  AddProperty(lo, "usuario_sync",     "")
  AddProperty(lo, "pass_sync",        "")
  AddProperty(lo, "portal_dgii",      "")
  AddProperty(lo, "dgii_multimoneda", "")
  If Type("osis") # "O"
    Return lo
  Endif
  If Pemstatus(osis, "servidor_ecf", 5)
    lo.servidor_ecf = Alltrim(Transform(Nvl(osis.servidor_ecf, "")))
  Endif
  If Pemstatus(osis, "usuario_sync", 5)
    lo.usuario_sync = Alltrim(Transform(Nvl(osis.usuario_sync, "")))
  Endif
  If Pemstatus(osis, "pass_sync", 5)
    lo.pass_sync = Alltrim(Transform(Nvl(osis.pass_sync, "")))
  Endif
  If Pemstatus(osis, "portal_dgii", 5)
    lo.portal_dgii = Alltrim(Transform(Nvl(osis.portal_dgii, "")))
  Endif
  If Pemstatus(osis, "dgii_multimoneda", 5)
    Local u
    u = osis.dgii_multimoneda
    Do Case
    Case Vartype(u) = "L"
      lo.dgii_multimoneda = Iif(u, "T", "F")
    Otherwise
      lo.dgii_multimoneda = Alltrim(Transform(Nvl(u, "")))
    Endcase
  Endif
  Return lo
Endfunc
