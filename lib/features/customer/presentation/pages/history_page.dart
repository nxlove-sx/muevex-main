import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:muevex/core/models/service_model.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/utils/money.dart';
import 'package:muevex/core/widgets/muevex_app_bar.dart';
import 'package:muevex/core/widgets/state_views.dart';
import 'package:muevex/core/widgets/skeleton_shimmer.dart';
import 'package:muevex/features/customer/providers/customer_providers.dart';
import 'package:muevex/features/service/providers/service_providers.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerServicesProvider);

    return Scaffold(
      appBar: MuevexGradientAppBar(
        title: 'Historial',
        leading: const SizedBox.shrink(),
      ),
      body: async.when(
        data: (services) {
          final history = services
              .where((s) =>
                  !s.status.isActive && s.status != ServiceStatus.solicitado)
              .toList();
          if (history.isEmpty) {
            return const MuevexEmptyView(
              icon: Icons.history_rounded,
              title: 'Aún no tienes historial',
              subtitle: 'Tus servicios completados o cancelados aparecerán aquí.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(customerServicesProvider);
              await ref.read(customerServicesProvider.future).catchError(
                  (_) => const <Service>[]);
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final service = history[index];
                return _HistoryCard(
                  service: service,
                  onRepeat: () {
                    ref.read(serviceFormProvider.notifier)
                        .fillFromService(service);
                    context.go('/service/create');
                  },
                );
              },
            ),
          );
        },
        loading: () => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: const Column(
            children: [
              HistoryTileSkeleton(),
              HistoryTileSkeleton(),
              HistoryTileSkeleton(),
              HistoryTileSkeleton(),
            ],
          ),
        ),
        error: (e, _) => MuevexErrorView(
          message: 'No pudimos cargar tu historial. Inténtalo de nuevo.',
          onRetry: () => ref.invalidate(customerServicesProvider),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Service service;
  final VoidCallback? onRepeat;
  const _HistoryCard({required this.service, this.onRepeat});

  bool get _completed => service.status == ServiceStatus.completado;

  @override
  Widget build(BuildContext context) {
    final color =
        _completed ? MuevexTheme.successColor : MuevexTheme.errorColor;
    final date = (service.completedAt ?? service.createdAt).toLocal();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MuevexTheme.surfaceBorderOf(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _completed ? Icons.check_rounded : Icons.close_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _routeLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_two(date.day)}/${_two(date.month)}/${date.year} · '
                  '${_two(date.hour)}:${_two(date.minute)} · '
                  '${_statusLabelOf(service.status)}',
                  style: TextStyle(fontSize: 11.5, color: MuevexTheme.secondaryTextOf(context)),
                ),
              ],
            ),
          ),
          if (_completed && service.priceTotal > 0) ...[
            const SizedBox(width: 8),
            Text(
              money(service.priceTotal),
              style: TextStyle(
                color: MuevexTheme.successColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (_completed && onRepeat != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Repetir servicio',
              icon: const Icon(Icons.replay_rounded,
                  color: MuevexTheme.primaryColor),
              onPressed: onRepeat,
            ),
          ],
        ],
      ),
    );
  }

  String _routeLabel() {
    final from = service.originName?.trim().isNotEmpty == true
        ? service.originName!.trim()
        : '${service.originLat.toStringAsFixed(3)}, '
            '${service.originLng.toStringAsFixed(3)}';
    final to = service.destinationName?.trim().isNotEmpty == true
        ? service.destinationName!.trim()
        : '${service.destinationLat.toStringAsFixed(3)}, '
            '${service.destinationLng.toStringAsFixed(3)}';
    return '$from → $to';
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}

String _statusLabelOf(ServiceStatus status) {
  switch (status) {
    case ServiceStatus.solicitado:
      return 'Solicitado';
    case ServiceStatus.aceptado:
      return 'Conductor asignado';
    case ServiceStatus.enRecogida:
      return 'En recogida';
    case ServiceStatus.enCurso:
      return 'En camino';
    case ServiceStatus.completado:
      return 'Completado';
    case ServiceStatus.canceladoCliente:
      return 'Cancelado';
    case ServiceStatus.canceladoConductor:
      return 'Cancelado';
  }
}