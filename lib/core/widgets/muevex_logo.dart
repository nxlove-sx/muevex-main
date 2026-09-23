import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Logo oficial de MUEVEX.
///
/// Usa la imagen del logo incluida en `assets/images/muevex_logo.png`
/// enmarcada en un contenedor redondeado con sombra suave, de modo que se vea
/// bien sobre los degradados azul/turquesa de la app (splash, login, registro
/// y home).
class MuevexLogo extends StatelessWidget {
  /// Tamaño del contenedor cuadrado que enmarca el logo.
  final double size;

  /// Color de fondo del contenedor. Por defecto blanco para verse bien sobre
  /// los degradados azul/turquesa.
  final Color? backgroundColor;

  const MuevexLogo({
    super.key,
    this.size = 96,
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.09),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          'assets/images/muevex_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Center(
            child: Icon(
              Icons.local_shipping_rounded,
              size: size * 0.55,
              color: MuevexTheme.primaryColor,
            ),
          ),
        ),
      ),
    );
  }
}