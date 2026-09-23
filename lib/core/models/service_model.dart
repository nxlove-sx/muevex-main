import 'package:equatable/equatable.dart';

/// Los 7 estados canónicos de la plataforma (spec 50).
enum ServiceStatus {
  solicitado,
  aceptado,
  enRecogida,
  enCurso,
  completado,
  canceladoCliente,
  canceladoConductor,
}

extension ServiceStatusMapping on ServiceStatus {
  String get dbName {
    switch (this) {
      case ServiceStatus.solicitado:
        return 'solicitado';
      case ServiceStatus.aceptado:
        return 'aceptado';
      case ServiceStatus.enRecogida:
        return 'en_recogida';
      case ServiceStatus.enCurso:
        return 'en_curso';
      case ServiceStatus.completado:
        return 'completado';
      case ServiceStatus.canceladoCliente:
        return 'cancelado_cliente';
      case ServiceStatus.canceladoConductor:
        return 'cancelado_conductor';
    }
  }

  static ServiceStatus fromDbName(String dbName) {
    switch (dbName.toLowerCase()) {
      case 'solicitado':
        return ServiceStatus.solicitado;
      case 'aceptado':
        return ServiceStatus.aceptado;
      case 'en_recogida':
        return ServiceStatus.enRecogida;
      case 'en_curso':
        return ServiceStatus.enCurso;
      case 'completado':
        return ServiceStatus.completado;
      case 'cancelado_cliente':
        return ServiceStatus.canceladoCliente;
      case 'cancelado_conductor':
        return ServiceStatus.canceladoConductor;
      // Valores legacy (pre-integración) tolerados.
      case 'requested':
      case 'searching_driver':
        return ServiceStatus.solicitado;
      case 'driver_accepted':
      case 'driver_on_way':
        return ServiceStatus.aceptado;
      case 'driver_arrived':
      case 'loading':
        return ServiceStatus.enRecogida;
      case 'in_transit':
      case 'arrived_destination':
        return ServiceStatus.enCurso;
      case 'delivered':
      case 'completed':
        return ServiceStatus.completado;
      case 'cancelled':
        return ServiceStatus.canceladoConductor;
      default:
        throw ArgumentError('Estado de servicio desconocido: $dbName');
    }
  }
}

extension ServiceStatusExtension on ServiceStatus {
  String get arabicName {
    switch (this) {
      case ServiceStatus.solicitado:
        return 'Solicitado';
      case ServiceStatus.aceptado:
        return 'Conductor asignado';
      case ServiceStatus.enRecogida:
        return 'Conductor en recogida';
      case ServiceStatus.enCurso:
        return 'En camino al destino';
      case ServiceStatus.completado:
        return 'Completado';
      case ServiceStatus.canceladoCliente:
        return 'Cancelado por ti';
      case ServiceStatus.canceladoConductor:
        return 'Cancelado por el conductor';
    }
  }

  bool get isActive =>
      this == ServiceStatus.aceptado ||
      this == ServiceStatus.enRecogida ||
      this == ServiceStatus.enCurso ||
      this == ServiceStatus.solicitado;
}

class Service extends Equatable {
  final String id;
  final String customerId;
  final String? driverId;
  final ServiceStatus status;

  final double priceBase;
  final double? priceOffer;
  final double estimatedPrice;
  final double? finalPrice;
  final double platformFee;
  final double driverEarnings;

  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;
  final String origin;
  final String destination;
  final String? originName;
  final String? destinationName;

  final String description;

  final double distanceKm;
  final int durationMinutes;

  final String loadType;
  final String? loadDescription;
  final double loadWeightKg;
  final int floors;
  final bool loadingHelp;
  final List<String> photos;

  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  // Campos legacy (solo lectura / backwards-compat)
  final double loadWeight;
  final double estimatedTimeMin;
  final bool needsHelp;
  final List<String> loadPhotos;
  final Map<String, dynamic> loadDetails;
  final double recommendedPrice;

  const Service({
    required this.id,
    required this.customerId,
    this.driverId,
    required this.status,
    this.priceBase = 0,
    this.priceOffer,
    this.estimatedPrice = 0,
    this.finalPrice,
    this.platformFee = 0,
    this.driverEarnings = 0,
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
    this.origin = '',
    this.destination = '',
    this.originName,
    this.destinationName,
    this.description = '',
    this.distanceKm = 0,
    this.durationMinutes = 0,
    this.loadType = 'muebles',
    this.loadDescription,
    this.loadWeightKg = 0,
    this.floors = 0,
    this.loadingHelp = false,
    this.photos = const [],
    required this.createdAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.loadWeight = 0,
    this.estimatedTimeMin = 0,
    this.needsHelp = false,
    this.loadPhotos = const [],
    this.loadDetails = const {},
    this.recommendedPrice = 0,
  });

  /// Precio que se muestra en la UI (canónico, con respaldo legacy).
  double get priceTotal =>
      estimatedPrice > 0 ? estimatedPrice : (priceBase > 0 ? priceBase : 0);

  factory Service.fromMap(Map<String, dynamic> map) {
    final estimated = (map['estimated_price'] as num?)?.toDouble() ??
        (map['price_base'] as num?)?.toDouble() ??
        (map['price_recommended'] as num?)?.toDouble() ??
        0.0;
    final name = (String? key) => map[key] as String?;
    return Service(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      driverId: map['driver_id'] as String?,
      status: ServiceStatusMapping.fromDbName(map['status'] as String),
      priceBase: (map['price_base'] as num?)?.toDouble() ?? 0.0,
      priceOffer: map['price_offer'] != null ? (map['price_offer'] as num).toDouble() : null,
      estimatedPrice: estimated,
      finalPrice: map['final_price'] != null ? (map['final_price'] as num).toDouble() : null,
      platformFee: (map['platform_fee'] as num?)?.toDouble() ?? 0.0,
      driverEarnings: (map['driver_earnings'] as num?)?.toDouble() ?? 0.0,
      originLat: (map['origin_lat'] as num?)?.toDouble() ?? 0.0,
      originLng: (map['origin_lng'] as num?)?.toDouble() ?? 0.0,
      destinationLat: (map['destination_lat'] as num?)?.toDouble() ?? 0.0,
      destinationLng: (map['destination_lng'] as num?)?.toDouble() ?? 0.0,
      origin: name('origin') ?? '',
      destination: name('destination') ?? '',
      originName: name('origin_name'),
      destinationName: name('destination_name'),
      description: name('description') ?? '',
      distanceKm: (map['distance_km'] as num?)?.toDouble() ?? 0.0,
      durationMinutes: (map['duration_minutes'] as num?)?.toInt() ??
          (map['estimated_time_min'] as num?)?.toInt() ??
          0,
      loadType: name('load_type') ?? 'muebles',
      loadDescription: name('load_description'),
      loadWeightKg: (map['load_weight_kg'] as num?)?.toDouble() ??
          (map['load_weight'] as num?)?.toDouble() ??
          0.0,
      floors: (map['floors'] as num?)?.toInt() ?? 0,
      loadingHelp: (map['loading_help'] as bool?) ??
          (map['needs_help'] as bool?) ??
          false,
      photos: map['photos'] != null ? List<String>.from(map['photos']) : [],
      createdAt: DateTime.parse(map['created_at'] as String),
      acceptedAt: map['accepted_at'] != null
          ? DateTime.tryParse(map['accepted_at'] as String)
          : null,
      startedAt: map['started_at'] != null
          ? DateTime.tryParse(map['started_at'] as String)
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'] as String)
          : null,
      loadWeight: (map['load_weight'] as num?)?.toDouble() ?? 0.0,
      estimatedTimeMin: (map['estimated_time_min'] as num?)?.toDouble() ?? 0.0,
      needsHelp: (map['needs_help'] as bool?) ?? false,
      loadPhotos: map['load_photos'] != null
          ? List<String>.from(map['load_photos'])
          : [],
      loadDetails: map['load_details'] != null
          ? Map<String, dynamic>.from(map['load_details'])
          : {},
      recommendedPrice: (map['recommended_price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'driver_id': driverId,
      'status': status.dbName,
      'price_base': priceBase,
      'price_offer': priceOffer,
      'estimated_price': estimatedPrice,
      'final_price': finalPrice,
      'platform_fee': platformFee,
      'driver_earnings': driverEarnings,
      'origin_lat': originLat,
      'origin_lng': originLng,
      'destination_lat': destinationLat,
      'destination_lng': destinationLng,
      'origin': origin,
      'destination': destination,
      'origin_name': originName,
      'destination_name': destinationName,
      'description': description,
      'distance_km': distanceKm,
      'duration_minutes': durationMinutes,
      'load_type': loadType,
      'load_description': loadDescription,
      'load_weight_kg': loadWeightKg,
      'floors': floors,
      'loading_help': loadingHelp,
      'photos': photos,
      'created_at': createdAt.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  Service copyWith({
    String? id,
    String? customerId,
    String? driverId,
    ServiceStatus? status,
    double? priceBase,
    double? priceOffer,
    double? estimatedPrice,
    double? finalPrice,
    double? platformFee,
    double? driverEarnings,
    double? originLat,
    double? originLng,
    double? destinationLat,
    double? destinationLng,
    String? origin,
    String? destination,
    String? originName,
    String? destinationName,
    String? description,
    double? distanceKm,
    int? durationMinutes,
    String? loadType,
    String? loadDescription,
    double? loadWeightKg,
    int? floors,
    bool? loadingHelp,
    List<String>? photos,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return Service(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      driverId: driverId ?? this.driverId,
      status: status ?? this.status,
      priceBase: priceBase ?? this.priceBase,
      priceOffer: priceOffer ?? this.priceOffer,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      finalPrice: finalPrice ?? this.finalPrice,
      platformFee: platformFee ?? this.platformFee,
      driverEarnings: driverEarnings ?? this.driverEarnings,
      originLat: originLat ?? this.originLat,
      originLng: originLng ?? this.originLng,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLng: destinationLng ?? this.destinationLng,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      originName: originName ?? this.originName,
      destinationName: destinationName ?? this.destinationName,
      description: description ?? this.description,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      loadType: loadType ?? this.loadType,
      loadDescription: loadDescription ?? this.loadDescription,
      loadWeightKg: loadWeightKg ?? this.loadWeightKg,
      floors: floors ?? this.floors,
      loadingHelp: loadingHelp ?? this.loadingHelp,
      photos: photos ?? this.photos,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    customerId,
    driverId,
    status,
    priceBase,
    priceOffer,
    estimatedPrice,
    finalPrice,
    platformFee,
    driverEarnings,
    originLat,
    originLng,
    destinationLat,
    destinationLng,
    origin,
    destination,
    originName,
    destinationName,
    description,
    distanceKm,
    durationMinutes,
    loadType,
    loadDescription,
    loadWeightKg,
    floors,
    loadingHelp,
    photos,
    createdAt,
    acceptedAt,
    startedAt,
    completedAt,
  ];
}