/// API Endpoints - Change baseUrl according to your backend
class ApiEndpoints {
  ApiEndpoints._();

  // Base URL - Change this to your backend URL
  static const String baseUrl = 'https://your-api-url.com/api/v1';

  // Auth Endpoints
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String logout = '/auth/logout';
  static const String refreshToken = '/auth/refresh';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String verifyOtp = '/auth/verify-otp';

  // User Endpoints
  static const String userProfile = '/user/profile';
  static const String updateProfile = '/user/update';
  static const String changePassword = '/user/change-password';

  // Emergency/SOS Endpoints
  static const String emergencyContacts = '/emergency/contacts';
  static const String addEmergencyContact = '/emergency/contacts/add';
  static const String deleteEmergencyContact = '/emergency/contacts/delete';
  static const String sendSosAlert = '/emergency/sos/send';
  static const String sosHistory = '/emergency/sos/history';  

  // OCR Endpoints
  static const String ocrScan = '/ocr/scan';
  static const String ocrHistory = '/ocr/history';

  // Face Recognition Endpoints
  static const String addFace = '/face/add';
  static const String recognizeFace = '/face/recognize';
  static const String savedFaces = '/face/list';
  static const String deleteFace = '/face/delete';

  // Settings Endpoints
  static const String getSettings = '/settings';
  static const String updateSettings = '/settings/update';
}
