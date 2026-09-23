import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modo claro/oscuro seleccionado (persistido en shared_preferences).
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

class ThemePrefs {
  ThemePrefs._();

  /// Lee la preferencia guardada (llamarlo antes de runApp).
  static Future<ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool('darkMode') ?? false)
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  static Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', mode == ThemeMode.dark);
  }
}
