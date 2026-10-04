import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:muevex/features/map/data/route_service.dart';
import 'package:muevex/features/map/models/route_result.dart';

enum RouteStatus { idle, loading, success, error }

class MapRouteState {
  final RouteStatus status;
  final RouteResult? route;
  final String? error;

  const MapRouteState._({required this.status, this.route, this.error});

  const MapRouteState.initial() : this._(status: RouteStatus.idle);
}

/// Provee el [RouteService] compartido por la pantalla de mapa.
final routeServiceProvider = Provider<RouteService>((ref) {
  final service = RouteService();
  ref.onDispose(service.dispose);
  return service;
});

/// Estado y lógica de la ruta vial entre origen y destino.
///
/// Evita recalcular (y volver al estado de carga) cuando el origen y el
/// destino son los mismos que ya se calcularon, para no parpadear la UI.
class MapRouteNotifier extends StateNotifier<MapRouteState> {
  final RouteService _service;

  MapRouteNotifier(this._service) : super(const MapRouteState.initial());

  int _generation = 0;
  LatLng? _lastOrigin;
  LatLng? _lastDestination;

  Future<void> requestRoute({
    required LatLng origin,
    required LatLng destination,
    bool force = false,
  }) async {
    if (!force &&
        _lastOrigin == origin &&
        _lastDestination == destination &&
        state.status == RouteStatus.success) {
      return;
    }

    final generation = ++_generation;
    _lastOrigin = origin;
    _lastDestination = destination;
    state = const MapRouteState._(status: RouteStatus.loading);

    try {
      final route =
          await _service.getRoute(origin: origin, destination: destination);
      if (!mounted || generation != _generation) return;
      debugPrint(
          'MUEVEX route OK distance=${route.distanceKm.toStringAsFixed(3)}km '
          'duration=${route.durationSeconds.toStringAsFixed(0)}s '
          'points=${route.points.length}');
      state = MapRouteState._(status: RouteStatus.success, route: route);
    } on RouteException catch (e) {
      if (!mounted || generation != _generation) return;
      debugPrint('MUEVEX route ERROR: ${e.message}');
      state = MapRouteState._(status: RouteStatus.error, error: e.message);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      state = const MapRouteState._(
        status: RouteStatus.error,
        error: 'No se pudo calcular la ruta.',
      );
    }
  }

  /// Limpia el estado cuando falta origen o destino.
  void clear() {
    _generation++;
    _lastOrigin = null;
    _lastDestination = null;
    state = const MapRouteState.initial();
  }
}

final mapRouteProvider =
    StateNotifierProvider<MapRouteNotifier, MapRouteState>((ref) {
  return MapRouteNotifier(ref.watch(routeServiceProvider));
});
