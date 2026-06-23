import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Firebase Authentication Service
class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  /// Validate Gmail email (only Gmail allowed)
  bool _isGmailAddress(String email) {
    return email.toLowerCase().endsWith('@gmail.com');
  }

  /// Check if email exists in Firebase (check Firestore users collection)
  Future<bool> emailExists(String email) async {
    try {
      debugPrint('🔍 Checking if email exists: $email');

      // Method 1: Check Firestore users collection (most reliable)
      try {
        final query = await _firestore
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 5));

        if (query.docs.isNotEmpty) {
          debugPrint('Email found in Firestore: $email');
          return true;
        }
      } catch (e) {
        debugPrint('Firestore check failed: $e');
      }

      // Method 2: Try Firebase Auth method as fallback
      try {
        final methods = await _auth
            .fetchSignInMethodsForEmail(email)
            .timeout(const Duration(seconds: 5));
        if (methods.isNotEmpty) {
          debugPrint('Email found in Firebase Auth: $email');
          return true;
        }
      } catch (e) {
        debugPrint('fetchSignInMethodsForEmail failed: $e');
      }

      debugPrint('Email not found: $email');
      return false;
    } catch (e) {
      debugPrint('emailExists check failed: $e');
      return false;
    }
  }

  /// Sign up with email and password (Gmail only)
  Future<UserCredential?> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      // Validate Gmail
      if (!_isGmailAddress(email)) {
        throw Exception(
            'Only Gmail addresses are allowed. Please use your @gmail.com email.');
      }

      // Create user
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update display name
      await credential.user?.updateDisplayName(name);

      // Save user data to Firestore and create default SOS contacts
      if (credential.user != null) {
        try {
          await _firestore.collection('users').doc(credential.user!.uid).set({
            'uid': credential.user!.uid,
            'name': name,
            'email': email,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint(
                  'Firestore save timed out, but user registered successfully');
            },
          );
          // Default contacts will be created by SosProvider on auth state change
        } catch (firestoreError) {
          debugPrint('Firestore save failed: $firestoreError');
        }
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthException(e));
    } catch (e) {
      throw Exception('Sign up failed: $e');
    }
  }

  /// Sign in with email and password
  Future<UserCredential?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // SosProvider listens for auth changes and will create default contacts
      return credential;
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthException(e));
    } catch (e) {
      throw Exception('Sign in failed: $e');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Send password reset email with OTP
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      if (!_isGmailAddress(email)) {
        throw Exception('Only Gmail addresses are allowed.');
      }

      debugPrint('Attempting to send password reset email to: $email');

      // Firebase will silently fail if email doesn't exist (security feature)
      // but will throw error if account exists without password (e.g., Google Sign-in)
      await _auth.sendPasswordResetEmail(email: email);

      debugPrint('Password reset email request sent to: $email');
      debugPrint('If account exists, check your inbox and spam folder');
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} - ${e.message}');

      // Special handling for user-not-found
      if (e.code == 'user-not-found') {
        throw Exception(
            'No account found with this email address.\n\nPlease check your email or create a new account.');
      }

      throw Exception(_handleAuthException(e));
    } catch (e) {
      debugPrint('Error sending password reset email: $e');
      throw Exception('Failed to send password reset email: $e');
    }
  }

  /// Confirm password reset with code
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    try {
      await _auth.confirmPasswordReset(code: code, newPassword: newPassword);
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthException(e));
    } catch (e) {
      throw Exception('Failed to reset password: $e');
    }
  }

  /// Handle Firebase Auth exceptions
  String _handleAuthException(dynamic e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'weak-password':
          return 'Password is too weak. Use at least 6 characters.';
        case 'email-already-in-use':
          return 'An account already exists with this email.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'user-not-found':
          return 'No account found with this email.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'operation-not-allowed':
          return 'This operation is not allowed.';
        case 'network-request-failed':
          return 'Network error. Please check your connection.';
        default:
          return e.message ?? 'An error occurred. Please try again.';
      }
    }
    return e.toString();
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      debugPrint('🔄 Starting Google Sign-In...');

      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        debugPrint('⚠️ User cancelled Google Sign-In');
        return null;
      }

      debugPrint('✅ Google account selected: ${googleUser.email}');

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      debugPrint('✅ Got Google auth tokens');

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      debugPrint('Created Firebase credential');

      // Sign in to Firebase with the Google credential
      final userCredential = await _auth.signInWithCredential(credential);

      debugPrint('Signed in to Firebase: ${userCredential.user?.email}');

      // Save user data to Firestore if new user
      if (userCredential.additionalUserInfo?.isNewUser ?? false) {
        final user = userCredential.user;
        if (user != null) {
          debugPrint('Saving new user to Firestore...');
          await _firestore.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'name': user.displayName ?? '',
            'email': user.email ?? '',
            'photoUrl': user.photoURL,
            'provider': 'google',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          debugPrint('✅ User saved to Firestore');
        }
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} - ${e.message}');
      throw Exception(_handleAuthException(e));
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      debugPrint('Error type: ${e.runtimeType}');
      throw Exception('Google Sign-In failed: $e');
    }
  }

  /// Sign out from Google
  Future<void> signOutGoogle() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
