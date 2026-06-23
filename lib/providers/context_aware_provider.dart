import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserContext {
  stationary,
  walking,
  fastMoving // Vehicle
}

class ContextAwareProvider extends ChangeNotifier {
  StreamSubscription<Position>? _positionSubscription;
  
  bool _isEnabled = true;
  UserContext _currentContext = UserContext.stationary;
  double _currentSpeedKmh = 0.0;
  
  // Speed thresholds in km/h
  static const double _walkingThreshold = 1.5; // ~0.4 m/s
  static const double _fastMovingThreshold = 15.0; // ~4.1 m/s

  bool get isEnabled => _isEnabled;
  UserContext get currentContext => _currentContext;
  double get currentSpeedKmh => _currentSpeedKmh;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('context_aware_enabled') ?? true;
    
    if (_isEnabled) {
      await _startMonitoring();
    }
  }

  void toggleContextAwareness(bool value) async {
    _isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('context_aware_enabled', value);
    
    if (_isEnabled) {
      await _startMonitoring();
    } else {
      _stopMonitoring();
    }
    notifyListeners();
  }

  Future<void> _startMonitoring() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    _positionSubscription?.cancel();
    
    // High accuracy, distance filter of 5 meters to prevent tiny jitter
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, 
    );

    _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      
      // position.speed is in m/s
      _currentSpeedKmh = position.speed * 3.6;
      
      UserContext newContext;
      if (_currentSpeedKmh >= _fastMovingThreshold) {
        newContext = UserContext.fastMoving;
      } else if (_currentSpeedKmh >= _walkingThreshold) {
        newContext = UserContext.walking;
      } else {
        newContext = UserContext.stationary;
      }

      if (_currentContext != newContext) {
        _currentContext = newContext;
        debugPrint("[ContextAware] Switched to ${_currentContext.name} mode at ${_currentSpeedKmh.toStringAsFixed(1)} km/h");
        notifyListeners();
      }
    });
  }

  void _stopMonitoring() {
    _positionSubscription?.cancel();
  }

  @override
  void dispose() {
    _stopMonitoring();
    super.dispose();
  }
}
