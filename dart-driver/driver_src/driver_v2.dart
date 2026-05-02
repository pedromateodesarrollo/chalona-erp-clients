// Driver v2 — bug fix: ahora valida que monto sea > 0 (no >= 0)
// y que tenga RNC del cliente. Cambia el formato del mensaje.

String procesar(String docJson) {
  return 'driver-v2 [MEJORADO] procesó "$docJson" (palabras=${docJson.split(' ').length})';
}

int sumar(int a, int b) => a + b + 1; // bug "fix" demo

String validarFactura(String facturaJson) {
  final monto = _extraerNum(facturaJson, 'monto');
  final rnc = _extraerStr(facturaJson, 'rnc');
  final errores = <String>[];
  if (monto == null) errores.add('monto requerido');
  if (monto != null && monto <= 0) errores.add('monto debe ser mayor a 0');
  if (rnc == null || rnc.isEmpty) errores.add('rnc requerido');
  final ok = errores.isEmpty;
  return '{"ok":$ok,"errores":${errores.toString()},"driver_version":"v2"}';
}

num? _extraerNum(String json, String key) {
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

String? _extraerStr(String json, String key) {
  final pat = '"$key":"';
  final i = json.indexOf(pat);
  if (i < 0) return null;
  final j = i + pat.length;
  final k = json.indexOf('"', j);
  if (k < 0) return null;
  return json.substring(j, k);
}
