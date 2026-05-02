*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfe_BaseData as cNcfe_BussinessClass
     
    * Settins 
      oDataPath  = SYS(5)+CURDIR()+"data\"
      oDataSrc   = 1
      oIsOpenDbf = ""
      oFound     = .f. 
      
    * Data Seccion
      oTblName   = ""
      oTblIndex  = ""
      oTblFilter = ""
      oLstField  = ""
      oLstType   = ""
      oLstHeader = ""
    
    *---------------------------------------------------
     PROCEDURE pSearchByField
       * Iniciar Variables 
         LPARAMETERS lstTblName as String, lcFldName as String, lcFldType as Integer, lSearch, curData as String 
         LOCAL lbReturn as Boolean, strQuery as String 
         lbReturn = .f. 
         strQuery = ""
         this.oFound = .f. 
         
       * 
         IF this.pIsCharacter(lstTblName) AND !EMPTY(lstTblName) THEN 
            IF this.pIsCharacter(lcFldName) AND !EMPTY(lcFldName) THEN 
               IF this.pIsCharacter(curData) AND !EMPTY(curData) THEN 
                  IF this.pIsNumeric(lcFldType) AND lcFldType > 0 THEN 
                   * Generar filtro
                     DO CASE 
                        CASE lcFldType = 1 															&& Entero
                             IF this.pIsNumeric(lSearch) AND lSearch > 0 then
                                strQuery = " select * from "+lstTblName+" Where "+lcFldName+" = "+TRANSFORM(lSearch)
                             ELSE
                                MESSAGEBOX("Parametro Erroneo: de Busqueda",16,"Error en Parametro")
                             ENDIF 
                        CASE lcFldType = 3															&& Cadena de Caracteres
                             IF this.pIsCharacter(lSearch) AND !EMPTY(lSearch) then
                                strQuery = " select * from "+lstTblName+" Where " + this.pGetFilterDetail(lcFldName,lSearch)
                             ELSE
                                MESSAGEBOX("Parametro Erroneo: de Busqueda",16,"Error en Parametro")
                             ENDIF 
                        CASE lcFldType = 7															&& Cadena Corta
                             IF this.pIsCharacter(lSearch) AND !EMPTY(lSearch) then
                                strQuery = " select * from "+lstTblName+" Where ALLTRIM(UPPER("+lcFldName+")) == ALLTRIM(UPPER('"+TRANSFORM(lSearch)+"'))"
                             ELSE
                                MESSAGEBOX("Parametro Erroneo: de Busqueda",16,"Error en Parametro")
                             ENDIF 
                     OTHERWISE 
*                        CASE lcFldType = 2															&& Fecha
*                        CASE lcFldType = 4															&& Moneda
*                        CASE lcFldType = 5															&& Logico
                        MESSAGEBOX("Parametro Erroneo: Tipo de Campo",16,"Error en Parametro")
                     ENDCASE 
                     
                   * Finalizar 
                     IF !EMPTY(ALLTRIM(strQuery)) THEN 
                         strQuery = strQuery + " Order By "+lcFldName 
                         IF this.pSqlExec(lstTblName,strQuery,curData) AND this.pTabla_Tiene_registros(curData) then
                            IF lcFldType = 3 THEN 			&& Descripcion
                               this.oFound = this.pSelectItem_FrmConsulta(curData)
                            ELSE
                               this.oFound = .t.
                            ENDIF 
                            lbReturn = .t. 
                         ENDIF 
                     ENDIF 
                  ELSE
                     MESSAGEBOX("Parametro Erroneo: Tipo de Campo",16,"Error en Parametro")
                  ENDIF 
               ELSE
                  MESSAGEBOX("Parametro Erroneo: Cursor Destino",16,"Error en Parametro")
               ENDIF 
            ELSE
               MESSAGEBOX("Parametro Erroneo: Campo de Busqueda",16,"Error en Parametro")
            ENDIF 
         ELSE
            MESSAGEBOX("Parametro Erroneo: Nombre de la Tabla",16,"Error en Parametro")
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pSelectItem_FrmConsulta
       * Iniciar las Variables 
         LPARAMETERS curData as String 
         PUBLIC oFrmConsulta
         opcion = 0 
         
       * Settings 
         oFrmConsulta = CREATEOBJECT("cFrmConsulta")
         oFrmConsulta.oTblName   = curData 
         oFrmConsulta.oLstField  = this.oLstField
         oFrmConsulta.oLstType   = this.oLstType
         oFrmConsulta.oLstHeader = this.oLstHeader
         oFrmConsulta.pSetGrid()
       
       * Mostrar Info 
         oFrmConsulta.show(1)
       
       * Finalizar 
         oFrmConsulta = null 
         RELEASE oFrmConsulta
         RETURN (opcion = 1)
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pSqlExec
       * Iniciar Variables 
         LPARAMETERS lstTblName as String, StrQuery as String, curData as String 
         LOCAL lbReturn as Boolean, lbReadOnly as Boolean  
         lbReturn   = .t. 
         
       * Procesar 
         IF this.pIsCharacter(lstTblName) AND !EMPTY(lstTblName) THEN 
            IF this.pIsCharacter(StrQuery) AND !EMPTY(StrQuery) THEN 
               lbReadOnly = (this.pIsCharacter(curData) And !EMPTY(ALLTRIM(curData)))
               DO CASE 
                  CASE this.oDataSrc = 1 														&& DBFs
                       IF this.pOpenLstDbf(lstTblName,lbReadOnly) then
                        * Variables 
                          IF lbReadOnly then
                             StrQuery = StrQuery + " Into Cursor "+curData
                          ENDIF 
                    
                        * Procesar 
                          TRY
                             &StrQuery
                             lbReturn = .t.   
                          CATCH
                             AERROR(laError)
                          ENDTRY 
                    
                        * Finalizar 
                          this.pCloseLstDbf(lstTblName)
                          IF !lbReturn then
                              this.pShowError(400,"Error","Imposible Cargar los Datos"+CHR(13)+"Detalle: "+laError(2) , .t. )
                          ENDIF 
                       ENDIF 
               OTHERWISE 
                  this.pShowError(404,"Parametro Erroneo","Origen de Datos ("+this.oDataSrc +") no ha sido Configurado"+CHR(13)+"Nota: Avisar al Encardado de Tecnología" , .t. )
               ENDCASE 
            ELSE
               this.pShowError(400,"Parametro Erroneo","QUERY Erroneo o Vacio"+CHR(13)+"Program: "+PROGRAM() , .t. )
            ENDIF 
         ELSE 
            this.pShowError(400,"Parametro Erroneo","Nombre de la Tabla Erroneo o Vacio"+CHR(13)+"Program: "+PROGRAM() , .t. )
         ENDIF 
       
       * Finalizar 
         RETURN lbReturn 
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pOpenLstDbf
       * Iniciar Variables 
         LPARAMETERS lstTblName as String, lbReadOnly as Boolean 
         LOCAL lbReturn as Boolean, lcTblName as String, i as Integer  
         lbReturn = .f. 
         this.oIsOpenDbf = ""
         
       * Procesar 
         IF this.pIsCharacter(lstTblName) AND !EMPTY(ALLTRIM(lstTblName)) THEN 
            lstTblName = ALLTRIM(lstTblName)
            FOR i = 1 TO GETWORDCOUNT(lstTblName,",")
                lcTblName = ALLTRIM(GETWORDNUM(lstTblName,i,","))
                IF !EMPTY(lcTblName) THEN 
                    this.pClosedbf(lcTblName)
                    lbReturn = this.pOpenDbf(lcTblName, lbReadOnly)
                    IF lbReturn = .f. then
                       EXIT 
                    ENDIF 
                ENDIF 
            ENDFOR 
         ELSE
            this.pShowError(400,"Parametro Erroneo","Nombre de la Tabla Erroneo o Vacio"+CHR(13)+"Program: "+PROGRAM() , .t. )
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 
     
    *---------------------------------------------------
     PROCEDURE pOpenDbf
       LPARAMETERS lcTblName as String, lbReadOnly as Boolean 
       LOCAL lbReturn as Boolean, lcFile as String  
       lbReturn = .f. 
       IF this.pTblExists(lcTblName,".Dbf") then
          = this.pCloseDbf(lcTblName)
          lcFile = this.oDataPath+ALLTRIM(lcTblName)+".Dbf"
          TRY 
              IF lbReadOnly then
                 USE (lcFile) IN 0 SHARED NOUPDATE
              ELSE
                 USE (lcFile) IN 0 SHARED 
              ENDIF 
              SELECT (lcTblName)
              lbReturn = .t. 
          CATCH
              AERROR(laError)
          ENDTRY 
          IF !lbReturn THEN 
              this.pShowError(404,"Aviso","Imposible Utilizar la Tabla ("+lcTblName +")." +laError(2), .t.)
          ENDIF 
       ELSE
          this.pShowError(400,"Bad Parameter","Nombre de la Tabla Erroneo", .t.)
       ENDIF 
       RETURN lbReturn 
     ENDPROC 
     
    *---------------------------------------------------
     PROCEDURE pTblExists
       LPARAMETERS lcTblName as String, lcExtension as String 
       LOCAL lbReturn as Boolean, lcFile as String  
       lbReturn = .f. 
       IF this.pIsCharacter(lcTblName) AND !EMPTY(lcTblName) THEN 
          IF this.pIsCharacter(lcExtension) AND !EMPTY(lcExtension) THEN 
             lcFile = this.oDataPath+ALLTRIM(lcTblName)+ALLTRIM(lcExtension)
             IF FILE(lcFile) THEN 
                lbReturn = .t. 
             ELSE 
                this.pShowError(404,"Archivo no Existe: "+lcFile,"No tiene acceso a La Tabla: "+lcFile , lbShowError)
             ENDIF 
          ELSE 
             this.pShowError(400,"Parametro Invalido","Extensión de Archivo Erroneo o Vacio"+CHR(13)+"Program: "+PROGRAM(), .t.)
          ENDIF 
       ELSE 
          this.pShowError(400,"Parametro Invalido","Nombre de Archivo Erroneo o Vacio"+CHR(13)+"Program: "+PROGRAM(), .t.)
       ENDIF 
       RETURN lbReturn 
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pCloseLstDbf
       * Iniciar Variables 
         LPARAMETERS lstTblName as String, lbReadOnly as Boolean 
         LOCAL lbReturn as Boolean, lcTblName as String, i as Integer  
         lbReturn = .f. 
         this.oIsOpenDbf = ""
         
       * Procesar 
         IF this.pIsCharacter(lstTblName) AND !EMPTY(ALLTRIM(lstTblName)) THEN 
            lstTblName = ALLTRIM(lstTblName)
            FOR i = 1 TO GETWORDCOUNT(lstTblName,",")
                lcTblName = ALLTRIM(GETWORDNUM(lstTblName,i,","))
                IF !EMPTY(lcTblName) THEN 
                    this.pClosedbf(lcTblName)
                ENDIF 
            ENDFOR 
         ELSE
            this.pShowError(400,"Parametro Erroneo","Nombre de la Tabla Erroneo o Vacio"+CHR(13)+"Program: "+PROGRAM() , .t. )
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pCloseDbf
       LPARAMETERS lcTblName as String, lbShowError as Boolean 
       LOCAL lbReturn as Boolean 
       lbReturn = .t. 
       IF this.pSelect(lcTblName) THEN 
          TRY
             USE 
          CATCH
             AERROR(laError)
             lbReturn = .f. 
          ENDTRY 
          IF !lbReturn THEN 
              this.pShowError(404,"Aviso","Imposible Cerrar la Tabla ("+lcTblName +")." +laError(2), lbShowError)
          ENDIF 
       ENDIF 
       RETURN lbReturn 
     ENDPROC 
     
    *---------------------------------------------------
     PROCEDURE pSelect
       LPARAMETERS lcTblName as String, lbShowError as Boolean 
       LOCAL lbReturn as Boolean 
       lbReturn = .f. 
       IF this.pIsCharacter(lcTblName) THEN 
          IF USED(lcTblName) then
             SELECT (lcTblName)
             lbReturn = .t. 
          ELSE 
             this.pShowError(404,"Advise","La Tabla ("+lcTblName +") no esta en uso", lbShowError)
          ENDIF 
       ELSE
          this.pShowError(400,"Bad Parameter","Nombre de la Tabla Erroneo", lbShowError)
       ENDIF 
       RETURN lbReturn 
     ENDPROC 
     
    *---------------------------------------------------
     PROCEDURE pTabla_Tiene_Registros
       LPARAMETERS lcTblName as String, lbShowError as Boolean 
       LOCAL lbReturn as Boolean 
       lbReturn = .f. 
       IF this.pSelect(lcTblName) THEN 
          GO TOP 
          IF EOF() THEN 
             this.pShowError(404,"Aviso","La Tabla ("+lcTblName +") no tiene registros", lbShowError)
          ELSE
             lbReturn = .t. 
          ENDIF 
       ENDIF 
       RETURN lbReturn 
     ENDPROC 
     
   *------------------------------------------------
    PROCEDURE pGetCursorName
      LOCAL curName as String 
      curName = SYS(2015)
      DO WHILE this.pSelect(curName,.f.)
         curName = SYS(2015)
      ENDDO 
      RETURN curName
    ENDPROC 
     

 ENDDEFINE 



*--------------------------------------------------------------------------------------------------------------------------
*--------------------------------------------------------------------------------------------------------------------------
*--------------------------------------------------------------------------------------------------------------------------


*---------------------------------------------------------------------------------
 DEFINE CLASS ncf_credito as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"
 ENDDEFINE 

 
*--------------------------------------------------------------------------------------------------------------------------
*--------------------------------------------------------------------------------------------------------------------------
*--------------------------------------------------------------------------------------------------------------------------
 
*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfe_BussinessClass as cNcfe_ErrorHanddler
 

    *---------------------------------------------------
     FUNCTION pGetFecha
         LOCAL ldFecha as date, lcURL as String , loHTTP,;
              lcResponse as string, lcFechaFinal 

         * URL de una API pública que devuelve la hora con zona horaria
         lcURL = "http://worldtimeapi.org/api/timezone/America/Santo_Domingo"
         ldFecha = DATE()

         TRY
         
             loHTTP = CREATEOBJECT("MSXML2.XMLHTTP")
             loHTTP.Open("GET", lcURL, .F.)
             loHTTP.Send()

             IF loHTTP.Status = 200
                 lcResponse = loHTTP.ResponseText
                 lcFechaFinal = this.ParseJSONDateRD(lcResponse)
                 IF VARTYPE(lcFechaFinal) = "T" THEN 
                    ldFecha = DATE(lcFechaFinal)
                 ENDIF 
             ENDIF
         CATCH
            WAIT WINDOW "la Conexion a Internet no es Posible " NOWAIT 
         ENDTRY
         lbReturn = ldFecha
     ENDFUNC

    *---------------------------------------------------
     FUNCTION ParseJSONDateRD(tcJSON)
       * Iniciar Variables 
         LOCAL lcFechaISO, lcFechaFinal

       * Extraer el valor del campo "datetime"
         lcFechaISO = STREXTRACT(tcJSON, '"datetime":"', '"')
         IF EMPTY(lcFechaISO)
            RETURN .NULL.
         ENDIF

       * Convertir a tipo DateTime (solo los primeros 19 caracteres: YYYY-MM-DDTHH:MM:SS)
         lcFechaFinal = CTOT(STRTRAN(LEFT(lcFechaISO, 19), "T", " "))
         RETURN lcFechaFinal
     ENDFUNC

    *---------------------------------------------------
     PROCEDURE pIsBoolean
       LPARAMETERS lBooleanValue
       RETURN (VARTYPE(lBooleanValue) = "L")
     ENDPROC 
     
    *---------------------------------------------------
     PROCEDURE pIsNumeric
       LPARAMETERS lNumericValue
       RETURN (VARTYPE(lNumericValue) = "N" OR VARTYPE(lNumericValue) = "I" OR VARTYPE(lNumericValue) = "Y")
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pIsCharacter 
       LPARAMETERS lStringValue
       RETURN (VARTYPE(lStringValue) = "C")
     ENDPROC 
     
    *---------------------------------------------------
     PROCEDURE pIsDate
       LPARAMETERS lDateValue
       RETURN (VARTYPE(lDateValue) = "D")
     ENDPROC 
     
    *---------------------------------------------------
     PROCEDURE pIsDateTime
       LPARAMETERS lDateTimeValue
       RETURN (VARTYPE(lDateTimeValue) = "T")
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pIsTrue
       LPARAMETERS lTrueValue 
       LOCAL lbReturn as Boolean 
       lbReturn = .f. 
       DO CASE 
          CASE this.pIsNumeric(lTrueValue)
               lbReturn = IIF(lTrueValue=1,.t.,.f.)
          CASE this.pIsBoolean(lTrueValue)
               lbReturn = lTrueValue
       ENDCASE 
       RETURN lbReturn 
     ENDPROC 
     
    *---------------------------------------------------
     PROCEDURE pIsNumericString
       LPARAMETERS lNumericString 
       LOCAL lbReturn as Boolean
       lbReturn = .f. 
       IF this.pIsCharacter(lNumericString) AND !EMPTY(lNumericString) AND VAL(lNumericString) > 0 then
          IF ALLTRIM(lNumericString) == ALLTRIM(this.pSoloNumeros(lNumericString)) THEN 
             lbReturn = .t. 
          ENDIF 
       ENDIF 
       RETURN lbReturn
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pIsValidRnc
       LPARAMETERS lNumericString 
       LOCAL lbReturn as Boolean
       lbReturn = .f. 
       IF this.pIsCharacter(lNumericString) AND !EMPTY(lNumericString) AND ALLTRIM(lNumericString) == ALLTRIM(this.pSoloNumeros(lNumericString)) then
          DO case
             CASE LEN(lNumericString) = 9
                  lbReturn = .t. 
             CASE LEN(lNumericString) = 11
                  lbReturn = .t. 
          ENDCASE 
       ENDIF 
       RETURN lbReturn
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pSoloNumeros
       LPARAMETERS lNumericString 
       LOCAL lbReturn as Boolean, lcString as String, lcChar as String  
       lbReturn = .f. 
       lcString = ""
       IF this.pIsCharacter(lNumericString) AND !EMPTY(lNumericString) then
          lNumericString = ALLTRIM(lNumericString)
          FOR i = 1 TO LEN(lNumericString)
              lcChar = SUBSTR(lNumericString,i,1)
              IF lcChar $ "0123456789" then
                 lcString = lcString + lcChar
              ENDIF 
          ENDFOR 
       ENDIF 
       RETURN lcString
     ENDPROC 
     
    *---------------------------------------------------
     PROCEDURE pFormatTelefono
       LPARAMETERS lTelString 
       LOCAL lcString as String, lcChar as String, i as Integer  
       lcString = ""
       IF this.pIsCharacter(lTelString) AND !EMPTY(this.pSoloNumeros(lTelString)) then
          lTelString = ALLTRIM(this.pSoloNumeros(lTelString))
          IF LEN(lTelString) >= 10 then
             FOR i = 1 TO 10
                 lcString = lcString + icase(i=4,"-", i=7,"-","")+ALLTRIM(SUBSTR(lTelString,i,1))
             ENDFOR 
          ENDIF 

*!*	          IF LEN(lTelString) >= 10 then
*!*	             FOR i = 1 TO LEN(lTelString)
*!*	                 lcString = lcString + icase(i=1,"(", i=4,") ", i=7,"-","")+ALLTRIM(SUBSTR(lTelString,i,1))
*!*	             ENDFOR 
*!*	          ENDIF 
       ENDIF 
       RETURN lcString 
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pGetFilterDetail
        LPARAMETERS lcFldName as String, strSearch as String 
        LOCAL lcString as String, i as Integer  
        lcString = ""
        IF this.pIsCharacter(lcFldName) AND !EMPTY(lcFldName) AND this.pIsCharacter(strSearch) AND !EMPTY(strSearch) then
           FOR i = 1 TO GETWORDCOUNT(strSearch," ")
               lcWord = lcFldName+" Like '%"+ALLTRIM(GETWORDNUM(strSearch,i," "))+"%' "
               IF EMPTY(lcString) then
                  lcString = "( "+lcWord 
               ELSE
                  lcString = lcString + " And "+lcWord 
               ENDIF 
           ENDFOR 
           lcString = lcString + " )"
        ENDIF 
        RETURN lcString 
     ENDPROC 
    
    *--------------------------------------------
     PROCEDURE pFormatDocumento
       * Iniciar Variables 
         LPARAMETERS liCuadre as Integer, liDocumento as Integer 
         LOCAL lcDocument as String 
         lcDocument = ""
         
       * Cuadre 
         IF this.pIsNumeric(liCuadre) AND liCuadre > 0 then
            lcDocument = TRANSFORM(liCuadre)+"-"
         ENDIF 
         
       * Documento 
         IF this.pIsNumeric(liDocumento) AND liDocumento > 0 then
            IF liDocumento <= 9999999 then
               lcDocument = ALLTRIM(lcDocument) + TRANSFORM(liDocumento,"@l 9999999")
            ELSE 
               lcDocument = ALLTRIM(lcDocument) + TRANSFORM(liDocumento)
            ENDIF 
         ENDIF 
       
       * Finalizar
         RETURN ALLTRIM(lcDocument)
     ENDPROC 
 
    *---------------------------------------------
     PROCEDURE pFormatEmail
       * Iniciar Variables 
         LPARAMETERS lcTexto
         LOCAL lnPosAt as integer, lnInicio as integer, lnFin  as integer, lcCorreo as String 
         lcTexto = " " + LOWER(ALLTRIM(lcTexto))
         
       * Procesar 
         lnPosAt = AT("@", lcTexto)   								&& Buscar 1er @
	     IF lnPosAt > 1
	        lnInicio = lnPosAt - 1									&& * Buscar el inicio del correo (antes del @)
	        DO WHILE lnInicio > 1 AND ;
	            (ISALPHA(SUBSTR(lcTexto, lnInicio, 1)) OR ;
	             SUBSTR(lcTexto, lnInicio, 1) $ "._%+-0123456789")
	            lnInicio = lnInicio - 1
	        ENDDO
	        lnInicio = lnInicio + 1

	        * Buscar el final del correo (después del @)
	        lnFin = lnPosAt + 1
	        DO WHILE lnFin <= LEN(lcTexto) AND ;
	            (ISALPHA(SUBSTR(lcTexto, lnFin, 1)) OR ;
	             SUBSTR(lcTexto, lnFin, 1) $ ".-0123456789")
	            lnFin = lnFin + 1
	        ENDDO

	        lcCorreo = SUBSTR(lcTexto, lnInicio, lnFin - lnInicio)
	     ELSE
	        lcCorreo = ""
	     ENDIF
	    
	  * Finalizar 
	    RETURN ALLTRIM(lcCorreo)
	 ENDPROC 
    
 
 ENDDEFINE 

 

*--------------------------------------------------------------------------------------------------------------------------
*--------------------------------------------------------------------------------------------------------------------------
*--------------------------------------------------------------------------------------------------------------------------

*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfe_ErrorHanddler as Custom 

   * Manejo de Error 
     oSuccess    = .f.
     oIdError    = 0
     oMsgError   = ""
     oMsgDetail  = ""

    *---------------------------------------------------
     PROCEDURE pShowError
       LPARAMETERS liError as Integer, lcMsgError as String, lcDetail as String, lbShowError as Boolean 
       WITH this 
           .oIdError  = liError 
           .oMsgError = ALLTRIM(lcMsgError)
           .oMsgDetail = ALLTRIM(lcDetail)
            IF this.pIsTrue(lbShowError) then
               MESSAGEBOX(.oMsgDetail,16,.oMsgError)
            ENDIF 
       ENDWITH 
     ENDPROC

 ENDDEFINE 


*--------------------------------------------------------------------------------------------------------------------------
*--------------------------------------------------------------------------------------------------------------------------
*--------------------------------------------------------------------------------------------------------------------------

*---------------------------------------------------------------------------------
 DEFINE CLASS cFrmConsulta as Form 
 
    * Settings
      Autocenter  = .t. 
      backcolor   = RGB(44,60,76)
      borderstyle = 1 
      caption     = "CONSULTA:"
      height      = 520
      maxbutton   = .f. 
      minbutton   = .f. 
      showtips    = .f. 
      showwindow  = 1
      width       = 720
    
    * Data Seccion
      oTblName   = ""
      oTblIndex  = ""
      oTblFilter = ""
      oLstField  = ""
      oLstType   = ""
      oLstHeader = ""

    * Grid 
      ADD OBJECT grdData as grid WITH ;
          height             = 430 ,;
          left               = 16 ,;
          top                = 20 ,;
          width              = 684 ,;  
          fontsize           = 8 ,;
          FONTname           = "Arial" ,;
          headerheight       = 30 ,;
          rowheight          = 20 ,;
          gridlinecolor      = RGB(192,192,192) ,;
          scrollbars         = 2 ,;
          themes             = .f. ,;
          allowcellselection = .f. ,;
          allowheadersizing  = .f. ,;
          allowrowsizing     = .f. ,;
          deletemark         = .f.
          
      ADD OBJECT bntOk as commandbutton WITH ;
          caption  = "    \<Ok" ,;
          fontbold = .t. ,;
          fontsize = 11 ,;
          height   = 37 ,;
          left     = 12 ,;
          pictureposition = 1 ,;
          picture  = "bmp\yesok.gif" ,;
          top    = 470 ,;
          width  = 120 
          
      ADD OBJECT bntCancel as commandbutton WITH ;
          cancel   = .t. ,;
          caption  = "  \<Cancel" ,;
          fontbold = .t. ,;
          fontsize = 11 ,;
          height   = 37 ,;
          left     = 144,;
          pictureposition = 1 ,;
          picture  = "bmp\wzundo.bmp" ,;
          top    = 470 ,;
          width  = 120 
     
    *---------------------------------------------------
     PROCEDURE pSetGrid 
       * Iniciar Variables
         LOCAL lbReturn as Boolean, liFields as Integer  
         lbReturn = .f. 
         
       * Procesar   
         WITH this.grdData 
             .recordsourcetype   = 1
             .RecordSource       = ALLTRIM(this.oTblName)
             .columncount        = GETWORDCOUNT(this.oLstField,",")
              FOR liIdColumn = 1 TO .columncount
                  WITH .columns(liIdColumn)
                       .ControlSource   = ALLTRIM(GETWORDNUM(this.oLstField,liIdColumn,","))
                        WITH .Header1
                             .Caption   = ALLTRIM(GETWORDNUM(this.oLstHeader,liIdColumn,","))
                             .fontbold  = .t.
                             .fontsize  = 09
		                     .alignment = ICASE(val(GETWORDNUM(this.oLstType,liIdColumn,",")) = 3,0,2)
		                ENDWITH 
                  ENDWITH 
                  thisform.pFormatColumn(.columns(liIdColumn), val(GETWORDNUM(this.oLstType,liIdColumn,",")))
              ENDFOR 
             .SetAll("DynamicBackColor","IIF(INT(RECNO()/2)=RECNO()/2,RGB(244,244,244),RGB(255,255,255))","Column")
         ENDWITH 
         
       * Finalizar 
         RETURN lbReturn 
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE pFormatColumn
       * Iniciar las Variables 
         LPARAMETERS loColumn as Integer, liFldType as Integer
         
       * Procesar 
         WITH loColumn
              DO CASE
                CASE liFldType = 1					&& ID
                    .alignment = 2
                    .width     = 71
                    .format    = "lz"
                    .inputmask = "999999"
                CASE liFldType = 2					&& Fecha
                    .alignment = 2
                    .width     = 80
                    .format    = "@e"
                CASE liFldType = 3					&& Texto Largo
                    .Header1.caption   = " "+ALLTRIM(.Header1.caption)
                    .alignment = 0
                    .width     = 340
                    .format    = "!"
                CASE liFldType = 4					&& Moneda
                    .alignment = 1
                    .width     = 120
                    .format    = "z"
                    .inputmask = "999,999,999.99"
                CASE liFldType = 5					&& Activo
                    .AddObject("chk1","cFrmConsulta_CheckBox")
                    .CurrentControl = "chk1"
                    .width          = 30
                    .sparse         = .f.
                CASE liFldType = 6					&& Tipo
                    .alignment = 2
                    .width     = 30
                    .format    = "lz"
                    .inputmask = "99"
                CASE liFldType = 7					&& Texto Largo
                    .alignment = 0
                    .width     = 100
                    .format    = "!"
             ENDCASE
         ENDWITH 

       * Finalizar 
         RETURN 
     ENDPROC 


    *---------------------------------------------------
     PROCEDURE grdData.dblClick 
       thisform.bntOk.click 
     ENDPROC 
    
    *---------------------------------------------------
     PROCEDURE grdData.KeyPress 
       LPARAMETERS nKeyCode, nShiftAltCtrl
       IF nKeyCode = 13 then
          thisform.bntOk.click 
       ELSE 
          DODEFAULT()
       ENDIF 
     ENDPROC 

    *---------------------------------------------------
     PROCEDURE bntOk.click 
        opcion = 1
        thisform.Release()
     ENDPROC 
     
    *---------------------------------------------------
     PROCEDURE bntCancel.click 
        opcion = 0
        thisform.Release()
     ENDPROC 

 ENDDEFINE 
 
 
*---------------------------------------------------------------------------------
 DEFINE CLASS cFrmConsulta_CheckBox as CheckBox 
   
   caption   = ""
   alignment = 2 
   autosize  = .t.
   backstyle = 0
   height    = 17
   width     = 18
   specialeffect = 1

 ENDDEFINE 


 

