import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const String _key = 'theme_mode';
  SharedPreferences? _prefs; // nullable to guard against calls before async load completes (WR-001)
  ThemeMode _themeMode = ThemeMode.system;

  ThemeService() {
    _loadFromPrefs();
  }

  ThemeMode get themeMode => _themeMode;

  Future<void> _loadFromPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final String? themeStr = _prefs!.getString(_key);
    if (themeStr == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeStr == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final String themeStr = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';
    // Use cached _prefs if available; otherwise await a fresh instance.
    // This prevents a LateInitializationError if setThemeMode is called
    // before _loadFromPrefs() completes (WR-001 fix).
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(_key, themeStr);
  }
}
