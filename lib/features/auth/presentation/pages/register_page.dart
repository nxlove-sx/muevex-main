import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:muevex/core/models/user_model.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/widgets/animations.dart';
import 'package:muevex/core/widgets/custom_button.dart';
import 'package:muevex/core/widgets/custom_text_field.dart';
import 'package:muevex/core/widgets/muevex_app_bar.dart';
import 'package:muevex/core/widgets/muevex_logo.dart';
import 'package:muevex/core/widgets/muevex_snackbar.dart';
import 'package:muevex/features/auth/providers/auth_provider.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();

  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    super.dispose();
  }

  bool get _formIsValid =>
      nameController.text.trim().length >= 2 &&
      emailController.text.trim().isNotEmpty &&
      _emailRegExp.hasMatch(emailController.text.trim()) &&
      passwordController.text.length >= 8;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final result = await ref.read(authProvider.notifier).register(
          emailController.text.trim(),
          passwordController.text,
          nameController.text.trim(),
          UserRole.customer,
        );
    if (!mounted) return;
    switch (result) {
      case AuthRegisterResult.success:
        context.go('/');
      case AuthRegisterResult.needsEmailConfirm:
        showMuevexSnackBar(
          context,
          message:
              'Revisa tu correo para confirmar la cuenta antes de iniciar sesión.',
          icon: Icons.mark_email_read_outlined,
        );
      case AuthRegisterResult.failure:
        showMuevexSnackBar(
          context,
          message: 'No se pudo crear la cuenta. Inténtalo de nuevo.',
          icon: Icons.person_add_alt_1_outlined,
          isError: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: MuevexGradientAppBar(
        title: 'Crear Cuenta',
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Logo
              const MuevexLogo(size: 84),
              const SizedBox(height: 20),
              const Text(
                'Regístrate como Cliente',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Crea tu cuenta y empieza a mover tus cosas hoy mismo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
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
                        index: 0,
                        child: CustomTextField(
                          controller: nameController,
                          label: 'Nombre completo',
                          prefixIcon: Icons.person,
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (value.length < 2) {
                              return 'Ingresa tu nombre completo';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      StaggeredEntrance(
                        index: 1,
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
                        index: 2,
                        child: CustomTextField(
                          controller: passwordController,
                          label: 'Contraseña',
                          obscureText: true,
                          prefixIcon: Icons.lock,
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            final value = v ?? '';
                            if (value.length < 6) {
                              return 'Mínimo 6 caracteres';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 28),
                      StaggeredEntrance(
                        index: 3,
                        child: CustomButton(
                          text: 'Registrarse',
                          icon: Icons.check_circle,
                          gradient: true,
                          height: 56,
                          enabled: _formIsValid,
                          loading: authState is AsyncLoading,
                          onPressed: _submit,
                        ),
                      ),
                      if (authState is AsyncError) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                MuevexTheme.errorColor.withValues(alpha: 0.08),
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
                                  'No se pudo crear la cuenta. Revisa los '
                                  'datos e inténtalo de nuevo.',
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '¿Ya tienes cuenta? ',
                    style: TextStyle(color: Colors.grey),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/login'),
                    child: const Text(
                      'Inicia sesión',
                      style: TextStyle(
                        color: MuevexTheme.primaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
