import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:muevex/core/models/user_model.dart';
import 'package:muevex/core/models/service_model.dart';
import 'package:muevex/core/models/load_model.dart';
import 'package:muevex/core/services/tariff_codec.dart';
import 'package:muevex/core/services/tariff_engine.dart';
import 'package:muevex/features/map/data/geocoding_service.dart';
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
          // ── Campos del motor de tarifas ──
          // `items` es la lista real de artículos; `loadType` se deduce de
          // ella y se conserva solo por compatibilidad con los filtros que ya
          // lo leen. `floors` se mantiene como suma de recogida + entrega.
          'items': <Map<String, dynamic>>[],
          'floorsPickup': 0,
          'floorsDelivery': 0,
          'trips': 1,
          'helperOrigin': 'incluido',
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

  // ── Motor de tarifas ────────────────────────────────────────────────────

  /// Fija la selección de artículos y recalcula `loadType` y `floors` para que
  /// las columnas legacy nunca queden contradiciendo a las nuevas.
  void setItems(List<ArticuloSeleccionado> articulos) {
    final selected = articulos.where((a) => a.cantidad > 0).toList();
    state = {
      ...state,
      'items': articulosAMaps(selected),
      'loadType': tipoCargaLegacy(selected),
      'floors': _pickup(state) + _delivery(state),
    };
  }

  /// Añade un artículo, o le suma una unidad si ya estaba.
  void agregarArticulo(ArticuloCatalogo articulo) {
    final actuales = articulosDesdeJson(state['items']);
    final i = actuales.indexWhere((a) => a.articulo.id == articulo.id);
    if (i >= 0) {
      actuales[i] = ArticuloSeleccionado(
        actuales[i].articulo,
        actuales[i].cantidad + 1,
      );
    } else {
      actuales.add(ArticuloSeleccionado(articulo, 1));
    }
    setItems(actuales);
  }

  /// Baja la cantidad de un artículo; lo quita al llegar a cero.
  void restarArticulo(String articuloId) {
    final actuales = articulosDesdeJson(state['items']);
    final i = actuales.indexWhere((a) => a.articulo.id == articuloId);
    if (i < 0) return;
    final cantidad = actuales[i].cantidad - 1;
    if (cantidad <= 0) {
      actuales.removeAt(i);
    } else {
      actuales[i] = ArticuloSeleccionado(actuales[i].articulo, cantidad);
    }
    setItems(actuales);
  }

  void setFloorsPickup(int pisos) => state = {
        ...state,
        'floorsPickup': pisos < 0 ? 0 : pisos,
        'floors': (pisos < 0 ? 0 : pisos) + _delivery(state),
      };

  void setFloorsDelivery(int pisos) => state = {
        ...state,
        'floorsDelivery': pisos < 0 ? 0 : pisos,
        'floors': _pickup(state) + (pisos < 0 ? 0 : pisos),
      };

  void setTrips(int viajes) =>
      state = {...state, 'trips': viajes < 1 ? 1 : (viajes > 10 ? 10 : viajes)};

  /// Cambia quién pone el ayudante y refleja el recargo en el campo legacy
  /// `needsHelp`, que el conductor todavía lee.
  void setHelperOrigin(OrigenAyudante origen) => state = {
        ...state,
        'helperOrigin': origen.name,
        'needsHelp': origen.tieneCosto,
      };

  int _pickup(Map<String, dynamic> s) =>
      (s['floorsPickup'] as num?)?.toInt() ?? 0;
  int _delivery(Map<String, dynamic> s) =>
      (s['floorsDelivery'] as num?)?.toInt() ?? 0;

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
      'description': service.description.isEmpty
          ? state['description']
          : service.description,
      'loadType':
          service.loadType.isNotEmpty ? service.loadType : state['loadType'],
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

/// Precio estimado del servicio actual, según el motor de tarifas.
///
/// Devuelve el total, no el desglose. Para el desglose (el que ve el cliente
/// al tocar el precio) usa [tarifaActualProvider].
final recommendedPriceProvider = StateProvider<double>((ref) {
  return ref.watch(tarifaActualProvider).total;
});

/// Desglose completo de la tarifa del servicio en edición.
final tarifaActualProvider = StateProvider<Tarifa>((ref) {
  final formState = ref.watch(serviceFormProvider);
  return TarifaEngine.calcular(
    entradaDesdeFormulario(formState, _computeDistanceKm(formState)),
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

/// Devuelve el nombre resuelto del lugar.
/// - Si `formName` ya es una dirección escrita por el usuario (no vacío y
///   no es "Mi ubicación"), lo usa tal cual.
/// - Si es "Mi ubicación" o vacío, intenta reverse-geocode con Esri.
/// - Si falla la red, devuelve `formName` (o "Ubicación actual" si era vacío).
Future<String> _resolvedName(
  String? formName,
  LatLng point,
  GeocodingService geocoder,
) async {
  final trimmed = formName?.trim() ?? '';
  final esMiUbicacion = trimmed.isEmpty ||
      trimmed.toLowerCase() == 'mi ubicación' ||
      trimmed.toLowerCase() == 'mi ubicacion';

  if (!esMiUbicacion) return trimmed;

  final reverse = await geocoder.reverseGeocode(point);
  if (reverse != null && reverse.isNotEmpty) return reverse;

  return 'Ubicación actual';
}

final createServiceProvider =
    FutureProvider.family<bool, Map<String, dynamic>>((ref, data) async {
  final user = ref.watch(authProvider).value;
  if (user == null) {
    throw Exception(
        'sesión no cargada (¿tu cuenta no tiene fila en users? revisa RLS de users)');
  }

  try {
    final form = data;
    final distanceKm = _computeDistanceKm(form);
    final durationMinutes =
        (distanceKm / 35.0 * 60).round(); // estimación a 35 km/h promedio

    // Motor de tarifas nuevo: calcula precio y desglose a partir del formulario
    // completo (artículos, pisos, ayudante, viajes).
    final tarifa =
        TarifaEngine.calcular(entradaDesdeFormulario(form, distanceKm));

    final weight = (form['loadWeight'] as num?)?.toDouble() ?? 0.0;
    final weightKg = (tarifa.pesoKg > 0) ? tarifa.pesoKg : weight;
    final helperOrigin = ayudanteDesdeDb(form['helperOrigin'] as String?);

    // Geocodificación inversa: si el origen/destino es "Mi ubicación" (GPS),
    // resolvemos a dirección real. Fallback al nombre que venga del form.
    final geocoder = GeocodingService();
    final originLat = ((form['originLat'] as num?) ?? 0).toDouble();
    final originLng = ((form['originLng'] as num?) ?? 0).toDouble();
    final destLat = ((form['destinationLat'] as num?) ?? 0).toDouble();
    final destLng = ((form['destinationLng'] as num?) ?? 0).toDouble();

    final originName = await _resolvedName(
      form['originName'] as String?,
      LatLng(originLat, originLng),
      geocoder,
    );
    final destName = await _resolvedName(
      form['destinationName'] as String?,
      LatLng(destLat, destLng),
      geocoder,
    );
    geocoder.dispose();

    final service = Service(
      id: '',
      customerId: user.id,
      driverId: null,
      priceBase: tarifa.total,
      estimatedPrice: tarifa.total,
      recommendedPrice: tarifa.total,
      originLat: originLat,
      originLng: originLng,
      destinationLat: destLat,
      destinationLng: destLng,
      origin: originName,
      destination: destName,
      originName: originName,
      destinationName: destName,
      description: form['description'] as String? ?? '',
      loadDescription: form['description'] as String?,
      loadType: form['loadType'] as String? ?? 'muebles',
      loadWeight: weight,
      loadWeightKg: weightKg,
      // Pisos totales = recogida + entrega (para compatibilidad legacy)
      floors: (form['floorsPickup'] as num?)?.toInt() ??
          0 + ((form['floorsDelivery'] as num?)?.toInt() ?? 0),
      loadingHelp: helperOrigin.tieneCosto,
      needsHelp: helperOrigin.tieneCosto,
      status: ServiceStatus.solicitado,
      createdAt: DateTime.now(),
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      estimatedTimeMin: 0.0,
      loadPhotos: List<String>.from(form['photos'] as List? ?? []),
      // Tarifas v2
      items: articulosAMaps(articulosDesdeJson(form['items'])),
      floorsPickup: (form['floorsPickup'] as num?)?.toInt() ?? 0,
      floorsDelivery: (form['floorsDelivery'] as num?)?.toInt() ?? 0,
      trips: (form['trips'] as num?)?.toInt() ?? 1,
      helperOrigin: ayudanteAMaps(helperOrigin),
      estimatedWeightKg: tarifa.pesoKg,
      estimatedVolumeM3: tarifa.volumenM3,
      vehicleCategory: tarifa.categoriaSugerida.nombre,
      tariffBreakdown: desgloseAMap(tarifa),
      tariffVersion: 'v2',
    );

    // Persistencia de los campos nuevos: la función `createServiceWithPhotos`
    // ya incluye todos los campos del modelo `Service`, así que con que el
    // modelo tenga los campos basta. Aquí solo los ponemos en el objeto.
    // NOTA: si el repositorio no guarda aún estos campos, hay que actualizarlo.
    // Se hace abajo en service_repository.dart.

    final photoPaths = List<String>.from(form['photos'] as List? ?? []);
    await createServiceWithPhotos(service, photoPaths);
    return true;
  } catch (e) {
    debugPrint('MUEVEX error al crear servicio: $e');
    rethrow;
  }
});
