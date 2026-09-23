import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Proveedor de mapas: **Esri World Dark Gray Canvas** (mapa oscuro).
///
/// NOTA: la versión anterior usaba CartoDB dark (`basemaps.cartocdn.com`).
/// A finales de agosto de 2026 CARTO cambió su política y ahora sirve sus
/// tiles raster SIN API key con una marca de agua "API KEY REQUIRED"
/// dibujada encima (https://carto.com/basemaps/apikey). Para no depender de
/// ninguna llave, MUEVEX usa el basemap público de Esri:
///   https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer
///
/// Es un servicio gratuito y sin API key (solo requiere atribución). Se
/// combinan dos capas:
///   - Base: lienzo oscuro (calles y manzanas) + texto de referencia (nombres
///     de vías, ciudades) para buena legibilidad sobre fondo oscuro.
const String kEsriDarkBaseTileUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/'
    'World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
const String kEsriDarkReferenceTileUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/'
    'World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}';

/// Zoom máximo que sirve el basemap oscuro de Esri (16).
const double kMapMaxZoom = 16.0;

/// Fondo del mapa mientras cargan los tiles y color general del estilo oscuro.
const Color kMapBackgroundColor = Color(0xFF141A2E);

/// Mapa oscuro con identidad MUEVEX para la pantalla de solicitar transporte.
///
/// Es responsabilidad de la pantalla entregar los [markers] y [polylines];
/// este widget solo se encarga de renderizar el mapa, de forma que el cambio
/// de texto del buscador no reconstruye el mapa completo (item 13 y 17).
class TransportMap extends StatelessWidget {
  final MapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final void Function(LatLng point)? onMapTapped;
  final void Function(MapPosition position, bool hasGesture)? onMapMoved;

  const TransportMap({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.markers,
    this.polylines = const [],
    this.initialZoom = 14,
    this.onMapTapped,
    this.onMapMoved,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        minZoom: 3,
        maxZoom: kMapMaxZoom,
        backgroundColor: kMapBackgroundColor,
        onTap: (tapPosition, point) => onMapTapped?.call(point),
        onPositionChanged: onMapMoved,
      ),
      children: [
        TileLayer(
          urlTemplate: kEsriDarkBaseTileUrl,
          userAgentPackageName: 'com.example.muevex',
          tileProvider: NetworkTileProvider(),
          keepBuffer: 6,
          panBuffer: 2,
        ),
        TileLayer(
          urlTemplate: kEsriDarkReferenceTileUrl,
          userAgentPackageName: 'com.example.muevex',
          tileProvider: NetworkTileProvider(),
          keepBuffer: 6,
        ),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }
}