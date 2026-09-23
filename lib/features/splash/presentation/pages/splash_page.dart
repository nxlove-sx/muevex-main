import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/widgets/animations.dart';
import 'package:muevex/core/widgets/muevex_logo.dart';
import 'package:muevex/core/supabase/supabase_client.dart' as api;

/// Portada animada de MUEVEX. Se muestra al iniciar la app y conduce al
/// flujo de autenticación cuando termina la animación.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleSlide;
  late final Animation<double> _subtitleFade;
  late final Animation<double> _truckSlide;
  late final Animation<double> _buttonFade;
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;
  Timer? _autoNav;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack)),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.35, curve: Curves.easeIn)),
    );
    _titleSlide = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic)),
    );
    _subtitleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.55, 0.8, curve: Curves.easeIn)),
    );
    _truckSlide = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.6, 1.0, curve: Curves.easeInOut)),
    );
    _buttonFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.75, 1.0, curve: Curves.easeIn)),
    );

    // Pulso suave del motocarro central.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulse = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.12), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 1.12, end: 1.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _pulseController.repeat();
        }
      });
    _pulseController.forward();

    // Secuencia de animación de ida y vuelta del motocarro.
    _controller
      ..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          _controller.forward();
        }
      })
      ..forward();

    // Redirigir automáticamente tras terminar la presentación.
    // Si ya hay sesión (persistida por Supabase) se entra directo a la home.
    _autoNav = Timer(
      api.authed
          ? const Duration(milliseconds: 1400)
          : const Duration(milliseconds: 4600),
      () {
        if (mounted) context.go(api.authed ? '/' : '/login');
      },
    );
  }

  @override
  void dispose() {
    _autoNav?.cancel();
    _pulseController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: MuevexTheme.primaryGradient,
        ),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 640;
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        // Logo principal
                        FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: const Shimmer(
                              highlight: Colors.white54,
                              child: MuevexLogo(size: 120),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Título
                        SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.8),
                            end: Offset.zero,
                          ).animate(_titleSlide),
                          child: const Text(
                            'MUEVEX',
                            style: TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 6,
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Subtítulo
                        FadeTransition(
                          opacity: _subtitleFade,
                          child: const Text(
                            'Transporte de muebles y cargas pequeñas\nfácil, rápido y seguro',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                              height: 1.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Motocarro animado (decorativo, no interactivo)
                        SizedBox(
                          height: compact ? 96 : 120,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(-1.5, 0),
                              end: Offset.zero,
                            ).animate(_truckSlide),
                            child: Center(
                              child: ScaleTransition(
                                scale: _pulse,
                                child: Container(
                                  width: compact ? 96 : 120,
                                  height: compact ? 96 : 120,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.18),
                                        blurRadius: 28,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.local_shipping_rounded,
                                    size: compact ? 56 : 72,
                                    color: MuevexTheme.secondaryColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                        // Botón comenzar
                        FadeTransition(
                          opacity: _buttonFade,
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: MuevexTheme.primaryColor,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 4,
                              ),
                              onPressed: () {
                                _autoNav?.cancel();
                                context.go(api.authed ? '/' : '/login');
                              },
                              child: const Text(
                                'Comenzar',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        ),
      ),
    );
  }
}
