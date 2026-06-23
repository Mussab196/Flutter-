import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  bool _isAuthenticated = false;
  bool _isDarkMode = true;

  AppProvider(this._prefs) {
    _loadPreferences();
  }

  bool get isAuthenticated => _isAuthenticated;
  bool get isDarkMode => _isDarkMode;

  void _loadPreferences() {
    _isAuthenticated = _prefs.getBool('aura-authenticated') ?? false;
    _isDarkMode = _prefs.getBool('aura-dark-mode') ?? true;
  }

  Future<void> setAuthenticated(bool value) async {
    _isAuthenticated = value;
    await _prefs.setBool('aura-authenticated', value);
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    await _prefs.setBool('aura-dark-mode', _isDarkMode);
    notifyListeners();
  }

  void logout() {
    setAuthenticated(false);
  }
}
