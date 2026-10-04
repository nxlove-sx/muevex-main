import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:muevex/core/utils/money.dart';
import 'package:muevex/core/services/location_service.dart';
import 'package:muevex/core/services/tariff_codec.dart';
import 'package:muevex/core/services/tariff_engine.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/widgets/animations.dart';
import 'package:muevex/core/widgets/muevex_snackbar.dart';
import 'package:muevex/core/widgets/price_breakdown_sheet.dart';
import 'package:muevex/features/service/providers/service_providers.dart';
import 'package:muevex/features/map/models/location_result.dart';
import 'package:muevex/features/map/presentation/widgets/location_controls.dart';
import 'package:muevex/features/map/presentation/widgets/load_type_selector.dart';
import 'package:muevex/features/map/presentation/widgets/location_search_bar.dart';
import 'package:muevex/features/map/presentation/widgets/map_widget.dart';
import 'package:muevex/features/map/presentation/widgets/map_route_style.dart';
import 'package:muevex/features/map/presentation/widgets/origin_destination_selector.dart';
import 'package:muevex/features/map/presentation/widgets/search_results_panel.dart';
import 'package:muevex/features/map/providers/map_route_provider.dart';
import 'package:muevex/features/map/providers/map_search_provider.dart';

/// Centro por defecto del mapa cuando no hay ubicación ni permiso: Montería.
const LatLng _monteriaCenter = LatLng(8.7566, -75.8900);

/// Pantalla de mapa para solicitar transporte de muebles y cargas pequeñas.
///
/// Experiencia similar en concepto y calidad a las apps de transporte
/// modernas, pero con identidad propia de MUEVEX:
///  - Mapa oscuro (CartoDB dark sobre OSM) como elemento principal.
///  - Buscador flotante con autocompletado de lugares reales (Photon).
///  - Resultados ordenados por cercanía a la ubicación/área visible.
///  - Selección de origen y destino con marcador y animación de cámara.
///  - Panel inferior deslizable con el tipo de carga y resumen del viaje.
class RequestMapPage extends ConsumerStatefulWidget {
  const RequestMapPage({super.key});

  @override
  ConsumerState<RequestMapPage> createState() => _RequestMapPageState();
}

class _RequestMapPageState extends ConsumerState<RequestMapPage>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  StreamSubscription<Position>? _positionSub;

  /// Un **único** controlador para todas las animaciones de cámara.
  ///
  /// Antes se creaba uno nuevo por llamada a [_animateCameraTo] y se
  /// destruía el anterior. Con `SingleTickerProviderStateMixin` eso está
  /// prohibido: el mixin solo admite un ticker, y crear un segundo lanza
  /// `FlutterError` ("multiple tickers were created with single
  /// TickerProviderStateMixin"). Bastaba con pulsar "Mi ubicación" y luego
  /// elegir un destino para provocarlo.
  late final AnimationController _cameraAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  /// Tween de la cámara en curso. Se reasignan en cada [_animateCameraTo] y
  /// los lee el listener que se registra una sola vez en [initState].
  Animation<double>? _camLat;
  Animation<double>? _camLng;
  Animation<double>? _camZoom;

  LatLng? _userLocation;
  LatLng? _origin;
  String? _originName;
  LatLng? _destination;
  String? _destinationName;

  String _selectedLoadType = 'muebles';
  bool _locating = false;
  bool _searchOpen = false;
  bool _searchForOrigin = false;

  @override
  void initState() {
    super.initState();

    // Un solo listener para toda la vida de la pantalla: los tweens se
    // reasignan en cada _animateCameraTo, así que aquí no se toca la cámara.
    _cameraAnim.addListener(_onCameraTick);

    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocationFlow());
  }

  /// Aplica el estado actual de los tweens a la cámara.
  void _onCameraTick() {
    final lat = _camLat;
    final lng = _camLng;
    final zoom = _camZoom;
    if (lat == null || lng == null || zoom == null) return;
    _mapController.move(LatLng(lat.value, lng.value), zoom.value);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _cameraAnim
      ..removeListener(_onCameraTick)
      ..dispose();
    _sheetController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Ubicación y permisos
  // -------------------------------------------------------------------------

  /// Solicita el permiso de ubicación de forma proactiva al abrir la pantalla
  /// y, si se concede, fija el origen en la ubicación actual. Si el permiso
  /// está bloqueado o el GPS apagado, lo indica para resolverlo.
  Future<void> _initLocationFlow() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showSnack(
          'Activa el GPS de tu teléfono para usar tu ubicación como origen.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return;

    if (permission == LocationPermission.denied) {
      _showSnack(
          'Permiso de ubicación denegado. Puedes indicar tu origen con el buscador.');
      return;
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      _showSnack(
        'Permiso de ubicación bloqueado. Actívalo en Ajustes para usar "Mi ubicación".',
        settingsAction: true,
      );
      return;
    }

    await _fetchAndApplyLocation();
  }

  /// Aplica la posición actual como origen (y clima del mapa) al obtenerla.
  Future<void> _fetchAndApplyLocation({Position? given}) async {
    final position = given ??
        await LocationService.getCurrentPosition(requestIfNeeded: false);
    if (!mounted || position == null) return;

    debugPrint('MUEVEX location applied lat=${position.latitude} '
        'lng=${position.longitude} accuracy=${position.accuracy}');

    final point = LatLng(position.latitude, position.longitude);
    setState(() {
      _userLocation = point;
      _origin = point;
      _originName = 'Mi ubicación';
    });
    _writeOriginToForm(point);
    ref
        .read(mapSearchProvider.notifier)
        .updateContext(proximity: _userLocation);
    _animateCameraTo(point, zoom: 15);
    _startLiveTracking();
    _maybeRequestRoute();
  }

  void _startLiveTracking() {
    if (_positionSub != null) return;
    _positionSub = LocationService.getPositionStream().listen((pos) {
      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(pos.latitude, pos.longitude);
      });
    }, onError: (_) {});
  }

  /// "Usar mi ubicación": obtiene la posición (pide permiso si hace falta) y la
  /// aplica como origen. Si ya hay destino, recalcula la ruta automáticamente.
  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    final position =
        await LocationService.getCurrentPosition(requestIfNeeded: true);
    if (!mounted) return;
    setState(() => _locating = false);

    if (position != null) {
      await _fetchAndApplyLocation(given: position);
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      _showSnack(
          'Activa el GPS de tu teléfono para usar tu ubicación como origen.');
    } else {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        _showSnack(
          'Permiso de ubicación bloqueado. Actívalo en Ajustes.',
          settingsAction: true,
        );
      } else {
        _showSnack('No se pudo obtener tu ubicación. Reintenta.');
      }
    }
  }

  void _showSnack(String message, {bool settingsAction = false}) {
    if (!mounted) return;
    showMuevexSnackBar(
      context,
      message: message,
      icon: settingsAction ? Icons.settings_outlined : Icons.info_outline,
      isError: true,
      actionLabel: settingsAction ? 'Ajustes' : null,
      onAction: settingsAction ? () => Geolocator.openAppSettings() : null,
    );
  }

  void _writeOriginToForm(LatLng point) {
    final notifier = ref.read(serviceFormProvider.notifier);
    notifier.setOriginLat(point.latitude);
    notifier.setOriginLng(point.longitude);
  }

  void _writeDestinationToForm(LatLng point) {
    final notifier = ref.read(serviceFormProvider.notifier);
    notifier.setDestinationLat(point.latitude);
    notifier.setDestinationLng(point.longitude);
  }

  // -------------------------------------------------------------------------
  // Búsqueda de lugares
  // -------------------------------------------------------------------------

  void _openSearch({required bool forOrigin}) {
    setState(() {
      _searchOpen = true;
      _searchForOrigin = forOrigin;
    });
    ref.read(mapSearchProvider.notifier).reset();
    _searchController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    FocusScope.of(context).unfocus();
    ref.read(mapSearchProvider.notifier).reset();
    setState(() => _searchOpen = false);
  }

  void _onSearchChanged(String value) {
    final notifier = ref.read(mapSearchProvider.notifier);
    notifier.updateContext(
        proximity: _userLocation ?? _origin ?? _mapController.camera.center);
    notifier.onQueryChanged(value);
  }

  /// Aplica un resultado del buscador como origen o destino.
  void _selectResult(LocationResult result) {
    ref.read(mapSearchProvider.notifier).select(result);
    setState(() {
      if (_searchForOrigin) {
        _origin = result.coordinates;
        _originName = result.name;
        _writeOriginToForm(result.coordinates);
      } else {
        _destination = result.coordinates;
        _destinationName = result.name;
        _writeDestinationToForm(result.coordinates);
      }
    });
    setState(() => _searchOpen = false);
    FocusScope.of(context).unfocus();
    _animateCameraTo(result.coordinates, zoom: 16);
    _autoExpandSheet();
    _maybeRequestRoute();
  }

  void _retrySearch() {
    final notifier = ref.read(mapSearchProvider.notifier);
    notifier.onQueryChanged(_searchController.text);
  }

  // -------------------------------------------------------------------------
  // Ruta vial (OSRM)
  // -------------------------------------------------------------------------

  /// Solicita la ruta entre origen y destino. Sin alguno de los dos, la limpia.
  void _maybeRequestRoute({bool force = false}) {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) {
      if (!force) ref.read(mapRouteProvider.notifier).clear();
      return;
    }
    ref
        .read(mapRouteProvider.notifier)
        .requestRoute(origin: origin, destination: destination, force: force);
  }

  // -------------------------------------------------------------------------
  // Cámara
  // -------------------------------------------------------------------------

  /// Mueve la cámara suavemente (no brusco) hacia [target].
  void _animateCameraTo(LatLng target, {double zoom = 16}) {
    final start = _mapController.camera;
    final curved = CurvedAnimation(
      parent: _cameraAnim,
      curve: Curves.easeInOutCubic,
    );
    _camLat = Tween<double>(
      begin: start.center.latitude,
      end: target.latitude,
    ).animate(curved);
    _camLng = Tween<double>(
      begin: start.center.longitude,
      end: target.longitude,
    ).animate(curved);
    _camZoom = Tween<double>(begin: start.zoom, end: zoom).animate(curved);

    // Si ya había una animación en curso se reinicia desde el punto actual,
    // que es lo que espera el usuario al pulsar dos veces seguidas.
    _cameraAnim
      ..stop()
      ..forward(from: 0);
  }

  /// Encuadra la cámara (con animación suave) para ver la ruta completa,
  /// dejando espacio arriba para el selector y abajo para el panel.
  void _fitRouteToCamera(LatLngBounds bounds) {
    final fit = CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.fromLTRB(48, 120, 48, 300),
      maxZoom: 16,
    );
    try {
      final fitResult = fit.fit(_mapController.camera);
      debugPrint('MUEVEX camera fit → center=(${fitResult.center.latitude}, '
          '${fitResult.center.longitude}) zoom=${fitResult.zoom.toStringAsFixed(1)}');
      _animateCameraTo(
        fitResult.center,
        zoom: fitResult.zoom.clamp(3, kMapMaxZoom),
      );
    } catch (_) {
      // El mapa aún no está listo; la próxima interacción re-encuadra.
    }
  }

  void _zoomIn() {
    final camera = _mapController.camera;
    _mapController.move(camera.center, (camera.zoom + 1).clamp(3, kMapMaxZoom));
  }

  void _zoomOut() {
    final camera = _mapController.camera;
    _mapController.move(camera.center, (camera.zoom - 1).clamp(3, kMapMaxZoom));
  }

  void _onMapMoved(MapPosition position, bool hasGesture) {
    ref.read(mapSearchProvider.notifier).updateContext(
          proximity: _userLocation ?? _origin,
          bounds: position.bounds,
        );
  }

  /// Al tocar el mapa se define directamente el destino en ese punto.
  void _onMapTapped(LatLng point) {
    if (_searchOpen) {
      _closeSearch();
    }
    setState(() {
      _destination = point;
      _destinationName = null;
    });
    _writeDestinationToForm(point);
    _autoExpandSheet();
    _maybeRequestRoute();
  }

  void _autoExpandSheet() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sheetController.animateTo(
        0.46,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // -------------------------------------------------------------------------
  // Continuar
  // -------------------------------------------------------------------------

  void _onContinue() {
    final form = ref.read(serviceFormProvider);
    final hasOrigin =
        _origin != null || ((form['originLat'] as num?) ?? 0) != 0;
    final hasDestination =
        _destination != null || ((form['destinationLat'] as num?) ?? 0) != 0;

    if (!hasOrigin) {
      showMuevexSnackBar(
        context,
        message: 'Indica tu punto de origen',
        icon: Icons.trip_origin,
        isError: true,
      );
      return;
    }
    if (!hasDestination) {
      showMuevexSnackBar(
        context,
        message: 'Selecciona un destino',
        icon: Icons.location_on,
        isError: true,
      );
      return;
    }
    final notifier = ref.read(serviceFormProvider.notifier);
    notifier.setLoadType(_selectedLoadType);
    notifier.setOriginName(_originName ?? 'Mi ubicación');
    notifier.setDestinationName(_destinationName ?? 'Destino en el mapa');
    context.go('/service/create');
  }

  /// Eligió un tipo de carga en el resumen.
  ///
  /// Antes el selector solo cambiaba un `_selectedLoadType` local, que no se
  /// escribía en el formulario hasta pulsar "continuar". Como el precio se
  /// calcula del formulario, en esta pantalla **el selector no movía el
  /// precio**: se podía elegir "Electrodomésticos" y seguir viendo la tarifa
  /// de los muebles.
  ///
  /// Ahora escribe en el formulario en el acto. Si ya había artículos
  /// elegidos en el paso anterior, el precio los tiene por encima del tipo y
  /// el selector parecería no hacer nada, así que se quitan y se avisa: mejor
  /// un cambio dicho en voz alta que un control que no hace nada.
  void _onLoadTypeSelected(String type) {
    setState(() => _selectedLoadType = type);

    final notifier = ref.read(serviceFormProvider.notifier);
    notifier.setLoadType(type);

    final items = ref.read(serviceFormProvider)['items'] as List?;
    if (items != null && items.isNotEmpty) {
      notifier.setItems(const []);
      showMuevexSnackBar(
        context,
        message: 'Se quitó la lista de artículos al cambiar el tipo de carga',
        icon: Icons.inventory_2_outlined,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final searchState = ref.watch(mapSearchProvider);
    final routeState = ref.watch(mapRouteProvider);
    final form = ref.watch(serviceFormProvider);

    // Badge flotante de ruta: solo cuando el camino vial ya está listo.
    final route = routeState.route;
    final badgeKm = route?.distanceKm ?? 0.0;
    final badgeMinutes = (route?.durationSeconds ?? 0).toDouble() / 60.0;
    final badgePrice = route != null
        ? TarifaEngine.calcular(
            entradaDesdeFormulario(form, route.distanceKm),
          ).total
        : 0.0;
    final showBadge = routeState.status == RouteStatus.success &&
        route != null &&
        (_destination != null || ((form['destinationLat'] as num?) ?? 0) != 0);

    // Cuando la ruta se calcula, encuadra la cámara sobre la geometría vial.
    ref.listen<MapRouteState>(mapRouteProvider, (previous, next) {
      if (next.status != RouteStatus.success || next.route == null) return;
      if (next.route == previous?.route) return;
      final points = next.route!.points;
      if (points.length < 2) return;
      _fitRouteToCamera(LatLngBounds.fromPoints(points));
    });

    // Las alturas declaradas en cada `Marker` son el espacio que le da
    // flutter_map al pin; el `Marker` pone el borde INFERIOR de esa caja
    // exactamente sobre la coordenada. Los pins usan
    // `MainAxisAlignment.end` (ver `_OriginPin`/`_DestinationPin`) para que la
    // punta quede pegada a ese borde: si la etiqueta crece con el tamaño de
    // letra, crece hacia arriba y la punta no se mueve. Antes el `SizedBox`
    // de cada pin medía menos que su contenido y la punta quedaba 6 px fuera
    // del punto.
    final markers = <Marker>[
      if (_userLocation != null)
        Marker(
          point: _userLocation!,
          width: 30,
          height: 30,
          child: const _UserLocationDot(),
        ),
      if (_origin != null && _isCustomOrigin)
        Marker(
          key: ValueKey('origin-${_origin!.latitude}-${_origin!.longitude}'),
          point: _origin!,
          width: 44,
          height: 56,
          alignment: Alignment.bottomCenter,
          child: const _PinDropper(child: _OriginPin()),
        ),
      if (_destination != null)
        Marker(
          key: ValueKey('dest-${_destination!.latitude}'
              '-${_destination!.longitude}'),
          point: _destination!,
          width: 116,
          height: 96,
          alignment: Alignment.bottomCenter,
          child: _PinDropper(
            child: _DestinationPin(
              label: _destinationName ?? 'DESTINO',
            ),
          ),
        ),
    ];

    // Ruta vial real (OSRM) sobre las calles, con casing + gradiente y
    // chevrones que marcan el sentido de la marcha.
    final routePoints = routeState.route?.points ?? const <LatLng>[];
    final polylines = <Polyline>[
      if (routePoints.length > 1) ...buildRoutePolylines(routePoints),
    ];
    markers.addAll(routeFlowMarkers(routePoints));

    return Scaffold(
      backgroundColor: kMapBackgroundColor,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // ---- Mapa (elemento principal) ----
              TransportMap(
                controller: _mapController,
                initialCenter: _origin ?? _userLocation ?? _monteriaCenter,
                initialZoom: 14,
                markers: markers,
                polylines: polylines,
                onMapTapped: _onMapTapped,
                onMapMoved: _onMapMoved,
              ),

              // ---- Zona superior: selector origen/destino o buscador ----
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -0.12),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _searchOpen
                            ? LocationSearchBar(
                                key: const ValueKey('search'),
                                controller: _searchController,
                                focusNode: _searchFocus,
                                forOrigin: _searchForOrigin,
                                onChanged: _onSearchChanged,
                                onBack: _closeSearch,
                                onClear: () => _onSearchChanged(''),
                              )
                            : OriginDestinationSelector(
                                key: const ValueKey('selector'),
                                originName: _originName,
                                destinationName: _destinationName,
                                onTapOrigin: () => _openSearch(forOrigin: true),
                                onTapDestination: () =>
                                    _openSearch(forOrigin: false),
                                onUseMyLocation: _useCurrentLocation,
                                locating: _locating,
                              ),
                      ),
                      if (_searchOpen)
                        SearchResultsPanel(
                          state: searchState,
                          maxHeight: size.height * 0.44,
                          onSelect: _selectResult,
                          onRetry: _retrySearch,
                        ),
                    ],
                  ),
                ),
              ),

              // ---- Controles circulares (+ / - / mi ubicación) ----
              // Se anclan justo encima del panel inferior colapsado
              // (minChildSize 0.16) para no quedar flotando arriba de la
              // pantalla ni ocultos detrás de la hoja deslizable.
              Positioned(
                right: 14,
                bottom: constraints.maxHeight * 0.16 + 52,
                child: LocationControls(
                  locating: _locating,
                  onRecenter: _useCurrentLocation,
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                ),
              ),

              // ---- Badge flotante: distancia · tiempo · precio est. ----
              if (showBadge)
                Positioned(
                  left: 14,
                  right: 72,
                  bottom: constraints.maxHeight * 0.16 + 20,
                  child: _RouteInfoBadge(
                    distanceKm: badgeKm,
                    durationMinutes: badgeMinutes,
                    price: badgePrice,
                  ),
                ),

              // ---- Panel inferior deslizable ----
              if (!_searchOpen) _buildBottomSheet(size),
            ],
          );
        },
      ),
    );
  }

  bool get _isCustomOrigin {
    if (_origin == null || _userLocation == null) return false;
    return (_origin!.latitude - _userLocation!.latitude).abs() > 0.0001 ||
        (_origin!.longitude - _userLocation!.longitude).abs() > 0.0001;
  }

  Widget _buildBottomSheet(Size size) {
    final form = ref.watch(serviceFormProvider);
    final routeState = ref.watch(mapRouteProvider);
    final hasDestination =
        _destination != null || ((form['destinationLat'] as num?) ?? 0) != 0;

    // Distancia, duración y precio basados en la ruta vial real. Mientras la
    // ruta no esté lista se usan la distancia geodésica y su precio de
    // referencia para no dejar los campos en blanco durante la carga.
    final routeKm = routeState.route?.distanceKm ?? 0.0;
    final routeMinutes = routeState.route?.durationSeconds ?? 0.0;
    final needsHelp = (form['needsHelp'] as bool?) ?? false;
    final serviceFloors = (form['floors'] ?? 0) as int;
    final fallbackDistance = ref.watch(recommendedDistanceKmProvider);
    final shownKm = routeKm > 0 ? routeKm : fallbackDistance;
    final shownMinutes = routeMinutes > 0 ? (routeMinutes / 60) : 0.0;

    // UNA sola tarifa para el precio y para el desglose.
    //
    // Antes se calculaba dos veces: el precio con `entradaDesdeFormulario` (que
    // respalda al tipo de carga cuando no hay artículos) y el desglose con una
    // entrada armada a mano que solo miraba los artículos. Con la carga inicial
    // —artículos vacíos, que es justo como empieza esta pantalla— un servicio
    // de muebles se cotizaba en $55.000 y el desglose decía $25.000.
    final tarifaResumen = TarifaEngine.calcular(
      entradaDesdeFormulario(form, shownKm),
    );
    final shownPrice = tarifaResumen.total;
    debugPrint('MUEVEX summary status=${routeState.status.name} '
        'km=${shownKm.toStringAsFixed(3)} min=${shownMinutes.toStringAsFixed(1)} '
        'price=\$${shownPrice.toStringAsFixed(0)}');

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.20,
      minChildSize: 0.16,
      maxChildSize: 0.72,
      snap: true,
      snapSizes: const [0.16, 0.34, 0.60],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: MuevexTheme.surfaceOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black38, blurRadius: 20, offset: Offset(0, -4)),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              _SheetHandle(),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '¿Qué necesitas mover?',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 14),
                      LoadTypeSelector(
                        selected: _selectedLoadType,
                        onSelect: _onLoadTypeSelected,
                      ),
                      const SizedBox(height: 16),
                      if (hasDestination) ...[
                        const Divider(height: 24),
                        _TripSummary(
                          originName: _originName ?? 'Mi ubicación',
                          destinationName: _destinationName,
                          hasOrigin: _origin != null ||
                              ((form['originLat'] as num?) ?? 0) != 0,
                          distanceKm: shownKm,
                          durationMinutes: shownMinutes,
                          price: shownPrice,
                          tarifa: tarifaResumen,
                          serviceType: _selectedLoadType,
                          needsHelp: needsHelp,
                          floors: serviceFloors,
                          routeStatus: routeState.status,
                          routeError: routeState.error,
                          onRetryRoute: () => _maybeRequestRoute(force: true),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: MuevexTheme.secondaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _onContinue,
                            icon: const Icon(Icons.arrow_forward, size: 20),
                            label: const Text(
                              'Continuar',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        AnimatedPanel(
                          visible: true,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: MuevexTheme.primaryColor
                                  .withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.touch_app,
                                    size: 18, color: MuevexTheme.primaryColor),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Elige el destino en el mapa o con el '
                                    'buscador para ver el precio estimado.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF374151),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Fuente: Esri, Maxar, Earthstar Geographics · '
                          'Datos © OpenStreetMap contributors',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Marcadores
// ---------------------------------------------------------------------------

/// Píldora compacta sobre el mapa con la distancia, el tiempo y el precio
/// estimado de la ruta ya calculada (feedback sin abrir la hoja inferior).
class _RouteInfoBadge extends StatelessWidget {
  final double distanceKm;
  final double durationMinutes;
  final double price;

  const _RouteInfoBadge({
    required this.distanceKm,
    required this.durationMinutes,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
              color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            distanceKm > 0
                ? '${distanceKm.toStringAsFixed(1)} km · '
                    '${durationMinutes.round()} min'
                : 'Calculando ruta…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (price > 0) ...[
            const SizedBox(height: 2),
            Text(
              'Precio est. ${moneyConIva(price)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: MuevexTheme.secondaryColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserLocationDot extends StatelessWidget {
  const _UserLocationDot();

  @override
  Widget build(BuildContext context) {
    return const PulsingHalo(
      icon: Icons.my_location,
      color: Color(0xFF4D9FFF),
      size: 20,
      duration: Duration(milliseconds: 1600),
    );
  }
}

/// Animación de "caída" al colocar un pin (origen o destino). Al cambiar la
/// coordenada, el [Marker] se recrea con una [Key] distinta y la animación
/// vuelve a reproducirse; al mover el mapa se conserva (misma key).
class _PinDropper extends StatelessWidget {
  final Widget child;

  const _PinDropper({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.35, end: 1.0),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: child,
    );
  }
}

class _OriginPin extends StatelessWidget {
  const _OriginPin();

  @override
  Widget build(BuildContext context) {
    // Sin `SizedBox` propio: el `Marker` da el tamaño exacto (44x56) y
    // `MainAxisAlignment.end` ancla la punta a la coordenada.
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: MuevexTheme.successColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 6),
            ],
          ),
          child: const Icon(Icons.trip_origin, color: Colors.white, size: 18),
        ),
        const CustomPaint(
          size: Size(12, 8),
          painter: _PinTailPainter(MuevexTheme.successColor),
        ),
      ],
    );
  }
}

class _DestinationPin extends StatelessWidget {
  final String label;

  const _DestinationPin({required this.label});

  @override
  Widget build(BuildContext context) {
    // Etiqueta arriba, círculo y punta abajo: la punta es lo último del
    // Column, así que con `MainAxisAlignment.end` cae exactamente sobre la
    // coordenada (borde inferior de la caja del `Marker`).
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 110),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [MuevexTheme.secondaryColor, Color(0xFFFF8F5F)],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 8),
            ],
          ),
          child: const Icon(Icons.place_rounded, color: Colors.white, size: 22),
        ),
        const CustomPaint(
          size: Size(14, 9),
          painter: _PinTailPainter(MuevexTheme.secondaryColor),
        ),
      ],
    );
  }
}

/// Triángulo que apunta hacia la coordenada real del marcador.
class _PinTailPainter extends CustomPainter {
  final Color color;
  const _PinTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PinTailPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Panel inferior
// ---------------------------------------------------------------------------

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _TripSummary extends StatelessWidget {
  final String originName;
  final String? destinationName;
  final bool hasOrigin;
  final double distanceKm;
  final double durationMinutes;
  final double price;

  /// La tarifa ya calculada de la que sale [price]. El desglose se pinta desde
  /// aquí y no desde una segunda cuenta, para que no puedan discrepar.
  final Tarifa tarifa;

  final String serviceType;
  final bool needsHelp;
  final int floors;
  final RouteStatus routeStatus;
  final String? routeError;
  final VoidCallback onRetryRoute;

  const _TripSummary({
    required this.originName,
    required this.destinationName,
    required this.hasOrigin,
    required this.distanceKm,
    required this.durationMinutes,
    required this.price,
    required this.tarifa,
    required this.serviceType,
    required this.needsHelp,
    required this.floors,
    required this.routeStatus,
    required this.routeError,
    required this.onRetryRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.trip_origin,
                size: 18, color: MuevexTheme.successColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasOrigin ? originName : 'Sin origen',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on,
                size: 18, color: MuevexTheme.secondaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                destinationName ?? 'Destino',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (routeStatus == RouteStatus.loading) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Calculando la mejor ruta por las calles…',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                  ),
                ),
              ],
            ),
          ),
        ] else if (routeStatus == RouteStatus.error) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 16, color: MuevexTheme.errorColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    routeError ?? 'No se pudo calcular la ruta.',
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF6B7280)),
                  ),
                ),
                TextButton(
                  onPressed: onRetryRoute,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text(
                    'Reintentar',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: MuevexTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: _SummaryMetric(
                icon: Icons.route_outlined,
                label: 'Distancia',
                value: distanceKm > 0
                    ? '${distanceKm.toStringAsFixed(1)} km'
                    : '--',
              ),
            ),
            Expanded(
              child: _SummaryMetric(
                icon: Icons.schedule_outlined,
                label: 'Tiempo est.',
                value: durationMinutes > 0
                    ? '${durationMinutes.round()} min'
                    : '--',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SummaryMetric(
                icon: Icons.sell_outlined,
                label: 'Precio est.',
                value: price > 0 ? moneyConIva(price) : '--',
                highlight: true,
              ),
            ),
            Expanded(
              child: _SummaryMetric(
                icon: Icons.local_shipping_outlined,
                label: 'Vehículo',
                value: 'Motocarro',
              ),
            ),
          ],
        ),
        if (price > 0) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showPriceBreakdownSheet(context, tarifa: tarifa),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.receipt_long_outlined,
                  size: 15, color: MuevexTheme.primaryColor),
              label: const Text(
                'Ver desglose del precio',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: MuevexTheme.primaryColor,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? MuevexTheme.secondaryColor.withValues(alpha: 0.1)
            : const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18,
              color: highlight
                  ? MuevexTheme.secondaryColor
                  : MuevexTheme.primaryColor),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, color: MuevexTheme.secondaryTextOf(context)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: highlight
                  ? MuevexTheme.secondaryColor
                  : const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}
