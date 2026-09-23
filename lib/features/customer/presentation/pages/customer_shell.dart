import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/features/customer/presentation/pages/customer_home_page.dart';
import 'package:muevex/features/customer/presentation/pages/history_page.dart';
import 'package:muevex/features/profile/presentation/pages/profile_page.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const CustomerHomePage(),
      const HistoryPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        indicatorColor: MuevexTheme.primaryColor.withValues(alpha: 0.15),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: MuevexTheme.primaryColor),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: MuevexTheme.primaryColor),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: MuevexTheme.primaryColor),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}