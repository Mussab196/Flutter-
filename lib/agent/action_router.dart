import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/sos_provider.dart';
import '../providers/ocr_provider.dart';
import '../providers/app_provider.dart';
import '../providers/live_vision_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/auth_provider.dart';
import '../main.dart'; // To get rootNavigatorKey
import 'agent_provider.dart';
import 'agent_skills.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

/// ActionRouter — Executes parsed intents from the Vision agent.
/// 
/// Supports 14 action types for full Jarvis-level control.
class ActionRouter {
  ActionRouter._();

  /// Master dispatcher — routes intent to the correct handler.
  static Future<void> executeAction(BuildContext context, Map<String, dynamic> intent) async {
    final String action = (intent['action']?.toString() ?? '').toLowerCase().trim();
    final String target = (intent['target']?.toString() ?? '').toLowerCase().trim();

    debugPrint('[ActionRouter] Executing: action="$action" target="$target"');

    switch (action) {
      case 'navigate':
      case 'open':
      case 'go':
      case 'go_to':
        _handleNavigation(context, target);
        break;
      case 'trigger':
      case 'emergency':
        await _handleTrigger(context, target);
        break;
      case 'call':
        await _handleCall(context, target);
        break;
      case 'read':
        await _handleRead(context, target);
        break;
      case 'toggle':
        await _handleToggle(context, target);
        break;
      case 'status':
        await _handleStatus(context, target);
        break;
      case 'repeat':
        _handleRepeat(context);
        break;
      case 'remember':
        await _handleRemember(context, target);
        break;
      case 'recall':
        await _handleRecall(context, target);
        break;
      case 'volume':
        await _handleVolume(context, target);
        break;
      case 'describe':
        await _handleDescribe(context);
        break;
      case 'math':
        _handleMath(context, target);
        break;
      case 'currency':
        await _handleCurrency(context);
        break;
      case 'greet':
        _handleGreet(context);
        break;
      case 'where_am_i':
        await _handleWhereAmI(context);
        break;
      case 'read_medicine':
        await _handleMedicineReader(context);
        break;
      case 'read_document':
        await _handleRead(context, 'document');
        break;
      case 'scene_memory':
        _handleSceneMemory(context);
        break;
      case 'guide_to':
        _handleGuideTo(context, target);
        break;
      case 'save_location':
        _handleSaveLocation(context, target);
        break;
      case 'stop_navigation':
        _handleStopNavigation(context);
        break;
      case 'inform':
        // Inform is speech-only — already handled by AgentProvider
        break;
      case 'screen_action':
        await _handleScreenAction(context, target);
        break;
      default:
        debugPrint('[ActionRouter] Unknown action: "$action"');
    }
  }

  // ═══════════════════════════════════════════
  //  PHYSICAL NAVIGATION (Guide To / Save)
  // ═══════════════════════════════════════════
  static void _handleGuideTo(BuildContext context, String target) {
    if (target.isEmpty) return;
    
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final isReallyAuthenticated = firebaseUser != null && !firebaseUser.isAnonymous;
    if (!isReallyAuthenticated) {
      final agent = Provider.of<AgentProvider>(context, listen: false);
      agent.speak("Please log in first to use this feature.");
      return;
    }

    final navProvider = Provider.of<NavigationProvider>(context, listen: false);
    navProvider.navigateToSaved(target);
    
    // Also push the navigation screen so the user can see/hear the UI
    final navContext = rootNavigatorKey.currentContext ?? context;
    if (navContext.mounted) {
      navContext.go('/navigation');
    }
  }

  static void _handleSaveLocation(BuildContext context, String target) {
    if (target.isEmpty) return;
    
    final navProvider = Provider.of<NavigationProvider>(context, listen: false);
    navProvider.saveCurrentLocation(target);
  }

  static void _handleStopNavigation(BuildContext context) {
    final navProvider = Provider.of<NavigationProvider>(context, listen: false);
    if (navProvider.navMode == NavMode.guidedRoute) {
      navProvider.stopRoute();
    }
  }

  // ═══════════════════════════════════════════
  //  NAVIGATE
  // ═══════════════════════════════════════════
  static void _handleNavigation(BuildContext context, String target) {
    final routeMap = <String, String>{
      // Most specific first
      'add_face':          '/add-face',
      'add face':          '/add-face',
      'new person':        '/add-face',
      'save face':         '/add-face',
      'register face':     '/add-face',
      // Then less specific
      'face_recognition':  '/face-recognition',
      'face recognition':  '/face-recognition',
      'face':              '/face-recognition',
      'recognition':       '/face-recognition',
      'recognize':         '/face-recognition',
      'person':            '/face-recognition',
      'people':            '/face-recognition',
      // Text/OCR
      'text_reader':       '/ocr-reader',
      'text reader':       '/ocr-reader',
      'read text':         '/ocr-reader',
      'text':              '/ocr-reader',
      'ocr':               '/ocr-reader',
      'reader':            '/ocr-reader',
      // Vision/Camera
      'live_vision':       '/live-vision',
      'live vision':       '/live-vision',
      'camera':            '/live-vision',
      'object':            '/live-vision',
      'objects':           '/live-vision',
      'detect':            '/live-vision',
      'see':               '/live-vision',
      // Navigation
      'navigation':        '/navigation',
      'navigate':          '/navigation',
      'walk':              '/navigation',
      'direction':         '/navigation',
      'map':               '/navigation',
      'ghar':              '/navigation',  // Urdu: home/go home
      // SOS
      'sos':               '/sos',
      'emergency':         '/sos',
      'help':              '/sos',
      // Settings
      'settings':          '/settings',
      'setting':           '/settings',
      'preferences':       '/settings',
      // Chat
      'chat':              '/vision-chat',
      'vision chat':       '/vision-chat',
      'talk':              '/vision-chat',
      'converse':          '/vision-chat',
      // Home
      'home':              '/home',
      'main':              '/home',
      'dashboard':         '/home',
      // Back
      'back':              'back',
    };

    // Exact match
    if (routeMap.containsKey(target)) {
      _navigateTo(context, routeMap[target]!);
      return;
    }

    // Contains match
    for (final entry in routeMap.entries) {
      if (target.contains(entry.key)) {
        _navigateTo(context, entry.value);
        return;
      }
    }

    debugPrint('[ActionRouter] Navigation target not recognized: "$target"');
  }

  static DateTime _lastNavTime = DateTime.fromMillisecondsSinceEpoch(0);
  static String _lastNavRoute = '';

  static void _navigateTo(BuildContext context, String route) {
    if (!context.mounted) return;
    
    final agent = Provider.of<AgentProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final isReallyAuthenticated = firebaseUser != null && !firebaseUser.isAnonymous;

    // Auth Guard - Prevent navigating if not logged in
    if (!isReallyAuthenticated && route != '/login' && route != '/signup' && route != '/onboarding' && route != '/splash') {
      agent.speak("Please log in first to use this feature.");
      return;
    }
    
    // Handle back specifically
    if (route == 'back') {
      // If already on home, tell the user
      if (agent.currentScreenRoute == '/home') {
        agent.speak("You are already on the home screen.");
        return;
      }
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        try {
          if (navContext.canPop()) {
            navContext.pop();
          } else {
            navContext.go('/home');
          }
        } catch (e) {
          debugPrint('[ActionRouter] Error going back: $e');
        }
        agent.updateCurrentScreen('/home', 'Home');
      }
      return;
    }

    // Prevent navigating to the screen we are already on!
    if (agent.currentScreenRoute == route) {
      debugPrint('[ActionRouter] Already on route: $route');
      agent.speak("You are already on the ${routeToName(route)} screen.");
      return;
    }

    final now = DateTime.now();
    if (route == _lastNavRoute && now.difference(_lastNavTime).inSeconds < 3) {
      debugPrint('[ActionRouter] Blocked duplicate navigation to $route');
      return;
    }
    
    _lastNavTime = now;
    _lastNavRoute = route;

    final previousRoute = agent.currentScreenRoute;
    agent.updateCurrentScreen(route, routeToName(route));
    
    final navContext = rootNavigatorKey.currentContext;
    if (navContext != null && navContext.mounted) {
      try {
        navContext.go(route);
      } catch (e) {
        debugPrint('[ActionRouter] Error navigating to $route: $e');
      }
    } else {
      debugPrint('[ActionRouter] Navigator context is not available for $route');
    }
  }

  static String routeToName(String route) {
    return switch (route) {
      '/home'             => 'Home',
      '/live-vision'      => 'Live Vision Camera',
      '/ocr-reader'       => 'Text Reader',
      '/face-recognition' => 'Face Recognition',
      '/add-face'         => 'Add New Face',
      '/navigation'       => 'Navigation',
      '/sos'              => 'Emergency SOS',
      '/settings'         => 'Settings',
      _                   => 'Unknown',
    };
  }

  // ═══════════════════════════════════════════
  //  TRIGGER
  // ═══════════════════════════════════════════
  static Future<void> _handleTrigger(BuildContext context, String target) async {
    if (!context.mounted) return;
    final navContext = rootNavigatorKey.currentContext ?? context;
    
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final isReallyAuthenticated = firebaseUser != null && !firebaseUser.isAnonymous;

    if (target.contains('sos') || target.contains('emergency') || target.contains('help')) {
      final sosProvider = Provider.of<SosProvider>(context, listen: false);
      sosProvider.autoTrigger = true;
      if (navContext.mounted) navContext.push('/sos'); // SOS allowed without login
    } else if (target.contains('describe') || target.contains('scene')) {
      if (!isReallyAuthenticated) {
        final agent = Provider.of<AgentProvider>(context, listen: false);
        agent.speak("Please log in first to use this feature.");
        return;
      }
      if (navContext.mounted) navContext.push('/live-vision');
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!context.mounted) return;
      final visionProvider = Provider.of<LiveVisionProvider>(context, listen: false);
      await visionProvider.announceScene();
    } else if (target.contains('flash')) {
      final result = await AgentSkills.toggleFlashlight();
      if (context.mounted) {
        Provider.of<AgentProvider>(context, listen: false).speak(result);
      }
    } else if (target == 'capture' || target == 'read_aloud') {
      final agent = Provider.of<AgentProvider>(context, listen: false);
      final currentRoute = ModalRoute.of(navContext)?.settings.name ?? '';
      final agentRoute = agent.currentScreenRoute;
      final agentName = agent.currentScreenName.toLowerCase();
      
      if (currentRoute == '/ocr-reader' || 
          agentRoute == '/ocr-reader' || 
          agentRoute.contains('ocr') || 
          agentName.contains('text reader')) {
        final ocrProvider = Provider.of<OcrProvider>(context, listen: false);
        if (target == 'capture') {
          agent.speak("Capturing document...", awaitCompletion: false);
          final text = await ocrProvider.captureAndRecognize();
          if (text.isEmpty && context.mounted) {
            agent.speak("I couldn't detect any text.");
          }
        } else {
          // read aloud
          if (ocrProvider.recognizedText.isNotEmpty) {
            await ocrProvider.speakText(ocrProvider.recognizedText);
          } else {
            agent.speak("Capturing document to read aloud...", awaitCompletion: false);
            final text = await ocrProvider.captureAndRecognize();
            if (text.isNotEmpty) {
              await ocrProvider.speakText(text);
            } else if (context.mounted) {
              agent.speak("I couldn't detect any text.");
            }
          }
        }
      } else {
        if (context.mounted) {
          agent.speak("Capture is not available on this screen.");
        }
      }
    }
  }

  // ═══════════════════════════════════════════
  //  CALL
  // ═══════════════════════════════════════════
  static Future<void> _handleCall(BuildContext context, String target) async {
    if (!context.mounted) return;
    final sosProvider = Provider.of<SosProvider>(context, listen: false);
    final contacts = sosProvider.contacts;
    String? phoneToCall;

    for (var contact in contacts) {
      if (target.contains(contact.name.toLowerCase()) ||
          contact.name.toLowerCase().contains(target)) {
        phoneToCall = contact.phone;
        break;
      }
    }

    if (phoneToCall != null) {
      final Uri launchUri = Uri(scheme: 'tel', path: phoneToCall);
      try {
        if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
      } catch (e) {
        debugPrint('[ActionRouter] Call failed: $e');
      }
    } else if (context.mounted) {
      Provider.of<AgentProvider>(context, listen: false)
          .speak("I couldn't find $target in your emergency contacts.");
    }
  }

  // ═══════════════════════════════════════════
  //  READ (OCR)
  // ═══════════════════════════════════════════
  static Future<void> _handleRead(BuildContext context, String target) async {
    if (!context.mounted) return;

    if (target.contains('clipboard')) {
      final result = await AgentSkills.readClipboard();
      if (context.mounted) {
        Provider.of<AgentProvider>(context, listen: false).speak(result);
      }
    } else {
      // Default: camera OCR
      context.push('/ocr-reader');
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!context.mounted) return;
      final ocrProvider = Provider.of<OcrProvider>(context, listen: false);
      final text = await ocrProvider.captureAndRecognize();
      if (text.isNotEmpty) {
        await ocrProvider.speakText(text);
      } else if (context.mounted) {
        Provider.of<AgentProvider>(context, listen: false)
            .speak("I couldn't detect any text. Try holding the camera steady.");
      }
    }
  }

  // ═══════════════════════════════════════════
  //  TOGGLE
  // ═══════════════════════════════════════════
  static Future<void> _handleToggle(BuildContext context, String target) async {
    if (!context.mounted) return;

    if (target.contains('theme') || target.contains('dark') || target.contains('light')) {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      appProvider.toggleDarkMode();
    } else if (target.contains('voice') || target.contains('sound') || target.contains('speaker')) {
      final visionProvider = Provider.of<LiveVisionProvider>(context, listen: false);
      visionProvider.toggleSpeaker();
    } else if (target.contains('flash_on')) {
      final result = await AgentSkills.setFlashlight(true);
      if (context.mounted) {
        Provider.of<AgentProvider>(context, listen: false).speak(result);
      }
    } else if (target.contains('flash_off')) {
      final result = await AgentSkills.setFlashlight(false);
      if (context.mounted) {
        Provider.of<AgentProvider>(context, listen: false).speak(result);
      }
    } else if (target.contains('flash')) {
      final result = await AgentSkills.toggleFlashlight();
      if (context.mounted) {
        Provider.of<AgentProvider>(context, listen: false).speak(result);
      }
    }
  }

  // ═══════════════════════════════════════════
  //  STATUS (time, battery, general)
  // ═══════════════════════════════════════════
  static Future<void> _handleStatus(BuildContext context, String target) async {
    if (!context.mounted) return;
    final agent = Provider.of<AgentProvider>(context, listen: false);

    if (target.contains('time') || target.contains('date') || target.contains('waqt')) {
      agent.speak(AgentSkills.getTimeReport());
    } else if (target.contains('battery') || target.contains('charge')) {
      final result = await AgentSkills.getBatteryStatus();
      agent.speak(result);
    } else {
      // General status: time + battery
      final time = AgentSkills.getTimeReport();
      final battery = await AgentSkills.getBatteryStatus();
      agent.speak("$time $battery");
    }
  }

  // ═══════════════════════════════════════════
  //  REPEAT
  // ═══════════════════════════════════════════
  static void _handleRepeat(BuildContext context) {
    if (!context.mounted) return;
    final agent = Provider.of<AgentProvider>(context, listen: false);
    final lastText = agent.lastSpokenText;
    if (lastText != null && lastText.isNotEmpty) {
      agent.speak(lastText);
    } else {
      agent.speak("I haven't said anything yet.");
    }
  }

  // ═══════════════════════════════════════════
  //  REMEMBER (save reminder)
  // ═══════════════════════════════════════════
  static Future<void> _handleRemember(BuildContext context, String target) async {
    if (!context.mounted) return;
    final result = await AgentSkills.saveReminder(target);
    if (context.mounted) {
      Provider.of<AgentProvider>(context, listen: false).speak(result);
    }
  }

  // ═══════════════════════════════════════════
  //  RECALL (retrieve reminders)
  // ═══════════════════════════════════════════
  static Future<void> _handleRecall(BuildContext context, String target) async {
    if (!context.mounted) return;
    String result;
    if (target.contains('clear') || target.contains('delete') || target.contains('remove')) {
      result = await AgentSkills.clearReminders();
    } else {
      result = await AgentSkills.getReminders();
    }
    if (context.mounted) {
      Provider.of<AgentProvider>(context, listen: false).speak(result);
    }
  }

  // ═══════════════════════════════════════════
  //  VOLUME
  // ═══════════════════════════════════════════
  static Future<void> _handleVolume(BuildContext context, String target) async {
    if (!context.mounted) return;
    final result = await AgentSkills.adjustVolume(target);
    if (context.mounted) {
      Provider.of<AgentProvider>(context, listen: false).speak(result);
    }
  }

  // ═══════════════════════════════════════════
  //  DESCRIBE (Camera + Gemini Vision AI)
  // ═══════════════════════════════════════════
  static Future<void> _handleDescribe(BuildContext context) async {
    if (!context.mounted) return;
    final agent = Provider.of<AgentProvider>(context, listen: false);
    
    agent.speak("Looking around for you...", awaitCompletion: false);
    
    final description = await AgentSkills.describeScene(
      geminiApiKey: agent.geminiApiKey,
    );
    
    if (context.mounted) {
      agent.speak(description);
    }
  }

  // ═══════════════════════════════════════════
  //  💵 CURRENCY DETECTION
  // ═══════════════════════════════════════════
  static Future<void> _handleCurrency(BuildContext context) async {
    if (!context.mounted) return;
    final agent = Provider.of<AgentProvider>(context, listen: false);
    
    agent.speak("Scanning the currency note. Please hold steady...", awaitCompletion: false);
    
    final result = await AgentSkills.detectCurrency(
      geminiApiKey: agent.geminiApiKey,
      azureApiKey: agent.azureApiKey,
    );
    
    if (context.mounted) {
      agent.speak(result);
    }
  }

  // ═══════════════════════════════════════════
  //  MATH
  // ═══════════════════════════════════════════
  static void _handleMath(BuildContext context, String target) {
    if (!context.mounted) return;
    final agent = Provider.of<AgentProvider>(context, listen: false);
    final answer = AgentSkills.tryMathAnswer(target);
    if (answer != null) {
      agent.speak(answer);
    } else {
      agent.speak("I couldn't solve that. Try saying something like: 25 plus 30.");
    }
  }

  // ═══════════════════════════════════════════
  //  GREET
  // ═══════════════════════════════════════════
  static void _handleGreet(BuildContext context) {
    if (!context.mounted) return;
    final agent = Provider.of<AgentProvider>(context, listen: false);
    agent.speak(AgentSkills.getSmartGreeting(''));
  }

  // ═══════════════════════════════════════════
  //  🌍 WHERE AM I (GPS + Geocode)
  // ═══════════════════════════════════════════
  static Future<void> _handleWhereAmI(BuildContext context) async {
    if (!context.mounted) return;
    // Speech already started by offline matcher ("Let me check your location...")
    // The skill fills the actual response via _executeOfflineMatch
  }

  // ═══════════════════════════════════════════
  //  💊 MEDICINE READER
  // ═══════════════════════════════════════════
  static Future<void> _handleMedicineReader(BuildContext context) async {
    if (!context.mounted) return;
    // Speech already started by offline matcher
    // The skill fills the actual response
  }

  // ═══════════════════════════════════════════
  //  🧠 SCENE MEMORY
  // ═══════════════════════════════════════════
  static void _handleSceneMemory(BuildContext context) {
    if (!context.mounted) return;
    // Speech already filled by the skill in _executeOfflineMatch
  }

  // ═══════════════════════════════════════════
  //  📱 SCREEN CONTEXT ACTIONS
  // ═══════════════════════════════════════════
  static Future<void> _handleScreenAction(BuildContext context, String target) async {
    final navContext = rootNavigatorKey.currentContext ?? context;
    if (!navContext.mounted) return;

    final agent = Provider.of<AgentProvider>(navContext, listen: false);
    final currentRoute = ModalRoute.of(navContext)?.settings.name ?? '';
    final agentRoute = agent.currentScreenRoute;
    final agentName = agent.currentScreenName.toLowerCase();

    final isOnOcrScreen = currentRoute == '/ocr-reader' || 
                          agentRoute == '/ocr-reader' || 
                          agentRoute.contains('ocr') || 
                          agentName.contains('text reader');

    if (target == 'capture') {
      if (isOnOcrScreen) {
        final ocrProvider = Provider.of<OcrProvider>(navContext, listen: false);
        if (ocrProvider.isCameraInitialized) {
          final text = await ocrProvider.captureAndRecognize();
          if (text.isNotEmpty) {
            await ocrProvider.speakText(text);
          }
        }
      } else {
        agent.speak("You are not on the Read Text screen.");
      }
    } else if (target == 'read_aloud') {
      if (isOnOcrScreen) {
        final ocrProvider = Provider.of<OcrProvider>(navContext, listen: false);
        if (ocrProvider.isCameraInitialized) {
          if (ocrProvider.recognizedText.isNotEmpty) {
            await ocrProvider.speakRecognizedText();
          } else {
            final text = await ocrProvider.captureAndRecognize();
            if (text.isNotEmpty) {
              await ocrProvider.speakText(text);
            }
          }
        }
      } else {
        agent.speak("You are not on the Read Text screen.");
      }
    } else if (target == 'stop') {
      if (isOnOcrScreen) {
        final ocrProvider = Provider.of<OcrProvider>(navContext, listen: false);
        await ocrProvider.stopSpeaking();
      } else {
        // Not on OCR screen — just confirm we stopped
        agent.speak("Stopped.");
      }
    }
  }
}
