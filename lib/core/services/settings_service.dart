// lib/core/services/settings_service.dart
//
// App settings, persisted in SharedPreferences. Currently: locale override
// (null = follow the system, the default).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService with ChangeNotifier {
  static const _localeKey = 'app_locale';

  Locale? _locale;

  /// Forced app locale; null follows the system locale.
  Locale? get locale => _locale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    _locale = (code == null || code.isEmpty) ? null : Locale(code);
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale?.languageCode ?? '');
  }
}
