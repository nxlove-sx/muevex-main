import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// `latlong2` define su propia clase `Path` (de rutas geográficas) que choca con
// `dart:ui`'s `Path` de dibujo, así que se oculta del import.
import 'package:latlong2/latlong.dart' hide Path;

import 'package:muevex/features/map/data/muevex_tile_cache.dart';

/// Proveedor de mapas: **Esri World Dark Gray Canvas** (mapa oscuro).
///
/// NOTA: la versión anterior usaba CartoDB dark (`basemaps.cartocdn.com`).
/// A finales de agosto de 2026 CARTO cambió su política y ahora sirve sus
/// teselas raster SIN API key con una marca de agua "API KEY REQUIRED"
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

/// Fondo del mapa mientras cargan las teselas y color del estilo oscuro.
const Color kMapBackgroundColor = Color(0xFF141A2E);

/// Mapa oscuro con identidad MUEVEX para la pantalla de solicitar transporte.
///
/// Es responsabilidad de la pantalla entregar los [markers] y [polylines];
/// este widget solo se encarga de renderizar el mapa, de forma que el cambio
/// de texto del buscador no reconstruye el mapa completo.
///
/// Mejoras de rendimiento y robustez sobre la versión anterior:
///   - **Caché en memoria y disco** de las teselas ([MuevexTileCache]): el
///     mapa se dibuja al instante la segunda vez y funciona sin conexión en
///     las zonas ya vistas. Antes se redescargaba todo en cada visita.
///   - **Atribución de Esri** visible, que su licencia exige y que faltaba.
///   - **Barra de escala**, para saber cuánto abarca el mapa que se ve.
///   - **Tesela de repuesto** cuando una petición falla, en lugar del icono
///     de imagen rota de Flutter.
///   - **Overlay de error** si fallan muchas teselas, con botón de reintento.
class TransportMap extends StatefulWidget {
  final MapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final void Function(LatLng point)? onMapTapped;
  final void Function(MapPosition position, bool hasGesture)? onMapMoved;

  /// Muestra la atribución de Esri. Su licencia la exige: no se debe desactivar
  /// sin sustituirla por otra atribución equivalente.
  final bool showAttribution;

  /// Muestra la barra de escala en una esquina.
  final bool showScaleBar;

  const TransportMap({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    required this.markers,
    this.polylines = const [],
    this.onMapTapped,
    this.onMapMoved,
    this.showAttribution = true,
    this.showScaleBar = true,
  });

  @override
  State<TransportMap> createState() => _TransportMapState();
}

class _TransportMapState extends State<TransportMap> {
  int _tileErrorCount = 0;
  bool _showingErrorOverlay = false;

  @override
  void initState() {
    super.initState();
    // La poda del caché de disco recorre el sistema de archivos. Llamarla desde
    // build la ejecutaba en cada reconstrucción (y esta pantalla se
    // reconstruye por cada fix de GPS y por cada frame de gesto del mapa), así
    // que era I/O de disco dentro de la fase de pintado.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => MuevexTileCache.instance.pruneDiskIfNeeded(),
    );
  }

  void _onTileError(TileImage tile, Object error, StackTrace? stack) {
    debugPrint('MUEVEX: falló la tesela ${tile.coordinates.key} ($error)');
    // `errorTileCallback` lo invoca la capa de teselas de flutter_map, que
    // sigue pidiendo teselas aunque el widget se haya retirado del árbol: los
    // errores llegan con retardo, tras el dispose. Sin esta guarda, una
    // conexión mala (justo cuando más errores hay) provoca
    // "setState() called after dispose()".
    if (!mounted) return;
    setState(() {
      _tileErrorCount++;
      if (_tileErrorCount > 5 && !_showingErrorOverlay) {
        _showingErrorOverlay = true;
      }
    });
  }

  void _retryTiles() {
    MuevexTileCache.instance.clearMemory();
    setState(() {
      _tileErrorCount = 0;
      _showingErrorOverlay = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: widget.controller,
          options: MapOptions(
            initialCenter: widget.initialCenter,
            initialZoom: widget.initialZoom,
            minZoom: 3,
            maxZoom: kMapMaxZoom,
            backgroundColor: kMapBackgroundColor,
            onTap: (tapPosition, point) => widget.onMapTapped?.call(point),
            onPositionChanged: widget.onMapMoved,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.drag |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: kEsriDarkBaseTileUrl,
              userAgentPackageName: 'com.example.muevex',
              tileProvider: kMuevexTileProvider,
              keepBuffer: 6,
              panBuffer: 2,
              maxNativeZoom: 16,
              errorImage: kFallbackTileImage,
              errorTileCallback: _onTileError,
            ),
            TileLayer(
              urlTemplate: kEsriDarkReferenceTileUrl,
              userAgentPackageName: 'com.example.muevex',
              tileProvider: kMuevexTileProvider,
              keepBuffer: 6,
              errorImage: kFallbackTileImage,
              errorTileCallback: _onTileError,
            ),
            PolylineLayer(polylines: widget.polylines),
            MarkerLayer(markers: widget.markers),
            if (widget.showScaleBar) const MuevexScaleBar(),
            if (widget.showAttribution) const _EsriAttribution(),
          ],
        ),
        if (_showingErrorOverlay)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: kMapBackgroundColor.withValues(alpha: 0.9),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.map_outlined,
                          size: 64,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No se pueden cargar los mapas',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Verifica tu conexión a internet.\nSe intentaron $_tileErrorCount cargas de teselas.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _retryTiles,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F63FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EsriAttribution extends StatelessWidget {
  const _EsriAttribution();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xB3101626),
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              'Esri · HERE · Garmin · © OpenStreetMap',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MuevexScaleBar extends StatelessWidget {
  static const double _maxWidth = 92;
  const MuevexScaleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final metresPerPixel = _metresPerPixel(camera);
    if (metresPerPixel <= 0) return const SizedBox.shrink();

    final target = metresPerPixel * _maxWidth;
    final nice = _niceDistance(target);
    final barWidth = (nice / metresPerPixel).clamp(24.0, _maxWidth);

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xB3101626),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: barWidth,
                  height: 4,
                  child: CustomPaint(painter: _ScaleBarPainter()),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDistance(nice),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double _metresPerPixel(MapCamera camera) {
    const step = 0.01;
    final origin = LatLng(camera.center.latitude, camera.center.longitude);
    final target =
        LatLng(camera.center.latitude, camera.center.longitude + step);
    final p1 = camera.project(origin, camera.zoom);
    final p2 = camera.project(target, camera.zoom);
    final pixels = (p2.x - p1.x).abs();
    if (pixels <= 0) return 0;
    final metres = const Distance().as(LengthUnit.Meter, origin, target);
    return metres / pixels;
  }

  static double _niceDistance(double metres) {
    final magnitude = _pow10((metres.abs()).abs() < 1e-9 ? 1e-9 : metres.abs());
    final normalised = metres / magnitude;
    final double step;
    if (normalised >= 5)
      step = 5;
    else if (normalised >= 2)
      step = 2;
    else
      step = 1;
    return step * magnitude;
  }

  static double _pow10(double value) {
    var exponent = 0;
    var scaled = value;
    while (scaled >= 10) {
      scaled /= 10;
      exponent++;
    }
    while (scaled < 1) {
      scaled *= 10;
      exponent--;
    }
    return _exp10(exponent);
  }

  static double _exp10(int exponent) {
    var result = 1.0;
    var n = exponent.abs();
    while (n > 0) {
      result *= 10;
      n--;
    }
    return exponent < 0 ? 1 / result : result;
  }

  static String _formatDistance(double metres) {
    if (metres >= 1000) {
      final km = metres / 1000;
      return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
    }
    return '${metres.round()} m';
  }
}

class _ScaleBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, size.height - 0.7)
      ..lineTo(size.width, size.height - 0.7)
      ..moveTo(0, 0)
      ..lineTo(0, size.height)
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScaleBarPainter oldDelegate) => false;
}
