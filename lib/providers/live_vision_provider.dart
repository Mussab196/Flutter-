import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import '../utils/tts_config.dart';

/// Detection result for a single object
class DetectedObjectInfo {
  final String label;
  final double confidence;
  final Rect boundingBox;

  DetectedObjectInfo({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  String get displayConfidence => '${(confidence * 100).toStringAsFixed(0)}%';
}

/// Live Vision Provider - Manages ML Kit object detection and TTS
class LiveVisionProvider extends ChangeNotifier {
  // Text-to-speech
  final FlutterTts _flutterTts = FlutterTts();

  // Frame processing throttle — 333ms between frames (max 3 FPS)
  DateTime _lastFrameTime = DateTime(2000);
  static const Duration _frameThrottle = Duration(milliseconds: 333);

  // State
  bool _isInitialized = false;
  bool _isPaused = false;
  bool _isSpeakerOn = true;
  bool _isSpeaking = false;
  String? _errorMessage;

  // Detection results
  List<DetectedObjectInfo> _detectedObjects = [];
  String _sceneDescription = '';

  // Announce settings
  DateTime? _lastAnnouncement;
  static const Duration _announcementCooldown = Duration(seconds: 5);

  // ═══ CONFIDENCE TUNING ═══
  // Minimum confidence to include in scene description (reduces false positives)
  static const double _minDescriptionConfidence = 0.45;
  // High confidence = announced with conviction ("I can see")
  static const double _highConfidence = 0.75;
  // Low confidence = hedged ("I think I see")
  static const double _lowConfidence = 0.55;

  // Dedupe tracking — don't re-announce identical scenes
  String _lastAnnouncedDescription = '';

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isPaused => _isPaused;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isSpeaking => _isSpeaking;
  String? get errorMessage => _errorMessage;
  List<DetectedObjectInfo> get detectedObjects => _detectedObjects;
  String get sceneDescription => _sceneDescription;

  /// Initialize the provider
  Future<void> initialize() async {
    try {
      await _initTts();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to initialize: $e';
      notifyListeners();
    }
  }

  /// Initialize Text-to-Speech with premium human-like voice
  Future<void> _initTts() async {
    await TtsConfig.apply(_flutterTts);

    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
      notifyListeners();
    });

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      notifyListeners();
    });

    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      _errorMessage = 'TTS Error: $msg';
      notifyListeners();
    });
  }

  /// Generate a confidence-aware scene description
  void _generateSceneDescription() {
    if (_detectedObjects.isEmpty) {
      _sceneDescription = 'No objects detected in view.';
      return;
    }

    // Filter by minimum confidence threshold
    final confident = _detectedObjects
        .where((obj) => obj.confidence >= _minDescriptionConfidence)
        .toList();

    if (confident.isEmpty) {
      _sceneDescription = 'No objects detected in view.';
      return;
    }

    // Group objects by label, tracking best confidence per label
    Map<String, int> objectCounts = {};
    Map<String, double> objectBestConfidence = {};

    for (var obj in confident) {
      objectCounts[obj.label] = (objectCounts[obj.label] ?? 0) + 1;
      if ((objectBestConfidence[obj.label] ?? 0) < obj.confidence) {
        objectBestConfidence[obj.label] = obj.confidence;
      }
    }

    // Build confidence-aware description
    List<String> descriptions = [];
    objectCounts.forEach((label, count) {
      if (count == 1) {
        descriptions.add('a $label');
      } else {
        descriptions.add('$count ${label}s');
      }
    });

    // Determine overall confidence level for phrasing
    final avgConfidence = objectBestConfidence.values.reduce((a, b) => a + b)
        / objectBestConfidence.length;

    String prefix;
    if (avgConfidence >= _highConfidence) {
      prefix = 'I can see';           // High confidence
    } else if (avgConfidence >= _lowConfidence) {
      prefix = 'I think I can see';   // Moderate
    } else {
      prefix = 'I might be seeing';   // Low but above threshold
    }

    if (descriptions.length == 1) {
      _sceneDescription = '$prefix ${descriptions[0]}.';
    } else if (descriptions.length == 2) {
      _sceneDescription = '$prefix ${descriptions[0]} and ${descriptions[1]}.';
    } else {
      final lastItem = descriptions.removeLast();
      _sceneDescription = '$prefix ${descriptions.join(", ")}, and $lastItem.';
    }
  }

  /// Announce the scene description via TTS — with deduplication
  void _announceIfNeeded() {
    if (!_isSpeakerOn || _isPaused || _isSpeaking) return;

    final now = DateTime.now();
    if (_lastAnnouncement != null &&
        now.difference(_lastAnnouncement!) < _announcementCooldown) {
      return;
    }

    if (_sceneDescription.isNotEmpty &&
        _sceneDescription != 'No objects detected in view.' &&
        _sceneDescription != _lastAnnouncedDescription) {
      _speak(_sceneDescription);
      _lastAnnouncement = now;
      _lastAnnouncedDescription = _sceneDescription;
    }
  }

  /// Speak text using TTS
  Future<void> _speak(String text) async {
    if (!_isSpeakerOn) return;
    await _flutterTts.speak(text);
  }

  /// Toggle pause state
  void togglePause() {
    _isPaused = !_isPaused;
    if (_isPaused) {
      _flutterTts.stop();
    }
    notifyListeners();
  }

  /// Toggle speaker
  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    if (!_isSpeakerOn) {
      _flutterTts.stop();
    }
    notifyListeners();
  }

  /// Manually trigger scene description announcement
  Future<void> announceScene() async {
    if (_sceneDescription.isNotEmpty) {
      await _speak(_sceneDescription);
    }
  }

  /// Announce Gemini detection results
  Future<void> announceGeminiDetections(List<String> labels) async {
    if (!_isSpeakerOn || _isPaused) return;

    if (labels.isEmpty) {
      await _speak('No objects detected.');
      return;
    }

    // Build natural description
    String description;
    if (labels.length == 1) {
      description = 'I can see ${labels[0]}.';
    } else if (labels.length == 2) {
      description = 'I can see ${labels[0]} and ${labels[1]}.';
    } else {
      final lastItem = labels.removeLast();
      description = 'I can see ${labels.join(", ")}, and $lastItem.';
    }

    _sceneDescription = description;
    notifyListeners();

    await _speak(description);
  }

  /// Handle YOLO detection results from YOLOView
  void onDetectionResults(List<YOLOResult> results) {
    // 1. Throttle frame processing to save battery & stop UI lag
    final now = DateTime.now();
    if (now.difference(_lastFrameTime) < _frameThrottle) return;
    _lastFrameTime = now;

    // Convert YOLO results to our internal format — filter out noise early
    _detectedObjects = results
        .where((r) => r.confidence >= 0.30) // Hard floor: ignore sub-30% garbage
        .map((result) => DetectedObjectInfo(
              label: result.className,
              confidence: result.confidence,
              boundingBox: result.boundingBox,
            ))
        .toList();

    // Generate scene description (applies its own higher threshold)
    _generateSceneDescription();

    // Announce if needed (with deduplication)
    _announceIfNeeded();

    notifyListeners();
  }

  /// Stop all operations
  Future<void> stop() async {
    await _flutterTts.stop();
    _isPaused = true;
    notifyListeners();
  }

  /// Dispose resources
  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }
}
