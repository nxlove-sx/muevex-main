import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muevex/core/providers/theme_provider.dart';
import 'package:muevex/core/supabase/supabase_client.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _setupGlobalErrorHandling();

  try {
    await initSupabase();
  } catch (e) {
    debugPrint('MUEVEX: No se pudo inicializar Supabase: $e');
  }

  final savedTheme = await ThemePrefs.load();

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith((ref) => savedTheme),
      ],
      child: const MuevexApp(),
    ),
  );
}



void _setupGlobalErrorHandling() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // En release el error ya fue presentado; se evita romper el frame.
    if (kDebugMode) {
      debugPrint('MUEVEX error: ${details.exceptionAsString()}');
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      debugPrint('MUEVEX platform error: $error');
    }
    return true;
  };
}

class MuevexApp extends ConsumerWidget {
  const MuevexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'MUEVEX',
      theme: MuevexTheme.light(),
      darkTheme: MuevexTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerDelegate: goRouter.routerDelegate,
      routeInformationParser: goRouter.routeInformationParser,
      routeInformationProvider: goRouter.routeInformationProvider,
    );
  }
}
