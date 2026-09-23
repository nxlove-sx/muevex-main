import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// AppBar con degradado de marca (azul → turquesa) y título en negrita.
///
/// Da a todas las secciones secundarias una cabecera consistente: fondo con
/// gradiente de la marca, iconos y título en blanco, y área de estado clara.
class MuevexGradientAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const MuevexGradientAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      leading: leading,
      actions: actions,
      bottom: bottom,
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: MuevexTheme.primaryGradient,
        ),
      ),
    );
  }
}