import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muevex/core/models/user_model.dart';
import 'package:muevex/core/models/service_model.dart';
import 'package:muevex/core/models/load_model.dart';
import 'package:muevex/core/services/price_calculator.dart';
import 'package:muevex/core/supabase/supabase_client.dart';
import 'package:muevex/features/auth/providers/auth_provider.dart';

// Form state for creating service
final serviceFormProvider =
    StateNotifierProvider<ServiceFormNotifier, Map<String, dynamic>>((ref) {
  return ServiceFormNotifier();
});

class ServiceFormNotifier extends StateNotifier<Map<String, dynamic>> {
  ServiceFormNotifier()
      : super({
          'originLat': 0.0,
          'originLng': 0.0,
          'destinationLat': 0.0,
          'destinationLng': 0.0,
          'originName': '',
          'destinationName': '',
          'description': '',
          'loadWeight': 0.0,
          'loadDimensions': '',
          'loadType': 'muebles',
          'needsHelp': false,
          'floors': 0,
          'photos': [],
        });

  void setOriginLat(double lat) => state = {...state, 'originLat': lat};
  void setOriginLng(double lng) => state = {...state, 'originLng': lng};

  void setDestinationLat(double lat) =>
      state = {...state, 'destinationLat': lat};
  void setDestinationLng(double lng) =>
      state = {...state, 'destinationLng': lng};

  void setOriginName(String name) => state = {...state, 'originName': name};

  void setDestinationName(String name) =>
      state = {...state, 'destinationName': name};

  void setDescription(String desc) => state = {...state, 'description': desc};

  void setLoadWeight(double weight) => state = {...state, 'loadWeight': weight};

  void setLoadDimensions(String dims) =>
      state = {...state, 'loadDimensions': dims};

  void setLoadType(String type) => state = {...state, 'loadType': type};

  void setNeedsHelp(bool value) => state = {...state, 'needsHelp': value};

  void setFloors(int floors) => state = {...state, 'floors': floors};

  void addPhoto(String photoPath) {
    final List<String> photos = List<String>.from(state['photos']);
    photos.add(photoPath);
    state = {...state, 'photos': photos};
  }

  void removePhoto(String photoPath) {
    final List<String> photos = List<String>.from(state['photos']);
    photos.remove(photoPath);
    state = {...state, 'photos': photos};
  }

  /// Carga los datos de un servicio anterior para repetirlo (prefill).
  void fillFromService(Service service) {
    state = {
      ...state,
      'originLat': service.originLat,
      'originLng': service.originLng,
      'destinationLat': service.destinationLat,
      'destinationLng': service.destinationLng,
      'originName': service.originName ?? '',
      'destinationName': service.destinationName ?? '',
      'description':
          service.description.isEmpty ? state['description'] : service.description,
      'loadType': service.loadType.isNotEmpty ? service.loadType : state['loadType'],
      'loadWeight': service.loadWeightKg > 0
          ? service.loadWeightKg
          : (service.loadWeight > 0 ? service.loadWeight : state['loadWeight']),
      'floors': service.floors > 0 ? service.floors : state['floors'],
      'needsHelp':
          service.loadingHelp ? service.loadingHelp : state['needsHelp'],
    };
  }

  void clear() {
    state = {
      'originLat': 0.0,
      'originLng': 0.0,
      'destinationLat': 0.0,
      'destinationLng': 0.0,
      'originName': '',
      'destinationName': '',
      'description': '',
      'loadWeight': 0.0,
      'loadDimensions': '',
      'loadType': 'muebles',
      'needsHelp': false,
      'floors': 0,
      'photos': [],
    };
  }

  Load getCurrentLoad() {
    return Load(
      id: '',
      serviceId: '',
      description: state['description'] as String,
      weightKg: (state['loadWeight'] as num).toDouble(),
      dimensions: state['loadDimensions'] as String,
      type: state['loadType'] as String,
      needsHelp: state['needsHelp'] as bool,
      floors: state['floors'] as int,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> getCurrentServiceMap() {
    return {
      'originLat': state['originLat'],
      'originLng': state['originLng'],
      'destinationLat': state['destinationLat'],
      'destinationLng': state['destinationLng'],
    };
  }
}

final currentServiceProvider = StateProvider<Service?>((ref) => null);

final userServicesProvider = FutureProvider<List<Service>>((ref) async {
  final user = ref.watch(authProvider).value;
  if (user != null && user.role == UserRole.customer) {
    return await getUserServices(user.id);
  }
  return <Service>[];
});

/// Distancia aproximada (km) entre origen y destino del formulario actual.
/// Se usa en el resumen del panel inferior de la pantalla de mapa.
final recommendedDistanceKmProvider = StateProvider<double>((ref) {
  return _computeDistanceKm(ref.watch(serviceFormProvider));
});

final recommendedPriceProvider = StateProvider<double>((ref) {
  final formState = ref.watch(serviceFormProvider);
  final serviceType = formState['loadType'] as String? ?? 'muebles';
  final needsHelp = formState['needsHelp'] as bool? ?? false;
  final floors = (formState['floors'] ?? 0) as int;
  final distanceKm = _computeDistanceKm(formState);

  return PriceCalculator.calculateRecommendedPrice(
    distanceKm: distanceKm,
    serviceType: serviceType,
    needsHelp: needsHelp,
    floors: floors,
    hourPeriod: null,
  );
});

/// Calcula la distancia aproximada (en km) entre origen y destino usando la
/// fórmula del haversine. Devuelve 0 si falta algún punto.
double _computeDistanceKm(Map<String, dynamic> formState) {
  final originLat = (formState['originLat'] as num?)?.toDouble() ?? 0.0;
  final originLng = (formState['originLng'] as num?)?.toDouble() ?? 0.0;
  final destLat = (formState['destinationLat'] as num?)?.toDouble() ?? 0.0;
  final destLng = (formState['destinationLng'] as num?)?.toDouble() ?? 0.0;

  if ((originLat == 0 && originLng == 0) || (destLat == 0 && destLng == 0)) {
    return 0.0;
  }

  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(destLat - originLat);
  final dLng = _toRadians(destLng - originLng);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_toRadians(originLat)) *
          math.cos(_toRadians(destLat)) *
          math.pow(math.sin(dLng / 2), 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRadians(double deg) => deg * math.pi / 180.0;

final createServiceProvider =
    FutureProvider.family<bool, Map<String, dynamic>>((ref, data) async {
  final user = ref.watch(authProvider).value;
  if (user == null) {
    throw Exception(
        'sesión no cargada (¿tu cuenta no tiene fila en users? revisa RLS de users)');
  }

  try {
    final priceTotal = (data['priceTotal'] as num?)?.toDouble() ?? 0.0;
    final priceBase = (data['priceBase'] as num?)?.toDouble() ?? priceTotal;
    final weight = (data['loadWeight'] as num?)?.toDouble() ?? 0.0;
    final floors = (data['floors'] as num?)?.toInt() ?? 0;
    final needsHelp = data['needsHelp'] as bool? ?? false;
    final distanceKm = _computeDistanceKm(data);
    final durationMinutes =
        (distanceKm / 35.0 * 60).round(); // estimación a 35 km/h promedio

    final service = Service(
      id: '',
      customerId: user.id,
      driverId: null,
      priceBase: priceBase,
      estimatedPrice: priceTotal,
      recommendedPrice: (data['priceRecommended'] as num?)?.toDouble() ?? priceTotal,
      originLat: ((data['originLat'] as num?) ?? 0).toDouble(),
      originLng: ((data['originLng'] as num?) ?? 0).toDouble(),
      destinationLat: ((data['destinationLat'] as num?) ?? 0).toDouble(),
      destinationLng: ((data['destinationLng'] as num?) ?? 0).toDouble(),
      origin: data['originName'] as String? ?? '',
      destination: data['destinationName'] as String? ?? '',
      originName: data['originName'] as String?,
      destinationName: data['destinationName'] as String?,
      description: data['description'] as String? ?? '',
      loadDescription: data['description'] as String?,
      loadType: data['loadType'] as String? ?? 'muebles',
      loadWeight: weight,
      loadWeightKg: weight,
      floors: floors,
      loadingHelp: needsHelp,
      needsHelp: needsHelp,
      status: ServiceStatus.solicitado,
      createdAt: DateTime.now(),
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      estimatedTimeMin: 0.0,
      loadPhotos: List<String>.from(data['photos'] as List? ?? []),
    );

    final photoPaths = List<String>.from(data['photos'] as List? ?? []);
    await createServiceWithPhotos(service, photoPaths);
    return true;
  } catch (e) {
    debugPrint('MUEVEX error al crear servicio: $e');
    rethrow;
  }
});
