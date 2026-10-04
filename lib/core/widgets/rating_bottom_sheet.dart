/// Bottom sheet para que el cliente califique al conductor (1-5 estrellas +
/// comentario opcional).
///
/// Se muestra cuando un servicio está completado y el cliente aún no lo ha
/// calificado. Llama a [submitClientRating] y refresca el proveedor de
/// servicios.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muevex/core/supabase/supabase_client.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/widgets/muevex_snackbar.dart';
import 'package:muevex/features/customer/providers/customer_providers.dart';

/// Palabras de las cinco estrellas.
///
/// Sin ellas el usuario tiene que decidir cuánto es "bien" cada vez, y casi
/// todos marcan 4. La etiqueta dice qué se está midiendo en cada nivel.
const _kEtiquetas = <int, String>{
  1: 'Mala',
  2: 'Regular',
  3: 'Aceptable',
  4: 'Buena',
  5: 'Excelente',
};

/// Abre el bottom sheet de calificación.
///
/// Devuelve `true` si se envió la calificación, `false` si se canceló o falló.
Future<bool> showRatingBottomSheet(
  BuildContext context, {
  required String serviceId,
  required String driverId,
  required String driverName,
  required WidgetRef ref,
}) async {
  double stars = 0;
  final commentCtrl = TextEditingController();
  bool sending = false;

  // El snackbar se pinta en el contexto de la página, no en el del sheet: si se
  // pide antes de cerrar, `Navigator.pop` desmonta el sheet y el aviso se queda
  // a medio camino o se pierde.
  final rootContext = context;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final selected = stars.round();
        return Container(
          decoration: BoxDecoration(
            color: MuevexTheme.surfaceOf(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: MuevexTheme.surfaceBorderOf(ctx),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Avatar + nombre. Identificar a quién se está
                  // calificando antes de tocar las estrellas evita
                  // calificar a la persona equivocada.
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color:
                              MuevexTheme.warningColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          color: MuevexTheme.warningColor,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Califica a $driverName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: MuevexTheme.primaryTextOf(ctx),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tu opinión ayuda a mejorar el servicio',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: MuevexTheme.secondaryTextOf(ctx),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Estrellas
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) {
                        final filled = i < stars.round();
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setSheet(() => stars = i + 1.0),
                          onHorizontalDragUpdate: (details) {
                            const ancho = 48.0 * 5;
                            final localX =
                                (details.localPosition.dx / ancho) * 5;
                            setSheet(() =>
                                stars = localX.clamp(1, 5).ceilToDouble());
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Icon(
                              filled
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 46,
                              color: filled
                                  ? MuevexTheme.warningColor
                                  : MuevexTheme.surfaceBorderOf(ctx),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Qué significa la nota elegida. Sin esto las cinco
                  // estrellas son cinco botones iguales y el usuario
                  // elige a ciegas.
                  SizedBox(
                    height: 22,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        selected == 0
                            ? 'Toca una estrella'
                            : '${_kEtiquetas[selected]} · $selected de 5',
                        key: ValueKey(selected),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              selected == 0 ? FontWeight.w500 : FontWeight.w700,
                          color: selected == 0
                              ? MuevexTheme.tertiaryTextOf(ctx)
                              : MuevexTheme.warningColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Comentario opcional
                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    maxLength: 280,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      color: MuevexTheme.primaryTextOf(ctx),
                    ),
                    decoration: InputDecoration(
                      labelText: 'Comentario (opcional)',
                      hintText: '¿Cómo fue la experiencia?',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: MuevexTheme.surfaceBorderOf(ctx),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: MuevexTheme.primaryColor,
                          width: 1.5,
                        ),
                      ),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Enviar
                  FilledButton(
                    onPressed: selected == 0 || sending
                        ? null
                        : () async {
                            setSheet(() => sending = true);
                            final res = await submitClientRating(
                              serviceId: serviceId,
                              driverId: driverId,
                              score: stars,
                              comment: commentCtrl.text,
                            );
                            if (!ctx.mounted) return;
                            setSheet(() => sending = false);
                            if (res.ok) {
                              Navigator.pop(ctx, true);
                              if (rootContext.mounted) {
                                showMuevexSnackBar(
                                  rootContext,
                                  message: '¡Gracias por calificar!',
                                  icon: Icons.star_rounded,
                                );
                              }
                              ref.invalidate(customerServicesProvider);
                            } else {
                              // Si ya había calificado, cerrar es lo
                              // correcto: el usuario ya tiene lo que
                              // vino a hacer y dejarlo con un error en
                              // pantalla lo invita a insistir. El aviso
                              // se pinta en el contexto de la página,
                              // que sobrevive al cierre del sheet.
                              final destino =
                                  res.alreadyRated ? rootContext : ctx;
                              if (res.alreadyRated) {
                                Navigator.pop(ctx, false);
                              }
                              if (destino.mounted) {
                                showMuevexSnackBar(
                                  destino,
                                  message: res.error ??
                                      'No se pudo guardar la calificación',
                                  isError: true,
                                  icon: Icons.error_outline,
                                );
                              }
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: MuevexTheme.primaryColor,
                      disabledBackgroundColor:
                          MuevexTheme.primaryColor.withValues(alpha: 0.35),
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(
                            selected == 0
                                ? 'Enviar calificación'
                                : 'Enviar $selected de 5',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Solo puedes calificar una vez por servicio',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: MuevexTheme.tertiaryTextOf(ctx),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  commentCtrl.dispose();
  return result ?? false;
}
