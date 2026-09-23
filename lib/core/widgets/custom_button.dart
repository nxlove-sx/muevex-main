import 'package:flutter/material.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/widgets/animations.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? textColor;
  final double? height;
  final bool loading;
  final BorderRadius? borderRadius;
  final IconData? icon;
  final bool gradient;
  final bool enabled;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.backgroundColor,
    this.textColor,
    this.height,
    this.loading = false,
    this.borderRadius,
    this.icon,
    this.gradient = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && !loading;
    final color = enabled
        ? backgroundColor ?? MuevexTheme.primaryColor
        : Colors.grey.shade300;
    final foreground = enabled
        ? textColor ?? Colors.white
        : Colors.grey.shade600;
    final radius = borderRadius ?? BorderRadius.circular(14);
    final bg = gradient ? MuevexTheme.primaryGradient : null;

    final button = Material(
      color: canTap && gradient ? null : color,
      elevation: 0,
      borderRadius: radius,
      child: Ink(
        // Soporta gradiente o color sólido dentro del recorte del ink.
        decoration: BoxDecoration(
          gradient: canTap ? bg : null,
          color: canTap && gradient ? null : color,
          borderRadius: radius,
        ),
        child: InkWell(
          onTap: canTap ? onPressed : null,
          borderRadius: radius,
          splashColor: Colors.white24,
          highlightColor: Colors.transparent,
          child: Container(
            height: height ?? 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: enabled ? Colors.white : Colors.grey.shade600,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: foreground),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        text,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    // Escala sutil al presionar para feedback táctil.
    // La acción la dispara el InkWell interno; Listener solo anima la escala.
    return PressableScale(
      pressedScale: 0.97,
      child: button,
    );
  }
}