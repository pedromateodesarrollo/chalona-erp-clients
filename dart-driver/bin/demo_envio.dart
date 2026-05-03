// Demo end-to-end: login → enviaEcfDesde → consultaEstado contra el API
// ecf-service. Por default apunta a producción; para probar contra BD test
// arrancar server-ecf local y exportar `ECF_BASE_URL=http://localhost:3030`.
//
// Uso:
//   dart run bin/demo_envio.dart
//
// Variables de entorno opcionales:
//   ECF_BASE_URL    Default: https://ecf-service.vicortiz.com
//   ECF_USER        Default: VICTORORTIZ941@GMAIL.COM   (test creds)
//   ECF_PASS        Default: victor123                  (test creds)
//   ECF_RNC_EMISOR  Default: 131996035
//   ECF_PORTAL      Default: testecf

import 'dart:io';

import 'package:dart_driver_poc/ecf_client.dart';

String _env(String k, String def) {
  final v = Platform.environment[k]?.trim();
  return (v == null || v.isEmpty) ? def : v;
}

Future<void> main() async {
  final baseUrl = _env('ECF_BASE_URL', 'https://ecf-service.vicortiz.com');
  final usuario = _env('ECF_USER', 'VICTORORTIZ941@GMAIL.COM');
  final clave = _env('ECF_PASS', 'victor123');
  final rnc = _env('ECF_RNC_EMISOR', '131996035');
  final portal = _env('ECF_PORTAL', 'testecf');
  // Motor entorno: 'test' si baseUrl apunta a localhost; 'produccion' si no.
  final motorEntorno = baseUrl.contains('localhost') ? 'test' : 'produccion';

  print('=== demo_envio ===');
  print('  baseUrl       : $baseUrl');
  print('  motorEntorno  : $motorEntorno');
  print('  usuario       : $usuario');
  print('  RNC emisor    : $rnc');
  print('  portal DGII   : $portal');
  print('');

  final client = EcfClient(baseUrl: baseUrl, motorEntorno: motorEntorno);

  try {
    print('-- 1. Login');
    final login = await client.login(usuario, clave);
    print('   usuario.email  : ${login['usuario']?['email']}');
    print('   empresa.nombre : ${login['empresa']?['nombre']}');
    print('   motor cargado  : ${client.motorMeta}');
    print('');

    print('-- 2. Construir DocumentoEcf (factura crédito fiscal tipo 31)');
    final doc = DocumentoEcf(
      fiscal: '31',
      encf: 'E310000000099', // demo — el integrador asigna
      fecha: DateTime.now(),
      moneda: 'DOP',
      valor: 1000.00,
      itbis: 180.00,
      total: 1180.00,
      emisor: EmisorEcf(
        rnc: rnc,
        nombre: 'Empresa Demo SRL',
        direccion: 'Calle Principal #1, Santo Domingo',
      ),
      comprador: CompradorEcf(
        rnc: '01800451302', // cédula 11 dígitos (válida) o RNC 9 dígitos
        nombre: 'Cliente Demo SA',
      ),
      lineas: [
        LineaEcf(
          descripcion: 'Servicio de consultoría',
          cantidad: 1,
          precio: 1000.00,
          itbis: 180.00,
          itbisTasa: 18,
          esServicio: true,
        ),
      ],
    );
    print('   tipo=${doc.fiscal} encf=${doc.encf} total=${doc.total}');
    print('');

    print('-- 3. enviaEcfDesde');
    final enviado = await client.enviaEcfDesde(doc, portal: portal);
    print('   estado            : ${enviado.estado}');
    print('   estado_descripcion: ${enviado.estadoDescripcion}');
    print('   encf              : ${enviado.encf}');
    print('   codigoSeguridad   : ${enviado.codigoSeguridad}');
    print('   timbre            : ${enviado.timbre}');
    print('');

    if (enviado.encf != null) {
      print('-- 4. consultaEstado');
      final result = await client.consultaEstado([enviado.encf!]);
      for (final r in result) {
        print('   $r');
      }
    }
  } on EcfApiError catch (e) {
    stderr.writeln('ERROR: $e');
    exit(1);
  } finally {
    client.close();
  }
}
