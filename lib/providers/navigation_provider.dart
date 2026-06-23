import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'obstacle_provider.dart';
import '../utils/tts_config.dart';

/// A waypoint in the navigation route
class NavWaypoint {
  final double lat;
  final double lng;
  final String instruction;
  final String direction; // "left", "right", "straight", "uturn"

  const NavWaypoint({
    required this.lat,
    required this.lng,
    required this.instruction,
    this.direction = 'straight',
  });
}

/// Navigation mode
enum NavMode {
  freeWalk,      // No destination, just compass + obstacle warnings
  guidedRoute,   // Following waypoints to a destination
}

/// NavigationProvider — Smart Navigation with YOLO Obstacle Fusion
///
/// Combines:
/// - GPS positioning with high-accuracy tracking
/// - Compass heading from magnetometer
/// - Turn-by-turn voice guidance
/// - YOLO obstacle detection danger feed
/// - Saved locations (home, work, etc.)
class NavigationProvider extends ChangeNotifier {
  // ═══ GPS ═══
  Position? _currentPosition;
  bool _locationAvailable = false;
  String _locationStatus = 'Initializing GPS...';
  StreamSubscription<Position>? _positionStream;

  // ═══ Compass ═══
  double _heading = 0.0;
  double _smoothedHeading = 0.0; // EMA-filtered heading for stability
  String _currentDirection = 'N';
  StreamSubscription? _compassStream;
  // Low-pass filter alpha: lower = smoother but slower response.
  // 0.15 is optimal for walking — filters magnetometer noise (±15°)
  // while still tracking real turns within ~0.5 seconds.
  static const double _compassAlpha = 0.15;

  // ═══ Movement ═══
  double _speed = 0.0; // m/s
  String _movementStatus = 'Stationary';
  double _gpsBearing = 0.0; // Bearing from GPS (reliable when walking)
  double _totalDistanceWalked = 0.0; // Accumulated distance in free-walk
  Position? _previousPosition; // For distance accumulation

  // ═══ Navigation ═══
  NavMode _navMode = NavMode.freeWalk;
  List<NavWaypoint> _waypoints = [];
  int _currentWaypointIndex = 0;
  String _nextInstruction = '';
  double _distanceToNextWaypoint = 0;
  double _bearingToNextWaypoint = 0;
  String _turnDirection = '';
  double _totalDistanceRemaining = 0;
  String? _destinationName;
  bool _closeApproachAnnounced = false; // Track 15m approach warning

  // ═══ Obstacle Fusion ═══
  DangerLevel _currentDangerLevel = DangerLevel.safe;
  String _obstacleWarning = '';
  bool _obstacleAlertActive = false;

  // ═══ TTS ═══
  final FlutterTts _tts = FlutterTts();
  bool _voiceEnabled = true;
  bool _isSpeaking = false;
  DateTime _lastAnnouncement = DateTime(2000);

  // ═══ Saved Locations ═══
  Map<String, Map<String, double>> _savedLocations = {};

  // ═══ Getters ═══
  Position? get currentPosition => _currentPosition;
  bool get locationAvailable => _locationAvailable;
  String get locationStatus => _locationStatus;
  double get heading => _heading;
  String get currentDirection => _currentDirection;
  double get speed => _speed;
  String get movementStatus => _movementStatus;
  NavMode get navMode => _navMode;
  List<NavWaypoint> get waypoints => _waypoints;
  int get currentWaypointIndex => _currentWaypointIndex;
  String get nextInstruction => _nextInstruction;
  double get distanceToNextWaypoint => _distanceToNextWaypoint;
  double get bearingToNextWaypoint => _bearingToNextWaypoint;
  String get turnDirection => _turnDirection;
  double get totalDistanceRemaining => _totalDistanceRemaining;
  String? get destinationName => _destinationName;
  DangerLevel get currentDangerLevel => _currentDangerLevel;
  String get obstacleWarning => _obstacleWarning;
  bool get obstacleAlertActive => _obstacleAlertActive;
  bool get voiceEnabled => _voiceEnabled;
  bool get isSpeaking => _isSpeaking;
  bool get isNavigating => _navMode == NavMode.guidedRoute;
  Map<String, Map<String, double>> get savedLocations => _savedLocations;

  NavigationProvider() {
    _initTts();
    _loadSavedLocations();
  }

  // ═══════════════════════════════════════════════
  //  INITIALIZATION
  // ═══════════════════════════════════════════════

  Future<void> _initTts() async {
    await TtsConfig.apply(_tts);
    _tts.setStartHandler(() {
      _isSpeaking = true;
      notifyListeners();
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      notifyListeners();
    });
  }

  Future<void> startNavigation() async {
    await _initLocation();
    _initCompass();
  }

  bool _isNavigationActive = false;

  void stopSensors() {
    _isNavigationActive = false;
    _positionStream?.cancel();
    _positionStream = null;
    _compassStream?.cancel();
    _compassStream = null;
    _locationAvailable = false;
    _locationStatus = 'Navigation stopped';
    _speed = 0.0;
    _movementStatus = 'Stationary';
    _tts.stop();
    notifyListeners();
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _locationStatus = 'Location services disabled';
        _speak('Please enable GPS for navigation.');
        notifyListeners();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _locationStatus = 'Location permission denied';
          _speak('I need location access to help you navigate.');
          notifyListeners();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _locationStatus = 'Permission permanently denied';
        _speak('Location permission is permanently denied. Please enable it in settings.');
        notifyListeners();
        return;
      }

      _isNavigationActive = true;

      // Get initial position (can take time)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Prevent race condition: if user exited screen while awaiting GPS
      if (!_isNavigationActive) return;

      _currentPosition = position;
      _locationAvailable = true;
      _locationStatus = 'Location acquired';
      _speed = position.speed;
      _updateMovementStatus();
      notifyListeners();

      _speak('Navigation ready. I have your location.');

      // Start continuous tracking
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1, // Every 1 meter for better accuracy
        ),
      ).listen(_onPositionUpdate);
    } catch (e) {
      _locationStatus = 'GPS Error: $e';
      debugPrint('[Navigation] Location error: $e');
      notifyListeners();
    }
  }

  DateTime _lastCompassUpdate = DateTime.now();

  void _initCompass() {
    _compassStream = magnetometerEventStream().listen((event) {
      double rawHeading = math.atan2(event.y, event.x) * (180 / math.pi);
      rawHeading = (rawHeading + 360) % 360;

      // ═══ COMPASS SMOOTHING (Exponential Moving Average) ═══
      // Raw magnetometer fluctuates ±15° from metal, phone case, etc.
      // EMA with α=0.15 smooths this while tracking real turns.
      // Use circular interpolation to avoid 359°→1° jump glitches.
      double diff = rawHeading - _smoothedHeading;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      _smoothedHeading = (_smoothedHeading + _compassAlpha * diff + 360) % 360;

      // ═══ GPS-BEARING FUSION ═══
      // When walking (speed > 0.8 m/s), GPS-derived bearing is MORE
      // accurate than magnetometer for straight-line movement.
      // Blend: 70% GPS + 30% compass when walking, 100% compass when still.
      if (_speed > 0.8 && _gpsBearing > 0) {
        double gpsDiff = _gpsBearing - _smoothedHeading;
        if (gpsDiff > 180) gpsDiff -= 360;
        if (gpsDiff < -180) gpsDiff += 360;
        _heading = (_smoothedHeading + 0.7 * gpsDiff + 360) % 360;
      } else {
        _heading = _smoothedHeading;
      }

      _currentDirection = _headingToDirection(_heading);

      // If navigating, update turn direction
      if (_navMode == NavMode.guidedRoute) {
        _updateTurnDirection();
      }

      // Throttle updates to ~30 FPS to prevent UI lag
      final now = DateTime.now();
      if (now.difference(_lastCompassUpdate).inMilliseconds > 33) {
        _lastCompassUpdate = now;
        notifyListeners();
      }
    });
  }

  // ═══════════════════════════════════════════════
  //  POSITION UPDATES
  // ═══════════════════════════════════════════════

  void _onPositionUpdate(Position position) {
    // ═══ GPS-BEARING EXTRACTION ═══
    // Use GPS heading when available (it's more reliable than
    // magnetometer when the user is actually moving).
    if (position.heading != 0.0 && position.speed > 0.5) {
      _gpsBearing = position.heading;
    }

    // ═══ DISTANCE ACCUMULATION (for free-walk tracking) ═══
    if (_previousPosition != null && position.speed > 0.3) {
      _totalDistanceWalked += _haversineDistance(
        _previousPosition!.latitude, _previousPosition!.longitude,
        position.latitude, position.longitude,
      );
    }
    _previousPosition = position;

    _currentPosition = position;
    _speed = position.speed;
    _updateMovementStatus();

    if (_navMode == NavMode.guidedRoute && _waypoints.isNotEmpty) {
      _updateRouteProgress();
    } else {
      _announceFreeWalk();
    }

    notifyListeners();
  }

  void _updateMovementStatus() {
    if (_speed < 0.5) { // 0.5 m/s ≈ 1.8 km/h (filters GPS drift when stationary)
      _speed = 0.0;
      _movementStatus = 'Stationary';
    } else if (_speed < 1.5) {
      _movementStatus = 'Walking slowly';
    } else if (_speed < 3.0) {
      _movementStatus = 'Walking';
    } else if (_speed < 6.0) {
      _movementStatus = 'Running / Cycling';
    } else {
      _movementStatus = 'In vehicle';
    }
  }

  // ═══════════════════════════════════════════════
  //  ROUTE NAVIGATION (Turn-by-Turn)
  // ═══════════════════════════════════════════════

  /// Start navigating to a destination with waypoints
  void startRoute({
    required String destinationName,
    required List<NavWaypoint> waypoints,
  }) {
    _navMode = NavMode.guidedRoute;
    _destinationName = destinationName;
    _waypoints = waypoints;
    _currentWaypointIndex = 0;

    if (_waypoints.isNotEmpty) {
      _nextInstruction = _waypoints[0].instruction;
      _updateRouteProgress();
    }

    _speak('Starting navigation to $destinationName.');
    notifyListeners();
  }

  /// Stop current navigation and return to free walk mode
  void stopRoute() {
    _navMode = NavMode.freeWalk;
    _destinationName = null;
    _waypoints = [];
    _speak('Navigation stopped.');
    notifyListeners();
  }

  /// Start navigating to a saved location
  void navigateToSaved(String name) {
    final loc = _savedLocations[name];
    if (loc == null || _currentPosition == null) {
      _speak("I don't have a saved location called $name.");
      return;
    }

    final destLat = loc['lat']!;
    final destLng = loc['lng']!;

    // Generate simple straight-line waypoints
    final waypoints = _generateSimpleRoute(destLat, destLng, name);
    startRoute(destinationName: name, waypoints: waypoints);
  }

  /// Navigate to specific coordinates
  void navigateToCoordinates(double lat, double lng, String name) {
    if (_currentPosition == null) {
      _speak('Waiting for GPS. Please step outside and try again in a moment.');
      return;
    }

    final waypoints = _generateSimpleRoute(lat, lng, name);
    startRoute(destinationName: name, waypoints: waypoints);
  }

  /// Generate a simple route with intermediate waypoints
  List<NavWaypoint> _generateSimpleRoute(double destLat, double destLng, String destName) {
    if (_currentPosition == null) return [];

    final startLat = _currentPosition!.latitude;
    final startLng = _currentPosition!.longitude;
    final totalDist = _haversineDistance(startLat, startLng, destLat, destLng);

    final List<NavWaypoint> wps = [];

    if (totalDist < 50) {
      // Very close — single waypoint
      wps.add(NavWaypoint(
        lat: destLat,
        lng: destLng,
        instruction: 'You have arrived at $destName.',
        direction: 'straight',
      ));
    } else {
      // Generate waypoints every 20 meters
      final steps = (totalDist / 20).ceil().clamp(2, 50);
      for (int i = 1; i <= steps; i++) {
        final fraction = i / steps;
        final lat = startLat + (destLat - startLat) * fraction;
        final lng = startLng + (destLng - startLng) * fraction;

        String instruction;
        if (i == steps) {
          instruction = 'You have arrived at $destName.';
        } else {
          final mRemaining = (totalDist * (1 - fraction)).round();
          instruction = 'Continue straight. $mRemaining meters remaining.';
        }

        wps.add(NavWaypoint(
          lat: lat,
          lng: lng,
          instruction: instruction,
          direction: 'straight',
        ));
      }
    }

    return wps;
  }

  /// Update route progress — check if reached waypoint
  void _updateRouteProgress() {
    if (_currentPosition == null || _waypoints.isEmpty) return;
    if (_currentWaypointIndex >= _waypoints.length) return;

    final wp = _waypoints[_currentWaypointIndex];
    final dist = _haversineDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      wp.lat,
      wp.lng,
    );

    _distanceToNextWaypoint = dist;
    _bearingToNextWaypoint = _calculateBearing(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      wp.lat,
      wp.lng,
    );

    // Calculate total remaining
    double totalRemaining = dist;
    for (int i = _currentWaypointIndex + 1; i < _waypoints.length; i++) {
      final prev = i == _currentWaypointIndex + 1
          ? wp
          : _waypoints[i - 1];
      totalRemaining += _haversineDistance(prev.lat, prev.lng, _waypoints[i].lat, _waypoints[i].lng);
    }
    _totalDistanceRemaining = totalRemaining;

    _updateTurnDirection();

    // ═══ ADAPTIVE WAYPOINT ARRIVAL RADIUS ═══
    // GPS accuracy on phones is ±5-10m. Using 8m caused "stuck" waypoints.
    // Walking: 10m radius, Vehicle: 15m (GPS drifts more at speed)
    final arrivalRadius = _speed > 6.0 ? 15.0 : 10.0;

    // ═══ CLOSE APPROACH WARNING ═══
    // Announce at 15m so blind user prepares for turn
    if (dist < 15 && !_closeApproachAnnounced) {
      _closeApproachAnnounced = true;
      final turnName = _turnDirection == 'straight' ? 'continue straight' : 'turn ${_turnDirection.replaceAll('_', ' ')}';
      _speak('In about 10 meters, $turnName.');
    }

    if (dist < arrivalRadius) {
      _currentWaypointIndex++;
      _closeApproachAnnounced = false; // Reset for next waypoint

      if (_currentWaypointIndex >= _waypoints.length) {
        // Arrived at destination!
        _navMode = NavMode.freeWalk;
        _speak('You have arrived at ${_destinationName ?? "your destination"}.');
        _destinationName = null;
        _waypoints = [];
      } else {
        // Move to next waypoint
        final next = _waypoints[_currentWaypointIndex];
        _nextInstruction = next.instruction;
        _announceNavigation(next.instruction);
      }
    } else {
      // Announce distance periodically
      _announceDistanceUpdate();
    }
  }

  /// Calculate turn direction based on bearing vs heading
  void _updateTurnDirection() {
    final diff = (_bearingToNextWaypoint - _heading + 360) % 360;

    if (diff < 20 || diff > 340) {
      _turnDirection = 'straight';
      _nextInstruction = '${_formatDistance(_distanceToNextWaypoint)} ahead. Continue straight.';
    } else if (diff >= 20 && diff < 70) {
      _turnDirection = 'slight_right';
      _nextInstruction = 'Bear slightly right. ${_formatDistance(_distanceToNextWaypoint)} to next point.';
    } else if (diff >= 70 && diff < 150) {
      _turnDirection = 'right';
      _nextInstruction = 'Turn right. ${_formatDistance(_distanceToNextWaypoint)} to next point.';
    } else if (diff >= 150 && diff < 210) {
      _turnDirection = 'uturn';
      _nextInstruction = 'Turn around. You are going the wrong way.';
    } else if (diff >= 210 && diff < 290) {
      _turnDirection = 'left';
      _nextInstruction = 'Turn left. ${_formatDistance(_distanceToNextWaypoint)} to next point.';
    } else {
      _turnDirection = 'slight_left';
      _nextInstruction = 'Bear slightly left. ${_formatDistance(_distanceToNextWaypoint)} to next point.';
    }
  }

  /// Announce turn-by-turn navigation updates
  void _announceNavigation(String message) {
    if (!_voiceEnabled || _isSpeaking) return;
    _tts.speak(message);
  }

  /// Announce distance updates periodically with proximity-adaptive cooldowns.
  /// Closer to waypoint = more frequent announcements for blind user safety.
  void _announceDistanceUpdate() {
    if (!_voiceEnabled || _isSpeaking) return;

    final now = DateTime.now();

    // ═══ PROXIMITY-BASED ANNOUNCEMENT COOLDOWNS ═══
    // > 50m:  8 seconds (user is far, don't spam)
    // 15-50m: 5 seconds (approaching, more updates)
    // < 15m:  3 seconds (critical zone, frequent guidance)
    // U-turn: 4 seconds (wrong way needs urgent correction)
    Duration cooldown;
    if (_turnDirection == 'uturn') {
      cooldown = const Duration(seconds: 4);
    } else if (_distanceToNextWaypoint < 15) {
      cooldown = const Duration(seconds: 3);
    } else if (_distanceToNextWaypoint < 50) {
      cooldown = const Duration(seconds: 5);
    } else {
      cooldown = const Duration(seconds: 8);
    }

    if (now.difference(_lastAnnouncement) < cooldown) return;
    _lastAnnouncement = now;

    // Smart distance announcements
    if (_distanceToNextWaypoint < 15) {
      _speak(_nextInstruction);
    } else if (_distanceToNextWaypoint < 50) {
      _speak('${_formatDistance(_distanceToNextWaypoint)} to your next turn.');
    } else if (_distanceToNextWaypoint < 200) {
      _speak('Continue ${_turnDirection == 'straight' ? 'straight' : 'ahead'}. ${_formatDistance(_distanceToNextWaypoint)} remaining.');
    }
  }

  /// Enhanced free walk mode with obstacle fusion and distance tracking.
  /// Provides contextual awareness for blind users walking without a destination.
  void _announceFreeWalk() {
    if (!_voiceEnabled || _isSpeaking) return;

    final now = DateTime.now();
    if (now.difference(_lastAnnouncement) < const Duration(seconds: 8)) return;
    _lastAnnouncement = now;

    final dir = _headingToFullName(_currentDirection);
    final parts = <String>[];

    // Direction
    parts.add('Facing $dir.');

    // Movement status with distance walked
    if (_speed > 0.5) {
      parts.add(_movementStatus);
      if (_totalDistanceWalked > 10) {
        parts.add('Walked about ${_totalDistanceWalked.round()} meters so far.');
      }
    } else {
      parts.add('Stationary.');
    }

    // ═══ OBSTACLE FUSION INTO FREE-WALK ═══
    // Integrate YOLO obstacle detection into walking announcements
    if (_obstacleAlertActive && _obstacleWarning.isNotEmpty) {
      parts.add('Caution: $_obstacleWarning');
    } else if (_currentDangerLevel == DangerLevel.safe) {
      parts.add('Path ahead looks clear.');
    }

    _speak(parts.join(' '));
  }

  // ═══════════════════════════════════════════════
  //  OBSTACLE FUSION
  // ═══════════════════════════════════════════════

  /// Receive obstacle updates from ObstacleProvider
  void updateObstacleStatus(DangerLevel level, String warning) {
    final previousLevel = _currentDangerLevel;
    _currentDangerLevel = level;
    _obstacleWarning = warning;
    _obstacleAlertActive = level.index >= DangerLevel.warning.index;

    // If danger escalated during navigation, announce immediately
    if (level.index > previousLevel.index &&
        level.index >= DangerLevel.warning.index) {
      _speak(warning);
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  //  SAVED LOCATIONS
  // ═══════════════════════════════════════════════

  /// Save current location
  Future<void> saveCurrentLocation(String name) async {
    if (_currentPosition == null) {
      _speak('Cannot save. Location not available.');
      return;
    }

    _savedLocations[name] = {
      'lat': _currentPosition!.latitude,
      'lng': _currentPosition!.longitude,
    };

    await _persistSavedLocations();
    _speak('Location saved as $name.');
    notifyListeners();
  }

  /// Delete saved location
  Future<void> deleteSavedLocation(String name) async {
    _savedLocations.remove(name);
    await _persistSavedLocations();
    notifyListeners();
  }

  Future<void> _loadSavedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('nav_loc_'));
      for (final key in keys) {
        final name = key.replaceFirst('nav_loc_', '');
        final lat = prefs.getDouble('${key}_lat');
        final lng = prefs.getDouble('${key}_lng');
        if (lat != null && lng != null) {
          _savedLocations[name] = {'lat': lat, 'lng': lng};
        }
      }
    } catch (e) {
      debugPrint('[Navigation] Error loading saved locations: $e');
    }
  }

  Future<void> _persistSavedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in _savedLocations.entries) {
        await prefs.setDouble('nav_loc_${entry.key}_lat', entry.value['lat']!);
        await prefs.setDouble('nav_loc_${entry.key}_lng', entry.value['lng']!);
        // Store a marker key so we can enumerate
        await prefs.setBool('nav_loc_${entry.key}', true);
      }
    } catch (e) {
      debugPrint('[Navigation] Error saving locations: $e');
    }
  }

  // ═══════════════════════════════════════════════
  //  CONTROLS
  // ═══════════════════════════════════════════════

  void toggleVoice() {
    _voiceEnabled = !_voiceEnabled;
    if (!_voiceEnabled) _tts.stop();
    notifyListeners();
  }

  void stopNavigation() {
    _navMode = NavMode.freeWalk;
    _waypoints = [];
    _currentWaypointIndex = 0;
    _destinationName = null;
    _speak('Navigation stopped.');
    notifyListeners();
  }

  /// Manually announce full status
  void announceCurrentStatus() {
    final dir = _headingToFullName(_currentDirection);
    String status = 'You are facing $dir. $_movementStatus.';

    if (_currentPosition != null) {
      status += ' Coordinates: '
          '${_currentPosition!.latitude.toStringAsFixed(4)}, '
          '${_currentPosition!.longitude.toStringAsFixed(4)}.';
    }

    if (_navMode == NavMode.guidedRoute && _destinationName != null) {
      status += ' Navigating to $_destinationName. '
          '${_formatDistance(_totalDistanceRemaining)} remaining.';
    }

    if (_obstacleAlertActive) {
      status += ' $_obstacleWarning';
    }

    _speak(status);
  }

  Future<void> _speak(String text) async {
    if (!_voiceEnabled) return;
    await _tts.speak(text);
  }

  // ═══════════════════════════════════════════════
  //  MATH HELPERS
  // ═══════════════════════════════════════════════

  /// Haversine distance in meters
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  /// Calculate bearing from point A to point B
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = _toRadians(lon2 - lon1);
    final y = math.sin(dLon) * math.cos(_toRadians(lat2));
    final x = math.cos(_toRadians(lat1)) * math.sin(_toRadians(lat2)) -
        math.sin(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * math.cos(dLon);
    final bearing = math.atan2(y, x) * (180 / math.pi);
    return (bearing + 360) % 360;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  String _formatDistance(double meters) {
    if (meters < 10) return '${meters.round()} meters';
    if (meters < 100) return '${(meters / 10).round() * 10} meters';
    if (meters < 1000) return '${(meters / 10).round() * 10} meters';
    return '${(meters / 1000).toStringAsFixed(1)} kilometers';
  }

  String _headingToDirection(double heading) {
    if (heading >= 337.5 || heading < 22.5) return 'N';
    if (heading >= 22.5 && heading < 67.5) return 'NE';
    if (heading >= 67.5 && heading < 112.5) return 'E';
    if (heading >= 112.5 && heading < 157.5) return 'SE';
    if (heading >= 157.5 && heading < 202.5) return 'S';
    if (heading >= 202.5 && heading < 247.5) return 'SW';
    if (heading >= 247.5 && heading < 292.5) return 'W';
    if (heading >= 292.5 && heading < 337.5) return 'NW';
    return 'N';
  }

  String _headingToFullName(String dir) {
    return switch (dir) {
      'N'  => 'North',
      'NE' => 'Northeast',
      'E'  => 'East',
      'SE' => 'Southeast',
      'S'  => 'South',
      'SW' => 'Southwest',
      'W'  => 'West',
      'NW' => 'Northwest',
      _    => 'Unknown',
    };
  }

  /// Get turn arrow icon
  IconData getTurnIcon() {
    return switch (_turnDirection) {
      'left'         => Icons.turn_left_rounded,
      'right'        => Icons.turn_right_rounded,
      'slight_left'  => Icons.turn_slight_left_rounded,
      'slight_right' => Icons.turn_slight_right_rounded,
      'uturn'        => Icons.u_turn_left_rounded,
      _              => Icons.straight_rounded,
    };
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _compassStream?.cancel();
    _tts.stop();
    super.dispose();
  }
}
