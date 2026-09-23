import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/widgets/animations.dart';
import 'package:muevex/core/widgets/custom_button.dart';
import 'package:muevex/core/widgets/custom_text_field.dart';
import 'package:muevex/core/widgets/muevex_logo.dart';
import 'package:muevex/core/widgets/muevex_snackbar.dart';
import 'package:muevex/features/auth/providers/auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  bool get _formIsValid =>
      emailController.text.trim().isNotEmpty &&
      _emailRegExp.hasMatch(emailController.text.trim()) &&
      passwordController.text.length >= 6;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final success = await ref
        .read(authProvider.notifier)
        .login(
          emailController.text.trim(),
          passwordController.text,
        );
    if (!mounted) return;
    if (success) {
      context.go('/');
    } else {
      showMuevexSnackBar(
        context,
        message: 'No se pudieron validar tus credenciales.',
        icon: Icons.lock_outline,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      body: Stack(
        children: [
          // Cabecera con gradiente
          Container(
            height: MediaQuery.of(context).size.height * 0.36,
            decoration: const BoxDecoration(
              gradient: MuevexTheme.primaryGradient,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
            ),
          ),
          // Burbujas de luz decorativas sobre el gradiente
          Positioned(
            right: -50,
            top: 110,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: -70,
            top: 170,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    MuevexTheme.accentColor.withValues(alpha: 0.4),
                    MuevexTheme.accentColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  // Logo
                  StaggeredEntrance(
                    index: 0,
                    child: const MuevexLogo(size: 90),
                  ),
                  const SizedBox(height: 16),
                  StaggeredEntrance(
                    index: 1,
                    child: const Text(
                      'MUEVEX',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  StaggeredEntrance(
                    index: 2,
                    child: const Text(
                      'Inicia sesión para continuar',
                      style: TextStyle(fontSize: 15, color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Tarjeta principal
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StaggeredEntrance(
                            index: 3,
                            child: CustomTextField(
                              controller: emailController,
                              label: 'Correo',
                              keyboardType: TextInputType.emailAddress,
                              prefixIcon: Icons.email,
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                final value = v?.trim() ?? '';
                                if (value.isEmpty) {
                                  return 'Ingresa tu correo';
                                }
                                if (!_emailRegExp.hasMatch(value)) {
                                  return 'Ingresa un correo válido';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          StaggeredEntrance(
                            index: 4,
                            child: CustomTextField(
                              controller: passwordController,
                              label: 'Contraseña',
                              obscureText: true,
                              prefixIcon: Icons.lock,
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                final value = v ?? '';
                                if (value.isEmpty) {
                                  return 'Ingresa tu contraseña';
                                }
                                if (value.length < 6) {
                                  return 'Mínimo 6 caracteres';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          StaggeredEntrance(
                            index: 5,
                            child: CustomButton(
                              text: 'Entrar',
                              icon: Icons.login,
                              gradient: true,
                              height: 56,
                              enabled: _formIsValid,
                              loading: authState.isLoading,
                              onPressed: _submit,
                            ),
                          ),
                          if (authState is AsyncError) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: MuevexTheme.errorColor
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: MuevexTheme.errorColor
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 20,
                                    color: MuevexTheme.errorColor,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'No se pudo iniciar sesión. '
                                      'Revisa tus credenciales e inténtalo '
                                      'de nuevo.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: MuevexTheme.errorColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '¿No tienes cuenta? ',
                        style: TextStyle(color: Colors.grey),
                      ),
                      GestureDetector(
                        onTap: () => context.go('/register'),
                        child: const Text(
                          'Regístrate',
                          style: TextStyle(
                            color: MuevexTheme.primaryColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
