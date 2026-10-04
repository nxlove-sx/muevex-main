import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:muevex/core/models/notification_model.dart';
import 'package:muevex/core/services/notification_service.dart';
import 'package:muevex/core/supabase/supabase_client.dart';
import 'package:muevex/features/auth/providers/auth_provider.dart';
import 'package:muevex/features/notifications/presentation/pages/notifications_page.dart';

/// Mantiene una suscripción de Realtime **siempre viva** a la tabla
/// `notifications` del usuario autenticado.
///
/// Se watched desde la raíz de la app ([MuevexApp]) para que:
///
///  1. La suscripción exista aunque el usuario nunca abra la bandeja de
///     notificaciones (antes solo arrancaba al abrir la página, así que no
///     sonaba nada si la app estaba en otra pantalla).
///  2. Cada `INSERT` dispare una notificación local **con sonido**.
///  3. Se refresque el contador de no leídas del header.
///
/// Al cerrar sesión el canal se cancela automáticamente porque el provider
/// vuelve a mirar `authProvider` y se reconstruye.
final realtimeNotificationListenerProvider = Provider<void>((ref) {
  final user = ref.watch(authProvider).value;
  if (user == null) return;

  final channel = supabase
      .channel('realtime-notifications:${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          column: 'user_id',
          type: PostgresChangeFilterType.eq,
          value: user.id,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isEmpty) return;

          final AppNotification n;
          try {
            n = AppNotification.fromMap(row);
          } catch (e) {
            debugPrint('MUEVEX: no se pudo parsear la notificación: $e');
            return;
          }

          // La BD ya trae `title` y `message` legibles; se usan tal cual
          // para no perder información del backend.
          unawaited(
            notificationService.showOrderEventNotification(
              type: n.type,
              userRole: 'customer',
              data: n.data,
              title: n.title,
              body: n.message,
            ),
          );

          // Refresca la bandeja y el badge de no leídas.
          ref.invalidate(notificationsProvider);
          ref.invalidate(unreadNotificationsCountProvider);
        },
      )
      .subscribe();

  ref.onDispose(() {
    unawaited(supabase.removeChannel(channel));
  });
});
