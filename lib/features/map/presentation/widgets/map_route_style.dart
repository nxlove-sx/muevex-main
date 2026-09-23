import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Estilos de ruta premium sobre el mapa oscuro de MUEVEX.
///
/// - `buildRoutePolylines`: ruta con "casing" oscuro + núcleo en gradiente
///   (teal → azul), o variante tenue punteada para el trayecto ya planeado.
/// - `routeFlowMarkers`: chevrones que marcan el sentido de la marcha cada
///   `stepMeters` metros a lo largo de la geometría vial.

List<Polyline> buildRoutePolylines(
  List<LatLng> points, {
  bool dim = false,
}) {
  if (points.length < 2) return const [];
  if (dim) {
    return [
      Polyline(
        points: points,
        color: Colors.white.withValues(alpha: 0.30),
        strokeWidth: 6,
        isDotted: true,
        strokeCap: StrokeCap.round,
      ),
    ];
  }
  return [
    // Casing: sombra oscura que da profundidad sobre las calles.
    Polyline(
      points: points,
      color: const Color(0xE0162440),
      strokeWidth: 9,
      borderColor: Colors.black54,
      borderStrokeWidth: 1,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
    ),
    // Núcleo en gradiente: teal → naranja → azul según avanza la ruta.
    Polyline(
      points: points,
      gradientColors: const [
        MuevexTheme.accentColor,
        MuevexTheme.secondaryColor,
        MuevexTheme.primaryColor,
      ],
      strokeWidth: 4.5,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
    ),
  ];
}

/// Chevrones que indican el sentido de marcha de la ruta [points].
///
/// Deja el tramo inicial libre para que el marcador del conductor no quede
/// tapado por una flecha.
List<Marker> routeFlowMarkers(
  List<LatLng> points, {
  double stepMeters = 420,
}) {
  if (points.length < 2) return const [];
  const dist = Distance();
  final cumulative = <double>[0];
  for (var i = 1; i < points.length; i++) {
    cumulative.add(
      cumulative.last +
          dist.as(LengthUnit.Meter, points[i - 1], points[i]),
    );
  }
  final total = cumulative.last;
  if (total < stepMeters * 1.5) return const [];
  final out = <Marker>[];
  for (var step = 1; step * stepMeters < total; step++) {
    final target = step * stepMeters;
    final placed = _pointAtDistance(points, cumulative, target);
    if (placed == null) continue;
    out.add(_buildRouteArrow(placed.$1, placed.$2));
  }
  return out;
}

/// Punto sobre la polyline a la distancia acumulada [target] (metros).
///
/// Devuelve el punto y el rumbo (grados geográficos, 0 = norte) del tramo.
(LatLng, double)? _pointAtDistance(
  List<LatLng> points,
  List<double> cumulative,
  double target,
) {
  for (var i = 0; i < points.length - 1; i++) {
    final start = cumulative[i];
    final end = cumulative[i + 1];
    if (target < start || target > end) continue;
    final t = (end == start) ? 0.0 : (target - start) / (end - start);
    final a = points[i];
    final b = points[i + 1];
    return (
      LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ),
      _bearing(a, b),
    );
  }
  return null;
}

double _bearing(LatLng a, LatLng b) {
  final lat1 = a.latitudeInRad;
  final lat2 = b.latitudeInRad;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return math.atan2(y, x) * 180 / math.pi;
}

Marker _buildRouteArrow(LatLng point, double bearingDeg) {
  // El chevron apunta al este; resto 90° para llevar el ángulo al rumbo real.
  final angle = (bearingDeg - 90) * math.pi / 180;
  return Marker(
    point: point,
    width: 30,
    height: 30,
    child: Transform.rotate(
      angle: angle,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.chevron_right_rounded,
            size: 28,
            color: Colors.black45,
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 26,
            color: Colors.white,
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: MuevexTheme.accentColor.withValues(alpha: 0.9),
          ),
        ],
      ),
    ),
  );
}