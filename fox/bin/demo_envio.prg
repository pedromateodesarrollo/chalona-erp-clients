*------------------------------------------------------------
* demo_envio.prg - demostracion standalone del cliente Fox ECF
* usando la CAPA DE CURSORES (CrearCursores + EnviarDesdeCursores).
*
* Envia 10 comprobantes (tipos 31-32-33-34-41-43-44-45-46-47) al portal
* testecf via el loader chalona-ecf-loader.prg. No requiere SQL Server:
* este programa llena los cursores publicos (curChalMae / curChalDet /
* curChalEmp / curChalCli / curChalRef / curChalSup) en memoria y le
* pide al motor que los envie a DGII.
*
* Equivalente conceptual al demo_envio.dart y demo_envio.py: 10 tipos,
* eNCF generado por servidor, tipo 32 captura encf y se usa como
* NCFModificado en 33/34.
*
* Uso (Windows con VFP9):
*   cd ecf\clients\fox\bin
*   "C:\Program Files (x86)\Microsoft Visual FoxPro 9\vfp9.exe" -t -clauncher.fpw
*   type demo_envio.log
*
* Emisor: Vicortiz Softwares srl (RNC 131086268).
* Portal: testecf (pruebas DGII - no afecta datos reales).
*------------------------------------------------------------

Set Talk Off
Set Safety Off
Set Exclusive Off
Set Date British          && fechas dd/mm/yyyy en VFP -> motor las exporta dd-mm-yyyy

* ----- Log --------------------------------------------------
Public pcDemoLog
pcDemoLog = Addbs(Justpath(Sys(16, 0))) + "demo_envio.log"
Strtofile("", pcDemoLog)
DemoLog("=== demo_envio (Fox - capa cursores) ===")

* ----- Bootstrap loader + config ---------------------------
* Loader vive un directorio arriba (ecf/clients/fox/chalona-ecf-loader.prg).
Local lcLoaderDir, lcLoaderPath
lcLoaderDir = Addbs(Fullpath(Addbs(Justpath(Sys(16, 0))) + ".."))
lcLoaderPath = lcLoaderDir + "chalona-ecf-loader.prg"
If !File(lcLoaderPath)
  DemoLog("ERROR: no se encontro " + lcLoaderPath)
  Return
Endif
Set Procedure To (lcLoaderPath) Additive

* Suprimir popups (corremos sin UI).
Public glChalonaEcfSilenciarUi
glChalonaEcfSilenciarUi = .T.

Local loCfg
loCfg = Createobject("Empty")
AddProperty(loCfg, "servidor_ecf",     "https://ecf-service.vicortiz.com/")
AddProperty(loCfg, "usuario_sync",     "test@r131086268.com")
AddProperty(loCfg, "pass_sync",        "1234")
AddProperty(loCfg, "portal_dgii",      "testecf")
AddProperty(loCfg, "dgii_multimoneda", "F")

DemoLog("  servidor : " + loCfg.servidor_ecf)
DemoLog("  usuario  : " + loCfg.usuario_sync)
DemoLog("  portal   : " + loCfg.portal_dgii)
DemoLog("  modo     : cursores (CrearCursores + EnviarDesdeCursores)")
DemoLog("")

DemoLog("-- chalonaSetConfig...")
If !chalonaSetConfig(loCfg)
  DemoLog("ERROR: chalonaSetConfig devolvio .F. (descarga del motor fallo)")
  Return
Endif
DemoLog("   OK - motor cargado, version: " + Transform(chalonaVersionCliente()))
DemoLog("")

* ----- Datos comunes a los 10 envios -----------------------
Local lcEmiRnc, lcEmiNombre, lcEmiDir
Local lcCliRncLocal, lcCliNomLocal
Local lcCliRncExt, lcCliNomExt
Local ldHoy
lcEmiRnc      = "131086268"
lcEmiNombre   = "Vicortiz Softwares srl"
lcEmiDir      = "Santo Domingo, Republica Dominicana"
lcCliRncLocal = "101009025"
lcCliNomLocal = "Cliente Demo SRL"
lcCliRncExt   = "01800451302"
lcCliNomExt   = "Comprador Extranjero Demo"
ldHoy         = Date()

* ----- Loop por los 10 tipos -------------------------------
Local lcTipos, i, lcTipo, lcCtrl, lcEncfTipo32, loResp
Local lnOk, lnFail
Local Array laResumen[10]
lcTipos = "31,32,33,34,41,43,44,45,46,47"
lnOk = 0
lnFail = 0
lcEncfTipo32 = ""

For i = 1 To 10
  lcTipo = GetNthItem(lcTipos, i, ",")
  lcCtrl = "DEMO-" + lcTipo + "-" + Sys(2015)

  DemoLog("[" + Transform(i) + "/10] Tipo " + lcTipo + "  control=" + lcCtrl)

  * 1. Recrear cursores vacios.
  goChalonaEcf.CrearCursores()

  * 2. Poblar segun el tipo.
  PoblarCursores(lcTipo, lcCtrl, lcEmiRnc, lcEmiNombre, lcEmiDir, ;
                 lcCliRncLocal, lcCliNomLocal, lcCliRncExt, lcCliNomExt, ;
                 ldHoy, lcEncfTipo32)

  * 3. Enviar.
  loResp = goChalonaEcf.EnviarDesdeCursores(lcCtrl)

  If Vartype(loResp) # "O" Or !loResp.ok
    Local lcMsg
    lcMsg = "api.fallo"
    If Vartype(loResp) = "O" And Pemstatus(loResp, "message", 5)
      lcMsg = Nvl(loResp.message, lcMsg)
    Endif
    DemoLog("  FAIL - " + lcMsg)
    laResumen[i] = "FAIL Tipo " + lcTipo + "  " + lcMsg
    lnFail = lnFail + 1
    Loop
  Endif

  * 4. Leer writeback en curChalMae (motor reescribio la fila).
  Local lcEncf, lcEstado
  lcEncf = ""
  lcEstado = ""
  If Used("curChalMae")
    Select curChalMae
    Locate
    If !Eof()
      lcEncf = Alltrim(Nvl(curChalMae.encf, ""))
      lcEstado = Alltrim(Nvl(curChalMae.estado, ""))
    Endif
  Endif
  If Empty(lcEstado)
    lcEstado = "ok"
  Endif

  DemoLog("  OK  - estado: " + lcEstado + "  eNCF: " + lcEncf)
  laResumen[i] = "OK   Tipo " + lcTipo + "  " + lcEncf + "  estado=" + lcEstado
  lnOk = lnOk + 1

  * Tipo 32 aceptado -> usar su eNCF como NCFModificado en 33/34.
  If lcTipo = "32" And !Empty(lcEncf)
    lcEncfTipo32 = lcEncf
  Endif
Endfor

DemoLog("")
DemoLog("=========================================")
DemoLog("  RESUMEN: " + Transform(lnOk) + " ok / " + Transform(lnFail) + " fail (de 10)")
DemoLog("=========================================")
For i = 1 To 10
  DemoLog("  " + laResumen[i])
Endfor
DemoLog("")
Return


*============================================================
* Funciones auxiliares
*============================================================

Function DemoLog
  Lparameters tcLine
  Strtofile(Nvl(tcLine, "") + Chr(13) + Chr(10), pcDemoLog, 1)
  ? Nvl(tcLine, "")
Endfunc

Function GetNthItem
  Lparameters tcList, tnIdx, tcSep
  Local lcRest, lnPos, lnCount, lcItem
  lcRest = tcList
  lnCount = 0
  Do While .T.
    lnCount = lnCount + 1
    lnPos = At(tcSep, lcRest)
    If lnPos = 0
      If lnCount = tnIdx
        Return lcRest
      Endif
      Return ""
    Endif
    lcItem = Left(lcRest, lnPos - 1)
    If lnCount = tnIdx
      Return lcItem
    Endif
    lcRest = Substr(lcRest, lnPos + Len(tcSep))
  Enddo
Endfunc


* Llena curChalMae / curChalDet / curChalEmp / curChalCli / curChalRef /
* curChalSup segun el tipo de e-CF.
*
* Convenciones:
*   - Una linea fija de "Caja de Dona" (260000 + 18% itbis = 306800)
*     para ventas (31/32/45/46). Tipo 44/47 ajusta montos.
*   - Gastos (41/43) sin detalle: motor sintetiza linea desde comentario.
*   - Tipo 34 (NC) requiere referencia a encf de 32 aceptado en este lote.
Function PoblarCursores
  Lparameters tcTipo, tcCtrl, tcEmiRnc, tcEmiNombre, tcEmiDir, ;
              tcCliRncLocal, tcCliNomLocal, tcCliRncExt, tcCliNomExt, ;
              tdHoy, tcEncfRefTipo32

  * --- curChalEmp (siempre) ---
  Insert Into curChalEmp ;
    (rnc, nombre, direccion, iprecio) ;
    Values (tcEmiRnc, tcEmiNombre, tcEmiDir, 0)

  * --- curChalCli y curChalMae varian por tipo ---
  Local lnValor, lnItbis, lnTotal, lnTasaItbis
  lnValor = 260000.00
  lnTasaItbis = 18.00
  lnItbis = Round(lnValor * lnTasaItbis / 100, 2)
  lnTotal = lnValor + lnItbis

  Local lcRncCli, lcNomCli, lnExtFlag, llSinComprador
  lcRncCli = tcCliRncLocal
  lcNomCli = tcCliNomLocal
  lnExtFlag = 0
  llSinComprador = .F.

  Do Case
  Case tcTipo = "44" Or tcTipo = "46" Or tcTipo = "47"
    lcRncCli = tcCliRncExt
    lcNomCli = tcCliNomExt
    lnExtFlag = 1
  Case tcTipo = "43"
    llSinComprador = .T.        && Gastos Menores: sin comprador
  Endcase

  If !llSinComprador
    Insert Into curChalCli ;
      (extranjero_flag, rnc, nombre) ;
      Values (lnExtFlag, lcRncCli, lcNomCli)
  Endif

  * --- curChalMae ---
  Local lcEncf, lcNcf, lcOcontrol, lnDgiiCodmod, lcReferencia, lcDoc, lcNumero
  Local lnItbisR, lnIsr, lnDiasCr, lcComentario, ldFechaVenc
  lcEncf = ""
  lcNcf = ""
  lcOcontrol = ""
  lnDgiiCodmod = 0
  lcReferencia = ""
  lcDoc = ""
  lcNumero = "0"
  lnItbisR = 0
  lnIsr = 0
  lnDiasCr = 0
  lcComentario = ""
  ldFechaVenc = Date(Year(tdHoy) + 1, 12, 31)   && 31/12/(anio+1)

  Do Case
  Case tcTipo = "41" Or tcTipo = "43"
    * Gastos: usar ncf (no encf). Detalle sintetico via comentario.
    lcNcf = ""               && el motor lo arma con secuencia DGII
    lcComentario = "Gasto demo tipo " + tcTipo + " - linea sintetica"
    lnItbisR = lnItbis        && retencion ITBIS (Norma 07-18) para tipo 41
    If tcTipo = "43"
      lnValor = 700.00
      lnTasaItbis = 0
      lnItbis = 0
      lnItbisR = 0
      lnTotal = 700.00
    Endif
  Case tcTipo = "34"
    * Nota credito: hace falta ocontrol + dgii_codmod + curChalRef.
    lcOcontrol = "REF-" + Nvl(tcEncfRefTipo32, "")
    lnDgiiCodmod = 1          && Anulacion total (codigo 1)
    lnValor = 1000.00
    lnTasaItbis = 0
    lnItbis = 0
    lnTotal = 1000.00
  Case tcTipo = "33"
    * Nota debito.
    lcOcontrol = "REF-" + Nvl(tcEncfRefTipo32, "")
    lnDgiiCodmod = 3
    lnValor = 1000.00
    lnTasaItbis = 0
    lnItbis = 0
    lnTotal = 1000.00
  Case tcTipo = "47"
    * Pagos al exterior: total exento, ISR retenido.
    lnValor = 180000.00
    lnTasaItbis = 0
    lnItbis = 0
    lnTotal = 180000.00
    lnIsr = 48600.00
  Case tcTipo = "46"
    * Exportacion: monto grande sin ITBIS.
    lnValor = 1800000.00
    lnTasaItbis = 0
    lnItbis = 0
    lnTotal = 1800000.00
  Endcase

  Insert Into curChalMae ;
    (fiscal, encf, ncf, control, fecha, valor, descuento, itbis, total, ;
     tasa, moneda, rnc, nombre, entidad, ocontrol, fechavencencf, ;
     dgii_codmod, itbisr, isr, diascr, comentario, ;
     referencia, doc, numero) ;
    Values ;
    (tcTipo, lcEncf, lcNcf, tcCtrl, tdHoy, lnValor, 0, lnItbis, lnTotal, ;
     1, "DOP", Iif(llSinComprador, "", lcRncCli), Iif(llSinComprador, "", lcNomCli), ;
     "", lcOcontrol, ldFechaVenc, ;
     lnDgiiCodmod, lnItbisR, lnIsr, lnDiasCr, lcComentario, ;
     lcReferencia, lcDoc, lcNumero)

  * --- curChalDet (omitir gastos 41/43) ---
  If tcTipo # "41" And tcTipo # "43"
    Insert Into curChalDet ;
      (precio, cantidad, descrip, mercs_nombre, mercs_servicio, ;
       itbis, itbis_tasa, itbis_retenido, isr_retenido) ;
      Values ;
      (lnValor, 1.0000, "Caja de Dona (demo)", "Caja de Dona", 1, ;
       lnItbis, lnTasaItbis, 0, Iif(tcTipo = "47", 48600.00, 0))
  Endif

  * --- curChalRef (33 con ref opcional, 34 obligatoria) ---
  If (tcTipo = "33" Or tcTipo = "34") And !Empty(Nvl(tcEncfRefTipo32, ""))
    Insert Into curChalRef ;
      (encf, fecha) ;
      Values (tcEncfRefTipo32, tdHoy)
  Endif

  * --- curChalSup (gastos sin RNC en cabecera; aqui no aplica) ---
  * Nada: rnc va en curChalMae para 41/43.

Endfunc
