// demo_envio.dart — demostración standalone del driver Dart ECF.
//
// Envía 10 comprobantes (tipos 31-32-33-34-41-43-44-45-46-47) al portal
// testecf usando EcfClient. eNCF generado por servidor (portal testecf).
// No requiere package:api ni acceso a BD.
//
// Uso:
//   cd ecf/clients/dart-driver
//   dart run bin/demo_envio.dart
//
// Emisor: Vicortiz Softwares srl (RNC 131086268).
// Portal: testecf (pruebas DGII — no afecta datos reales).

import 'dart:convert';
import 'dart:io';

import 'package:dart_driver_poc/ecf_client.dart';

// ---------------------------------------------------------------------------
// Configuración emisor (Vicortiz Softwares srl — empresa de prueba)
// ---------------------------------------------------------------------------
const _kRnc = '131086268';
const _kNombre = 'Vicortiz Softwares srl';
const _kDireccion = 'Santo Domingo, República Dominicana';
const _kEmail = 'victorortiz941@gmail.com';
const _kUsuario = 'test@r131086268.com';
const _kClave = '1234';
const _kPortal = 'testecf';
const _kBaseUrl = 'https://ecf-service.vicortiz.com';

// ---------------------------------------------------------------------------
// 10 comprobantes de certificación DGII (tipos 31-32-33-34-41-43-44-45-46-47)
// Fuente: documentos_certificacion_dgii — datos del emisor se sobreescriben
// en obtenerDocumentos().
// ---------------------------------------------------------------------------
const String _kJsonBase =
    r'[{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"31","eNCF":"E310000000003","FechaVencimientoSecuencia":"31-12-2025","IndicadorMontoGravado":"0","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoGravadoTotal":"260000.00","MontoGravadoI1":"260000.00","ITBIS1":"18","TotalITBIS":"46800.00","TotalITBIS1":"46800.00","MontoTotal":"306800.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"1","NombreItem":"Caja de Dona","IndicadorBienoServicio":"1","CantidadItem":"1.00","PrecioUnitarioItem":"260000.00","MontoItem":"260000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"32","eNCF":"E320000000003","IndicadorMontoGravado":"0","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","Municipio":"320301","Provincia":"320000","TablaTelefonoEmisor":["809-472-7676","809-491-1918"],"CorreoEmisor":"DOCUMENTOSELECTRONICOSDE0612345678969789+9000000000000000000000000000001@123.COM","WebSite":"www.facturaelectronica.com","CodigoVendedor":"AA0000000100000000010000000002000000000300000000050000000006","NumeroFacturaInterna":"123456789016","NumeroPedidoInterno":"123456789016","ZonaVenta":"NORTE","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoGravadoTotal":"260000.00","MontoGravadoI1":"260000.00","ITBIS1":"18","TotalITBIS":"46800.00","TotalITBIS1":"46800.00","MontoTotal":"306800.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"1","NombreItem":"Caja de Dona","IndicadorBienoServicio":"1","CantidadItem":"1.00","PrecioUnitarioItem":"260000.00","MontoItem":"260000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"33","eNCF":"E310000000003","FechaVencimientoSecuencia":"31-12-2025","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoExento":"1000.00","MontoTotal":"1000.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"4","NombreItem":"Caja de Dona","IndicadorBienoServicio":"1","CantidadItem":"1.00","PrecioUnitarioItem":"1000.00","MontoItem":"1000.00"}],"InformacionReferencia":{"NCFModificado":"E320000000002","FechaNCFModificado":"01-04-2020","CodigoModificacion":"3"}},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"34","eNCF":"E340000000003","FechaVencimientoSecuencia":"31-12-2025","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoExento":"1000.00","MontoTotal":"1000.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"4","NombreItem":"Caja de Dona","IndicadorBienoServicio":"1","CantidadItem":"1.00","PrecioUnitarioItem":"1000.00","MontoItem":"1000.00"}],"InformacionReferencia":{"NCFModificado":"E320000000002","FechaNCFModificado":"01-04-2020","CodigoModificacion":"3"}},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"41","eNCF":"E410000000001","FechaVencimientoSecuencia":"31-12-2025","IndicadorMontoGravado":"0","TipoPago":"1","TablaFormasPago":[{"FormaPago":"1","MontoPago":"9000.00"}]},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020","Municipio":"010101","Provincia":"010000","TablaTelefonoEmisor":["809-472-7676","809-491-1918"]},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 02","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000"},"Totales":{"MontoGravadoTotal":"10000.00","MontoGravadoI1":"10000.00","ITBIS1":"18","TotalITBIS":"1800.00","TotalITBIS1":"1800.00","MontoTotal":"11800.00","ValorPagar":"11800.00","TotalITBISRetenido":"1800.00","TotalISRRetencion":"1000.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"1","Retencion":{"IndicadorAgenteRetencionoPercepcion":"1","MontoITBISRetenido":"1800.00","MontoISRRetenido":"1000.00"},"NombreItem":"SERVICIO PUBLICIDAD","IndicadorBienoServicio":"2","DescripcionItem":"LOREM IPSUM DOLOR SITI AMET, CONSECTETUR ADIPISCI IT. VESTIBULUM 1234 FERMENTUM E-X, CONSEQUAT (IACULIS) ARCU. PELLENTESQUE RUTRUM DUI EGET SAPIEN DICTUM, EU MOLLIS LECTUS AUCTOR. NUNC ORNARE ERAT QUIS NISL IMPERDIET PORTA. NULLAM VEL PHARETRA LEO, PELLENTESQUE FERMENTUM LECTUS. VIVAMUS ORCI IPSUM, SCELERISQUE QUIS VEHICULA QUIS, TEMPUS VITAE PURUS. ALIQUAM SAGITTIS EROS VITAE ANTE FAUCIBUS AUCTOR. MAECENAS PELLENTESQUE VEL EST IN CONGUE. FUSCE ARCU LIGULA, HENDRERIT EU DOLOR A, FACILISIS GRAVIDA DOLOR. PELLENTESQUE SED ALIQUET DOLOR. MAURIS BIBENDUM VEHICULA DICTUM. ETIAM TEMPUS, ODIO NEC CONSECTETUR IACULIS, ODIO NIBH EGESTAS FELIS, SED VIVERRA MAGNA EX SUSCIPIT AUGUE. PELLENTESQUE VESTIBULUM, LACUS NON MATTIS MOLESTIE, NEQUE LEO FACILISIS URNA, AC SUSCIPIT ERAT NISI ET MAGNA. PRAESENT PLACERAT SED LEO A GRAVIDA. MORBI ID ELIT LACUS. CLASS APTENT TACITI SOCIOSQU AD LITORA TORQUENT PER CONUBIA NOSTRA, PER INCEPTOS HIMENAEOS, CONSECTETUR ADIPISCING ELIT. NUNC ORNARE ERAT QUIS NISL IMP.","CantidadItem":"1.00","UnidadMedida":"43","PrecioUnitarioItem":"10000.00","MontoItem":"10000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"43","eNCF":"E430000000001","FechaVencimientoSecuencia":"31-12-2025","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","Municipio":"010101","Provincia":"010000","TablaTelefonoEmisor":["809-472-7676","809-491-1918"],"CorreoEmisor":"DOCUMENTOSELECTRONICOSDE0612345678969789+9000000000000000000000000000001@123.COM","WebSite":"www.facturaelectronica.com","NumeroFacturaInterna":"123456789016","NumeroPedidoInterno":"123456789016","FechaEmision":"01-04-2020"},"Totales":{"MontoExento":"700.00","MontoTotal":"700.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"4","NombreItem":"Peajes viaje semana I","IndicadorBienoServicio":"2","CantidadItem":"7.00","UnidadMedida":"43","PrecioUnitarioItem":"100.00","MontoItem":"700.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"44","eNCF":"E440000000003","FechaVencimientoSecuencia":"31-12-2025","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"","IdentificadorExtranjero":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoExento":"260000.00","MontoTotal":"260000.00","ValorPagar":"260000.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"4","NombreItem":"Caja de Dona","IndicadorBienoServicio":"1","CantidadItem":"1.00","PrecioUnitarioItem":"260000.00","MontoItem":"260000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"45","eNCF":"E450000000003","FechaVencimientoSecuencia":"31-12-2025","IndicadorMontoGravado":"0","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoGravadoTotal":"30000.00","MontoGravadoI1":"30000.00","ITBIS1":"18","TotalITBIS":"5400.00","TotalITBIS1":"5400.00","MontoTotal":"35400.00","ValorPagar":"35400.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"1","NombreItem":"SERVICIO PUBLICIDAD","IndicadorBienoServicio":"2","DescripcionItem":"prestaci\u00f3n de servicios relacionados con la creaci\u00f3n, ejecuci\u00f3n y distribuci\u00f3n de campa\u00f1as publicitarias.","CantidadItem":"1.00","UnidadMedida":"43","PrecioUnitarioItem":"30000.00","MontoItem":"30000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"46","eNCF":"E460000000003","FechaVencimientoSecuencia":"31-12-2025","TipoIngresos":"01","TipoPago":"1"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"RNCComprador":"01800451302","RazonSocialComprador":"DOCUMENTOS ELECTRONICOS DE 03","ContactoComprador":"MARCOS LATIPLOL","CorreoComprador":"MARCOSLATIPLOL@KKKK.COM","DireccionComprador":"CALLE JACINTO DE LA CONCHA FELIZ ESQUINA 27 DE FEBRERO,FRENTE A DOMINO","MunicipioComprador":"010100","ProvinciaComprador":"010000","FechaEntrega":"10-10-2020","FechaOrdenCompra":"10-11-2018","NumeroOrdenCompra":"4500352238","CodigoInternoComprador":"10633440"},"Totales":{"MontoGravadoTotal":"1800000.00","MontoGravadoI3":"1800000.00","ITBIS3":"0","TotalITBIS":"0.00","TotalITBIS3":"0.00","MontoTotal":"1800000.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"3","NombreItem":"AGUACATE CRIOLLO","IndicadorBienoServicio":"1","CantidadItem":"100.00","UnidadMedida":"43","PrecioUnitarioItem":"18000.00","MontoItem":"1800000.00"}]},{"Encabezado":{"Version":"1.0","IdDoc":{"TipoeCF":"47","eNCF":"E470000000003","FechaVencimientoSecuencia":"31-12-2025"},"Emisor":{"RNCEmisor":"131996035","RazonSocialEmisor":"DOCUMENTOS ELECTRONICOS DE 02","NombreComercial":"DOCUMENTOS ELECTRONICOS DE 02","DireccionEmisor":"AVE. ISABEL AGUIAR NO. 269, ZONA INDUSTRIAL DE HERRERA","FechaEmision":"01-04-2020"},"Comprador":{"IdentificadorExtranjero":"533445888","RazonSocialComprador":"ALEJA FERMIN SANTOS"},"Totales":{"MontoExento":"180000.00","MontoTotal":"180000.00","TotalISRRetencion":"48600.00"}},"DetallesItems":[{"NumeroLinea":"1","IndicadorFacturacion":"4","Retencion":{"IndicadorAgenteRetencionoPercepcion":"1","MontoISRRetenido":"48600.00"},"NombreItem":"LICENCIA WYI","IndicadorBienoServicio":"2","CantidadItem":"1.00","UnidadMedida":"43","PrecioUnitarioItem":"180000.00","MontoItem":"180000.00"}]}]';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _fechaHoy() {
  final now = DateTime.now();
  final d = now.day.toString().padLeft(2, '0');
  final m = now.month.toString().padLeft(2, '0');
  return '$d-$m-${now.year}';
}

// Copia profunda de un Map/List via JSON.
dynamic _deepCopy(dynamic v) => jsonDecode(jsonEncode(v));

// ---------------------------------------------------------------------------
// obtenerDocumentos
// ---------------------------------------------------------------------------

/// Devuelve los 10 comprobantes con emisor Vicortiz listo para enviar.
/// El servidor genera el eNCF automáticamente (portal testecf).
/// Los tipos 33 y 34 tienen FechaNCFModificado = hoy; NCFModificado se
/// inyecta en runtime con el eNCF del tipo 32 aceptado en este mismo lote.
List<Map<String, dynamic>> obtenerDocumentos() {
  final raw = (jsonDecode(_kJsonBase) as List).cast<Map<String, dynamic>>();
  final docs = raw.map((d) => _deepCopy(d) as Map<String, dynamic>).toList();

  final fecha = _fechaHoy();

  for (final doc in docs) {
    final enc = doc['Encabezado'] as Map<String, dynamic>;
    final idDoc = enc['IdDoc'] as Map<String, dynamic>;
    final emisor = enc['Emisor'] as Map<String, dynamic>;

    // Vaciar eNCF — el servidor lo genera para testecf.
    idDoc['eNCF'] = '';

    emisor['RNCEmisor'] = _kRnc;
    emisor['RazonSocialEmisor'] = _kNombre;
    emisor['NombreComercial'] = _kNombre;
    emisor['DireccionEmisor'] = _kDireccion;
    emisor['CorreoEmisor'] = _kEmail;
    emisor['FechaEmision'] = fecha;

    // Tipos 33/34: actualizar FechaNCFModificado a hoy para que los días
    // sean 0 (≤30) → IndicadorNotaCredito correcto = 0 (default).
    // NCFModificado se reemplaza en main() con el eNCF del tipo 32.
    final ref = doc['InformacionReferencia'] as Map<String, dynamic>?;
    if (ref != null) {
      ref['FechaNCFModificado'] = fecha;
    }
  }

  return docs;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final docs = obtenerDocumentos();

  print('=== demo_certificacion ===');
  print('  baseUrl  : $_kBaseUrl');
  print('  usuario  : $_kUsuario');
  print('  emisor   : $_kRnc / $_kNombre');
  print('  portal   : $_kPortal');
  print('  docs     : ${docs.length} comprobantes (eNCF generado por servidor)');
  print('');

  final client = EcfClient(baseUrl: _kBaseUrl);

  try {
    print('-- Login...');
    final login = await client.login(_kUsuario, _kClave);
    final empNombre = login['empresa']?['nombre'] ?? '';
    print('   OK — empresa: $empNombre');
    print('');
  } on EcfApiError catch (e) {
    stderr.writeln('Login falló: $e');
    client.close();
    exit(1);
  }

  var okCount = 0;
  var failCount = 0;
  final resumen = <String>[];
  // eNCF del tipo 32 aceptado — se usa como NCFModificado en tipos 33 y 34.
  String? encfTipo32;

  for (var i = 0; i < docs.length; i++) {
    final doc = docs[i];
    final enc = doc['Encabezado'] as Map<String, dynamic>;
    final idDoc = enc['IdDoc'] as Map<String, dynamic>;
    final tipo = idDoc['TipoeCF'] as String;

    // Inyectar NCFModificado real en ND (33) y NC (34).
    if ((tipo == '33' || tipo == '34') && encfTipo32 != null) {
      final ref = doc['InformacionReferencia'] as Map<String, dynamic>?;
      if (ref != null) ref['NCFModificado'] = encfTipo32;
    }

    final encf = idDoc['eNCF'] as String;
    print('[${i + 1}/${docs.length}] Tipo $tipo  eNCF: $encf');
    try {
      final r = await client.enviaEcf(rnc: _kRnc, portal: _kPortal, json: doc);
      final estado = r['estado']?.toString() ?? 'ok';
      final encfResult = r['numero']?.toString() ?? encf;
      print('  OK  - estado: $estado  eNCF: $encfResult');
      resumen.add('OK   Tipo $tipo  $encfResult  estado=$estado');
      okCount++;
      // Guardar eNCF de tipo 32 para referencias posteriores.
      if (tipo == '32') encfTipo32 = encfResult;
    } on EcfApiError catch (e) {
      print('  FAIL - ${e.code}');
      resumen.add('FAIL Tipo $tipo  ${e.code}');
      failCount++;
    }
  }

  client.close();

  print('');
  print('=========================================');
  print('  RESUMEN: $okCount ok / $failCount fail (de ${docs.length})');
  print('=========================================');
  for (final r in resumen) {
    print('  $r');
  }
  print('');

  exit(failCount > 0 ? 1 : 0);
}
