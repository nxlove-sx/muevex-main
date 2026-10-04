import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:muevex/core/widgets/animations.dart';

/// Controles flotantes del mapa: re-centrar en mi ubicación, zoom + y zoom -.
///
/// Botones circulares con **efecto cristal** (el mapa se ve difuminado a
/// través del botón) y realimentación táctil al pulsarlos. El cristal hace que
/// los controles seem parte del mapa en vez de cajas opacas encima de él, que
/// es lo que rompe la sensación de "app de mapas" cuando el basemap es oscuro.
class LocationControls extends StatelessWidget {
  final VoidCallback onRecenter;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  /// `true` mientras se pide la ubicación: el botón de recentrar muestra un
  /// indicador y se desactiva para no disparar peticiones en paralelo.
  final bool locating;

  const LocationControls({
    super.key,
    required this.onRecenter,
    required this.onZoomIn,
    required this.onZoomOut,
    this.locating = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassIconButton(
          tooltip: 'Mi ubicación',
          onPressed: locating ? null : onRecenter,
          child: locating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.my_location, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 12),
        GlassIconButton(
          tooltip: 'Acercar',
          onPressed: onZoomIn,
          child: const Icon(Icons.add, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 12),
        GlassIconButton(
          tooltip: 'Alejar',
          onPressed: onZoomOut,
          child: const Icon(Icons.remove, color: Colors.white, size: 24),
        ),
      ],
    );
  }
}

/// Botón circular con fondo de cristal, usado por los controles del mapa.
///
/// Tres capas, de atrás hacia delante:
///   1. `BackdropFilter` que difumina lo que hay debajo (el mapa).
///   2. Tinte oscuro translúcido, para que el icono tenga contraste.
///   3. Borde claro de 1 px, que es lo que da la sensación de cristal.
///
/// Se añade [PressableScale] para que el botón se hunda al pulsarlo: en una
/// pantalla donde el dedo tapa el botón, ese rebote es la única confirmación
/// visible de que la pulsación ha registrado.
class GlassIconButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  const GlassIconButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.tooltip,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: PressableScale(
        // Sin rebote si el botón está deshabilitado: animarlo insinuaría que
        // responde cuando no lo hace.
        pressedScale: enabled ? 0.9 : 1,
        child: SizedBox(
          width: size,
          height: size,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x66101A2E),
                  border: Border.all(
                    color: enabled ? Colors.white24 : Colors.white10,
                    width: 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onPressed,
                    splashColor: Colors.white12,
                    highlightColor: Colors.white10,
                    child: Center(child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
