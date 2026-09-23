import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:muevex/features/map/data/geocoding_service.dart';
import 'package:muevex/features/map/models/location_result.dart';

/// Estados de la búsqueda de lugares (item 14).
enum MapSearchStatus {
  /// Sin búsqueda activa.
  idle,

  /// Esperando respuesta del servicio (mostrar indicador de carga).
  searching,

  /// Hay resultados para mostrar.
  results,

  /// La búsqueda terminó sin resultados.
  noResults,

  /// El usuario seleccionó un resultado (se estableció como destino/origen).
  locationSelected,

  /// Ocurrió un error al buscar.
  error,
}

/// Estado completo de la búsqueda de lugares.
class MapSearchState {
  final MapSearchStatus status;
  final List<LocationResult> results;
  final String query;
  final String? error;
  final LocationResult? selected;

  const MapSearchState({
    required this.status,
    this.results = const [],
    this.query = '',
    this.error,
    this.selected,
  });

  const MapSearchState.initial()
      : this(status: MapSearchStatus.idle);

  MapSearchState copyWith({
    MapSearchStatus? status,
    List<LocationResult>? results,
    String? query,
    String? error,
    LocationResult? selected,
  }) {
    return MapSearchState(
      status: status ?? this.status,
      results: results ?? this.results,
      query: query ?? this.query,
      error: error ?? this.error,
      selected: selected ?? this.selected,
    );
  }
}

/// Controla la búsqueda de lugares con debounce y cancelación de peticiones
/// obsoletas (item 5 y 17):
///  - Debounce de ~400 ms mientras se escribe.
///  - Número de generación para descartar respuestas que ya no corresponden
///    al texto actual.
///  - El contexto (proximidad + viewbox) se actualiza mientras el mapa cambia.
class MapSearchNotifier extends StateNotifier<MapSearchState> {
  final GeocodingService _service;

  MapSearchNotifier(this._service) : super(const MapSearchState.initial());

  Timer? _debounce;
  int _requestGeneration = 0;

  LatLng? _proximity;
  LatLngBounds? _bounds;

  /// Actualiza el contexto de la búsqueda (ubicación actual y área visible).
  /// Se llama cuando el mapa se mueve para adaptar los resultados a la zona.
  void updateContext({LatLng? proximity, LatLngBounds? bounds}) {
    _proximity = proximity ?? _proximity;
    _bounds = bounds ?? _bounds;
  }

  /// Punto de partida del usuario (o null si aún no se conoce).
  LatLng? get proximity => _proximity;

  /// Área visible del mapa (o null si aún no se define).
  LatLngBounds? get visibleBounds => _bounds;

  /// Se invoca al cambiar el texto del buscador. Programa la búsqueda real
  /// con debounce y descarta peticiones anteriores.
  void onQueryChanged(String raw) {
    final query = raw.trim();
    _debounce?.cancel();

    if (query.length < 3) {
      _requestGeneration++; // cancela las búsquedas previas aún en vuelo
      state = MapSearchState(
        status: MapSearchStatus.idle,
        query: query,
      );
      return;
    }

    state = MapSearchState(
      status: MapSearchStatus.searching,
      query: query,
    );
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    final generation = ++_requestGeneration;
    try {
      final results = await _service.search(
        query,
        proximity: _proximity,
        bounds: _bounds,
      );
      if (!mounted || generation != _requestGeneration) return;
      state = MapSearchState(
        status: results.isEmpty
            ? MapSearchStatus.noResults
            : MapSearchStatus.results,
        results: results,
        query: query,
      );
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      debugPrint('MUEVEX geocode ERROR [$query]: ${e.runtimeType}: $e');
      state = MapSearchState(
        status: MapSearchStatus.error,
        query: query,
        error: 'Error al buscar. Intenta nuevamente.',
      );
    }
  }

  /// Asigna un resultado como seleccionado (destino u origen).
  void select(LocationResult result) {
    _debounce?.cancel();
    _requestGeneration++;
    state = MapSearchState(
      status: MapSearchStatus.locationSelected,
      query: result.name,
      selected: result,
    );
  }

  /// Vuelve al estado inicial (por ejemplo al cerrar el buscador).
  void reset() {
    _debounce?.cancel();
    _requestGeneration++;
    state = const MapSearchState.initial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// Proveedor del servicio de geocoding (una sola instancia por app).
final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  final service = GeocodingService();
  ref.onDispose(service.dispose);
  return service;
});

/// Proveedor del estado de búsqueda de lugares.
final mapSearchProvider =
    StateNotifierProvider<MapSearchNotifier, MapSearchState>((ref) {
  return MapSearchNotifier(ref.watch(geocodingServiceProvider));
});