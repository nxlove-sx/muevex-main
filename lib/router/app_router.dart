import 'package:go_router/go_router.dart';

import 'package:muevex/core/supabase/supabase_client.dart' as api;
import 'package:muevex/features/splash/presentation/pages/splash_page.dart';
import 'package:muevex/features/auth/presentation/pages/login_page.dart';
import 'package:muevex/features/auth/presentation/pages/register_page.dart';
import 'package:muevex/features/customer/presentation/pages/customer_shell.dart';
import 'package:muevex/features/notifications/presentation/pages/notifications_page.dart';
import 'package:muevex/features/service/presentation/pages/create_service_page.dart';
import 'package:muevex/features/map/presentation/pages/map_screen.dart';
import 'package:muevex/features/map/presentation/pages/request_map_page.dart';
import 'package:muevex/features/profile/presentation/pages/profile_page.dart';

final GoRouter goRouter = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) {
    final logged = api.authed;
    final loc = state.matchedLocation;
    const publicRoutes = {'/splash', '/login', '/register'};
    if (!logged && !publicRoutes.contains(loc)) return '/login';
    if (logged && (loc == '/login' || loc == '/register')) return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashPage(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const CustomerShell(),
      routes: [
        GoRoute(
          path: 'map',
          builder: (context, state) => const RequestMapPage(),
        ),
        GoRoute(
          path: 'service/create',
          builder: (context, state) => const CreateServicePage(),
        ),
        GoRoute(
          path: 'service/:serviceId/map',
          builder: (context, state) => MapScreen(
            serviceId: state.pathParameters['serviceId']!,
          ),
        ),
        GoRoute(
          path: 'profile',
          builder: (context, state) => const ProfilePage(),
        ),
        GoRoute(
          path: 'notifications',
          builder: (context, state) => const NotificationsPage(),
        ),
      ],
    ),
  ],
);
