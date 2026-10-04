import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Logo oficial de MUEVEX.
///
/// Usa la imagen del logo incluida en `assets/images/muevex_logo.png`
/// enmarcada en un contenedor redondeado con sombra suave, de modo que se vea
/// bien sobre los degradados azul/turquesa de la app (splash, login, registro
/// y home).
///
/// Mejoras agregadas:
/// - Soporte para modo oscuro automático
/// - Animación de pulso al aparecer
/// - Efecto shimmer opcional
class MuevexLogo extends StatefulWidget {
  /// Tamaño del contenedor cuadrado que enmarca el logo.
  final double size;

  /// Color de fondo del contenedor. Por defecto blanco para verse bien sobre
  /// los degradados azul/turquesa.
  final Color? backgroundColor;

  /// Si muestra animación de pulso al aparecer.
  final bool pulse;

  /// Si muestra efecto shimmer.
  final bool shimmer;

  const MuevexLogo({
    super.key,
    this.size = 96,
    this.backgroundColor,
    this.pulse = true,
    this.shimmer = false,
  });

  @override
  State<MuevexLogo> createState() => _MuevexLogoState();
}

class _MuevexLogoState extends State<MuevexLogo> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _shimmerController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeOutBack,
      ),
    );
    if (widget.pulse) {
      _pulseController.forward();
    }

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (widget.shimmer) {
      _shimmerController.repeat();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveBg = widget.backgroundColor ??
        (isDark ? const Color(0xFF1E293B) : Colors.white);

    Widget logo = ScaleTransition(
      scale: _pulseScale,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: effectiveBg,
          borderRadius: BorderRadius.circular(widget.size * 0.28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F63FF).withValues(alpha: 0.25),
              blurRadius: widget.size * 0.18,
              offset: Offset(0, widget.size * 0.09),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size * 0.28),
          child: Image.asset(
            'assets/images/muevex_logo.png',
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Center(
              child: Icon(
                Icons.local_shipping_rounded,
                size: widget.size * 0.55,
                color: MuevexTheme.primaryColor,
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.shimmer) {
      logo = _ShimmerWrapper(
        controller: _shimmerController,
        child: logo,
      );
    }

    return logo;
  }
}

class _ShimmerWrapper extends StatelessWidget {
  final Widget child;
  final AnimationController controller;

  const _ShimmerWrapper({
    required this.child,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final dx = (controller.value * 2 - 1) * bounds.width * 1.5;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.5),
                Colors.transparent,
              ],
              stops: const [0.2, 0.5, 0.8],
              transform: _SlideGradient(dx),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: child,
    );
  }
}

/// Logo de MUEVEX con un **halo que respira** por detrás.
///
/// El logo estático sobre un degradado se lee como una imagen pegada encima.
/// El haloexpandiéndose y desvaneciéndose en bucle hace que parezca que la
/// marca "emite" luz, que es lo que da la sensación de app viva en el splash y
/// en las pantallas de acceso.
///
/// El halo se pinta con [CustomPaint] en vez de con `BoxShadow`: una sombra
/// difuminada obliga a repintar el desenfoque en cada frame, mientras que el
/// painter solo cambia de tamaño y opacidad, que es trivial para la GPU.
///
/// ```dart
/// const AnimatedMuevexLogo(size: 120)   // en el splash
/// ```
class AnimatedMuevexLogo extends StatefulWidget {
  final double size;

  /// Periodo de una respiración completa. Un valor tan alto se percibe como
  /// parpadeo, por eso no baja de ~1,6 s.
  final Duration period;

  /// Intensidad del halo (0-1). A 0 el logo se comporta como [MuevexLogo].
  final double haloIntensity;

  const AnimatedMuevexLogo({
    super.key,
    this.size = 120,
    this.period = const Duration(milliseconds: 2600),
    this.haloIntensity = 1,
  });

  @override
  State<AnimatedMuevexLogo> createState() => _AnimatedMuevexLogoState();
}

class _AnimatedMuevexLogoState extends State<AnimatedMuevexLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.period,
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant AnimatedMuevexLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si cambia el periodo en caliente (p. ej. por `TickerMode`), hay que
    // reconstruir el controlador; `repeat()` sobre el anterior seguiría con la
    // duración antigua.
    if (oldWidget.period != widget.period) {
      _controller
        ..stop()
        ..duration = widget.period
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Si el logo no tiene halo, no hace falta ni el controlador: se apaga para
    // no gastar frames en animar nada.
    if (widget.haloIntensity <= 0) {
      return MuevexLogo(size: widget.size);
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // 0 -> 1 -> 0: el halo crece mientras se desvanece, y al llegar al
          // final desaparece justo cuando está más grande, así que el reinicio
          // del bucle no se nota.
          final t = Curves.easeOut.transform(_controller.value);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size.square(widget.size),
                painter: _BreathingHaloPainter(
                  progress: t,
                  intensity: widget.haloIntensity,
                ),
              ),
              child!,
            ],
          );
        },
        child: MuevexLogo(size: widget.size),
      ),
    );
  }
}

/// Dibuja un halo circular que crece y se desvanece con [progress] (0-1).
class _BreathingHaloPainter extends CustomPainter {
  final double progress;
  final double intensity;

  const _BreathingHaloPainter({
    required this.progress,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Radio: del 62% al 100% del lado del logo.
    final base = size.shortestSide * 0.62;
    final radius = base + (size.shortestSide * 0.38) * progress;

    // Opacidad: opuesta al crecimiento (máxima al empezar, nula al terminar).
    final opacity = (1 - progress) * 0.45 * intensity;
    if (opacity <= 0.01) return;

    canvas.drawCircle(
      size.center(Offset.zero),
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.05
        ..color = Colors.white.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _BreathingHaloPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.intensity != intensity;
}

class _SlideGradient extends GradientTransform {
  final double dx;
  _SlideGradient(this.dx);
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// Logo pequeño para la barra de navegación.
class MuevexLogoSmall extends StatelessWidget {
  final double size;

  const MuevexLogoSmall({
    super.key,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.25),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F63FF).withValues(alpha: 0.2),
            blurRadius: size * 0.1,
            offset: Offset(0, size * 0.05),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.asset(
          'assets/images/muevex_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.local_shipping_rounded,
            size: size * 0.6,
            color: MuevexTheme.primaryColor,
          ),
        ),
      ),
    );
  }
}
