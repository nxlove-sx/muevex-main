import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:muevex/core/models/notification_model.dart';
import 'package:muevex/core/supabase/supabase_client.dart';
import 'package:muevex/core/supabase/supabase_client.dart' as api;
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/widgets/muevex_app_bar.dart';
import 'package:muevex/core/widgets/state_views.dart';
import 'package:muevex/features/auth/providers/auth_provider.dart';

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  final user = ref.watch(authProvider).value;
  if (user == null) return <AppNotification>[];
  final channel = supabase
      .channel('customer-notifications:${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          column: 'user_id',
          type: PostgresChangeFilterType.eq,
          value: user.id,
        ),
        callback: (_) => ref.invalidateSelf(),
      )
      .subscribe();
  ref.onDispose(channel.unsubscribe);
  return api.getMyNotifications(user.id);
});

/// Notificaciones sin leer del cliente actual (para el badge del header).
final unreadNotificationsCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull;
  if (list == null) return 0;
  return list.where((n) => !n.read).length;
});

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool _autoMarked = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);

    // Al abrir la bandeja, marca todo como leído una sola vez.
    if (async.hasValue && async.value!.isNotEmpty && !_autoMarked) {
      _autoMarked = true;
      final user = ref.read(authProvider).value;
      if (user != null) {
        api.markAllNotificationsRead(user.id).then((_) {
          if (mounted) ref.invalidate(notificationsProvider);
        });
      }
    }

    return Scaffold(
      appBar: const MuevexGradientAppBar(title: 'Notificaciones'),
      body: async.when(
        loading: () =>
            const BrandLoadingView(message: 'Cargando notificaciones…'),
        error: (e, _) => MuevexErrorView(
          message:
              'No pudimos cargar tus notificaciones. '
              'Verifica tu conexión e inténtalo de nuevo.',
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(notificationsProvider),
          child: list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: const [
                    SizedBox(height: 24),
                    MuevexEmptyView(
                      icon: Icons.notifications_off_outlined,
                      title: 'Sin notificaciones',
                      subtitle:
                          'Aquí verás los avisos de tus servicios: '
                          'conductor asignado, estado del viaje y más.',
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _NotificationTile(n: list[i]),
                ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification n;
  const _NotificationTile({required this.n});

  (IconData, Color) get _style {
    return switch (n.type) {
      'service_accepted' =>
        (Icons.check_circle, MuevexTheme.successColor),
      'service_arrival' =>
        (Icons.place, MuevexTheme.primaryColor),
      'service_started' =>
        (Icons.local_shipping, MuevexTheme.accentColor),
      'service_completed' =>
        (Icons.celebration, MuevexTheme.successColor),
      'service_cancelled' || 'service_cancelled_by_driver' =>
        (Icons.cancel, MuevexTheme.errorColor),
      'new_rating' =>
        (Icons.star_rounded, MuevexTheme.warningColor),
      _ => (Icons.notifications_rounded, MuevexTheme.primaryColor),
    };
  }

  String get _timeAgo {
    final diff = DateTime.now().difference(n.createdAt.toLocal());
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return '${n.createdAt.day}/${n.createdAt.month}';
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style;
    final unread = !n.read;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unread
              ? color.withValues(alpha: 0.35)
              : MuevexTheme.surfaceBorderOf(context),
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.55)],
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        title: Text(
          n.title,
          style: TextStyle(
            fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          n.message,
          style: TextStyle(fontSize: 12.5, color: MuevexTheme.secondaryTextOf(context)),
        ),
        isThreeLine: n.message.length > 50,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unread)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              )
            else
              Icon(Icons.done_all_rounded,
                  size: 15, color: Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(
              _timeAgo,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}