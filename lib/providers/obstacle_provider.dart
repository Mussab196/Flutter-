import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/tts_config.dart';

/// Danger level classification for detected obstacles
enum DangerLevel {
  safe,     // No immediate danger
  caution,  // Should be aware
  warning,  // Approaching danger
  critical, // Immediate danger — stairs, deep drop, vehicle
}

/// A single classified obstacle with spatial awareness
class ClassifiedObstacle {
  final String label;
  final double confidence;
  final Rect boundingBox;
  final DangerLevel dangerLevel;
  final String position; // "left", "center", "right"
  final double relativeSize; // 0.0 to 1.0 — bigger = closer

  const ClassifiedObstacle({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.dangerLevel,
    required this.position,
    required this.relativeSize,
  });
}

/// ObstacleProvider — Classifies YOLO detections into danger levels
/// and provides accessibility-focused warnings with haptic feedback.
///
/// Maps COCO labels + custom labels to accessibility-relevant categories:
/// - Stairs, steps, escalators → CRITICAL
/// - Vehicles (car, truck, bus, motorcycle) → CRITICAL when close
/// - Doors, gates → CAUTION (navigational landmark)
/// - Furniture (chair, bench, table) → CAUTION
/// - People, animals → WARNING when very close
class ObstacleProvider extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  // State
  List<ClassifiedObstacle> _obstacles = [];
  DangerLevel _currentDangerLevel = DangerLevel.safe;
  String _warningMessage = '';
  bool _isWarning = false;
  bool _hapticEnabled = true;
  bool _isSpeaking = false;

  // ═══ CONFIDENCE THRESHOLDS PER DANGER LEVEL ═══
  // Lower threshold for critical = never miss a staircase
  // Higher threshold for safe = reduce noise from false positives
  static const Map<DangerLevel, double> confidenceThresholds = {
    DangerLevel.critical: 0.40, // NEVER miss stairs/vehicles — even low-confidence matters
    DangerLevel.warning:  0.50, // People/animals — moderate threshold
    DangerLevel.caution:  0.55, // Furniture — slightly higher to reduce clutter
    DangerLevel.safe:     0.65, // Landmarks — only announce when confident
  };

  // ═══ TEMPORAL SMOOTHING — Anti-Flicker ═══
  // Object must appear in N consecutive frames before we announce it.
  // This eliminates single-frame false positives that plague real-time detection.
  static const int requiredConsecutiveFrames = 3;
  final Map<String, int> _labelFrameCount = {};  // label → consecutive frame count
  final Map<String, DateTime> _labelLastSeen = {}; // label → last frame timestamp
  static const Duration frameTimeout = Duration(milliseconds: 800);

  // Throttle announcements
  DateTime _lastWarning = DateTime(2000);
  String _lastWarningMessage = '';
  static const Duration _warningCooldown = Duration(seconds: 4);
  static const Duration _criticalCooldown = Duration(seconds: 2);

  // Screen dimensions for position calculation
  double _screenWidth = 1.0;
  double _screenHeight = 1.0;

  // Getters
  List<ClassifiedObstacle> get obstacles => _obstacles;
  DangerLevel get currentDangerLevel => _currentDangerLevel;
  String get warningMessage => _warningMessage;
  bool get isWarning => _isWarning;
  bool get hapticEnabled => _hapticEnabled;

  /// COCO label → danger classification mapping
  /// These are the 80 standard COCO labels that YOLOv8 detects by default
  static const Map<String, DangerLevel> dangerMap = {
    // ═══ CRITICAL — Immediate physical danger ═══
    'stairs':       DangerLevel.critical,
    'staircase':    DangerLevel.critical,
    'steps':        DangerLevel.critical,
    'escalator':    DangerLevel.critical,
    'car':          DangerLevel.critical,
    'truck':        DangerLevel.critical,
    'bus':          DangerLevel.critical,
    'motorcycle':   DangerLevel.critical,
    'bicycle':      DangerLevel.critical,
    'train':        DangerLevel.critical,
    'fire hydrant': DangerLevel.warning,

    // ═══ WARNING — Could be dangerous ═══
    'person':       DangerLevel.warning,
    'dog':          DangerLevel.warning,
    'cat':          DangerLevel.warning,
    'horse':        DangerLevel.warning,
    'cow':          DangerLevel.warning,
    'sheep':        DangerLevel.warning,
    'elephant':     DangerLevel.warning,
    'bear':         DangerLevel.warning,

    // ═══ CAUTION — Navigational obstacles ═══
    'chair':        DangerLevel.caution,
    'couch':        DangerLevel.caution,
    'bench':        DangerLevel.caution,
    'potted plant': DangerLevel.caution,
    'dining table': DangerLevel.caution,
    'toilet':       DangerLevel.caution,
    'bed':          DangerLevel.caution,
    'suitcase':     DangerLevel.caution,
    'backpack':     DangerLevel.caution,
    'umbrella':     DangerLevel.caution,
    'handbag':      DangerLevel.caution,
    'stop sign':    DangerLevel.caution,
    'parking meter':DangerLevel.caution,

    // ═══ SAFE — Navigational landmarks (doors, etc.) ═══
    'door':         DangerLevel.safe,
    'tv':           DangerLevel.safe,
    'laptop':       DangerLevel.safe,
    'cell phone':   DangerLevel.safe,
    'book':         DangerLevel.safe,
    'clock':        DangerLevel.safe,
    'bottle':       DangerLevel.safe,
    'cup':          DangerLevel.safe,
    'fork':         DangerLevel.safe,
    'knife':        DangerLevel.caution,
    'scissors':     DangerLevel.caution,
  };

  /// Friendly label overrides for speech
  static const Map<String, String> _speechLabels = {
    'car':          'vehicle',
    'truck':        'large vehicle',
    'bus':          'bus',
    'motorcycle':   'motorcycle',
    'bicycle':      'bicycle',
    'dining table': 'table',
    'potted plant': 'plant',
    'cell phone':   'phone',
    'fire hydrant': 'fire hydrant on the path',
    'stop sign':    'stop sign',
    'couch':        'sofa',
  };

  ObstacleProvider() {
    _initProvider();
  }

  Future<void> _initProvider() async {
    final prefs = await SharedPreferences.getInstance();
    _hapticEnabled = prefs.getBool('obstacle_haptic_enabled') ?? true;
    notifyListeners();
    await _initTts();
  }

  Future<void> _initTts() async {
    await TtsConfig.apply(_tts);
    _tts.setStartHandler(() => _isSpeaking = true);
    _tts.setCompletionHandler(() => _isSpeaking = false);
  }

  /// Set screen dimensions for position calculation
  void setScreenSize(double width, double height) {
    _screenWidth = width;
    _screenHeight = height;
  }

  Future<void> setHapticEnabled(bool enabled) async {
    _hapticEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('obstacle_haptic_enabled', enabled);
    notifyListeners();
  }

  bool _isProcessingInBackground = false;

  /// Main entry: process raw YOLO detections into classified obstacles (using background isolate)
  Future<void> processDetections(List<Map<String, dynamic>> rawDetections) async {
    if (_isProcessingInBackground) return; // Drop frame if previous background run is still computing
    _isProcessingInBackground = true;

    try {
      final payload = IsolatePayload(
        rawDetections: rawDetections,
        labelFrameCount: Map<String, int>.from(_labelFrameCount),
        labelLastSeen: Map<String, DateTime>.from(_labelLastSeen),
        screenWidth: _screenWidth,
        screenHeight: _screenHeight,
        now: DateTime.now(),
      );

      // Distribute computing to Background Isolate
      final result = await compute(_processDetectionsIsolate, payload);

      // Main Isolate receives the result and updates local state instantly
      _obstacles = result.obstacles;
      
      _labelFrameCount.clear();
      _labelFrameCount.addAll(result.labelFrameCount);

      _labelLastSeen.clear();
      _labelLastSeen.addAll(result.labelLastSeen);

      // Update overall danger level
      _currentDangerLevel = _obstacles.isEmpty
          ? DangerLevel.safe
          : _obstacles.first.dangerLevel;

      // Generate warnings and haptics
      _generateWarning();

      notifyListeners();
    } catch (e) {
      debugPrint('[ObstacleProvider] Background processing error: $e');
    } finally {
      _isProcessingInBackground = false;
    }
  }

  /// Process from DetectedObjectInfo list (from LiveVisionProvider)
  void processFromDetectedObjects(List<dynamic> detectedObjects) {
    final rawDetections = detectedObjects.map((obj) => {
      'label': obj.label as String,
      'confidence': obj.confidence as double,
      'boundingBox': obj.boundingBox as Rect,
    }).toList();

    processDetections(rawDetections);
  }

  /// Classify danger level based on label and proximity (bounding box size)
  DangerLevel _classifyDanger(String label, Rect box) {
    final baseDanger = dangerMap[label] ?? DangerLevel.safe;
    final relativeSize = _calculateRelativeSize(box);

    // Escalate danger if object is very close (large bounding box)
    if (relativeSize > 0.4) {
      // Object takes up >40% of screen = very close
      if (baseDanger == DangerLevel.warning) return DangerLevel.critical;
      if (baseDanger == DangerLevel.caution) return DangerLevel.warning;
    } else if (relativeSize > 0.25) {
      // Object takes up >25% = approaching
      if (baseDanger == DangerLevel.caution) return DangerLevel.warning;
    }

    return baseDanger;
  }

  /// Calculate horizontal position: left / center / right
  String _calculatePosition(Rect box) {
    final centerX = box.center.dx;
    final third = _screenWidth / 3;

    if (centerX < third) return 'left';
    if (centerX > third * 2) return 'right';
    return 'ahead';
  }

  /// Calculate relative size (0.0 to 1.0) — proxy for distance
  double _calculateRelativeSize(Rect box) {
    if (_screenWidth <= 0 || _screenHeight <= 0) return 0;
    final area = box.width * box.height;
    final screenArea = _screenWidth * _screenHeight;
    return (area / screenArea).clamp(0.0, 1.0);
  }

  /// Generate natural language warning
  void _generateWarning() {
    if (_obstacles.isEmpty) {
      _warningMessage = 'Path appears clear.';
      _isWarning = false;
      return;
    }

    // Filter to only dangerous objects (confidence already filtered in processDetections)
    final dangerous = _obstacles.where(
      (o) => o.dangerLevel.index >= DangerLevel.caution.index
    ).toList();

    if (dangerous.isEmpty) {
      _warningMessage = 'Path appears clear.';
      _isWarning = false;
      return;
    }

    _isWarning = true;

    // Build warning based on most dangerous obstacle
    final top = dangerous.first;
    final speechLabel = _speechLabels[top.label] ?? top.label;

    switch (top.dangerLevel) {
      case DangerLevel.critical:
        _warningMessage = 'Danger! $speechLabel at ${_estimateDistance(top)}. ${_getEvadeInstruction(top.position)}!';
        _triggerHaptic(HapticFeedback.heavyImpact);
        _announceWarning(_warningMessage, isCritical: true);
        break;
      case DangerLevel.warning:
        _warningMessage = 'Caution: $speechLabel approaching at ${_estimateDistance(top)}. ${_getEvadeInstruction(top.position)}.';
        _triggerHaptic(HapticFeedback.mediumImpact);
        _announceWarning(_warningMessage, isCritical: false);
        break;
      case DangerLevel.caution:
        // Count obstacles
        final obstacleDesc = _buildObstacleList(dangerous);
        _warningMessage = 'Heads up: $obstacleDesc';
        _announceWarning(_warningMessage, isCritical: false);
        break;
      case DangerLevel.safe:
        break;
    }
  }

  // Map of approximate real-world widths (in meters) for COCO classes
  static const Map<String, double> _realWorldWidths = {
    'person': 0.5,
    'car': 1.8,
    'bicycle': 0.6,
    'motorcycle': 0.8,
    'bus': 2.5,
    'truck': 2.5,
    'chair': 0.5,
    'couch': 2.0,
    'sofa': 2.0,
    'dining table': 1.5,
    'bed': 1.5,
    'door': 0.9,
    'fire hydrant': 0.3,
    'stop sign': 0.6,
    'dog': 0.3,
    'cat': 0.2,
  };

  String _estimateDistance(ClassifiedObstacle top) {
    final realWidth = _realWorldWidths[top.label] ?? 0.5; // Default to 0.5m if unknown
    
    // Perceived width ratio (0.0 to 1.0)
    double perceivedWidthRatio = top.boundingBox.width / _screenWidth;
    if (perceivedWidthRatio <= 0) perceivedWidthRatio = 0.01; // Avoid div by zero

    // Using an assumed 60-degree horizontal FOV for the smartphone camera
    // Distance = (RealWidth * 0.866) / PerceivedWidthRatio
    double distanceMeters = (realWidth * 0.866) / perceivedWidthRatio;

    // Clamp distance to avoid crazy numbers
    distanceMeters = distanceMeters.clamp(0.2, 10.0);

    // Format output
    if (distanceMeters < 1.0) {
      return "less than 1 meter";
    } else if (distanceMeters >= 5.0) {
      return "about 5 meters";
    } else {
      return "about ${distanceMeters.toStringAsFixed(1)} meters";
    }
  }

  String _getEvadeInstruction(String position) {
    if (position == 'left') return 'Move slightly right';
    if (position == 'right') return 'Move slightly left';
    return 'Stop or step aside';
  }

  /// Build a natural language list of obstacles
  String _buildObstacleList(List<ClassifiedObstacle> obstacles) {
    // Group by label
    final Map<String, List<ClassifiedObstacle>> grouped = {};
    for (final obs in obstacles) {
      grouped.putIfAbsent(obs.label, () => []).add(obs);
    }

    final parts = <String>[];
    for (final entry in grouped.entries) {
      final label = _speechLabels[entry.key] ?? entry.key;
      final pos = entry.value.first.position;
      if (entry.value.length > 1) {
        parts.add('${entry.value.length} ${label}s $pos');
      } else {
        parts.add('$label $pos');
      }
    }

    if (parts.length == 1) return '${parts[0]}.';
    if (parts.length == 2) return '${parts[0]} and ${parts[1]}.';
    final last = parts.removeLast();
    return '${parts.join(", ")}, and $last.';
  }

  /// Announce warning via TTS with cooldown
  void _announceWarning(String message, {required bool isCritical}) {
    if (_isSpeaking) return;

    final now = DateTime.now();
    final cooldown = isCritical ? _criticalCooldown : _warningCooldown;

    // Skip if same message and within cooldown
    if (message == _lastWarningMessage &&
        now.difference(_lastWarning) < cooldown) {
      return;
    }

    _lastWarning = now;
    _lastWarningMessage = message;
    _tts.speak(message);
  }

  /// Trigger haptic feedback for danger warnings
  void _triggerHaptic(Future<void> Function() intensity) {
    if (!_hapticEnabled) return;
    intensity();
  }

  /// Get color for danger level (for UI rendering)
  static Color getDangerColor(DangerLevel level) {
    return switch (level) {
      DangerLevel.critical => const Color(0xFFFF1744),
      DangerLevel.warning  => const Color(0xFFFF9100),
      DangerLevel.caution  => const Color(0xFFFFEA00),
      DangerLevel.safe     => const Color(0xFF00E676),
    };
  }

  /// Get icon for danger level
  static IconData getDangerIcon(DangerLevel level) {
    return switch (level) {
      DangerLevel.critical => Icons.warning_amber_rounded,
      DangerLevel.warning  => Icons.error_outline_rounded,
      DangerLevel.caution  => Icons.info_outline_rounded,
      DangerLevel.safe     => Icons.check_circle_outline_rounded,
    };
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}

// ══════════════════════════════════════════════
//  BACKGROUND ISOLATE MULTI-THREADED COMPUTING
// ══════════════════════════════════════════════

/// Top-level payload for background isolate processing
class IsolatePayload {
  final List<Map<String, dynamic>> rawDetections;
  final Map<String, int> labelFrameCount;
  final Map<String, DateTime> labelLastSeen;
  final double screenWidth;
  final double screenHeight;
  final DateTime now;

  IsolatePayload({
    required this.rawDetections,
    required this.labelFrameCount,
    required this.labelLastSeen,
    required this.screenWidth,
    required this.screenHeight,
    required this.now,
  });
}

/// Top-level result from background isolate processing
class IsolateResult {
  final List<ClassifiedObstacle> obstacles;
  final Map<String, int> labelFrameCount;
  final Map<String, DateTime> labelLastSeen;

  IsolateResult({
    required this.obstacles,
    required this.labelFrameCount,
    required this.labelLastSeen,
  });
}

/// Top-level function that runs strictly inside a Background Isolate
IsolateResult _processDetectionsIsolate(IsolatePayload payload) {
  final rawDetections = payload.rawDetections;
  final labelFrameCount = Map<String, int>.from(payload.labelFrameCount);
  final labelLastSeen = Map<String, DateTime>.from(payload.labelLastSeen);
  final screenWidth = payload.screenWidth;
  final screenHeight = payload.screenHeight;
  final now = payload.now;

  final classified = <ClassifiedObstacle>[];
  final seenLabelsThisFrame = <String>{};

  // 1. Math functions localized inside isolate
  double calculateRelativeSize(Rect box) {
    if (screenWidth <= 0 || screenHeight <= 0) return 0;
    final area = box.width * box.height;
    final screenArea = screenWidth * screenHeight;
    return (area / screenArea).clamp(0.0, 1.0);
  }

  DangerLevel classifyDanger(String label, Rect box) {
    final baseDanger = ObstacleProvider.dangerMap[label] ?? DangerLevel.safe;
    final relativeSize = calculateRelativeSize(box);

    if (relativeSize > 0.4) {
      if (baseDanger == DangerLevel.warning) return DangerLevel.critical;
      if (baseDanger == DangerLevel.caution) return DangerLevel.warning;
    } else if (relativeSize > 0.25) {
      if (baseDanger == DangerLevel.caution) return DangerLevel.warning;
    }
    return baseDanger;
  }

  String calculatePosition(Rect box) {
    final centerX = box.center.dx;
    final third = screenWidth / 3;
    if (centerX < third) return 'left';
    if (centerX > third * 2) return 'right';
    return 'ahead';
  }

  // 2. Heavy calculations & loops
  for (final det in rawDetections) {
    final label = (det['label'] as String? ?? '').toLowerCase();
    final confidence = (det['confidence'] as double? ?? 0.0);
    final box = det['boundingBox'] as Rect? ?? Rect.zero;

    final dangerLevel = classifyDanger(label, box);
    final threshold = ObstacleProvider.confidenceThresholds[dangerLevel] ?? 0.5;

    if (confidence < threshold) continue;

    seenLabelsThisFrame.add(label);

    classified.add(ClassifiedObstacle(
      label: label,
      confidence: confidence,
      boundingBox: box,
      dangerLevel: dangerLevel,
      position: calculatePosition(box),
      relativeSize: calculateRelativeSize(box),
    ));
  }

  // 3. Temporal smoothing
  for (final label in seenLabelsThisFrame) {
    final lastSeen = labelLastSeen[label];
    if (lastSeen != null && now.difference(lastSeen) < ObstacleProvider.frameTimeout) {
      labelFrameCount[label] = (labelFrameCount[label] ?? 0) + 1;
    } else {
      labelFrameCount[label] = 1;
    }
    labelLastSeen[label] = now;
  }

  // 4. Decay logic
  labelFrameCount.keys
      .where((k) => !seenLabelsThisFrame.contains(k))
      .toList()
      .forEach((k) {
    final lastSeen = labelLastSeen[k];
    if (lastSeen != null && now.difference(lastSeen) > ObstacleProvider.frameTimeout) {
      labelFrameCount.remove(k);
      labelLastSeen.remove(k);
    }
  });

  // 5. Filtering temporal rules
  final obstacles = classified.where((obs) {
    final frames = labelFrameCount[obs.label] ?? 0;
    final requiredFrames = obs.dangerLevel == DangerLevel.critical
        ? 2
        : ObstacleProvider.requiredConsecutiveFrames;
    return frames >= requiredFrames;
  }).toList();

  // 6. Sorting
  obstacles.sort((a, b) => b.dangerLevel.index.compareTo(a.dangerLevel.index));

  return IsolateResult(
    obstacles: obstacles,
    labelFrameCount: labelFrameCount,
    labelLastSeen: labelLastSeen,
  );
}
