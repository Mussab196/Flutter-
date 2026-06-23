import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'agent_skills.dart';
import 'offline_command_matcher.dart';
import '../utils/tts_config.dart';


/// Agent States — exhaustive enum for precise UI and logic control
enum AgentState {
  resting,       // Idle, passively listening for wake word
  waking,        // Wake word detected, acknowledging
  listening,     // Actively listening for user command
  thinking,      // Processing command via Gemini
  speaking,      // Speaking response to user
  executing,     // Executing action (navigation, trigger, etc.)
  error,         // Recoverable error occurred
  disabled,      // Agent turned off in settings
}

/// A single turn in the conversation memory
class ConversationTurn {
  final String userMessage;
  final String agentResponse;
  final String action;
  final DateTime timestamp;

  ConversationTurn({
    required this.userMessage,
    required this.agentResponse,
    required this.action,
    required this.timestamp,
  });

  Map<String, String> toPromptFormat() => {
    'user': userMessage,
    'assistant': agentResponse,
    'action': action,
  };
}

class AgentProvider extends ChangeNotifier {
  bool _isDisposed = false;
  // ══════════════════════════════════════════════
  //  STATE
  // ══════════════════════════════════════════════
  AgentState _state = AgentState.resting;
  AgentState get state => _state;

  bool get isListening => _state == AgentState.listening;
  bool get isProcessing => _state == AgentState.thinking;
  bool get isSpeaking => _state == AgentState.speaking;
  bool get isExecuting => _state == AgentState.executing;
  bool get isActive => _state != AgentState.resting && _state != AgentState.disabled;

  bool _agentEnabled = true;
  bool get agentEnabled => _agentEnabled;

  String _currentStatusText = "Resting";
  String get currentStatusText => _currentStatusText;

  String _lastUserTranscript = "";
  String get lastUserTranscript => _lastUserTranscript;

  String _errorMessage = "";
  String get errorMessage => _errorMessage;

  // ══════════════════════════════════════════════
  //  CONVERSATION MEMORY (last 5 turns)
  // ══════════════════════════════════════════════
  final List<ConversationTurn> _conversationHistory = [];
  List<ConversationTurn> get conversationHistory => List.unmodifiable(_conversationHistory);
  static const int _maxHistoryTurns = 5;

  // ══════════════════════════════════════════════
  //  SELF-ECHO DETECTION
  // ══════════════════════════════════════════════
  /// Stores the last TTS output so we can reject STT input that matches it.
  /// This prevents the agent from hearing its own speech and treating it as a new command.
  String _lastSpokenTextForEcho = '';
  DateTime _lastSpeakTime = DateTime(2000);
  static const Duration _echoCooldown = Duration(seconds: 3);

  /// Check if the heard text is just the agent's own speech echoing back
  bool _isSelfEcho(String heardText) {
    if (_lastSpokenTextForEcho.isEmpty) return false;
    // Only check within cooldown window after speaking
    if (DateTime.now().difference(_lastSpeakTime) > _echoCooldown) return false;
    
    final heard = heardText.toLowerCase().trim();
    final spoken = _lastSpokenTextForEcho.toLowerCase().trim();
    
    // If too short, skip echo check (wake words like "hey aura" are real commands)
    if (heard.length < 15) return false;
    
    // Check if heard text is a substring of what we just said
    if (spoken.contains(heard)) return true;
    if (heard.contains(spoken) && spoken.length > 10) return true;
    
    // Check word overlap — if >60% of heard words appear in spoken text
    final heardWords = heard.split(' ').where((w) => w.length > 2).toSet();
    final spokenWords = spoken.split(' ').where((w) => w.length > 2).toSet();
    if (heardWords.isEmpty) return false;
    
    final overlap = heardWords.intersection(spokenWords).length;
    final overlapRatio = overlap / heardWords.length;
    if (overlapRatio > 0.6) {
      debugPrint('[Aura Echo] Rejected self-echo: "$heard" matched ${(overlapRatio * 100).toStringAsFixed(0)}% of last spoken');
      return true;
    }
    return false;
  }

  // ══════════════════════════════════════════════
  //  CONTEXT (injected by app)
  // ══════════════════════════════════════════════
  String _currentScreenRoute = '/home';
  String _currentScreenName = 'Home';

  String get currentScreenRoute => _currentScreenRoute;
  String get currentScreenName => _currentScreenName;

  void updateCurrentScreen(String route, String name) {
    _currentScreenRoute = route;
    _currentScreenName = name;
  }

  // Startup grace period to ignore STT during app launch (TTS greeting, TalkBack, etc)
  final DateTime _appStartTime = DateTime.now();

  // ══════════════════════════════════════════════
  //  EXTERNAL DEPENDENCIES
  // ══════════════════════════════════════════════
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  // GenerativeModel moved to Python LangGraph backend
  bool _sttInitialized = false;
  bool _ttsInitialized = false;
  bool _isTtsSpeaking = false;
  bool _isTransitioning = false;
  Completer<void>? _speakCompleter;

  // Track if we've already greeted on startup to prevent repeated greetings
  static bool _hasGreetedOnStartup = false;

  // API Keys — Loaded from SharedPreferences or env
  String _geminiApiKey = '';
  String get geminiApiKey => _geminiApiKey;

  String _azureApiKey = '';
  String get azureApiKey => _azureApiKey;
  
  String _backendUrl = 'https://malik2165-aura-agent.hf.space';
  String get backendUrl => _backendUrl;

  // Wake word variants — comprehensive coverage for accent/mishearing tolerance
  static const List<String> _wakeWords = [
    'hey aura',
    'hello aura',
    'hi aura',
    'okay aura',
    'ok aura',
    'aura',         // standalone wake word
    // common misrecognitions
    'a aura',
    'hera',
    'aurora',
    'ara',
    'or a',
    'are a',
    'ora',
    'aira',
    'awra',
    'dora',
    'laura',
    // Urdu/Hindi common STT misrecognitions
    'he aura',
    'hai aura',
    'hey aur',
    'hey ara',
    'ay aura',
    'ay ara',
    'suno aura',
    'aura suno',
    'aurat',
    'horrah'
  ];

  /// Fuzzy wake-word match: allows up to 2 character edits (Levenshtein distance)
  static bool _fuzzyWakeWordMatch(String input) {
    // First: exact substring match (fastest path)
    if (_wakeWords.any((w) => input.contains(w))) return true;

    // Second: check each word-pair in input against "aura" with edit distance
    final words = input.split(' ');
    for (var word in words) {
      if (_levenshtein(word, 'aura') <= 1) return true;
    }
    return false;
  }

  /// Simple Levenshtein distance for short strings
  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> prev = List.generate(t.length + 1, (i) => i);
    List<int> curr = List.filled(t.length + 1, 0);

    for (int i = 1; i <= s.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= t.length; j++) {
        int cost = s[i - 1] == t[j - 1] ? 0 : 1;
        curr[j] = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce((a, b) => a < b ? a : b);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[t.length];
  }

  // Shake detection
  StreamSubscription? _shakeSubscription;
  static const double _shakeThreshold = 15.0;
  DateTime _lastShakeTime = DateTime(2000);

  // User name for personalized greetings
  String _userName = '';

  // Passive listening retry
  int _passiveRetryCount = 0;
  static const int _maxPassiveRetries = 10;
  Timer? _passiveRestartTimer;

  // Follow-up mode — keeps listening after action
  bool _followUpMode = false;
  Timer? _followUpTimer;

  // Offline Mode - user setting
  bool _offlineMode = false;
  bool get offlineMode => _offlineMode;

  AgentProvider() {
    _initAgent();
  }

  // ══════════════════════════════════════════════
  //  INITIALIZATION
  // ══════════════════════════════════════════════
  Future<void> _initAgent() async {
    try {
      // 1. Load settings & API key
      final prefs = await SharedPreferences.getInstance();
      _agentEnabled = prefs.getBool('agent_enabled') ?? true;
      // Check both keys for backwards compatibility
      _userName = prefs.getString('user_name') ?? 
                  prefs.getString('aura-user-name') ?? '';
      _geminiApiKey = prefs.getString('gemini_api_key') ?? 
                      const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
      _azureApiKey = prefs.getString('azure_api_key') ?? '';
      
      _backendUrl = prefs.getString('vision_backend_url') ?? 'https://malik2165-aura-agent.hf.space';
      _offlineMode = prefs.getBool('vision_offline_mode') ?? false;

      if (_geminiApiKey.isEmpty) {
        debugPrint('[Vision Agent] ⚠️ No Gemini API key found. Set via settings or env.');
        // Don't set a fake key — agent will gracefully handle missing key
      }

      // 2. (Gemini model initialization moved to Python LangGraph backend)

      // 3. Initialize TTS with completion tracking
      await _initTts();

      // 4. Initialize Speech-To-Text
      await _initStt();

      // 5. Initialize shake-to-activate
      _initShakeDetection();

      // 6. Start passive listening if enabled
      if (_agentEnabled && _sttInitialized) {
        _setState(AgentState.resting);
        _startPassiveListening();
        // Smart greeting on startup (only once)
        if (!_hasGreetedOnStartup) {
          _hasGreetedOnStartup = true;
          // Delay greeting so passive listening has time to fully start first
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!_isDisposed) {
              final greeting = AgentSkills.getSmartGreeting(_userName);
              speak(greeting, awaitCompletion: false);
            }
          });
        }
      } else if (!_agentEnabled) {
        _setState(AgentState.disabled);
      }
    } catch (e) {
      debugPrint('[Vision Agent] Init error: $e');
      _setState(AgentState.error);
      _errorMessage = 'Agent initialization failed';
      notifyListeners();
    }
  }



  /// Shake phone to activate Vision (like tapping Iron Man's arc reactor)
  void _initShakeDetection() {
    _shakeSubscription?.cancel();
    _shakeSubscription = accelerometerEventStream().listen((event) {
      final double acceleration = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z
      );

      if (acceleration > _shakeThreshold) {
        final now = DateTime.now();
        // Debounce: only respond to shakes 2 seconds apart
        if (now.difference(_lastShakeTime).inMilliseconds > 2000) {
          _lastShakeTime = now;
          if (_agentEnabled && _state == AgentState.resting) {
            debugPrint('[Vision Agent] 📱 Shake detected! Activating...');
            HapticFeedback.heavyImpact();
            _onWakeWordDetected();
          }
        }
      }
    });
  }



  /// Initialize TTS with premium human-like voice
  Future<void> _initTts() async {
    try {
      // Apply centralized premium voice configuration
      await TtsConfig.apply(_flutterTts);

      _flutterTts.setStartHandler(() {
        debugPrint('[Vision TTS] Started speaking');
        _isTtsSpeaking = true;
      });

      _flutterTts.setCompletionHandler(() {
        debugPrint('[Vision TTS] Finished speaking');
        _isTtsSpeaking = false;
        _speakCompleter?.complete();
        _speakCompleter = null;
        
        // Restart passive listening if we are in resting state
        if (_state == AgentState.resting && _agentEnabled) {
          _startPassiveListening();
        }
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint('[Vision TTS] Error: $msg');
        _isTtsSpeaking = false;
        _speakCompleter?.completeError(msg);
        _speakCompleter = null;
      });

      _flutterTts.setCancelHandler(() {
        _isTtsSpeaking = false;
        _speakCompleter?.complete();
        _speakCompleter = null;
      });

      _ttsInitialized = true;
    } catch (e) {
      debugPrint('[Vision TTS] Init error: $e');
      _ttsInitialized = false;
    }
  }

  /// Initialize STT with robust error handling and explicit permission check
  Future<void> _initStt() async {
    try {
      // Explicitly request microphone permission first
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }

      if (!status.isGranted) {
        debugPrint('[Vision STT] Microphone permission denied by user.');
        _errorMessage = 'Microphone access denied';
        _sttInitialized = false;
        _setState(AgentState.error);
        return;
      }

      _sttInitialized = await _speechToText.initialize(
        onStatus: _onSttStatus,
        onError: (error) {
          debugPrint('[Vision STT] Error: ${error.errorMsg} (permanent: ${error.permanent})');
          if (error.errorMsg == 'error_speech_timeout' || error.errorMsg == 'error_no_match') {
            // Silence timeout. 
            if (_followUpMode || _state == AgentState.listening) {
              // Active listen or follow-up timed out without user speaking. Reset to resting.
              _followUpMode = false;
              _setState(AgentState.resting);
              _currentStatusText = "Resting";
              notifyListeners();
              _startPassiveListening();
              return;
            }
            
            // Restart passive listening seamlessly.
            if (_agentEnabled && _state == AgentState.resting && !_followUpMode) {
              _schedulePassiveRestart();
            }
            return;
          }
          if (error.permanent) {
            // Many 'permanent' errors from STT (like error_client) are actually transient Google app bugs.
            // Don't show scary permission errors for them.
            debugPrint('[Vision STT] Permanent error detected: ${error.errorMsg}');
            
            // Only show UI error if it's an active listen that failed
            if (_state == AgentState.listening) {
              _errorMessage = 'Mic error: ${error.errorMsg}';
              _setState(AgentState.error);
              
              // Auto-clear error after 3 seconds
              Future.delayed(const Duration(seconds: 3), () {
                if (_state == AgentState.error && !_isDisposed) {
                   _setState(AgentState.resting);
                   _startPassiveListening();
                }
              });
            } else {
              // If it failed during background passive listening, just silently retry
              _schedulePassiveRestart(isError: true);
            }
          }
        },
      );
      debugPrint('[Vision STT] Initialized: $_sttInitialized');
    } catch (e) {
      debugPrint('[Vision STT] Init error: $e');
      _sttInitialized = false;
    }
  }

  // ══════════════════════════════════════════════
  //  STT STATUS HANDLER
  // ══════════════════════════════════════════════
  void _onSttStatus(String status) {
    debugPrint('[Vision STT] Status: $status');
    if (_isTransitioning) return;
    
    if (status == 'notListening' || status == 'done') {
      if (_state == AgentState.listening && _lastUserTranscript.isNotEmpty) {
        debugPrint('[Vision STT] Listen ended without finalResult. Forcing process.');
        final text = _lastUserTranscript;
        _lastUserTranscript = "";
        _onCommandReceived(text);
        return;
      }

      if (_followUpMode || _state == AgentState.listening) {
        // Active listen or follow-up naturally stopped (timeout). Reset state.
        _followUpMode = false;
        _setState(AgentState.resting);
        _currentStatusText = "Resting";
        notifyListeners();
        _startPassiveListening();
      } else if (_agentEnabled && _state == AgentState.resting) {
        // Restart passive listening seamlessly
        _schedulePassiveRestart();
      }
    }
  }

  /// Schedule passive listening restart with exponential backoff
  void _schedulePassiveRestart({bool isError = false}) {
    _passiveRestartTimer?.cancel();
    if (isError) {
      _passiveRetryCount++;
    }
    
    if (_passiveRetryCount >= _maxPassiveRetries) {
      debugPrint('[Vision Agent] Max passive retries reached, backing off');
      _passiveRetryCount = 0;
      _passiveRestartTimer = Timer(const Duration(seconds: 15), () {
        if (_agentEnabled && _state == AgentState.resting) {
          _startPassiveListening();
        }
      });
      return;
    }

    // Give Android STT service enough time to release the mic before restarting
    // If it's an error retry, back off exponentially. Otherwise, wait 800ms.
    final delay = isError 
        ? Duration(milliseconds: (1000 * (1 << (_passiveRetryCount - 1))).clamp(1000, 10000))
        : const Duration(milliseconds: 800);
        
    _passiveRestartTimer = Timer(delay, () {
      if (_agentEnabled && _state == AgentState.resting) {
        _startPassiveListening();
      }
    });
  }

  // ══════════════════════════════════════════════
  //  PASSIVE LISTENING (Wake Word Detection)
  // ══════════════════════════════════════════════
  Future<void> _startPassiveListening() async {
    if (!_agentEnabled || !_sttInitialized) return;
    if (_state != AgentState.resting && _state != AgentState.disabled) return;

    try {
      _isTransitioning = true;
      // Always stop before starting to clear any lingering OS mic locks
      await _speechToText.cancel();
      await _speechToText.stop();
      // Small delay to ensure STT callbacks from cancel/stop have fired and are ignored
      await Future.delayed(const Duration(milliseconds: 300));
      _isTransitioning = false;
      
      await _speechToText.listen(
        onResult: (result) {
          // Ignore STT events while the agent is speaking its own response
          if (_isTtsSpeaking) return;

          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          
          // Self-echo check: reject if this is the agent hearing itself
          if (_isSelfEcho(words)) return;

          // Direct Offline Command Evaluation (Runs continuously in background)
          final offlineMatch = OfflineCommandMatcher.tryMatch(words);
          if (offlineMatch.confidence >= 0.75) {
            debugPrint('[Aura Agent] ⚡ Direct background offline command matched: ${offlineMatch.action}');
            _speechToText.stop();
            _passiveRetryCount = 0;
            _executeOfflineMatch(words, offlineMatch, isPassive: true);
            return;
          }

          // Check for any wake word — exact + fuzzy
          bool wakeWordDetected = _fuzzyWakeWordMatch(words);

          if (wakeWordDetected) {
            _passiveRetryCount = 0; // Reset retry count on success
            _onWakeWordDetected();
            return;
          }
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 5), // Android native STT limits
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
        localeId: 'en_US',
        onDevice: _offlineMode, // Use on-device STT when offline
      );
      _passiveRetryCount = 0; // Reset on successful start
    } catch (e) {
      debugPrint('[Vision Agent] Passive listening error: $e');
      _schedulePassiveRestart(isError: true);
    }
  }

  /// Handle wake word detection — Jarvis-style acknowledgement
  void _onWakeWordDetected() {
    _setState(AgentState.waking);
    _currentStatusText = "Heard you!";
    HapticFeedback.heavyImpact();

    // Instantly activate the microphone instead of making the user wait for a TTS response.
    // Run after a small delay to escape the STT onResult callback and prevent deadlocks
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_isDisposed) startListening();
    });
  }

  // ══════════════════════════════════════════════
  //  ACTIVE LISTENING (User Command Capture)
  // ══════════════════════════════════════════════
  Future<void> startListening() async {
    if (!_agentEnabled) {
      await speak("Aura assistant is disabled. You can enable it in settings.");
      _setState(AgentState.disabled);
      return;
    }

    if (!_sttInitialized) {
      await speak("Sorry, microphone is not available right now.");
      _setState(AgentState.error);
      return;
    }

    _isTransitioning = true;
    
    // CRITICAL FIX: Explicitly cancel any active passive listening session
    // while the transitioning flag is true. This prevents the old session's
    // 'done' event from instantly aborting the new active listening session!
    await _speechToText.cancel();
    await _speechToText.stop();

    _setState(AgentState.listening);
    _currentStatusText = "Listening...";
    _lastUserTranscript = "";
    notifyListeners();

    await _flutterTts.stop(); // Stop any ongoing speech
    // Reduced to 100ms so it goes to listening instantly after speaking
    await Future.delayed(const Duration(milliseconds: 300)); 
    _isTransitioning = false;

    try {
      await _speechToText.listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase().trim();
          
          // Self-echo check: reject if this is the agent hearing itself
          if (_isSelfEcho(words)) {
            debugPrint('[Aura Agent] 🔇 Ignoring self-echo in active listen: "$words"');
            return;
          }
          
          // Update transcript in real-time for UI
          _lastUserTranscript = result.recognizedWords;
          notifyListeners();
          
          // Instantly execute offline commands without waiting for silence timeout
          final offlineMatch = OfflineCommandMatcher.tryMatch(words);
          if (offlineMatch.confidence >= 0.75) {
            debugPrint('[Aura Agent] ⚡ Direct active offline command matched: ${offlineMatch.action}');
            _speechToText.stop();
            _onCommandReceived(result.recognizedWords);
            return;
          }

          if (result.finalResult) {
            _onCommandReceived(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 15), 
        pauseFor: const Duration(seconds: 10),
        cancelOnError: false,
        listenMode: stt.ListenMode.confirmation,
        localeId: 'en_US',
        onDevice: _offlineMode, // Use on-device STT when offline for zero-network operation
      );
    } catch (e) {
      debugPrint('[Vision Agent] Active listening error: $e');
      await speak("Sorry, I couldn't hear you. Please try again.");
      _setState(AgentState.resting);
      _startPassiveListening();
    }
  }

  /// Helper to check internet connectivity quickly
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Handle received command
  void _onCommandReceived(String command) async {
    if (command.trim().isEmpty) {
      await speak("I didn't catch that. Say 'Hey Aura' and try again.");
      _setState(AgentState.resting);
      _startPassiveListening();
      return;
    }

    // Stop any ongoing speech immediately so user doesn't have to wait
    await _flutterTts.stop();

    _setState(AgentState.thinking);
    _currentStatusText = "Thinking...";
    notifyListeners();

    // ═══════════════════════════════════════════════════════════════
    //  OFFLINE-FIRST ARCHITECTURE
    //  tryMatch() now ALWAYS returns a result (never null).
    //  - confidence >= 0.75: High confidence → execute directly
    //  - confidence >= 0.50: Medium → use if offline, else try cloud
    //  - confidence < 0.50:  Fallback/help text → use if offline, else cloud
    // ═══════════════════════════════════════════════════════════════

    final offlineResult = OfflineCommandMatcher.tryMatch(command);
    debugPrint('[Vision Agent] ⚡ Offline match: ${offlineResult.action}/${offlineResult.target} (${(offlineResult.confidence * 100).toStringAsFixed(0)}%)');

    // HIGH CONFIDENCE → Execute immediately (instant, 0ms)
    if (offlineResult.confidence >= 0.75) {
      await _executeOfflineMatch(command, offlineResult);
      return;
    }

    // OFFLINE MODE → Always use offline result (even low confidence)
    if (_offlineMode) {
      if (offlineResult.confidence >= 0.40) {
        await _executeOfflineMatch(command, offlineResult);
      } else {
        // Use the fallback/help response
        _setState(AgentState.speaking);
        await speak(offlineResult.speech, awaitCompletion: true);
        _addToHistory(command, offlineResult.speech, 'inform');
        _setState(AgentState.resting);
        _startPassiveListening();
      }
      return;
    }

    // ONLINE MODE → Try cloud for complex/low-confidence queries
    bool canUseOnline = _geminiApiKey.isNotEmpty && await _hasInternet();

    if (canUseOnline && offlineResult.confidence < 0.60) {
      // Cloud is available AND offline has low confidence → use cloud
      debugPrint('[Vision Agent] 🌐 Low offline confidence, forwarding to cloud...');
      await _processUserCommand(command);
    } else if (offlineResult.confidence >= 0.40) {
      // Medium confidence or no cloud → use offline
      await _executeOfflineMatch(command, offlineResult);
    } else if (canUseOnline) {
      // Very low confidence but cloud available → try cloud
      await _processUserCommand(command);
    } else {
      // No cloud, low confidence → use fallback
      _setState(AgentState.speaking);
      await speak(offlineResult.speech, awaitCompletion: true);
      _addToHistory(command, offlineResult.speech, 'inform');
      _setState(AgentState.resting);
      _startPassiveListening();
    }
  }

  /// Execute an offline-matched command with full skill resolution.
  /// This handles the speech output, skill calls, and action routing
  /// identically to how the online agent path works — so ActionRouter
  /// sees no difference.
  Future<void> _executeOfflineMatch(String command, OfflineMatchResult match, {bool isPassive = false}) async {
    try {
      String speechOutput = match.speech;

      // ─── Resolve skill-based speech (time, battery, etc.) ───
      if (match.useSkill != null) {
        switch (match.useSkill) {
          case 'flashlight':
            if (match.target == 'flash_on') {
              speechOutput = await AgentSkills.setFlashlight(true);
            } else if (match.target == 'flash_off') {
              speechOutput = await AgentSkills.setFlashlight(false);
            } else {
              speechOutput = await AgentSkills.toggleFlashlight();
            }
            break;
          case 'greet':
            speechOutput = AgentSkills.getSmartGreeting(_userName);
            break;
          case 'clipboard':
            speechOutput = await AgentSkills.readClipboard();
            break;
          case 'math':
            speechOutput = AgentSkills.tryMathAnswer(match.target) ?? 
                "I couldn't solve that. Try saying something like: 25 plus 30.";
            break;
          case 'remember':
            speechOutput = await AgentSkills.saveReminder(match.target);
            break;
          case 'recall':
            speechOutput = await AgentSkills.getReminders();
            break;
          case 'recall_clear':
            speechOutput = await AgentSkills.clearReminders();
            break;
          case 'where_am_i':
            speechOutput = await AgentSkills.whereAmI();
            break;
          case 'read_medicine':
            speechOutput = await AgentSkills.detectMedicineLabel(
              geminiApiKey: _geminiApiKey,
            );
            break;
          case 'scene_memory':
            speechOutput = AgentSkills.recallLastScene();
            break;
        }
      }

      // Save to conversation memory
      _addToHistory(command, speechOutput, match.action);

      // 1. Set the intent so ActionRouter can execute it INSTANTLY
      final intent = match.toIntent();
      intent['speech'] = speechOutput;
      
      if (!isPassive) {
        _setState(AgentState.executing);
      }
      _lastIntent = intent;
      notifyListeners();

      // 2. Speak the response (fire and forget)
      if (speechOutput.isNotEmpty) {
        speak(speechOutput, awaitCompletion: false);
      }

      // 3. Enter follow-up mode (only if active)
      if (!isPassive) {
        _enterFollowUpMode();
      } else {
        // If passive, we go back to resting and silently restart listening
        _setState(AgentState.resting);
        _startPassiveListening();
      }

    } catch (e) {
      debugPrint('[Vision Agent] Offline execution error: $e');
      _setState(AgentState.speaking);
      await speak("Sorry, something went wrong. Please try again.", awaitCompletion: true);
      _setState(AgentState.resting);
      _startPassiveListening();
    }
  }

  void stopListening() {
    _speechToText.stop();
    _followUpMode = false;
    _followUpTimer?.cancel();
    _setState(AgentState.resting);
    _currentStatusText = "Resting";
    notifyListeners();
    _startPassiveListening();
  }

  // ══════════════════════════════════════════════
  //  COMMAND PROCESSING (Gemini AI)
  // ══════════════════════════════════════════════
  Future<void> _processUserCommand(String command) async {
    try {
      debugPrint('[Vision Agent] User said: "$command"');

      // 1. Instantly check Offline Commands first before calling Gemini
      final offlineMatch = OfflineCommandMatcher.tryMatch(command);
      if (offlineMatch.confidence >= 0.75) {
        debugPrint('[Aura Agent] ⚡ Fast-tracking active command via offline matcher: ${offlineMatch.action}');
        _executeOfflineMatch(command, offlineMatch);
        return;
      }

      // Guard: If no API keys, inform user
      if (_geminiApiKey.isEmpty && _azureApiKey.isEmpty) {
        _setState(AgentState.speaking);
        await speak('Please set your Gemini or Azure API key in settings first.', awaitCompletion: true);
        _setState(AgentState.resting);
        _startPassiveListening();
        return;
      }

      // Build context-rich prompt
      final contextPrompt = _buildContextPrompt(command);

      // Determine API URL (Use dynamic URL if set, otherwise default to localhost)
      if (_geminiApiKey.isEmpty) {
        _setState(AgentState.speaking);
        await speak('Your API key is missing. Please set it in Settings.', awaitCompletion: true);
        _setState(AgentState.resting);
        _startPassiveListening();
        return;
      }

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _geminiApiKey,
        generationConfig: GenerationConfig(
          temperature: 0.3,
          maxOutputTokens: 500,
        ),
        // tools: [Tool.googleSearch()], // Unsupported in this package version
        systemInstruction: Content.system('''
You are Aura, an intelligent AI assistant inside the 'Aura' mobile app for visually impaired users.

RULES:
1. Your response will be spoken aloud via TTS to a blind user. Be clear, concise, natural, and highly intelligent.
2. You MUST return ONLY a raw JSON object. NO markdown, NO code blocks, NO backticks, NO explanation text.
3. You have access to real-time Google Search. For ANY general knowledge question, latest news, weather, or facts, use your search grounding to provide accurate, up-to-date answers. 
4. Think critically and answer ANY question the user asks intelligently using the "inform" action.
5. If the user speaks in Urdu or Hindi, respond in that language and set "language" to "ur" or "hi".
6. NEVER repeat your previous answer unless explicitly asked "repeat that".
7. Keep answers to 2-3 sentences max unless the user asks for detail.
8. If unsure even after searching, say so honestly.

RESPONSE FORMAT (ONLY this JSON, nothing else):
{"action": "ACTION", "target": "TARGET", "speech": "YOUR_ANSWER", "language": "en"}


ACTIONS:
- "inform" — Answer any question, give information, or respond conversationally.
- "navigate" — Open a screen. target = route name (e.g. "/live-vision", "/settings").
- "trigger" — Trigger device action. target = "flash_on", "flash_off", etc.
- "greet" — Greet the user.
- "math" — Solve a math problem.
- "where_am_i" — Tell user their location.
- "remember" — Save a reminder. target = what to remember.
- "recall" — Recall saved reminders.
- "read_document" — Read a document.
- "read_medicine" — Read medicine label.
- "scene_memory" — Recall last scene.
- "status" — Report app/device status.
- "repeat" — Repeat last response.
- "volume" — Change volume.
- "call" — Make a phone call.
- "toggle" — Toggle a setting.

EXAMPLES:
User: "What is the capital of France?" → {"action": "inform", "target": "general", "speech": "The capital of France is Paris.", "language": "en"}
User: "Open settings" → {"action": "navigate", "target": "/settings", "speech": "Opening settings.", "language": "en"}
User: "Pakistan ka prime minister kon ha?" → {"action": "inform", "target": "general", "speech": "Pakistan ke Prime Minister Shehbaz Sharif hain.", "language": "ur"}

IMPORTANT: Return ONLY the JSON. No extra text.
''')
      );

      final content = [Content.text(contextPrompt)];
      final response = await model.generateContent(content).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Gemini API took too long to respond'),
      );

      final String? responseText = response.text;
      debugPrint('[Vision Agent] Gemini local response: $responseText');

      if (responseText == null || responseText.trim().isEmpty) {
        throw Exception('Empty response from AI');
      }

      // Parse JSON response (handle markdown code blocks)
      String cleanJson = responseText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      
      Map<String, dynamic> intent;
      try {
        intent = jsonDecode(cleanJson);
      } catch (e) {
        // Try to extract JSON from mixed content (multiple strategies)
        Map<String, dynamic>? parsed;
        
        // Strategy 1: Find first complete JSON object
        final jsonMatch = RegExp(r'\{[^{}]*\}').firstMatch(cleanJson);
        if (jsonMatch != null) {
          try {
            parsed = jsonDecode(jsonMatch.group(0)!);
          } catch (_) {}
        }
        
        // Strategy 2: Find JSON with nested braces
        if (parsed == null) {
          final deepMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(cleanJson);
          if (deepMatch != null) {
            try {
              parsed = jsonDecode(deepMatch.group(0)!);
            } catch (_) {}
          }
        }
        
        if (parsed != null) {
          intent = parsed;
        } else {
          // Last resort: treat entire response as informational speech
          intent = {
            'action': 'inform',
            'target': 'general',
            'speech': cleanJson.length > 200 ? cleanJson.substring(0, 200) : cleanJson,
            'language': 'en',
          };
        }
      }

      // Validate required fields
      final String action = intent['action']?.toString() ?? 'inform';
      final String speechOutput = intent['speech']?.toString() ?? 'Done.';
      // Ensure target exists in intent (ActionRouter reads it directly)
      intent['target'] ??= 'general';
      // Use the language from the agent if provided, else default to 'en'
      final String lang = intent['language'] ?? 'en';

      // Save to conversation memory
      _addToHistory(command, speechOutput, action);

      // 1. Set the intent so ActionRouter can execute it INSTANTLY
      _setState(AgentState.executing);
      _lastIntent = intent;
      notifyListeners();

      // 2. Speak the response (screen changes while this happens)
      if (speechOutput.isNotEmpty) {
        await speak(speechOutput, language: lang, awaitCompletion: true);
      }

      // 3. Wait a beat for TTS to fully stop before listening again
      //    This prevents the mic from picking up the tail end of TTS audio
      await Future.delayed(const Duration(milliseconds: 500));

      // 4. Enter follow-up mode (listen for more commands)
      _enterFollowUpMode();

    } on TimeoutException {
      debugPrint('[Vision Agent] ⏰ Cloud timeout — trying offline fallback');
      await _cloudFallbackToOffline(command, 'The server is taking too long.');
    } on FormatException catch (e) {
      debugPrint('[Vision Agent] JSON parse error: $e');
      _setState(AgentState.speaking);
      await speak("I got confused for a moment. Could you say that again?", awaitCompletion: true);
      _setState(AgentState.resting);
      _startPassiveListening();
    } catch (e) {
      debugPrint('[Vision Agent] ⚠️ Cloud error: $e — trying offline fallback');
      final errorStr = e.toString().toLowerCase();
      String reason;
      
      if (errorStr.contains('api key not valid') || 
          errorStr.contains('api key not found') ||
          errorStr.contains('invalid api key') ||
          errorStr.contains('api_key_invalid')) {
        reason = 'Your Gemini API key is invalid or incorrect.';
        _setState(AgentState.speaking);
        await speak("$reason Please update it in settings.", awaitCompletion: true);
        _setState(AgentState.resting);
        _startPassiveListening();
        return;
      } else if (errorStr.contains('quota') || errorStr.contains('429') || errorStr.contains('resource_exhausted')) {
        reason = 'Your Gemini API key quota has been exceeded.';
        _setState(AgentState.speaking);
        await speak("$reason Please create a new key or wait.", awaitCompletion: true);
        _setState(AgentState.resting);
        _startPassiveListening();
        return;
      } else if (errorStr.contains('not found') || errorStr.contains('model') || errorStr.contains('404')) {
        reason = 'The AI model was not found. Please check your API key supports gemini-2.5-flash.';
        _setState(AgentState.speaking);
        await speak(reason, awaitCompletion: true);
        _setState(AgentState.resting);
        _startPassiveListening();
        return;
      } else if (errorStr.contains('permission') || errorStr.contains('403')) {
        reason = 'Your API key does not have permission to use this model.';
        _setState(AgentState.speaking);
        await speak(reason, awaitCompletion: true);
        _setState(AgentState.resting);
        _startPassiveListening();
        return;
      } else {
        reason = 'The AI service returned an error.';
      }
      await _cloudFallbackToOffline(command, reason);
    }
  }

  /// Graceful fallback: when cloud fails, try offline matcher as last resort.
  /// This prevents the user from getting stuck with "something went wrong"
  /// when the HF Space is sleeping or internet is flaky.
  Future<void> _cloudFallbackToOffline(String command, String reason) async {
    final offlineResult = OfflineCommandMatcher.tryMatch(command);
    if (offlineResult.confidence >= 0.5) {
      debugPrint('[Vision Agent] ⚡ Cloud failed but offline can handle it: ${offlineResult.action}');
      await _executeOfflineMatch(command, offlineResult);
    } else {
      // Truly unhandleable — inform the user clearly
      _setState(AgentState.speaking);
      await speak(
        "$reason I can handle navigation and device controls offline, but for this request I need an internet connection.",
        awaitCompletion: true,
      );
      _setState(AgentState.resting);
      _startPassiveListening();
    }
  }

  /// Build context-aware prompt with conversation history
  String _buildContextPrompt(String command) {
    final now = DateTime.now();
    final timeOfDay = now.hour < 12 ? 'morning' : (now.hour < 17 ? 'afternoon' : 'evening');
    
    final buffer = StringBuffer();
    
    // Context header — gives AI full situational awareness
    buffer.writeln('=== CONTEXT ===');
    buffer.writeln('Current Screen: $_currentScreenName ($_currentScreenRoute)');
    buffer.writeln('Time: ${now.hour}:${now.minute.toString().padLeft(2, '0')} ($timeOfDay)');
    buffer.writeln('Date: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    buffer.writeln('App: Aura (Accessibility App for Blind Users)');
    if (_userName.isNotEmpty) {
      buffer.writeln('User Name: $_userName');
    }
    buffer.writeln('Platform: ${Platform.isAndroid ? 'Android' : 'iOS'}');

    // Conversation history for continuity
    if (_conversationHistory.isNotEmpty) {
      buffer.writeln('\n=== PREVIOUS CONVERSATION (for context only, do NOT answer these again) ===');
      for (final turn in _conversationHistory) {
        buffer.writeln('User asked: "${turn.userMessage}"');
        buffer.writeln('You answered: "${turn.agentResponse}"');
      }
      buffer.writeln('=== END PREVIOUS ===');
    }

    buffer.writeln('\n=== NEW USER QUESTION (answer THIS only) ===');
    buffer.writeln('User: "$command"');
    buffer.writeln('\nCRITICAL: Answer ONLY the NEW question above. Do NOT re-answer previous questions. Return ONLY a JSON object.');

    return buffer.toString();
  }

  // ══════════════════════════════════════════════
  //  CONVERSATION MEMORY
  // ══════════════════════════════════════════════
  void _addToHistory(String userMsg, String agentResponse, String action) {
    _conversationHistory.add(ConversationTurn(
      userMessage: userMsg,
      agentResponse: agentResponse,
      action: action,
      timestamp: DateTime.now(),
    ));

    // Keep only last N turns
    while (_conversationHistory.length > _maxHistoryTurns) {
      _conversationHistory.removeAt(0);
    }
  }

  void clearHistory() {
    _conversationHistory.clear();
    notifyListeners();
  }

  // ══════════════════════════════════════════════
  //  FOLLOW-UP MODE
  // ══════════════════════════════════════════════
  void _enterFollowUpMode() {
    _followUpMode = true;
    _followUpTimer?.cancel();
    
    // CRITICAL: Wait for TTS to fully finish before opening mic.
    // This prevents the agent from hearing its own speech as a new question.
    if (_agentEnabled && _followUpMode) {
      // Check if TTS is still speaking — wait for it
      if (_isTtsSpeaking) {
        debugPrint('[Aura Agent] TTS still speaking, delaying follow-up listen...');
        // Poll until TTS finishes (max 10 seconds)
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
          if (!_isTtsSpeaking || timer.tick > 33 || _isDisposed) {
            timer.cancel();
            if (!_isDisposed && _followUpMode) {
              _startFollowUpListening();
            }
          }
        });
      } else {
        _startFollowUpListening();
      }
    }
  }

  /// Actually start the follow-up listening session (called after TTS finishes)
  void _startFollowUpListening() {
    if (!_agentEnabled || _isDisposed) return;
    
    _setState(AgentState.listening);
    _currentStatusText = "Anything else?";
    notifyListeners();
    
    _speechToText.listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase().trim();
          
          // SELF-ECHO CHECK: Reject if this is the agent hearing itself
          if (_isSelfEcho(words)) {
            debugPrint('[Aura Agent] 🔇 Ignoring self-echo in follow-up: "$words"');
            return;
          }
          
          // Update UI real-time
          _lastUserTranscript = result.recognizedWords;
          notifyListeners();

          // Instantly execute offline commands
          final offlineMatch = OfflineCommandMatcher.tryMatch(words);
          if (offlineMatch.confidence >= 0.75) {
            debugPrint('[Aura Agent] ⚡ Direct follow-up offline command matched: ${offlineMatch.action}');
            _speechToText.stop();
            _followUpMode = false;
            _followUpTimer?.cancel();
            _onCommandReceived(words);
            return;
          }

          if (result.finalResult) {
            _followUpMode = false;
            _followUpTimer?.cancel();
            
            if (words.isNotEmpty && words.length > 2) {
              // User has a follow-up command
              _onCommandReceived(words);
            } else {
              // No follow-up, go back to passive
              _setState(AgentState.resting);
              _currentStatusText = "Resting";
              notifyListeners();
              _startPassiveListening();
            }
          }
        },
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 10),
        cancelOnError: false,
        partialResults: true,
        listenMode: stt.ListenMode.confirmation,
        localeId: 'en_US',
        onDevice: _offlineMode,
      ).catchError((e) {
        debugPrint('[Vision Agent] Follow-up listen error: $e');
        _followUpMode = false;
        _setState(AgentState.resting);
        _startPassiveListening();
      });
  }

  // ══════════════════════════════════════════════
  //  TTS (Text-to-Speech)
  // ══════════════════════════════════════════════
  /// Speak text. If awaitCompletion is true, waits until TTS finishes.
  Future<void> speak(String text, {String language = 'en', bool awaitCompletion = false}) async {
    if (_isDisposed || !_ttsInitialized || text.trim().isEmpty) return;

    try {
      // 1. CRITICAL Echo Cancellation: Stop microphone so STT doesn't hear TTS
      _isTransitioning = true;
      await _speechToText.cancel();
      await _speechToText.stop();
      _isTransitioning = false;

      // Handle language mapping
      String ttsLang = "en-US";
      if (language.startsWith('ur')) {
        ttsLang = "ur-PK";
      } else if (language.startsWith('hi')) {
        ttsLang = "hi-IN";
      }
      
      await _flutterTts.setLanguage(ttsLang);

      // Cancel any pending completer before stopping
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
      _speakCompleter = null;
      await _flutterTts.stop(); // Stop any ongoing speech

      _isTtsSpeaking = true;
      // Store for self-echo detection
      _lastSpokenTextForEcho = text;
      _lastSpeakTime = DateTime.now();
      
      // Fallback timeout to prevent Android TTS completion bugs from locking the mic forever
      int estimatedMs = (text.length * 70) + 1500;
      Timer(Duration(milliseconds: estimatedMs), () {
        if (_isTtsSpeaking && !_isDisposed) {
          debugPrint('[Vision TTS] Force resetting _isTtsSpeaking after $estimatedMs ms');
          _isTtsSpeaking = false;
          // CRITICAL: Also restart passive listening since the completion handler never fired
          if (_state == AgentState.resting && _agentEnabled) {
            _startPassiveListening();
          }
        }
      });

      if (awaitCompletion) {
        _speakCompleter = Completer<void>();
        await _flutterTts.speak(text);
        // Wait for completion with timeout
        await _speakCompleter?.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('[Vision TTS] Speak timeout — continuing');
          },
        );
      } else {
        await _flutterTts.speak(text);
      }
    } catch (e) {
      debugPrint('[Vision TTS] Speak error: $e');
      _speakCompleter = null;
      _isTtsSpeaking = false;
    }
  }

  /// Get the last thing Vision said (for repeat command)
  String? get lastSpokenText {
    if (_conversationHistory.isNotEmpty) {
      return _conversationHistory.last.agentResponse;
    }
    return null;
  }

  // ══════════════════════════════════════════════
  //  SETTINGS
  // ══════════════════════════════════════════════
  void toggleAgent(bool value) async {
    _agentEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agent_enabled', value);

    if (value) {
      _setState(AgentState.resting);
      if (_sttInitialized) {
        _startPassiveListening();
      }
      speak("Aura assistant is now active. Say 'Hey Aura' to get started.", awaitCompletion: false);
    } else {
      _speechToText.stop();
      _followUpTimer?.cancel();
      _passiveRestartTimer?.cancel();
      _flutterTts.stop();
      _setState(AgentState.disabled);
    }

    notifyListeners();
  }

  void toggleOfflineMode(bool value) async {
    _offlineMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vision_offline_mode', value);
    
    if (value) {
      speak("Offline mode enabled.", awaitCompletion: false);
    } else {
      speak("Online mode enabled.", awaitCompletion: false);
    }
    
    notifyListeners();
  }

  /// Save Gemini API key
  Future<void> setApiKey(String key) async {
    _geminiApiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key);
    // Key is sent to Python backend on each request — no local model to reinit
    speak('API key updated. Vision is ready.', awaitCompletion: false);
  }

  /// Save Azure API key
  Future<void> setAzureApiKey(String key) async {
    _azureApiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('azure_api_key', key);
    speak('Azure API key updated. Vision is ready.', awaitCompletion: false);
  }

  /// Update Backend URL (useful for demoing on physical devices)
  Future<void> setBackendUrl(String url) async {
    // Basic cleanup: remove trailing slash
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    _backendUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vision_backend_url', url);
    notifyListeners();
  }

  // ══════════════════════════════════════════════
  //  INTENT EMITTER (for ActionRouter)
  // ══════════════════════════════════════════════
  Map<String, dynamic>? _lastIntent;
  Map<String, dynamic>? get consumeLastIntent {
    final intent = _lastIntent;
    _lastIntent = null;
    return intent;
  }


  // ══════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════
  void _setState(AgentState newState) {
    _state = newState;
    _currentStatusText = switch (newState) {
      AgentState.resting   => "Resting",
      AgentState.waking    => "Heard you!",
      AgentState.listening => "Listening...",
      AgentState.thinking  => "Thinking...",
      AgentState.speaking  => "Speaking...",
      AgentState.executing => "On it!",
      AgentState.error     => "Error",
      AgentState.disabled  => "Disabled",
    };
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _passiveRestartTimer?.cancel();
    _followUpTimer?.cancel();
    _shakeSubscription?.cancel();
    _speechToText.stop();
    _flutterTts.stop();
    if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
      _speakCompleter!.complete();
    }
    super.dispose();
  }
}
