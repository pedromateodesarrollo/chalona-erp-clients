// Lógica REAL extraída de api/lib/src/ecf/tools/ecf.validator.dart
// (funciones puras, sin dependencia de EcfModel) — para validar viabilidad
// de compilar lógica e-CF representativa con dart_eval.

bool isFechaDdMmYyyy(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return false;
  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return false;
  if (m < 1 || m > 12) return false;
  if (d < 1 || d > 31) return false;
  if (y < 2020 || y > 2100) return false; // v3 demo: bug fix endurece año mínimo
  return true;
}

int? diasCalendarioEntreReferenciaYEmisionNc(
  String fechaNcfModificado,
  String fechaEmisionNc,
) {
  if (!isFechaDdMmYyyy(fechaNcfModificado) ||
      !isFechaDdMmYyyy(fechaEmisionNc)) {
    return null;
  }
  final pr = fechaNcfModificado.split('-');
  final pe = fechaEmisionNc.split('-');
  final dRef = DateTime(
    int.parse(pr[2]),
    int.parse(pr[1]),
    int.parse(pr[0]),
  );
  final dEmi = DateTime(
    int.parse(pe[2]),
    int.parse(pe[1]),
    int.parse(pe[0]),
  );
  return dEmi.difference(dRef).inDays;
}

bool fechaEsMayorOIgual(String fechaA, String fechaB) {
  final a = fechaA.split('-');
  final b = fechaB.split('-');
  if (a.length != 3 || b.length != 3) return false;
  final da = int.tryParse(a[0]);
  final ma = int.tryParse(a[1]);
  final ya = int.tryParse(a[2]);
  final db = int.tryParse(b[0]);
  final mb = int.tryParse(b[1]);
  final yb = int.tryParse(b[2]);
  if (da == null || ma == null || ya == null ||
      db == null || mb == null || yb == null) {
    return false;
  }
  if (ya != yb) return ya > yb;
  if (ma != mb) return ma > mb;
  return da >= db;
}

// Nota: dart_eval no implementa num.round() (sí ceil, abs, toInt). Workaround:
bool montoEsCeroEnCentavos(num v) {
  final c = v * 100;
  final entero = (c >= 0 ? c + 0.5 : c - 0.5).toInt();
  return entero == 0;
}

// Workaround dart_eval: usar `double` no `num` en parámetros — `num` no es
// primitivo en eval y requiere boxing manual. Con `double` funciona directo.
bool coincideConTolerancia(double sumaDetalle, double total, double tolerancia) {
  final diff = sumaDetalle - total;
  final abs = diff < 0 ? -diff : diff;
  return abs <= tolerancia;
}

// Tope de Nota de Crédito (tipo 34): no puede exceder total_factura + suma_ND
String validarTopeNotaCredito(
  num montoNc,
  num totalFactura,
  num sumaNotasDebito,
) {
  final tope = totalFactura + sumaNotasDebito;
  if (montoNc > tope) {
    return 'NC excede tope: $montoNc > $tope (factura=$totalFactura + ND=$sumaNotasDebito)';
  }
  return 'OK: NC $montoNc dentro de tope $tope';
}
