import 'package:geolocator/geolocator.dart';

/// Servicio de geolocalización para MUEVEX.
/// Proporciona la ubicación actual del usuario para el mapa en tiempo real.
///
/// Importante: el permiso de ubicación solo se debe solicitar en respuesta a
/// una acción del usuario (p. ej. tocar un botón), no al abrir la pantalla,
/// para evitar pantallas en blanco o peticiones sin contexto.
class LocationService {
  const LocationService._();

  /// Comprueba el estado del permiso SIN mostrar el diálogo del sistema.
  static Future<bool> isPermissionGranted() async {
    var serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Solicita el permiso de ubicación (muestra el diálogo del sistema).
  /// Devuelve `true` si se concedió.
  static Future<bool> requestPermission() async {
    var serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Devuelve la posición actual del dispositivo, o null si no hay permisos
  /// o no se pudo obtener. Recibe `requestIfNeeded` para pedir el diálogo
  /// solo cuando se invoca desde una interacción del usuario.
  static Future<Position?> getCurrentPosition(
      {bool requestIfNeeded = false}) async {
    final granted = requestIfNeeded
        ? await requestPermission()
        : await isPermissionGranted();
    if (!granted) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return position;
    } catch (_) {
      return null;
    }
  }

  /// Inicia un seguimiento continuo de la ubicación. El stream emite la
  /// posición actualizada en tiempo real. Solo llamar cuando el permiso ya
  /// está concedido.
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
  }
}
