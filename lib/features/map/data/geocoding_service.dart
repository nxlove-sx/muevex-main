import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:muevex/features/map/models/location_result.dart';

/// Servicio de búsqueda/geocodificación de lugares para MUEVEX.
///
/// Proveedor principal: **Esri World Geocoding Service** (el mismo que los
/// tiles del mapa). No requiere API key.
///
/// Por qué ESRI y no Photon (medido contra el servicio real, 02/10/2026):
///  - "Calle 10 # 30-20, Medellín": Photon **no devuelve nada**; ESRI devuelve
///    el punto exacto (score 100).
///  - "Carrera 70 # 1-50, Medellín": Photon devuelve "Estación EnCicla UPB",
///    o sea un punto cualquiera de la carrera; ESRI devuelve la dirección.
///  - ESRI con el campo suelto `text=` es inútil para búsquedas parciales
///    ("carrera 70" → "Colombia"), por eso se manda siempre `SingleLine`
///    junto con `countryCode=CO`.
///
/// Photon queda **solo como respaldo**: si ESRI no devuelve nada, se consulta
/// Photon para que el buscador nunca se quede muerto (ESRI tiene cuota por IP).
/// Los resultados de Photon son menos precisos; por eso van detrás de los de
/// ESRI y no se mezclan.
class GeocodingService {
  static const String _esriHost = 'geocode.arcgis.com';
  static const String _esriPath =
      '/arcgis/rest/services/World/GeocodeServer/findAddressCandidates';

  static const String _photonHost = 'photon.komoot.io';
  static const String _photonPath = '/api/';

  /// MUEVEX solo opera en Colombia. Sin esto ESRI mezcla resultados de otros
  /// países con nombres parecidos.
  static const String _countryCode = 'CO';

  /// Corta los candidatos que no son un sitio concreto. Medido el 02/10/2026:
  /// una dirección real con número baja 93-100 ("Carrera 3 # 12-40, Montería"
  /// = 93) y la basura que devuelve cuando la búsqueda está a medio escribir
  /// ("Carrera", "Centro Comercial Carrera" en otra ciudad) baja 81-83. Con 90
  /// se descarta la basura; mejor "no encontré" que un pin en otra ciudad.
  static const double _minScore = 90;

  /// Dos candidatos a menos de esto son el mismo lugar: ESRI devuelve la misma
  /// esquina 3-4 veces con coordenadas que difieren en metros.
  static const double _dedupeMeters = 60;

  /// Radio para considerar "cercano" al usuario al ordenar. Los lejanos se
  /// siguen mostrando, pero al final: si el destino es en otra ciudad tiene
  /// que aparecer.
  static const double _nearRadiusMeters = 120000;

  /// Radio de preferencia enviado a ESRI (metros). Es un sesgo, no un filtro:
  /// ESRI lo usa para desempatar candidatos con el mismo score.
  static const int _preferenceRadiusMeters = 50000;

  final http.Client _client = http.Client();

  /// Memoria caché por consulta + zona, para no repetir llamadas mientras el
  /// usuario escribe (item 17: rendimiento).
  final Map<String, List<LocationResult>> _cache = {};
  static const int _cacheMaxEntries = 24;

  static const Distance _distance = Distance();

  static const Map<String, String> _headers = {
    'User-Agent': 'muevex-app/1.0 (demo)',
    'Accept': 'application/json',
    'Accept-Language': 'es-CO,es',
  };

  /// Busca lugares mientras el usuario escribe.
  ///
  /// [query] texto a buscar (mínimo 3 caracteres, lo filtra el provider).
  /// [proximity] punto de referencia (ubicación del usuario o centro del mapa)
  /// para que lo cercano salga primero. [limit] número de sugerencias.
  ///
  /// Antes se filtraba por el área visible del mapa ([bbox] de Photon); eso
  /// impedía buscar destinos fuera de lo que se veía en pantalla, así que se
  ///quitó: la prioridad la da [proximity], no un recorte.
  Future<List<LocationResult>> search(
    String query, {
    LatLng? proximity,
    int limit = 6,
  }) async {
    final key = _cacheKey(query, proximity);
    final cached = _cache[key];
    if (cached != null) return cached;

    Object? esriError;
    var results = const <LocationResult>[];

    try {
      results = _prepare(
        await _searchEsri(query, proximity: proximity),
        proximity,
        limit,
      );
    } catch (e) {
      esriError = e;
      debugPrint('MUEVEX geocode ESRI [$query]: ${e.runtimeType}: $e');
    }

    if (results.isEmpty) {
      try {
        results = _prepare(
          await _searchPhoton(query, proximity: proximity, limit: limit),
          proximity,
          limit,
        );
      } catch (e) {
        debugPrint('MUEVEX geocode Photon [$query]: ${e.runtimeType}: $e');
      }
    }

    // Los dos proveedores fallaron: no es "no hay resultados", es un fallo de
    // red. La UI distingue los dos casos, así que no se debe mentir.
    if (results.isEmpty && esriError != null) {
      throw GeocodingException('No se pudo buscar. Revisa tu conexión.');
    }

    if (results.isNotEmpty) {
      _cache[key] = results;
      if (_cache.length > _cacheMaxEntries) {
        _cache.remove(_cache.keys.first);
      }
    }
    return results;
  }

  /// Consulta el geocodificador de ESRI (`findAddressCandidates`).
  Future<List<LocationResult>> _searchEsri(
    String query, {
    LatLng? proximity,
  }) async {
    final params = <String, String>{
      'SingleLine': query,
      'f': 'json',
      'outSR': '4326',
      'langCode': 'es',
      'maxLocations': '8',
      'outFields':
          'Match_addr,Addr_type,City,Region,Neighborhood,Postal,Country',
      'countryCode': _countryCode,
      if (proximity != null) ...{
        'location': '${proximity.longitude.toStringAsFixed(6)},'
            '${proximity.latitude.toStringAsFixed(6)}',
        'distance': '$_preferenceRadiusMeters',
      },
    };

    final uri = Uri.https(_esriHost, _esriPath, params);
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw GeocodingException(
        'El servicio de búsqueda respondió ${response.statusCode}',
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final candidates = (body['candidates'] as List?) ?? const [];
    return candidates
        .whereType<Map<String, dynamic>>()
        .map((c) => LocationResult.fromEsri(c, minScore: _minScore))
        .whereType<LocationResult>()
        .toList();
  }

  /// Respaldo: Photon (Komoot). Útil para puntos de interés y nombres de
  /// lugares, flojo para direcciones con número.
  Future<List<LocationResult>> _searchPhoton(
    String query, {
    LatLng? proximity,
    int limit = 6,
  }) async {
    final params = <String, String>{
      'q': query,
      'limit': '$limit',
      if (proximity != null) 'lat': proximity.latitude.toStringAsFixed(4),
      if (proximity != null) 'lon': proximity.longitude.toStringAsFixed(4),
    };

    final uri = Uri.https(_photonHost, _photonPath, params);
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw GeocodingException(
        'El servicio de búsqueda respondió ${response.statusCode}',
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final features = (body['features'] as List?) ?? const [];
    return features
        .whereType<Map<String, dynamic>>()
        .map(LocationResult.fromPhoton)
        .where((r) =>
            r.coordinates.latitude != 0.0 || r.coordinates.longitude != 0.0)
        .toList();
  }

  /// Quita duplicados y ordena por relevancia para [proximity].
  List<LocationResult> _prepare(
    List<LocationResult> raw,
    LatLng? proximity,
    int limit,
  ) {
    final unique = <LocationResult>[];
    for (final r in raw) {
      final samePlace = unique.any((u) =>
          u.name.toLowerCase() == r.name.toLowerCase() &&
          _distance.as(LengthUnit.Meter, u.coordinates, r.coordinates) <=
              _dedupeMeters);
      if (!samePlace) unique.add(r);
    }

    if (proximity != null) {
      unique.sort((a, b) {
        final da = _distance.as(LengthUnit.Meter, proximity, a.coordinates);
        final db = _distance.as(LengthUnit.Meter, proximity, b.coordinates);
        final aNear = da <= _nearRadiusMeters;
        final bNear = db <= _nearRadiusMeters;
        if (aNear != bNear) return aNear ? -1 : 1;
        return da.compareTo(db);
      });
    }
    return unique.take(limit).toList();
  }

  /// Clave de caché: consulta normalizada + zona, redondeada para que
  /// movimientos pequeños del mapa reutilicen resultados.
  String _cacheKey(String query, LatLng? proximity) {
    final zone = proximity == null
        ? 'global'
        : '${proximity.latitude.toStringAsFixed(1)}_'
            '${proximity.longitude.toStringAsFixed(1)}';
    return '${query.trim().toLowerCase()}|$zone';
  }

  void dispose() => _client.close();

  /// Geocodificación inversa: coordenadas → dirección legible.
  ///
  /// Usa **Esri World Geocoding Service** (mismo proveedor que los tiles del mapa).
  /// No requiere API key para uso básico. Devuelve una cadena tipo
  /// "Calle 42A, Los Conquistadores, Medellín" o `null` si falla.
  Future<String?> reverseGeocode(LatLng point) async {
    // Esri reverseGeocode: location=lon,lat&f=json&outSR=4326
    final uri = Uri.https(
      'geocode.arcgis.com',
      '/arcgis/rest/services/World/GeocodeServer/reverseGeocode',
      {
        'location':
            '${point.longitude.toStringAsFixed(6)},${point.latitude.toStringAsFixed(6)}',
        'f': 'json',
        'outSR': '4326',
        'langCode': 'es',
      },
    );

    try {
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'muevex-app/1.0 (demo)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final address = body['address'] as Map<String, dynamic>?;

      if (address == null) return null;

      // Construye "Calle, Barrio, Ciudad" evitando nulos y duplicados
      final parts = <String>[];
      final add = (String? v) {
        if (v != null && v.isNotEmpty && !parts.contains(v)) parts.add(v);
      };
      add(address['Address'] as String?); // "Carrera 63B 40 35"
      add(address['Neighborhood'] as String?); // "Los Conquistadores"
      add(address['Subregion'] as String?); // a veces el barrio
      add(address['City'] as String?); // "Medellín"
      // add(address['Region'] as String?);     // "Antioquia" → muy genérico

      if (parts.isEmpty) return null;
      return parts.join(', ');
    } catch (_) {
      return null;
    }
  }
}

class GeocodingException implements Exception {
  final String message;
  const GeocodingException(this.message);

  @override
  String toString() => message;
}
