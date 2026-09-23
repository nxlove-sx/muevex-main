import 'package:flutter/material.dart';

/// Controles flotantes del mapa: re-centrar en mi ubicación, zoom + y zoom -.
///
/// Botones circulares, modernos y discretos, consistentes con el mapa oscuro.
class LocationControls extends StatelessWidget {
  final VoidCallback onRecenter;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
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
        _ControlButton(
          tooltip: 'Mi ubicación',
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
          onPressed: onRecenter,
        ),
        const SizedBox(height: 12),
        _ControlButton(
          tooltip: 'Acercar',
          child: const Icon(Icons.add, color: Colors.white, size: 24),
          onPressed: onZoomIn,
        ),
        const SizedBox(height: 12),
        _ControlButton(
          tooltip: 'Alejar',
          child: const Icon(Icons.remove, color: Colors.white, size: 24),
          onPressed: onZoomOut,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onPressed;
  final String tooltip;

  const _ControlButton({
    required this.child,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Material(
        color: const Color(0xE61B2740),
        elevation: 3,
        shadowColor: Colors.black45,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(child: child),
        ),
      ),
    );
  }
}