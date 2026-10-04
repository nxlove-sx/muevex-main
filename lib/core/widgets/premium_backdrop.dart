import 'package:flutter/material.dart';

/// Fondo decorativo premium: gradiente de marca + burbujas de luz translúcidas
/// que dan profundidad a cabeceras (home, login, perfil conductor).
///
/// Uso:
/// ```dart
/// BlobField(
///   gradientColors: MuevexTheme.primaryGradient.colors,
///   child: ...,
/// )
/// ```
class BlobField extends StatelessWidget {
  /// Gradiente de fondo (array de colores para [LinearGradient]).
  final List<Color> gradientColors;

  /// Intensidad de las burbujas (0-1). Por defecto 0.35.
  final double intensity;

  final Widget child;

  const BlobField({
    super.key,
    required this.gradientColors,
    required this.child,
    this.intensity = 0.35,
  });

  @override
  Widget build(BuildContext context) {
    final light = Colors.white.withValues(alpha: intensity);
    final teal = const Color(0xFF00C2A8).withValues(alpha: intensity * 0.8);
    final orange = const Color(0xFFFF8A3D).withValues(alpha: intensity * 0.6);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Stack(
        children: [
          // Burbuja superior derecha (luz clara)
          _Blob(
            size: 260,
            top: -90,
            right: -70,
            color: light,
          ),
          // Burbuja inferior izquierda (teal)
          _Blob(
            size: 220,
            bottom: -80,
            left: -50,
            color: teal,
          ),
          // Burbuja pequeña crema (acento cálido)
          _Blob(
            size: 120,
            top: 60,
            left: 60,
            color: orange,
          ),
          child,
        ],
      ),
    );
  }
}

/// Círculo con degradado radial suave (sin borde duro). Debe usarse dentro de
/// un [Stack] (devuelve un [Positioned]).
class _Blob extends StatelessWidget {
  final double size;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final Color color;

  const _Blob({
    required this.size,
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.9),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
