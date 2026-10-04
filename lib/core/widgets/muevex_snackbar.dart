import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Muestra un SnackBar con la identidad MUEVEX: flotante, fondo oscuro,
/// icono según el tipo (éxito/error/info) y esquinas redondeadas.
void showMuevexSnackBar(
  BuildContext context, {
  required String message,
  IconData icon = Icons.info_outline,
  bool isError = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final accentColor =
      isError ? MuevexTheme.errorColor : MuevexTheme.successColor;
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, color: accentColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF111827),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 4),
      action: actionLabel != null && onAction != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: accentColor,
              onPressed: onAction,
            )
          : null,
    ),
  );
}
