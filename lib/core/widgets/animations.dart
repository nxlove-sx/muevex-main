import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Colección de primitivas de animación reutilizables para MUEVEX.
/// Evitan repetir AnimationController/Transform en cada pantalla.

/// Entrada escalonada (fade + deslizamiento) de un hijo.
/// Se usa con `AnimatedWidgets.stagger` o directamente con un `delay`.
class StaggeredEntrance extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration duration;
  final Offset offset;
  final Curve curve;

  const StaggeredEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 450),
    this.offset = const Offset(0, 0.3),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final delay = Duration(milliseconds: widget.index * 70);
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });

    _opacity = CurvedAnimation(parent: _controller, curve: widget.curve);
    _slide = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));
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
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(offset: _slide.value, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Escala al presionar: da feedback táctil a botones/tarjetas.
/// El "rebote" al soltar usa una curva con ligero overshoot para sentirse natural.
class PressableScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;

  const PressableScale({
    super.key,
    required this.child,
    this.pressedScale = 0.97,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _scale = Tween<double>(begin: 1.0, end: widget.pressedScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  void _onPointerDown(PointerDownEvent _) => _controller.forward();
  void _onPointerUp(PointerEvent _) => _controller.reverse();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: (_) => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// Brillo animado (shimmer) para logos o placeholders.
class Shimmer extends StatefulWidget {
  final Widget child;
  final Color highlight;
  final Duration duration;

  const Shimmer({
    super.key,
    required this.child,
    this.highlight = Colors.white24,
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
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
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final dx = (_controller.value * 2 - 1) * bounds.width * 1.5;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                widget.highlight,
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
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double dx;
  _SlideGradient(this.dx);
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// Anima la aparición de una lista con desvanecido y desplazamiento.
class FadeInListView extends StatefulWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final Duration duration;

  const FadeInListView({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.duration = const Duration(milliseconds: 500),
  });

  @override
  State<FadeInListView> createState() => _FadeInListViewState();
}

class _FadeInListViewState extends State<FadeInListView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      final t = (i + 1) / math.max(widget.children.length, 1);
      children.add(
        FadeTransition(
          opacity: CurvedAnimation(
            parent: _controller,
            curve: Interval(
              math.max(0, t - 0.25),
              t,
              curve: Curves.easeOut,
            ),
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: _controller,
                curve: Interval(
                  math.max(0, t - 0.25),
                  t,
                  curve: Curves.easeOutCubic,
                ),
              ),
            ),
            child: widget.children[i],
          ),
        ),
      );
    }
    return Padding(
      padding: widget.padding,
      child: Column(children: children),
    );
  }
}

/// Contador numérico animado: hace "tick up/down" suavemente al cambiar el valor.
/// Ideal para precios, pesos, etc.
class AnimatedNumber extends StatelessWidget {
  final double value;
  final Duration duration;
  final Curve curve;
  final String Function(double value) formatter;
  final TextStyle? style;

  const AnimatedNumber({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 500),
    this.curve = Curves.easeOutCubic,
    required this.formatter,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: curve,
      builder: (context, animatedValue, _) => Text(
        formatter(animatedValue),
        style: style,
      ),
    );
  }
}

/// Caja que cambia su altura y opacidad animadas. Para secciones que
/// aparecen/desaparecen con movimiento (p. ej. resúmenes de selección).
class AnimatedPanel extends StatelessWidget {
  final bool visible;
  final Widget child;
  final Duration duration;
  final Offset slideOffset;

  const AnimatedPanel({
    super.key,
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 320),
    this.slideOffset = const Offset(0, -0.1),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: AnimatedSlide(
          duration: duration,
          curve: Curves.easeOutCubic,
          offset: visible ? Offset.zero : slideOffset,
          child: AnimatedOpacity(
            duration: duration,
            curve: Curves.easeOut,
            opacity: visible ? 1.0 : 0.0,
            child: visible ? child : child,
          ),
        ),
      ),
    );
  }
}

/// Marcador "botando" para el mapa: da la sensación de ubicación viva.
///
/// [alignment] sitúa el hijo dentro de la caja del marcador. Para un pin que
/// debe señalar una coordenada va [Alignment.bottomCenter]: el `Marker` de
/// flutter_map apoya el borde inferior de su caja en el punto, así que
/// anclar abajo deja la punta del pin sobre el punto aunque la caja sea más
/// alta que el pin.
class BouncingMarker extends StatefulWidget {
  final Widget child;
  final double amplitude;
  final Duration duration;
  final bool animate;
  final AlignmentGeometry alignment;

  const BouncingMarker({
    super.key,
    required this.child,
    this.amplitude = 6.0,
    this.duration = const Duration(milliseconds: 900),
    this.animate = true,
    this.alignment = Alignment.center,
  });

  @override
  State<BouncingMarker> createState() => _BouncingMarkerState();
}

class _BouncingMarkerState extends State<BouncingMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.animate) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(BouncingMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
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
      builder: (context, child) {
        final t = _controller.value;
        final y = -math.sin(t * math.pi) * widget.amplitude;
        return SizedBox(
          width: 44,
          height: 54,
          child: Stack(
            alignment: widget.alignment,
            children: [
              Transform.translate(
                offset: Offset(0, y),
                child: child,
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  width: 20 - (t * 8),
                  height: 6 - (t * 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Icono con un halo pulsante, útil para estados activos (conductor a bordo).
class PulsingHalo extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final Duration duration;

  const PulsingHalo({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<PulsingHalo> createState() => _PulsingHaloState();
}

class _PulsingHaloState extends State<PulsingHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
    _scale = Tween<double>(begin: 0.6, end: 1.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 1.4,
      height: widget.size * 1.4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Opacity(
              opacity: _opacity.value,
              child: Transform.scale(
                scale: _scale.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
          Icon(widget.icon, color: widget.color, size: widget.size),
        ],
      ),
    );
  }
}

/// ✨ NUEVAS ANIMACIONES MEJORADAS ✨

/// Rotación continua con loop infinito (para logos, spinners).
class RotatingWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final bool animate;

  const RotatingWidget({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 4),
    this.animate = true,
  });

  @override
  State<RotatingWidget> createState() => _RotatingWidgetState();
}

class _RotatingWidgetState extends State<RotatingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(RotatingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) {
      _controller.repeat();
    } else if (!widget.animate && oldWidget.animate) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: CurvedAnimation(parent: _controller, curve: Curves.linear),
      child: widget.child,
    );
  }
}

/// Pulso con escala y opacidad (mejorado con 3 capas).
class PulseScale extends StatefulWidget {
  final Widget child;
  final Color color;
  final Duration duration;
  final double minScale;
  final double maxScale;

  const PulseScale({
    super.key,
    required this.child,
    required this.color,
    this.duration = const Duration(milliseconds: 1200),
    this.minScale = 0.8,
    this.maxScale = 1.2,
  });

  @override
  State<PulseScale> createState() => _PulseScaleState();
}

class _PulseScaleState extends State<PulseScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _scale =
        Tween<double>(begin: widget.minScale, end: widget.maxScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      // FadeTransition, no `Opacity(opacity: _opacity.value)`: leer `.value`
      // dentro de build no programa ningún frame, así que la opacidad se
      // quedaba congelada en su valor inicial mientras el controlador seguía
      // emitiendo frames a 60 fps sin que nadie los consumiera.
      //
      // (Las otras dos lecturas de `_opacity.value` del fichero sí son
      // correctas: van dentro de un AnimatedBuilder.)
      child: FadeTransition(
        opacity: _opacity,
        child: widget.child,
      ),
    );
  }
}

/// Efecto de "flotación" (levita) para elementos decorativos.
class FloatingWidget extends StatefulWidget {
  final Widget child;
  final double amplitude;
  final Duration duration;

  const FloatingWidget({
    super.key,
    required this.child,
    this.amplitude = 12.0,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<FloatingWidget> createState() => _FloatingWidgetState();
}

class _FloatingWidgetState extends State<FloatingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder es imprescindible: sin él, build() solo se ejecuta una
    // vez y `Transform.translate` conserva el offset del primer frame, así que
    // el widget no se movía nunca, mientras el `repeat()` seguía emitiendo
    // frames a 60 fps sin que nadie los consumiera.
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            0,
            -math.sin(_controller.value * math.pi) * widget.amplitude,
          ),
          child: child,
        );
      },
    );
  }
}

/// Transición de página con escala y desvanecido.
class ScaleFadeTransition extends StatefulWidget {
  final Widget child;
  final bool visible;

  const ScaleFadeTransition({
    super.key,
    required this.child,
    this.visible = true,
  });

  @override
  State<ScaleFadeTransition> createState() => _ScaleFadeTransitionState();
}

class _ScaleFadeTransitionState extends State<ScaleFadeTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    if (widget.visible) _controller.forward();
  }

  @override
  void didUpdateWidget(ScaleFadeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _controller.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
        child: widget.child,
      ),
    );
  }
}

/// Spinner de carga premium con gradiente.
class PremiumSpinner extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;

  const PremiumSpinner({
    super.key,
    this.size = 48,
    this.color = const Color(0xFF0F63FF),
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<PremiumSpinner> createState() => _PremiumSpinnerState();
}

class _PremiumSpinnerState extends State<PremiumSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
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
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _SpinnerPainter(
              color: widget.color,
              progress: _controller.value,
            ),
          ),
        );
      },
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final Color color;
  final double progress;

  _SpinnerPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Gradiente de arco
    paint.shader = SweepGradient(
      colors: [
        color.withValues(alpha: 0.0),
        color.withValues(alpha: 0.3),
        color,
        color,
        color.withValues(alpha: 0.3),
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(progress * 2 * math.pi),
    ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
