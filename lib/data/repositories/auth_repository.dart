import '../models/api_response_model.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../../core/constants/api_endpoints.dart';

/// Authentication Repository
class AuthRepository {
  final ApiService _apiService = ApiService();
  late StorageService _storageService;

  AuthRepository();

  /// Initialize storage service
  Future<void> init() async {
    _storageService = await StorageService.getInstance();
  }

  /// Login with email and password
  Future<ApiResponse<UserModel>> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiEndpoints.login,
      body: {
        'email': email,
        'password': password,
      },
    );

    if (response.success && response.data != null) {
      // Save tokens
      final token = response.data!['token'] ?? response.data!['access_token'];
      if (token != null) {
        await _storageService.saveAccessToken(token);
        _apiService.setAccessToken(token);
      }

      // Save refresh token if available
      final refreshToken = response.data!['refresh_token'];
      if (refreshToken != null) {
        await _storageService.saveRefreshToken(refreshToken);
      }

      // Parse user data
      final userData = response.data!['user'] ?? response.data;
      final user = UserModel.fromJson(userData);

      // Save user info
      await _storageService.saveUserId(user.id);
      await _storageService.saveUserName(user.name);
      await _storageService.saveUserEmail(user.email);
      await _storageService.setAuthenticated(true);

      return ApiResponse.success(data: user);
    }

    return ApiResponse.error(
      message: response.message ?? 'Login failed',
      statusCode: response.statusCode,
    );
  }

  /// Register new user
  Future<ApiResponse<UserModel>> register({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiEndpoints.register,
      body: {
        'name': name,
        'email': email,
        'password': password,
        if (phone != null) 'phone': phone,
      },
    );

    if (response.success && response.data != null) {
      // Save tokens if provided
      final token = response.data!['token'] ?? response.data!['access_token'];
      if (token != null) {
        await _storageService.saveAccessToken(token);
        _apiService.setAccessToken(token);
      }

      // Parse user data
      final userData = response.data!['user'] ?? response.data;
      final user = UserModel.fromJson(userData);

      // Save user info
      await _storageService.saveUserId(user.id);
      await _storageService.saveUserName(user.name);
      await _storageService.saveUserEmail(user.email);
      await _storageService.setAuthenticated(true);

      return ApiResponse.success(data: user);
    }

    return ApiResponse.error(
      message: response.message ?? 'Registration failed',
      statusCode: response.statusCode,
    );
  }

  /// Logout
  Future<void> logout() async {
    try {
      await _apiService.post(ApiEndpoints.logout);
    } catch (_) {}

    // Clear local storage
    await _storageService.clearTokens();
    await _storageService.setAuthenticated(false);
    _apiService.setAccessToken(null);
  }

  /// Get current user profile
  Future<ApiResponse<UserModel>> getProfile() async {
    final response = await _apiService.get<Map<String, dynamic>>(
      ApiEndpoints.userProfile,
    );

    if (response.success && response.data != null) {
      final user = UserModel.fromJson(response.data!);
      return ApiResponse.success(data: user);
    }

    return ApiResponse.error(
      message: response.message ?? 'Failed to get profile',
      statusCode: response.statusCode,
    );
  }

  /// Check if user is logged in
  bool isLoggedIn() {
    return _storageService.isAuthenticated() &&
        _storageService.getAccessToken() != null;
  }

  /// Get stored user name
  String? getStoredUserName() {
    return _storageService.getUserName();
  }

  /// Get stored user email
  String? getStoredUserEmail() {
    return _storageService.getUserEmail();
  }
}
