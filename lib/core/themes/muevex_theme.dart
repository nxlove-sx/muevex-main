import 'package:flutter/material.dart';

/// Paleta y tema central de MUEVEX.
///
/// Usa un esquema moderno azul profundo -> turquesa -> naranja, pensado para
/// una app de transporte de muebles con motocarros (rato/energía/frescura).
class MuevexTheme {
  MuevexTheme._();

  // Colores principales de MUEVEX
  static const Color primaryColor = Color(0xFF0F63FF);
  static const Color primaryLight = Color(0xFF4D9FFF);
  static const Color primaryDark = Color(0xFF063A8F);
  static const Color secondaryColor = Color(0xFFFF6B35);
  static const Color accentColor = Color(0xFF00C2A8);
  static const Color successColor = Color(0xFF22C55E);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color warningColor = Color(0xFFF59E0B);

  // Texto principal
  static const TextStyle primaryTextStyle = TextStyle(
    color: Colors.black,
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  /// Estilos de texto consistentes para la app.
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
  );
  static const TextStyle headlineMedium = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );
  static const TextStyle headlineSmall = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// Gradiente principal usado en portada, cabeceras y botones.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F63FF), Color(0xFF00C2A8)],
  );

  /// Gradiente cálido (naranja) usado como acento.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF8A3D), Color(0xFFFF5F6D)],
  );

  static const List<Color> chartColors = [
    Color(0xFF0F63FF),
    Color(0xFF00C2A8),
    Color(0xFFFF6B35),
    Color(0xFF9B4DFF),
    Color(0xFFF59E0B),
  ];

  /// Superficie de tarjetas/contenedores advertida del tema: blanco en claro
  /// y azul oscuro en modo oscuro. Evita texto blanco sobre blanco.
  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF151F36)
          : Colors.white;

  /// Borde de las mismas superficies según el modo.
  static Color surfaceBorderOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade800
          : Colors.grey.shade200;

  /// Texto secundario legible en claro y oscuro.
  static Color secondaryTextOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade400
          : Colors.grey.shade600;

  /// Texto de máximo contraste: títulos, cifras y lo que debe leerse primero.
  static Color primaryTextOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : const Color(0xFF0B1524);

  /// Texto terciario: etiquetas small-caps, unidades y metadatos que solo
  /// sirven de apoyo. Nunca para información que el usuario deba leer primero.
  static Color tertiaryTextOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade500
          : Colors.grey.shade500;

  // Tema de luz
  static ThemeData light() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      surface: const Color(0xFFF7F9FC),
    );

    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SlideFadePageTransitionsBuilder(),
          TargetPlatform.iOS: _SlideFadePageTransitionsBuilder(),
          TargetPlatform.windows: _SlideFadePageTransitionsBuilder(),
          TargetPlatform.macOS: _SlideFadePageTransitionsBuilder(),
          TargetPlatform.linux: _SlideFadePageTransitionsBuilder(),
        },
      ),
      colorScheme: baseScheme.copyWith(
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: accentColor,
        surface: const Color(0xFFF7F9FC),
        onSurface: const Color(0xFF111827),
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F9FC),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Color(0xFF111827)),
        titleTextStyle: TextStyle(
          color: Color(0xFF111827),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: TextStyle(color: Colors.grey.shade500),
        labelStyle: TextStyle(color: Colors.grey.shade700),
        prefixIconColor: primaryColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: errorColor),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEAF1FF),
        selectedColor: primaryColor,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dividerTheme: DividerThemeData(color: Colors.grey.shade200),
    );
  }

  // Tema de oscuridad
  static ThemeData dark() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: baseScheme.copyWith(
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: accentColor,
        surface: const Color(0xFF0F1526),
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF0B1020),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111A2E),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        prefixIconColor: primaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF151F36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

/// Transición de página: el nuevo contenido entra con deslizamiento lateral
/// y desvanecimiento, manteniendo la anterior estática. Da un toque moderno.
class _SlideFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _SlideFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.settings.name == '/' &&
        animation.status == AnimationStatus.reverse) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
