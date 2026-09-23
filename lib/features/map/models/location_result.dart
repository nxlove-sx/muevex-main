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
      if (statePart != null &&
          statePart.isNotEmpty &&
          statePart != cityPart)
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

  /// Normaliza un valor de Photon a texto, tolerando `num` y otros tipos.
  static String? _asString(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return value.toString();
  }
}