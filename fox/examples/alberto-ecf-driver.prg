*-----------------------------------------------------------------------------
* AlbertoEcfDriver  (driver para cliente Alberto - DBFs locales)
*
* Implementa el contrato del driver de chalona-ecf.prg cuando los datos
* viven en tablas DBF (no SQL Server). Sustituye a ChalonaEcfDriverSqlServer.
*
* INSTANCIACION:
*   loEcf = Createobject("ChalonaEcf")
*   loEcf.SetDriver(Createobject("AlbertoEcfDriver"))
*   loEcf.Enviar(tcControl)
*
* FORMATO tcControl:
*   "<tipo_ecf>|<numero_documento>"   ej: "32|12345"
*   La empresa se toma de la variable global VFP `mEmpresa`.
*
* MAPEO POR TIPO  (basado en ecf/clients/fox/alberto/cncfe_document.prg):
*   31 (FCF)              -> cxc      transa=3   join cliente, vendedor
*   32 (FC consumo)       -> ventas   transa=4   rnc/nombre inline
*   33 (ND)               -> cxc      transa=?   (mismo que 31, ver TODO)
*   34 (NC)               -> ncr      transa=107 join cliente, vendedor
*   41 (Compra)           -> compras  transa=2   join suplidor (cncfe_document.cNcfE_CompraMercancia)
*   43 (Gasto Menor)      -> reggasto             join nada
*
* PRECONDICION: todas las DBF deben estar en el path actual de VFP.
* Variable global mEmpresa setteada antes de instanciar el driver.
*
* ESTADO RESPUESTA / SYNC:
*   GuardarRespuestaEnvio / MarcarErrorEnvio: no-op (.T.). Alberto sincroniza
*   estados via pull periodico /cg/ecf/ecfGetUpdates -> tabla sync_ecf.
*   Sync* methods: lock por archivo, listados vacios (sin tabla unificada).
*-----------------------------------------------------------------------------

Define Class AlbertoEcfDriver As Custom

  * Referencia NC/ND: setteadas por CargarMaestro tipo 34, leidas por CargarReferenciaImtr.
  oRefEncfPending = ""
  oRefFechaPending = .Null.
  oRefCodigoMod = 3
  * Path del lock file para sync masivo (relativo al directorio de datos).
  cLockPath = "data\chalonaecf_sync.lck"
  lLockOwned = .F.

  *-------------------------------------------------------------------------
  Procedure _ParseControl
    Lparameters tcControl, tnTipo, tnNumero
    Local lcCtrl, lnPipe
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    lcCtrl = Alltrim(tcControl)
    lnPipe = At("|", lcCtrl)
    If lnPipe < 1
      tnTipo = 0
      tnNumero = 0
      Return
    Endif
    tnTipo = Val(Left(lcCtrl, lnPipe - 1))
    tnNumero = Val(Substr(lcCtrl, lnPipe + 1))
  Endproc

  *-------------------------------------------------------------------------
  Procedure _CrearCursorMaestro
    Lparameters tcAlias
    Create Cursor (tcAlias) ;
      (fiscal      C(2), ;
       encf        C(20), ;
       control     C(40), ;
       fecha       D, ;
       valor       N(15,2), ;
       descuento   N(15,2), ;
       itbis       N(15,2), ;
       total       N(15,2), ;
       tasa        N(15,4), ;
       moneda      C(10), ;
       rnc         C(20), ;
       nombre      C(150), ;
       entidad     C(20), ;
       ocontrol    C(40), ;
       fechavencencf D, ;
       dgii_codmod N(2), ;
       itbisr      N(15,2), ;
       isr         N(15,2), ;
       comentario  C(200), ;
       referencia  C(40), ;
       doc         C(40), ;
       numero      C(40), ;
       ncf         C(20))
  Endproc

  *-------------------------------------------------------------------------
  Function CargarMaestro
    Lparameters tcControl
    Local lnTipo, lnNumero, llOk
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    This._ParseControl(tcControl, @lnTipo, @lnNumero)
    If lnTipo = 0 Or lnNumero <= 0
      Return ""
    Endif

    ChalonaEcfUseInIfUsed("curChalMae")
    This._CrearCursorMaestro("curChalMae")
    llOk = .F.

    Try
      Do Case
      Case lnTipo = 32
        llOk = This._CargarMaestroVentas(lnNumero, "32", 4)
      Case lnTipo = 31
        llOk = This._CargarMaestroCxc(lnNumero, "31", 3)
      Case lnTipo = 33
        * TODO: confirmar transa correcto para Nota Debito (probablemente cxc).
        llOk = This._CargarMaestroCxc(lnNumero, "33", 3)
      Case lnTipo = 34
        llOk = This._CargarMaestroNcr(lnNumero)
      Case lnTipo = 41
        llOk = This._CargarMaestroCompras(lnNumero)
      Case lnTipo = 43
        llOk = This._CargarMaestroReggasto(lnNumero)
      Endcase
    Catch To loEx
      ChalonaEcfLogException("AlbertoEcfDriver.CargarMaestro", tcControl, loEx, "")
      llOk = .F.
    Endtry

    If !llOk
      ChalonaEcfUseInIfUsed("curChalMae")
      Return ""
    Endif
    Select curChalMae
    Go Top
    Return "curChalMae"
  Endfunc

  *-------------------------------------------------------------------------
  * Tipo 32: ventas transa=4. RNC/nombre inline en ventas.
  Function _CargarMaestroVentas
    Lparameters tnNumero, tcTipo, tnTransa
    Local lcCtrl, lnSel
    lnSel = Select()
    If !Used("ventas")
      Use ventas Again Shared In 0
    Endif
    Select ventas
    Locate For factura = tnNumero And transa = tnTransa And empresa = mEmpresa
    If !Found()
      Select (lnSel)
      Return .F.
    Endif
    lcCtrl = Alltrim(tcTipo) + "|" + Alltrim(Transform(ventas.factura))
    Insert Into curChalMae (fiscal, encf, control, fecha, valor, descuento, itbis, total, ;
                            tasa, moneda, rnc, nombre, entidad, ocontrol, ;
                            fechavencencf, dgii_codmod) ;
      Values (tcTipo, ;
              Alltrim(Nvl(ventas.ncf, "")), ;
              lcCtrl, ;
              ventas.fecha, ;
              This._NumProp("ventas", "valor"), ;
              This._NumProp("ventas", "descuento"), ;
              This._NumProp("ventas", "itbis"), ;
              This._NumProp("ventas", "total"), ;
              This._TasaProp("ventas"), ;
              This._MonedaProp("ventas"), ;
              This._StrProp("ventas", "rnc"), ;
              This._StrProp("ventas", "nombre"), ;
              Alltrim(Transform(ventas.codigo)), ;
              "", ;
              This._FechaProp("ventas", "ncfvence"), ;
              3)
    Select (lnSel)
    Return .T.
  Endfunc

  *-------------------------------------------------------------------------
  * Tipo 31/33: cxc. RNC viene de cliente (join).
  Function _CargarMaestroCxc
    Lparameters tnNumero, tcTipo, tnTransa
    Local lcCtrl, lnSel, lcCodCli, lcRnc, lcNom
    lnSel = Select()
    If !Used("cxc")
      Use cxc Again Shared In 0
    Endif
    Select cxc
    Locate For factura = tnNumero And transa = tnTransa And empresa = mEmpresa
    If !Found()
      Select (lnSel)
      Return .F.
    Endif
    lcCodCli = Alltrim(Transform(cxc.codigo))
    lcCtrl = Alltrim(tcTipo) + "|" + Alltrim(Transform(cxc.factura))
    * Lookup cliente para rnc/nombre.
    lcRnc = ""
    lcNom = ""
    If !Used("cliente")
      Use cliente Again Shared In 0
    Endif
    Select cliente
    Locate For codigo = cxc.codigo And empresa = mEmpresa
    If Found()
      lcRnc = This._StrProp("cliente", "rnc")
      lcNom = This._StrProp("cliente", "cliente")
    Endif

    Select cxc
    Insert Into curChalMae (fiscal, encf, control, fecha, valor, descuento, itbis, total, ;
                            tasa, moneda, rnc, nombre, entidad, ocontrol, ;
                            fechavencencf, dgii_codmod) ;
      Values (tcTipo, ;
              Alltrim(Nvl(cxc.ncf, "")), ;
              lcCtrl, ;
              cxc.fecha, ;
              This._NumProp("cxc", "valor"), ;
              This._NumProp("cxc", "descuento"), ;
              This._NumProp("cxc", "itbis"), ;
              This._NumProp("cxc", "total"), ;
              This._TasaProp("cxc"), ;
              This._MonedaProp("cxc"), ;
              lcRnc, lcNom, lcCodCli, ;
              "", ;
              This._FechaProp("cxc", "ncfvence"), ;
              3)
    Select (lnSel)
    Return .T.
  Endfunc

  *-------------------------------------------------------------------------
  * Tipo 34: ncr transa=107. Setea referencia (ncfa, vence2) en propiedades.
  Function _CargarMaestroNcr
    Lparameters tnNumero
    Local lcCtrl, lnSel, lcCodCli, lcRnc, lcNom, lcOctl, lnCodMod
    lnSel = Select()
    If !Used("ncr")
      Use ncr Again Shared In 0
    Endif
    Select ncr
    Locate For factura = tnNumero And transa = 107 And empresa = mEmpresa
    If !Found()
      Select (lnSel)
      Return .F.
    Endif
    lcCodCli = Alltrim(Transform(ncr.codigo))
    lcCtrl = "34|" + Alltrim(Transform(ncr.factura))

    * Capturar referencia para CargarReferenciaImtr.
    This.oRefEncfPending = This._StrProp("ncr", "ncfa")
    This.oRefFechaPending = This._FechaProp("ncr", "vence2")
    lnCodMod = 0
    If Type("ncr.pago") != "U"
      lnCodMod = Int(Nvl(ncr.pago, 0))
    Endif
    If lnCodMod < 1 Or lnCodMod > 5
      lnCodMod = 3
    Endif
    This.oRefCodigoMod = lnCodMod
    * ocontrol no vacio dispara en motor la llamada a CargarReferenciaImtr.
    lcOctl = "ALB:" + This.oRefEncfPending

    * Lookup cliente para rnc/nombre.
    lcRnc = ""
    lcNom = ""
    If !Used("cliente")
      Use cliente Again Shared In 0
    Endif
    Select cliente
    Locate For codigo = ncr.codigo And empresa = mEmpresa
    If Found()
      lcRnc = This._StrProp("cliente", "rnc")
      lcNom = This._StrProp("cliente", "cliente")
    Endif

    Select ncr
    Insert Into curChalMae (fiscal, encf, control, fecha, valor, descuento, itbis, total, ;
                            tasa, moneda, rnc, nombre, entidad, ocontrol, ;
                            fechavencencf, dgii_codmod) ;
      Values ("34", ;
              Alltrim(Nvl(ncr.ncf, "")), ;
              lcCtrl, ;
              ncr.fecha, ;
              This._NumProp("ncr", "monto"), ;
              0, ;
              This._NumProp("ncr", "itbis"), ;
              This._NumProp("ncr", "total"), ;
              This._TasaProp("ncr"), ;
              This._MonedaProp("ncr"), ;
              lcRnc, lcNom, lcCodCli, ;
              lcOctl, ;
              This._FechaProp("ncr", "vence"), ;
              lnCodMod)
    Select (lnSel)
    Return .T.
  Endfunc

  *-------------------------------------------------------------------------
  * Tipo 41: compras transa=2. Join suplidor para rnc/nombre.
  Function _CargarMaestroCompras
    Lparameters tnNumero
    Local lcCtrl, lnSel, lcCodSup, lcRnc, lcNom
    lnSel = Select()
    If !Used("compras")
      Use compras Again Shared In 0
    Endif
    Select compras
    Locate For factura = tnNumero And transa = 2 And empresa = mEmpresa
    If !Found()
      Select (lnSel)
      Return .F.
    Endif
    lcCodSup = Alltrim(Transform(compras.codigo))
    lcCtrl = "41|" + Alltrim(Transform(compras.factura))

    lcRnc = ""
    lcNom = ""
    If !Used("suplidor")
      Use suplidor Again Shared In 0
    Endif
    Select suplidor
    Locate For codigo = compras.codigo And empresa = mEmpresa
    If Found()
      lcRnc = This._StrProp("suplidor", "rnc")
      lcNom = This._StrProp("suplidor", "suplidor")
    Endif

    Select compras
    Insert Into curChalMae (fiscal, encf, control, fecha, valor, descuento, itbis, total, ;
                            tasa, moneda, rnc, nombre, entidad, ocontrol, ;
                            fechavencencf, dgii_codmod, ;
                            comentario, referencia, doc, numero, ncf, itbisr, isr) ;
      Values ("41", ;
              Alltrim(Nvl(compras.ncf, "")), ;
              lcCtrl, ;
              This._FechaProp("compras", "fecha2"), ;
              This._NumProp("compras", "valor"), ;
              This._NumProp("compras", "descuento"), ;
              This._NumProp("compras", "itbis"), ;
              This._NumProp("compras", "total"), ;
              This._TasaProp("compras"), ;
              This._MonedaProp("compras"), ;
              lcRnc, lcNom, lcCodSup, ;
              "", ;
              This._FechaProp("compras", "ncfvence"), ;
              3, ;
              "", "", "", ;
              Alltrim(Transform(compras.factura)), ;
              Alltrim(Nvl(compras.ncf, "")), ;
              This._NumProp("compras", "ritbis"), ;
              This._NumProp("compras", "risr"))
    Select (lnSel)
    Return .T.
  Endfunc

  *-------------------------------------------------------------------------
  * Tipo 43: reggasto. Sin join.
  Function _CargarMaestroReggasto
    Lparameters tnNumero
    Local lcCtrl, lnSel, lcCom
    lnSel = Select()
    If !Used("reggasto")
      Use reggasto Again Shared In 0
    Endif
    Select reggasto
    Locate For numero = tnNumero And empresa = mEmpresa
    If !Found()
      Select (lnSel)
      Return .F.
    Endif
    lcCtrl = "43|" + Alltrim(Transform(reggasto.numero))
    lcCom = This._StrProp("reggasto", "comentario")

    Insert Into curChalMae (fiscal, encf, control, fecha, valor, descuento, itbis, total, ;
                            tasa, moneda, rnc, nombre, entidad, ocontrol, ;
                            fechavencencf, dgii_codmod, ;
                            comentario, referencia, doc, numero, ncf) ;
      Values ("43", ;
              Alltrim(Nvl(reggasto.ncf, "")), ;
              lcCtrl, ;
              reggasto.fecha, ;
              This._NumProp("reggasto", "importe"), ;
              0, ;
              0, ;
              This._NumProp("reggasto", "importe"), ;
              This._TasaProp("reggasto"), ;
              This._MonedaProp("reggasto"), ;
              "", "", "", ;
              "", ;
              This._FechaProp("reggasto", "ncfvence"), ;
              3, ;
              lcCom, ;
              This._StrProp("reggasto", "referencia"), ;
              This._StrProp("reggasto", "doc"), ;
              Alltrim(Transform(reggasto.numero)), ;
              Alltrim(Nvl(reggasto.ncf, "")))
    Select (lnSel)
    Return .T.
  Endfunc

  *-------------------------------------------------------------------------
  * Helpers de campo defensivos (campo puede no existir).
  Function _NumProp
    Lparameters tcAlias, tcField
    Local lcRef
    lcRef = tcAlias + "." + tcField
    If Type(lcRef) = "U"
      Return 0
    Endif
    Return _ChalonaEcfNzNum(Evaluate(lcRef))
  Endfunc

  Function _StrProp
    Lparameters tcAlias, tcField
    Local lcRef
    lcRef = tcAlias + "." + tcField
    If Type(lcRef) = "U"
      Return ""
    Endif
    Return Alltrim(Transform(Nvl(Evaluate(lcRef), "")))
  Endfunc

  Function _FechaProp
    Lparameters tcAlias, tcField
    Local lcRef
    lcRef = tcAlias + "." + tcField
    If Type(lcRef) = "U" Or Type(lcRef) # "D"
      Return {/}
    Endif
    Return Evaluate(lcRef)
  Endfunc

  Function _TasaProp
    Lparameters tcAlias
    Local lnT
    lnT = This._NumProp(tcAlias, "tasa")
    If lnT < 1
      Return 1
    Endif
    Return lnT
  Endfunc

  Function _MonedaProp
    Lparameters tcAlias
    Local lcM
    lcM = This._StrProp(tcAlias, "moneda")
    If Empty(lcM)
      Return "DOP"
    Endif
    Return lcM
  Endfunc

  *-------------------------------------------------------------------------
  Function EsGastos
    Lparameters tcControl
    Local lnTipo, lnNumero
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    This._ParseControl(tcControl, @lnTipo, @lnNumero)
    Return Inlist(lnTipo, 41, 43)
  Endfunc

  *-------------------------------------------------------------------------
  * Detalle: shape esperado por motor: precio, cantidad, descrip, mercs_nombre,
  * mercs_servicio (0 mercancia, 2 servicio), itbis_retenido, isr_retenido.
  Function CargarDetalle
    Lparameters tcControl
    Local lnTipo, lnNumero, llOk
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    This._ParseControl(tcControl, @lnTipo, @lnNumero)
    If lnNumero <= 0
      Return ""
    Endif

    ChalonaEcfUseInIfUsed("curChalDet")
    Create Cursor curChalDet ;
      (precio N(18,6), cantidad N(18,4), descrip C(200), mercs_nombre C(200), ;
       mercs_servicio N(2), itbis_retenido N(15,2), isr_retenido N(15,2))

    llOk = .F.
    Try
      Do Case
      Case lnTipo = 32
        llOk = This._CargarDetalleVentas(lnNumero, 4)
      Case Inlist(lnTipo, 31, 33)
        llOk = This._CargarDetalleCxc(lnNumero, 3)
      Case lnTipo = 34
        llOk = This._CargarDetalleNc(lnNumero)
      Otherwise
        * Gastos (41/43): el motor sintetiza el detalle. No llama esto.
        llOk = .T.
      Endcase
    Catch To loEx
      ChalonaEcfLogException("AlbertoEcfDriver.CargarDetalle", tcControl, loEx, "")
      llOk = .F.
    Endtry

    If !llOk
      ChalonaEcfUseInIfUsed("curChalDet")
      Return ""
    Endif
    Return "curChalDet"
  Endfunc

  *-------------------------------------------------------------------------
  Function _CargarDetalleVentas
    Lparameters tnNumero, tnTransa
    Local lnSel, lcDescr, lnPItbis, lnIndBs
    lnSel = Select()
    If !Used("detalle")
      Use detalle Again Shared In 0
    Endif
    Select detalle
    Scan For factura = tnNumero And transa = tnTransa And empresa = mEmpresa
      lcDescr = ""
      If !Used("producto")
        Use producto Again Shared In 0
      Endif
      Select producto
      Locate For codigo = detalle.producto And empresa = mEmpresa
      If Found()
        lcDescr = This._StrProp("producto", "nombre")
      Endif
      Select detalle
      lnPItbis = This._NumProp("detalle", "itbisporc")
      * mercs_servicio: 2 servicio, 0/1 mercancia. Asumimos 0 (mercancia) por defecto.
      lnIndBs = 0
      Insert Into curChalDet (precio, cantidad, descrip, mercs_nombre, mercs_servicio, ;
                              itbis_retenido, isr_retenido) ;
        Values (This._NumProp("detalle", "precio"), ;
                This._NumProp("detalle", "cantidad"), ;
                lcDescr, lcDescr, lnIndBs, 0, 0)
    Endscan
    Select (lnSel)
    Return .T.
  Endfunc

  Function _CargarDetalleCxc
    Lparameters tnNumero, tnTransa
    Return This._CargarDetalleVentas(tnNumero, tnTransa)
  Endfunc

  *-------------------------------------------------------------------------
  * NC: detalle sintetico (basado en cncfe_document.cNcfE_NotaCredito.pGetDetalle).
  * Separa monto exento y monto con 18% segun ncr.itbis.
  Function _CargarDetalleNc
    Lparameters tnNumero
    Local lnSel, lnMonto, lnItbis, lnTotal, lnM18, lnM00, lcConcepto
    lnSel = Select()
    If !Used("ncr")
      Use ncr Again Shared In 0
    Endif
    Select ncr
    Locate For factura = tnNumero And transa = 107 And empresa = mEmpresa
    If !Found()
      Select (lnSel)
      Return .F.
    Endif
    lnMonto = This._NumProp("ncr", "monto")
    lnItbis = This._NumProp("ncr", "itbis")
    lnTotal = This._NumProp("ncr", "total")
    lcConcepto = This._StrProp("ncr", "concepto1")

    lnM18 = 0
    If lnItbis > 0
      lnM18 = Round(lnItbis / 0.18, 2)
    Endif
    lnM00 = lnMonto - lnM18

    If lnM18 > 0
      Insert Into curChalDet (precio, cantidad, descrip, mercs_nombre, mercs_servicio, ;
                              itbis_retenido, isr_retenido) ;
        Values (lnM18, 1, Alltrim(lcConcepto) + "  CON 18% ITBIS", ;
                Alltrim(lcConcepto) + "  CON 18% ITBIS", 0, 0, 0)
    Endif
    If lnM00 > 0
      Insert Into curChalDet (precio, cantidad, descrip, mercs_nombre, mercs_servicio, ;
                              itbis_retenido, isr_retenido) ;
        Values (lnM00, 1, Alltrim(lcConcepto) + "  EXENTO", ;
                Alltrim(lcConcepto) + "  EXENTO", 0, 0, 0)
    Endif
    Select (lnSel)
    Return .T.
  Endfunc

  *-------------------------------------------------------------------------
  * fiscal en Alberto solo tiene prefijo+contador (no vence). El motor lee
  * fechavencencf del maestro como prioridad; si esta vacio cae aqui.
  Function CargarFiscalVence
    Lparameters tcTipoEcf
    If Vartype(tcTipoEcf) # "C"
      tcTipoEcf = ""
    Endif
    ChalonaEcfUseInIfUsed("curChalFis")
    Create Cursor curChalFis (vence D)
    * Sin filas: motor abortara con ecf.iddoc.fecha_vencimiento_requerida si fechavencencf esta vacio.
    Return "curChalFis"
  Endfunc

  *-------------------------------------------------------------------------
  Function CargarEmpresa
    Local lnSel
    ChalonaEcfUseInIfUsed("curChalEmp")
    Create Cursor curChalEmp (rnc C(20), nombre C(150), direccion C(200), iprecio N(1))
    lnSel = Select()
    Try
      If !Used("empresa")
        Use empresa Again Shared In 0
      Endif
      Select empresa
      Locate For codigo = mEmpresa
      If Found()
        Insert Into curChalEmp (rnc, nombre, direccion, iprecio) ;
          Values (This._StrProp("empresa", "rnc"), ;
                  This._StrProp("empresa", "nombre"), ;
                  This._StrProp("empresa", "direccion"), ;
                  This._NumProp("empresa", "iprecio"))
      Endif
    Catch
    Endtry
    Select (lnSel)
    Return "curChalEmp"
  Endfunc

  *-------------------------------------------------------------------------
  Function CargarSuplidorRncNombre
    Lparameters tcCodigo
    Local lnSel
    If Vartype(tcCodigo) # "C"
      tcCodigo = ""
    Endif
    ChalonaEcfUseInIfUsed("curChalSup")
    Create Cursor curChalSup (rnc C(20), nombre C(150))
    lnSel = Select()
    Try
      If !Used("suplidor")
        Use suplidor Again Shared In 0
      Endif
      Select suplidor
      Locate For Alltrim(Transform(codigo)) == Alltrim(tcCodigo) And empresa = mEmpresa
      If Found()
        Insert Into curChalSup (rnc, nombre) ;
          Values (This._StrProp("suplidor", "rnc"), ;
                  This._StrProp("suplidor", "suplidor"))
      Endif
    Catch
    Endtry
    Select (lnSel)
    Return "curChalSup"
  Endfunc

  *-------------------------------------------------------------------------
  * extranjero: Alberto no tiene columna 'extranjero' en cliente/suplidor.
  * Devolvemos extranjero_flag=0; el motor luego marcara extranjero=1 si el
  * RNC no es identificador fiscal RD valido.
  Function CargarTerceroExtranjero
    Lparameters tcCodigo, tlEsGastos
    Local lnSel, lcTabla, lcAliasFld
    If Vartype(tcCodigo) # "C"
      tcCodigo = ""
    Endif
    If Vartype(tlEsGastos) # "L"
      tlEsGastos = .F.
    Endif
    ChalonaEcfUseInIfUsed("curChalCli")
    Create Cursor curChalCli (extranjero_flag N(1), rnc C(20), nombre C(150))
    lnSel = Select()
    Try
      If tlEsGastos
        lcTabla = "suplidor"
        lcAliasFld = "suplidor"
      Else
        lcTabla = "cliente"
        lcAliasFld = "cliente"
      Endif
      If !Used(lcTabla)
        Use (lcTabla) Again Shared In 0
      Endif
      Select (lcTabla)
      Locate For Alltrim(Transform(codigo)) == Alltrim(tcCodigo) And empresa = mEmpresa
      If Found()
        Insert Into curChalCli (extranjero_flag, rnc, nombre) ;
          Values (0, ;
                  This._StrProp(lcTabla, "rnc"), ;
                  This._StrProp(lcTabla, lcAliasFld))
      Endif
    Catch
    Endtry
    Select (lnSel)
    Return "curChalCli"
  Endfunc

  *-------------------------------------------------------------------------
  * Para NC/ND el motor llama esto con lcOcontrol = curChalMae.ocontrol.
  * En NC seteamos ocontrol = "ALB:" + ncfa; aprovechamos las propiedades
  * oRefEncfPending / oRefFechaPending capturadas en CargarMaestroNcr.
  Function CargarReferenciaImtr
    Lparameters tcOcontrol
    If Vartype(tcOcontrol) # "C"
      tcOcontrol = ""
    Endif
    ChalonaEcfUseInIfUsed("curChalRef")
    Create Cursor curChalRef (encf C(20), fecha D)
    If !Empty(This.oRefEncfPending)
      Insert Into curChalRef (encf, fecha) ;
        Values (Alltrim(This.oRefEncfPending), ;
                Iif(Vartype(This.oRefFechaPending) = "D", This.oRefFechaPending, {/}))
    Endif
    Return "curChalRef"
  Endfunc

  *-------------------------------------------------------------------------
  Function ContarOrigen
    Lparameters tcControl
    Local loRes, lnTipo, lnNumero, lnSel, lnFound
    loRes = Createobject("Empty")
    AddProperty(loRes, "imtr", 0)
    AddProperty(loRes, "gastos", 0)
    If Vartype(tcControl) # "C"
      tcControl = ""
    Endif
    This._ParseControl(tcControl, @lnTipo, @lnNumero)
    If lnNumero <= 0
      Return loRes
    Endif

    lnSel = Select()
    lnFound = 0
    Try
      Do Case
      Case lnTipo = 32
        If !Used("ventas")
          Use ventas Again Shared In 0
        Endif
        Select ventas
        Locate For factura = lnNumero And transa = 4 And empresa = mEmpresa
        lnFound = Iif(Found(), 1, 0)
        loRes.imtr = lnFound
      Case Inlist(lnTipo, 31, 33)
        If !Used("cxc")
          Use cxc Again Shared In 0
        Endif
        Select cxc
        Locate For factura = lnNumero And transa = 3 And empresa = mEmpresa
        lnFound = Iif(Found(), 1, 0)
        loRes.imtr = lnFound
      Case lnTipo = 34
        If !Used("ncr")
          Use ncr Again Shared In 0
        Endif
        Select ncr
        Locate For factura = lnNumero And transa = 107 And empresa = mEmpresa
        lnFound = Iif(Found(), 1, 0)
        loRes.imtr = lnFound
      Case lnTipo = 41
        If !Used("compras")
          Use compras Again Shared In 0
        Endif
        Select compras
        Locate For factura = lnNumero And transa = 2 And empresa = mEmpresa
        lnFound = Iif(Found(), 1, 0)
        loRes.gastos = lnFound
      Case lnTipo = 43
        If !Used("reggasto")
          Use reggasto Again Shared In 0
        Endif
        Select reggasto
        Locate For numero = lnNumero And empresa = mEmpresa
        lnFound = Iif(Found(), 1, 0)
        loRes.gastos = lnFound
      Endcase
    Catch
    Endtry
    Select (lnSel)
    Return loRes
  Endfunc

  *-------------------------------------------------------------------------
  * No-op: Alberto sincroniza estados via pull (/cg/ecf/ecfGetUpdates -> sync_ecf).
  Function GuardarRespuestaEnvio
    Lparameters tcControl, loData, tlEsGastos
    Return .T.
  Endfunc

  Function MarcarErrorEnvio
    Lparameters tcControl, tcMensaje, tlEsGastos
    Return .T.
  Endfunc

  *-------------------------------------------------------------------------
  * Lock por archivo (sin SQL Server).
  Function SyncIntentarLock
    Local lnH
    If File(This.cLockPath)
      Return -1
    Endif
    lnH = Fcreate(This.cLockPath)
    If lnH < 0
      Return -99
    Endif
    Fclose(lnH)
    This.lLockOwned = .T.
    Return 0
  Endfunc

  Procedure SyncLiberarLock
    If This.lLockOwned And File(This.cLockPath)
      Erase (This.cLockPath)
    Endif
    This.lLockOwned = .F.
  Endproc

  *-------------------------------------------------------------------------
  * No hay tabla unificada de estados en Alberto. Cursor vacio con shape
  * completo (mismo que el driver default) para que el motor pueda escribir
  * sin error si en algun momento agregamos pendientes.
  Function SyncListarPendientes
    ChalonaEcfUseInIfUsed("curChalonaEncfEnProceso")
    Create Cursor curChalonaEncfEnProceso ;
      (control C(40), encf C(20), es_gastos L, ;
       numero C(20), estado C(200), estado_descripcion C(500), ;
       codigo_seguridad C(200), fecha_firma C(100), timbre C(500), ;
       secuencia_utilizada N(1), momento C(50))
    Return "curChalonaEncfEnProceso"
  Endfunc

  Function SyncListarDuplicados
    ChalonaEcfUseInIfUsed("curChalDup")
    Create Cursor curChalDup (control C(40))
    Return "curChalDup"
  Endfunc

  *-------------------------------------------------------------------------
  * Alberto sincroniza estados via pull /cg/ecf/ecfGetUpdates -> sync_ecf.
  * Aqui no persistimos nada al final del SincronizarEstadosEnProceso.
  Function SyncFinalizar
    Return .T.
  Endfunc

EndDefine
