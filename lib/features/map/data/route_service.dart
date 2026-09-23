import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:muevex/features/map/models/route_result.dart';

/// Servicio de rutas reales vial por calles usando el servidor público de
/// OSRM (Open Source Routing Machine). No requiere API key.
///
/// Documentación de la API: https://project-osrm.org/docs/v5.5.x/api/
/// Endpoint usado: `GET /route/v1/driving/{lon,lat};{lon,lat}`
class RouteService {
  static const String _host = 'router.project-osrm.org';
  static const String _basePath = '/route/v1/driving';

  static const int _timeoutSeconds = 10;
  static const int _cacheMaxEntries = 12;

  final http.Client _client = http.Client();
  final Map<String, RouteResult> _cache = {};

  /// Calcula la ruta vial entre [origin] y [destination].
  ///
  /// Las llamadas repetidas con los mismos puntos se sirven desde caché,
  /// evitando consumir la red y demorar la pantalla.
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    int alternatives = 0,
  }) async {
    final key = _cacheKey(origin, destination);
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }

    final coordinates = '${_f(origin.longitude)},${_f(origin.latitude)};'
        '${_f(destination.longitude)},${_f(destination.latitude)}';

    final uri = Uri.https(
      _host,
      '$_basePath/$coordinates',
      {
        'overview': 'full',
        'geometries': 'geojson',
        'alternatives': '$alternatives',
      },
    );

    late http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'User-Agent': 'muevex-app/1.0 (demo)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: _timeoutSeconds));
    } on TimeoutException {
      throw const RouteException('El servidor de rutas tardó demasiado. Reintenta.');
    } on http.ClientException {
      throw const RouteException('No hay conexión. No se pudo calcular la ruta.');
    } catch (_) {
      throw const RouteException('No se pudo calcular la ruta.');
    }

    if (response.statusCode != 200) {
      throw RouteException('El servidor de rutas respondió ${response.statusCode}.');
    }

    final RouteResult result;
    try {
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      result = RouteResult.fromOsrmJson(decoded);
    } on FormatException {
      throw const RouteException('No hay una ruta posible entre esos puntos.');
    }

    if (result.points.isEmpty || result.distanceMeters <= 0) {
      throw const RouteException('No hay una ruta posible entre esos puntos.');
    }

    _cache[key] = result;
    if (_cache.length > _cacheMaxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }

  /// Formato compacto de coordenada (seis decimales son ~1 m de precisión),
  /// evitando exponentes en la URL.
  static String _f(double value) => value.toStringAsFixed(6);

  static String _cacheKey(LatLng origin, LatLng destination) {
    return '${_f(origin.latitude)}_${_f(origin.longitude)}'
        '_${_f(destination.latitude)}_${_f(destination.longitude)}';
  }

  void dispose() => _client.close();
}

/// Error amigable de cálculo de rutas, listo para mostrarse al usuario.
class RouteException implements Exception {
  final String message;

  const RouteException(this.message);

  @override
  String toString() => message;
}