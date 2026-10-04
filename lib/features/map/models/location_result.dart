import 'package:latlong2/latlong.dart';

/// Resultado de una búsqueda de lugar (geocoding/autocompletado).
///
/// Representa un lugar real devuelto por el servicio de búsqueda, con su
/// nombre, dirección formateada y coordenadas. Se usa como sugerencia en el
/// buscador de destinos y para centrar el mapa al seleccionar un resultado.
class LocationResult {
  final String name;
  final String? street;
  final String? houseNumber;
  final String? city;
  final String? state;
  final String? country;
  final String? postcode;
  final LatLng coordinates;
  final String osmType;
  final String osmId;

  const LocationResult({
    required this.name,
    this.street,
    this.houseNumber,
    this.city,
    this.state,
    this.country,
    this.postcode,
    required this.coordinates,
    this.osmType = '',
    this.osmId = '',
  });

  /// Línea secundaria legible: calle + ciudad + departamento.
  String get subtitle {
    final cityPart = city?.trim();
    final statePart = state?.trim();
    final parts = <String>[
      if (street != null && street!.trim().isNotEmpty) street!.trim(),
      if (cityPart != null && cityPart.isNotEmpty) cityPart,
      if (statePart != null && statePart.isNotEmpty && statePart != cityPart)
        statePart,
    ];
    final countryPart = country?.trim();
    if (countryPart != null &&
        countryPart.isNotEmpty &&
        !parts.contains(countryPart)) {
      parts.add(countryPart);
    }
    return parts.isEmpty ? 'Ubicación' : parts.take(3).join(', ');
  }

  /// Convierte una feature de Photon (Komoot) en un [LocationResult].
  ///
  /// Los valores de propiedades pueden venir como `String` o como `num`
  /// (por ejemplo `housenumber`, `postcode`), así que se normalizan con
  /// [_asString] en lugar de un cast directo.
  factory LocationResult.fromPhoton(Map<String, dynamic> feature) {
    final props = (feature['properties'] as Map?) ?? const {};
    final geometry = (feature['geometry'] as Map?) ?? const {};
    final coords = (geometry['coordinates'] as List?) ?? const [];
    final lon = coords.isNotEmpty ? (coords[0] as num).toDouble() : 0.0;
    final lat = coords.length > 1 ? (coords[1] as num).toDouble() : 0.0;

    final name = (_asString(props['name']) ?? '').trim();
    final street = (_asString(props['street']) ?? '').trim();
    final displayName = name.isNotEmpty
        ? name
        : street.isNotEmpty
            ? street
            : 'Ubicación';

    return LocationResult(
      name: displayName,
      street: _asString(props['street']),
      houseNumber: _asString(props['housenumber']),
      city: _asString(props['city']),
      state: _asString(props['state']),
      country: _asString(props['country']),
      postcode: _asString(props['postcode']),
      coordinates: LatLng(lat, lon),
      osmType: _asString(props['osm_type']) ?? '',
      osmId: _asString(props['osm_id']) ?? '',
    );
  }

  /// Convierte un candidato de `findAddressCandidates` (Esri) en un
  /// [LocationResult], o `null` si el candidato no sirve como destino.
  ///
  /// La dirección de Esri llega como texto plano, separada por comas:
  /// "Calle 10 30 20, Las Lomas No.1, Medellín, Antioquia". El primer
  /// fragmento es la calle con número (lo que va en la etiqueta del pin), los
  /// últimos son ciudad y departamento.
  ///
  /// Se descarta lo que no es un sitio concreto:
  ///  - score bajo: ESRI devuelve "Carrera" (82) o "Centro Comercial Carrera"
  ///    (81) en otra ciudad cuando la búsqueda está a medio escribir, mientras
  ///    que una dirección real baja 93-100.
  ///  - [Addr_type](https://developers.arcgis.com/rest/services/geocode/GeocodeService/overview.htm)
  ///    `Country` o `State`: "Colombia" no es un destino.
  static LocationResult? fromEsri(
    Map<String, dynamic> candidate, {
    double minScore = 90,
  }) {
    final score = (candidate['score'] as num?)?.toDouble() ?? 0;
    if (score < minScore) return null;

    final attrs = (candidate['attributes'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final addrType = (_asString(attrs['Addr_type']) ?? '').toLowerCase();
    if (addrType == 'country' || addrType == 'state') return null;

    final location = candidate['location'] as Map?;
    final lon = (location?['x'] as num?)?.toDouble();
    final lat = (location?['y'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    if (lat == 0 && lon == 0) return null;

    final match = _firstNonEmpty([
      _asString(attrs['Match_addr']),
      _asString(candidate['address']),
    ]);
    if (match == null) return null;

    var parts = match
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length > 1 && parts.last.toLowerCase() == 'colombia') {
      parts.removeLast();
    }
    if (parts.isEmpty) return null;

    // "Calle 10, Medellín, Antioquia" (3 partes) es un punto de interés con
    // ciudad; "Calle 10 # 30-20, Las Lomas, Medellín, Antioquia" (4+) sí trae
    // calle, así que solo ahí se usa la calle como subtítulo (si no, el
    // subtítulo repetiría el nombre tal cual).
    final isStreetAddress = parts.length >= 4;
    return LocationResult(
      name: parts.first,
      street: isStreetAddress ? parts.first : null,
      city: _firstNonEmpty([
        _asString(attrs['City']),
        if (parts.length >= 3) parts[parts.length - 2],
      ]),
      state: _firstNonEmpty([
        _asString(attrs['Region']),
        if (parts.length >= 2) parts.last,
      ]),
      postcode: _asString(attrs['Postal']),
      coordinates: LatLng(lat, lon),
    );
  }

  /// Primer texto no vacío de [values].
  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final trimmed = v?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// Normaliza un valor de Photon a texto, tolerando `num` y otros tipos.
  static String? _asString(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return value.toString();
  }
}
