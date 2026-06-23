/// App-wide constants
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Aura';
  static const String appVersion = '1.0.0';

  // SharedPreferences Keys
  static const String keyAuthenticated = 'aura-authenticated';
  static const String keyDarkMode = 'aura-dark-mode';
  static const String keyOnboardingComplete = 'aura-onboarding';
  static const String keyAccessToken = 'aura-access-token';
  static const String keyRefreshToken = 'aura-refresh-token';
  static const String keyUserId = 'aura-user-id';
  static const String keyUserName = 'aura-user-name';
  static const String keyUserEmail = 'aura-user-email';

  // API Timeouts
  static const int connectionTimeout = 30000; // 30 seconds
  static const int receiveTimeout = 30000; // 30 seconds

  // Pagination
  static const int defaultPageSize = 20;
}
