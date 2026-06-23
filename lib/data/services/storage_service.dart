import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

/// Local Storage Service using SharedPreferences
class StorageService {
  static StorageService? _instance;
  static SharedPreferences? _prefs;

  StorageService._();

  /// Initialize storage service
  static Future<StorageService> getInstance() async {
    _instance ??= StorageService._();
    _prefs ??= await SharedPreferences.getInstance();
    return _instance!;
  }

  /// Get SharedPreferences instance
  SharedPreferences get prefs => _prefs!;

  // ============ AUTH TOKENS ============

  /// Save access token
  Future<bool> saveAccessToken(String token) async {
    return await _prefs!.setString(AppConstants.keyAccessToken, token);
  }

  /// Get access token
  String? getAccessToken() {
    return _prefs!.getString(AppConstants.keyAccessToken);
  }

  /// Save refresh token
  Future<bool> saveRefreshToken(String token) async {
    return await _prefs!.setString(AppConstants.keyRefreshToken, token);
  }

  /// Get refresh token
  String? getRefreshToken() {
    return _prefs!.getString(AppConstants.keyRefreshToken);
  }

  /// Clear auth tokens
  Future<void> clearTokens() async {
    await _prefs!.remove(AppConstants.keyAccessToken);
    await _prefs!.remove(AppConstants.keyRefreshToken);
  }

  // ============ USER DATA ============

  /// Save user ID
  Future<bool> saveUserId(String userId) async {
    return await _prefs!.setString(AppConstants.keyUserId, userId);
  }

  /// Get user ID
  String? getUserId() {
    return _prefs!.getString(AppConstants.keyUserId);
  }

  /// Save user name
  Future<bool> saveUserName(String name) async {
    return await _prefs!.setString(AppConstants.keyUserName, name);
  }

  /// Get user name
  String? getUserName() {
    return _prefs!.getString(AppConstants.keyUserName);
  }

  /// Save user email
  Future<bool> saveUserEmail(String email) async {
    return await _prefs!.setString(AppConstants.keyUserEmail, email);
  }

  /// Get user email
  String? getUserEmail() {
    return _prefs!.getString(AppConstants.keyUserEmail);
  }

  // ============ APP SETTINGS ============

  /// Save authenticated state
  Future<bool> setAuthenticated(bool value) async {
    return await _prefs!.setBool(AppConstants.keyAuthenticated, value);
  }

  /// Get authenticated state
  bool isAuthenticated() {
    return _prefs!.getBool(AppConstants.keyAuthenticated) ?? false;
  }

  /// Save dark mode preference
  Future<bool> setDarkMode(bool value) async {
    return await _prefs!.setBool(AppConstants.keyDarkMode, value);
  }

  /// Get dark mode preference
  bool isDarkMode() {
    return _prefs!.getBool(AppConstants.keyDarkMode) ?? true;
  }

  /// Save onboarding complete state
  Future<bool> setOnboardingComplete(bool value) async {
    return await _prefs!.setBool(AppConstants.keyOnboardingComplete, value);
  }

  /// Get onboarding complete state
  bool isOnboardingComplete() {
    return _prefs!.getBool(AppConstants.keyOnboardingComplete) ?? false;
  }

  // ============ GENERIC METHODS ============

  /// Save string value
  Future<bool> saveString(String key, String value) async {
    return await _prefs!.setString(key, value);
  }

  /// Get string value
  String? getString(String key) {
    return _prefs!.getString(key);
  }

  /// Save bool value
  Future<bool> saveBool(String key, bool value) async {
    return await _prefs!.setBool(key, value);
  }

  /// Get bool value
  bool? getBool(String key) {
    return _prefs!.getBool(key);
  }

  /// Clear all data
  Future<bool> clearAll() async {
    return await _prefs!.clear();
  }

  /// Remove specific key
  Future<bool> remove(String key) async {
    return await _prefs!.remove(key);
  }
}
