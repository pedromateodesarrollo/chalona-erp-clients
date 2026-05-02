// Driver de prueba v2 — endurece validación.
// Suma a v1:
//   - RNC emisor (9 u 11 dígitos)
//   - RNC comprador (cuando aplica)
//   - monto_total > 0
//   - tipo 34 (NC): valida tope = total_factura + suma_nd
//   - tipo 32 manual RFCE: monto < 250000

String preValidar(String comprobanteJson) {
  final tipo = _str(comprobanteJson, 'tipo');
  final fecha = _str(comprobanteJson, 'fecha_emision');
  final rncEmi = _str(comprobanteJson, 'rnc_emisor');
  final rncCom = _str(comprobanteJson, 'rnc_comprador');
  final monto = _num(comprobanteJson, 'monto_total');
  final totalFactura = _num(comprobanteJson, 'total_factura_referenciada');
  final sumaNd = _num(comprobanteJson, 'suma_nd_referenciadas');

  final errores = <String>[];

  // tipo
  if (tipo == null || tipo.isEmpty) {
    errores.add('tipo requerido');
  } else if (tipo != '31' && tipo != '32' && tipo != '33' && tipo != '34') {
    errores.add('tipo inválido: $tipo (debe ser 31, 32, 33 o 34)');
  }

  // fecha
  if (fecha == null || fecha.isEmpty) {
    errores.add('fecha_emision requerida');
  } else if (!_fechaValida(fecha)) {
    errores.add('fecha_emision inválida: "$fecha" (esperado dd-MM-yyyy)');
  }

  // RNC emisor
  if (rncEmi == null || rncEmi.isEmpty) {
    errores.add('rnc_emisor requerido');
  } else if (!_rncValido(rncEmi)) {
    errores.add('rnc_emisor inválido: "$rncEmi" (9 u 11 dígitos)');
  }

  // monto
  if (monto == null) {
    errores.add('monto_total requerido');
  } else if (monto <= 0) {
    errores.add('monto_total debe ser > 0 (actual: $monto)');
  }

  // tipo 31: requiere RNC comprador
  if (tipo == '31') {
    if (rncCom == null || rncCom.isEmpty) {
      errores.add('rnc_comprador requerido para tipo 31 (Crédito Fiscal)');
    } else if (!_rncValido(rncCom)) {
      errores.add('rnc_comprador inválido: "$rncCom"');
    }
  }

  // tipo 32 manual RFCE: monto < 250000
  if (tipo == '32' && monto != null && monto >= 250000) {
    errores.add(
      'tipo 32 con monto >= 250000 requiere comprador identificado (manual RFCE)',
    );
  }

  // tipo 34 (NC): tope = total_factura + suma_nd
  if (tipo == '34' && monto != null) {
    final tf = totalFactura ?? 0;
    final sn = sumaNd ?? 0;
    final tope = tf + sn;
    if (monto > tope) {
      errores.add(
        'NC excede tope: monto $monto > tope $tope (factura=$tf + ND=$sn)',
      );
    }
  }

  return _resultJson(errores.isEmpty, errores, 'v2');
}

bool _fechaValida(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return false;
  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return false;
  if (m < 1 || m > 12) return false;
  if (d < 1 || d > 31) return false;
  if (y < 2020 || y > 2100) return false;
  return true;
}

bool _rncValido(String rnc) {
  if (rnc.length != 9 && rnc.length != 11) return false;
  for (var i = 0; i < rnc.length; i++) {
    final c = rnc.codeUnitAt(i);
    if (c < 48 || c > 57) return false; // no es dígito
  }
  return true;
}

String? _str(String json, String key) {
  final pat = '"$key":"';
  final i = json.indexOf(pat);
  if (i < 0) return null;
  final j = i + pat.length;
  final k = json.indexOf('"', j);
  if (k < 0) return null;
  return json.substring(j, k);
}

num? _num(String json, String key) {
  final pat = '"$key":';
  final i = json.indexOf(pat);
  if (i < 0) return null;
  var j = i + pat.length;
  while (j < json.length && json[j] == ' ') j++;
  var k = j;
  while (k < json.length && '0123456789.-'.contains(json[k])) k++;
  if (j == k) return null;
  return num.tryParse(json.substring(j, k));
}

String _resultJson(bool ok, List<String> errores, String version) {
  var esc = '';
  for (var i = 0; i < errores.length; i++) {
    if (i > 0) esc += ',';
    final e = errores[i];
    var safe = '';
    for (var k = 0; k < e.length; k++) {
      final ch = e[k];
      if (ch == '"') safe += r'\"';
      else if (ch == r'\') safe += r'\\';
      else safe += ch;
    }
    esc += '"$safe"';
  }
  return '{"ok":$ok,"errores":[$esc],"version":"$version"}';
}
