import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/utils/money.dart';
import 'package:muevex/core/widgets/animations.dart';
import 'package:muevex/core/widgets/muevex_logo.dart';
import 'package:muevex/core/widgets/state_views.dart';
import 'package:muevex/core/widgets/skeleton_shimmer.dart';
import 'package:muevex/core/supabase/supabase_client.dart' as api;
import 'package:muevex/core/widgets/muevex_snackbar.dart';
import 'package:muevex/core/widgets/invoice_sheet.dart';
import 'package:muevex/core/widgets/rating_bottom_sheet.dart';
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

  /// Cuántos servicios terminados se listan en el home.
  ///
  /// Con veinte mudanzas el home se convierte en un scroll infinito de
  /// tarjetas viejas y el servicio que importa (el que se acaba de
  /// completar, el que hay que calificar) queda enterrado.
  static const int _kHistorialVisibles = 5;

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
                        const SizedBox(height: 26),
                        StaggeredEntrance(
                          index: 1,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Mis servicios',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: MuevexTheme.primaryTextOf(context),
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (profileAsync.value != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: MuevexTheme.primaryColor
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${profileAsync.value!.totalServices}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: MuevexTheme.primaryColor,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              if (profileAsync.value != null)
                                Text(
                                  'en tu historial',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: MuevexTheme.tertiaryTextOf(context),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        servicesAsync.when(
                          data: (services) {
                            final current = services
                                .where((s) =>
                                    s.status.isActive ||
                                    s.status == ServiceStatus.solicitado)
                                .toList();
                            // Los finalizados también se listan, y no es
                            // cosmético: al completarse un servicio la tarjeta
                            // desaparecía de la lista y con ella el único
                            // punto de entrada a "Calificar" y a la
                            // minifactura. El botón existía, pero no había
                            // dónde verlo.
                            final past = services
                                .where((s) =>
                                    !s.status.isActive &&
                                    s.status != ServiceStatus.solicitado)
                                .toList()
                              ..sort(
                                  (a, b) => b.createdAt.compareTo(a.createdAt));
                            final shown =
                                past.take(_kHistorialVisibles).toList();

                            if (current.isEmpty && shown.isEmpty) {
                              return _EmptyState(
                                  onCreate: () => context.go('/map'));
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (current.isEmpty)
                                  const _Subheading(
                                      text: 'Sin servicios activos')
                                else
                                  const _Subheading(text: 'En curso'),
                                const SizedBox(height: 10),
                                for (var i = 0; i < current.length; i++)
                                  StaggeredEntrance(
                                    // `key` por servicio, no por posición:
                                    // sin él Flutter empareja cada ranura con
                                    // el State que ya hubiera, y como el State
                                    // de `_ServiceCard` guarda `_driver`,
                                    // `_driverLoading` y `_cancelling`, al
                                    // reordenarse la lista (cada evento
                                    // Realtime llega así) el botón "Cancelar"
                                    // se quedaba en "Cancelando…" para
                                    // siempre en otro servicio.
                                    key: ValueKey(current[i].id),
                                    index: i + 2,
                                    child: _ServiceCard(service: current[i]),
                                  ),
                                if (shown.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  _Subheading(
                                    text: past.length > shown.length
                                        ? 'Finalizados · últimos ${shown.length}'
                                        : 'Finalizados',
                                  ),
                                  const SizedBox(height: 10),
                                  for (var i = 0; i < shown.length; i++)
                                    StaggeredEntrance(
                                      key: ValueKey(shown[i].id),
                                      index: current.length + i + 2,
                                      child: _ServiceCard(service: shown[i]),
                                    ),
                                ],
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
                              message: 'No pudimos cargar tus servicios. '
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
          message: 'No pudimos cargar tu información. Verifica tu conexión.',
          onRetry: () => ref.invalidate(authProvider),
        ),
      ),
    );
  }
}

/// Rótulo de grupo dentro de "Mis servicios" ("En curso", "Finalizados").
///
/// Sin él, cuando hay servicios terminados y activos a la vez, la lista se lee
/// como un bloque plano y no se distingue lo que exige atención de lo que ya
/// pasó.
class _Subheading extends StatelessWidget {
  const _Subheading({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: MuevexTheme.tertiaryTextOf(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: MuevexTheme.surfaceBorderOf(context),
          ),
        ),
      ],
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
        : minutes < 60
            ? 'hace $minutes min'
            : 'hace ${(minutes / 60).floor()} h';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded,
            size: 12, color: MuevexTheme.tertiaryTextOf(context)),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: MuevexTheme.tertiaryTextOf(context),
          ),
        ),
      ],
    );
  }
}

class _ServiceCardState extends ConsumerState<_ServiceCard> {
  bool _cancelling = false;
  bool _rating = false;
  bool _alreadyRated = false;
  bool _generatingInvoice = false;

  /// Id de la factura ya emitida de este servicio, o null si todavía no tiene.
  ///
  /// Antes era un bool y el botón "Ver factura" no tenía forma de saber qué
  /// factura abrir. Se guarda el id, que es lo que necesita el visor.
  ///
  /// Ya no es un campo: sale del fetch compartido (ver [_invoiceIdEmitida]).
  api.DriverCardInfo? _driver;
  bool _driverLoading = false;

  Service get service => widget.service;

  @override
  void initState() {
    super.initState();
    _maybeLoadDriver();
    if (service.status == ServiceStatus.completado &&
        service.driverId != null) {
      _checkAlreadyRated();
    }
  }

  @override
  void didUpdateWidget(covariant _ServiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final statusChanged = oldWidget.service.status != service.status;
    final driverChanged = oldWidget.service.driverId != service.driverId;

    if (driverChanged) {
      _driver = null;
      _driverLoading = false;
      _alreadyRated = false;
      _maybeLoadDriver();
    }
    // Re-check rating eligibility when status becomes completado
    if (statusChanged || driverChanged) {
      if (service.status == ServiceStatus.completado &&
          service.driverId != null) {
        _checkAlreadyRated();
      }
    }
  }

  Future<void> _checkAlreadyRated() async {
    // Si la consulta falla se asume "no calificado": es el estado que deja el
    // botón disponible, y un intento de más devuelve el 23505 que ya se sabe
    // manejar. Lo contrario deja al cliente sin poder calificar sin explicación.
    var rated = false;
    try {
      rated = await api.hasClientRatedService(service.id);
    } catch (_) {}
    if (mounted) setState(() => _alreadyRated = rated);
  }

  /// Minifactura ya emitida de este servicio, leída del fetch compartido.
  ///
  /// Antes cada tarjeta pedía **todas** las facturas del cliente por su cuenta
  /// (`_checkHasInvoice`): con diez servicios completados eran diez consultas
  /// idénticas. Ahora todas leen el mismo mapa de
  /// [myInvoicesByServiceProvider], que se pide una vez.
  ///
  /// Devuelve `null` mientras el mapa no llega, y por eso los botones se
  /// esconden hasta entonces: si no, un servicio que ya tiene minifactura
  /// mostraría un instante "Generar minifactura".
  String? get _invoiceIdEmitida {
    final facturas = ref.watch(myInvoicesByServiceProvider).value;
    if (facturas == null) return null;
    return facturas[service.id]?.id;
  }

  bool get _facturasCargadas {
    final async = ref.watch(myInvoicesByServiceProvider);
    // Mientras el mapa está en camino, los botones se esconden: si se pintaran
    // antes, un servicio que ya tiene minifactura mostraría un instante
    // "Generar minifactura". En cuanto llega, se muestran los que toca.
    //
    // Si la carga **falla**, en cambio, sí se muestran. Escondérolos dejaría al
    // cliente sin minifactura y sin explicación, y tocar "Generar" es
    // inofensivo: `crear_factura_desde_servicio` y `emitir_factura` son
    // idempotentes, así que devuelven la que ya existía en vez de duplicar.
    return !async.isLoading;
  }

  Future<void> _maybeLoadDriver() async {
    final driverId = service.driverId;
    if (driverId == null || service.status == ServiceStatus.solicitado) return;
    setState(() => _driverLoading = true);
    // El `finally` no es opcional aquí: sin él, un fallo de red dejaba
    // `_driverLoading` en true para siempre y la tarjeta se quedaba en shimmer
    // el resto de la sesión, sin botón de calificar y sin explicación.
    try {
      final card = await api.getDriverCard(driverId);
      if (mounted) setState(() => _driver = card);
    } catch (_) {
      // Sin ficha no se pinta el bloque del conductor; el resto de la tarjeta
      // (estado, ruta, acciones) sigue siendo correcto y utilizable.
    } finally {
      if (mounted) setState(() => _driverLoading = false);
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
      if (!mounted) return;
      setState(() => _cancelling = false);
      ref.invalidate(customerServicesProvider);
    }
  }

  Future<void> _rateService() async {
    final driverId = service.driverId;
    if (driverId == null || _alreadyRated || _rating) return;
    // La cabecera del sheet necesita el nombre del conductor. Si la ficha no
    // cargó, el botón no debe quedarse en silencio: un botón que al pulsarlo no
    // hace nada es peor que no tenerlo.
    if (_driver == null) {
      _maybeLoadDriver();
      showMuevexSnackBar(
        context,
        message:
            'No pudimos cargar los datos del conductor. Inténtalo de nuevo.',
        isError: true,
        icon: Icons.error_outline,
      );
      return;
    }
    setState(() => _rating = true);
    final ok = await showRatingBottomSheet(
      context,
      serviceId: service.id,
      driverId: driverId,
      driverName: _driver!.name,
      ref: ref,
    );
    if (ok && mounted) {
      setState(() => _alreadyRated = true);
    }
    if (mounted) setState(() => _rating = false);
  }

  Future<void> _generateInvoice() async {
    if (_generatingInvoice ||
        _invoiceIdEmitida != null ||
        service.driverId == null) {
      return;
    }
    setState(() => _generatingInvoice = true);
    try {
      final invoice = await api.createInvoiceFromService(service.id);
      if (!mounted) return;
      final publicada = await api.publicarMinifactura(invoice.id);
      if (!mounted) return;
      if (publicada != null) {
        // El botón no guarda el id: lo lee del fetch compartido, así que hay que
        // pedirlo otra vez para que la tarjeta pase de "Generar" a "Ver" sola.
        ref.invalidate(myInvoicesByServiceProvider);
        // Y se abre directamente, en vez de dejar solo el aviso: el cliente
        // acaba de pedir una minifactura y lo que quiere es verla. Pedirle que
        // vuelva a tocar "Ver" es un paso de sobra.
        await showInvoiceSheet(context, invoiceId: publicada.id);
      } else {
        if (mounted) {
          showMuevexSnackBar(
            context,
            message: 'Se creó la minifactura pero no se pudo publicar',
            isError: true,
            icon: Icons.error_outline,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showMuevexSnackBar(
          context,
          message: 'Error al generar la minifactura: $e',
          isError: true,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _generatingInvoice = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(service.status);
    final isActive = service.status.isActive;
    final canCancel = service.status == ServiceStatus.solicitado;
    final hasRoute =
        service.originName != null || service.destinationName != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MuevexTheme.surfaceBorderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          // Solo los servicios en curso se abren al mapa con un toque. En los
          // demás el toque tiene que caer en el botón que lo pide, no en el
          // botón equivocado por un dedo grande.
          onTap:
              isActive ? () => context.go('/service/${service.id}/map') : null,
          child: Column(
            children: [
              _buildHeader(context, color, isActive, canCancel),
              // La barra de fases va sobre el fondo de la tarjeta, justo
              // debajo del estado: es la respuesta a "¿en qué va?", y solo
              // importa mientras el viaje no ha terminado.
              if (isActive) _buildStepper(context),
              if (hasRoute) _buildRoute(context),
              if (service.driverId != null && !isActive)
                _buildDriver(context, color),
              _buildActions(context, color, isActive, canCancel),
            ],
          ),
        ),
      ),
    );
  }

  /// Barra de fases del viaje, sobre un fondo tenue para separarla del resto
  /// sin añadir otra línea divisoria.
  Widget _buildStepper(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      decoration: BoxDecoration(
        color: MuevexTheme.primaryColor.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.06 : 0.03,
        ),
      ),
      child: _ServiceStatusStepper(status: service.status),
    );
  }

  /// Franja superior: estado, tipo de servicio, precio y chevron.
  Widget _buildHeader(
    BuildContext context,
    Color color,
    bool isActive,
    bool canCancel,
  ) {
    // Solo carga y fotos: el texto libre ya aparece arriba como título, y
    // repetirlo aquí dos veces en la misma tarjeta se lee como un descuido.
    final meta = <String>[
      if (service.loadWeightKg > 0)
        '${service.loadWeightKg.toStringAsFixed(0)} kg'
      else if (service.photos.isNotEmpty)
        '${service.photos.length} foto${service.photos.length > 1 ? 's' : ''}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              _statusLabel(service.status),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _serviceTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.2,
                    color: MuevexTheme.primaryTextOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (service.estimatedPrice > 0) ...[
                      Text(
                        moneyConIva(service.estimatedPrice),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: MuevexTheme.secondaryColor,
                        ),
                      ),
                      if (meta.isNotEmpty || isActive || canCancel)
                        const SizedBox(width: 8),
                    ],
                    if (meta.isNotEmpty)
                      Flexible(
                        child: Text(
                          meta.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: MuevexTheme.tertiaryTextOf(context),
                          ),
                        ),
                      ),
                    // Elapsed se mueve solo: un contador congelado en "hace 5min"
                    // es peor que no ponerlo, porque el cliente ve que la app no
                    // se entera. Por eso sigue siendo un widget con timer y no un
                    // string calculado en el build de la tarjeta.
                    if (isActive || canCancel)
                      _ElapsedText(createdAt: service.createdAt),
                  ],
                ),
              ],
            ),
          ),
          if (isActive)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                color: MuevexTheme.primaryColor,
                size: 24,
              ),
            ),
        ],
      ),
    );
  }

  String _serviceTitle() {
    final carga = service.loadDescription;
    if (carga != null && carga.isNotEmpty) return carga;
    if (service.description.isNotEmpty) return service.description;
    return 'Servicio de mudanza';
  }

  /// Origen → destino con la línea que los une, al estilo de las apps de
  /// transporte. Es el dato que el cliente viene a mirar, así que va con más
  /// aire que el resto y sin bordes que lo compitan.
  Widget _buildRoute(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _routeNode(MuevexTheme.successColor, filled: true),
              Container(
                width: 2,
                height: 26,
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: MuevexTheme.tertiaryTextOf(context)
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              _routeNode(MuevexTheme.errorColor, filled: false),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _routeLine(
                  'ORIGEN',
                  service.originName ?? 'Ubicación actual',
                ),
                const SizedBox(height: 12),
                _routeLine('DESTINO', service.destinationName ?? 'Por definir'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeNode(Color c, {required bool filled}) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? c : MuevexTheme.surfaceOf(context),
        border: Border.all(color: c, width: 2.5),
      ),
    );
  }

  Widget _routeLine(String label, String value) {
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: MuevexTheme.tertiaryTextOf(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: MuevexTheme.primaryTextOf(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Ficha del conductor: avatar, nombre, reputación y llamada. Va separada
  /// por una línea porque es un bloque con su propia jerarquía, no un dato más
  /// de la lista.
  Widget _buildDriver(BuildContext context, Color color) {
    if (_driverLoading) {
      return Column(
        children: [
          _divider(context),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _shimmerCircle(44),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(120, 13),
                    const SizedBox(height: 7),
                    _shimmerBox(90, 11),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    final driver = _driver;
    if (driver == null) {
      // Aún no hay ficha (o el conductor la borró). No se muestra un hueco vacío:
      // el cliente ve sus servicios igual.
      return const SizedBox.shrink();
    }

    final phone = driver.phone;

    return Column(
      children: [
        _divider(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        MuevexTheme.primaryColor.withValues(alpha: 0.12),
                    backgroundImage: driver.photoUrl != null
                        ? NetworkImage(driver.photoUrl!)
                        : null,
                    child: driver.photoUrl == null
                        ? const Icon(Icons.person_rounded,
                            color: MuevexTheme.primaryColor, size: 22)
                        : null,
                  ),
                  if (driver.isVerified)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 13,
                          color: MuevexTheme.primaryColor,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            driver.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                              color: MuevexTheme.primaryTextOf(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _ratingPill(context, driver.rating),
                      ],
                    ),
                    if (_vehicleLine(driver).isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _vehicleLine(driver),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: MuevexTheme.secondaryTextOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (phone != null && phone.isNotEmpty)
                _iconAction(
                  context,
                  icon: Icons.phone_rounded,
                  tooltip: 'Llamar al conductor',
                  onTap: () => _callDriver(phone),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _vehicleLine(api.DriverCardInfo d) {
    final parts = <String>[
      if ((d.plate ?? '').isNotEmpty) d.plate!.toUpperCase(),
      if ((d.vehicleType ?? '').isNotEmpty) d.vehicleType!,
    ];
    return parts.join(' · ');
  }

  Widget _ratingPill(BuildContext context, double rating) {
    final shown = rating > 0 ? rating.toStringAsFixed(1) : '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: MuevexTheme.warningColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded,
              size: 12, color: MuevexTheme.warningColor),
          const SizedBox(width: 2),
          Text(
            shown,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconAction(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: MuevexTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 19, color: MuevexTheme.primaryColor),
          ),
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(
        height: 1,
        color: MuevexTheme.surfaceBorderOf(context).withValues(alpha: 0.7),
      );

  Widget _shimmerBox(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: MuevexTheme.tertiaryTextOf(context).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
      );

  Widget _shimmerCircle(double d) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: MuevexTheme.tertiaryTextOf(context).withValues(alpha: 0.14),
        ),
      );

  // ── Acciones ─────────────────────────────────────────────────────────────
  // Los botones van en `Wrap` y no en `Row`: con cuatro acciones a la vez
  // un `Row` de `Expanded` las deja ilegibles en pantallas estrechas, y
  // partir el ancho a partes iguales es justo lo que produce texto cortado.
  Widget _buildActions(
    BuildContext context,
    Color color,
    bool isActive,
    bool canCancel,
  ) {
    final buttons = <Widget>[];

    if (canCancel) {
      buttons.add(_ghostButton(
        context,
        label: 'Cancelar',
        icon: Icons.close_rounded,
        color: MuevexTheme.errorColor,
        busy: _cancelling,
        onTap: _cancelService,
      ));
    }

    if (isActive) {
      buttons.add(_primaryButton(
        context,
        label: 'Ver en mapa',
        icon: Icons.map_rounded,
        color: MuevexTheme.primaryColor,
        gradient: MuevexTheme.primaryGradient,
        onTap: () => context.go('/service/${service.id}/map'),
      ));
    }

    if (!isActive && service.status == ServiceStatus.completado) {
      if (service.driverId != null && !_alreadyRated) {
        buttons.add(_ghostButton(
          context,
          label: 'Calificar',
          icon: Icons.star_rounded,
          color: MuevexTheme.warningColor,
          busy: _rating,
          onTap: _rateService,
        ));
      } else if (_alreadyRated) {
        buttons.add(_staticBadge(
          context,
          label: 'Calificado',
          icon: Icons.check_circle_rounded,
          color: MuevexTheme.successColor,
        ));
      }

      if (_facturasCargadas) {
        if (_invoiceIdEmitida == null && service.driverId != null) {
          buttons.add(_primaryButton(
            context,
            label: 'Generar minifactura',
            icon: Icons.receipt_long_rounded,
            color: MuevexTheme.successColor,
            busy: _generatingInvoice,
            onTap: _generateInvoice,
            iconColor: Colors.white,
          ));
        } else if (_invoiceIdEmitida != null) {
          buttons.add(_ghostButton(
            context,
            label: 'Ver minifactura',
            icon: Icons.receipt_long_rounded,
            color: MuevexTheme.successColor,
            onTap: () =>
                showInvoiceSheet(context, invoiceId: _invoiceIdEmitida!),
          ));
        }
      }
    }

    if (buttons.isEmpty) return const SizedBox(height: 4);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: MuevexTheme.surfaceBorderOf(context).withValues(alpha: 0.7),
          ),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: buttons,
      ),
    );
  }

  /// Botón con relleno de color. Es la acción que el usuario quiere hacer, así
  /// que va sólido; todo lo demás es [_ghostButton].
  Widget _primaryButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    LinearGradient? gradient,
    bool busy = false,
    Color? iconColor,
  }) {
    final fg = iconColor ?? Colors.white;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 42),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          color: gradient == null ? color : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: FilledButton.icon(
          onPressed: busy ? null : onTap,
          style: FilledButton.styleFrom(
            backgroundColor: gradient == null ? color : Colors.transparent,
            foregroundColor: fg,
            disabledBackgroundColor: color.withValues(alpha: 0.45),
            disabledForegroundColor: Colors.white70,
            elevation: 0,
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: busy
              ? SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Icon(icon, size: 17, color: fg),
          label: Text(label),
        ),
      ),
    );
  }

  /// Botodo delineado: acciones secundarias o destructivas. Nunca compite con
  /// el botón sólido de la misma fila.
  Widget _ghostButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 42),
      child: OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          backgroundColor: color.withValues(alpha: 0.05),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        icon: busy
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(icon, size: 17, color: color),
        label: Text(label),
      ),
    );
  }

  /// Etiqueta de estado ya alcanzado ("Calificado"). No es un botón: es un
  /// hecho. Se pinta como texto plano sobre fondo suave para que no parezca
  /// pulsable y nadie gasta un toque en descubrir que no hace nada.
  Widget _staticBadge(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _callDriver(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      showMuevexSnackBar(
        context,
        message: 'No se pudo abrir el teléfono',
        isError: true,
        icon: Icons.error_outline,
      );
    }
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
