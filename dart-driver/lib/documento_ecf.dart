// Modelo de comprobante e-CF (`DocumentoEcf`) — espejo de la estructura de
// cursores Fox (`curChalMae`, `curChalDet`, `curChalEmp`, `curChalCli`,
// `curChalRef`, `curChalSup`).
//
// El programador llena un `DocumentoEcf` con datos *de su ERP* y lo pasa al
// cliente shell. El motor (bytecode bajado) lo recibe serializado, valida,
// arma el payload DGII y lo envía. Tras la respuesta, el motor llena los
// campos de resultado (estado, codigoSeguridad, timbre, etc.) y el cliente
// devuelve el `DocumentoEcf` enriquecido.
//
// Ejemplo:
//
//   final doc = DocumentoEcf(
//     fiscal: '31',
//     fecha: DateTime(2026, 4, 15),
//     valor: 1000, itbis: 180, total: 1180, moneda: 'DOP',
//     emisor: EmisorEcf(rnc: '131996035', nombre: 'Mi SRL', direccion: 'Calle 1'),
//     comprador: CompradorEcf(rnc: '101000001', nombre: 'Cliente SA'),
//     lineas: [
//       LineaEcf(descripcion: 'Servicio X', cantidad: 1, precio: 1000,
//                itbis: 180, itbisTasa: 18, esServicio: true),
//     ],
//   );
//   final enviado = await client.enviaEcfDesde(doc, portal: 'testecf');
//   print(enviado.estado);  // 'Aceptado'
//   print(enviado.timbre);

/// Documento e-CF (encabezado + colecciones).
class DocumentoEcf {
  // ---- Identificación ----
  /// Tipo de comprobante DGII: `'31'` Fact. Crédito Fiscal, `'32'` Consumo,
  /// `'33'` Nota Débito, `'34'` Nota Crédito, `'41'` Compras, `'43'` Gastos
  /// Menores, `'44'` Régimen Especial, `'45'` Gubernamental, `'46'` Exportación,
  /// `'47'` Pagos al Exterior.
  String fiscal;

  /// e-NCF (lo asigna el motor/server al enviar). Null hasta envío exitoso.
  String? encf;

  /// NCF (legacy, vacío en flujos puramente electrónicos).
  String? ncf;

  /// ID interno de control del integrador (referencia local).
  String? control;

  /// Fecha de emisión.
  DateTime fecha;

  // ---- Montos (en moneda del documento) ----
  double valor;       // subtotal
  double descuento;
  double itbis;
  double total;
  double tasa;        // tasa cambio si moneda != 'DOP'
  String moneda;      // 'DOP', 'USD', 'EUR', ...

  // ---- Retenciones ----
  double itbisRetenido;
  double isrRetenido;

  // ---- Para Notas Crédito/Débito (33, 34) ----
  /// Código modificación DGII (1..5). Solo aplica a NC/ND.
  int? dgiiCodMod;

  /// Fecha vencimiento del e-NCF original (NC/ND).
  DateTime? fechaVencEcf;

  /// Días calendario entre referencia y emisión (informativo).
  int? diasReferencia;

  /// Comentario / justificación.
  String? comentario;

  // ---- Resultado del envío (lo llena el motor) ----
  String? estado;             // 'Aceptado', 'En Proceso', 'Rechazado', ...
  String? estadoDescripcion;
  String? codigoSeguridad;
  String? fechaFirma;
  String? timbre;             // URL timbre fiscal
  bool? secuenciaUtilizada;
  String? momento;
  String? respuestaMensajes;

  // ---- Relacionados ----
  EmisorEcf emisor;
  CompradorEcf? comprador;
  SuplidorEcf? suplidor;       // tipos 41/43/44/47
  List<LineaEcf> lineas;
  List<ReferenciaEcf> referencias;
  DateTime? fechaVenceFiscal;  // curChalFis.vence

  DocumentoEcf({
    required this.fiscal,
    required this.fecha,
    required this.emisor,
    this.encf,
    this.ncf,
    this.control,
    this.valor = 0,
    this.descuento = 0,
    this.itbis = 0,
    this.total = 0,
    this.tasa = 1,
    this.moneda = 'DOP',
    this.itbisRetenido = 0,
    this.isrRetenido = 0,
    this.dgiiCodMod,
    this.fechaVencEcf,
    this.diasReferencia,
    this.comentario,
    this.estado,
    this.estadoDescripcion,
    this.codigoSeguridad,
    this.fechaFirma,
    this.timbre,
    this.secuenciaUtilizada,
    this.momento,
    this.respuestaMensajes,
    this.comprador,
    this.suplidor,
    this.fechaVenceFiscal,
    List<LineaEcf>? lineas,
    List<ReferenciaEcf>? referencias,
  })  : lineas = lineas ?? <LineaEcf>[],
        referencias = referencias ?? <ReferenciaEcf>[];

  /// Serializa a `Map<String, dynamic>` con misma forma que cursores Fox.
  /// Fechas en formato `dd-MM-yyyy` (estándar DGII).
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      // curChalMae
      'fiscal': fiscal,
      if (encf != null) 'encf': encf,
      if (ncf != null) 'ncf': ncf,
      if (control != null) 'control': control,
      'fecha': _fmtDate(fecha),
      'valor': valor,
      'descuento': descuento,
      'itbis': itbis,
      'total': total,
      'tasa': tasa,
      'moneda': moneda,
      'itbisr': itbisRetenido,
      'isr': isrRetenido,
      if (dgiiCodMod != null) 'dgii_codmod': dgiiCodMod,
      if (fechaVencEcf != null) 'fechavencencf': _fmtDate(fechaVencEcf!),
      if (diasReferencia != null) 'diascr': diasReferencia,
      if (comentario != null) 'comentario': comentario,
      // Resultado (vacío al construir, lleno al recibir respuesta)
      if (estado != null) 'estado': estado,
      if (estadoDescripcion != null) 'estado_descripcion': estadoDescripcion,
      if (codigoSeguridad != null) 'codigo_seguridad': codigoSeguridad,
      if (fechaFirma != null) 'fecha_firma': fechaFirma,
      if (timbre != null) 'timbre': timbre,
      if (secuenciaUtilizada != null)
        'secuencia_utilizada': secuenciaUtilizada! ? 1 : 0,
      if (momento != null) 'momento': momento,
      if (respuestaMensajes != null) 'respuesta_mensajes': respuestaMensajes,
      // Relacionados
      'emisor': emisor.toMap(),
      if (comprador != null) 'comprador': comprador!.toMap(),
      if (suplidor != null) 'suplidor': suplidor!.toMap(),
      'lineas': lineas.map((l) => l.toMap()).toList(),
      if (referencias.isNotEmpty)
        'referencias': referencias.map((r) => r.toMap()).toList(),
      if (fechaVenceFiscal != null) 'vence_fiscal': _fmtDate(fechaVenceFiscal!),
    };
  }

  /// Reconstruye desde `Map` (p.ej. respuesta del motor con campos de resultado).
  factory DocumentoEcf.fromMap(Map<String, dynamic> m) {
    final emisor = EmisorEcf.fromMap(
      (m['emisor'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    return DocumentoEcf(
      fiscal: (m['fiscal'] as String?) ?? '',
      fecha: _parseDate(m['fecha']) ?? DateTime.now(),
      emisor: emisor,
      encf: m['encf'] as String?,
      ncf: m['ncf'] as String?,
      control: m['control'] as String?,
      valor: _num(m['valor']),
      descuento: _num(m['descuento']),
      itbis: _num(m['itbis']),
      total: _num(m['total']),
      tasa: _num(m['tasa'], 1),
      moneda: (m['moneda'] as String?) ?? 'DOP',
      itbisRetenido: _num(m['itbisr']),
      isrRetenido: _num(m['isr']),
      dgiiCodMod: (m['dgii_codmod'] as num?)?.toInt(),
      fechaVencEcf: _parseDate(m['fechavencencf']),
      diasReferencia: (m['diascr'] as num?)?.toInt(),
      comentario: m['comentario'] as String?,
      estado: m['estado'] as String?,
      estadoDescripcion: m['estado_descripcion'] as String?,
      codigoSeguridad: m['codigo_seguridad'] as String?,
      fechaFirma: m['fecha_firma'] as String?,
      timbre: m['timbre'] as String?,
      secuenciaUtilizada: _intToBool(m['secuencia_utilizada']),
      momento: m['momento'] as String?,
      respuestaMensajes: m['respuesta_mensajes'] as String?,
      comprador: m['comprador'] != null
          ? CompradorEcf.fromMap(
              (m['comprador'] as Map).cast<String, dynamic>(),
            )
          : null,
      suplidor: m['suplidor'] != null
          ? SuplidorEcf.fromMap(
              (m['suplidor'] as Map).cast<String, dynamic>(),
            )
          : null,
      lineas: (m['lineas'] as List?)
              ?.map((e) => LineaEcf.fromMap((e as Map).cast<String, dynamic>()))
              .toList() ??
          <LineaEcf>[],
      referencias: (m['referencias'] as List?)
              ?.map((e) =>
                  ReferenciaEcf.fromMap((e as Map).cast<String, dynamic>()))
              .toList() ??
          <ReferenciaEcf>[],
      fechaVenceFiscal: _parseDate(m['vence_fiscal']),
    );
  }
}

/// Emisor del comprobante (curChalEmp).
class EmisorEcf {
  String rnc;
  String nombre;
  String direccion;

  /// Indicador precio (Fox `iprecio`): 0=neto, 1=incluye ITBIS.
  int indicadorPrecio;

  EmisorEcf({
    required this.rnc,
    required this.nombre,
    required this.direccion,
    this.indicadorPrecio = 0,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'rnc': rnc,
        'nombre': nombre,
        'direccion': direccion,
        'iprecio': indicadorPrecio,
      };

  factory EmisorEcf.fromMap(Map<String, dynamic> m) => EmisorEcf(
        rnc: (m['rnc'] as String?) ?? '',
        nombre: (m['nombre'] as String?) ?? '',
        direccion: (m['direccion'] as String?) ?? '',
        indicadorPrecio: (m['iprecio'] as num?)?.toInt() ?? 0,
      );
}

/// Comprador (curChalCli).
class CompradorEcf {
  /// `true` si comprador es extranjero (sin RNC dominicano).
  bool extranjero;
  String? rnc;
  String nombre;

  CompradorEcf({
    required this.nombre,
    this.rnc,
    this.extranjero = false,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'extranjero_flag': extranjero ? 1 : 0,
        if (rnc != null) 'rnc': rnc,
        'nombre': nombre,
      };

  factory CompradorEcf.fromMap(Map<String, dynamic> m) => CompradorEcf(
        nombre: (m['nombre'] as String?) ?? '',
        rnc: m['rnc'] as String?,
        extranjero: ((m['extranjero_flag'] as num?)?.toInt() ?? 0) == 1,
      );
}

/// Suplidor (curChalSup) — tipos 41/43/44/47.
class SuplidorEcf {
  String rnc;
  String nombre;

  SuplidorEcf({required this.rnc, required this.nombre});

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'rnc': rnc, 'nombre': nombre};

  factory SuplidorEcf.fromMap(Map<String, dynamic> m) => SuplidorEcf(
        rnc: (m['rnc'] as String?) ?? '',
        nombre: (m['nombre'] as String?) ?? '',
      );
}

/// Línea de detalle (curChalDet).
class LineaEcf {
  double precio;
  double cantidad;
  String descripcion;

  /// Nombre catálogo de mercancía/servicio (opcional).
  String? mercsNombre;

  /// `true` si es servicio, `false` si es bien (curChalDet.mercs_servicio: 2|1).
  bool esServicio;

  double itbis;
  double itbisTasa;        // 18.00, 16.00, 0
  double itbisRetenido;
  double isrRetenido;

  LineaEcf({
    required this.descripcion,
    required this.cantidad,
    required this.precio,
    this.mercsNombre,
    this.esServicio = false,
    this.itbis = 0,
    this.itbisTasa = 18,
    this.itbisRetenido = 0,
    this.isrRetenido = 0,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'precio': precio,
        'cantidad': cantidad,
        'descrip': descripcion,
        if (mercsNombre != null) 'mercs_nombre': mercsNombre,
        'mercs_servicio': esServicio ? 2 : 1,
        'itbis': itbis,
        'itbis_tasa': itbisTasa,
        'itbis_retenido': itbisRetenido,
        'isr_retenido': isrRetenido,
      };

  factory LineaEcf.fromMap(Map<String, dynamic> m) => LineaEcf(
        descripcion: (m['descrip'] as String?) ?? '',
        cantidad: _num(m['cantidad']),
        precio: _num(m['precio']),
        mercsNombre: m['mercs_nombre'] as String?,
        esServicio: ((m['mercs_servicio'] as num?)?.toInt() ?? 1) == 2,
        itbis: _num(m['itbis']),
        itbisTasa: _num(m['itbis_tasa'], 18),
        itbisRetenido: _num(m['itbis_retenido']),
        isrRetenido: _num(m['isr_retenido']),
      );
}

/// Referencia a un e-NCF anterior (curChalRef) — usado en NC/ND.
class ReferenciaEcf {
  String encf;
  DateTime fecha;

  ReferenciaEcf({required this.encf, required this.fecha});

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'encf': encf, 'fecha': _fmtDate(fecha)};

  factory ReferenciaEcf.fromMap(Map<String, dynamic> m) => ReferenciaEcf(
        encf: (m['encf'] as String?) ?? '',
        fecha: _parseDate(m['fecha']) ?? DateTime.now(),
      );
}

// ---------------------------------------------------------------------------
// Helpers privados
// ---------------------------------------------------------------------------
String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.year}';

DateTime? _parseDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  // dd-MM-yyyy
  final p = s.split('-');
  if (p.length == 3) {
    final d = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final y = int.tryParse(p[2]);
    if (d != null && m != null && y != null) {
      // dd-MM-yyyy si y>1900 sino yyyy-MM-dd
      if (y > 1900) return DateTime(y, m, d);
      final y2 = int.tryParse(p[0]);
      final m2 = int.tryParse(p[1]);
      final d2 = int.tryParse(p[2]);
      if (y2 != null && m2 != null && d2 != null) return DateTime(y2, m2, d2);
    }
  }
  return DateTime.tryParse(s);
}

double _num(Object? v, [double def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? def;
}

bool? _intToBool(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v.toInt() != 0;
  return null;
}
