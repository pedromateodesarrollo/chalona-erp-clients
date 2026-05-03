*- instancio el objeto
*- genero los cursores
*- lleno los cursores
*- envio los datos
LOCAL ecf
ecf = jf_ecf()
ecf.sync_ecf()

*---------------------------------------------------
 DEFINE CLASS Ecf as Custom 

	http       = .f.
	credencial = '{}'
	resultado  = ''
	portal     = ''
	
  * Variables 
	oMsync     = '""'

   *---------------------------------------
	PROCEDURE init(urlServer,credentials)
		SET PROCEDURE TO http, json ADDITIVE 
		LOCAL x
		x               = json_decode(credentials)
		this.portal     = x.portal
		this.http       = createobject('http',urlServer)
		this.credencial = credentials
	ENDPROC 
	
   *---------------------------------------
	PROCEDURE login
	
		IF this.http.islogged THEN 
		   RETURN .t.
		ENDIF 
		
		IF !this.http.login(this.credencial)
			this.resultado='No se pudo loguear con el servidor'
			MESSAGEBOX('El servidor no esta aceptando las credenciales')
			RETURN .f.
		ENDIF 
		
	ENDPROC 

   *---------------------------------------
	PROCEDURE sync_ecf()
	  * Inicar variables
	    LOCAL lbReturn as Boolean, loRespose ,msync ,oElemento
	    lbReturn = .f. 
	    lcAlias  = ALLTRIM(ALIAS())
	    my_FechaEcf_Rexiter = DATE()
		
      * Procesar 
        IF this.login() AND this.OpenDbf_Ecf_sync() THEN 	
           msync = this.oMsync									&& 
           msync = this.pGetLastDateTime()
*           msync = '"2025-05-01"'
		   loRespose = this.http.post('/cg/ecf/ecfGetUpdates',TEXTMERGE('{"sync":<<msync>>}'))
		   lbReturn = loRespose.Ok
		   IF loRespose.Ok THEN 
		    * Abrir la Tabla: NCFe Enviados
		      this.pCloseDbf("sync_ecf")
              USE sync_ecf IN 0 SHARED 
              IF this.pSelect("sync_ecf") THEN 
                 SET ORDER TO ID   && ID
              ELSE
                 this.pCloseDbf("sync_ecf")
                 MESSAGEBOX("Imposible Abrir la Tabla de NCFe Enviados",16,"Error")
                 RETURN .f. 
              ENDIF 

		    * Actualizar los NCFe
		      FOR EACH oElemento IN loRespose.response
		      	  oElemento.addproperty('timbre',vacio(oElemento.timbre,''))
		          lbReturn = this.pUpdate_sync_ecf(oElemento)
		          IF !lbReturn THEN 
		              EXIT 
		          ENDIF 
		      ENDFOR 
		   ELSE 
		      MESSAGEBOX("Error En Conexion al Servidor de NCFe")
		   ENDIF 
		ENDIF 
		
      * Finalizar 
        this.pCloseDbf("sync_ecf")
        this.pSelect(lcAlias)
		RETURN lbReturn
	ENDPROC 

  *---------------------------------------
	PROCEDURE pGetLastDateTime
	  * Iniciar Variables 
	    LOCAL lbReturn as Boolean, lcDatetime as String, ldCurrentFecha as Date, curData as String  
	    lbReturn       = .f. 
	    ldCurrentFecha = DATE()
	    curData        = SYS(2015)
	    lcDatetime     = '"'+ALLTRIM(TRANSFORM(YEAR(ldCurrentFecha),"@l 9999"))+"-"+;
	                         ALLTRIM(TRANSFORM(MONTH(ldCurrentFecha),"@l 99"))+"-"+;
	                         ALLTRIM(TRANSFORM(day(ldCurrentFecha),"@l 99"))+'"'
	                 
      * Cargar Datos
        = pCloseDbf("sync_ecf")
        TRY 
           USE data\sync_ecf SHARED NOUPDATE IN 0 
           select top 1 * from sync_ecf WHERE idEstado = 4 order by momento INTO CURSOR &curData
           IF pTabla_tiene_Registros(curData) THEN 
              lbReturn = .t. 
           ELSE 
               select top 1 * from sync_ecf order by id DESC INTO CURSOR &curData
               lbReturn = .t. 
           ENDIF 
        CATCH
           AERROR(laError)
           MESSAGEBOX("Imposible Cargar los NCFe"+CHR(13)+"Detalle: "+laError(2))
           lbReturn = .f. 
        ENDTRY 
      
      * Procesar 
        IF lbReturn AND pTabla_tiene_Registros(curData) THEN 
           lcDatetime  = '"'+ALLTRIM(momento)+'"'
        ENDIF 

      * Finalizar 
        this.pCloseDbf(curData)
        this.pSelect("sync_ecf")
		RETURN lcDatetime
	ENDPROC 

   *---------------------------------------
	PROCEDURE pUpdate_sync_ecf()
	  * Iniciar Variables 
	    LPARAMETERS oElemento 
	    LOCAL lbReturn as Boolean
	    lbReturn = .f. 
	  
      * Procesar 
        IF this.pSelect("sync_ecf") then
           SEEK oElemento.id
           IF !FOUND() THEN 
               APPEND BLANK 
               replace id WITH oElemento.id
           ENDIF 
           
         * Coleccion de RNC no Enviado o Erroneo
           IF VARTYPE(oElemento.comprador) = "U" OR VARTYPE(oElemento.comprador) != "C" OR EMPTY(oElemento.comprador) then
              oElemento.comprador = "00000000001"
           ENDIF 
             
           
         * Actualizar Datos 
           TRY 
			  replace emisor     WITH oElemento.emisor ,;
			          comprador  WITH oElemento.comprador ,;
			          tipo       WITH oElemento.tipo ,;
			          numero     WITH oElemento.numero ,;
			          estado     WITH ALLTRIM(oElemento.estado) ,;
			          idestado   WITH this.pGetIdEstado(estado) ,;
			          momento    WITH oElemento.momento ,;
			          portal     WITH oElemento.portal ,;
			          sync       WITH oElemento.sync ,;
			          timbre     WITH oElemento.timbre
              lbReturn = .t. 
           CATCH
              AERROR(laError)
           ENDTRY     
           
           IF lbReturn THEN 
	         * Esenciales 
	           IF !EMPTY(ALLTRIM(timbre)) THEN 
	               gsCodigoSeguridad = this.getCodigoSeguridad(ALLTRIM(Timbre))
	               gsFechaFirma      = this.getFechaFirma(ALLTRIM(Timbre))
	           ENDIF 
	           

	         * Respuesta de la Api
			   IF VARTYPE(oElemento.respuesta) = "O" then
		          replace respuesta  WITH oElemento.respuesta.encode()
			   ENDIF 
		   ELSE 
             * Mensaje de Error 
               MESSAGEBOX("Imposible Actualizar la tabla de los NCFe"+CHR(13)+"Detalle: "+laError(2))
		   ENDIF  
        ELSE
           MESSAGEBOX("Imposible Seleccionar la tabla de los NCFe")
        ENDIF 
      
      * Finalizar
        RETURN lbReturn 
	ENDPROC 

   *---------------------------------------
	PROCEDURE pGetIdEstado(lcEstado)
	  * Iniciar Variables 
	    LOCAL liResult as Integer
	    liResult = 1
	  
	  * Procesar 
	    IF VARTYPE(lcEstado) = "C" AND !EMPTY(lcEstado) THEN 
		   DO case 
		      CASE ALLTRIM(UPPER(lcEstado)) == ALLTRIM(UPPER("Aceptado"))
		           liResult = 1
		      CASE ALLTRIM(UPPER(lcEstado)) == ALLTRIM(UPPER("Aceptado Condicional"))
		           liResult = 2
		      CASE ALLTRIM(UPPER(lcEstado)) == ALLTRIM(UPPER("Fallo Comunicacion"))
		           liResult = 3
		      CASE ALLTRIM(UPPER(lcEstado)) == ALLTRIM(UPPER("Pendiente"))
		           liResult = 4
		      CASE ALLTRIM(UPPER(lcEstado)) == ALLTRIM(UPPER("Rechazado"))
		           liResult = 5
		      CASE ALLTRIM(UPPER(lcEstado)) == ALLTRIM(UPPER("Sin�Estado"))
		           liResult = 6
		   OTHERWISE 
	               liResult = 9
	       ENDCASE 
	    ELSE
	       MESSAGEBOX("Aviso: Error en el Estado Devuelto "+CHR(13)+;
	                  "            Notifique al Departamento de TI",16,"Aviso Urgente")
	    ENDIF 
	  
	  * Finalizar 
	    RETURN liResult
	ENDPROC 
    

   *---------------------------------------
    PROCEDURE getCodigoSeguridad	
      * Iniciar Variables 
        LPARAMETERS lcTimbre as String 
        LOCAL lcResult as String, liPosition as Integer 
        lcResult = ""
        
      * Procesar 
        IF VARTYPE(lcTimbre) = "C" AND !EMPTY(lcTimbre) AND AT('CodigoSeguridad',lcTimbre) > 0 THEN 
           liPosition = AT('CodigoSeguridad',lcTimbre)	
           lcResult   = SUBSTR(lcTimbre,liPosition)	
           lcResult   = getwordnum(lcResult,2,'=')	
        ENDIF 
     
      * Finalizar 
        RETURN lcResult
    ENDPROC 
  
   *---------------------------------------
    PROCEDURE getFechaFirma(lcFirma)
      * Iniciar Variables 
        LOCAL lcResult as String, liPosition as Integer  
        lcResult = ""
        
      * Procesar 
        IF VARTYPE(lcFirma) = "C" AND !EMPTY(lcFirma) AND AT('fechafirma',lcFirma) > 0 THEN 
           liPosition = AT('fechafirma',lcFirma)
           lcResult   = SUBSTR(lcFirma,liPosition)
           lcResult   = GETWORDNUM(lcResult,2,'=' )
           lcResult   = GETWORDNUM(lcResult,1,'%')
        ENDIF 
        
      * Finalizar
        RETURN lcResult
    ENDPROC 
     
   *---------------------------------------
	PROCEDURE OpenDbf_Ecf_sync()
	  LOCAL lbReturn as Boolean, lcSync as String, msgError as String   
	  lbReturn = .f. 
	  lcSync   = '""'
	  msgError = ""
	  this.oMsync = '""'
	  
	  
	 * Procesar 
	   IF this.pOpenDbf("sync_ecf") THEN 
	      SELECT sync_ecf
	           * Crear Cursor 
	             TRY 
	                select MAX(sync) as resultSync from sync_ecf INTO CURSOR curSync_ecf
	                lbReturn = .t. 
	             CATCH
	                AERROR(laError)
	                msgError = laError(2)
	             ENDTRY 
	             
	           * Procesar 
	             IF lbReturn then
	                IF this.pTabla_tiene_registros("curSync_ecf") THEN 
                       this.oMsync = NVL(ALLTRIM(resultSync),lcSync)
	                ELSE
	                   msgError = "Detalle: El Cursor no fue Creado"
	                   lbReturn = .f. 
	                ENDIF 
	            ENDIF 
	     SELECT sync_ecf
	   ENDIF 
	   
	 * Cargar Ultima Fecha Sincronizacion
	   
	 * Mostrar Error 
	   IF !EMPTY(msgError) then
	       MESSAGEBOX("Imposible Crear el Cursor: Ecf_sync"+CHR(13)+"Detalle: "+msgError)
	   ENDIF 
	  
     * Finalizar 
       this.pCloseDbf("curSync_ecf")
       this.pSelect("sync_ecf")
	   RETURN lbReturn 
	ENDPROC 

	
	PROCEDURE aprobarFacturaSuplidor(nid)
		IF vacio(nid)
			RETURN .f.
		ENDIF 
		IF !this.login()
			RETURN .f. 
		ENDIF 
		LOCAL r
		r=this.http.post('/cg/ecf/ecfApproveOrRejectInvoice',TEXTMERGE('{"id":<<nid>>}'))
		IF !r.ok
			MESSAGEBOX(r.response)
		ENDIF 
		this.sync_ecf()
	ENDPROC 
	
	PROCEDURE rechazarFacturaSuplidor(nid,razon)
		IF vacio(nid)
			RETURN .f.
		ENDIF 
		IF vacio(razon)
			RETURN .f.
		ENDIF 
		IF !this.login()
			RETURN .f. 
		ENDIF 
		LOCAL r
		r=this.http.post('/cg/ecf/ecfApproveOrRejectInvoice',TEXTMERGE('{"id":<<nid>>,"razon":"<<razon>>"}'))
		IF !r.ok
			MESSAGEBOX(r.response)
		ENDIF 
		this.sync_ecf()
	ENDPROC
	
	PROCEDURE actualiza_estado(cestado,cmensaje)
		SELECT ecf_encabezado
		       replace respuesta_estado   WITH cestado
		       replace respuesta_mensajes WITH cmensaje
	ENDPROC


   *--------------------------------------------------------------------------------------------
	PROCEDURE sendEcf()
	  * Iniciar Variables 
	    LOCAL lbReturn as Boolean, r, args, json, setdate as String, cmensajes, x 
	    lbReturn = .f. 
		setdate  = 'set date to '+SET('date')
	  
	  * Procesar 
	    IF this.pValidarNcf_Ecf() THEN 
	       IF this.login() THEN 
		      json = this.getEcfJson()
		      args = TEXTMERGE('{"rnc":"<<ALLTRIM(ecf_encabezado.empresa_rnc)>>","portal":"<<ALLTRIM(ecf_encabezado.portal)>>","json":<<json>>}')
		      r    = this.http.post('/send-ecf',args)
		      IF VARTYPE(r.response)='O'	
			     SET DATE TO AMERICAN 
			     IF pSelect("ecf_encabezado") THEN 
		            replace respuesta_trackId 				WITH r.response.get('trackid','');
				            respuesta_codigo  				WITH TRANSFORM(r.response.get('codigo',''));
				            respuesta_codigo_seguridad		WITH TRANSFORM(r.response.get('codigoSeguridad','')) ;
				            respuesta_fecha_firma			WITH TRANSFORM(r.response.get('fechaFirma',''));
				            respuesta_timbre				WITH r.response.get('timbre','');
				            respuesta_estado  				WITH r.response.get('estado','');
				            respuesta_secuenciaUtilizada  	WITH r.response.get('secuenciaUtilizada',.f.);
				            respuesta_fechaRecepcion  		WITH CTOT(r.response.get('fechaRecepcion',''));
				            respuesta_mensajes  			WITH r.response.get('mensajes','')

			        this.sync_ecf()
	                lbReturn = .t. 
			     ELSE
			        MESSAGEBOX("Encabezado del Ncf no Esta en uso",16,'Fallo la generacion del eNCF')
			     ENDIF 
	          ELSE 
			     MESSAGEBOX(r.response,16,'Fallo la generacion del eNCF')
	          ENDIF 
	       ELSE
	          this.actualiza_estado('Fallo Comunicacion','No se puede acceder al servidor')
	       ENDIF 
	    ENDIF 

	  * Finalizar
       &setdate			
	    RETURN lbReturn 
	ENDPROC 

   *--------------------------------------------------------------------------------------------
	PROCEDURE pValidarNcf_Ecf()
	  * Iniciar Variables 
	    LOCAL lbReturn as Boolean, lstError as String  
	    lbReturn = .t. 
	    lstError = ""
	    
	  * Validar el NCF 
		IF vacio(ecf_encabezado.comprobante_tipo)
		   lstError = CHR(13)+'- Falta el NCF'
		   lbReturn = .f. 
		ELSE 
		   IF !inlist(ecf_encabezado.comprobante_tipo,'31','32','33','34','41','43','44','45','46','47') THEN 
		       lstError = lstError + CHR(13)+'- Tipo comprobante invalido'
		       lbReturn = .f. 
		   ENDIF 
		   
		   IF vacio(ecf_encabezado.comprobante_numero)
		      lstError = lstError + CHR(13)+'- Especifique el comprobante electronico'
		      lbReturn = .f. 
		   ENDIF
		   
		   IF ecf_encabezado.comprobante_tipo='43' AND ecf_encabezado.itbis1+ecf_encabezado.itbis2+ecf_encabezado.itbis3>0
		      lstError = lstError + CHR(13)+'- Los gastos menores no llevan itbis'
		      lbReturn = .f. 
		   ENDIF
		ENDIF 
      
      * Errores 
        IF !lbReturn THEN 
            this.actualiza_estado('Error Validacion','Listado de Errores: '+lstError)
            MESSAGEBOX('Listado de Errores: '+lstError,16,'Error Validacion')
        ENDIF 
	
	  * Finalizar
	    RETURN lbReturn 
	ENDPROC 

   
*!*	   *--------------------------------------------------------------------------------------------
*!*		PROCEDURE sendEcf()
*!*			IF !this.login()
*!*				this.actualiza_estado('Fallo Comunicacion','No se puede acceder al servidor')
*!*				RETURN .f.
*!*			ENDIF 

*!*			IF vacio(ecf_encabezado.comprobante_tipo)
*!*				this.actualiza_estado('Error Validacion','Especifique el tipo de comprobante electronico')
*!*				RETURN .f.
*!*			ENDIF 
*!*			
*!*			IF !inlist(ecf_encabezado.comprobante_tipo,'31','32','33','34','41','43','44','45','46','47')
*!*				this.actualiza_estado('Error Validacion','Tipo comprobante invalido')
*!*				RETURN .f.
*!*			ENDIF 
*!*			IF vacio(ecf_encabezado.comprobante_numero)
*!*				this.actualiza_estado('Error Validacion','Especifique el comprobante electronico')
*!*				RETURN .f.
*!*			ENDIF
*!*			IF ecf_encabezado.comprobante_tipo='43' AND ecf_encabezado.itbis1+ecf_encabezado.itbis2+ecf_encabezado.itbis3>0
*!*				this.actualiza_estado('Error Validacion','Los gastos menores no llevan itbis')
*!*				RETURN .f.
*!*			ENDIF  
*!*			 
*!*			LOCAL r,args,json
*!*			json=this.getEcfJson()
*!*			args=TEXTMERGE('{"rnc":"<<ALLTRIM(ecf_encabezado.empresa_rnc)>>","portal":"<<ALLTRIM(ecf_encabezado.portal)>>","json":<<json>>}')
*!*		
*!*			r=this.http.post('/send-ecf',args)
*!*	*		r=this.http.post('/fe/recepcion/api/ecf',args)
*!*					
*!*	*		r=http('http://176.16.20.20:3001/send-ecf',args)
*!*			

*!*			
*!*			IF VARTYPE(r.response)='O'
*!*				LOCAL setdate
*!*				setdate='set date to '+SET('date')
*!*				SET DATE TO AMERICAN 
*!*				SELECT ecf_encabezado
*!*				LOCAL cmensajes,x

*!*			    replace respuesta_trackId 				WITH r.response.get('trackid','');
*!*					    respuesta_codigo  				WITH TRANSFORM(r.response.get('codigo',''));
*!*					    respuesta_codigo_seguridad		WITH TRANSFORM(r.response.get('codigoSeguridad','')) ;
*!*					    respuesta_fecha_firma			WITH TRANSFORM(r.response.get('fechaFirma',''));
*!*					    respuesta_timbre				WITH r.response.get('timbre','');
*!*					    respuesta_estado  				WITH r.response.get('estado','');
*!*					    respuesta_secuenciaUtilizada  	WITH r.response.get('secuenciaUtilizada',.f.);
*!*					    respuesta_fechaRecepcion  		WITH CTOT(r.response.get('fechaRecepcion',''));
*!*					    respuesta_mensajes  			WITH r.response.get('mensajes','')
*!*				
*!*				&setdate			
*!*				this.sync_ecf()

*!*				
*!*				*MESSAGEBOX('COMPROBANTE ENVIADO A DGII')
*!*			else
*!*				MESSAGEBOX(r.response)
*!*				MESSAGEBOX('Fallo la generacion del eNCF')	
*!*				RETURN .f.
*!*			ENDIF 
*!*			RETURN .t.
*!*		ENDPROC 
*!*		
*!*		PROCEDURE getEcfStatus
*!*			PARAMETERS trackid
*!*			SET PROCEDURE TO json ADDITIVE 
*!*			IF !this.login()
*!*				RETURN ''
*!*			ENDIF 
*!*			*trackid='0d9463de-af5f-41da-8c4e-9cbc4f951e14'
*!*			PRIVATE r
*!*			r= this.http.post('/cg/ecf/ecfRequestByTrakid',TEXTMERGE('{"id":"<<trackid>>"}'))
*!*			IF VARTYPE(r.response)='O'
*!*				RETURN r.response.estado
*!*			ELSE 
*!*				RETURN ''
*!*			ENDIF 
*!*		ENDPROC 	
	
   *---------------------------------------------------------------------------------------------------
	PROCEDURE getEcfJson()
		LOCAL cdetalle as String , cstring as String 
		cdetalle=this.detalle()
		SELECT ecf_encabezado
		TEXT TO cstring NOSHOW TEXTMERGE 
			{
				"Encabezado":{
					"Version":"1.0",
					"IdDoc":{
						"TipoeCF":"<<t(comprobante_tipo)>>",
						"eNCF":"<<t(comprobante_numero)>>",
						"FechaVencimientoSecuencia":"<<this.date_format(comprobante_fechavence)>>",
						"IndicadorNotaCredito":"<<icase(comprobante_tipo!='34','',(fecha-ncf_modificado_fecha)>30,'1','0')>>",
						"IndicadorMontoGravado":"0",
						"TipoIngresos":"01",
						"TipoPago":<<IIF(venta_de_contado,'1','2')>>,
						"FechaLimitePago":"<<this.date_format(fecha_vencimiento)>>",
						"TerminoPago":"<<t(terminos_de_pago)>>",
						"TablaFormasPago":<<this.fpagos2json()>>
					},
					"Emisor":{
						"RNCEmisor":"<<t(empresa_rnc)>>",
						"RazonSocialEmisor":"<<t(empresa_razon_social)>>",
						"NombreComercial":"<<t(empresa_nombre_comercial)>>",
						"DireccionEmisor":"<<t(empresa_direccion)>>",
						"TablaTelefonoEmisor":<<this.telefonos_emisor()>>,
						"CorreoEmisor":"<<t(empresa_correo)>>",
						"FechaEmision":"<<this.date_format(ecf_encabezado.fecha)>>"
					},
					"Comprador":{
						"RNCComprador":"<<t(cliente_rnc)>>",
						"IdentificadorExtranjero":"<<ALLTRIM(cliente_id_extranjero)>>",
						"RazonSocialComprador":"<<t(cliente_razon_social)>>",
						"ContactoComprador":"<<t(cliente_contacto)>>",
						"CorreoComprador":"<<Iif(AT('@', t(cliente_correo)) > 0, t(cliente_correo), '')>>",
						"DireccionComprador":"<<t(cliente_direccion)>>",
						"PaisComprador":"<<t(cliente_pais)>>",
						"FechaEntrega":"<<this.date_format(cliente_fecha_entrega)>>",
						"ContactoEntrega":"<<t(cliente_contacto_entrega)>>",
						"DireccionEntrega":"<<t(cliente_direccion_entrega)>>",
						"TelefonoAdicional":"",
						"FechaOrdenCompra":"<<this.date_format(orden_compra_fecha)>>",
						"NumeroOrdenCompra":"<<t(orden_compra_numero)>>",
						"CodigoInternoComprador":"<<t(cliente_codigo)>>",
						"ResponsablePago":"<<t(cliente_responsable_pago)>>"
					},
					"Totales":{
						"MontoGravadoTotal":<<monto_gravado1+monto_gravado2+monto_gravado3>>,
						"MontoGravadoI1":<<monto_gravado1>>,
						"MontoGravadoI2":<<monto_gravado2>>,
						"MontoGravadoI3":<<monto_gravado3>>,
						"MontoExento":<<monto_exento>>,
						"ITBIS1":<<itasa1>>,
						"ITBIS2":<<itasa2>>,
						"ITBIS3":<<itasa3>>,
						"TotalITBIS":<<itbis1+itbis2+itbis3>>,
						"TotalITBIS1":<<itbis1>>,
						"TotalITBIS2":<<itbis2>>,
						"TotalITBIS3":<<itbis3>>,
						"MontoTotal":<<total_factura>>,
						"TotalITBISRetenido":<<itbis_retenido_total>>,
						"TotalISRRetencion":<<isr_retenido_total>>
					}
				},

				"DetallesItems":<<cdetalle>>,
				"DescuentosORecargos":[{
					"NumeroLinea":1,
					"TipoAjuste":"D",
					"DescripcionDescuentooRecargo":"Descuento",
					"TipoValor":"$",
					"ValorDescuentooRecargo":0,
					"MontoDescuentooRecargo":<<descuento_global_valor>>,
					"IndicadorFacturacionDescuentooRecargo":1
				}],
				"InformacionReferencia":{
					"NCFModificado":"<<ALLTRIM(NVL(ncf_modificado_numero,''))>>",
					"FechaNCFModificado":"<<this.date_format(ncf_modificado_fecha)>>",
					"CodigoModificacion":<<NVL(ncf_modificado_tipo_modificacion,0)>>
				}
			}

		ENDTEXT 
		_cliptext = cstring 
		RETURN cstring 
	ENDPROC
	
	PROCEDURE telefonos_emisor()
		LOCAL r
		r=''
		IF !vacio(empresa_telefono1)
			r=r+',"'+phone_format(empresa_telefono1)+'"'
		ENDIF 
		IF !vacio(empresa_telefono2)
			r=r+',"'+phone_format(empresa_telefono2)+'"'
		ENDIF 
		IF !vacio(empresa_telefono3)
			r=r+',"'+phone_format(empresa_telefono3)+'"'
		ENDIF
		RETURN '['+SUBSTR(r,2)+']' 
	ENDPROC 
	
	PROCEDURE detalle()
		LOCAL r,det
		r=''
		SELECT ecf_detalle
		SCAN
			TEXT TO r ADDITIVE TEXTMERGE PRETEXT 2 NOSHOW 
			,{
				"NumeroLinea":<<RECNO()>>,
				"TablaCodigosItem":[{
					"TipoCodigo":"Interna",
                    "CodigoItem":"<<t(codigo)>>"
				}],
				"IndicadorFacturacion":<<tipo_asignacion_itbis>>,
				"Retencion":{
					"IndicadorAgenteRetencionoPercepcion":1,
					"MontoITBISRetenido":<<itbis_retenido>>,
					"MontoISRRetenido":<<isr_retenido>>
				},
				"NombreItem":"<<t(nombre)>>",
				"IndicadorBienoServicio":<<IIF(servicio,2,1)>>,
				"DescripcionItem":"<<t(descripcion)>>",
				"CantidadItem":<<cantidad>>,
				"UnidadMedida":<<unidad>>,
				"PrecioUnitarioItem":<<precio>>,
				"MontoItem":<<ROUND(precio*cantidad,2)-descuento_valor>>,
				"DescuentoMonto":<<descuento_valor>>,
				"TablaSubDescuento":[{
					"TipoSubDescuento":"$",
					"MontoSubDescuento":<<descuento_valor>>
				}]
			}	
			ENDTEXT 
		ENDSCAN  
		r='['+SUBSTR(r,2)+']'
		RETURN r
	ENDPROC 
	

   *-------------------------------------------------------------------------	
	PROCEDURE date_format 
	  * Iniciar Variables 
	    LPARAMETERS ldFecha as Date 
	    LOCAL strDate as String 
	    
	  * Procesar 
	    IF vacio(ldFecha) OR VARTYPE(ldFecha) != "D" OR EMPTY(ldFecha) THEN 
	       strDate = ''
	    ELSE 
	       strDate = TRANSFORM(DAY(ldFecha),'@l 99')+'-'+TRANSFORM(month(ldFecha),'@l 99')+'-'+TRANSFORM(year(ldFecha),'@l 9999')
	    ENDIF 
	  
	  * Finalizar
	    RETURN strDate
	ENDPROC
	
   *-------------------------------------------------------------------------	
	PROCEDURE fpagos2json
	  * Iniciar variables 
	    LOCAL lcResult as String 
	    lcResult = ''
	    
	  * Procesar 
	    IF pTabla_tiene_Registros('ecf_fpago') then
	       SCAN 
	          lcResult = lcResult+',{"FormaPago":'+TRANSFORM(tipo)+',"MontoPago":'+TRANSFORM(pagado)+'}'
	       ENDSCAN 
	       lcResult = '['+SUBSTR(lcResult,2)+']'
	    ELSE 
	       lcResult = '[]'
	    ENDIF 
	  
	  * Finalizar 
	    SELECT ecf_encabezado
	    RETURN lcResult
	  
*!*			IF EOF('ecf_fpago')
*!*				RETURN '[]'
*!*			ENDIF 
*!*			
*!*			SELECT ecf_fpago
*!*			LOCAL r
*!*			r=''
*!*			SCAN
*!*				r=r+',{"FormaPago":'+TRANSFORM(tipo)+',"MontoPago":'+TRANSFORM(pagado)+'}'
*!*			ENDSCAN 
*!*			SELECT ecf_encabezado
*!*			RETURN '['+SUBSTR(r,2)+']'
	ENDPROC 

*!*		PROCEDURE generateListas
*!*			IF !USED('ecf_fpago_list')
*!*				CREATE CURSOR ecf_fpago_list(codigo i,descripcion c(60))
*!*				INSERT INTO ecf_fpago_list values(1,'Efectivo')
*!*				INSERT INTO ecf_fpago_list values(2,'Cheque/Transferencia/Deposito')
*!*				INSERT INTO ecf_fpago_list values(3,'Tarjeta')
*!*				INSERT INTO ecf_fpago_list values(4,'Venta a Credito')
*!*				INSERT INTO ecf_fpago_list values(5,'Bonos o Certificados de regalo')
*!*				INSERT INTO ecf_fpago_list values(6,'Permuta')
*!*				INSERT INTO ecf_fpago_list values(7,'Nota de Credito')
*!*				INSERT INTO ecf_fpago_list values(8,'Otras Formas de pago')
*!*			ENDIF
*!*			
*!*			IF !USED('ecf_unidad')
*!*				CREATE CURSOR ecf_unidad(;
*!*					codigo i,;
*!*					abbr c(20),;
*!*					nombre c(80))

*!*				insert into ecf_unidad values(1   ,'BARR',        'Barril')
*!*				insert into ecf_unidad values(2   ,'BOL',         'Bolsa')
*!*				insert into ecf_unidad values(3   ,'BOT',         'Bote')
*!*				insert into ecf_unidad values(4   ,'BULTO',       'Bultos')
*!*				insert into ecf_unidad values(5   ,'BOTELLA',     'Botella')
*!*				insert into ecf_unidad values(6   ,'CAJ',         'Caja/CajÃ³n')
*!*				insert into ecf_unidad values(7   ,'CAJETILLA',   'Cajetilla')
*!*				insert into ecf_unidad values(8   ,'CM',          'CentÃ­metro')
*!*				insert into ecf_unidad values(9   ,'CIL',         'Cilindro')
*!*				insert into ecf_unidad values(10  ,'CONJ',        'Conjunto')
*!*				insert into ecf_unidad values(11  ,'CONT',        'Contenedor')
*!*				insert into ecf_unidad values(12  ,'DÃA',         'DÃ­a')
*!*				insert into ecf_unidad values(13  ,'DOC',         'Docena')
*!*				insert into ecf_unidad values(14  ,'FARD',        'Fardo')
*!*				insert into ecf_unidad values(15  ,'GL',          'Galones')
*!*				insert into ecf_unidad values(16  ,'GRAD',        'Grado')
*!*				insert into ecf_unidad values(17  ,'GR',          'Gramo')
*!*				insert into ecf_unidad values(18  ,'GRAN',        'Granel')
*!*				insert into ecf_unidad values(19  ,'HOR',         'Hora')
*!*				insert into ecf_unidad values(20  ,'HUAC',        'Huacal')
*!*				insert into ecf_unidad values(21  ,'KG',          'Kilogramo')
*!*				insert into ecf_unidad values(22  ,'kWh',         'Kilovatio Hora')
*!*				insert into ecf_unidad values(23  ,'LB',          'Libra')
*!*				insert into ecf_unidad values(24  ,'LITRO',       'Litro')
*!*				insert into ecf_unidad values(25  ,'LOT',         'Lote')
*!*				insert into ecf_unidad values(26  ,'M',           'Metro')
*!*				insert into ecf_unidad values(27  ,'M2',          'Metro Cuadrado')
*!*				insert into ecf_unidad values(28  ,'M3',          'Metro CÃºbico')
*!*				insert into ecf_unidad values(29  ,'MMBTU',       'Millones de Unidades TÃ©rmicas')
*!*				insert into ecf_unidad values(30  ,'MIN',         'Minuto')
*!*				insert into ecf_unidad values(31  ,'PAQ',         'Paquete')
*!*				insert into ecf_unidad values(32  ,'PAR',         'Par')
*!*				insert into ecf_unidad values(33  ,'PIE',         'Pie')
*!*				insert into ecf_unidad values(34  ,'PZA',         'Pieza')
*!*				insert into ecf_unidad values(35  ,'ROL',         'Rollo')
*!*				insert into ecf_unidad values(36  ,'SOBR',        'Sobre')
*!*				insert into ecf_unidad values(37  ,'SEG',         'Segundo')
*!*				insert into ecf_unidad values(38  ,'TANQUE',      'Tanque')
*!*				insert into ecf_unidad values(39  ,'TONE',        'Tonelada')
*!*				insert into ecf_unidad values(40  ,'TUB',         'Tubo')
*!*				insert into ecf_unidad values(41  ,'YD',          'Yarda')
*!*				insert into ecf_unidad values(42  ,'YD2',         'Yarda cuadrada')
*!*				insert into ecf_unidad values(43  ,'UND',         'Unidad')
*!*				insert into ecf_unidad values(44  ,'EA',          'Elemento')
*!*				insert into ecf_unidad values(45  ,'MILLAR',      'Millar')
*!*				insert into ecf_unidad values(46  ,'SAC',         'Saco')
*!*				insert into ecf_unidad values(47  ,'LAT',         'Lata')
*!*				insert into ecf_unidad values(48  ,'DIS',         'Display')
*!*				insert into ecf_unidad values(49  ,'BID',         'BidÃ³n')
*!*				insert into ecf_unidad values(50  ,'RAC',         'RaciÃ³n')
*!*				insert into ecf_unidad values(51  ,'Q',           'Quintal')
*!*				insert into ecf_unidad values(52  ,'GRT',         'Gross Register Tonnage (Toneladas de registro bruto)')
*!*				insert into ecf_unidad values(53  ,'P2',          'Pie cuadrado     ')
*!*				insert into ecf_unidad values(54  ,'PAX',         'Pasajero')
*!*				insert into ecf_unidad values(55  ,'PULG',        'Pulgadas')
*!*				insert into ecf_unidad values(56  ,'STAY',        'Parqueo barcos en muelle')
*!*				insert into ecf_unidad values(57  ,'BDJ',         'Bandeja')


*!*					
*!*			ENDIF  
*!*		ENDPROC 
	
*!*		PROCEDURE ecfCreateCursors()
*!*			this.generateListas()
*!*			CREATE CURSOR ecf_encabezado(;
*!*				portal c(20) DEFAULT 'cert',;
*!*				empresa_rnc c(11),;
*!*				empresa_razon_social c(150),;
*!*				empresa_nombre_comercial c(150),;
*!*				empresa_direccion c(100),;
*!*				empresa_telefono1 c(12),;
*!*				empresa_telefono2 c(12),;
*!*				empresa_telefono3 c(12),;
*!*				empresa_correo c(80),;
*!*				vendedor c(60),;
*!*				factura c(20),;
*!*				pedido c(20),;
*!*				fecha d,;
*!*				comprobante_tipo c(2),;
*!*				comprobante_numero c(13),;
*!*				comprobante_fechavence d,;
*!*				comprobante_tipob_numero c(11),;
*!*				venta_de_contado l,;
*!*				fecha_vencimiento d ,;
*!*				terminos_de_pago c(15),;
*!*				cliente_rnc c(20),;
*!*				cliente_id_extranjero c(20),;
*!*				cliente_razon_social c(150),;
*!*				cliente_contacto c(80),;
*!*				cliente_correo c(80),;
*!*				cliente_direccion c(100),;
*!*				cliente_pais c(60),;
*!*				cliente_fecha_entrega d,;
*!*				cliente_contacto_entrega c(100),;
*!*				cliente_direccion_entrega c(100),;
*!*				cliente_telefono c(12),;
*!*				cliente_codigo c(20),;
*!*				cliente_responsable_pago c(20),;
*!*				orden_compra_fecha d,;
*!*				orden_compra_numero c(20),;
*!*				monto_gravado1 n(15,2) NOT null,;
*!*				monto_gravado2 n(15,2) NOT null,;
*!*				monto_gravado3 n(15,2) NOT null,;
*!*				monto_exento n(15,2) NOT null,;
*!*				descuento_global_valor n(15,2) NOT null,;
*!*				itasa1 n(15,2) NOT null,;
*!*				itasa2 n(15,2) NOT null,;
*!*				itasa3 n(15,2) NOT null,;
*!*				itbis1 n(15,2) NOT null,;
*!*				itbis2 n(15,2) NOT null,;
*!*				itbis3 n(15,2) NOT null,;
*!*				total_factura n(15,2) NOT NULL,;
*!*				itbis_retenido_total n(15,2),;
*!*				isr_retenido_total n(15,2),;
*!*				ncf_modificado_numero c(20),;
*!*				ncf_modificado_fecha d,;
*!*				ncf_modificado_tipo_modificacion i,;
*!*			    respuesta_trackId c(36),;
*!*			    respuesta_codigo c(10),;
*!*			    respuesta_codigo_seguridad c(10),;
*!*			    respuesta_fecha_firma c(20),;
*!*			    respuesta_timbre c(250),;
*!*			    respuesta_estado c(20),;
*!*			    respuesta_secuenciaUtilizada l,;
*!*			    respuesta_fechaRecepcion t ,;
*!*			    respuesta_mensajes c(254);
*!*			)
*!*			APPEND BLANK 			
*!*			CREATE CURSOR ecf_fpago(;
*!*				tipo i NOT NULL DEFAULT 1 check(BETWEEN(tipo,1,8)) ERROR 'Forma de pago invalidad, verificar cursor ecf_fpago_list',;
*!*				pagado n(15,2) NOT NULL check(pagado>0) ERROR 'el monto pagado debe ser mayor que cero';
*!*			)
*!*			
*!*			CREATE CURSOR ecf_detalle(;
*!*				codigo c(35),;
*!*				tipo_asignacion_itbis i check(between(tipo_asignacion_itbis,0,4)),;
*!*				nombre c(80),;
*!*				servicio l,;
*!*				descripcion c(254),;
*!*				cantidad n(15,2),;
*!*				unidad c(2),;
*!*				precio n(15,4),;
*!*				descuento_porcentual n(15,2),;
*!*				descuento_valor n(15,2),;
*!*				itbis_retenido n(15,2),;
*!*				isr_retenido n(15,2);
*!*				)
*!*				
*!*		ENDPROC 


   *---------------------------------------
	PROCEDURE pOpenDbf
	  LPARAMETERS lcTblName as String 
	  lbReturn = .f. 
	  IF VARTYPE(lcTblName) = "C"  AND !EMPTY(lcTblName) THEN 
	     this.pCloseDbf(lcTblName)
         TRY 
            USE sync_ecf IN 0 SHARED NOUPDATE 
            SELECT sync_ecf
            lbReturn = .t. 
         CATCH
            AERROR(laError)
            MESSAGEBOX("Imposible Accesar la Tabla de NCF"+CHR(13)+"Detalle: "+laError(2))
         ENDTRY 
	  ENDIF 
	  RETURN lbReturn 
	ENDPROC   
	     
   *---------------------------------------
	PROCEDURE pClosedbf
	  LPARAMETERS lcTblName as String 
	  IF this.pSelect(lcTblName) THEN 
	     USE 
	  ENDIF 
	  RETURN 
	ENDPROC   

   *---------------------------------------
	PROCEDURE pSelect
	  LPARAMETERS lcTblName as String 
	  LOCAL lbReturn as Boolean 
	  lbReturn = .f. 
	  IF VARTYPE(lcTblName) = "C"  AND !EMPTY(lcTblName) AND USED(lcTblName) THEN 
	     SELECT (lcTblName)
	     lbReturn = .t. 
	  ENDIF 
	  RETURN lbReturn 
	ENDPROC 

   *---------------------------------------
	PROCEDURE pTabla_Tiene_Registros
	  LPARAMETERS lcTblName as String 
	  LOCAL lbReturn as Boolean 
	  lbReturn = .f. 
	  IF this.pSelect(lcTblName) THEN 
	     GO TOP 
	     lbReturn = !EOF()
	  ENDIF 
	  RETURN lbReturn 
	ENDPROC 



ENDDEFINE 

PROCEDURE t(x)
	x=strtran(x,'"','')
	x=STRTRAN(x,CHR(13),' ')
	RETURN ALLTRIM(x)
ENDPROC 


Procedure ncf(x)
	Local nselect,r
	nselect=Select()
	next_ncf_codigo=x
	TEXT TO cstring NOSHOW 
		update fiscal set contador=contador+1 where codigo=?next_ncf_codigo
		SELECT prefijo,contador FROM fiscal WHERE codigo=?next_ncf_codigo
	ENDTEXT 
	If !request(cstring,'get_ncf')
		Select (nselect)
		Return ''
	Endif 
	r=ALLTRIM(get_ncf.prefijo)+Transform(get_ncf.contador,'@l 99999999')
	Select (nselect)
	Return r
Endproc 


PROCEDURE v()
	replace empresa_rnc WITH '131086268'
	replace empresa_razon_social WITH 'Vicortiz Softwares srl'
	replace empresa_nombre_comercial WITH 'Vicortiz Softwares srl'
	replace empresa_direccion WITH 'Autopista de San isidro plaza jeanca v local 7A'
ENDPROC 

PROCEDURE phone_format(x)
	IF vacio(x)
		RETURN ''
	ENDIF 
	x=ALLTRIM(x)
	x=STRTRAN(x,'-','')
	x=STRTRAN(x,'(','')
	x=STRTRAN(x,')','')
	RETURN TRANSFORM(VAL(x),'999-999-9999')
endproc 






