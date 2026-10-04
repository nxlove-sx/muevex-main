import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Barra pulsante (skeleton) que simula el efecto shimmer profesional.
/// En lugar de [ShaderMask], el propio gradiente de la decoración se
/// desplaza con una animación lineal, lo cual es más fiable y rápido.
class SkeletonShimmer extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 10,
  });

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Color(0xFFD5DAE2), // gris base
                Color(0xFFEFF1F5), // brillo
                Color(0xFFD5DAE2), // gris base
              ],
              stops: [
                (t - 0.35).clamp(0.0, 1.0),
                t,
                (t + 0.35).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton que imita la tarjeta de servicio activo del home del cliente.
class ServiceCardSkeleton extends StatelessWidget {
  const ServiceCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MuevexTheme.surfaceBorderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              SkeletonShimmer(width: 40, height: 40, borderRadius: 12),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonShimmer(width: 120, height: 14, borderRadius: 6),
                    SizedBox(height: 8),
                    SkeletonShimmer(width: 80, height: 12, borderRadius: 6),
                  ],
                ),
              ),
              SkeletonShimmer(width: 36, height: 24, borderRadius: 12),
            ],
          ),
          const SizedBox(height: 14),
          const SkeletonShimmer(
              width: double.infinity, height: 8, borderRadius: 4),
          const SizedBox(height: 10),
          Row(
            children: const [
              SkeletonShimmer(width: 60, height: 12, borderRadius: 6),
              SizedBox(width: 12),
              SkeletonShimmer(width: 40, height: 12, borderRadius: 6),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton para la página de historial (fila).
class HistoryTileSkeleton extends StatelessWidget {
  const HistoryTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MuevexTheme.surfaceBorderOf(context)),
      ),
      child: Row(
        children: const [
          SkeletonShimmer(width: 42, height: 42, borderRadius: 12),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonShimmer(width: 140, height: 14, borderRadius: 6),
                SizedBox(height: 8),
                SkeletonShimmer(width: 90, height: 12, borderRadius: 6),
              ],
            ),
          ),
          SkeletonShimmer(width: 56, height: 20, borderRadius: 10),
        ],
      ),
    );
  }
}
