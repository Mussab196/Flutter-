import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/user_model.dart';
import '../data/repositories/auth_repository.dart';
import '../data/services/storage_service.dart';
import '../data/services/api_service.dart';
import '../data/services/firebase_auth_service.dart';

/// Authentication Provider - Manages user authentication state
class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository = AuthRepository();
  final FirebaseAuthService _firebaseAuth = FirebaseAuthService();

  UserModel? _user;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _errorMessage;

  // Getters
  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;
  String get userName =>
      _user?.name ?? _firebaseAuth.currentUser?.displayName ?? 'User';
  User? get firebaseUser => _firebaseAuth.currentUser;

  /// Initialize auth provider
  Future<void> init() async {
    await _authRepository.init();
    final storage = await StorageService.getInstance();

    _isAuthenticated = storage.isAuthenticated();

    if (_isAuthenticated) {
      // Load stored user data
      final token = storage.getAccessToken();
      if (token != null) {
        ApiService().setAccessToken(token);
      }

      _user = UserModel(
        id: storage.getUserId() ?? '',
        name: storage.getUserName() ?? 'User',
        email: storage.getUserEmail() ?? '',
      );
    }

    notifyListeners();
  }

  /// Login with email and password
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _authRepository.login(
        email: email,
        password: password,
      );

      if (response.success && response.data != null) {
        _user = response.data;
        _isAuthenticated = true;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _errorMessage = response.message ?? 'Login failed';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Register new user
  Future<bool> register({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _authRepository.register(
        name: name,
        email: email,
        password: password,
        phone: phone,
      );

      if (response.success && response.data != null) {
        _user = response.data;
        _isAuthenticated = true;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _errorMessage = response.message ?? 'Registration failed';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    await _authRepository.logout();

    _user = null;
    _isAuthenticated = false;
    _errorMessage = null;
    _isLoading = false;

    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // FIREBASE AUTHENTICATION METHODS

  /// Login with Firebase Email & Password
  Future<bool> loginWithFirebase({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final credential = await _firebaseAuth.signIn(
        email: email,
        password: password,
      );

      if (credential != null) {
        final firebaseUser = _firebaseAuth.currentUser;
        final storage = await StorageService.getInstance();

        _user = UserModel(
          id: firebaseUser?.uid ?? '',
          name: firebaseUser?.displayName ?? email.split('@').first,
          email: firebaseUser?.email ?? email,
          profileImage: firebaseUser?.photoURL,
        );

        await storage.setAuthenticated(true);
        await storage.saveUserName(_user!.name);
        await storage.saveUserEmail(_user!.email);
        await storage.saveUserId(_user!.id);

        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Login failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Register with Firebase Email & Password
  Future<bool> registerWithFirebase({
    required String name,
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final credential = await _firebaseAuth.signUp(
        name: name,
        email: email,
        password: password,
      );

      if (credential != null) {
        final firebaseUser = _firebaseAuth.currentUser;
        final storage = await StorageService.getInstance();

        _user = UserModel(
          id: firebaseUser?.uid ?? '',
          name: name,
          email: email,
          profileImage: firebaseUser?.photoURL,
        );

        await storage.setAuthenticated(true);
        await storage.saveUserName(_user!.name);
        await storage.saveUserEmail(_user!.email);
        await storage.saveUserId(_user!.id);

        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Registration failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logout from Firebase
  Future<void> logoutFirebase() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _firebaseAuth.signOut();
      final storage = await StorageService.getInstance();
      await storage.clearAll();

      _user = null;
      _isAuthenticated = false;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Logout error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if email exists in Firebase
  Future<bool> checkEmailExists(String email) async {
    try {
      return await _firebaseAuth.emailExists(email);
    } catch (e) {
      return false;
    }
  }

  /// Send password reset email
  Future<bool> sendPasswordReset(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _firebaseAuth.sendPasswordResetEmail(email);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Confirm password reset with OTP code
  Future<bool> resetPasswordWithCode({
    required String code,
    required String newPassword,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _firebaseAuth.confirmPasswordReset(
        code: code,
        newPassword: newPassword,
      );
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign in with Google
  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('AuthProvider: Starting Google Sign-In...');

      final credential = await _firebaseAuth.signInWithGoogle();

      if (credential != null) {
        debugPrint('AuthProvider: Got Firebase credential');

        final firebaseUser = _firebaseAuth.currentUser;
        final storage = await StorageService.getInstance();

        _user = UserModel(
          id: firebaseUser?.uid ?? '',
          name: firebaseUser?.displayName ?? 'User',
          email: firebaseUser?.email ?? '',
          profileImage: firebaseUser?.photoURL,
        );

        await storage.setAuthenticated(true);
        await storage.saveUserName(_user!.name);
        await storage.saveUserEmail(_user!.email);
        await storage.saveUserId(_user!.id);

        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();

        debugPrint('AuthProvider: Google Sign-In successful!');
        return true;
      } else {
        _errorMessage = 'Google Sign-In cancelled';
        _isLoading = false;
        notifyListeners();
        debugPrint('AuthProvider: Google Sign-In cancelled by user');
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      debugPrint('AuthProvider: Google Sign-In error: $_errorMessage');
      return false;
    }
  }

  /// Check if user is already logged in (on app start)
  Future<void> checkAuthStatus() async {
    final firebaseUser = _firebaseAuth.currentUser;

    if (firebaseUser != null) {
      final storage = await StorageService.getInstance();

      _user = UserModel(
        id: firebaseUser.uid,
        name: firebaseUser.displayName ?? 'User',
        email: firebaseUser.email ?? '',
        profileImage: firebaseUser.photoURL,
      );

      _isAuthenticated = true;
      await storage.setAuthenticated(true);
    } else {
      _isAuthenticated = false;
    }

    notifyListeners();
  }

  // DEMO MODE METHODS (Backup when Firebase not configured)

  /// Simulate login for demo (when no backend)
  Future<bool> loginDemo({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 1500));

    // Demo validation
    if (email.isNotEmpty && password.length >= 6) {
      final storage = await StorageService.getInstance();

      _user = UserModel(
        id: 'demo_user_001',
        name: email.split('@').first,
        email: email,
      );

      await storage.setAuthenticated(true);
      await storage.saveUserName(_user!.name);
      await storage.saveUserEmail(_user!.email);
      await storage.saveUserId(_user!.id);

      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _errorMessage = 'Invalid email or password';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Simulate registration for demo
  Future<bool> registerDemo({
    required String name,
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 1500));

    if (name.isNotEmpty && email.isNotEmpty && password.length >= 6) {
      final storage = await StorageService.getInstance();

      _user = UserModel(
        id: 'demo_user_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        email: email,
      );

      await storage.setAuthenticated(true);
      await storage.saveUserName(_user!.name);
      await storage.saveUserEmail(_user!.email);
      await storage.saveUserId(_user!.id);

      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _errorMessage = 'Please fill all fields correctly';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
