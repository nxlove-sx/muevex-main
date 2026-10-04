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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: MuevexTheme.surfaceOf(context),
          border: Border(
            top: BorderSide(
              color: MuevexTheme.surfaceBorderOf(context),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _NavTab(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: 'Inicio',
                  selected: _index == 0,
                  onTap: () => setState(() => _index = 0),
                ),
                _NavTab(
                  icon: Icons.history_outlined,
                  selectedIcon: Icons.history,
                  label: 'Historial',
                  selected: _index == 1,
                  onTap: () => setState(() => _index = 1),
                ),
                _NavTab(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  label: 'Perfil',
                  selected: _index == 2,
                  onTap: () => setState(() => _index = 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color activeColor = MuevexTheme.primaryColor;
    final Color inactiveColor =
        MuevexTheme.secondaryTextOf(context).withValues(alpha: 0.6);

    return Expanded(
      child: Material(
        color: selected
            ? MuevexTheme.primaryColor.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 2),
          leading: Icon(
            selected ? selectedIcon : icon,
            color: selected ? activeColor : inactiveColor,
            size: 24,
          ),
          title: Text(
            label,
            style: TextStyle(
              color: selected ? activeColor : inactiveColor,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
