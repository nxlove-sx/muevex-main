import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/widgets/animations.dart';
import 'package:muevex/core/widgets/muevex_app_bar.dart';
import 'package:muevex/core/widgets/muevex_snackbar.dart';
import 'package:muevex/core/widgets/state_views.dart';
import 'package:muevex/core/providers/theme_provider.dart';
import 'package:muevex/core/supabase/supabase_client.dart' as api;
import 'package:muevex/features/auth/providers/auth_provider.dart';
import 'package:muevex/features/auth/providers/session_reset.dart';
import 'package:muevex/features/customer/providers/customer_providers.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authProvider);
    final profileAsync = ref.watch(customerProfileProvider);

    return Scaffold(
      appBar: MuevexGradientAppBar(
        title: 'Mi Perfil',
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: userAsync.when(
        data: (userData) => profileAsync.when(
          data: (customerProfile) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StaggeredEntrance(
                  index: 0,
                  child: Center(
                    child: Column(
                      children: [
                        // Anillo de pulso alrededor del avatar
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Anillo de pulso alrededor del avatar
                            Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: MuevexTheme.primaryGradient,
                                boxShadow: [
                                  BoxShadow(
                                    color: MuevexTheme.primaryColor
                                        .withValues(alpha: 0.3),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 112,
                              height: 112,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              alignment: Alignment.center,
                              child: CircleAvatar(
                                radius: 46,
                                backgroundColor: MuevexTheme.primaryColor,
                                child: Text(
                                  userData?.name.isNotEmpty == true
                                      ? userData!.name[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                      fontSize: 32, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          userData?.name ?? 'Usuario',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          userData?.email ?? '',
                          style:
                              TextStyle(fontSize: 16, color: MuevexTheme.secondaryTextOf(context)),
                        ),
                        const SizedBox(height: 8),
                        const Chip(
                          label: Text('CLIENTE'),
                          backgroundColor: MuevexTheme.successColor,
                          labelStyle: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (customerProfile != null) ...[
                  StaggeredEntrance(
                    index: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Información del Perfil',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _buildInfoRow(context, 'Teléfono',
                            customerProfile.phone ?? 'No registrado'),
                        _buildInfoRow(context, 'Dirección',
                            customerProfile.address ?? 'No registrada'),
                        _buildInfoRow(context, 
                            'Rating',
                            customerProfile.rating?.toStringAsFixed(1) ??
                                'N/A'),
                        _buildInfoRow(context, 'Total Servicios',
                            customerProfile.totalServices.toString()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                StaggeredEntrance(
                  index: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Acciones',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _actionTile(context, Icons.edit, 'Editar Perfil', () =>
                          _editProfile(context, ref, userData, customerProfile)),
                      _actionTile(context, Icons.lock_outline, 'Cambiar Contraseña', () =>
                          _changePassword(context, ref)),
                      _actionTile(context, Icons.payment, 'Métodos de Pago',
                          () => _showPaymentMethod(context)),
                      _actionTile(context, Icons.notifications, 'Notificaciones',
                          () => context.go('/notifications')),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: ref.watch(themeModeProvider) == ThemeMode.dark,
                        onChanged: (dark) async {
                          final mode =
                              dark ? ThemeMode.dark : ThemeMode.light;
                          ref.read(themeModeProvider.notifier).state = mode;
                          await ThemePrefs.save(mode);
                        },
                        secondary: const Icon(Icons.dark_mode_outlined,
                            color: MuevexTheme.primaryColor),
                        title: const Text('Modo Oscuro'),
                        subtitle: Text(
                          ref.watch(themeModeProvider) == ThemeMode.dark
                              ? 'Interfaz en modo oscuro'
                              : 'Interfaz en modo claro',
                          style: TextStyle(fontSize: 12, color: MuevexTheme.secondaryTextOf(context)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                StaggeredEntrance(
                  index: 3,
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout,
                          color: MuevexTheme.errorColor),
                      label: const Text('Cerrar Sesión',
                          style: TextStyle(color: MuevexTheme.errorColor)),
                      onPressed: () async {
                        invalidateSessionProviders(ref);
                        await ref.read(authProvider.notifier).logout();
                        if (context.mounted) context.go('/login');
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          loading: () =>
              const BrandLoadingView(message: 'Cargando tu perfil…'),
          error: (e, _) => MuevexErrorView(
            message:
                'No pudimos cargar tu perfil. Verifica tu conexión.',
            onRetry: () => ref.invalidate(customerProfileProvider),
          ),
        ),
        loading: () => const BrandLoadingView(message: 'Cargando tu perfil…'),
        error: (e, _) => MuevexErrorView(
          message:
              'No pudimos cargar tu sesión. Inicia sesión de nuevo.',
          onRetry: () => ref.invalidate(authProvider),
        ),
      ),
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña actual'),
                validator: (v) =>
                    (v != null && v.isNotEmpty) ? null : 'Ingresa tu contraseña actual',
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nueva contraseña'),
                validator: (v) => v == null || v.length < 8
                    ? 'Mínimo 8 caracteres'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
                validator: (v) => v != next.text ? 'Las contraseñas no coinciden' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final ok = await api.changePassword(
                currentPassword: current.text,
                newPassword: next.text,
              );
              if (ctx.mounted) Navigator.pop(ctx, ok);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (saved ?? false) {
      if (context.mounted) {
        showMuevexSnackBar(
          context,
          message: 'Contraseña actualizada.',
          icon: Icons.lock_outline,
        );
      }
    } else if (saved != null) {
      if (context.mounted) {
        showMuevexSnackBar(
          context,
          message: 'La contraseña actual no es correcta.',
          icon: Icons.lock,
          isError: true,
        );
      }
    }
  }

  void _showPaymentMethod(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Método de pago'),
        content: const Text(
            'Por ahora MUEVEX acepta pago en efectivo contra entrega. '
            'Pagos con tarjeta y monedero llegarán pronto.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    userData,
    customerProfile,
  ) async {
    final nameCtrl = TextEditingController(text: userData?.name ?? '');
    final phoneCtrl = TextEditingController(
        text: customerProfile?.phone ?? userData?.phone ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar perfil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Teléfono'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (saved != true || !context.mounted) return;
    final userId = userData?.id;
    if (userId == null) return;

    try {
      await api.supabase.from('users').update({'name': nameCtrl.text.trim()}).eq('id', userId);
      await api.supabase
          .from('customer_profiles')
          .update({'phone': phoneCtrl.text.trim()}).eq('user_id', userId);
      ref.invalidate(customerProfileProvider);
      ref.invalidate(authProvider);
      if (context.mounted) {
        showMuevexSnackBar(
          context,
          message: 'Perfil actualizado',
          icon: Icons.check_circle,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showMuevexSnackBar(
          context,
          message: 'No se pudo guardar el perfil. Inténtalo de nuevo.',
          icon: Icons.error_outline,
          isError: true,
        );
      }
    }
  }

  Widget _actionTile(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return PressableScale(
      pressedScale: 0.97,
      child: Material(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            leading: Icon(icon, color: MuevexTheme.primaryColor),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: MuevexTheme.secondaryTextOf(context))),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
