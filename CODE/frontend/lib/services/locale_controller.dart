import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The farmer's chosen app language, persisted across restarts.
///
/// Null means "follow the device's system language" (falling back to English
/// if the device is set to something this app has no translation for, per
/// MaterialApp's own locale-resolution logic) - that is the default until
/// someone explicitly picks one from Profile -> Language.
class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  static const _kKey = 'app_locale';

  Locale? _locale;
  Locale? get locale => _locale;

  Future<void> preload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_kKey);
      if (code != null) _locale = Locale(code);
    } catch (e) {
      debugPrint('LocaleController: preload failed: $e');
    }
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(_kKey);
      } else {
        await prefs.setString(_kKey, locale.languageCode);
      }
    } catch (e) {
      debugPrint('LocaleController: persist failed: $e');
    }
  }
}
