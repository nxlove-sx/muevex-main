import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Centro por defecto del mapa: Montería, Córdoba (Colombia).
const LatLng _monteriaCenter = LatLng(8.7566, -75.8900);

/// Widget de mapa interactivo para elegir el origen y destino de un servicio.
class MapPointPicker extends StatefulWidget {
  /// Coordenada inicial del centro del mapa.
  final LatLng initialCenter;

  /// Punto de origen seleccionado. Null si aún no se ha elegido.
  final LatLng? origin;

  /// Punto de destino seleccionado. Null si aún no se ha elegido.
  final LatLng? destination;

  /// Ubicación en tiempo real del usuario (GPS). Se muestra como marcador azul.
  final LatLng? userLocation;

  /// Callback cuando el usuario selecciona un punto en el mapa.
  final void Function(LatLng point)? onPointSelected;

  const MapPointPicker({
    super.key,
    this.initialCenter = _monteriaCenter,
    this.origin,
    this.destination,
    this.userLocation,
    this.onPointSelected,
  });

  @override
  State<MapPointPicker> createState() => _MapPointPickerState();
}

class _MapPointPickerState extends State<MapPointPicker> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MapPointPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cuando cambian los puntos, encuadrar automáticamente la ruta/origen.
    final route =
        widget.origin != null && widget.destination != null;
    if (route && (oldWidget.origin != widget.origin ||
        oldWidget.destination != widget.destination)) {
      _fitBounds([widget.origin!, widget.destination!]);
    } else if (!route && widget.origin != null &&
        oldWidget.origin != widget.origin) {
      _fitPoint(widget.origin!);
    } else if (widget.origin == null && widget.destination == null &&
        widget.userLocation != null &&
        oldWidget.userLocation != widget.userLocation) {
      _fitPoint(widget.userLocation!);
    }
  }

  void _fitPoint(LatLng point) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(point, 14);
    });
  }

  void _fitBounds(List<LatLng> points) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(CameraFit.bounds(
          bounds: bounds, padding: const EdgeInsets.all(56)));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determinar el centro del mapa: usar el origen si existe, sino la ubicación
    // del usuario (GPS), sino el centro inicial.
    final center = widget.origin ?? widget.userLocation ?? widget.initialCenter;

    final markers = <Marker>[
      if (widget.userLocation != null)
        Marker(
          point: widget.userLocation!,
          width: 28,
          height: 28,
          child: const _UserLocationMarker(),
        ),
      if (widget.origin != null)
        Marker(
          point: widget.origin!,
          width: 42,
          height: 42,
          child: const _OriginMarker(),
        ),
      if (widget.destination != null)
        Marker(
          point: widget.destination!,
          width: 42,
          height: 42,
          child: const _DestinationMarker(),
        ),
    ];

    final polylines = <Polyline>[
      if (widget.origin != null && widget.destination != null)
        Polyline(
          points: [widget.origin!, widget.destination!],
          color: MuevexTheme.primaryColor,
          strokeWidth: 4,
        ),
    ];

    return Container(
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MuevexTheme.primaryColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
              minZoom: 3,
              onTap: (tapPosition, point) {
                widget.onPointSelected?.call(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.muevex',
              ),
              PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
            ],
          ),
          // Indicador superior de estado
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app,
                      size: 18, color: MuevexTheme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.origin == null
                          ? 'Toca el mapa para elegir el ORIGEN'
                          : widget.destination == null
                              ? 'Toca el mapa para elegir el DESTINO'
                              : 'Ruta seleccionada, de origen a destino',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginMarker extends StatelessWidget {
  const _OriginMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          color: MuevexTheme.successColor,
          shape: BoxShape.circle,
          border: Border.fromBorderSide(
              BorderSide(color: Colors.white, width: 2)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: const Icon(Icons.trip_origin, color: Colors.white, size: 16),
      ),
    );
  }
}

class _DestinationMarker extends StatelessWidget {
  const _DestinationMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          color: MuevexTheme.errorColor,
          shape: BoxShape.circle,
          border: Border.fromBorderSide(
              BorderSide(color: Colors.white, width: 2)),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: const Icon(Icons.location_on, color: Colors.white, size: 16),
      ),
    );
  }
}

class _UserLocationMarker extends StatelessWidget {
  const _UserLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x334D9FFF),
          border: Border.fromBorderSide(
            BorderSide(color: MuevexTheme.primaryLight, width: 3),
          ),
        ),
        child:
            const Icon(Icons.my_location, color: MuevexTheme.primaryLight, size: 14),
      ),
    );
  }
}
