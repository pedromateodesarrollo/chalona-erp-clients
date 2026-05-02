// Driver v1 — fuente Dart que se compila a bytecode .evc
// Esta lógica vive en el servidor; cliente la baja al detectar versión nueva.

String procesar(String docJson) {
  return 'driver-v1 procesó: "$docJson" (longitud=${docJson.length})';
}

int sumar(int a, int b) => a + b;

String validarFactura(String facturaJson) {
  // Parser ad-hoc minimalista para evitar dart:convert si no está en eval
  final monto = _extraerNum(facturaJson, 'monto');
  final errores = <String>[];
  if (monto == null) errores.add('monto requerido');
  if (monto != null && monto < 0) errores.add('monto no puede ser negativo');
  final ok = errores.isEmpty;
  return '{"ok":$ok,"errores":${errores.toString()},"driver_version":"v1"}';
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
