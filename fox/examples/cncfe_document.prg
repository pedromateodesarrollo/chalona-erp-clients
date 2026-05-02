
*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_Document as cNcfE_Document_Source
      
    * Clases
*      ADD OBJECT cCompraMercancia as cNcfE_CompraMercancia
      ADD OBJECT cVtaCredito      as cNcfE_VtaCredito
      ADD OBJECT cVtaContado      as cNcfE_VtaContado
      ADD OBJECT cCompraServicio  as cNcfE_CompraServicio
      ADD OBJECT cGastoMenor      as cNcfE_GastoMenor
      ADD OBJECT cVtaSercicio     as cNcfE_VtaSercicio

      ADD OBJECT cNotaCredito  as cNcfE_NotaCredito
*      ADD OBJECT cNotaDebito   as cNcfE_NotaDebito

    *--------------------------------------------
     PROCEDURE pCalcularTotales 
       WITH this 
          * Calcular: SubTotal 
           .oSubTotal = .oExento + .oMonto1 + .oMonto2 + .oMonto3 + .oMonto4 
           .oImporte  = .oSubTotal + this.pTotal_Itbis()
           
          * Proporcionalidad: Descuento 
            IF .oDescu > 0 AND .oSubTotal > 0 then
               .oMonto1 = .oMonto1 - this.pCal_Proporcionalidad(.oSubTotal, .oDescu, .oMonto1 )
               .oMonto2 = .oMonto2 - this.pCal_Proporcionalidad(.oSubTotal, .oDescu, .oMonto2 )
               .oMonto3 = .oMonto3 - this.pCal_Proporcionalidad(.oSubTotal, .oDescu, .oMonto3 )
               .oMonto4 = .oMonto4 - this.pCal_Proporcionalidad(.oSubTotal, .oDescu, .oMonto4 )
               .oExento = .oExento - this.pCal_Proporcionalidad(.oSubTotal, .oDescu, .oExento )
            ENDIF 
            
          * Proporcionalidad: Cargo
            IF .oCargo > 0 AND .oSubTotal > 0 then
               .oMonto1 = .oMonto1 - this.pCal_Proporcionalidad(.oSubTotal, .oCargo, .oMonto1 )
               .oMonto2 = .oMonto2 - this.pCal_Proporcionalidad(.oSubTotal, .oCargo, .oMonto2 )
               .oMonto3 = .oMonto3 - this.pCal_Proporcionalidad(.oSubTotal, .oCargo, .oMonto3 )
               .oMonto4 = .oMonto4 - this.pCal_Proporcionalidad(.oSubTotal, .oCargo, .oMonto4 )
               .oExento = .oExento - this.pCal_Proporcionalidad(.oSubTotal, .oCargo, .oExento )
            ENDIF 
          
          * Calcular el Monto 
           .oMonto = .oExento + .oMonto1 + .oMonto2 + .oMonto3 + .oMonto4 - .oDescu
          
          * Calcular: SubTotal 
           .oItbis = this.pTotal_Itbis()
           
          * Total 
           .oImporte  = .oMonto + .oItbis
       ENDWITH 
       RETURN this.pSetTotales(this.parent.curEncabezado)
     ENDPROC 

    *--------------------------------------------
     PROCEDURE msgError
       LPARAMETERS msgError
       IF this.pIsCharacter(msgError) AND !EMPTY(ALLTRIM(msgError)) then
          this.pShowError(400,"Error","Imposible Cargar este Documento"+CHR(13)+"Detalle: "+msgError, .t.)
       ENDIF 
       RETURN 
     ENDPROC 

    *--------------------------------------------
     PROCEDURE pSetMedioDePago
       * Iniciar las Variables 
         LPARAMETERS liMedioPago as Integer, lyImporte as Currency, curData as String  
         LOCAL lbReturn as Boolean, curMedioPago as String, msgError as String    
         lbReturn     = .f. 
         msgError    = ""
       
       * Procesar 
         IF this.pIsNumeric(liMedioPago) AND BETWEEN(liMedioPago,1,8) then
            IF this.pSelect(curData) then
               TRY 
                  INSERT INTO &curData (tipo,pagado) VALUES (liMedioPago, lyImporte )
                  lbReturn = .t. 
               CATCH
                  AERROR(laError)
                  msgError = ALLTRIM(laError(2))
               ENDTRY 
            ENDIF 
         ELSE 
            msgError = "Archivo de Medio de Pago del Documento No Esta Disponible"+CHR(13)+"Program: "+PROGRAM()
         ENDIF 
         
       * Finalizar 
         this.msgError(msgError)
         RETURN lbReturn 
     ENDPROC 

    *--------------------------------------------
     PROCEDURE pSetDefault
       * Iniciar Variables
         LPARAMETERS liTipo as Integer, lcValue as String 
         LOCAL lcResult as String 
         lcResult = ""
         lcValue  = ALLTRIM(lcValue)
         
       * Procesar 
         DO CASE 
            CASE liTipo = 1					&& Rnc
                 lcResult = ALLTRIM(this.pSoloNumeros(lcValue))
                 IF EMPTY(lcResult) THEN 
                    lcResult = "00000000001"
                 ENDIF 
         ENDCASE 
       
       * Finalizar 
         RETURN lcResult 
     
     ENDPROC 

*!*	    *--------------------------------------------
*!*	     PROCEDURE pSetPayMethod
*!*	       * Iniciar Variables 
*!*	         LPARAMETERS curData as Integer, destiny_curPayMethod as String  
*!*	         LOCAL lbReturn as Boolean, msgError as String
*!*	         lbReturn = .f. 
*!*	         msgError = ""
*!*	         
*!*	       * Procesa 
*!*	         IF this.pTabla_tiene_registros(curData) then
*!*	            MESSAGEBOX("Cargar Metodo de Pago")
*!*	         ENDPROC 

*!*	       * Finalizar 
*!*	         this.msgError(msgError)
*!*	         RETURN lbReturn 
*!*	     ENDPROC 


    *--------------------------------------------
     PROCEDURE pSetHeader 
       * Iniciar Variables 
         LPARAMETERS curData as Integer, destiny_curEncabezado as String  
         LOCAL lbReturn as Boolean, msgError as String
         lbReturn = .f. 
         msgError = ""
         
       * Procesa 
         IF this.pTabla_tiene_registros(curData) then
            ON ERROR 
            TRY
               WITH this
                  * Datos: Docuento
                   .oNumero_Documento    = this.pFormatDocumento(numero_cuadre, numero_documento)
                   .oFecha_Documento     = fecha_documento
                   .oPedido_Documento    = ALLTRIM(ordenco_documento)
*                   .oContado_documento   = .t. 
                   .oVence_Documento     = vence_documento
                   .oTermino_Documento   = "" 									&& Termino de Pago
                   .oFecha_Orden_Compra  = DATE()
                   .oNumero_Orden_Compra = ""
                   .oMedio_de_Pago       = idMedio_pago
              
                  * Datos: Cliente
                   .oCodigo_Cliente    = TRANSFORM(codigo_cliente,"@l 99999")
                   .oRnc_Cliente       = this.pSetDefault(1,rnc_cliente)
                   .oIdExt_cliente     = ""
                   .oNombre_Cliente    = ALLTRIM(nombre_cliente)
                   .oContacto_cliente  = ALLTRIM(Contacto_cliente)
                   .oCorreo_Cliente    = .pFormatEmail(correo_cliente)
                   .oDir_Cliente       = ALLTRIM(dir_cliente)
                   .oPais_cliente      = "Republica Dominicana"
                   .oTelefono1_Cliente = ALLTRIM(this.pFormatTelefono(telefono1_cliente))
                   .oTelefono2_Cliente = ALLTRIM(this.pFormatTelefono(telefono2_cliente))
                   .oTelefono3_Cliente = ALLTRIM(this.pFormatTelefono(telefono3_cliente))
                   .oTipoNcf_Cliente   = tiponcf_cliente
                  
                  * Datos: NCF 
                   .oNumero_NCF       = ALLTRIM(ncf_documento)
                   .oVence_Ncf        = ncfvende_documento
                   
                  * Datos: NCF Afectado
                    IF SUBSTR(.oNumero_NCF,1,3) = "E34" THEN 
                      .oMod_numero_Ncf = ALLTRIM(ncf_afectado)
                      .oMod_Fecha_Ncf  = ncfvende_afectado
                      .oMod_Tipo_ncf   = ncfTipo_afectado
                    ENDIF 
                   
                  * Datos: Vendedor 
                   .oNombre_Vendedor   = ALLTRIM(nombre_vendedor)

                  * Datos: Itbis Retenido
                   .oItbis_retenido = ritbis
                   .oIsr_retenido   = risr
              
                  * Datos: Entrega
                   .oFecha_Entrega     = fecha_documento
                   .oContacto_Entrega  = ALLTRIM(nombre_cliente)
                   .oDir_Entrega       = ALLTRIM(dir_cliente)
                   .oTel_Entrega       = ALLTRIM(this.pFormatTelefono(telefono1_cliente))
                   .oResposable_pago   = ""
                   
                  * Finalizar 
                    lbReturn = .t.
               ENDWITH 

            CATCH
               AERROR(laError)
               msgError = ALLTRIM(laError(2))
            ENDTRY 
         ELSE 
            msgError = "Este Documento no Existe. Fin de la Busqueda"
         ENDIF 
         
       * Setear Datos en Cursor
         IF lbReturn then
            lbReturn = this.pSetEncabezado(destiny_curEncabezado)
         ENDIF 
         
       * Finalizar 
         this.msgError(msgError)
         RETURN lbReturn 
     ENDPROC 
     
     *--------------------------------------------
     PROCEDURE pSetDetail
       * Iniciar Variables 
         LPARAMETERS curData as Integer, destiny_curDetalle as String  
         LOCAL lbReturn as Boolean, msgError as String 
         lbReturn = .f. 
         msgError = ""

       * Procesa 
         IF this.pTabla_tiene_registros(curData) then
            SCAN 
                * Iniciar Variables 
                  lcCodigo   = TRANSFORM(idProducto_det,"@lz 999999")
*                  liIdTitbis = ICASE(porcItbis_det = 16,1,porcItbis_det=18,2,0)
                  liIdTitbis = ICASE(porcItbis_det = 18,1,porcItbis_det=16,2,4)
                  lcNombre   = ALLTRIM(Nombre_Producto_det)
                  lyCantidad = cantidad_det 
                  lcUnidad   = "1"
                  lbServicio = servicio_det
                  lyPrecio   = precio_det
                  lyDescu2   = descuento_det
                  lyCargo2   = 0
                  lySubTotal = ROUND(lyCantidad * lyPrecio, 4)
            
                * Calcular Totales 
                  WITH this
                       DO CASE 
                          CASE liIdTitbis = 1						&& 18&
                              .oMonto1  = .oMonto1 + lySubTotal - lyDescu2 + lyCargo2
                          CASE liIdTitbis = 2						&& 16&
                              .oMonto2  = .oMonto2 + lySubTotal - lyDescu2 + lyCargo2
                          CASE liIdTitbis = 3						&& Otros Impuesto
                              .oMonto3  = .oMonto3 + lySubTotal - lyDescu2 + lyCargo2
                       OTHERWISE 
                              .oExento  = .oExento + lySubTotal - lyDescu2 + lyCargo2
                       ENDCASE 
                  ENDWITH 
                  
                * Actualizar Cursor 
                  SELECT (destiny_curDetalle)
                          APPEND BLANK 
                          replace codigo                WITH lcCodigo ,;
                                  tipo_asignacion_itbis with liIdTitbis,;
                                  nombre                WITH lcNombre ,;
                                  servicio              WITH lbServicio ,;
                                  descripcion           WITH "" ,;
                                  cantidad              WITH lyCantidad ,;
                                  unidad                WITH TRANSFORM(lcUnidad,"@z 9999") ,;
                                  Precio                WITH lyPrecio ,;
                                  Descuento_porcentual  WITH 0 ,;
                                  descuento_valor       WITH lyDescu2 ,;
                                  itbis_retenido        WITH 0 ,;
                                  isr_retenido          WITH 0
                * Finalizr 
                  SELECT (curData)
            ENDSCAN 
            = this.pTabla_tiene_registros(destiny_curDetalle)
            lbReturn = this.pCalcularTotales()
         ELSE 
            msgError = "Este Documento no Tiene Detalle (Items). Fin de la Busqueda"
         ENDIF 
         
         
       * Finalizar 
         this.msgError(msgError)
         RETURN lbReturn 
     ENDPROC 
      
 ENDDEFINE 


*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------


*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_CompraServicio as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"


    *--------------------------------------------
     PROCEDURE pGetDocumento 
       * Iniciar Variables 
         LPARAMETERS liFactura as Integer, destiny_curEncabezado as String, destiny_curDetalle as String, destiny_curMedioPago as String  
         LOCAL lbReturn as Boolean, curEncabezado as String, curDetalle as String, curMedioPago as string, liMedioPago as Integer  
         lbReturn = .f. 
         WITH this.parent
             .pLimpiarDatos()
              curEncabezado = .pGetCursorName()
              curDetalle    = .pGetCursorName()
              curMedioPago  = .pGetCursorName()
         ENDWITH 
         
       * Procesar 
         IF this.pIsNumeric(liFactura) AND liFactura > 0 THEN 
          * Cargar Datos
            IF this.pSqlExec("regserv,vendedor,suplidor",this.pGetQuery(1,liFactura),curEncabezado) AND this.parent.pSetHeader(curEncabezado, destiny_curEncabezado) then
               IF this.pSqlExec("regserv,cuenta",this.pGetQuery(2,liFactura),curDetalle) AND this.parent.pSetDetail(curDetalle, destiny_curDetalle) THEN 
                  this.parent.oTermino_Documento = "21 Dias"
                  lbReturn = .t. 
*!*	                  IF pTabla_tiene_registros(curEncabezado) THEN 
*!*	                     liMedioPago = idMedio_pago
*!*	                     lyImporte   = Importe
*!*	                     lbReturn    = this.parent.pSetMedioDePago(liMedioPago, lyImporte, destiny_curMedioPago ) 
*!*	                  ENDIF 
               ENDIF 
            ENDIF 
          
          * Cerrar Cursores 
            WITH this 
                .pClosedbf(curEncabezado)
                .pClosedbf(curDetalle)
                .pClosedbf(curMedioPago)
            ENDWITH 
         ELSE
            this.pShowError(404,"Error en Parametro","El Número de Venta de Credito es Invalido o Cero", .t.)
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 

    *--------------------------------------------
     PROCEDURE pGetQuery
       LPARAMETERS liIdQuery as Integer, liFactura as Integer 
       LOCAL strQuery as String 
       strQuery = ""
       DO CASE 
          CASE liIdQuery = 1										&& Encabezado
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT  (0)                 as numero_cuadre,
                          a.Numero            as numero_documento,
                          a.ordenno           as ordenco_documento,
                          a.fecha             as fecha_documento,
                          (a.fecha+21)        as vence_documento,
                          a.codigo            as codigo_cliente,
                          a.fpago             as idMedio_pago, 					
                          (1)                 as codigo_Vendedor,
                          a.ncf               as ncf_documento, 
                          a.vence             as ncfvende_documento,
                          (0)                 as ritbis,
                          (0)                 as risr,
                          b.suplidor          as nombre_cliente,
                          b.rnc               as rnc_cliente ,
                          b.contacto1         as Contacto_cliente,
                          0                   as tiponcf_cliente, 			
                          b.direccion         as dir_cliente,
                          b.telefono1         as telefono1_cliente,
                          b.telefono2         as telefono2_cliente,
                          ("")                as telefono3_cliente, 
                          ("")                as correo_cliente,
                          ("EMPRESA")         as nombre_vendedor ,
                          a.importe 
                     from regserv a 
                          left join suplidor b on a.codigo = b.codigo And b.Empresa = <<mEmpresa>>
                     Where a.Numero = <<liFactura>> And 
                           a.Aux     = 1  And 
                           a.Empresa = <<mEmpresa>>
                     order by a.Numero
               ENDTEXT 
          CASE liIdQuery = 2										&& Detalle
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT a.tipo                   as idProducto_det,
                         (00000000000.0000)       as porcItbis_det,
                         a.itbis                  as itbis ,
                         NVL(b.cuenta, SPACE(40)) as Nombre_Producto_det,
                         (.f.)                    as servicio_det,
                         (1)                      as cantidad_det ,
                         a.monto                 as precio_det,
                         (0)                      as descuento_det
                     from detserv a 
                          left join cuenta b on ALLTRIM(a.cuenta) == ALLTRIM(b.cuenta) And b.Empresa = <<mEmpresa>>
                     Where a.Numero = <<liFactura>> And 
                           a.Empresa = <<mEmpresa>>
                     order by a.Numero
               ENDTEXT 
       ENDCASE 
       RETURN strQuery 
     ENDPROC 
 
 ENDDEFINE 

*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------


*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_GastoMenor as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"


    *--------------------------------------------
     PROCEDURE pGetDocumento 
       * Iniciar Variables 
         LPARAMETERS liFactura as Integer, destiny_curEncabezado as String, destiny_curDetalle as String, destiny_curMedioPago as String  
         LOCAL lbReturn as Boolean, curEncabezado as String, curDetalle as String, curMedioPago as string, liMedioPago as Integer  
         lbReturn = .f. 
         WITH this.parent
             .pLimpiarDatos()
              curEncabezado = .pGetCursorName()
              curDetalle    = .pGetCursorName()
              curMedioPago  = .pGetCursorName()
         ENDWITH 
         
       * Procesar 
         IF this.pIsNumeric(liFactura) AND liFactura > 0 THEN 
          * Cargar Datos
            IF this.pSqlExec("reggasto",this.pGetQuery(1,liFactura),curEncabezado)  AND this.parent.pSetHeader(curEncabezado, destiny_curEncabezado) then
               IF this.pSqlExec("detgasto,cuenta",this.pGetQuery(2,liFactura),curDetalle) AND this.parent.pSetDetail(curDetalle, destiny_curDetalle) THEN 
                  lbReturn = .t. 
               ENDIF 
            ENDIF 
            
          * Cerrar Cursores 
            WITH this 
                .pClosedbf(curEncabezado)
                .pClosedbf(curDetalle)
                .pClosedbf(curMedioPago)
            ENDWITH 
         ELSE
            this.pShowError(404,"Error en Parametro","El Número de Venta de Credito es Invalido o Cero", .t.)
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 

*!*	            MESSAGEBOX(3)
*!*	               IF this.pSqlExec("detgasto,cuenta",this.pGetQuery(2,liFactura),curDetalle) AND this.parent.pSetDetail(curDetalle, destiny_curDetalle) THEN 
*!*	                  IF pTabla_tiene_registros(curDetalle) THEN 
*!*	                     brow
*!*	                  ENDIF 
*!*	*                  this.parent.oTermino_Documento = "21 Dias"
*!*	*                  lbReturn = .t. 

*!*	*!*	                  IF pTabla_tiene_registros(curEncabezado) THEN 
*!*	*!*	                     liMedioPago = idMedio_pago
*!*	*!*	                     lyImporte   = Importe
*!*	*!*	                     lbReturn    = this.parent.pSetMedioDePago(liMedioPago, lyImporte, destiny_curMedioPago ) 
*!*	*!*	                  ENDIF 
*!*	               ENDIF 
*!*	            ENDIF 
          


    *--------------------------------------------
     PROCEDURE pGetQuery
       LPARAMETERS liIdQuery as Integer, liFactura as Integer 
       LOCAL strQuery as String 
       strQuery = ""
       DO CASE 
          CASE liIdQuery = 1										&& Encabezado
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT  (0)                 as numero_cuadre,
                          a.Numero            as numero_documento,
                          ("")                as ordenco_documento,
                          a.fecha             as fecha_documento,
                          a.fecha             as vence_documento,
                          ("")                as codigo_cliente,
                          ("")                as idMedio_pago, 					
                          ("")                as codigo_Vendedor,
                          a.ncf               as ncf_documento, 
                          a.ncfvence          as ncfvende_documento,
                          (0)                 as ritbis,
                          (0)                 as risr,
                          ("")                as nombre_cliente,
                          ("")                as rnc_cliente ,
                          ("")                as Contacto_cliente,
                          0                   as tiponcf_cliente, 			
                          ("")                as dir_cliente,
                          ("")                as telefono1_cliente,
                          ("")                as telefono2_cliente,
                          ("")                as telefono3_cliente, 
                          ("")                as correo_cliente,
                          ("")                as nombre_vendedor ,
                          a.importe 
                     from Reggasto a 
                     Where a.Numero = <<liFactura>> And 
                           a.Empresa = <<mEmpresa>>
                     order by a.Numero
               ENDTEXT 
               _cliptext = strQuery
          CASE liIdQuery = 2										&& Detalle
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT (0)                      as idProducto_det,
                         (00000000000.0000)       as porcItbis_det,
                         (00000000000.0000)       as itbis ,
                         NVL(b.cuenta, SPACE(40)) as Nombre_Producto_det,
                         (.f.)                    as servicio_det,
                         (1)                      as cantidad_det ,
                         a.monto                  as precio_det,
                         (0)                      as descuento_det
                     from detgasto a 
                          left join cuenta b on ALLTRIM(a.cuenta) == ALLTRIM(b.cuenta) And b.Empresa = <<mEmpresa>>
                     Where a.Numero = <<liFactura>> And 
                           a.Empresa = <<mEmpresa>>
                     order by a.Numero
               ENDTEXT 
               _cliptext = strQuery
       ENDCASE 
       RETURN strQuery 
     ENDPROC 
 
 ENDDEFINE 


*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------

*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_CompraMercancia as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"

    *--------------------------------------------
     PROCEDURE pGetDocumento 
       * Iniciar Variables 
         LPARAMETERS liFactura as Integer, destiny_curEncabezado as String, destiny_curDetalle as String, destiny_curMedioPago as String  
         LOCAL lbReturn as Boolean, curEncabezado as String, curDetalle as String 
         lbReturn = .f. 
         WITH this.parent
             .pLimpiarDatos()
              curEncabezado = .pGetCursorName()
              curDetalle    = .pGetCursorName()
         ENDWITH 
         
       * Procesar 
         IF this.pIsNumeric(liFactura) AND liFactura > 0 THEN 
          * Cargar Datos
            IF this.pSqlExec("compras,suplidor",this.pGetQuery(1,liFactura),curEncabezado) AND this.parent.pSetHeader(curEncabezado, destiny_curEncabezado) THEN 
               IF this.pSqlExec("detalle,producto",this.pGetQuery(2,liFactura),curDetalle) AND this.parent.pSetDetail(curDetalle, destiny_curDetalle) THEN
                  WITH this.parent 
                       lbReturn = .pSetMedioDePago(.oMedio_de_Pago, .oImporte, destiny_curMedioPago )
                  ENDWITH 
               ENDIF 
            ENDIF 
            
          * Cerrar Cursores 
            WITH this 
                .pClosedbf(curEncabezado)
                .pClosedbf(curDetalle)
            ENDWITH 
         ELSE
            this.pShowError(404,"Error en Parametro","El Número de Venta de Credito es Invalido o Cero", .t.)
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 
 
     *--------------------------------------------
     PROCEDURE pGetQuery
       LPARAMETERS liIdQuery as Integer, liFactura as Integer 
       LOCAL strQuery as String 
       strQuery = ""
       DO CASE 
          CASE liIdQuery = 1										&& Encabezado
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT (0)                  as numero_cuadre,
                          a.factura           as numero_documento,
                          a.factura2          as ordenco_documento,
                          a.fecha2            as fecha_documento,
                          a.vence             as vence_documento,
                          a.codigo            as codigo_cliente,
                          a.fpago             as idMedio_pago, 
                         (0)                  as codigo_Vendedor,
                          a.ncf               as ncf_documento, 
                          a.ncfvence          as ncfvende_documento,
                          (0)                 as ritbis,
                          (0)                 as risr,
                          NVL(b.suplidor,"")  as nombre_cliente,
                          NVL(b.rnc,"")       as rnc_cliente ,
                          NVL(b.contacto1,"") as Contacto_cliente,
                          NVL(b.tiponcf,-1)   as tiponcf_cliente,
                          NVL(b.direccion,"") as dir_cliente,
                          NVL(b.telefono1,"") as telefono1_cliente,
                          NVL(b.telefono2,"") as telefono2_cliente,
                          NVL(b.fax,"")       as telefono3_cliente, 
                          NVL(b.email,"")     as correo_cliente,
                          "EMPRESA"           as nombre_vendedor
                     from compras a 
                          left join suplidor b on a.codigo = b.codigo And b.Empresa = <<mEmpresa>>
                     Where a.factura = <<liFactura>> And 
                           a.transa  = 2 And 
                           a.Empresa = <<mEmpresa>>
                     order by a.factura
               ENDTEXT 
               
               
          CASE liIdQuery = 2										&& Detalle
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT a.producto  as idProducto_det,
                         a.itbisporc as porcItbis_det,
                         NVL(b.nombre, SPACE(40)) as Nombre_Producto_det,
                         (.f.)       as servicio_det,
                         a.cantidad  as cantidad_det ,
                         a.unidad    as idUnidad_det,
                         precio      as precio_det,
                         desc1       as descuento_det
                     from detalle a 
                          left join producto b on a.producto = b.codigo And b.Empresa = <<mEmpresa>>
                     Where a.Factura = <<liFactura>> And 
                           a.Transa  = 2  And 
                           a.Empresa = <<mEmpresa>>
                     order by a.factura 
               ENDTEXT 
              
       ENDCASE 
       RETURN strQuery 
     ENDPROC 
 
 ENDDEFINE 




*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------

*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_CompraSercicio as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"

    *--------------------------------------------
     PROCEDURE pGetDocumento 
       * Iniciar Variables 
         LPARAMETERS liFactura as Integer, destiny_curEncabezado as String, destiny_curDetalle as String, destiny_curMedioPago as String  
         LOCAL lbReturn as Boolean, curEncabezado as String, curDetalle as String 
         lbReturn = .f. 
         WITH this.parent
             .pLimpiarDatos()
              curEncabezado = .pGetCursorName()
              curDetalle    = .pGetCursorName()
         ENDWITH 
         
       * Procesar 
         IF this.pIsNumeric(liFactura) AND liFactura > 0 THEN 
          * Cargar Datos
            IF this.pSqlExec("regserv,suplidor",this.pGetQuery(1,liFactura),curEncabezado) AND this.parent.pSetHeader(curEncabezado, destiny_curEncabezado) THEN 
               IF this.pSqlExec("detserv,cuenta",this.pGetQuery(2,liFactura),curDetalle) AND this.parent.pSetDetail(curDetalle, destiny_curDetalle) THEN
                  WITH this.parent 
                       lbReturn = .pSetMedioDePago(.oMedio_de_Pago, .oImporte, destiny_curMedioPago )
                  ENDWITH 
               ENDIF 
            ENDIF 
            
          * Cerrar Cursores 
            WITH this 
                .pClosedbf(curEncabezado)
                .pClosedbf(curDetalle)
            ENDWITH 
         ELSE
            this.pShowError(404,"Error en Parametro","El Número de Venta de Credito es Invalido o Cero", .t.)
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 
 
     *--------------------------------------------
     PROCEDURE pGetQuery
       LPARAMETERS liIdQuery as Integer, liFactura as Integer 
       LOCAL strQuery as String 
       strQuery = ""
       DO CASE 
          CASE liIdQuery = 1										&& Encabezado
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT (0)                  as numero_cuadre,
                          a.numero            as numero_documento,
                          a.cuenta            as ordenco_documento,
                          a.fecha             as fecha_documento,
                          a.vence             as vence_documento,
                          a.codigo            as codigo_cliente,
                          a.fpago             as idMedio_pago, 
                         (0)                  as codigo_Vendedor,
                          a.ncf               as ncf_documento, 
                          a.ncfvence          as ncfvende_documento,
                          a.ritbis            as ritbis,
                          a.risr              as risr,
                          NVL(b.suplidor,"")  as nombre_cliente,
                          NVL(b.rnc,"")       as rnc_cliente ,
                          NVL(b.contacto1,"") as Contacto_cliente,
                          NVL(b.tiponcf,-1)   as tiponcf_cliente,
                          NVL(b.direccion,"") as dir_cliente,
                          NVL(b.telefono1,"") as telefono1_cliente,
                          NVL(b.telefono2,"") as telefono2_cliente,
                          NVL(b.fax,"")       as telefono3_cliente, 
                          NVL(b.email,"")     as correo_cliente,
                          "EMPRESA"           as nombre_vendedor
                     from regserv a 
                          left join suplidor b on a.codigo = b.codigo And b.Empresa = <<mEmpresa>>
                     Where a.Numero  = <<liFactura>> And 
                           a.Empresa = <<mEmpresa>>
                     order by a.Numero
               ENDTEXT 
               
               
          CASE liIdQuery = 2										&& Detalle
              TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                 SELECT ALLTRIM(a.cuenta)       as idProducto_det,
                       (IIF(a.itbis>0,2,0))     as porcItbis_det,
                        NVL(b.descr, SPACE(40)) as Nombre_Producto_det,
                       (1)                      as cantidad_det ,
                       (.t.)                    as servicio_det,
                       (1)                      as idUnidad_det,
                        a.monto                 as precio_det,
                       (0)                      as descuento_det
                     from detserv a 
                          left join cuenta b on ALLTRIM(a.cuenta) == ALLTRIM(b.cuenta) And b.Empresa = <<mEmpresa>>
                     Where a.Numero  = <<liFactura>> And 
                           a.Empresa = <<mEmpresa>>
                     order by a.Numero
              ENDTEXT 
              
       ENDCASE 
       RETURN strQuery 
     ENDPROC 
 
 ENDDEFINE 




*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------

*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_VtaSercicio as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"

    *--------------------------------------------
     PROCEDURE pGetDocumento 
       * Iniciar Variables 
         LPARAMETERS liFactura as Integer, destiny_curEncabezado as String, destiny_curDetalle as String, destiny_curMedioPago as String  
         LOCAL lbReturn as Boolean, curEncabezado as String, curDetalle as String 
         lbReturn = .f. 
         WITH this.parent
             .pLimpiarDatos()
              curEncabezado = .pGetCursorName()
              curDetalle    = .pGetCursorName()
         ENDWITH 
         
       * Procesar 
         IF this.pIsNumeric(liFactura) AND liFactura > 0 THEN 
          * Cargar Datos
            IF this.pSqlExec("fact_enc,cliente",this.pGetQuery(1,liFactura),curEncabezado) AND this.parent.pSetHeader(curEncabezado, destiny_curEncabezado) THEN
               IF this.pSqlExec("fact_det,servicio",this.pGetQuery(2,liFactura),curDetalle) AND this.parent.pSetDetail(curDetalle, destiny_curDetalle) THEN
                  WITH this.parent 
                       lbReturn = .pSetMedioDePago(.oMedio_de_Pago, .oImporte, destiny_curMedioPago )
                  ENDWITH 
               ENDIF 
            ENDIF 
            
          * Cerrar Cursores 
            WITH this 
                .pClosedbf(curEncabezado)
                .pClosedbf(curDetalle)
            ENDWITH 
         ELSE
            this.pShowError(404,"Error en Parametro","El Número de Venta de Credito es Invalido o Cero", .t.)
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 

    *--------------------------------------------
     PROCEDURE pGetQuery
       LPARAMETERS liIdQuery as Integer, liFactura as Integer 
       LOCAL strQuery as String 
       strQuery = ""
       DO CASE 
          CASE liIdQuery = 1										&& Encabezado
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT (0)                  as numero_cuadre,
                          a.factura           as numero_documento,
                          a.ref               as ordenco_documento,
                          a.fecha             as fecha_documento,
                         (a.fecha + 3)        as vence_documento,
                          a.codigo            as codigo_cliente,
                         (4)                  as idMedio_pago, 
                         (1)                  as codigo_Vendedor,
                          a.ncf               as ncf_documento, 
                          a.ncfvence          as ncfvende_documento,
                          (0)                 as ritbis,
                          (0)                 as risr,
                          NVL(b.cliente,"")   as nombre_cliente,
                          NVL(b.rnc,"")       as rnc_cliente ,
                          NVL(b.contacto1,"") as Contacto_cliente,
                          NVL(b.tiponcf,-1)   as tiponcf_cliente,
                          NVL(b.direccion,"") as dir_cliente,
                          NVL(b.telefono1,"") as telefono1_cliente,
                          NVL(b.telefono2,"") as telefono2_cliente,
                          NVL(b.fax,"")       as telefono3_cliente, 
                          NVL(b.email,"")     as correo_cliente,
                          "EMPRESA"           as nombre_vendedor
                     from fact_enc a 
                          left join cliente  b on a.codigo = b.codigo And b.Empresa = <<mEmpresa>>
                     Where a.Factura = <<liFactura>> And 
                           a.Empresa = <<mEmpresa>>
                     order by a.factura 
               ENDTEXT 
               
          CASE liIdQuery = 2										&& Detalle
              TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                 SELECT a.codigo    as idProducto_det,
                        a.itbisporc as porcItbis_det,
                        NVL(b.descr, SPACE(40)) as Nombre_Producto_det,
                        a.cantidad  as cantidad_det ,
                        (.t.)       as servicio_det,
                       (1)          as idUnidad_det,
                        a.precio    as precio_det,
                        a.descu     as descuento_det
                     from fact_det a
                          left join servicio b on a.codigo = b.codigo And b.tipo = 75 And b.Empresa = <<mEmpresa>>
                     Where a.Factura = <<liFactura>> And 
                           a.Empresa = <<mEmpresa>>
                     order by a.factura 
              ENDTEXT 
       ENDCASE 
       RETURN strQuery 
     ENDPROC 

 ENDDEFINE 




*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------


*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_VtaCredito as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"


    *--------------------------------------------
     PROCEDURE pGetDocumento 
       * Iniciar Variables 
         LPARAMETERS liFactura as Integer, destiny_curEncabezado as String, destiny_curDetalle as String, destiny_curMedioPago as String  
         LOCAL lbReturn as Boolean, curEncabezado as String, curDetalle as String 
         lbReturn = .f. 
         WITH this.parent
             .pLimpiarDatos()
              curEncabezado = .pGetCursorName()
              curDetalle    = .pGetCursorName()
         ENDWITH 
         
       * Procesar 
         IF this.pIsNumeric(liFactura) AND liFactura > 0 THEN 
          * Cargar Datos
            IF this.pSqlExec("cxc,cliente,vendedor",this.pGetQuery(1,liFactura),curEncabezado) AND this.parent.pSetHeader(curEncabezado, destiny_curEncabezado) then
               IF this.pSqlExec("detalle,producto",this.pGetQuery(2,liFactura),curDetalle) AND this.parent.pSetDetail(curDetalle, destiny_curDetalle) THEN 
                  IF this.pTabla_tiene_registros(destiny_curDetalle) THEN 
                     WITH this.parent 
                          lbReturn = .pSetMedioDePago(.oMedio_de_Pago, .oImporte, destiny_curMedioPago )
                     ENDWITH 
                  ENDIF 
               ENDIF 
            ENDIF 
            
          * Cerrar Cursores 
            WITH this 
                .pClosedbf(curEncabezado)
                .pClosedbf(curDetalle)
            ENDWITH 
         ELSE
            this.pShowError(404,"Error en Parametro","El Número de Venta de Credito es Invalido o Cero", .t.)
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 

    *--------------------------------------------
     PROCEDURE pGetQuery
       LPARAMETERS liIdQuery as Integer, liFactura as Integer 
       LOCAL strQuery as String 
       strQuery = ""
       DO CASE 
          CASE liIdQuery = 1										&& Encabezado
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  select  a.cuadre            as numero_cuadre,
                          a.factura           as numero_documento,
                          a.ref               as ordenco_documento,
                          a.fecha             as fecha_documento,
                          a.vence             as vence_documento,
                          a.codigo            as codigo_cliente,
                          a.pago              as idMedio_pago, 
                          a.vendedor          as codigo_Vendedor,
                          a.ncf               as ncf_documento, 
                          a.ncfvence          as ncfvende_documento,
                          (0)                 as ritbis,
                          (0)                 as risr,
                          NVL(b.cliente,"")   as nombre_cliente,
                          NVL(b.rnc,"")       as rnc_cliente ,
                          NVL(b.contacto1,"") as Contacto_cliente,
                          NVL(b.tiponcf,-1)   as tiponcf_cliente,
                          NVL(b.direccion,"") as dir_cliente,
                          NVL(b.telefono1,"") as telefono1_cliente,
                          NVL(b.telefono2,"") as telefono2_cliente,
                          NVL(b.fax,"")       as telefono3_cliente, 
                          NVL(b.email,"")     as correo_cliente,
                          NVL(c.nombre,"")    as nombre_vendedor 
                     from cxc a 
                          left join cliente  b on a.codigo   = b.codigo And b.Empresa = <<mEmpresa>>
                          left join vendedor c on a.vendedor = c.codigo And c.Empresa = <<mEmpresa>>
                     Where a.Factura = <<liFactura>> And 
                           a.Transa  = 3  And 
                           a.Empresa = <<mEmpresa>>
                     order by a.factura 
               ENDTEXT 
               
          CASE liIdQuery = 2										&& Detalle
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT a.producto  as idProducto_det,
                         a.itbisporc as porcItbis_det,
                         NVL(b.nombre, SPACE(40)) as Nombre_Producto_det,
                         (.f.)       as servicio_det,
                         a.cantidad  as cantidad_det ,
                         a.unidad    as idUnidad_det,
                         precio      as precio_det,
                         desc1       as descuento_det
                     from detalle a 
                          left join producto b on a.producto = b.codigo And b.Empresa = <<mEmpresa>>
                     Where a.Factura = <<liFactura>> And 
                           a.Transa  = 3  And 
                           a.Empresa = <<mEmpresa>>
                     order by a.factura 
               ENDTEXT 

       ENDCASE 
       RETURN strQuery 
     ENDPROC 
 
 ENDDEFINE 


*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------


*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_VtaContado as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"


    *--------------------------------------------
     PROCEDURE pGetDocumento 
       * Iniciar Variables 
         LPARAMETERS liFactura as Integer, destiny_curEncabezado as String, destiny_curDetalle as String, destiny_curMedioPago as String  
         LOCAL lbReturn as Boolean, curEncabezado as String, curDetalle as String, curMedioPago as string 
         lbReturn = .f. 
         WITH this.parent
             .pLimpiarDatos()
             .oContado_documento = .t.
              curEncabezado = .pGetCursorName()
              curDetalle    = .pGetCursorName()
              curMedioPago  = .pGetCursorName()
         ENDWITH 
         
       * Procesar 
         IF this.pIsNumeric(liFactura) AND liFactura > 0 THEN 
          * Cargar Datos
            WAIT WINDOW "Cargardo Encabezado de Venta de Contado"+CHR(13)+"Espere..." NOWAIT 
            IF this.pSqlExec("ventas,vendedor,rnc",this.pGetQuery(1,liFactura),curEncabezado) AND this.parent.pSetHeader(curEncabezado, destiny_curEncabezado) then
               WAIT WINDOW "Cargardo Detalle de Venta de Contado"+CHR(13)+"Espere..." NOWAIT 
               IF this.pSqlExec("detalle,producto,itbis",this.pGetQuery(2,liFactura),curDetalle) AND this.parent.pSetDetail(curDetalle, destiny_curDetalle) THEN 
                  WAIT WINDOW "Cargardo Medido de Pago en Venta de Contado"+CHR(13)+"Espere..." NOWAIT 
                  IF this.pSqlExec("fpagoventa",this.pGetQuery(3,liFactura),curMedioPago)  then
                   * Cargar el Medio de Pago
                     WITH this.parent 
*                          lbReturn = .pSetMedioDePago(.oMedio_de_Pago, .oImporte, destiny_curMedioPago )
                           lbReturn = .t. 
                          IF pTabla_tiene_registros(curMedioPago) THEN 
                             SCAN
                                IF .pSetMedioDePago(Tipo, Venta, destiny_curMedioPago ) then
                                    = pSelect(curMedioPago)
                                ELSE 
                                   lbReturn = .f. 
                                   EXIT 
                                ENDIF 
                             ENDSCAN 
                          ELSE
                             lbReturn = .pSetMedioDePago(.oMedio_de_Pago, .oImporte, destiny_curMedioPago )
                          ENDIF 
                     ENDWITH 
                  ENDIF 
               ENDIF 
            ENDIF 
            WAIT CLEAR 
          
          * Cerrar Cursores 
            WITH this 
                .pClosedbf(curEncabezado)
                .pClosedbf(curDetalle)
                .pClosedbf(curMedioPago)
            ENDWITH 
         ELSE
            this.pShowError(404,"Error en Parametro","El Número de Venta de Credito es Invalido o Cero", .t.)
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 

    *--------------------------------------------
     PROCEDURE pGetQuery
       LPARAMETERS liIdQuery as Integer, liFactura as Integer 
       LOCAL strQuery as String 
       strQuery = ""
       DO CASE 
          CASE liIdQuery = 1										&& Encabezado
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  select  a.cuadre            as numero_cuadre,
                          a.factura           as numero_documento,
                          ""                  as ordenco_documento,
                          a.fecha             as fecha_documento,
                          a.fecha             as vence_documento,
                          a.codigo            as codigo_cliente,
                          0                   as idMedio_pago, 					
                          (1)                 as codigo_Vendedor,
                          a.ncf               as ncf_documento, 
                          a.ncfvence          as ncfvende_documento,
                          (0)                 as ritbis,
                          (0)                 as risr,
                          a.nombre            as nombre_cliente,
                          a.rnc               as rnc_cliente ,
                          ("")                as Contacto_cliente,
                          0                   as tiponcf_cliente, 			
                          a.direccion         as dir_cliente,
                          ("")                as telefono1_cliente,
                          ("")                as telefono2_cliente,
                          ("")                as telefono3_cliente, 
                          ("")                as correo_cliente,
                          ("EMPRESA")         as nombre_vendedor 
                     from ventas a 
                     Where a.Factura = <<liFactura>> And 
                           a.Transa  = 4  And 
                           a.Empresa = <<mEmpresa>>
                     order by a.factura 
               ENDTEXT 
          CASE liIdQuery = 2										&& Detalle
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT a.producto               as idProducto_det,
                         c.porciento              as porcItbis_det,
                         NVL(b.nombre, SPACE(40)) as Nombre_Producto_det,
                         (.f.)                    as servicio_det,
                         a.cantidad               as cantidad_det ,
                         a.precio                 as precio_det,
                         (0)                      as descuento_det
                     from detalle a 
                          left join producto b on a.producto = b.codigo And b.Empresa = <<mEmpresa>>
                          left join Itbis    c on a.codItbis = c.codigo 
                     Where a.Factura = <<liFactura>> And 
                           a.Transa  = 4  And 
                           a.Empresa = <<mEmpresa>>
                     order by a.factura 
               ENDTEXT 
          CASE liIdQuery = 3										&& Detalle
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT a.tipo  ,
                         a.codigo ,
                         a.cantidad,
                         a.importe ,
                         a.venta,
                         a.itbis
                     from fpagoventa a 
                     Where a.Factura = <<liFactura>> And 
                           a.Transa  = 4  And 
                           a.Empresa = <<mEmpresa>>
                     order by a.factura 
               ENDTEXT 
       ENDCASE 
       RETURN strQuery 
     ENDPROC 
 
 ENDDEFINE 



*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
 
*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_NotaDebito as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"

*!*	    *--------------------------------------------
*!*	     PROCEDURE pGetDocumento 
*!*	       * Iniciar Variables 
*!*	         LPARAMETERS liFactura as Integer, destiny_curEncabezado as String, destiny_curDetalle as String, destiny_curMedioPago as String  
*!*	         LOCAL lbReturn as Boolean, curEncabezado as String, curDetalle as String 
*!*	         lbReturn = .f. 
*!*	         WITH this.parent
*!*	             .pLimpiarDatos()
*!*	              curEncabezado = .pGetCursorName()
*!*	              curDetalle    = .pGetCursorName()
*!*	         ENDWITH 
*!*	         
*!*	       * Procesar 
*!*	         IF this.pIsNumeric(liFactura) AND liFactura > 0 THEN 
*!*	          * Cargar Datos
*!*	            IF this.pSqlExec("cxc,cliente",this.pGetQuery(1,liFactura),curEncabezado) AND this.parent.pSetHeader(curEncabezado, destiny_curEncabezado) then
*!*	               IF this.pTabla_tiene_registros(destiny_curDetalle) THEN 
*!*	                  BROWSE 
*!*	                  lbReturn = .f. 
*!*	               ENDIF 
*!*	            ENDIF 
*!*	            
*!*	          * Cerrar Cursores 
*!*	            WITH this 
*!*	                .pClosedbf(curEncabezado)
*!*	            ENDWITH 
*!*	         ELSE
*!*	            this.pShowError(404,"Error en Parametro","El Número de Venta de Credito es Invalido o Cero", .t.)
*!*	         ENDIF 

*!*	       * Finalizar 
*!*	         RETURN lbReturn 
*!*	     ENDPROC 

*!*	    *--------------------------------------------
*!*	     PROCEDURE pGetQuery
*!*	       LPARAMETERS liIdQuery as Integer, liFactura as Integer 
*!*	       LOCAL strQuery as String 
*!*	       strQuery = ""
*!*	       DO CASE 
*!*	          CASE liIdQuery = 1										&& Encabezado
*!*	               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
*!*	                  SELECT  (0)                 as numero_cuadre,
*!*	                          a.factura           as numero_documento,
*!*	                          a.concepto1         as ordenco_documento,
*!*	                          a.fecha             as fecha_documento,
*!*	                          a.fecha             as vence_documento,
*!*	                          a.codigo            as codigo_cliente,
*!*	                          (4)                 as idMedio_pago,  		
*!*	                          a.vendedor          as codigo_Vendedor,		
*!*	                          a.ncf               as ncf_documento, 
*!*	                          a.vence             as ncfvende_documento,
*!*	                          a.ncfa              as ncf_afectado, 
*!*	                          (0)                 as ritbis,
*!*	                          (0)                 as risr,
*!*	                          NVL(b.cliente,"")   as nombre_cliente,
*!*	                          NVL(b.rnc,"")       as rnc_cliente ,
*!*	                          NVL(b.contacto1,"") as Contacto_cliente,
*!*	                          NVL(b.tiponcf,-1)   as tiponcf_cliente,
*!*	                          NVL(b.direccion,"") as dir_cliente,
*!*	                          NVL(b.telefono1,"") as telefono1_cliente,
*!*	                          NVL(b.telefono2,"") as telefono2_cliente,
*!*	                          NVL(b.fax,"")       as telefono3_cliente, 
*!*	                          NVL(b.email,"")     as correo_cliente,
*!*	                          NVL(c.nombre,"")    as nombre_vendedor 
*!*	                     from ncr a 
*!*	                          left join cliente  b on a.codigo   = b.codigo And b.Empresa = <<mEmpresa>>
*!*	                          left join vendedor c on a.vendedor = c.codigo And c.Empresa = <<mEmpresa>>
*!*	                     Where a.Factura = <<liFactura>> And 
*!*	                           a.Transa  = 3  And 
*!*	                           a.Empresa = <<mEmpresa>>
*!*	                     order by a.factura 
*!*	               ENDTEXT 

*!*	          CASE liIdQuery = 2										&& Detalle
*!*	               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
*!*	                  SELECT a.factura2  as idProducto_det,
*!*	                         (0) as porcItbis_det,
*!*	                         NVL(b.nombre, SPACE(40)) as Nombre_Producto_det,
*!*	                         (.f.)       as servicio_det,
*!*	                         (1)         as cantidad_det ,
*!*	                         (1)         as idUnidad_det,
*!*	                         total       as precio_det,
*!*	                         (0)         as descuento_det
*!*	                     from cxc a 
*!*	                          left join producto b on a.producto = b.codigo And b.Empresa = <<mEmpresa>>
*!*	                     Where a.Factura = <<liFactura>> And 
*!*	                           a.Transa  = 107  And 
*!*	                           a.Empresa = <<mEmpresa>>
*!*	                     order by a.factura 
*!*	               ENDTEXT 

*!*	               
*!*	       ENDCASE 
*!*	       RETURN strQuery 
*!*	     ENDPROC 

 ENDDEFINE 




*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------

*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_NotaCredito as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"
     
     oImporte = 0
     
    *--------------------------------------------
     PROCEDURE pGetDocumento 
       * Iniciar Variables 
         LPARAMETERS liFactura as Integer, destiny_curEncabezado as String, destiny_curDetalle as String, destiny_curMedioPago as String  
         LOCAL lbReturn as Boolean, curEncabezado as String, curDetalle as String 
         lbReturn = .f. 
         WITH this.parent
             .pLimpiarDatos()
              curEncabezado = .pGetCursorName()
              curDetalle    = .pGetCursorName()
         ENDWITH 
         
       * Procesar 
         IF this.pIsNumeric(liFactura) AND liFactura > 0 THEN 
          * Cargar Datos
            IF this.pSqlExec("ncr,cliente,vendedor",this.pGetQuery(1,liFactura),curEncabezado) AND this.parent.pSetHeader(curEncabezado, destiny_curEncabezado) THEN 
               IF this.pGetDetalle(curEncabezado, curDetalle) THEN 
                  IF this.parent.pSetDetail(curDetalle, destiny_curDetalle) THEN 
                     lbReturn = .t.
                  ENDIF 
*!*	                  WITH this.parent 
*!*	                       lbReturn = .pSetMedioDePago(.oMedio_de_Pago, .oImporte, destiny_curMedioPago )
*!*	                  ENDWITH 
               ENDIF 
            ENDIF 
            
          * Cerrar Cursores 
            WITH this 
                .pClosedbf(curEncabezado)
                .pClosedbf(curDetalle)
            ENDWITH 
         ELSE
            this.pShowError(404,"Error en Parametro","El Número de Venta de Credito es Invalido o Cero", .t.)
         ENDIF 

       * Finalizar 
         RETURN lbReturn 
     ENDPROC 
     
    *-----------------------------------------------------------------------------------
     PROCEDURE pGetDetalle
       * Iniciar variables 
         LPARAMETERS curEncabezado as string, curDetalle as String 
         LOCAL lbReturn as Boolean, lcConcepto as string, ;
               lyMonto00 as Currency, lyMonto18 as Currency, lyMonto16 as Currency 
         STORE 0 TO lyMonto00, lyMonto18, lyMonto16
         lbReturn  = .f. 
         
       * Crear Cursor 
         CREATE CURSOR &curDetalle (idProducto_det i, porcItbis_det y, Nombre_Producto_det c(40),;
                servicio_det l, cantidad_det y, idUnidad_det c(10), precio_det y, descuento_det y)
       
       * Iniciar variables 
         WITH this 
              IF .pTabla_tiene_registros(curEncabezado) THEN 
                * Calcular Totales 
                  IF itbis > 0 then
                     lyMonto18 = ROUND(itbis / .18,2)
                  ENDIF 
                  this.oImporte = Monto
                  lyMonto00 = Monto - ( lyMonto18 + lyMonto16)

                * Agregar Valor Gravado
                  IF lyMonto18 > 0 AND .pSelect(curEncabezado) THEN 
                     lcConcepto = ALLTRIM(concepto1) + "  CON 18% ITBIS"
                     INSERT INTO &curDetalle VALUES (1,18,lcConcepto,.f.,1,"1",lyMonto18,0)
                  ENDIF 

                * Agregar Valor Excento
                  IF lyMonto00 > 0 AND .pSelect(curEncabezado) then
                     lcConcepto = ALLTRIM(concepto1) + "  EXENTO"
                     INSERT INTO &curDetalle VALUES (1,0,lcConcepto,.f.,1,"1",lyMonto00,0)
                  ENDIF 
                 
                * Finalizar 
                 .pSelect(curDetalle)
                  lbReturn = .t. 
              ELSE
                 MESSAGEBOX("Imposible Cargar el Detalle del Documento")
              ENDIF 
         ENDWITH 
       
       * Finalizar
         RETURN lbReturn 
     ENDPROC 
 
    *--------------------------------------------
     PROCEDURE pGetQuery
       LPARAMETERS liIdQuery as Integer, liFactura as Integer 
       LOCAL strQuery as String 
       strQuery = ""
       DO CASE 
          CASE liIdQuery = 1										&& Encabezado
               TEXT TO strQuery TEXTMERGE NOSHOW PRETEXT 15
                  SELECT  (0)                 as numero_cuadre,
                          a.factura           as numero_documento,
                          a.concepto1         as ordenco_documento,
                          a.fecha             as fecha_documento,
                          a.fecha             as vence_documento,
                          a.codigo            as codigo_cliente,
                          (4)                 as idMedio_pago,  		
                          a.vendedor          as codigo_Vendedor,		
                          a.ncf               as ncf_documento, 
                          a.vence             as ncfvende_documento,
                          a.ncfa              as ncf_afectado, 
                          a.vence2            as ncfvende_afectado,
                          a.pago              as ncftipo_afectado,
                          a.monto             as monto ,
                          a.itbis             as itbis ,
                          a.total             as total ,
                          a.concepto1 ,
                          (0)                 as ritbis,
                          (0)                 as risr,
                          NVL(b.cliente,"")   as nombre_cliente,
                          NVL(b.rnc,"")       as rnc_cliente ,
                          NVL(b.contacto1,"") as Contacto_cliente,
                          NVL(b.tiponcf,-1)   as tiponcf_cliente,
                          NVL(b.direccion,"") as dir_cliente,
                          NVL(b.telefono1,"") as telefono1_cliente,
                          NVL(b.telefono2,"") as telefono2_cliente,
                          NVL(b.fax,"")       as telefono3_cliente, 
                          NVL(b.email,"")     as correo_cliente,
                          NVL(c.nombre,"")    as nombre_vendedor 
                     from ncr a 
                          left join cliente  b on a.codigo   = b.codigo And b.Empresa = <<mEmpresa>>
                          left join vendedor c on a.vendedor = c.codigo And c.Empresa = <<mEmpresa>>
                     Where a.Factura = <<liFactura>> And 
                           a.Transa  = 107  And 
                           a.Empresa = <<mEmpresa>>
                     order by a.factura 
               ENDTEXT 
               
       ENDCASE 
       RETURN strQuery 
     ENDPROC 

 ENDDEFINE 
 
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
*------------------------------------------------------------------------------------------------------------------------------------------------
 

*---------------------------------------------------------------------------------
 DEFINE CLASS cNcfE_Document_Source as cNcfe_BaseData OF ".\ncfe\cNcfe_BaseData.prg"

    * Datos: Docuento
      oNumero_Documento    = ""
      oFecha_Documento     = DATE()
      oPedido_Documento    = ""
      oContado_documento   = .f. 
      oVence_Documento     = DATE()
      oTermino_Documento   = "" 									&& Termino de Pago
      oFecha_Orden_Compra  = DATE()
      oNumero_Orden_Compra = ""
      oMedio_de_Pago       = 4

    * Datos: NCF 
      oTipo_Ncf       = ""
      oNumero_NCF     = ""
      oVence_Ncf      = DATE()
      oTipoB_Ncf      = ""

      oNumero_NCFa     = ""
      oVence_Ncfa     = DATE()
      oTipoB_Ncfa     = ""

      oMod_numero_Ncf = ""
      oMod_Fecha_Ncf  = DATE()
      oMod_Tipo_Ncf   = 0
      oMod_NotaCr     = 0
      
    * Datos: Cliente
      oCodigo_Cliente    = ""
      oRnc_Cliente       = ""
      oIdExt_cliente     = ""
      oNombre_Cliente    = ""
      oContacto_cliente  = ""
      oCorreo_Cliente    = ""
      oDir_Cliente       = ""
      oPais_cliente      = ""
      oTelefono1_Cliente = ""
      oTelefono2_Cliente = ""
      oTelefono3_Cliente = ""
      oTipoNcf_Cliente   = ""
      
    * Datos: Entrega
      oFecha_Entrega     = DATE()
      oContacto_Entrega  = ""
      oDir_Entrega       = ""
      oTel_Entrega       = ""
      oResposable_pago   = ""
      
    * Datos: Vendedor
      oCodigo_Vendedor   = ""
      oNombre_Vendedor   = ""
      
    * Datos: Totales 
      oMonto1  = 0.00
      oMonto2  = 0.00
      oMonto3  = 0.00								&& Sin Uso
      oMonto4  = 0.00								&& Sin Uso
      oExento  = 0.00

      oItbis1  = 0 
      oItbis2  = 0
      oItbis3  = 0
      
      oSubTotal = 0.00
      oDescu    = 0.00
      oCargo    = 0.00
      oMonto    = 0.00
      oItbis    = 0.00
      oImporte  = 0.00

    * Datos: Tasa de Itbis
      oITasa1   = 18
      oITasa2   = 16
      oITasa3   = 0
      
    * Datos: Retenciones 
      oItbis_retenido = 0.00
      oIsr_retenido   = 0.00
      
    * Cursores
      curEncabezado = ""
      curMedioPago  = ""
      curDetalle    = ""
      curTipoPago   = ""

    *--------------------------------------------
     PROCEDURE pSetTotales 
        LPARAMETERS curData as String 
        LOCAL lbReturn as boolean, msgError as String 
        msgError = ""
        lbReturn = .f. 
        WITH this 
             IF this.pTabla_tiene_registros(curData) THEN 
                TRY 
                    replace monto_exento           WITH .oExento ,;
                            monto_gravado1         WITH .oMonto1 ,;
                            monto_gravado2         WITH .oMonto2 ,;
                            monto_gravado3         WITH .oMonto3 ,;
                            descuento_global_valor WITH .oDescu  ,;
			                itasa1                 WITH .oITasa1 ,;
			                itasa2                 WITH .oITasa2 ,;
			                itasa3                 WITH .oITasa3 ,;
			                itbis1                 WITH .oItbis1 ,;
			                itbis2                 WITH .oItbis2 ,;
			                itbis3                 WITH .oItbis3 ,;
                            total_factura          WITH .oImporte ,;
                            itbis_retenido_total   WITH .oItbis_retenido ,;
                            isr_retenido_total     with .oIsr_retenido
                            
                    lbReturn = .t. 
                CATCH
                    AERROR(laError)
                    msgError = laError(2)
                ENDTRY 
            ENDIF 
        ENDWITH 
      
      * Mostar Error 
        IF !EMPTY(msgError) then
        ENDIF 
      
      * Finalizar 
        RETURN lbReturn  
     ENDPROC 


    *--------------------------------------------
     PROCEDURE pCal_Proporcionalidad
       LPARAMETERS lyImporte as currency, lyDescuento as Currency, lyMonto as Currency 
       LOCAL lyResult as Currency 
       lyResult = 0
       IF lyImporte > 0 AND lyMonto > 0 THEN 
          IF lyDescuento > 0 THEN 
             lyResult = ( lyMonto / lyImporte ) * lyDescuento
          ELSE 
             lyResult = lyMonto
          ENDIF 
       ENDIF 
       RETURN lyResult  
     ENDPROC 

    *--------------------------------------------
     PROCEDURE pTotal_Itbis
       LOCAL lyResult as Currency 
       lyResult = 0
       WITH this 
           .oItbis1  = .pCalcular_Itbis(.oMonto1, .oITasa1)
           .oItbis2  = .pCalcular_Itbis(.oMonto2, .oITasa2)
           .oItbis3  = .pCalcular_Itbis(.oMonto3, .oITasa3)
            lyResult = .oItbis1 + .oItbis2 + .oItbis3
       ENDWITH 
       RETURN lyResult  
     ENDPROC 

    *--------------------------------------------
     PROCEDURE pCalcular_Itbis
       LPARAMETERS lyMonto as Currency, lyTasa as Currency 
       LOCAL lyResult as Currency 
       lyResult = 0
       IF lyMonto > 0 AND lyTasa > 0 then
          lyResult = ROUND( lyMonto * (lyTasa/100),4)
       ENDIF 
       RETURN lyResult  
     ENDPROC 
     
    *--------------------------------------------
     PROCEDURE pLimpiarDatos
       WITH this 
          * Datos: Docuento
           .oNumero_Documento    = ""
           .oFecha_Documento     = DATE()
           .oPedido_Documento    = ""
           .oContado_documento   = .f. 
           .oVence_Documento     = DATE()
           .oTermino_Documento   = "" 									&& Termino de Pago
           .oFecha_Orden_Compra  = DATE()
           .oNumero_Orden_Compra = ""
           .oMedio_de_Pago       = 4

          * Datos: NCF 
           .oTipo_Ncf       = ""
           .oNumero_NCF     = ""
           .oVence_Ncf      = DATE()
           .oTipoB_Ncf      = ""
           .oMod_numero_Ncf = ""
           .oMod_Fecha_Ncf  = DATE()
           .oMod_Tipo_Ncf   = 0
      
          * Datos: Cliente
           .oCodigo_Cliente    = ""
           .oRnc_Cliente       = ""
           .oIdExt_cliente     = ""
           .oNombre_Cliente    = ""
           .oContacto_cliente  = ""
           .oCorreo_Cliente    = ""
           .oDir_Cliente       = ""
           .oPais_cliente      = ""
           .oTelefono1_Cliente = ""
           .oTelefono2_Cliente = ""
           .oTelefono3_Cliente = ""
           .oTipoNcf_Cliente   = ""
      
          * Datos: Entrega
           .oFecha_Entrega     = DATE()
           .oContacto_Entrega  = ""
           .oDir_Entrega       = ""
           .oTel_Entrega       = ""
           .oResposable_pago   = ""
      
          * Datos: Vendedor
           .oCodigo_Vendedor   = ""
           .oNombre_Vendedor   = ""
      
          * Datos: Totales 
           .oMonto1  = 0.00
           .oMonto2  = 0.00
           .oMonto3  = 0.00
           .oExento  = 0.00
           
           .oItbis1  = 0 
           .oItbis2  = 0
           .oItbis3  = 0
      
           .oMonto   = 0.00
           .oDescu   = 0.00
           .oCargo   = 0.00
           .oItbis   = 0.00
           .oImporte = 0.00
      
          * Datos: Retenciones 
           .oItbis_retenido = 0.00
           .oIsr_retenido   = 0.00
      
       ENDWITH 

     ENDPROC  

    *--------------------------------------------
     PROCEDURE pSetEncabezado
      * Iniciar Variables 
        LPARAMETERS curData as String 
        LOCAL lbReturn as Boolean, errDetail as String  
        lbReturn = .f. 
        errDetail = ""
        
      * Procesar 
        IF this.pTabla_tiene_registros(curData) then
           TRY
              WITH this 
                   * Datos: Documento
                     replace cliente_codigo        WITH  ALLTRIM(.oCodigo_Cliente),;
		        	         factura               WITH  ALLTRIM(.oNumero_Documento) ,;
		        	         pedido                WITH  ALLTRIM(.oPedido_Documento) ,;
		        	         fecha                 WITH .oFecha_Documento ,;
		        	         venta_de_contado      WITH .oContado_documento ,;
		        	         fecha_vencimiento     WITH .oVence_Documento ,;
		        	         terminos_de_pago      WITH  ALLTRIM(.oTermino_Documento) ,;
		        	         orden_compra_fecha    WITH .oFecha_Orden_Compra ,;
		        	         orden_compra_numero   WITH  ALLTRIM(.oNumero_Orden_Compra)

                   * Datos: Cliente
                     replace cliente_codigo        WITH ALLTRIM(.oCodigo_Cliente) ,;
                             cliente_rnc           WITH ALLTRIM(.oRnc_Cliente) ,;
                             cliente_id_extranjero WITH ALLTRIM(.oIdExt_cliente) ,;
                             cliente_razon_social  with ALLTRIM(.oNombre_Cliente) ,;
                             cliente_contacto      WITH ALLTRIM(.oContacto_cliente) ,;
                             cliente_correo        WITH ALLTRIM(.oCorreo_Cliente) ,;
                             cliente_direccion     WITH ALLTRIM(.oDir_Cliente) ,;
                             cliente_pais          WITH ALLTRIM(.oPais_cliente)
                             
                   * Datos: NCF 
                     replace comprobante_tipo          WITH  ALLTRIM(SUBSTR(.oNumero_NCF,2,2)),;
		        	         comprobante_numero        WITH .oNumero_NCF,;
		        	         comprobante_fechavence    WITH .oVence_Ncf,;
		        	         comprobante_tipob_numero  WITH .oTipob_Ncf ,;
		        	         ncf_modificado_numero     WITH .oMod_numero_Ncf ,;
	        	             ncf_modificado_tipo_modificacion WITH .oMod_Tipo_Ncf

                  * Datos: Itbis Retenido
                    replace itbis_retenido_total WITH .oItbis_retenido,;
                            isr_retenido_total   WITH .oIsr_retenido
                   
                   * Datos: Vendedor
                     replace vendedor    WITH ALLTRIM(.oNombre_Vendedor)
        
                   * Datos: Entrega 
                     replace cliente_fecha_entrega     WITH .oFecha_Entrega,;
		        	         cliente_contacto_entrega  WITH .oContacto_Entrega,;  
		          	         cliente_direccion_entrega WITH .oDir_Entrega,;
		          	         cliente_telefono          WITH .oTel_Entrega,;
		            	     cliente_responsable_pago  WITH .oResposable_pago
                   
		        	      
                ENDWITH 
                lbReturn = .t.
           CATCH
                AERROR(laError)
                errDetail = ALLTRIM(laError(2))
           ENDTRY 
           
         * Datos: NCF Afectado
		   IF lbReturn then
		      TRY 
                 IF VAL(comprobante_tipo) = 33 OR VAL(comprobante_tipo) = 34 then
	        	    replace ncf_modificado_fecha      WITH this.oMod_Fecha_Ncf 
	        	 ENDIF 
	          CATCH
                AERROR(laError)
                errDetail = "NCFe Afectado -- "+ALLTRIM(laError(2))
                lbReturn = .f.
	          ENDTRY 
		   endif

           
*           EDIT && XXXXXX
        ELSE 
           errDetail = "Archivo de Cabecera del Documento No Esta Disponible"+CHR(13)+"Program: "+PROGRAM()
        ENDIF 
        
      * Mostar Error 
        IF !EMPTY(errDetail) then
            this.pShowError(400,"Error","Imposible Actualizar Encabezado de NCFe"+CHR(13)+"Detalle: "+ errDetail +CHR(13)+"Program: "+PROGRAM() , .t. )         
        ENDIF 
        
      * Finalizar 
        RETURN lbReturn 
     ENDPROC 
      
    *---------------------------------------------------------------
     PROCEDURE pGetDetalleMedioPago
       LPARAMETERS liIdMedioPago as Integer
       LOCAL lcDetalle as String 
       lbDetalle = ""
       IF this.pIsNumeric(liIdMedioPago) AND BETWEEN(liIdMedioPago,1,8) then
          DO CASE 
             CASE liIdMedioPago = 1
                  lbDetalle = "Efectivo"
             CASE liIdMedioPago = 2
                  lbDetalle = "Cheque/Transferencia/Deposito"
             CASE liIdMedioPago = 3
                  lbDetalle = "Tarjeta"
             CASE liIdMedioPago = 4
                  lbDetalle = "Venta a Credito"
             CASE liIdMedioPago = 5
                  lbDetalle = "Bonos o Certificados de regalo"
             CASE liIdMedioPago = 6
                  lbDetalle = "Permuta"
             CASE liIdMedioPago = 7
                  lbDetalle = "Nota de Credito"
             CASE liIdMedioPago = 8
                  lbDetalle = "Otras Formas de pago"
          OTHERWISE 
             this.pShowError(404,"Error","Medio de Pago no Existe", .t.)
          ENDCASE 
       ELSE 
          this.pShowError(404,"Error","Medio de Pago no Existe", .t.)
       ENDIF 
       
       RETURN lbDetalle
     ENDPROC 

			     
    *--------------------------------------------
     PROCEDURE Init
         WITH this 
             .curEncabezado = .pGetCursorName()
             .curMedioPago  = .pGetCursorName()
             .curDetalle    = .pGetCursorName()
          ENDWITH 
     ENDPROC 

    *--------------------------------------------
     PROCEDURE pCerrarCursores
         WITH this 
             .pCloseDbf(.curEncabezado)
             .pCloseDbf(.curMedioPago)
             .pCloseDbf(.curDetalle)
         ENDWITH 
     ENDPROC 

 ENDDEFINE 




