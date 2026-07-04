*==========================================================================
* EnviarEventoDespacho(tcControl, tcTipo) -> objeto {ok, status, body, error}
*
* Notifica un evento al ERP (POST /erp/eventos) firmando el body con
* HMAC-SHA256 (header x-ov-signature). Solo recibe control + tipo; el
* resto de campos no son obligatorios.
*
* La firma se calcula sobre los BYTES EXACTOS del body que se envia.
* HMAC via PowerShell (presente en todo Windows). No depende de openssl.
*==========================================================================

#DEFINE ECF_EVENTOS_URL     "http://192.168.1.3:3005/erp/eventos"
#DEFINE ECF_EVENTOS_SECRETO "PON_AQUI_EL_SECRETO"

Function EnviarEventoDespacho
  Lparameters tcControl, tcTipo
  Local lcControl, lcTipo, lcBody, lcSig, loOut, lcResp, lnStatus

  lcControl = Iif(Vartype(tcControl) = "C", Alltrim(tcControl), "")
  lcTipo    = Iif(Vartype(tcTipo)    = "C", Alltrim(tcTipo),    "DESPACHO")

  loOut = Createobject("Empty")
  AddProperty(loOut, "ok",     .F.)
  AddProperty(loOut, "status", 0)
  AddProperty(loOut, "body",   "")
  AddProperty(loOut, "error",  "")

  If Empty(lcControl)
    loOut.error = "control requerido"
    Return loOut
  Endif

  * Body firmado == body enviado (mismos bytes). Orden de campos irrelevante
  * mientras coincidan firma y envio.
  lcBody = '{"tipo":"' + _EvtJsonEsc(lcTipo) + ;
           '","control":"' + _EvtJsonEsc(lcControl) + '"}'

  lcSig = _EvtHmacSha256(lcBody, ECF_EVENTOS_SECRETO)
  If Empty(lcSig)
    loOut.error = "no se pudo calcular la firma HMAC (PowerShell)"
    Return loOut
  Endif

  Local loHttp, loEx, llFallo
  loHttp = Createobject("MSXML2.XMLHTTP")
  loHttp.open("POST", ECF_EVENTOS_URL, .F.)
  loHttp.setRequestHeader("Content-Type", "application/json")
  loHttp.setRequestHeader("x-ov-signature", lcSig)

  llFallo = .F.
  Try
    loHttp.send(lcBody)
  Catch To loEx
    loOut.error = "fallo conexion: " + loEx.Message
    llFallo = .T.
  Endtry
  If llFallo
    loHttp = .Null.
    Return loOut
  Endif

  lnStatus = 0
  If Vartype(loHttp.status) = "N"
    lnStatus = loHttp.status
  Endif
  lcResp = ""
  If Vartype(loHttp.responseText) = "C"
    lcResp = loHttp.responseText
  Endif
  loHttp = .Null.

  loOut.status = lnStatus
  loOut.body   = lcResp
  loOut.ok     = (lnStatus >= 200 And lnStatus < 300)
  Return loOut
Endfunc

*--------------------------------------------------------------------------
* HMAC-SHA256(body, secreto) -> hex minusculas. Vacio si falla.
* Escribe secreto y body a temporales, firma con PowerShell, lee el hex.
*--------------------------------------------------------------------------
Function _EvtHmacSha256
  Lparameters tcBody, tcSecreto
  Local lcDir, lcStamp, lcSec, lcMsg, lcOut, lcCmd, lcSig, loWsh

  lcDir   = Addbs(Sys(2023))
  lcStamp = Sys(2015)
  lcSec   = lcDir + "ovsec_"  + lcStamp + ".tmp"
  lcMsg   = lcDir + "ovbody_" + lcStamp + ".tmp"
  lcOut   = lcDir + "ovsig_"  + lcStamp + ".tmp"

  * STRTOFILE escribe los bytes crudos (sin BOM, sin salto extra).
  Strtofile(Nvl(tcSecreto, ""), lcSec)
  Strtofile(Nvl(tcBody, ""),    lcMsg)

  lcCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "' + ;
    '$k=[Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText(' + Chr(39) + lcSec + Chr(39) + '));' + ;
    '$b=[IO.File]::ReadAllBytes('   + Chr(39) + lcMsg + Chr(39) + ');' + ;
    '$h=New-Object System.Security.Cryptography.HMACSHA256;$h.Key=$k;' + ;
    '$s=([BitConverter]::ToString($h.ComputeHash($b)) -replace ' + Chr(39) + '-' + Chr(39) + ',' + Chr(39) + Chr(39) + ').ToLower();' + ;
    '[IO.File]::WriteAllText(' + Chr(39) + lcOut + Chr(39) + ',$s)"'

  lcSig = ""
  Try
    loWsh = Createobject("WScript.Shell")
    loWsh.Run(lcCmd, 0, .T.)   && 0=oculto, .T.=esperar
    If File(lcOut)
      lcSig = Filetostr(lcOut)
      lcSig = Chrtran(lcSig, Chr(13) + Chr(10) + Chr(9) + " ", "")
    Endif
  Catch
    lcSig = ""
  Endtry

  Erase (lcSec)
  Erase (lcMsg)
  Erase (lcOut)
  Return lcSig
Endfunc

*--------------------------------------------------------------------------
* Escape JSON minimo (comillas y backslash). Suficiente para control/tipo.
*--------------------------------------------------------------------------
Function _EvtJsonEsc
  Lparameters tcStr
  Local lcStr
  lcStr = Nvl(tcStr, "")
  lcStr = Strtran(lcStr, "\", "\\")
  lcStr = Strtran(lcStr, '"', '\"')
  Return lcStr
Endfunc
