import 'package:latlong2/latlong.dart';

/// Resultado de una ruta vial calculada por un servicio de rutas reales.
///
/// Contiene los puntos de la geometría (que SIGUEN las calles), la distancia
/// recorrida y la duración estimada, tal como las devuelve el servicio.
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  double get distanceKm => distanceMeters / 1000.0;

  double get durationMinutes => durationSeconds / 60.0;

  /// Parsea la respuesta de OSRM (`/route/v1/driving/...` con
  /// `geometries=geojson`), que es la geometría de la ruta sobre las vías.
  ///
  /// El body tiene la forma:
  /// ```json
  /// { "code": "Ok", "routes": [ {
  ///   "distance": 1234.5, "duration": 123.4,
  ///   "geometry": { "coordinates": [[lon, lat], ...] }
  /// } ] }
  /// ```
  factory RouteResult.fromOsrmJson(Map<String, dynamic> json) {
    if (json['code'] != 'Ok') {
      throw const FormatException('OSRM no pudo calcular la ruta');
    }

    final routes = (json['routes'] as List?) ?? const [];
    if (routes.isEmpty) {
      throw const FormatException('OSRM: no se encontró ninguna ruta');
    }

    final route = routes.first as Map<String, dynamic>;
    final distance = (route['distance'] as num?)?.toDouble() ?? 0.0;
    final duration = (route['duration'] as num?)?.toDouble() ?? 0.0;
    final geometry = (route['geometry'] as Map?) ?? const {};
    final coords = (geometry['coordinates'] as List?) ?? const [];

    final points = <LatLng>[];
    for (final entry in coords) {
      if (entry is List && entry.length >= 2) {
        final lon = (entry[0] as num).toDouble();
        final lat = (entry[1] as num).toDouble();
        if (lat != 0 || lon != 0) {
          points.add(LatLng(lat, lon));
        }
      }
    }

    return RouteResult(
      points: points,
      distanceMeters: distance,
      durationSeconds: duration,
    );
  }
}
