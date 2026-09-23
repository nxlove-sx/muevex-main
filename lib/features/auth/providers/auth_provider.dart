import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muevex/core/models/user_model.dart' as muevex_user;
import 'package:muevex/core/supabase/supabase_client.dart';

/// Auth provider - manejo de estado de autenticación
final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<muevex_user.User?>>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<AsyncValue<muevex_user.User?>> {
  AuthNotifier() : super(const AsyncValue.data(null)) {
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    supabase.auth.onAuthStateChange.listen((event) async {
      final session = event.session;
      if (session != null) {
        try {
          final user = await getUserProfile(session.user.id);
          state = AsyncValue.data(user);
        } catch (e) {
          state = AsyncValue.error(e, StackTrace.current);
        }
      } else {
        state = const AsyncValue.data(null);
      }
    });
  }

  Future<muevex_user.User> _getUserProfile(String userId) async {
    return await getUserProfile(userId);
  }

  /// Login con email y contraseña
  Future<bool> login(String email, String password) async {
    try {
      state = const AsyncValue.loading();
      final res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      debugPrint('MUEVEX login: user=${res.user?.id}');
      if (res.user != null) {
        final user = await _getUserProfile(res.user!.id);
        state = AsyncValue.data(user);
        return true;
      }
      state = const AsyncValue.data(null);
      return false;
    } catch (e, st) {
      debugPrint('MUEVEX login ERROR: $e\n$st');
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Registro con email y contraseña
  Future<AuthRegisterResult> register(
      String email, String password, String name,
      muevex_user.UserRole role) async {
    try {
      state = const AsyncValue.loading();
      final authRes = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (authRes.user == null) {
        state = const AsyncValue.data(null);
        return AuthRegisterResult.failure;
      }
      final confirmed = authRes.user!.emailConfirmedAt != null ||
          (authRes.user!.identities?.isNotEmpty ?? false);
      if (!confirmed) {
        // Correo sin verificar: no creamos perfiles hasta confirmarlo.
        state = const AsyncValue.data(null);
        return AuthRegisterResult.needsEmailConfirm;
      }

      await supabase.from('users').insert({
        'id': authRes.user!.id,
        'email': email,
        'role': role.name,
        'name': name,
      });

      if (role == muevex_user.UserRole.customer) {
        await supabase.from('customer_profiles').insert({
          'id': authRes.user!.id,
          'user_id': authRes.user!.id,
          'phone': '',
          'rating': 0,
          'total_services': 0,
        });
      }

      final user = muevex_user.User(
        id: authRes.user!.id,
        email: email,
        role: role,
        name: name,
        createdAt: DateTime.now(),
      );
      state = AsyncValue.data(user);
      return AuthRegisterResult.success;
    } catch (e, st) {
      debugPrint('MUEVEX register ERROR: $e\n$st');
      state = AsyncValue.error(e, st);
      return AuthRegisterResult.failure;
    }
  }

  /// Cerrar sesión
  Future<void> logout() async {
    await supabase.auth.signOut();
    state = const AsyncValue.data(null);
  }
}

/// Role selector provider - para saber rol actual
final userRoleProvider = StateProvider<muevex_user.UserRole?>((ref) {
  final user = ref.watch(authProvider);
  return user.whenData((u) => u?.role).value;
});

/// Onboarded provider - si el usuario completó el onboarding
final onboardedProvider = StateProvider<bool>((ref) => false);

/// Complete profile provider
final completeProfileProvider = StateProvider<bool>((ref) => false);

/// Resultado del registro con verificación de correo.
enum AuthRegisterResult { success, needsEmailConfirm, failure }
