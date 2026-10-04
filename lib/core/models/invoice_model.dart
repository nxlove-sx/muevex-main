import 'package:equatable/equatable.dart';

/// Estados de la factura (coincide con invoice_status_enum en BD).
enum InvoiceStatus {
  borrador,
  emitida,
  anulada,
}

extension InvoiceStatusX on InvoiceStatus {
  String get dbName {
    switch (this) {
      case InvoiceStatus.borrador:
        return 'borrador';
      case InvoiceStatus.emitida:
        return 'emitida';
      case InvoiceStatus.anulada:
        return 'anulada';
    }
  }

  static InvoiceStatus fromDbName(String dbName) {
    switch (dbName) {
      case 'borrador':
        return InvoiceStatus.borrador;
      case 'emitida':
        return InvoiceStatus.emitida;
      case 'anulada':
        return InvoiceStatus.anulada;
      default:
        return InvoiceStatus.borrador;
    }
  }

  String get label {
    switch (this) {
      case InvoiceStatus.borrador:
        return 'Borrador';
      case InvoiceStatus.emitida:
        return 'Emitida';
      case InvoiceStatus.anulada:
        return 'Anulada';
    }
  }
}

/// Modelo de factura (Invoice) para MUEVEX.
///
/// Cumple requisitos DIAN Colombia:
/// - Consecutivo único (numero_factura: "FEV-000001")
/// - Datos emisor (plataforma) y receptor (cliente)
/// - Desglose: subtotal, IVA 19%, retenciones, total
/// - PDF firmado en Storage (pdf_url)
class Invoice extends Equatable {
  final String id;
  final String numeroFactura;

  // Referencias
  final String serviceId;
  final String customerId;
  final String? driverId;

  // Fechas
  final DateTime fechaEmision;
  final DateTime? fechaVencimiento;

  // Emisor (plataforma)
  final String emisorNit;
  final String emisorNombre;
  final String emisorDireccion;
  final String emisorCiudad;
  final String? emisorTelefono;
  final String? emisorEmail;
  final String? emisorResolucionDian;
  final DateTime? emisorFechaResolucion;
  final String emisorPrefijo;
  final int emisorRangoInicial;
  final int emisorRangoFinal;

  // Receptor (cliente)
  final String? receptorNit;
  final String receptorNombre;
  final String? receptorDireccion;
  final String? receptorCiudad;
  final String? receptorTelefono;
  final String? receptorEmail;

  // Detalle del servicio (snapshot)
  final String servicioDescripcion;
  final String? servicioOrigen;
  final String? servicioDestino;
  final double? servicioDistanciaKm;
  final DateTime? servicioFecha;

  // Montos
  final double subtotal;
  final double ivaPorcentaje;
  final double ivaValor;
  final double retencionFuentePorcentaje;
  final double retencionFuenteValor;
  final double retencionIcaPorcentaje;
  final double retencionIcaValor;
  final double total;

  // Estado y control
  final InvoiceStatus status;
  final String? pdfUrl;
  final String? notas;

  // Auditoría
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? emittedAt;
  final DateTime? voidedAt;
  final String? voidedReason;

  // Items (se cargan aparte)
  final List<InvoiceItem> items;

  const Invoice({
    required this.id,
    required this.numeroFactura,
    required this.serviceId,
    required this.customerId,
    this.driverId,
    required this.fechaEmision,
    this.fechaVencimiento,
    required this.emisorNit,
    required this.emisorNombre,
    required this.emisorDireccion,
    required this.emisorCiudad,
    this.emisorTelefono,
    this.emisorEmail,
    this.emisorResolucionDian,
    this.emisorFechaResolucion,
    required this.emisorPrefijo,
    required this.emisorRangoInicial,
    required this.emisorRangoFinal,
    this.receptorNit,
    required this.receptorNombre,
    this.receptorDireccion,
    this.receptorCiudad,
    this.receptorTelefono,
    this.receptorEmail,
    required this.servicioDescripcion,
    this.servicioOrigen,
    this.servicioDestino,
    this.servicioDistanciaKm,
    this.servicioFecha,
    required this.subtotal,
    required this.ivaPorcentaje,
    required this.ivaValor,
    required this.retencionFuentePorcentaje,
    required this.retencionFuenteValor,
    required this.retencionIcaPorcentaje,
    required this.retencionIcaValor,
    required this.total,
    required this.status,
    this.pdfUrl,
    this.notas,
    required this.createdAt,
    required this.updatedAt,
    this.emittedAt,
    this.voidedAt,
    this.voidedReason,
    this.items = const [],
  });

  factory Invoice.fromMap(Map<String, dynamic> map) {
    final itemsRaw = map['items'] as List<dynamic>?;
    return Invoice(
      id: map['id'] as String,
      numeroFactura: map['numero_factura'] as String,
      serviceId: map['service_id'] as String,
      customerId: map['customer_id'] as String,
      driverId: map['driver_id'] as String?,
      fechaEmision: DateTime.parse(map['fecha_emision'] as String),
      fechaVencimiento: map['fecha_vencimiento'] != null
          ? DateTime.parse(map['fecha_vencimiento'] as String)
          : null,
      emisorNit: map['emisor_nit'] as String,
      emisorNombre: map['emisor_nombre'] as String,
      emisorDireccion: map['emisor_direccion'] as String,
      emisorCiudad: map['emisor_ciudad'] as String,
      emisorTelefono: map['emisor_telefono'] as String?,
      emisorEmail: map['emisor_email'] as String?,
      emisorResolucionDian: map['emisor_resolucion_dian'] as String?,
      emisorFechaResolucion: map['emisor_fecha_resolucion'] != null
          ? DateTime.parse(map['emisor_fecha_resolucion'] as String)
          : null,
      emisorPrefijo: map['emisor_prefijo'] as String,
      emisorRangoInicial: (map['emisor_rango_inicial'] as num).toInt(),
      emisorRangoFinal: (map['emisor_rango_final'] as num).toInt(),
      receptorNit: map['receptor_nit'] as String?,
      receptorNombre: map['receptor_nombre'] as String,
      receptorDireccion: map['receptor_direccion'] as String?,
      receptorCiudad: map['receptor_ciudad'] as String?,
      receptorTelefono: map['receptor_telefono'] as String?,
      receptorEmail: map['receptor_email'] as String?,
      servicioDescripcion: map['servicio_descripcion'] as String,
      servicioOrigen: map['servicio_origen'] as String?,
      servicioDestino: map['servicio_destino'] as String?,
      servicioDistanciaKm: (map['servicio_distancia_km'] as num?)?.toDouble(),
      servicioFecha: map['servicio_fecha'] != null
          ? DateTime.parse(map['servicio_fecha'] as String)
          : null,
      subtotal: (map['subtotal'] as num).toDouble(),
      ivaPorcentaje: (map['iva_porcentaje'] as num).toDouble(),
      ivaValor: (map['iva_valor'] as num).toDouble(),
      retencionFuentePorcentaje:
          (map['retencion_fuente_porcentaje'] as num?)?.toDouble() ?? 0,
      retencionFuenteValor:
          (map['retencion_fuente_valor'] as num?)?.toDouble() ?? 0,
      retencionIcaPorcentaje:
          (map['retencion_ica_porcentaje'] as num?)?.toDouble() ?? 0,
      retencionIcaValor: (map['retencion_ica_valor'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num).toDouble(),
      status: InvoiceStatusX.fromDbName(map['status'] as String),
      pdfUrl: map['pdf_url'] as String?,
      notas: map['notas'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      emittedAt: map['emitted_at'] != null
          ? DateTime.parse(map['emitted_at'] as String)
          : null,
      voidedAt: map['voided_at'] != null
          ? DateTime.parse(map['voided_at'] as String)
          : null,
      voidedReason: map['voided_reason'] as String?,
      items: itemsRaw != null
          ? itemsRaw
              .whereType<Map<String, dynamic>>()
              .map(InvoiceItem.fromMap)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'numero_factura': numeroFactura,
      'service_id': serviceId,
      'customer_id': customerId,
      if (driverId != null) 'driver_id': driverId,
      'fecha_emision': fechaEmision.toIso8601String(),
      if (fechaVencimiento != null)
        'fecha_vencimiento': fechaVencimiento!.toIso8601String(),
      'emisor_nit': emisorNit,
      'emisor_nombre': emisorNombre,
      'emisor_direccion': emisorDireccion,
      'emisor_ciudad': emisorCiudad,
      if (emisorTelefono != null) 'emisor_telefono': emisorTelefono,
      if (emisorEmail != null) 'emisor_email': emisorEmail,
      if (emisorResolucionDian != null)
        'emisor_resolucion_dian': emisorResolucionDian,
      if (emisorFechaResolucion != null)
        'emisor_fecha_resolucion':
            emisorFechaResolucion!.toIso8601String().split('T').first,
      'emisor_prefijo': emisorPrefijo,
      'emisor_rango_inicial': emisorRangoInicial,
      'emisor_rango_final': emisorRangoFinal,
      if (receptorNit != null) 'receptor_nit': receptorNit,
      'receptor_nombre': receptorNombre,
      if (receptorDireccion != null) 'receptor_direccion': receptorDireccion,
      if (receptorCiudad != null) 'receptor_ciudad': receptorCiudad,
      if (receptorTelefono != null) 'receptor_telefono': receptorTelefono,
      if (receptorEmail != null) 'receptor_email': receptorEmail,
      'servicio_descripcion': servicioDescripcion,
      if (servicioOrigen != null) 'servicio_origen': servicioOrigen,
      if (servicioDestino != null) 'servicio_destino': servicioDestino,
      if (servicioDistanciaKm != null)
        'servicio_distancia_km': servicioDistanciaKm,
      if (servicioFecha != null)
        'servicio_fecha': servicioFecha!.toIso8601String(),
      'subtotal': subtotal,
      'iva_porcentaje': ivaPorcentaje,
      'iva_valor': ivaValor,
      'retencion_fuente_porcentaje': retencionFuentePorcentaje,
      'retencion_fuente_valor': retencionFuenteValor,
      'retencion_ica_porcentaje': retencionIcaPorcentaje,
      'retencion_ica_valor': retencionIcaValor,
      'total': total,
      'status': status.dbName,
      if (pdfUrl != null) 'pdf_url': pdfUrl,
      if (notas != null) 'notas': notas,
    };
  }

  Invoice copyWith({
    String? id,
    String? numeroFactura,
    String? serviceId,
    String? customerId,
    String? driverId,
    DateTime? fechaEmision,
    DateTime? fechaVencimiento,
    String? emisorNit,
    String? emisorNombre,
    String? emisorDireccion,
    String? emisorCiudad,
    String? emisorTelefono,
    String? emisorEmail,
    String? emisorResolucionDian,
    DateTime? emisorFechaResolucion,
    String? emisorPrefijo,
    int? emisorRangoInicial,
    int? emisorRangoFinal,
    String? receptorNit,
    String? receptorNombre,
    String? receptorDireccion,
    String? receptorCiudad,
    String? receptorTelefono,
    String? receptorEmail,
    String? servicioDescripcion,
    String? servicioOrigen,
    String? servicioDestino,
    double? servicioDistanciaKm,
    DateTime? servicioFecha,
    double? subtotal,
    double? ivaPorcentaje,
    double? ivaValor,
    double? retencionFuentePorcentaje,
    double? retencionFuenteValor,
    double? retencionIcaPorcentaje,
    double? retencionIcaValor,
    double? total,
    InvoiceStatus? status,
    String? pdfUrl,
    String? notas,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? emittedAt,
    DateTime? voidedAt,
    String? voidedReason,
    List<InvoiceItem>? items,
  }) {
    return Invoice(
      id: id ?? this.id,
      numeroFactura: numeroFactura ?? this.numeroFactura,
      serviceId: serviceId ?? this.serviceId,
      customerId: customerId ?? this.customerId,
      driverId: driverId ?? this.driverId,
      fechaEmision: fechaEmision ?? this.fechaEmision,
      fechaVencimiento: fechaVencimiento ?? this.fechaVencimiento,
      emisorNit: emisorNit ?? this.emisorNit,
      emisorNombre: emisorNombre ?? this.emisorNombre,
      emisorDireccion: emisorDireccion ?? this.emisorDireccion,
      emisorCiudad: emisorCiudad ?? this.emisorCiudad,
      emisorTelefono: emisorTelefono ?? this.emisorTelefono,
      emisorEmail: emisorEmail ?? this.emisorEmail,
      emisorResolucionDian: emisorResolucionDian ?? this.emisorResolucionDian,
      emisorFechaResolucion:
          emisorFechaResolucion ?? this.emisorFechaResolucion,
      emisorPrefijo: emisorPrefijo ?? this.emisorPrefijo,
      emisorRangoInicial: emisorRangoInicial ?? this.emisorRangoInicial,
      emisorRangoFinal: emisorRangoFinal ?? this.emisorRangoFinal,
      receptorNit: receptorNit ?? this.receptorNit,
      receptorNombre: receptorNombre ?? this.receptorNombre,
      receptorDireccion: receptorDireccion ?? this.receptorDireccion,
      receptorCiudad: receptorCiudad ?? this.receptorCiudad,
      receptorTelefono: receptorTelefono ?? this.receptorTelefono,
      receptorEmail: receptorEmail ?? this.receptorEmail,
      servicioDescripcion: servicioDescripcion ?? this.servicioDescripcion,
      servicioOrigen: servicioOrigen ?? this.servicioOrigen,
      servicioDestino: servicioDestino ?? this.servicioDestino,
      servicioDistanciaKm: servicioDistanciaKm ?? this.servicioDistanciaKm,
      servicioFecha: servicioFecha ?? this.servicioFecha,
      subtotal: subtotal ?? this.subtotal,
      ivaPorcentaje: ivaPorcentaje ?? this.ivaPorcentaje,
      ivaValor: ivaValor ?? this.ivaValor,
      retencionFuentePorcentaje:
          retencionFuentePorcentaje ?? this.retencionFuentePorcentaje,
      retencionFuenteValor: retencionFuenteValor ?? this.retencionFuenteValor,
      retencionIcaPorcentaje:
          retencionIcaPorcentaje ?? this.retencionIcaPorcentaje,
      retencionIcaValor: retencionIcaValor ?? this.retencionIcaValor,
      total: total ?? this.total,
      status: status ?? this.status,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      notas: notas ?? this.notas,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      emittedAt: emittedAt ?? this.emittedAt,
      voidedAt: voidedAt ?? this.voidedAt,
      voidedReason: voidedReason ?? this.voidedReason,
      items: items ?? this.items,
    );
  }

  @override
  List<Object?> get props => [
        id,
        numeroFactura,
        serviceId,
        customerId,
        driverId,
        fechaEmision,
        fechaVencimiento,
        emisorNit,
        emisorNombre,
        emisorDireccion,
        emisorCiudad,
        emisorTelefono,
        emisorEmail,
        emisorResolucionDian,
        emisorFechaResolucion,
        emisorPrefijo,
        emisorRangoInicial,
        emisorRangoFinal,
        receptorNit,
        receptorNombre,
        receptorDireccion,
        receptorCiudad,
        receptorTelefono,
        receptorEmail,
        servicioDescripcion,
        servicioOrigen,
        servicioDestino,
        servicioDistanciaKm,
        servicioFecha,
        subtotal,
        ivaPorcentaje,
        ivaValor,
        retencionFuentePorcentaje,
        retencionFuenteValor,
        retencionIcaPorcentaje,
        retencionIcaValor,
        total,
        status,
        pdfUrl,
        notas,
        createdAt,
        updatedAt,
        emittedAt,
        voidedAt,
        voidedReason,
        items,
      ];
}

/// Línea de factura (detalle).
class InvoiceItem extends Equatable {
  final String id;
  final String invoiceId;
  final int orden;
  final String? codigo;
  final String descripcion;
  final double cantidad;
  final String unidad;
  final double precioUnitario;
  final double descuentoPorcentaje;
  final double descuentoValor;
  final double subtotal;
  final double ivaPorcentaje;
  final double ivaValor;
  final double total;

  const InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.orden,
    this.codigo,
    required this.descripcion,
    required this.cantidad,
    required this.unidad,
    required this.precioUnitario,
    required this.descuentoPorcentaje,
    required this.descuentoValor,
    required this.subtotal,
    required this.ivaPorcentaje,
    required this.ivaValor,
    required this.total,
  });

  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      id: map['id'] as String,
      invoiceId: map['invoice_id'] as String,
      orden: (map['orden'] as num).toInt(),
      codigo: map['codigo'] as String?,
      descripcion: map['descripcion'] as String,
      cantidad: (map['cantidad'] as num).toDouble(),
      unidad: map['unidad'] as String,
      precioUnitario: (map['precio_unitario'] as num).toDouble(),
      descuentoPorcentaje:
          (map['descuento_porcentaje'] as num?)?.toDouble() ?? 0,
      descuentoValor: (map['descuento_valor'] as num?)?.toDouble() ?? 0,
      subtotal: (map['subtotal'] as num).toDouble(),
      ivaPorcentaje: (map['iva_porcentaje'] as num).toDouble(),
      ivaValor: (map['iva_valor'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'invoice_id': invoiceId,
      'orden': orden,
      if (codigo != null) 'codigo': codigo,
      'descripcion': descripcion,
      'cantidad': cantidad,
      'unidad': unidad,
      'precio_unitario': precioUnitario,
      'descuento_porcentaje': descuentoPorcentaje,
      'descuento_valor': descuentoValor,
      'subtotal': subtotal,
      'iva_porcentaje': ivaPorcentaje,
      'iva_valor': ivaValor,
      'total': total,
    };
  }

  InvoiceItem copyWith({
    String? id,
    String? invoiceId,
    int? orden,
    String? codigo,
    String? descripcion,
    double? cantidad,
    String? unidad,
    double? precioUnitario,
    double? descuentoPorcentaje,
    double? descuentoValor,
    double? subtotal,
    double? ivaPorcentaje,
    double? ivaValor,
    double? total,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      orden: orden ?? this.orden,
      codigo: codigo ?? this.codigo,
      descripcion: descripcion ?? this.descripcion,
      cantidad: cantidad ?? this.cantidad,
      unidad: unidad ?? this.unidad,
      precioUnitario: precioUnitario ?? this.precioUnitario,
      descuentoPorcentaje: descuentoPorcentaje ?? this.descuentoPorcentaje,
      descuentoValor: descuentoValor ?? this.descuentoValor,
      subtotal: subtotal ?? this.subtotal,
      ivaPorcentaje: ivaPorcentaje ?? this.ivaPorcentaje,
      ivaValor: ivaValor ?? this.ivaValor,
      total: total ?? this.total,
    );
  }

  @override
  List<Object?> get props => [
        id,
        invoiceId,
        orden,
        codigo,
        descripcion,
        cantidad,
        unidad,
        precioUnitario,
        descuentoPorcentaje,
        descuentoValor,
        subtotal,
        ivaPorcentaje,
        ivaValor,
        total,
      ];
}
