import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:muevex/core/utils/money.dart';
import 'package:muevex/core/models/service_model.dart';
import 'package:muevex/core/models/payment_model.dart';
import 'package:muevex/core/supabase/supabase_client.dart' as api;
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/widgets/animations.dart';
import 'package:muevex/core/widgets/muevex_app_bar.dart';
import 'package:muevex/core/widgets/muevex_snackbar.dart';
import 'package:muevex/core/widgets/state_views.dart';
import 'package:muevex/features/customer/providers/customer_providers.dart';
import 'package:muevex/features/map/data/route_service.dart';
import 'package:muevex/features/map/presentation/widgets/map_pins.dart';
import 'package:muevex/features/map/presentation/widgets/map_route_style.dart';
import 'package:muevex/features/map/presentation/widgets/map_widget.dart' as mw;

class MapScreen extends ConsumerStatefulWidget {
  final String serviceId;

  const MapScreen({
    super.key,
    required this.serviceId,
  });

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  Service? _service;
  bool _loading = true;
  String? _error;
  LatLng? _driverLocation;
  double _driverHeading = 0;
  api.DriverCardInfo? _driverCard;
  String? _driverId;
  bool _followDriver = true;
  bool _rated = false;

  final RouteService _routeService = RouteService();
  List<LatLng>? _roadRoute;
  List<LatLng>? _plannedRoute;
  double _roadKm = 0;
  double _roadMin = 0;
  bool _routeLoading = false;
  LatLng? _lastRouteFrom;
  DateTime _lastRouteAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _cameraRotation = 0;
  List<LatLng>? _flowPointsCache;
  List<Marker> _flowMarkersCache = const [];

  // Recalcula la ruta vial cuando el conductor se mueve más de 50 m o cada 15 s.
  static const double _routeRecalcMeters = 50;
  static const Duration _routeRecalcInterval = Duration(seconds: 15);

  sb.RealtimeChannel? _channel;

  /// Destino de la ruta del conductor: el ORIGEN mientras no esté en curso,
  /// el DESTINO desde que está en camino.
  LatLng? get _routeTarget {
    final s = _service;
    if (s == null) return null;
    final isEnCurso = s.status == ServiceStatus.enCurso;
    final lat = isEnCurso ? s.destinationLat : s.originLat;
    final lng = isEnCurso ? s.destinationLng : s.originLng;
    if (lat == 0 && lng == 0) return null;
    return LatLng(lat, lng);
  }

  @override
  void initState() {
    super.initState();
    _loadService();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _routeService.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadService() async {
    try {
      final service = await api.getServiceById(widget.serviceId);
      if (!mounted) return;
      setState(() {
        _service = service;
        _loading = false;
        _driverId = service.driverId;
      });
      _fitRoute(service);
      _subscribeRealtime(service);
      if (service.driverId != null) {
        await _loadDriverInfo(service.driverId!);
      }
      if (service.originLat != 0 && service.destinationLat != 0) {
        // Ruta planeada completa (origen → destino) como contexto, incluso
        // cuando el conductor ya viene en camino.
        await _scheduleTripRoute(service);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el servicio: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadDriverInfo(String driverId) async {
    await _refreshDriverLocation(driverId);
    if (!mounted) return;
    final loc = _driverLocation;
    final card = await api.getDriverCard(driverId);
    if (mounted && card != null) setState(() => _driverCard = card);
    // Ruta en vivo conductor → origen (o destino si está en curso).
    if (loc != null) await _updateRoadRoute(loc);
  }

  /// Ruta vial planeada origen → destino (sin conductor asignado).
  Future<void> _scheduleTripRoute(Service service) async {
    if (service.originLat == 0 && service.destinationLat == 0) return;
    if (_routeLoading) return;
    setState(() => _routeLoading = true);
    try {
      final r = await _routeService.getRoute(
        origin: LatLng(service.originLat, service.originLng),
        destination: LatLng(service.destinationLat, service.destinationLng),
      );
      if (!mounted) return;
      setState(() {
        _plannedRoute = r.points;
        if (_roadRoute == null) {
          _roadRoute = r.points;
          _roadKm = r.distanceMeters / 1000;
          _roadMin = r.durationSeconds / 60;
        }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  /// Ruta vial en vivo desde la posición actual del conductor hasta el
  /// destino. Se limita por distancia/tiempo para no saturar la red.
  Future<void> _updateRoadRoute(LatLng from) async {
    final target = _routeTarget;
    if (target == null || _routeLoading) return;
    final sinceLast = DateTime.now().difference(_lastRouteAt);
    if (_lastRouteFrom != null &&
        const Distance().distance(_lastRouteFrom!, from) < _routeRecalcMeters &&
        sinceLast < _routeRecalcInterval) {
      return;
    }
    setState(() => _routeLoading = true);
    try {
      final r = await _routeService.getRoute(origin: from, destination: target);
      if (!mounted) return;
      setState(() {
        _roadRoute = r.points;
        _roadKm = r.distanceMeters / 1000;
        _roadMin = r.durationSeconds / 60;
      });
      _lastRouteFrom = from;
      _lastRouteAt = DateTime.now();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  Future<void> _refreshDriverLocation(String driverId) async {
    try {
      final loc = await api.getDriverLocation(driverId);
      if (!mounted) return;
      setState(() {
        _driverLocation = loc != null
            ? LatLng(
                (loc['latitude'] as num).toDouble(),
                (loc['longitude'] as num).toDouble(),
              )
            : null;
      });
    } catch (_) {}
  }

  /// Realtime sobre `services` (estado) y `driver_locations` (posición).
  /// Al cambiar el conductor asignado se RE-SUSCRIBE para anclar el filtro
  /// de `driver_locations` al nuevo driver_id (evita ver a cualquier conductor).
  void _subscribeRealtime(Service service) {
    _channel?.unsubscribe();
    _channel = api.supabase.channel('customer-service-${widget.serviceId}');
    final subscribedDriver = _driverId;

    _channel!
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.update,
          schema: 'public',
          table: 'services',
          filter: sb.PostgresChangeFilter(
            column: 'id',
            type: sb.PostgresChangeFilterType.eq,
            value: widget.serviceId,
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            final newDriver = row['driver_id'] as String?;
            final newStatus = row['status'] as String?;
            debugPrint(
                'MUEVEX realtime services: status=$newStatus driver_id=$newDriver');
            if (!mounted) return;
            setState(() {
              _service = Service.fromMap(Map<String, dynamic>.from(row));
              _driverId = newDriver?.isEmpty == true ? null : newDriver;
              if (_driverId == null) _driverLocation = null;
              if (_driverId == null) _driverHeading = 0;
            });
            final driver = _driverId;
            if (driver != null) {
              await _loadDriverInfo(driver);
              final current = _service;
              if (current != null && driver != subscribedDriver) {
                _subscribeRealtime(current);
              }
            }
          },
        )
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'driver_locations',
          filter: subscribedDriver != null
              ? sb.PostgresChangeFilter(
                  column: 'driver_id',
                  type: sb.PostgresChangeFilterType.eq,
                  value: subscribedDriver,
                )
              : null,
          callback: (payload) => _fromPayload(payload.newRecord),
        )
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.update,
          schema: 'public',
          table: 'driver_locations',
          filter: subscribedDriver != null
              ? sb.PostgresChangeFilter(
                  column: 'driver_id',
                  type: sb.PostgresChangeFilterType.eq,
                  value: subscribedDriver,
                )
              : null,
          callback: (payload) => _fromPayload(payload.newRecord),
        )
        .subscribe();
  }

  void _fromPayload(Map<String, dynamic> payload) {
    final lat = payload['latitude'];
    final lng = payload['longitude'];
    if (lat == null || lng == null) return;
    if (!mounted) return;
    final loc = LatLng((lat as num).toDouble(), (lng as num).toDouble());
    final heading = (payload['heading'] as num?)?.toDouble() ?? 0;
    debugPrint('MUEVEX realtime driver_locations: $loc heading=$heading');
    setState(() {
      _driverLocation = loc;
      _driverHeading = heading;
    });
    _updateRoadRoute(loc);
    if (_followDriver) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _driverLocation == null) return;
        _mapController.move(
          _driverLocation!,
          math.max(_mapController.camera.zoom, 15),
        );
      });
    }
  }

  void _fitRoute(Service service) {
    if (service.originLat == 0 && service.destinationLat == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final origin = LatLng(service.originLat, service.originLng);
      final destination =
          LatLng(service.destinationLat, service.destinationLng);
      final bounds = LatLngBounds.fromPoints([origin, destination]);
      // Margen inferior amplio para que la ruta no quede detrás del panel.
      _mapController.fitCamera(CameraFit.bounds(
          bounds: bounds, padding: const EdgeInsets.fromLTRB(60, 60, 60, 190)));
    });
  }

  List<Marker> _flowMarkersFor(List<LatLng> points) {
    if (points == _flowPointsCache) return _flowMarkersCache;
    _flowPointsCache = points;
    _flowMarkersCache = routeFlowMarkers(points);
    return _flowMarkersCache;
  }

  Future<void> _cancelService() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar solicitud?'),
        content: const Text('El conductor será avisado de la cancelación.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Volver')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar',
                style: TextStyle(color: MuevexTheme.errorColor)),
          ),
        ],
      ),
    );
    if (res != true || !mounted) return;
    try {
      await api.supabase.rpc('cancel_service', params: {
        'p_service_id': widget.serviceId,
        'p_cancelled_by': 'cliente',
      });
      if (!mounted) return;
      final updated = await api.getServiceById(widget.serviceId);
      if (mounted) {
        setState(() => _service = updated);
        ref.invalidate(customerServicesProvider);
      }
    } catch (e) {
      if (mounted) {
        showMuevexSnackBar(
          context,
          message: 'No se pudo cancelar la solicitud. Inténtalo de nuevo.',
          icon: Icons.error_outline,
          isError: true,
        );
      }
    }
  }

  Future<void> _showRatingDialog(Service service) async {
    if (_rated) {
      _showAlreadyRated();
      return;
    }
    final driverId = service.driverId;
    if (driverId == null) return;

    final result = await showDialog<_RatingSelection>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RatingDialog(service: service),
    );
    if (result == null || !mounted) return;

    final me = api.getCurrentUser()?.id;
    if (me == null) return;

    try {
      // Registrar el pago de la carrera (idempotente: si el usuario toca
      // "Pagar" dos veces, solo se inserta el primer pago).
      if (!await api.paymentExists(service.id)) {
        await api.createPayment(Payment(
          id: '',
          serviceId: service.id,
          amount: precioTotalConIva(service.finalPrice ?? service.priceTotal),
          paymentMethod: 'efectivo',
          status: 'completed',
          paidAt: DateTime.now(),
          createdAt: DateTime.now(),
        ));
      }
      // Calificación del conductor.
      // Antes se ignoraba el resultado y se decía "¡Gracias!" pase lo que
      // pase: si ya estaba calificado o si hubo un 403, la app confirmaba algo
      // que no ocurrió y el usuario creía que había dejado su nota.
      final nota = await api.submitClientRating(
        serviceId: service.id,
        driverId: driverId,
        score: result.score.toDouble(),
        comment: result.comment,
      );
      if (!mounted) return;
      if (nota.ok) {
        setState(() => _rated = true);
        ref.invalidate(customerServicesProvider);
        showMuevexSnackBar(
          context,
          message: '¡Gracias por calificar al conductor!',
          icon: Icons.star,
        );
      } else {
        showMuevexSnackBar(
          context,
          message: nota.error ?? 'No se pudo guardar tu calificación.',
          icon: Icons.error_outline,
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        showMuevexSnackBar(
          context,
          message: 'No se pudo guardar tu calificación. Inténtalo de nuevo.',
          icon: Icons.error_outline,
          isError: true,
        );
      }
    }
  }

  void _showAlreadyRated() {
    showMuevexSnackBar(
      context,
      message: 'Ya calificaste este servicio.',
      icon: Icons.star_half,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MuevexGradientAppBar(
        title: _service == null ? 'Mapa del Servicio' : 'Seguimiento',
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const BrandLoadingView(message: 'Cargando el servicio…');
    }
    if (_error != null) {
      return MuevexErrorView(
        message: _error ?? 'No se pudo cargar el servicio.',
        onRetry: () {
          setState(() {
            _loading = true;
            _error = null;
          });
          _loadService();
        },
      );
    }

    final service = _service!;
    final origin = LatLng(service.originLat, service.originLng);
    final destination = LatLng(service.destinationLat, service.destinationLng);

    final markers = <Marker>[
      Marker(
        point: origin,
        width: 44,
        height: 96,
        alignment: Alignment.bottomCenter,
        child: const MapPin(
          icon: Icons.trip_origin_rounded,
          label: 'ORIGEN',
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF34D399), Color(0xFF16A34A)],
          ),
        ),
      ),
      Marker(
        point: destination,
        width: 44,
        height: 96,
        alignment: Alignment.bottomCenter,
        child: BouncingMarker(
          amplitude: 6,
          alignment: Alignment.bottomCenter,
          child: const MapPin(
            icon: Icons.flag_rounded,
            label: 'DESTINO',
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF87171), Color(0xFFDC2626)],
            ),
          ),
        ),
      ),
      if (_driverLocation != null)
        Marker(
          point: _driverLocation!,
          width: 74,
          height: 86,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              BouncingMarker(
                amplitude: 6,
                child: Transform.rotate(
                  // El icono apunta al este; resto 90° para que el ángulo
                  // coincida con el rumbo real del conductor (heading 0 = norte).
                  angle: (_driverHeading > 0 ? _driverHeading - 90 : 0) *
                      math.pi /
                      180,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: MuevexTheme.primaryGradient,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color:
                              MuevexTheme.primaryColor.withValues(alpha: 0.45),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.local_shipping,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),
              Positioned(
                top: -4,
                child: PulsingHalo(
                  icon: Icons.radio_button_checked,
                  color: MuevexTheme.accentColor,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
    ];

    // Ruta completa planeada y ruta restante del conductor. La completa se
    // atenúa (contexto) y la restante brilla en gradiente con chevrones.
    final fullPlanned = _plannedRoute ?? _roadRoute;
    final remaining = _roadRoute;
    final effectiveRoute = (remaining ?? fullPlanned) ?? const <LatLng>[];
    final polylines = <Polyline>[
      if (remaining != null && fullPlanned != null && fullPlanned.length > 1)
        ...buildRoutePolylines(fullPlanned, dim: true),
      if (effectiveRoute.length > 1) ...buildRoutePolylines(effectiveRoute),
    ];
    markers.addAll(_flowMarkersFor(effectiveRoute));

    final center = _driverLocation ??
        LatLng(
          (service.originLat + service.destinationLat) / 2,
          (service.originLng + service.destinationLng) / 2,
        );

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            minZoom: 3,
            maxZoom: mw.kMapMaxZoom,
            backgroundColor: mw.kMapBackgroundColor,
            onPositionChanged: (position, hasGesture) {
              final rotation = _mapController.camera.rotation;
              if ((rotation - _cameraRotation).abs() > 0.5) {
                setState(() => _cameraRotation = rotation);
              }
              if (hasGesture && _followDriver) {
                setState(() => _followDriver = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: mw.kEsriDarkBaseTileUrl,
              userAgentPackageName: 'com.example.muevex',
              keepBuffer: 6,
              panBuffer: 2,
            ),
            TileLayer(
              urlTemplate: mw.kEsriDarkReferenceTileUrl,
              userAgentPackageName: 'com.example.muevex',
              keepBuffer: 6,
            ),
            PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendItem(
                  color: MuevexTheme.successColor,
                  icon: Icons.trip_origin,
                  label: 'Origen'),
              const SizedBox(width: 8),
              _LegendItem(
                  color: MuevexTheme.primaryColor,
                  icon: Icons.local_shipping,
                  label: 'Conductor'),
              const SizedBox(width: 8),
              _LegendItem(
                  color: MuevexTheme.errorColor,
                  icon: Icons.place,
                  label: 'Destino'),
            ],
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 6,
          child: const Padding(
            padding: EdgeInsets.only(bottom: 2),
            child: Text(
              '© OpenStreetMap contributors · Esri',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10, color: Colors.white60),
            ),
          ),
        ),
        if (_driverLocation != null)
          Positioned(
            right: 14,
            bottom: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_cameraRotation != 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FloatingActionButton.small(
                      heroTag: 'compass-north',
                      onPressed: () => _mapController.rotate(0),
                      backgroundColor: Colors.white,
                      foregroundColor: MuevexTheme.primaryColor,
                      elevation: 4,
                      tooltip: 'Reorientar al norte',
                      child: const Icon(Icons.navigation_rounded),
                    ),
                  ),
                FloatingActionButton.small(
                  heroTag: 'follow-driver',
                  onPressed: () {
                    setState(() => _followDriver = !_followDriver);
                    if (_driverLocation != null) {
                      _mapController.move(
                        _driverLocation!,
                        math.max(_mapController.camera.zoom, 15),
                      );
                    } else if (_service != null) {
                      _fitRoute(_service!);
                    }
                  },
                  backgroundColor: Colors.white,
                  foregroundColor: _followDriver
                      ? MuevexTheme.primaryColor
                      : Colors.grey.shade500,
                  elevation: 4,
                  tooltip: 'Seguir al conductor',
                  child: _followDriver
                      ? const Icon(Icons.my_location)
                      : const Icon(Icons.near_me_disabled),
                ),
              ],
            ),
          ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: _StatusPanel(
            service: service,
            driverCard: _driverCard,
            driverLocation: _driverLocation,
            roadKm: _roadKm,
            roadMin: _roadMin,
            onCancel: _cancelService,
            onRate: () => _showRatingDialog(service),
          ),
        ),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final Service service;
  final api.DriverCardInfo? driverCard;
  final LatLng? driverLocation;
  final double roadKm;
  final double roadMin;
  final VoidCallback onCancel;
  final VoidCallback onRate;

  const _StatusPanel({
    required this.service,
    required this.driverCard,
    required this.driverLocation,
    this.roadKm = 0,
    this.roadMin = 0,
    required this.onCancel,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final status = service.status;
    final statusColor = switch (status) {
      ServiceStatus.solicitado => MuevexTheme.warningColor,
      ServiceStatus.aceptado => MuevexTheme.primaryColor,
      ServiceStatus.enRecogida => MuevexTheme.accentColor,
      ServiceStatus.enCurso => MuevexTheme.primaryLight,
      ServiceStatus.completado => MuevexTheme.successColor,
      ServiceStatus.canceladoCliente ||
      ServiceStatus.canceladoConductor =>
        Colors.grey,
    };
    final statusIcon = switch (status) {
      ServiceStatus.solicitado => Icons.schedule,
      ServiceStatus.aceptado => Icons.verified,
      ServiceStatus.enRecogida => Icons.delivery_dining,
      ServiceStatus.enCurso => Icons.rocket_launch,
      ServiceStatus.completado => Icons.check_circle,
      ServiceStatus.canceladoCliente ||
      ServiceStatus.canceladoConductor =>
        Icons.cancel,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Colors.black38, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 15, color: statusColor),
                    const SizedBox(width: 5),
                    Text(
                      '${status.arabicName.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (status == ServiceStatus.solicitado)
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: MuevexTheme.errorColor,
                  ),
                  child: const Text('Cancelar'),
                ),
            ],
          ),
          if (service.driverId == null &&
              status == ServiceStatus.solicitado) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: MuevexTheme.warningColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MuevexTheme.warningColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Buscando conductor disponible…',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: MuevexTheme.warningColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (service.driverId != null && driverCard != null) ...[
            const SizedBox(height: 12),
            _DriverCard(
              service: service,
              driver: driverCard!,
              distanceToDriver: driverLocation,
              roadKm: roadKm,
              roadMin: roadMin,
            ),
          ],
          if (roadKm > 0 && roadMin > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.route,
                    size: 15, color: MuevexTheme.primaryColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ruta en vivo: ${roadKm.toStringAsFixed(1)} km · '
                    '~${roadMin.round()} min',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MuevexTheme.primaryColor),
                  ),
                ),
              ],
            ),
          ],
          if (status == ServiceStatus.completado) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MuevexTheme.secondaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.payments,
                      color: MuevexTheme.secondaryColor, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Total: ${moneyConIva(service.finalPrice ?? service.priceTotal)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: MuevexTheme.secondaryColor),
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: MuevexTheme.secondaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onRate,
                    icon: const Icon(Icons.star, size: 18),
                    label: const Text('Pagar y calificar'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _RouteLine(
              icon: Icons.trip_origin,
              color: MuevexTheme.successColor,
              text: service.originName?.isNotEmpty == true
                  ? service.originName!
                  : (service.origin.isNotEmpty ? service.origin : 'Origen')),
          const SizedBox(height: 6),
          _RouteLine(
              icon: Icons.place,
              color: MuevexTheme.errorColor,
              text: service.destinationName?.isNotEmpty == true
                  ? service.destinationName!
                  : (service.destination.isNotEmpty
                      ? service.destination
                      : 'Destino')),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final Service service;
  final api.DriverCardInfo driver;
  final LatLng? distanceToDriver;
  final double roadKm;
  final double roadMin;

  const _DriverCard({
    required this.service,
    required this.driver,
    this.distanceToDriver,
    this.roadKm = 0,
    this.roadMin = 0,
  });

  @override
  Widget build(BuildContext context) {
    final useRoad = roadKm > 0 && roadMin > 0;
    final eta = useRoad ? roadMin.round() : _estimateEta(distanceToDriver);
    final km = useRoad
        ? roadKm
        : (distanceToDriver != null
            ? _haversine(
                distanceToDriver!, LatLng(service.originLat, service.originLng))
            : null);

    final vehicleLabel = <String>[
      if (driver.vehicleTypeLabel.isNotEmpty) driver.vehicleTypeLabel,
      if (driver.brand?.isNotEmpty == true) driver.brand!,
      if (driver.model?.isNotEmpty == true) driver.model!,
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MuevexTheme.primaryColor.withValues(alpha: 0.10),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: MuevexTheme.primaryColor.withValues(alpha: 0.25),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: MuevexTheme.primaryColor,
                    child:
                        driver.photoUrl != null && driver.photoUrl!.isNotEmpty
                            ? ClipOval(
                                child: Image.network(
                                  driver.photoUrl!,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person,
                                      color: Colors.white,
                                      size: 30),
                                ),
                              )
                            : const Icon(Icons.person,
                                color: Colors.white, size: 30),
                  ),
                  if (driver.isVerified)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified,
                          size: 16,
                          color: MuevexTheme.primaryColor,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            driver.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (driver.isVerified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: MuevexTheme.successColor
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Verificado',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: MuevexTheme.successColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ...List.generate(5, (i) {
                          final filled = i < driver.rating.round();
                          return Icon(
                            filled ? Icons.star : Icons.star_border,
                            size: 15,
                            color: filled ? Colors.amber : Colors.grey.shade400,
                          );
                        }),
                        const SizedBox(width: 4),
                        Text(
                          driver.rating > 0
                              ? driver.rating.toStringAsFixed(1)
                              : '—',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        if (driver.phone?.isNotEmpty == true) ...[
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: driver.phone!),
                              );
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Teléfono copiado al portapapeles',
                                    ),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone_outlined,
                                    size: 14, color: MuevexTheme.primaryColor),
                                const SizedBox(width: 3),
                                Text(
                                  driver.phone!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: MuevexTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (driver.hasVehicle && vehicleLabel.isNotEmpty)
                _DriverChip(
                  icon: Icons.directions_car_filled,
                  text: vehicleLabel,
                ),
              if (driver.hasVehicle)
                _DriverChip(
                  icon: Icons.confirmation_number_outlined,
                  text: driver.plate!,
                  accent: true,
                ),
              if (driver.capacityKg > 0)
                _DriverChip(
                  icon: Icons.scale_outlined,
                  text: '${driver.capacityKg} kg',
                ),
            ],
          ),
          if (eta != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: MuevexTheme.primaryColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule,
                      size: 16, color: MuevexTheme.primaryColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Llegará en ~$eta min'
                      '${km != null ? ' · a ${km.toStringAsFixed(1)} km del origen' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MuevexTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  int? _estimateEta(LatLng? driverPos) {
    if (driverPos == null) return null;
    // Antes de la recogida el conductor va hacia el ORIGEN del servicio.
    final target = service.status != ServiceStatus.enCurso
        ? LatLng(service.originLat, service.originLng)
        : LatLng(service.destinationLat, service.destinationLng);
    final km = _haversine(driverPos, target);
    return math.max(1, (km / 35 * 60).round());
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }
}

class _DriverChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool accent;

  const _DriverChip({
    required this.icon,
    required this.text,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? MuevexTheme.secondaryColor : Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MuevexTheme.surfaceBorderOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _RouteLine(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _RatingSelection {
  final int score;
  final String? comment;
  const _RatingSelection(this.score, this.comment);
}

class _RatingDialog extends StatefulWidget {
  final Service service;
  const _RatingDialog({required this.service});

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _score = 5;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Calificar servicio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('¿Cómo estuvo el servicio?'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return IconButton(
                  onPressed: () => setState(() => _score = i + 1),
                  icon: Icon(
                    i < _score ? Icons.star : Icons.star_border,
                    size: 34,
                    color: i < _score ? Colors.amber : Colors.grey.shade400,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Cuéntanos cómo te fue (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Después')),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, _RatingSelection(_score, _commentCtrl.text.trim())),
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _LegendItem({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
