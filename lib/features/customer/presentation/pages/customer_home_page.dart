import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/utils/money.dart';
import 'package:muevex/core/widgets/animations.dart';
import 'package:muevex/core/widgets/muevex_logo.dart';
import 'package:muevex/core/widgets/state_views.dart';
import 'package:muevex/core/widgets/skeleton_shimmer.dart';
import 'package:muevex/core/supabase/supabase_client.dart' as api;
import 'package:muevex/core/widgets/muevex_snackbar.dart';
import 'package:muevex/features/auth/providers/auth_provider.dart';
import 'package:muevex/features/notifications/presentation/pages/notifications_page.dart';
import 'package:muevex/features/customer/providers/customer_providers.dart';
import 'package:muevex/core/models/service_model.dart';

Color _statusColor(ServiceStatus status) {
  switch (status) {
    case ServiceStatus.solicitado:
      return MuevexTheme.warningColor;
    case ServiceStatus.aceptado:
      return MuevexTheme.primaryColor;
    case ServiceStatus.enRecogida:
      return MuevexTheme.accentColor;
    case ServiceStatus.enCurso:
      return MuevexTheme.secondaryColor;
    case ServiceStatus.completado:
      return MuevexTheme.successColor;
    case ServiceStatus.canceladoCliente:
    case ServiceStatus.canceladoConductor:
      return MuevexTheme.errorColor;
  }
}

/// Saludo calido según la hora del dispositivo.
String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 6) return 'Buenas noches';
  if (hour < 12) return 'Buenos días';
  if (hour < 19) return 'Buenas tardes';
  return 'Buenas noches';
}

class CustomerHomePage extends ConsumerWidget {
  const CustomerHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authProvider);
    final servicesAsync = ref.watch(customerServicesProvider);
    final profileAsync = ref.watch(customerProfileProvider);

    return Scaffold(
      drawer: userAsync.when(
        data: (userData) => Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration:
                    const BoxDecoration(gradient: MuevexTheme.primaryGradient),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.person,
                        color: MuevexTheme.primaryColor,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      userData?.name ?? 'Cliente',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      userData?.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.person, color: MuevexTheme.primaryColor),
                title: const Text('Mi Perfil'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/profile'),
              ),
              ListTile(
                leading: Badge.count(
                  count: ref.watch(unreadNotificationsCountProvider),
                  isLabelVisible:
                      ref.watch(unreadNotificationsCountProvider) > 0,
                  backgroundColor: MuevexTheme.errorColor,
                  textColor: Colors.white,
                  child: const Icon(Icons.notifications_none,
                      color: MuevexTheme.primaryColor),
                ),
                title: const Text('Notificaciones'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/notifications'),
              ),
              const Divider(),
              ListTile(
                leading:
                    const Icon(Icons.logout, color: MuevexTheme.errorColor),
                title: const Text('Cerrar Sesión',
                    style: TextStyle(color: MuevexTheme.errorColor)),
                onTap: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) context.go('/splash');
                },
              ),
            ],
          ),
        ),
        loading: () => const Drawer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Cargando tu perfil…',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ),
        error: (e, _) => const Drawer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No se pudo cargar tu perfil.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
      body: userAsync.when(
        data: (userData) => Column(
          children: [
            // Cabecera con gradiente y saludo
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                  20, MediaQuery.of(context).padding.top + 12, 20, 100),
              decoration: const BoxDecoration(
                gradient: MuevexTheme.primaryGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Stack(
                children: [
                  // Burbujas de luz decorativas
                  Positioned(
                    right: -60,
                    top: -70,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.28),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -40,
                    bottom: -60,
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            MuevexTheme.accentColor.withValues(alpha: 0.35),
                            MuevexTheme.accentColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40,
                    left: 130,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFFF8A3D).withValues(alpha: 0.4),
                            const Color(0xFFFF8A3D).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, -12 * (1 - t)),
                        child: child,
                      ),
                    ),
                    child: Row(
                      children: [
                        Builder(
                          builder: (context) => IconButton(
                            tooltip: 'Menú',
                            icon: const Icon(Icons.menu,
                                color: Colors.white, size: 28),
                            onPressed: Scaffold.of(context).openDrawer,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const MuevexLogo(size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_greeting()}, ${userData?.name ?? 'Cliente'}!',
                                style: const TextStyle(
                                  fontSize: 22,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                '¿Qué necesitas mover hoy?',
                                style: TextStyle(
                                    fontSize: 14, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ],
            ),
            ),
            // Contenido superpuesto
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -70),
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(customerServicesProvider);
                    await ref
                        .read(customerServicesProvider.future)
                        .catchError((_) => const <Service>[]);
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // CTA crear servicio
                      StaggeredEntrance(
                        index: 0,
                        child: PressableScale(
                          pressedScale: 0.98,
                          child: Material(
                            color: Colors.transparent,
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: MuevexTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: MuevexTheme.primaryColor
                                        .withValues(alpha: 0.35),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => context.go('/map'),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: const Icon(
                                          Icons.local_shipping_rounded,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Nuevo Servicio',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Solicita mover tus muebles y cargas',
                                              style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right,
                                          color: Colors.white, size: 28),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      StaggeredEntrance(
                        index: 1,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Mis servicios',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            if (profileAsync.value != null)
                              Text(
                                '${profileAsync.value!.totalServices} en total',
                                style: TextStyle(
                                    color: MuevexTheme.secondaryTextOf(context), fontSize: 13),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      servicesAsync.when(
                        data: (services) {
                          final current = services
                              .where((s) =>
                                  s.status.isActive ||
                                  s.status == ServiceStatus.solicitado)
                              .toList();
                          if (current.isEmpty && services.isEmpty) {
                            return _EmptyState(
                                onCreate: () => context.go('/map'));
                          }
                          return Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              if (current.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8),
                                  child: Text(
                                    'Sin servicios activos. Crea uno '
                                    'nuevo para empezar.',
                                    style: TextStyle(
                                        color: MuevexTheme.secondaryTextOf(context),
                                        fontSize: 13),
                                  ),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: current.length,
                                  itemBuilder: (context, index) =>
                                      StaggeredEntrance(
                                    index: index + 2,
                                    child: _ServiceCard(
                                        service: current[index]),
                                  ),
                                ),

                            ],
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 20, vertical: 28),
                          child: ServiceCardSkeleton(),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: MuevexErrorView(
                            message:
                                'No pudimos cargar tus servicios. '
                                'Verifica tu conexión e inténtalo de nuevo.',
                            onRetry: () =>
                                ref.invalidate(customerServicesProvider),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ],
        ),
        loading: () => const BrandLoadingView(
          message: 'Cargando tu información…',
        ),
        error: (e, _) => MuevexErrorView(
          message:
              'No pudimos cargar tu información. Verifica tu conexión.',
          onRetry: () => ref.invalidate(authProvider),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return MuevexEmptyView(
      icon: Icons.inventory_2_rounded,
      title: 'Aún no tienes servicios',
      subtitle: 'Crea tu primer servicio para empezar',
      actionLabel: 'Crear servicio',
      onAction: onCreate,
    );
  }
}

class _ServiceCard extends ConsumerStatefulWidget {
  final Service service;
  const _ServiceCard({required this.service});

  @override
  ConsumerState<_ServiceCard> createState() => _ServiceCardState();
}

/// Muestra cuánto hace que se solicitó el servicio, actualizándose cada
/// minuto. Da sensación de "vida real" a las tarjetas activas.
class _ElapsedText extends StatefulWidget {
  final DateTime createdAt;

  const _ElapsedText({required this.createdAt});

  @override
  State<_ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<_ElapsedText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes =
        DateTime.now().difference(widget.createdAt.toLocal()).inMinutes;
    final text = minutes < 1
        ? 'ahora'
        : 'hace $minutes min';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

class _ServiceCardState extends ConsumerState<_ServiceCard> {
  bool _cancelling = false;
  api.DriverCardInfo? _driver;
  bool _driverLoading = false;

  Service get service => widget.service;

  @override
  void initState() {
    super.initState();
    _maybeLoadDriver();
  }

  @override
  void didUpdateWidget(covariant _ServiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service.driverId != service.driverId) {
      _driver = null;
      _driverLoading = false;
      _maybeLoadDriver();
    }
  }

  Future<void> _maybeLoadDriver() async {
    final driverId = service.driverId;
    if (driverId == null || service.status == ServiceStatus.solicitado) return;
    setState(() => _driverLoading = true);
    final card = await api.getDriverCard(driverId);
    if (mounted) {
      setState(() {
        _driver = card;
        _driverLoading = false;
      });
    }
  }

  Future<void> _cancelService() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Cancelar solicitud?'),
        content: const Text(
          'Esta solicitud aún no tiene un conductor asignado. '
          'Si la cancelas podrás crear una nueva cuando quieras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _cancelling = true);
    try {
      await api.cancelService(service.id);
      if (mounted) {
        showMuevexSnackBar(
          context,
          message: 'Solicitud cancelada',
          icon: Icons.check_circle_outline,
        );
      }
    } catch (_) {
      if (mounted) {
        showMuevexSnackBar(
          context,
          message: 'No se pudo cancelar. Inténtalo de nuevo.',
          isError: true,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
      ref.invalidate(customerServicesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(service.status);
    final isActive = service.status.isActive;
    final canCancel = service.status == ServiceStatus.solicitado;
    return PressableScale(
      pressedScale: 0.98,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MuevexTheme.surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MuevexTheme.surfaceBorderOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.local_shipping_outlined, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.description.isEmpty
                        ? 'Servicio'
                        : service.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _statusLabel(service.status),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (service.estimatedPrice > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: MuevexTheme.secondaryColor
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            money(service.estimatedPrice),
                            style: const TextStyle(
                              color: MuevexTheme.secondaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (service.loadWeight > 0)
                        Text(
                          '${service.loadWeight.toStringAsFixed(0)} kg',
                          style: TextStyle(
                              fontSize: 12, color: MuevexTheme.secondaryTextOf(context)),
                        )
                      else if (service.photos.isNotEmpty)
                        Text(
                          '${service.photos.length} foto${service.photos.length > 1 ? 's' : ''}',
                          style: TextStyle(
                              fontSize: 12, color: MuevexTheme.secondaryTextOf(context)),
                        ),
                      if (isActive || canCancel) ...[
                        const SizedBox(width: 10),
                        _ElapsedText(createdAt: service.createdAt),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isActive || canCancel) ...[
              const SizedBox(height: 12),
              if (isActive)
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: MuevexTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          context.go('/service/${service.id}/map'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text(
                        'Seguir',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              if (canCancel)
                Align(
                  alignment: Alignment.center,
                  child: _cancelling
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                        )
                      : TextButton.icon(
                          onPressed: _cancelService,
                          style: TextButton.styleFrom(
                            foregroundColor: MuevexTheme.errorColor,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text(
                            'Cancelar solicitud',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
            ],
          ],
        ),
        if (service.status.isActive) ...[
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Divider(height: 10),
              ),
              _ServiceStatusStepper(status: service.status),
            ],
            if (service.status == ServiceStatus.solicitado) ...[
              const SizedBox(height: 10),
              const _SearchingForDriver(),
            ],
            if (_driverLoading && _driver == null) ...[
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Divider(height: 1),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Buscando tu conductor…',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
            if (_driver != null) ...[
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Divider(height: 1),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: isActive
                    ? () => context.go('/service/${service.id}/map')
                    : null,
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: MuevexTheme.primaryColor,
                          child: _driver!.photoUrl != null &&
                                  _driver!.photoUrl!.isNotEmpty
                              ? ClipOval(
                                  child: Image.network(
                                    _driver!.photoUrl!,
                                    width: 34,
                                    height: 34,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 20),
                                  ),
                                )
                              : const Icon(Icons.person,
                                  color: Colors.white, size: 20),
                        ),
                        if (_driver!.isVerified)
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: Container(
                              padding: const EdgeInsets.all(1),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.verified,
                                size: 12,
                                color: MuevexTheme.primaryColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Tu conductor · ${_driver!.name}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              ...List.generate(5, (i) => Icon(
                                    i < _driver!.rating.round()
                                        ? Icons.star
                                        : Icons.star_border,
                                    size: 13,
                                    color: i < _driver!.rating.round()
                                        ? Colors.amber
                                        : Colors.grey.shade400,
                                  )),
                              if (_driver!.hasVehicle) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.confirmation_number_outlined,
                                    size: 12, color: MuevexTheme.secondaryTextOf(context)),
                                const SizedBox(width: 2),
                                Text(
                                  _driver!.plate ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isActive)
                      const Icon(Icons.arrow_forward_ios,
                          size: 14, color: Colors.grey),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(ServiceStatus status) {
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
}

/// Indicador de progreso de las fases del viaje. Reduce la ansiedad de
/// espera mostrando en qué etapa va el servicio de un vistazo.
class _ServiceStatusStepper extends StatelessWidget {
  final ServiceStatus status;
  const _ServiceStatusStepper({required this.status});

  static const _phases = <(ServiceStatus, String)>[
    (ServiceStatus.solicitado, 'Solicitado'),
    (ServiceStatus.aceptado, 'Conductor'),
    (ServiceStatus.enRecogida, 'Recogida'),
    (ServiceStatus.enCurso, 'En camino'),
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = _phases.indexWhere((p) => p.$1 == status);
    if (currentIndex < 0) return const SizedBox.shrink();

    return Row(
      children: List.generate(_phases.length, (i) {
        final done = i <= currentIndex;
        final isCurrent = i == currentIndex;
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: done
                            ? MuevexTheme.primaryColor.withValues(alpha: 0.4)
                            : Colors.grey.shade200,
                      ),
                    ),
                  Container(
                    width: isCurrent ? 26 : 22,
                    height: isCurrent ? 26 : 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? MuevexTheme.primaryColor
                          : Colors.grey.shade200,
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: MuevexTheme.primaryColor
                                    .withValues(alpha: 0.35),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      isCurrent ? Icons.circle : Icons.check,
                      size: isCurrent ? 10 : 13,
                      color: isCurrent
                          ? Colors.white
                          : done
                              ? Colors.white
                              : Colors.grey.shade400,
                    ),
                  ),
                  if (i < _phases.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i < currentIndex
                            ? MuevexTheme.primaryColor.withValues(alpha: 0.4)
                            : Colors.grey.shade200,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                _phases[i].$2,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.1,
                  fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                  color: done
                      ? MuevexTheme.primaryColor.withValues(alpha: 0.9)
                      : Colors.grey.shade400,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Mensaje animado mientras un servicio está en estado "solicitado",
/// indicando que se está buscando un conductor disponible.
class _SearchingForDriver extends StatefulWidget {
  const _SearchingForDriver();

  @override
  State<_SearchingForDriver> createState() => _SearchingForDriverState();
}

class _SearchingForDriverState extends State<_SearchingForDriver>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ScaleTransition(
          scale: Tween(begin: 0.7, end: 1.0).animate(
            CurvedAnimation(
              parent: _controller,
              curve: Curves.easeInOut,
            ),
          ),
          child: FadeTransition(
            opacity: _controller.drive(
              Tween(begin: 0.4, end: 1.0),
            ),
            child: Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(left: 2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: MuevexTheme.primaryColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Esperando que un conductor acepte tu solicitud…',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
          ),
        ),
      ],
    );
  }
}

