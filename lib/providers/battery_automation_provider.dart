import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BatteryAutomationProvider extends ChangeNotifier {
  bool _isEnabled = true;
  double _originalBrightness = 0.5;

  bool get isEnabled => _isEnabled;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('battery_automation_enabled') ?? true;
    
    try {
      _originalBrightness = await ScreenBrightness().current;
    } catch (e) {
      debugPrint("Could not get original brightness: $e");
    }

    if (_isEnabled) {
      await _applyDimming();
    }
  }

  void toggleBatteryAutomation(bool value) async {
    if (_isEnabled == value) return;
    
    _isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('battery_automation_enabled', value);
    
    if (_isEnabled) {
      await _applyDimming();
    } else {
      await _restoreBrightness();
    }
    notifyListeners();
  }

  Future<void> _applyDimming() async {
    try {
      // Set to 0.0 for maximum battery saving (visually impaired users don't need bright screens)
      await ScreenBrightness().setScreenBrightness(0.0);
      debugPrint("[BatteryAutomation] Screen dimmed to 0%");
    } catch (e) {
      debugPrint("[BatteryAutomation] Failed to dim screen: $e");
    }
  }

  Future<void> _restoreBrightness() async {
    try {
      await ScreenBrightness().resetScreenBrightness();
      debugPrint("[BatteryAutomation] Screen brightness restored");
    } catch (e) {
      debugPrint("[BatteryAutomation] Failed to restore brightness: $e");
    }
  }

  // Can be called when app resumes from background if needed
  Future<void> onAppResumed() async {
    if (_isEnabled) {
      await _applyDimming();
    }
  }

  @override
  void dispose() {
    _restoreBrightness(); // Restore when provider is destroyed
    super.dispose();
  }
}
