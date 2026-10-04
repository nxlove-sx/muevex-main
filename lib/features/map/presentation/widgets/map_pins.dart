import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Marcadores premium para los puntos clave del mapa: origen, destino y
/// ubicación del usuario. Usan el diseño "anillo blanco + núcleo en gradiente"
/// con punta triangular que señala el punto exacto en coordenadas.
///
/// La etiqueta va ARRIBA y la punta abajo: el `Marker` de flutter_map apoya el
/// borde inferior de su caja en la coordenada, así que con
/// `MainAxisAlignment.end` la punta da en el punto exacto aunque la etiqueta
/// crezca con el tamaño de letra del sistema.

class MapPin extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  final String? label;

  const MapPin({
    super.key,
    required this.icon,
    required this.gradient,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: MuevexTheme.surfaceOf(context).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Text(
              label!,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -7),
          child: ClipPath(
            clipper: _TriangleClipper(10),
            child: Container(
              width: 20,
              height: 13,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Patas del marcador: triángulo centrado que apunta al punto exacto.
class _TriangleClipper extends CustomClipper<Path> {
  final double baseWidth;
  const _TriangleClipper(this.baseWidth);

  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(size.width / 2 - baseWidth / 2, 0)
      ..lineTo(size.width / 2 + baseWidth / 2, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(_TriangleClipper oldClipper) =>
      oldClipper.baseWidth != baseWidth;
}

class UserLocationDot extends StatelessWidget {
  const UserLocationDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(width: 3, color: MuevexTheme.primaryColor),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 6),
        ],
      ),
      child:
          const Icon(Icons.person, size: 14, color: MuevexTheme.primaryColor),
    );
  }
}
