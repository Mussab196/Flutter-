import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FallDetectionProvider extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  
  bool _isEnabled = true;
  bool _isFallDetected = false;
  bool _isCountingDown = false;
  Timer? _countdownTimer;
  int _secondsLeft = 10;
  
  // Detection state
  bool _possibleFallOccurred = false;
  DateTime? _timeOfImpact;
  
  // Constants for detection (G-force in m/s^2)
  // userAccelerometer excludes gravity. A hard drop/impact is typically > 25 m/s^2
  static const double _impactThreshold = 30.0; 
  static const double _stillnessThreshold = 2.0;
  static const Duration _stillnessDurationReq = Duration(seconds: 2);

  bool get isEnabled => _isEnabled;
  bool get isCountingDown => _isCountingDown;
  int get secondsLeft => _secondsLeft;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('fall_detection_enabled') ?? true;
    
    if (_isEnabled) {
      _startMonitoring();
    }
  }

  void toggleFallDetection(bool value) async {
    _isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fall_detection_enabled', value);
    
    if (_isEnabled) {
      _startMonitoring();
    } else {
      _stopMonitoring();
    }
    notifyListeners();
  }

  void _startMonitoring() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = userAccelerometerEventStream().listen((event) {
      if (_isCountingDown) return; // Ignore movement while in SOS countdown

      double magnitude = sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));

      // Phase 1: Massive Impact Spike
      if (!_possibleFallOccurred && magnitude > _impactThreshold) {
        _possibleFallOccurred = true;
        _timeOfImpact = DateTime.now();
        return;
      }

      // Phase 2: Stillness Check after impact
      if (_possibleFallOccurred && _timeOfImpact != null) {
        final timeSinceImpact = DateTime.now().difference(_timeOfImpact!);
        
        // If they start moving again within the window, cancel the fall
        if (magnitude > _stillnessThreshold) {
          _possibleFallOccurred = false;
          _timeOfImpact = null;
          return;
        }

        // If they stayed still for the required duration, trigger SOS
        if (timeSinceImpact > _stillnessDurationReq) {
          _triggerFallSequence();
          _possibleFallOccurred = false;
          _timeOfImpact = null;
        }
      }
    });
  }

  void _stopMonitoring() {
    _accelerometerSubscription?.cancel();
    _cancelSOS();
  }

  void _triggerFallSequence() {
    _isCountingDown = true;
    _secondsLeft = 10;
    notifyListeners();
    
    _tts.speak("Fall detected. Emergency SOS will be sent in 10 seconds.");
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _secondsLeft--;
      notifyListeners();
      
      if (_secondsLeft <= 0) {
        timer.cancel();
        await _executeSOS();
      } else if (_secondsLeft <= 5) {
        _tts.speak(_secondsLeft.toString());
      }
    });
  }

  void cancelSOS() {
    if (!_isCountingDown) return;
    
    _tts.speak("SOS Cancelled.");
    _cancelSOS();
  }
  
  void _cancelSOS() {
    _countdownTimer?.cancel();
    _isCountingDown = false;
    _isFallDetected = false;
    _possibleFallOccurred = false;
    notifyListeners();
  }

  Future<void> _executeSOS() async {
    _isCountingDown = false;
    notifyListeners();
    
    await _tts.speak("Sending Emergency S O S.");
    
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      
      final prefs = await SharedPreferences.getInstance();
      final emergencyContact = prefs.getString('emergency_contact') ?? "112"; // Default or setting
      
      final message = "EMERGENCY: Aura app detected a fall! I need help. My current location is: "
          "https://maps.google.com/?q=${position.latitude},${position.longitude}";
      
      // Use URL Launcher to trigger SMS
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: emergencyContact,
        queryParameters: <String, String>{
          'body': message,
        },
      );
      
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        await _tts.speak("Failed to open SMS app.");
      }
      
    } catch (e) {
      await _tts.speak("Failed to get location for SOS.");
      debugPrint("SOS Error: $e");
    }
  }

  @override
  void dispose() {
    _stopMonitoring();
    super.dispose();
  }
}
