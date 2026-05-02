// Driver de prueba v1 — validación mínima de comprobante e-CF.
// Solo verifica:
//   - tipo de comprobante (31, 32, 33, 34)
//   - fecha emisión formato dd-MM-yyyy y año razonable
//
// Devuelve JSON: {"ok": bool, "errores": [...], "version": "v1"}

String preValidar(String comprobanteJson) {
  final tipo = _str(comprobanteJson, 'tipo');
  final fecha = _str(comprobanteJson, 'fecha_emision');

  final errores = <String>[];

  if (tipo == null || tipo.isEmpty) {
    errores.add('tipo requerido');
  } else if (tipo != '31' && tipo != '32' && tipo != '33' && tipo != '34') {
    errores.add('tipo inválido: $tipo (debe ser 31, 32, 33 o 34)');
  }

  if (fecha == null || fecha.isEmpty) {
    errores.add('fecha_emision requerida');
  } else if (!_fechaValida(fecha)) {
    errores.add('fecha_emision inválida: "$fecha" (esperado dd-MM-yyyy)');
  }

  return _resultJson(errores.isEmpty, errores, 'v1');
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

String? _str(String json, String key) {
  final pat = '"$key":"';
  final i = json.indexOf(pat);
  if (i < 0) return null;
  final j = i + pat.length;
  final k = json.indexOf('"', j);
  if (k < 0) return null;
  return json.substring(j, k);
}

String _resultJson(bool ok, List<String> errores, String version) {
  // Sin map/join (dart_eval limited support); construcción manual.
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
