import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:volume_controller/volume_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/models/emergency_contact_model.dart';

/// SOS/Emergency Provider - Manages emergency contacts and SOS functionality
/// Uses Platform Channel for direct SMS sending (no app opening)
/// Works offline with local storage, syncs to Firebase when available
class SosProvider extends ChangeNotifier {
  /// Ensure default contacts exist in Firestore for this user
  Future<void> ensureDefaultContactsInFirestore() async {
    if (_userId == null) {
      debugPrint(
          '[Firestore] ensureDefaultContactsInFirestore: userId is null, cannot create defaults.');
      return;
    }
    final contactsRef = _firestore
        .collection('users')
        .doc(_userId)
        .collection('emergency_contacts');
    final snapshot = await contactsRef.limit(1).get();
    if (snapshot.docs.isEmpty) {
      _loadDefaultContacts();
      for (final contact in _contacts) {
        try {
          debugPrint(
              '[Firestore] Adding default contact for user $_userId: ${contact.toJson()}');
          await contactsRef.add(contact.toJson());
        } catch (e) {
          debugPrint(
              '[Firestore] Error adding default contact for user $_userId: $e');
        }
      }
      debugPrint(
          '[Firestore] Default contacts created in Firestore for user $_userId');
    } else {
      debugPrint(
          '[Firestore] Default contacts already exist for user $_userId');
    }

    /// Diagnostic: write a small doc to help determine connectivity/auth issues
    /// Returns null on success, or an error message on failure
    // REMOVED: debugPingFirestore method - not used
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Platform channel for native SMS
  static const _smsChannel = MethodChannel('com.aura/sms');

  // Flag to track if Firebase is available - default to true, set false on error
  bool _firebaseAvailable = true;

  bool autoTrigger = false; // Flag for ActionRouter to signal auto-press

  List<EmergencyContactModel> _contacts = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _errorMessage;
  Position? _currentPosition;
  List<Map<String, dynamic>> _sosHistory = [];
  int _smsSentCount = 0;

  // Getters
  List<EmergencyContactModel> get contacts => _contacts;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  Position? get currentPosition => _currentPosition;
  List<Map<String, dynamic>> get sosHistory => _sosHistory;
  int get smsSentCount => _smsSentCount;

  // Get current user ID
  String? get _userId => _auth.currentUser?.uid;

  /// Initialize provider - load contacts
  SosProvider() {
    loadContacts();
    // Listen for auth state changes and ensure default contacts are created
    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        try {
          await ensureDefaultContactsInFirestore();
          // Try to load from Firebase once user is available
          await _tryLoadFromFirebase();
        } catch (e) {
          debugPrint('Error ensuring default contacts on auth change: $e');
        }
      }
    });

    _initHardwareTriggers();
  }

  // --- Hardware Volume Trigger ---
  int _volumePressCount = 0;
  DateTime _lastVolumePressTime = DateTime.now();
  final DateTime _initTime = DateTime.now();

  void _initHardwareTriggers() {
    VolumeController.instance.addListener((volume) {
      final now = DateTime.now();
      
      // Ignore volume events during the first 3 seconds of app launch to prevent false triggers
      if (now.difference(_initTime).inSeconds < 3) return;
      // If more than 2 seconds since last press, reset counter
      if (now.difference(_lastVolumePressTime).inSeconds > 2) {
        _volumePressCount = 1;
      } else {
        _volumePressCount++;
      }
      
      _lastVolumePressTime = now;

      // If volume button changed 3 times rapidly
      if (_volumePressCount >= 3) {
        _volumePressCount = 0;
        // Check if triple press is enabled in settings before triggering
        _checkAndTriggerSOS();
      }
    });
  }

  Future<void> _checkAndTriggerSOS() async {
    // Only trigger if we aren't already sending one
    if (_isSending) return;
    
    // Check if the user has this feature enabled
    final prefs = await SharedPreferences.getInstance();
    final isTriplePressEnabled = prefs.getBool('sos_triple_press_enabled') ?? false;
    
    if (!isTriplePressEnabled) {
        debugPrint("[SosProvider] Hardware Volume triple press detected, but feature is disabled in settings.");
        return;
    }

    debugPrint("[SosProvider] Hardware Volume triple press detected! Sending SOS...");
    await sendSosAlert();
  }

  /// Load contacts - tries Firebase first, falls back to local storage
  Future<void> loadContacts() async {
    _isLoading = true;
    notifyListeners();

    // Try loading from local storage first (faster)
    await _loadContactsFromLocal();

    // Then try Firebase in background
    if (_userId != null) {
      _tryLoadFromFirebase();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load contacts from SharedPreferences
  Future<void> _loadContactsFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson = prefs.getString('emergency_contacts');

      if (contactsJson != null) {
        final List<dynamic> decoded = jsonDecode(contactsJson);
        _contacts =
            decoded.map((e) => EmergencyContactModel.fromJson(e)).toList();
      } else {
        _loadDefaultContacts();
        await _saveContactsToLocal();
      }
    } catch (e) {
      debugPrint('Error loading local contacts: $e');
      _loadDefaultContacts();
    }
  }

  /// Save contacts to SharedPreferences
  Future<void> _saveContactsToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson =
          jsonEncode(_contacts.map((c) => c.toJson()).toList());
      await prefs.setString('emergency_contacts', contactsJson);
    } catch (e) {
      debugPrint('Error saving local contacts: $e');
    }
  }

  /// Try to load from Firebase (non-blocking)
  Future<void> _tryLoadFromFirebase() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('emergency_contacts')
          .orderBy('createdAt', descending: false)
          .get()
          .timeout(const Duration(seconds: 10));

      _firebaseAvailable = true;

      if (snapshot.docs.isNotEmpty) {
        _contacts = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return EmergencyContactModel.fromJson(data);
        }).toList();
        await _saveContactsToLocal();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Firebase not available: $e');
      _firebaseAvailable = false;
    }
  }

  /// Load default emergency contacts
  void _loadDefaultContacts() {
    _contacts = [
      EmergencyContactModel(
        id: '1',
        name: 'Mom',
        phone: '+923001234567',
        role: 'Family',
        icon: Icons.favorite_rounded,
        color: const Color(0xFFE74C3C),
      ),
      EmergencyContactModel(
        id: '2',
        name: 'Dad',
        phone: '+923009876543',
        role: 'Family',
        icon: Icons.person_rounded,
        color: const Color(0xFF00B894),
      ),
      EmergencyContactModel(
        id: '3',
        name: 'Emergency',
        phone: '1122',
        role: 'Emergency',
        icon: Icons.local_hospital_rounded,
        color: const Color(0xFF4A90D9),
      ),
    ];
  }

  /// Check if SMS permission is granted
  Future<bool> hasSmsPermission() async {
    try {
      return await Permission.sms.isGranted;
    } catch (e) {
      debugPrint('Error checking SMS permission: $e');
      return false;
    }
  }

  /// Request SMS permission
  Future<void> requestSmsPermission() async {
    try {
      await Permission.sms.request();
    } catch (e) {
      debugPrint('Error requesting SMS permission: $e');
    }
  }

  /// Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _errorMessage = 'Location permission denied';
          notifyListeners();
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _errorMessage = 'Location permission permanently denied';
        notifyListeners();
        return null;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return _currentPosition;
    } catch (e) {
      _errorMessage = 'Failed to get location: $e';
      notifyListeners();
      return null;
    }
  }

  /// Send SMS directly using platform channel (no app opens)
  Future<bool> _sendSmsDirectly(String phoneNumber, String message) async {
    try {
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

      final result = await _smsChannel.invokeMethod('sendSms', {
        'phone': cleanNumber,
        'message': message,
      });

      return result == true;
    } catch (e) {
      debugPrint('Failed to send SMS to $phoneNumber: $e');
      return false;
    }
  }

  /// Send SOS Alert - Sends SMS directly to all contacts
  Future<bool> sendSosAlert({String? customMessage}) async {
    _isSending = true;
    _errorMessage = null;
    _smsSentCount = 0;
    notifyListeners();

    try {
      // Vibrate for feedback
      HapticFeedback.heavyImpact();

      // Check SMS permission
      final hasPermission = await hasSmsPermission();
      if (!hasPermission) {
        await requestSmsPermission();
        final permissionGranted = await hasSmsPermission();
        if (!permissionGranted) {
          _errorMessage = 'SMS permission denied';
          _isSending = false;
          notifyListeners();
          return false;
        }
      }

      // Check if auto-send location is enabled
      final prefs = await SharedPreferences.getInstance();
      final isAutoSendEnabled = prefs.getBool('sos_auto_send_enabled') ?? true;

      Position? position;
      if (isAutoSendEnabled) {
        // Get current location
        position = await getCurrentLocation();
      }

      // Create SOS message
      String message = '🆘 EMERGENCY SOS!\n';
      message += customMessage ?? 'I need immediate help!\n';

      if (position != null) {
        message +=
            '📍 Location: https://maps.google.com/?q=${position.latitude},${position.longitude}';
      }

      // Send SMS to all contacts in parallel (simultaneously)
      final smsTasks = <Future<bool>>[];
      for (var contact in _contacts) {
        if (contact.phone.isNotEmpty) {
          smsTasks.add(_sendSmsDirectly(contact.phone, message));
        }
      }

      // Wait for all SMS to be sent at the same time
      final results = await Future.wait(smsTasks);
      int successCount = results.where((sent) => sent).length;

      // Debug output
      for (int i = 0; i < results.length; i++) {
        if (results[i]) {
          debugPrint('SMS sent to ${_contacts[i].name}');
        } else {
          debugPrint('Failed to send SMS to ${_contacts[i].name}');
        }
      }

      // FALLBACK mechanism if direct SMS fails entirely
      if (successCount == 0 && _contacts.isNotEmpty) {
        debugPrint('Direct SMS failed, resorting to URL Launcher fallback');
        final firstContact = _contacts.first.phone.replaceAll(RegExp(r'[^\d+]'), '');
        final encodedMessage = Uri.encodeComponent(message);
        final smsUri = Uri.parse('sms:$firstContact?body=$encodedMessage');
        
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri);
          successCount = 1; // It opened app, so we count as "handled"
        } else {
          _errorMessage = 'Could not launch SMS app';
        }
      }

      _smsSentCount = successCount;

      // Save to Firebase (wait for it to complete)
      await _saveSosAlertToFirebase(
        latitude: position?.latitude,
        longitude: position?.longitude,
        message: message,
        recipients: _contacts.map((c) => c.phone).toList(),
        smsSentCount: successCount,
      );

      // Vibrate success
      if (successCount > 0) {
        HapticFeedback.mediumImpact();
      }

      _isSending = false;
      notifyListeners();
      return successCount > 0;
    } catch (e) {
      _errorMessage = 'Failed to send SOS: $e';
      _isSending = false;
      notifyListeners();
      return false;
    }
  }

  /// Save SOS alert to Firebase for history
  Future<void> _saveSosAlertToFirebase({
    double? latitude,
    double? longitude,
    String? message,
    List<String>? recipients,
    int? smsSentCount,
  }) async {
    if (_userId == null) {
      debugPrint('Cannot save SOS alert: User not logged in');
      return;
    }

    try {
      final path = 'users/$_userId/sos_history';
      final data = {
        'latitude': latitude,
        'longitude': longitude,
        'message': message,
        'recipients': recipients,
        'smsSentCount': smsSentCount,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      };

      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          debugPrint(
              '[Firestore] (attempt $attempt) Saving SOS alert to $path: $data');
          await _firestore
              .collection('users')
              .doc(_userId)
              .collection('sos_history')
              .add(data)
              .timeout(Duration(seconds: 15 * attempt));
          _firebaseAvailable = true;
          debugPrint('[Firestore] SOS alert saved to $path');
          break;
        } catch (e, s) {
          debugPrint(
              '[Firestore] Attempt $attempt failed saving SOS alert: $e');
          debugPrint(s.toString());
          if (attempt == 3) {
            _firebaseAvailable = false;
          } else {
            await Future.delayed(Duration(seconds: 2 * attempt));
          }
        }
      }
    } catch (e) {
      debugPrint('Error preparing SOS alert save: $e');
      _firebaseAvailable = false;
    }
  }

  /// Add new contact and save locally (and to Firebase if available)
  Future<void> addContact(EmergencyContactModel contact) async {
    // Try to save to Firebase first to get proper ID
    String? firebaseId;
    if (_userId != null) {
      try {
        final data = contact.toJson();
        data['createdAt'] = FieldValue.serverTimestamp();
        data['updatedAt'] = FieldValue.serverTimestamp();
        final path = 'users/$_userId/emergency_contacts';
        debugPrint('[Firestore] Trying to save contact to $path: $data');

        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            debugPrint(
                '[Firestore] (attempt $attempt) Adding contact to $path');
            final docRef = await _firestore
                .collection('users')
                .doc(_userId)
                .collection('emergency_contacts')
                .add(data)
                .timeout(Duration(seconds: 15 * attempt));
            firebaseId = docRef.id;
            _firebaseAvailable = true;
            debugPrint(
                '[Firestore] Contact saved to $path with id: $firebaseId');
            break;
          } catch (e, s) {
            debugPrint(
                '[Firestore] Attempt $attempt failed adding contact: $e');
            debugPrint(s.toString());
            if (attempt == 3) {
              _firebaseAvailable = false;
            } else {
              await Future.delayed(Duration(seconds: 2 * attempt));
            }
          }
        }
      } catch (e, s) {
        debugPrint('[Firestore] Fatal error preparing contact save: $e');
        debugPrint(s.toString());
        _firebaseAvailable = false;
      }
    } else {
      debugPrint(
          '[Firestore] addContact: userId is null, cannot save contact.');
    }

    // Add contact with Firebase ID if available, otherwise use local ID
    final contactToAdd = contact.copyWith(
      id: firebaseId ??
          contact.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
    );

    _contacts.add(contactToAdd);
    await _saveContactsToLocal();
    notifyListeners();
  }

  /// Remove contact locally (and from Firebase if available)
  Future<void> removeContact(String contactId) async {
    _contacts.removeWhere((c) => c.id == contactId);
    await _saveContactsToLocal();
    notifyListeners();

    // Try to delete from Firebase
    if (_userId != null) {
      try {
        final path = 'users/$_userId/emergency_contacts/$contactId';
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            debugPrint(
                '[Firestore] (attempt $attempt) Deleting contact at $path');
            await _firestore
                .collection('users')
                .doc(_userId)
                .collection('emergency_contacts')
                .doc(contactId)
                .delete()
                .timeout(Duration(seconds: 15 * attempt));
            _firebaseAvailable = true;
            debugPrint('[Firestore] Contact deleted from $path');
            break;
          } catch (e, s) {
            debugPrint(
                '[Firestore] Attempt $attempt failed deleting contact: $e');
            debugPrint(s.toString());
            if (attempt == 3) {
              _firebaseAvailable = false;
            } else {
              await Future.delayed(Duration(seconds: 2 * attempt));
            }
          }
        }
      } catch (e, s) {
        debugPrint('[Firestore] Fatal error deleting contact: $e');
        debugPrint(s.toString());
      }
    }
  }

  /// Update contact locally (and in Firebase if available)
  Future<void> updateContact(
      String contactId, EmergencyContactModel updatedContact) async {
    final index = _contacts.indexWhere((c) => c.id == contactId);
    if (index != -1) {
      _contacts[index] = updatedContact.copyWith(id: contactId);
      await _saveContactsToLocal();
      notifyListeners();
    }

    // Try to update Firebase
    if (_userId != null) {
      try {
        final data = updatedContact.toJson();
        data['updatedAt'] = FieldValue.serverTimestamp();
        final path = 'users/$_userId/emergency_contacts/$contactId';

        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            debugPrint(
                '[Firestore] (attempt $attempt) Updating contact at $path: $data');
            await _firestore
                .collection('users')
                .doc(_userId)
                .collection('emergency_contacts')
                .doc(contactId)
                .set(data, SetOptions(merge: true))
                .timeout(Duration(seconds: 15 * attempt));
            _firebaseAvailable = true;
            debugPrint('[Firestore] Contact updated at $path');
            break;
          } catch (e, s) {
            debugPrint(
                '[Firestore] Attempt $attempt failed updating contact: $e');
            debugPrint(s.toString());
            if (attempt == 3) {
              _firebaseAvailable = false;
            } else {
              await Future.delayed(Duration(seconds: 2 * attempt));
            }
          }
        }
      } catch (e, s) {
        debugPrint('[Firestore] Fatal error updating contact: $e');
        debugPrint(s.toString());
      }
    }
  }

  /// Load SOS history from Firebase (if available)
  Future<void> loadSosHistory() async {
    if (_userId == null || !_firebaseAvailable) {
      _sosHistory = [];
      notifyListeners();
      return;
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('sos_history')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get()
          .timeout(const Duration(seconds: 15));

      _sosHistory = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading SOS history: $e');
      _sosHistory = [];
      notifyListeners();
    }
  }

  /// Make phone call to a contact
  Future<void> makeCall(String phoneNumber) async {
    try {
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      final telUri = Uri.parse('tel:$cleanNumber');

      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri);
      }
    } catch (e) {
      debugPrint('Failed to make call: $e');
    }
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Refresh contacts from Firebase
  Future<void> refreshContacts() async {
    await loadContacts();
  }
}
