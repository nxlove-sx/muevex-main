import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Estados de carga, error y vacío reutilizables con la identidad MUEVEX.
/// Sustituyen los spinners planos y las tarjetas de error inconsistentes.

/// Carga con spinner de marca y mensaje contextual.
class BrandLoadingView extends StatelessWidget {
  final String message;

  const BrandLoadingView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: MuevexTheme.primaryColor,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: MuevexTheme.secondaryTextOf(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de error consistente con icono y botón de reintento opcional.
class MuevexErrorView extends StatelessWidget {
  final String message;
  final String title;
  final VoidCallback? onRetry;

  const MuevexErrorView({
    super.key,
    required this.message,
    this.title = 'Algo salió mal',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: MuevexTheme.surfaceOf(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: MuevexTheme.surfaceBorderOf(context)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: MuevexTheme.errorColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 36,
                  color: MuevexTheme.errorColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: MuevexTheme.secondaryTextOf(context)),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reintentar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MuevexTheme.primaryColor,
                      side: BorderSide(color: MuevexTheme.primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado vacío atractivo: icono en círculo suave + título + subtítulo + CTA.
class MuevexEmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const MuevexEmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MuevexTheme.surfaceBorderOf(context)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  MuevexTheme.primaryColor.withValues(alpha: 0.14),
                  MuevexTheme.primaryColor.withValues(alpha: 0.02),
                ],
              ),
            ),
            child: Center(
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: MuevexTheme.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MuevexTheme.primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  icon,
                  size: 36,
                  color: MuevexTheme.primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: MuevexTheme.secondaryTextOf(context)),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 20),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: MuevexTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}