import 'dart:convert';

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:muevex/features/map/models/location_result.dart';

/// Servicio de búsqueda/geocodificación de lugares para MUEVEX.
///
/// Usa **Photon** (Komoot), el buscador gratuito sobre datos de OpenStreetMap:
///   https://photon.komoot.io
///
/// No requiere API key. Provee autocompletado, geocodificación directa y
/// resultados ordenados por relevancia + proximidad. Acepta un punto de
/// referencia (ubicación del usuario) y un área visible (límites del mapa)
/// para priorizar los lugares cercanos a la zona donde se está buscando.
class GeocodingService {
  static const String _host = 'photon.komoot.io';
  static const String _path = '/api/';

  final http.Client _client = http.Client();

  /// Memoria caché pequeña por prefijo de consulta + zona, para evitar
  /// llamadas repetidas mientras se escribe (item 17: rendimiento).
  final Map<String, List<LocationResult>> _cache = {};
  static const int _cacheMaxEntries = 24;

  /// Busca lugares mientras el usuario escribe.
  ///
  /// [query] texto a buscar (mínimo 3 caracteres recomendado).
  /// [proximity] coordenadas de referencia (ubicación actual) para que los
  /// resultados cercanos aparezcan primero.
  /// [bounds] área visible del mapa (viewbox). Si se indica, Photon prioriza
  /// los resultados dentro de esa zona.
  Future<List<LocationResult>> search(
    String query, {
    LatLng? proximity,
    LatLngBounds? bounds,
    int limit = 6,
  }) async {
    final key = _cacheKey(query, proximity, bounds);
    final cached = _cache[key];
    if (cached != null) return cached;

    final params = <String, String>{
      'q': query,
      'limit': '$limit',
      if (proximity != null) 'lat': proximity.latitude.toStringAsFixed(4),
      if (proximity != null) 'lon': proximity.longitude.toStringAsFixed(4),
      if (bounds != null)
        'bbox':
            '${bounds.southWest.longitude.toStringAsFixed(4)},'
                '${bounds.southWest.latitude.toStringAsFixed(4)},'
                '${bounds.northEast.longitude.toStringAsFixed(4)},'
                '${bounds.northEast.latitude.toStringAsFixed(4)}',
    };

    final uri = Uri.https(_host, _path, params);
    final response = await _client
        .get(
          uri,
          headers: const {
            'User-Agent': 'muevex-app/1.0 (demo)',
            'Accept': 'application/json',
            'Accept-Language': 'es-CO,es',
          },
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw GeocodingException(
        'El servicio de búsqueda respondió ${response.statusCode}',
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final features = (body['features'] as List?) ?? const [];
    final results = features
        .whereType<Map<String, dynamic>>()
        .map(LocationResult.fromPhoton)
        .where((r) =>
            r.coordinates.latitude != 0.0 || r.coordinates.longitude != 0.0)
        .toList();

    if (results.isNotEmpty) {
      _cache[key] = results;
      if (_cache.length > _cacheMaxEntries) {
        _cache.remove(_cache.keys.first);
      }
    }
    return results;
  }

  /// Clave de caché: consulta normalizada + zona (proximidad y viewbox)
  /// redondeados para que movimientos pequeños del mapa reutilicen resultados.
  String _cacheKey(String query, LatLng? proximity, LatLngBounds? bounds) {
    String zone;
    if (bounds != null) {
      zone = '${bounds.southWest.latitude.toStringAsFixed(1)}_'
          '${bounds.southWest.longitude.toStringAsFixed(1)}_'
          '${bounds.northEast.latitude.toStringAsFixed(1)}_'
          '${bounds.northEast.longitude.toStringAsFixed(1)}';
    } else if (proximity != null) {
      zone = '${proximity.latitude.toStringAsFixed(1)}_'
          '${proximity.longitude.toStringAsFixed(1)}';
    } else {
      zone = 'global';
    }
    return '${query.trim().toLowerCase()}|$zone';
  }

  void dispose() => _client.close();
}

class GeocodingException implements Exception {
  final String message;
  const GeocodingException(this.message);

  @override
  String toString() => message;
}