import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:battery_plus/battery_plus.dart' as battery_plus;
import 'package:torch_light/torch_light.dart';

/// AgentSkills — All the cool Jarvis-level capabilities Vision can do.
/// 
/// These are standalone utility methods that ActionRouter calls.
/// Each skill is self-contained and does NOT depend on UI.
class AgentSkills {
  AgentSkills._();

  // ══════════════════════════════════════════════
  //  📸 DESCRIBE SCENE (Gemini Vision + Camera)
  // ══════════════════════════════════════════════
  /// Takes a photo with the camera and asks Gemini Vision to describe it
  /// for a blind user. Returns the description string.
  static Future<String> describeScene({
    required String geminiApiKey,
  }) async {
    CameraController? controller;
    try {
      // 1. Get available cameras
      final cameras = await availableCameras();
      if (cameras.isEmpty) return "I can't access the camera right now.";

      // 2. Init camera quickly at medium resolution (speed > quality here)
      controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();

      // 3. Capture image
      final XFile imageFile = await controller.takePicture();
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // 4. Dispose camera immediately (free resource)
      await controller.dispose();
      controller = null;

      // 5. Send to Gemini Vision for description
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: geminiApiKey,
        generationConfig: GenerationConfig(
          temperature: 0.4,
          maxOutputTokens: 300,
        ),
        systemInstruction: Content.system(
          'You are a vision assistant for a BLIND person. '
          'Describe what you see in the image clearly, concisely, and helpfully. '
          'Focus on: people, obstacles, text/signs, objects, and spatial layout. '
          'Keep it under 3 sentences. Be specific: "a red car parked on your left" not "a vehicle". '
          'If you see text, read it out. If there are potential hazards, mention them FIRST.'
        ),
      );

      final response = await model.generateContent([
        Content.multi([
          TextPart('Describe this scene for a blind person. Be concise and helpful:'),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]).timeout(const Duration(seconds: 20));

      final result = response.text ?? "I captured an image but couldn't describe it.";
      _saveSceneToMemory(result); // Save for scene_memory recall
      return result;
    } catch (e) {
      debugPrint('[AgentSkills] describeScene error: $e');
      controller?.dispose();
      return "Sorry, I couldn't take a picture right now. $e";
    }
  }

  // ══════════════════════════════════════════════
  //  💵 CURRENCY DETECTION (Gemini Vision / Azure + Camera)
  // ══════════════════════════════════════════════
  /// Takes a photo and detects the currency value in it using Gemini/Azure.
  static Future<String> detectCurrency({
    required String geminiApiKey,
    required String azureApiKey,
  }) async {
    CameraController? controller;
    try {
      // 1. Get available cameras
      final cameras = await availableCameras();
      if (cameras.isEmpty) return "I can't access the camera right now.";

      // 2. Init camera quickly at medium resolution for fast capturing
      controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();

      // 3. Capture image
      final XFile imageFile = await controller.takePicture();
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // 4. Dispose camera immediately to free native resource
      await controller.dispose();
      controller = null;

      // 5. Prefer Gemini due to superior localized currency understanding (e.g. PKR/INR)
      if (geminiApiKey.isNotEmpty) {
        return await _detectCurrencyWithGemini(imageBytes, geminiApiKey);
      } else if (azureApiKey.isNotEmpty) {
        return await _detectCurrencyWithAzure(imageBytes, azureApiKey);
      } else {
        return "Please set your Gemini or Azure API Key in Settings first.";
      }
    } catch (e) {
      debugPrint('[AgentSkills] detectCurrency error: $e');
      controller?.dispose();
      return "Sorry, I couldn't scan the note. Please try again. Error: $e";
    }
  }

  static Future<String> _detectCurrencyWithGemini(Uint8List imageBytes, String apiKey) async {
    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1,
        maxOutputTokens: 100,
      ),
      systemInstruction: Content.system(
        'You are a currency detection assistant for a visually impaired user. '
        'Your sole job is to identify the currency note in the image. '
        'Identify: the currency denomination (e.g., 50, 100, 500, 1000, 5000, 10, 20), '
        'the currency country/name (e.g., Pakistani Rupees (PKR), Indian Rupees, US Dollars, etc.), '
        'and confirm the bill value. '
        'Keep your response extremely short, direct, and clear. E.g.: "It is a 500 Pakistani Rupee note." or "It looks like a 1000 Rupee note." '
        'If no currency is found, say: "I cannot see any currency note in this image. Please try again with better lighting."'
      ),
    );

    final response = await model.generateContent([
      Content.multi([
        TextPart('Identify the currency note in this image and say it aloud:'),
        DataPart('image/jpeg', imageBytes),
      ]),
    ]).timeout(const Duration(seconds: 15));

    return response.text ?? "I could not determine the currency.";
  }

  static Future<String> _detectCurrencyWithAzure(Uint8List imageBytes, String apiKey) async {
    try {
      final uri = Uri.parse('https://westus.api.cognitive.microsoft.com/vision/v3.2/analyze?visualFeatures=Description,Tags');
      final response = await http.post(
        uri,
        headers: {
          'Ocp-Apim-Subscription-Key': apiKey,
          'Content-Type': 'application/octet-stream',
        },
        body: imageBytes,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final description = data['description']?['captions']?[0]?['text'] as String?;
        
        if (description != null) {
          return "Azure describes this as: $description";
        }
        return "I scanned the note using Azure, but could not identify a specific denomination. Please use Gemini for better local currency recognition.";
      } else {
        return "Azure Vision API returned an error: ${response.statusCode}. Please verify your key and region endpoint.";
      }
    } catch (e) {
      return "Failed to analyze with Azure: $e";
    }
  }

  // ══════════════════════════════════════════════
  //  ⏰ TIME & DATE
  // ══════════════════════════════════════════════
  static String getTimeReport() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    
    // 12-hour format with AM/PM
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 
                        'July', 'August', 'September', 'October', 'November', 'December'];
    
    final dayName = dayNames[now.weekday - 1];
    final monthName = monthNames[now.month - 1];
    
    return "It's $displayHour:$minute $period, $dayName, $monthName ${now.day}, ${now.year}.";
  }

  static String getSmartGreeting(String userName) {
    final hour = DateTime.now().hour;
    String greeting;
    String extra;
    
    if (hour >= 5 && hour < 12) {
      greeting = 'Good morning';
      extra = 'Hope you had a good rest.';
    } else if (hour >= 12 && hour < 17) {
      greeting = 'Good afternoon';
      extra = 'How is your day going?';
    } else if (hour >= 17 && hour < 21) {
      greeting = 'Good evening';
      extra = "Let me know if you need anything.";
    } else {
      greeting = 'Hey there';
      extra = "It's quite late. Take care of yourself.";
    }
    
    final name = userName.isNotEmpty ? ', $userName' : '';
    return '$greeting$name! $extra';
  }

  // ══════════════════════════════════════════════
  //  🔋 BATTERY STATUS
  // ══════════════════════════════════════════════
  static Future<String> getBatteryStatus() async {
    try {
      final battery = battery_plus.Battery();
      final int batteryLevel = await battery.batteryLevel;
      
      if (batteryLevel <= 20) {
        return "Warning: Battery is low at $batteryLevel%. Please charge your device.";
      } else if (batteryLevel >= 90) {
        return "Battery is nearly full at $batteryLevel%.";
      } else {
        return "Your battery is at $batteryLevel%.";
      }
    } catch (e) {
      debugPrint('[AgentSkills] Battery status error: $e');
      return "I couldn't check the battery level right now.";
    }
  }

  // ══════════════════════════════════════════════
  //  🔊 VOLUME CONTROL
  // ══════════════════════════════════════════════
  static Future<String> adjustVolume(String direction) async {
    try {
      const platform = MethodChannel('com.aura/volume');
      
      if (direction.contains('up') || direction.contains('increase') || 
          direction.contains('louder') || direction.contains('barha')) {
        await platform.invokeMethod('volumeUp');
        return "Volume increased.";
      } else if (direction.contains('down') || direction.contains('decrease') || 
                 direction.contains('lower') || direction.contains('quiet') ||
                 direction.contains('kam')) {
        await platform.invokeMethod('volumeDown');
        return "Volume decreased.";
      } else if (direction.contains('max') || direction.contains('full')) {
        await platform.invokeMethod('volumeMax');
        return "Volume set to maximum.";      
      } else if (direction.contains('mute') || direction.contains('silent') || 
                 direction.contains('off')) {
        await platform.invokeMethod('volumeMute');
        return "Volume muted.";
      }
      
      return "Say volume up, down, max, or mute.";
    } catch (e) {
      debugPrint('[AgentSkills] Volume control error: $e');
      return "I couldn't change the volume. This feature needs the native module.";
    }
  }

  // ══════════════════════════════════════════════
  //  📝 REMINDERS / MEMORY
  // ══════════════════════════════════════════════
  static Future<String> saveReminder(String reminder) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList('vision_reminders') ?? [];
      
      final entry = jsonEncode({
        'text': reminder,
        'time': DateTime.now().toIso8601String(),
      });
      
      existing.add(entry);
      await prefs.setStringList('vision_reminders', existing);
      
      return "Got it! I'll remember that: $reminder";
    } catch (e) {
      return "Sorry, I couldn't save that reminder.";
    }
  }

  static Future<String> getReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList('vision_reminders') ?? [];
      
      if (existing.isEmpty) {
        return "You don't have any saved reminders.";
      }
      
      final buffer = StringBuffer("Here are your reminders: ");
      for (int i = 0; i < existing.length; i++) {
        final entry = jsonDecode(existing[i]);
        buffer.write("${i + 1}. ${entry['text']}. ");
      }
      
      return buffer.toString();
    } catch (e) {
      return "I couldn't retrieve your reminders.";
    }
  }

  static Future<String> clearReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('vision_reminders');
      return "All reminders cleared.";
    } catch (e) {
      return "I couldn't clear the reminders.";
    }
  }

  // ══════════════════════════════════════════════
  //  🔦 FLASHLIGHT
  // ══════════════════════════════════════════════
  static bool _flashlightOn = false;
  
  static Future<String> toggleFlashlight() async {
    try {
      bool isTorchAvailable = await TorchLight.isTorchAvailable();
      if (!isTorchAvailable) {
        return "Flashlight is not available on this device.";
      }

      if (_flashlightOn) {
        await TorchLight.disableTorch();
        _flashlightOn = false;
        return "Flashlight turned off.";
      } else {
        await TorchLight.enableTorch();
        _flashlightOn = true;
        return "Flashlight turned on.";
      }
    } catch (e) {
      debugPrint('[AgentSkills] Flashlight error: $e');
      return "I couldn't control the flashlight.";
    }
  }

  static Future<String> setFlashlight(bool turnOn) async {
    try {
      bool isTorchAvailable = await TorchLight.isTorchAvailable();
      if (!isTorchAvailable) {
        return "Flashlight is not available on this device.";
      }

      if (turnOn) {
        await TorchLight.enableTorch();
        _flashlightOn = true;
        return "Flashlight turned on.";
      } else {
        await TorchLight.disableTorch();
        _flashlightOn = false;
        return "Flashlight turned off.";
      }
    } catch (e) {
      debugPrint('[AgentSkills] Flashlight error: $e');
      return "I couldn't control the flashlight.";
    }
  }

  // ══════════════════════════════════════════════
  //  📋 CLIPBOARD
  // ══════════════════════════════════════════════
  static Future<String> readClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        return "From clipboard: ${data.text}";
      }
      return "The clipboard is empty.";
    } catch (e) {
      return "I couldn't read the clipboard.";
    }
  }

  // ══════════════════════════════════════════════
  //  🧮 QUICK MATH
  // ══════════════════════════════════════════════
  static String? tryMathAnswer(String query) {
    // Simple check if it's a math question
    final mathPattern = RegExp(r'(\d+)\s*([\+\-\*\/xX×÷]|plus|minus|times|divided by)\s*(\d+)');
    final match = mathPattern.firstMatch(query.toLowerCase());
    
    if (match == null) return null;
    
    final a = double.parse(match.group(1)!);
    final op = match.group(2)!.toLowerCase();
    final b = double.parse(match.group(3)!);
    
    double result;
    String opName;
    
    if (op == '+' || op == 'plus') {
      result = a + b;
      opName = 'plus';
    } else if (op == '-' || op == 'minus') {
      result = a - b;
      opName = 'minus';
    } else if (op == '*' || op == 'x' || op == '×' || op == 'times') {
      result = a * b;
      opName = 'times';
    } else if (op == '/' || op == '÷' || op == 'divided by') {
      if (b == 0) return "Can't divide by zero!";
      result = a / b;
      opName = 'divided by';
    } else {
      return null;
    }
    
    // Format result (remove .0 for whole numbers)
    final resultStr = result == result.roundToDouble() 
        ? result.toInt().toString() 
        : result.toStringAsFixed(2);
    
    return "${a.toInt()} $opName ${b.toInt()} equals $resultStr.";
  }

  // ══════════════════════════════════════════════
  //  🌍 WHERE AM I (GPS Reverse Geocode)
  // ══════════════════════════════════════════════
  /// Uses free Nominatim API (no key needed) to convert GPS to address.
  /// Combined with last obstacle data for a rich scene answer.
  static Future<String> whereAmI() async {
    try {
      // 1. Get current GPS position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));

      // 2. Reverse geocode via free Nominatim API
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?'
        'format=json&lat=${position.latitude}&lon=${position.longitude}'
        '&zoom=18&addressdetails=1'
      );
      
      final response = await http.get(
        url,
        headers: {'User-Agent': 'AuraApp/2.0'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return "You are at coordinates ${position.latitude.toStringAsFixed(4)}, "
               "${position.longitude.toStringAsFixed(4)}, but I couldn't get the street name.";
      }

      final data = jsonDecode(response.body);
      final address = data['address'] as Map<String, dynamic>? ?? {};

      // Build natural spoken address
      final parts = <String>[];
      final road = address['road'] ?? address['pedestrian'] ?? address['footway'];
      if (road != null) parts.add('on $road');
      
      final area = address['neighbourhood'] ?? address['suburb'] ?? address['quarter'];
      if (area != null) parts.add('in $area');
      
      final city = address['city'] ?? address['town'] ?? address['village'];
      if (city != null) parts.add(city);

      if (parts.isNotEmpty) {
        return "You are located ${parts.join(', ')}.";
      }
      
      final displayName = data['display_name'] ?? 'an unknown location';
      return "You are near $displayName.";
    } on TimeoutException {
      return "I couldn't get your location in time. Please make sure GPS is enabled.";
    } catch (e) {
      debugPrint('[AgentSkills] whereAmI error: $e');
      return "I couldn't determine your location right now. Please check that GPS is enabled.";
    }
  }

  // ══════════════════════════════════════════════
  //  💊 MEDICINE / LABEL READER (Gemini Vision)
  // ══════════════════════════════════════════════
  /// Takes a photo and identifies medicine labels, instructions, and warnings.
  static Future<String> detectMedicineLabel({
    required String geminiApiKey,
  }) async {
    CameraController? controller;
    try {
      if (geminiApiKey.isEmpty) {
        return "Please set your Gemini API Key in Settings first.";
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) return "I can't access the camera right now.";

      controller = CameraController(
        cameras.first,
        ResolutionPreset.high, // High res for small text on medicine labels
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();

      final XFile imageFile = await controller.takePicture();
      final Uint8List imageBytes = await imageFile.readAsBytes();

      await controller.dispose();
      controller = null;

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: geminiApiKey,
        generationConfig: GenerationConfig(
          temperature: 0.1,
          maxOutputTokens: 300,
        ),
        systemInstruction: Content.system(
          'You are a medicine label reader for a BLIND person. '
          'Your job is to identify the medicine/product in the image and read its label. '
          'Focus on: 1) Medicine NAME, 2) DOSAGE/strength (mg, ml), '
          '3) Key INSTRUCTIONS (how many times per day, before/after food), '
          '4) EXPIRY date if visible, 5) Any WARNINGS. '
          'Be concise and read in order of importance. '
          'If this is not a medicine, describe what the label says instead. '
          'If you cannot read the text, say so and suggest better lighting or angle.'
        ),
      );

      final response = await model.generateContent([
        Content.multi([
          TextPart('Read this medicine label or product label for a blind person. Be clear and concise:'),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]).timeout(const Duration(seconds: 15));

      return response.text ?? "I could not read the label.";
    } catch (e) {
      debugPrint('[AgentSkills] detectMedicineLabel error: $e');
      controller?.dispose();
      return "Sorry, I couldn't read the label. Please try again with better lighting.";
    }
  }

  // ══════════════════════════════════════════════
  //  🧠 SCENE MEMORY (Remember + Recall)
  // ══════════════════════════════════════════════
  /// Stores the last scene description for quick recall without API calls.
  static String? _lastSceneDescription;
  static DateTime? _lastSceneTime;

  /// Save a scene description (called after describeScene succeeds)
  static void _saveSceneToMemory(String description) {
    _lastSceneDescription = description;
    _lastSceneTime = DateTime.now();
  }

  /// Recall the last scene description
  static String recallLastScene() {
    if (_lastSceneDescription == null || _lastSceneTime == null) {
      return "I haven't described any scene yet. Say 'describe' or 'what do you see' first.";
    }

    final ago = DateTime.now().difference(_lastSceneTime!);
    String timeAgo;
    if (ago.inSeconds < 60) {
      timeAgo = '${ago.inSeconds} seconds ago';
    } else if (ago.inMinutes < 60) {
      timeAgo = '${ago.inMinutes} minutes ago';
    } else {
      timeAgo = '${ago.inHours} hours ago';
    }

    return "From $timeAgo: $_lastSceneDescription";
  }
}
