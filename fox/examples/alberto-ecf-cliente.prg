*-----------------------------------------------------------------------------
* AlbertoEcfCliente
*
* Codigo de aplicacion Alberto sobre la nueva API publica de goChalonaEcf.
* Reemplaza al antiguo AlbertoEcfDriver (no se inyecta nada al motor).
*
* Convenciones Alberto:
*   - Datos en DBF locales (ventas, cxc, ncr, compras, reggasto, ...)
*   - Variable global mEmpresa filtra todo
*   - Control format = "<tipo>|<numero>"   ej: "32|12345"
*
* Uso desde la app Alberto:
*   loResp = AlbertoEnviarEcf(32, 12345)
*   loResp = AlbertoSincronizarEstados()
*-----------------------------------------------------------------------------

#Define ALB_LOCK_PATH  "data\chalonaecf_sync.lck"

*=============================================================================
* ENVIAR
*   AlbertoEnviarEcf(32, 12345) -> ChalonaResponse
*=============================================================================
Function AlbertoEnviarEcf
  Lparameters tnTipo, tnNumero

  * 1. Bootstrap loader (publica goChalonaEcf si no esta).
  If !_ChalonaLoaderInit()
    Return _ChalonaLoaderFail("alberto.loader.no_disponible")
  Endif

  Local lcCtrl, loResp
  lcCtrl = Alltrim(Transform(tnTipo)) + "|" + Alltrim(Transform(tnNumero))

  * 2. Pedir al motor que cree TODOS los cursores con shape rigido.
  goChalonaEcf.CrearCursores()

  * 3. Llenar cursores con datos de Alberto (DBF locales).
  If !_AlbLlenarMaestro(tnTipo, tnNumero, lcCtrl)
    Return ChalonaResponseNew(.F., "alberto.maestro_no_encontrado", "", "")
  Endif
  _AlbLlenarDetalle(tnTipo, tnNumero)
  _AlbLlenarEmpresa()
  _AlbLlenarTercero(tnTipo)
  _AlbLlenarReferencia()                  && solo aplica a NC tipo 34

  * 4. Motor lee cursores, envia DGII y REESCRIBE curChalMae con la respuesta
  *    (encf, estado, codigo_seguridad, fecha_firma, timbre, ...).
  loResp = goChalonaEcf.EnviarDesdeCursores(lcCtrl)

  * 4.b. Reintento si loader pide actualizacion.
  If _ChalonaLoaderEsVersionDesact(loResp)
    If _ChalonaLoaderDescargar()
      goChalonaEcf.CrearCursores()
      _AlbLlenarMaestro(tnTipo, tnNumero, lcCtrl)
      _AlbLlenarDetalle(tnTipo, tnNumero)
      _AlbLlenarEmpresa()
      _AlbLlenarTercero(tnTipo)
      _AlbLlenarReferencia()
      loResp = goChalonaEcf.EnviarDesdeCursores(lcCtrl)
    Endif
  Endif

  * 5. Persistir respuesta en tablas Alberto (sync_ecf, ventas.ncf, etc.).
  If loResp.ok
    _AlbPersistirRespuesta(tnTipo, tnNumero)
  Endif

  Return loResp
Endfunc


*=============================================================================
* CONSULTAR / SINCRONIZAR ESTADOS
*   AlbertoSincronizarEstados() -> ChalonaResponse
*
*   Alberto da al motor la lista de pendientes en curChalonaEncfEnProceso.
*   Motor consulta DGII y REESCRIBE el cursor con el estado actualizado.
*=============================================================================
Function AlbertoSincronizarEstados
  If !_ChalonaLoaderInit()
    Return _ChalonaLoaderFail("alberto.loader.no_disponible")
  Endif

  * Lock por archivo (Alberto no usa sp_getapplock).
  If File(ALB_LOCK_PATH)
    Return ChalonaResponseNew(.F., "alberto.sync.lock_tomado", "", "")
  Endif
  Local lnH
  lnH = Fcreate(ALB_LOCK_PATH)
  If lnH < 0
    Return ChalonaResponseNew(.F., "alberto.sync.lock_falla", "", "")
  Endif
  Fclose(lnH)

  Local loResp
  loResp = ChalonaResponseNew(.T., "alberto.sync.ok", "", "")

  Try
    * 1. Crear cursores vacios.
    goChalonaEcf.CrearCursores()

    * 2. Llenar curChalonaEncfEnProceso con docs Alberto en estado "en proceso".
    _AlbLlenarPendientes()

    * 3. Motor poll DGII por cada pendiente y reescribe el mismo cursor.
    loResp = goChalonaEcf.SincronizarDesdeCursor()

    If _ChalonaLoaderEsVersionDesact(loResp)
      If _ChalonaLoaderDescargar()
        goChalonaEcf.CrearCursores()
        _AlbLlenarPendientes()
        loResp = goChalonaEcf.SincronizarDesdeCursor()
      Endif
    Endif

    * 4. Leer cursor reescrito y persistir estados en sync_ecf de Alberto.
    If loResp.ok
      _AlbPersistirEstadosSync()
    Endif
  Catch
    loResp = ChalonaResponseNew(.F., "alberto.sync.exception", "", "")
  Endtry

  If File(ALB_LOCK_PATH)
    Erase (ALB_LOCK_PATH)
  Endif

  Return loResp
Endfunc


*=============================================================================
* HELPERS DE LLENADO
*=============================================================================

* Inserta 1 fila en curChalMae con el shape que el motor exige.
Function _AlbLlenarMaestro
  Lparameters tnTipo, tnNumero, tcCtrl
  Do Case
  Case tnTipo = 32
    Return _AlbMaeVentas(tnNumero, "32", 4, tcCtrl)
  Case Inlist(tnTipo, 31, 33)
    Return _AlbMaeCxc(tnNumero, Transform(tnTipo), 3, tcCtrl)
  Case tnTipo = 34
    Return _AlbMaeNcr(tnNumero, tcCtrl)
  Case tnTipo = 41
    Return _AlbMaeCompras(tnNumero, tcCtrl)
  Case tnTipo = 43
    Return _AlbMaeReggasto(tnNumero, tcCtrl)
  Endcase
  Return .F.
Endfunc

* Tipo 32: ventas transa=4. RNC/nombre inline.
Function _AlbMaeVentas
  Lparameters tnNumero, tcTipo, tnTransa, tcCtrl
  If !Used("ventas")
    Use ventas Again Shared In 0
  Endif
  Select ventas
  Locate For factura = tnNumero And transa = tnTransa And empresa = mEmpresa
  If !Found()
    Return .F.
  Endif
  Insert Into curChalMae ;
    (fiscal, encf, control, fecha, valor, descuento, itbis, total, ;
     tasa, moneda, rnc, nombre, entidad, ocontrol, fechavencencf, dgii_codmod) ;
    Values ( ;
      tcTipo, ;
      Alltrim(Nvl(ventas.ncf, "")), tcCtrl, ventas.fecha, ;
      _AlbNum("ventas","valor"), _AlbNum("ventas","descuento"), ;
      _AlbNum("ventas","itbis"), _AlbNum("ventas","total"), ;
      _AlbTasa("ventas"), _AlbMoneda("ventas"), ;
      _AlbStr("ventas","rnc"), _AlbStr("ventas","nombre"), ;
      Alltrim(Transform(ventas.codigo)), "", ;
      _AlbFecha("ventas","ncfvence"), 3 )
  Return .T.
Endfunc

* Tipo 31/33: cxc. RNC viene de cliente (lookup).
Function _AlbMaeCxc
  Lparameters tnNumero, tcTipo, tnTransa, tcCtrl
  Local lcCodCli, lcRnc, lcNom
  If !Used("cxc")
    Use cxc Again Shared In 0
  Endif
  Select cxc
  Locate For factura = tnNumero And transa = tnTransa And empresa = mEmpresa
  If !Found()
    Return .F.
  Endif
  lcCodCli = Alltrim(Transform(cxc.codigo))
  lcRnc = ""
  lcNom = ""
  If !Used("cliente")
    Use cliente Again Shared In 0
  Endif
  Select cliente
  Locate For codigo = cxc.codigo And empresa = mEmpresa
  If Found()
    lcRnc = _AlbStr("cliente","rnc")
    lcNom = _AlbStr("cliente","cliente")
  Endif
  Select cxc
  Insert Into curChalMae ;
    (fiscal, encf, control, fecha, valor, descuento, itbis, total, ;
     tasa, moneda, rnc, nombre, entidad, ocontrol, fechavencencf, dgii_codmod) ;
    Values ( ;
      tcTipo, ;
      Alltrim(Nvl(cxc.ncf, "")), tcCtrl, cxc.fecha, ;
      _AlbNum("cxc","valor"), _AlbNum("cxc","descuento"), ;
      _AlbNum("cxc","itbis"), _AlbNum("cxc","total"), ;
      _AlbTasa("cxc"), _AlbMoneda("cxc"), ;
      lcRnc, lcNom, lcCodCli, "", ;
      _AlbFecha("cxc","ncfvence"), 3 )
  Return .T.
Endfunc

* Tipo 34: ncr transa=107.
Function _AlbMaeNcr
  Lparameters tnNumero, tcCtrl
  Local lcCodCli, lcRnc, lcNom, lcOctl, lnCodMod
  If !Used("ncr")
    Use ncr Again Shared In 0
  Endif
  Select ncr
  Locate For factura = tnNumero And transa = 107 And empresa = mEmpresa
  If !Found()
    Return .F.
  Endif
  lcCodCli = Alltrim(Transform(ncr.codigo))
  lnCodMod = 0
  If Type("ncr.pago") != "U"
    lnCodMod = Int(Nvl(ncr.pago, 0))
  Endif
  If lnCodMod < 1 Or lnCodMod > 5
    lnCodMod = 3
  Endif
  * ocontrol no vacio dispara que motor llame a referencia (curChalRef).
  lcOctl = "ALB:" + _AlbStr("ncr","ncfa")
  lcRnc = ""
  lcNom = ""
  If !Used("cliente")
    Use cliente Again Shared In 0
  Endif
  Select cliente
  Locate For codigo = ncr.codigo And empresa = mEmpresa
  If Found()
    lcRnc = _AlbStr("cliente","rnc")
    lcNom = _AlbStr("cliente","cliente")
  Endif
  Select ncr
  Insert Into curChalMae ;
    (fiscal, encf, control, fecha, valor, descuento, itbis, total, ;
     tasa, moneda, rnc, nombre, entidad, ocontrol, fechavencencf, dgii_codmod) ;
    Values ( ;
      "34", ;
      Alltrim(Nvl(ncr.ncf, "")), tcCtrl, ncr.fecha, ;
      _AlbNum("ncr","monto"), 0, ;
      _AlbNum("ncr","itbis"), _AlbNum("ncr","total"), ;
      _AlbTasa("ncr"), _AlbMoneda("ncr"), ;
      lcRnc, lcNom, lcCodCli, lcOctl, ;
      _AlbFecha("ncr","vence"), lnCodMod )
  Return .T.
Endfunc

* Tipo 41: compras transa=2. Lookup suplidor.
Function _AlbMaeCompras
  Lparameters tnNumero, tcCtrl
  Local lcCodSup, lcRnc, lcNom
  If !Used("compras")
    Use compras Again Shared In 0
  Endif
  Select compras
  Locate For factura = tnNumero And transa = 2 And empresa = mEmpresa
  If !Found()
    Return .F.
  Endif
  lcCodSup = Alltrim(Transform(compras.codigo))
  lcRnc = ""
  lcNom = ""
  If !Used("suplidor")
    Use suplidor Again Shared In 0
  Endif
  Select suplidor
  Locate For codigo = compras.codigo And empresa = mEmpresa
  If Found()
    lcRnc = _AlbStr("suplidor","rnc")
    lcNom = _AlbStr("suplidor","suplidor")
  Endif
  Select compras
  Insert Into curChalMae ;
    (fiscal, ncf, control, fecha, valor, descuento, itbis, total, ;
     tasa, moneda, rnc, nombre, entidad, ocontrol, fechavencencf, dgii_codmod, ;
     numero, itbisr, isr) ;
    Values ( ;
      "41", ;
      Alltrim(Nvl(compras.ncf, "")), tcCtrl, _AlbFecha("compras","fecha2"), ;
      _AlbNum("compras","valor"), _AlbNum("compras","descuento"), ;
      _AlbNum("compras","itbis"), _AlbNum("compras","total"), ;
      _AlbTasa("compras"), _AlbMoneda("compras"), ;
      lcRnc, lcNom, lcCodSup, "", ;
      _AlbFecha("compras","ncfvence"), 3, ;
      Alltrim(Transform(compras.factura)), ;
      _AlbNum("compras","ritbis"), _AlbNum("compras","risr") )
  Return .T.
Endfunc

* Tipo 43: reggasto. Sin lookup tercero.
Function _AlbMaeReggasto
  Lparameters tnNumero, tcCtrl
  Local lcCom
  If !Used("reggasto")
    Use reggasto Again Shared In 0
  Endif
  Select reggasto
  Locate For numero = tnNumero And empresa = mEmpresa
  If !Found()
    Return .F.
  Endif
  lcCom = _AlbStr("reggasto","comentario")
  Insert Into curChalMae ;
    (fiscal, ncf, control, fecha, valor, descuento, itbis, total, ;
     tasa, moneda, rnc, nombre, entidad, ocontrol, fechavencencf, dgii_codmod, ;
     comentario, referencia, doc, numero) ;
    Values ( ;
      "43", ;
      Alltrim(Nvl(reggasto.ncf, "")), tcCtrl, reggasto.fecha, ;
      _AlbNum("reggasto","importe"), 0, 0, _AlbNum("reggasto","importe"), ;
      _AlbTasa("reggasto"), _AlbMoneda("reggasto"), ;
      "", "", "", "", ;
      _AlbFecha("reggasto","ncfvence"), 3, ;
      lcCom, _AlbStr("reggasto","referencia"), _AlbStr("reggasto","doc"), ;
      Alltrim(Transform(reggasto.numero)) )
  Return .T.
Endfunc


* Detalle: 32/31/33 -> imtrd-equivalente. 34 -> sintetico (con ITBIS / exento).
* 41/43 -> motor sintetiza, dejar curChalDet vacio.
Function _AlbLlenarDetalle
  Lparameters tnTipo, tnNumero
  Do Case
  Case tnTipo = 32
    _AlbDetalleVentas(tnNumero, 4)
  Case Inlist(tnTipo, 31, 33)
    _AlbDetalleVentas(tnNumero, 3)
  Case tnTipo = 34
    _AlbDetalleNc(tnNumero)
  Endcase
Endfunc

Function _AlbDetalleVentas
  Lparameters tnNumero, tnTransa
  Local lcDescr
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
      lcDescr = _AlbStr("producto","nombre")
    Endif
    Select detalle
    Insert Into curChalDet ;
      (precio, cantidad, descrip, mercs_nombre, mercs_servicio, ;
       itbis_retenido, isr_retenido) ;
      Values ( ;
        _AlbNum("detalle","precio"), _AlbNum("detalle","cantidad"), ;
        lcDescr, lcDescr, 0, 0, 0 )
  Endscan
Endfunc

Function _AlbDetalleNc
  Lparameters tnNumero
  Local lnMonto, lnItbis, lnM18, lnM00, lcConcepto
  If !Used("ncr")
    Use ncr Again Shared In 0
  Endif
  Select ncr
  Locate For factura = tnNumero And transa = 107 And empresa = mEmpresa
  If !Found()
    Return
  Endif
  lnMonto = _AlbNum("ncr","monto")
  lnItbis = _AlbNum("ncr","itbis")
  lcConcepto = _AlbStr("ncr","concepto1")
  lnM18 = 0
  If lnItbis > 0
    lnM18 = Round(lnItbis / 0.18, 2)
  Endif
  lnM00 = lnMonto - lnM18
  If lnM18 > 0
    Insert Into curChalDet ;
      (precio, cantidad, descrip, mercs_nombre, mercs_servicio, ;
       itbis_retenido, isr_retenido) ;
      Values ( ;
        lnM18, 1, Alltrim(lcConcepto) + "  CON 18% ITBIS", ;
        Alltrim(lcConcepto) + "  CON 18% ITBIS", 0, 0, 0 )
  Endif
  If lnM00 > 0
    Insert Into curChalDet ;
      (precio, cantidad, descrip, mercs_nombre, mercs_servicio, ;
       itbis_retenido, isr_retenido) ;
      Values ( ;
        lnM00, 1, Alltrim(lcConcepto) + "  EXENTO", ;
        Alltrim(lcConcepto) + "  EXENTO", 0, 0, 0 )
  Endif
Endfunc


Function _AlbLlenarEmpresa
  If !Used("empresa")
    Use empresa Again Shared In 0
  Endif
  Select empresa
  Locate For codigo = mEmpresa
  If !Found()
    Return
  Endif
  Insert Into curChalEmp (rnc, nombre, direccion, iprecio) ;
    Values (_AlbStr("empresa","rnc"), _AlbStr("empresa","nombre"), ;
            _AlbStr("empresa","direccion"), _AlbNum("empresa","iprecio"))
Endfunc


Function _AlbLlenarTercero
  Lparameters tnTipo
  Local lcCod, lcTabla, lcCampoNombre
  Select curChalMae
  Go Top
  lcCod = Alltrim(curChalMae.entidad)
  If Empty(lcCod)
    Return
  Endif
  lcTabla = Iif(Inlist(tnTipo, 41, 43), "suplidor", "cliente")
  lcCampoNombre = lcTabla
  If !Used(lcTabla)
    Use (lcTabla) Again Shared In 0
  Endif
  Select (lcTabla)
  Locate For Alltrim(Transform(codigo)) == lcCod And empresa = mEmpresa
  If !Found()
    Return
  Endif
  * Alberto no tiene columna 'extranjero' en sus DBF: extranjero_flag = 0.
  * Si el RNC no es identificador fiscal RD valido, motor lo trata como extranjero.
  Insert Into curChalCli (extranjero_flag, rnc, nombre) ;
    Values (0, _AlbStr(lcTabla,"rnc"), _AlbStr(lcTabla, lcCampoNombre))
Endfunc


* Solo NC tipo 34: capturar ncfa+vence2 desde tabla ncr.
Function _AlbLlenarReferencia
  Local lnFact, lcRefEncf, ldRefFec
  Select curChalMae
  Go Top
  If Alltrim(curChalMae.fiscal) != "34"
    Return
  Endif
  lnFact = Val(Substr(Alltrim(curChalMae.control), At("|", curChalMae.control) + 1))
  If !Used("ncr")
    Use ncr Again Shared In 0
  Endif
  Select ncr
  Locate For factura = lnFact And transa = 107 And empresa = mEmpresa
  If !Found()
    Return
  Endif
  lcRefEncf = _AlbStr("ncr","ncfa")
  ldRefFec  = _AlbFecha("ncr","vence2")
  If Empty(lcRefEncf)
    Return
  Endif
  Insert Into curChalRef (encf, fecha) Values (lcRefEncf, ldRefFec)
Endfunc


* Pendientes: docs Alberto con encf emitido pero estado aun "en proceso".
* Cliente decide la fuente; aqui ejemplo desde sync_ecf.
Function _AlbLlenarPendientes
  Local lnTipo
  If !Used("sync_ecf")
    Use sync_ecf Again Shared In 0
  Endif
  Select sync_ecf
  Scan For Lower(Alltrim(estado)) == "en proceso" And empresa = mEmpresa
    lnTipo = Val(Left(Alltrim(sync_ecf.control), 2))
    Insert Into curChalonaEncfEnProceso (control, encf, es_gastos) ;
      Values (Alltrim(sync_ecf.control), Alltrim(sync_ecf.encf), ;
              Inlist(lnTipo, 41, 43))
  Endscan
Endfunc


*=============================================================================
* PERSISTENCIA RESPUESTA
*=============================================================================

* Lee curChalMae (motor reescribio encf + estado + codigo_seguridad + ...).
* Persiste en sync_ecf de Alberto. Adaptar a la tabla destino del ERP.
Function _AlbPersistirRespuesta
  Lparameters tnTipo, tnNumero
  Select curChalMae
  Go Top
  If !Used("sync_ecf")
    Use sync_ecf Again Shared In 0
  Endif
  Select sync_ecf
  Locate For Alltrim(control) == Alltrim(curChalMae.control) And empresa = mEmpresa
  If Found()
    Replace ;
      encf With Alltrim(curChalMae.encf), ;
      estado With Alltrim(curChalMae.estado), ;
      codigo_seguridad With Alltrim(curChalMae.codigo_seguridad), ;
      fecha_firma With Alltrim(curChalMae.fecha_firma), ;
      timbre With Alltrim(curChalMae.timbre)
  Else
    Insert Into sync_ecf ;
      (empresa, control, encf, estado, codigo_seguridad, fecha_firma, timbre) ;
      Values (mEmpresa, Alltrim(curChalMae.control), Alltrim(curChalMae.encf), ;
              Alltrim(curChalMae.estado), Alltrim(curChalMae.codigo_seguridad), ;
              Alltrim(curChalMae.fecha_firma), Alltrim(curChalMae.timbre))
  Endif
Endfunc


* Recorre curChalonaEncfEnProceso (motor reescribio estado actualizado).
Function _AlbPersistirEstadosSync
  Local lcCtrl, lcEstado, lcCod
  If !Used("sync_ecf")
    Use sync_ecf Again Shared In 0
  Endif
  Select curChalonaEncfEnProceso
  Scan
    lcCtrl   = Alltrim(curChalonaEncfEnProceso.control)
    lcEstado = Alltrim(curChalonaEncfEnProceso.estado)
    lcCod    = Alltrim(curChalonaEncfEnProceso.codigo_seguridad)
    Select sync_ecf
    Locate For Alltrim(control) == lcCtrl And empresa = mEmpresa
    If Found()
      Replace estado With lcEstado, codigo_seguridad With lcCod
    Endif
    Select curChalonaEncfEnProceso
  Endscan
Endfunc


*=============================================================================
* HELPERS DE CAMPO (defensivos: campo puede no existir)
*=============================================================================
Function _AlbNum
  Lparameters tcAlias, tcField
  Local lcRef
  lcRef = tcAlias + "." + tcField
  Return Iif(Type(lcRef) = "U", 0, _ChalonaEcfNzNum(Evaluate(lcRef)))
Endfunc

Function _AlbStr
  Lparameters tcAlias, tcField
  Local lcRef
  lcRef = tcAlias + "." + tcField
  Return Iif(Type(lcRef) = "U", "", Alltrim(Transform(Nvl(Evaluate(lcRef), ""))))
Endfunc

Function _AlbFecha
  Lparameters tcAlias, tcField
  Local lcRef
  lcRef = tcAlias + "." + tcField
  Return Iif(Type(lcRef) = "D", Evaluate(lcRef), {/})
Endfunc

Function _AlbTasa
  Lparameters tcAlias
  Local lnT
  lnT = _AlbNum(tcAlias, "tasa")
  Return Iif(lnT < 1, 1, lnT)
Endfunc

Function _AlbMoneda
  Lparameters tcAlias
  Local lcM
  lcM = _AlbStr(tcAlias, "moneda")
  Return Iif(Empty(lcM), "DOP", lcM)
Endfunc
