/// OfflineCommandMatcher — Production-grade local-first voice command engine.
///
/// This runs entirely on-device with ZERO network dependency. It intercepts
/// voice commands BEFORE they reach the Python LangGraph backend, providing:
///  1. Instant response for navigation & device control (~0ms vs ~2-3s online)
///  2. Full offline functionality for ALL features
///  3. Reduced backend load and API costs
///
/// Architecture:
///   User speaks → STT → OfflineCommandMatcher.tryMatch()
///     ├── Match found (score ≥ threshold) → Execute locally, skip backend
///     └── No match → Provide helpful fallback OR forward to cloud if online
///
/// Matching strategy:
///   1. Normalize input (lowercase, trim, remove filler words)
///   2. Try each category in priority order
///   3. Score using weighted keyword matching with fuzzy tolerance
///   4. Apply confidence boosters for multiple keyword hits
///   5. Return best match above threshold, or helpful fallback
library;

import 'dart:math' as math;

class OfflineCommandMatcher {
  OfflineCommandMatcher._();

  // ═══════════════════════════════════════════════
  //  PUBLIC API
  // ═══════════════════════════════════════════════

  /// Result of an offline match attempt.
  /// NEVER returns null — always provides at least a helpful fallback.
  /// Use `result.confidence` to decide whether to use it:
  ///   - >= 0.75: High confidence, use directly
  ///   - >= 0.50: Medium confidence, use if offline
  ///   - < 0.50:  Low confidence / fallback, forward to cloud if available
  static OfflineMatchResult tryMatch(String rawCommand) {
    if (rawCommand.trim().isEmpty) {
      return const OfflineMatchResult(
        action: 'inform',
        target: 'empty',
        speech: "I didn't hear anything. Please try again.",
        confidence: 0.0,
      );
    }

    final command = _normalize(rawCommand);
    final words = command.split(RegExp(r'\s+'));

    // Try matchers in priority order (most critical first)
    OfflineMatchResult? result;

    // 1. SOS / Emergency — highest priority, must always work offline
    result = _matchEmergency(command, words);
    if (result != null) return result;

    // 2. Device controls — flashlight, volume, battery, time
    //    MUST run before navigation to prevent 'turn on flash light' → 'go back'
    result = _matchDeviceControl(command, words);
    if (result != null) return result;

    // 3. Navigation — "open X", "go to X", screen names
    result = _matchNavigation(command, words);
    if (result != null) return result;

    // 3.5 Contextual Screen Actions (capture, read aloud)
    result = _matchScreenAction(command, words);
    if (result != null) return result;

    // 4. Utility — reminders, clipboard, math, repeat
    result = _matchUtility(command, words);
    if (result != null) return result;

    // 5. Greetings and simple queries
    result = _matchGreeting(command, words);
    if (result != null) return result;

    // 6. Where Am I (GPS + reverse geocode)
    result = _matchWhereAmI(command, words);
    if (result != null) return result;

    // 7. Medicine / Label Reader
    result = _matchMedicineReader(command, words);
    if (result != null) return result;

    // 8. Scene Memory ("what did you see?", "was there a door?")
    result = _matchSceneMemory(command, words);
    if (result != null) return result;

    // 9. Navigation Routing (Guide To, Save Location, Stop Navigation)
    result = _matchSaveLocation(command, words);
    if (result != null) return result;

    result = _matchStopNavigation(command, words);
    if (result != null) return result;

    result = _matchGuideTo(command, words);
    if (result != null) return result;

    // 10. CATCH-ALL — Always give a helpful response
    return _buildFallbackResponse(command);
  }

  // ═══════════════════════════════════════════════
  //  TEXT NORMALIZATION
  // ═══════════════════════════════════════════════

  /// Normalize input: lowercase, trim, remove filler words, stem common suffixes
  static String _normalize(String raw) {
    String text = raw.toLowerCase().trim();

    // Remove common STT artifacts and filler words
    final fillers = [
      'please', 'can you', 'could you', 'would you', 'i want to',
      'i need to', 'i want you to', 'just', 'actually', 'like',
      'umm', 'uhh', 'uh', 'um', 'hmm', 'okay so', 'so',
      'kindly', 'mujhe', 'mera', 'mere', 'karo na', 'zara',
      'hey aura', 'hello aura', 'hi aura', 'okay aura',
      'ok aura',
    ];

    for (final filler in fillers) {
      text = text.replaceAll(filler, ' ');
    }

    // Collapse multiple spaces
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Disable stemming because it breaks exact matching for words like "navigation", "recognition", "setting", etc.
    // text = _stem(text);

    return text;
  }

  /// Simple English stemming — handles common verb suffixes
  static String _stem(String text) {
    final words = text.split(' ');
    final stemmed = words.map((word) {
      if (word.length < 5) return word; // Don't stem short words

      // Common suffixes to strip
      if (word.endsWith('ing') && word.length > 5) {
        return word.substring(0, word.length - 3);
      }
      if (word.endsWith('tion') && word.length > 6) {
        return word.substring(0, word.length - 4);
      }
      if (word.endsWith('ment') && word.length > 6) {
        return word.substring(0, word.length - 4);
      }
      if (word.endsWith('ness') && word.length > 6) {
        return word.substring(0, word.length - 4);
      }
      if (word.endsWith('ous') && word.length > 5) {
        return word.substring(0, word.length - 3);
      }
      if (word.endsWith('ize') && word.length > 5) {
        return word.substring(0, word.length - 3);
      }
      if (word.endsWith('ise') && word.length > 5) {
        return word.substring(0, word.length - 3);
      }
      return word;
    }).toList();
    return stemmed.join(' ');
  }

  // ═══════════════════════════════════════════════
  //  FUZZY MATCHING ENGINE
  // ═══════════════════════════════════════════════

  /// Score how well a command matches a set of keyword groups.
  /// Returns 0.0 to 1.0 where:
  ///   - Each matched keyword adds its weight
  ///   - Multiple matches from different groups boost confidence
  ///   - Fuzzy matching (edit distance ≤ 2) counts at 70% weight
  static double _score(String command, List<String> words, List<_KeywordGroup> groups) {
    double totalWeight = 0.0;
    int groupsMatched = 0;
    final double maxPossibleWeight = groups.fold(0.0, (sum, g) => sum + g.weight);

    for (final group in groups) {
      bool groupHit = false;
      for (final keyword in group.keywords) {
        // Strategy 1: Exact substring match (fastest)
        if (command.contains(keyword)) {
          totalWeight += group.weight;
          groupHit = true;
          break;
        }

        // Strategy 2: Fuzzy match each word against multi-word keywords
        final keywordWords = keyword.split(' ');
        if (keywordWords.length == 1) {
          // Single-word keyword: fuzzy match against each input word
          for (final word in words) {
            int maxDist = keyword.length <= 4 ? 1 : 2;
            if (keyword == 'sos') maxDist = 0;
            if (_levenshtein(word, keyword) <= maxDist && word.length > 2) {
              totalWeight += group.weight * 0.7; // 70% weight for fuzzy
              groupHit = true;
              break;
            }
          }
        }
        if (groupHit) break;
      }
      if (groupHit) groupsMatched++;
    }

    if (maxPossibleWeight == 0) return 0.0;

    // Base score from keyword weights
    double score = totalWeight / maxPossibleWeight;

    // Bonus for matching multiple keyword groups (indicates stronger intent)
    if (groupsMatched >= 2) score = math.min(1.0, score + 0.1);
    if (groupsMatched >= 3) score = math.min(1.0, score + 0.05);

    return score;
  }

  /// Levenshtein distance for fuzzy matching
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
        curr[j] = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
            .reduce((a, b) => a < b ? a : b);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[t.length];
  }

  /// Check if command contains any keyword (exact substring)
  static bool _containsAny(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  /// Check if any word in the command fuzzy-matches a keyword
  static bool _fuzzyContains(List<String> words, List<String> keywords) {
    for (final word in words) {
      if (word.length < 3) continue;
      for (final kw in keywords) {
        if (kw.contains(' ')) continue; // Skip multi-word for fuzzy
        
        // Dynamic distance based on word length to prevent short word false positives (like 'sos')
        int maxDist = 2;
        if (kw.length <= 4) maxDist = 1;
        if (kw == 'sos') maxDist = 0; // Never fuzzy match 'sos'
        
        if (_levenshtein(word, kw) <= maxDist) return true;
      }
    }
    return false;
  }

  // ═══════════════════════════════════════════════
  //  🚨 EMERGENCY (Always offline, always instant)
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchEmergency(String cmd, List<String> words) {
    // If the user specifically says "open", they just want navigation, not trigger.
    if (cmd.contains('open sos') || cmd.contains('sos screen')) {
      return null; // Let the navigation matcher handle it
    }

    const emergencyKeywords = [
      // English
      'emergency', 'help me', 'danger', 'send sos', 'trigger sos',
      'call for help', 'i need help', 'send alert', 'emergency alert',
      'panic', 'rescue', 'save me', 'urgent help', 'distress',
      'call police', 'call ambulance', 'accident', 'help',
      // Urdu/Hindi
      'madad', 'bachao', 'madad chahiye', 'mujhe madad', 'khatara',
      'emergency hai', 'alert bhejo', 'police bulao', 'ambulance bulao',
      // Common mishearings
      'assess', 'assess us', 'as oh as', 'send sms', 'trigger sms', 'help please', 'sauce'
    ];

    if (_containsAny(cmd, emergencyKeywords) ||
        _fuzzyContains(words, ['emergency', 'danger', 'rescue', 'bachao', 'madad']) ||
        (words.contains('sos') && !cmd.contains('open'))) {
      return const OfflineMatchResult(
        action: 'trigger',
        target: 'sos',
        speech: 'Triggering emergency SOS now!',
        confidence: 0.99,
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════
  //  🧭 NAVIGATION (Screen routing)
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchNavigation(String cmd, List<String> words) {
    // Navigation intent prefixes (boosts confidence)
    final hasNavPrefix = _containsAny(cmd, [
      'open', 'go to', 'take me to', 'show', 'launch', 'start',
      'navigate to', 'switch to', 'chalao', 'kholo', 'kholna',
      'dikhaao', 'dikhao', 'le chalo', 'chalo',
    ]);
    final double prefixBoost = hasNavPrefix ? 0.12 : 0.0;

    // ─── Exact OCR / Text Reader (Highest Priority in Navigation) ───
    if (_containsAny(cmd, ['read text', 'text reader', 'open read text', 'read text screen', 'start text reader', 'text reader screen', 'red text', 'open red text'])) {
      return const OfflineMatchResult(
        action: 'navigate',
        target: 'text_reader',
        speech: 'Opening Text Reader.',
        confidence: 0.99,
      );
    }

    // ─── Live Vision / Camera ───
    if (_containsAny(cmd, [
      'open live vision', 'live vision screen', 'start live vision', 'live camera',
      'live vision', 'live screen', 'open live screen', 'open camera', 'vision screen',
      'open live', 'start camera', 'live cam', 'camera screen',
      // Phonetic mishearings
      'live vison', 'live vizon', 'life vision', 'life vison',
      'open live vison', 'live vision kholo', 'camera kholo',
    ])) {
      return const OfflineMatchResult(
        action: 'navigate',
        target: 'live_vision',
        speech: 'Opening Live Vision.',
        confidence: 0.99,
      );
    }
    final visionScore = _score(cmd, words, [
      _KeywordGroup(0.5, ['live vision', 'camera', 'object detection', 'detect objects',
        'see around', 'surroundings', 'live camera', 'vision camera',
        'open camera', 'start camera', 'start detect', 'what is around',
        'kya hai samne', 'objects around', 'dekho', 'dekhao', 'camera kholo', 'live vision kholo',
        'object', 'detect', 'vision', 'camara', 'kemra', 'kemara']),
      _KeywordGroup(0.3, ['camera', 'objects', 'surrounding', 'samne', 'vision', 'kemra']),
    ]);
    if (visionScore + prefixBoost >= 0.40) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'live_vision',
        speech: 'Opening Live Vision camera.',
        confidence: math.min(0.99, visionScore + prefixBoost + 0.45),
      );
    }

    // ─── OCR / Text Reader ───
    if (_containsAny(cmd, ['open read text', 'read text screen', 'start text reader', 'text reader screen'])) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'text_reader',
        speech: 'Opening Text Reader.',
        confidence: 0.99,
      );
    }
    final ocrScore = _score(cmd, words, [
      _KeywordGroup(0.5, ['read text', 'text reader', 'scan text', 'read document',
        'padh ke sunao', 'text padho', 'document read', 'read this', 'text reader kholo',
        'ocr', 'red text', 'red document']),
      _KeywordGroup(0.3, ['read', 'text', 'document', 'padho', 'reed', 'scan']),
    ]);
    if (ocrScore + prefixBoost >= 0.40) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'text_reader',
        speech: 'Opening Text Reader.',
        confidence: math.min(0.99, ocrScore + prefixBoost + 0.45),
      );
    }

    // ─── Add Face ───
    if (_containsAny(cmd, ['open add face', 'add face screen', 'start add face', 'new person screen', 'open save face'])) {
      return const OfflineMatchResult(
        action: 'navigate',
        target: 'add_face',
        speech: 'Opening Add Face screen.',
        confidence: 0.99,
      );
    }
    final addFaceScore = _score(cmd, words, [
      _KeywordGroup(0.5, ['add face', 'new person', 'save face', 'register face',
        'naya face', 'naya chehra', 'chehra save', 'shakal save', 'add person',
        'head face', 'at face', 'add phase', 'safe face', 'safe phase']),
      _KeywordGroup(0.3, ['add', 'save', 'new', 'naya', 'chehra', 'safe']),
    ]);
    if (addFaceScore + prefixBoost >= 0.40) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'add_face',
        speech: 'Opening Add Face screen.',
        confidence: math.min(0.99, addFaceScore + prefixBoost + 0.45),
      );
    }

    // ─── Face Recognition ───
    if (_containsAny(cmd, ['open face recognition', 'face recognition screen', 'start face recognition'])) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'face_recognition',
        speech: 'Opening Face Recognition.',
        confidence: 0.99,
      );
    }
    final faceScore = _score(cmd, words, [
      _KeywordGroup(0.5, ['face recognition', 'recognize face', 'face scanner', 'face detect',
        'who is this', 'identify person', 'face read', 'face lock', 'face kholo', 'face recognition kholo',
        'shakal', 'pehchan', 'face', 'phase', 'space recognition', 'phase recognition', 'face reg', 'face rack']),
      _KeywordGroup(0.3, ['face', 'person', 'who', 'identify', 'shakal', 'phase']),
    ]);
    if (faceScore + prefixBoost >= 0.40) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'face_recognition',
        speech: 'Opening Face Recognition.',
        confidence: math.min(0.99, faceScore + prefixBoost + 0.45),
      );
    }

    // ─── Chat / Assistant ───
    if (_containsAny(cmd, ['open chat', 'chat screen', 'open vision chat', 'chat kholo'])) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'chat',
        speech: 'Opening Vision Chat.',
        confidence: 0.99,
      );
    }
    final chatScore = _score(cmd, words, [
      _KeywordGroup(0.5, ['chat', 'vision chat', 'assistant', 'talk to aura', 'open chat', 'chat kholo', 'baat karni hai', 'baat karo']),
      _KeywordGroup(0.3, ['talk', 'converse', 'messages', 'message', 'baat']),
    ]);
    if (chatScore + prefixBoost >= 0.40) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'chat',
        speech: 'Opening Chat.',
        confidence: math.min(0.99, chatScore + prefixBoost + 0.45),
      );
    }

    // ─── Navigation / Map ───
    if (_containsAny(cmd, ['open navigation', 'navigation screen', 'gps navigation', 'gps screen', 'start navigation'])) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'navigation',
        speech: 'Opening GPS Navigation.',
        confidence: 0.99,
      );
    }
    final navScore = _score(cmd, words, [
      _KeywordGroup(0.5, ['navigation', 'map', 'directions', 'walk mode', 'walking mode',
        'ghar le chalo', 'rasta', 'rasta dikhao', 'navigate me', 'guide me',
        'start navigation', 'open navigation', 'direction dikhao',
        'walking guide', 'compass', 'gps']),
      _KeywordGroup(0.3, ['navigate', 'direction', 'walk', 'rasta', 'compass', 'gps', 'map']),
    ]);
    // Avoid false match with "navigate to X" (which is a prefix for other screens)
    final isNavigateToSomething = cmd.contains('navigate to ') && !cmd.contains('navigate to saved');
    if (navScore + prefixBoost >= 0.40 && !isNavigateToSomething) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'navigation',
        speech: 'Opening Navigation.',
        confidence: math.min(0.99, navScore + prefixBoost + 0.40),
      );
    }

    // ─── SOS Screen (not trigger, just open) ───
    if (_containsAny(cmd, [
      'sos screen', 'emergency screen', 'emergency contacts',
      'show contacts', 'open sos', 'open emergency',
      'emergency page', 'sos page',
      // Phonetic mishearings:
      'open sms', 'sms screen', 'open source', 'source screen', 'sauce screen', 'open sauce'
    ])) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'sos',
        speech: 'Opening Emergency SOS screen.',
        confidence: 0.95 + prefixBoost,
      );
    }

    // ─── Home ───
    final homeScore = _score(cmd, words, [
      _KeywordGroup(0.6, ['home', 'home screen', 'main screen', 'dashboard',
        'go back home', 'back to home', 'ghar', 'main page', 'home page']),
      _KeywordGroup(0.2, ['home', 'main', 'dashboard']),
    ]);
    if (homeScore + prefixBoost >= 0.40) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'home',
        speech: 'Going to home screen.',
        confidence: math.min(0.99, homeScore + prefixBoost + 0.45),
      );
    }

    // ─── Back ───
    // STRICT: Only match exact phrases to prevent false positives
    if (_containsAny(cmd, ['go back', 'piche jao', 'wapas jao', 'wapis jao']) ||
        cmd == 'back' || cmd == 'piche' || cmd == 'wapas' || cmd == 'wapis') {
      return const OfflineMatchResult(
        action: 'navigate',
        target: 'back',
        speech: 'Going back.',
        confidence: 0.95,
      );
    }

    // ─── Settings ───
    final settingsScore = _score(cmd, words, [
      _KeywordGroup(0.6, ['settings', 'setting', 'preferences', 'options',
        'configuration', 'config', 'setup', 'api key', 'change settings']),
      _KeywordGroup(0.2, ['setting', 'config', 'preference', 'option']),
    ]);
    if (settingsScore + prefixBoost >= 0.40) {
      return OfflineMatchResult(
        action: 'navigate',
        target: 'settings',
        speech: 'Opening Settings.',
        confidence: math.min(0.99, settingsScore + prefixBoost + 0.45),
      );
    }





    return null;
  }

  // ═══════════════════════════════════════════════
  //  🔧 DEVICE CONTROLS
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchDeviceControl(String cmd, List<String> words) {
    // ─── Flashlight On ───
    if (_containsAny(cmd, [
      'turn on light', 'light on', 'torch on', 'flash on', 'flash light on', 'flashlight on',
      'turn on flashlight', 'turn on flash light', 'turn on torch',
      'flush light on', 'flesh light on', 'turn on flush light', 'turn on flesh light',
      'roshni on', 'light jalao', 'torch jalao'
    ])) {
      return const OfflineMatchResult(
        action: 'toggle',
        target: 'flash_on',
        speech: '',
        confidence: 0.96,
        useSkill: 'flashlight',
      );
    }

    // ─── Flashlight Off ───
    if (_containsAny(cmd, [
      'turn off light', 'light off', 'torch off', 'flash off', 'flash light off', 'flashlight off',
      'turn off flashlight', 'turn off flash light', 'turn off torch',
      'flush light off', 'flesh light off', 'turn off flush light', 'turn off flesh light',
      'roshni off', 'light band karo', 'torch band karo', 'light bujhao'
    ])) {
      return const OfflineMatchResult(
        action: 'toggle',
        target: 'flash_off',
        speech: '',
        confidence: 0.96,
        useSkill: 'flashlight',
      );
    }

    // ─── Flashlight Toggle / Generic ───
    // STRICT: Only match when user says just the word "flashlight"/"torch" etc.
    // NOT when it appears in a longer sentence (e.g. TTS echo "flashlight turned on")
    if (words.length <= 4 && (
        _containsAny(cmd, [
          'toggle flashlight', 'toggle torch', 'light karo', 'roshni',
        ]) || 
        // Exact standalone match (entire command IS the flashlight word)
        ['flashlight', 'torch', 'flash light', 'flush light', 'flesh light'].contains(cmd)
    )) {
      return const OfflineMatchResult(
        action: 'toggle',
        target: 'flash',
        speech: '',
        confidence: 0.95,
        useSkill: 'flashlight',
      );
    }

    // ─── Volume Up ───
    if (_containsAny(cmd, [
      'volume up', 'louder', 'increase volume', 'awaz barha',
      'volume barha', 'turn up', 'raise volume', 'awaz zyada',
      'volume increase', 'sound up', 'volume badhao',
    ])) {
      return const OfflineMatchResult(
        action: 'volume', target: 'up',
        speech: 'Increasing volume.',
        confidence: 0.96,
      );
    }

    // ─── Volume Down ───
    if (_containsAny(cmd, [
      'volume down', 'lower', 'decrease volume', 'quieter', 'awaz kam',
      'volume kam', 'turn down', 'reduce volume', 'softer',
      'volume decrease', 'sound down', 'volume kamm',
    ])) {
      return const OfflineMatchResult(
        action: 'volume', target: 'down',
        speech: 'Decreasing volume.',
        confidence: 0.96,
      );
    }

    // ─── Mute ───
    if (_containsAny(cmd, [
      'mute', 'silent', 'volume off', 'volume mute', 'khamosh',
      'chup', 'silence', 'shut up', 'stop talking', 'be quiet',
      'awaz band', 'band karo awaz',
    ])) {
      return const OfflineMatchResult(
        action: 'volume', target: 'mute',
        speech: 'Muting volume.',
        confidence: 0.95,
      );
    }

    // ─── Max Volume ───
    if (_containsAny(cmd, [
      'max volume', 'full volume', 'volume max', 'volume full',
      'puri awaz', 'maximum volume', 'loudest',
    ])) {
      return const OfflineMatchResult(
        action: 'volume', target: 'max',
        speech: 'Volume set to maximum.',
        confidence: 0.95,
      );
    }

    // ─── Time / Date ───
    if (_containsAny(cmd, [
      'what time', 'what is the time', 'tell me the time', 'tell me time',
      'what day', 'kya waqt', 'waqt batao', 'time kya hai',
      'what is today', 'today date', 'aaj kya tarikh', 'kitne baje',
      'current time', 'abhi time', 'kya date hai', 'din kya hai',
      'today is', 'tell time', 'check time', 'whats the time', 'whats the date',
      'current date'
    ])) {
      return const OfflineMatchResult(
        action: 'status', target: 'time',
        speech: '', // Will be filled by AgentSkills.getTimeReport()
        confidence: 0.94,
        useSkill: 'time',
      );
    }

    // ─── Battery ───
    if (_containsAny(cmd, [
      'battery level', 'how much battery', 'battery status', 'charge level', 
      'kitni battery', 'battery kitni hai', 'power level', 'battery check',
      'charge kitni', 'battery percentage', 'kya charge hai', 'check battery',
      'battery', 'charge'
    ])) {
      return const OfflineMatchResult(
        action: 'status', target: 'battery',
        speech: '', // Will be filled by AgentSkills.getBatteryStatus()
        confidence: 0.95,
        useSkill: 'battery',
      );
    }

    // ─── Theme Toggle ───
    if (_containsAny(cmd, [
      'dark mode', 'light mode', 'toggle theme', 'change theme',
      'switch theme', 'dark theme', 'light theme', 'night mode',
      'day mode', 'theme change', 'mode change',
    ])) {
      return const OfflineMatchResult(
        action: 'toggle', target: 'theme',
        speech: 'Toggling theme.',
        confidence: 0.94,
      );
    }

    // ─── Describe Scene ───
    if (_containsAny(cmd, [
      'describe', 'what do you see', 'what is in front',
      'what is around me', 'look around', 'scene', 'describe scene',
      'samne kya hai', 'batao kya dikh raha', 'kya hai yahan',
      'tell me what you see', 'describe surrounding', 'what around',
      'kya dikh raha', 'kya nazar aa raha', 'scene describe',
    ])) {
      return const OfflineMatchResult(
        action: 'describe', target: 'scene',
        speech: 'Looking around for you...',
        confidence: 0.92,
      );
    }

    // ─── Currency Detection ───
    if (_containsAny(cmd, [
      'detect currency', 'identify money', 'identify currency', 'read currency',
      'note check', 'paisa check', 'how much money', 'what note is this',
      'check note', 'scan money', 'scan note', 'paisa pehchano',
      'kitne ka note', 'note batao', 'paisa batao', 'currency scan',
      'read money', 'scan currency', 'data currency', 'data current see', 'detector and see',
      // Phonetic mishearings
      'detect crunch', 'detect cruncy', 'scan crunch', 'scan cruncy', 'scan corns',
      'identify crunch', 'crancy', 'cranchi', 'karanchi', 'mani', 'manny'
    ])) {
      return const OfflineMatchResult(
        action: 'currency', target: 'note',
        speech: 'Scanning the currency note. Please hold steady...',
        confidence: 0.95,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════
  //  🛠 UTILITY & IN-SCREEN ACTIONS
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchUtility(String cmd, List<String> words) {
    // ─── Screen Specific: Capture / Read Aloud ───
    if (_containsAny(cmd, ['capture', 'click', 'take picture', 'snap', 'scan it', 'scan now'])) {
      return const OfflineMatchResult(
        action: 'trigger', target: 'capture',
        speech: '', // ActionRouter handles speech
        confidence: 0.90,
      );
    }
    
    if (_containsAny(cmd, ['read aloud', 'start reading', 'speak text'])) {
      return const OfflineMatchResult(
        action: 'trigger', target: 'read_aloud',
        speech: '',
        confidence: 0.90,
      );
    }
    // ─── Repeat ───
    if (_containsAny(cmd, [
      'repeat', 'say again', 'repeat that', 'what did you say',
      'dobara bolo', 'phir se bolo', 'come again', 'pardon',
      'once more', 'say that again', 'repeat please', 'again',
      'ek bar phir', 'dubara',
    ])) {
      return const OfflineMatchResult(
        action: 'repeat', target: 'last',
        speech: '',
        confidence: 0.95,
      );
    }

    // ─── Stop / Cancel / Go Back ───
    // STRICT: Only match exact phrases to prevent false positives with flashlight/other commands
    if (_containsAny(cmd, [
      'go back', 'never mind', 'nevermind', 'band karo', 'rok do', 'wapas jao',
      'ruk jao', 'that is enough',
    ]) || ['stop', 'cancel', 'close', 'exit', 'quit', 'back', 'bas', 'enough'].contains(cmd)) {
      return const OfflineMatchResult(
        action: 'navigate', target: 'home',
        speech: 'Going back.',
        confidence: 0.88,
      );
    }

    // ─── Read Clipboard ───
    if (_containsAny(cmd, [
      'read clipboard', 'clipboard', 'paste', 'what is copied',
      'read copied text', 'copied', 'clipboard read', 'copy kya hai',
    ])) {
      return const OfflineMatchResult(
        action: 'read', target: 'clipboard',
        speech: '',
        confidence: 0.94,
        useSkill: 'clipboard',
      );
    }

    // ─── Remember ───
    if (cmd.startsWith('remember') || cmd.startsWith('yaad rakh') ||
        cmd.startsWith('save reminder') || cmd.startsWith('note down') ||
        cmd.startsWith('yaad rakho') || cmd.startsWith('save note')) {
      String content = cmd
          .replaceFirst(RegExp(r'^(remember|yaad rakh|yaad rakho|save reminder|note down|save note)\s*'), '')
          .trim();
      if (content.isEmpty) content = cmd;

      return OfflineMatchResult(
        action: 'remember', target: content,
        speech: '',
        confidence: 0.93,
        useSkill: 'remember',
      );
    }

    // ─── Recall Reminders ───
    if (_containsAny(cmd, [
      'my reminders', 'show reminders', 'what did i save',
      'recall', 'recall reminders', 'list reminders',
      'kya yaad kiya tha', 'mere reminders', 'show notes',
      'my notes', 'reminders dikhao', 'what did i remember',
    ])) {
      return const OfflineMatchResult(
        action: 'recall', target: 'all',
        speech: '',
        confidence: 0.93,
        useSkill: 'recall',
      );
    }

    // ─── Clear Reminders ───
    if (_containsAny(cmd, [
      'clear reminders', 'delete reminders', 'remove reminders',
      'clear all reminders', 'erase reminders', 'delete all notes',
      'clear notes', 'reminders delete', 'sab delete karo',
    ])) {
      return const OfflineMatchResult(
        action: 'recall', target: 'clear',
        speech: '',
        confidence: 0.94,
        useSkill: 'recall_clear',
      );
    }

    // ─── Math ───
    final mathPattern = RegExp(r'(\d+)\s*([\+\-\*\/xX×÷]|plus|minus|times|divided by|multiply|into)\s*(\d+)');
    if (mathPattern.hasMatch(cmd)) {
      return OfflineMatchResult(
        action: 'math', target: cmd,
        speech: '',
        confidence: 0.96,
        useSkill: 'math',
      );
    }

    // ─── What can you do? / Help ───
    if (_containsAny(cmd, [
      'what can you do', 'help', 'commands', 'features', 'abilities',
      'tum kya kar sakti ho', 'kya kya kar sakti ho', 'how to use',
      'tutorial', 'instructions', 'guide', 'what you do',
    ])) {
      return const OfflineMatchResult(
        action: 'inform', target: 'capabilities',
        speech: 'I can help you with many things! Say "open camera" for live vision, '
            '"read text" to scan documents, "recognize face" to identify people, '
            '"navigate" for GPS guidance, "emergency" for SOS, '
            '"what time" or "battery" for device info, '
            'and "flashlight" to toggle your torch. '
            'What would you like to do?',
        confidence: 0.92,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════
  //  👋 GREETINGS
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchGreeting(String cmd, List<String> words) {
    if (_containsAny(cmd, [
      'hello', 'hi', 'hey', 'good morning', 'good afternoon',
      'good evening', 'good night', 'salam', 'assalam',
      'how are you', 'kaise ho', 'kya haal', 'sup', 'hola',
      'namaste', 'adaab', 'salaam',
    ])) {
      // Only match if the command is primarily a greeting (not "hello open settings")
      if (words.length <= 5) {
        return const OfflineMatchResult(
          action: 'greet', target: 'user',
          speech: '',
          confidence: 0.88,
          useSkill: 'greet',
        );
      }
    }

    // ─── Thank you ───
    if (_containsAny(cmd, [
      'thank you', 'thanks', 'shukriya', 'dhanyavad', 'thank',
      'appreciate', 'good job', 'well done', 'great work',
    ])) {
      return const OfflineMatchResult(
        action: 'inform', target: 'thanks',
        speech: "You're welcome! I'm always here to help. Just say Hey Aura anytime.",
        confidence: 0.90,
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════
  //  🌍 WHERE AM I (GPS + Reverse Geocode)
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchWhereAmI(String cmd, List<String> words) {
    if (_containsAny(cmd, [
      'where am i', 'where are we', 'location', 'my location',
      'current location', 'gps', 'address', 'which street',
      'which road', 'which area', 'surroundings',
      // Urdu/Hindi
      'kahan hun', 'kahan hai', 'kahan hoon', 'jagah', 'pata batao',
      'location batao', 'konsi road', 'konsa rasta', 'kahan par',
    ])) {
      return const OfflineMatchResult(
        action: 'where_am_i', target: 'location',
        speech: 'Let me check your location...',
        confidence: 0.90,
        useSkill: 'where_am_i',
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════
  //  💊 MEDICINE / LABEL READER
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchMedicineReader(String cmd, List<String> words) {
    if (_containsAny(cmd, [
      'medicine', 'tablet', 'pill', 'capsule', 'syrup',
      'label', 'read label', 'read medicine', 'scan medicine',
      'medicine name', 'dosage', 'expiry',
      'read this', 'what is this medicine', 'which medicine',
      // Urdu/Hindi
      'dawai', 'goli', 'dawa', 'medicine batao', 'dawai parho',
      'label parho', 'kya dawai hai', 'medicine parhna',
    ])) {
      return const OfflineMatchResult(
        action: 'read_medicine', target: 'medicine',
        speech: 'Scanning the label. Please hold the medicine steady...',
        confidence: 0.88,
        useSkill: 'read_medicine',
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════
  //  🧠 SCENE MEMORY ("what did you see?")
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchSceneMemory(String cmd, List<String> words) {
    if (_containsAny(cmd, [
      'what did you see', 'what was there', 'was there a door',
      'was there a person', 'was there a car', 'was there a chair',
      'recall scene', 'previous scene', 'last scene', 'remember scene',
      'what you saw', 'tell me again what you saw',
      'scene memory', 'what was around', 'what was near',
      // Urdu/Hindi
      'kya dekha tha', 'kya tha wahan', 'darwaza tha', 'batao kya dekha',
      'pehle kya tha', 'dobara batao', 'scene yaad karo',
    ])) {
      return const OfflineMatchResult(
        action: 'scene_memory', target: 'recall',
        speech: '',
        confidence: 0.85,
        useSkill: 'scene_memory',
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════
  //  🗺️ GUIDE TO ("take me to...", "guide me to...")
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchGuideTo(String cmd, List<String> words) {
    // Check for guide-to pattern with a destination
    if (_containsAny(cmd, [
      'guide me', 'take me to', 'navigate to', 'go to',
      'show me the way', 'lead me', 'bring me to', 'walk me to',
      'guide to', 'directions to',
      // Urdu/Hindi
      'le chalo', 'le jao', 'rasta batao', 'chalo', 'mujhe le chalo',
    ])) {
      // Extract destination from command
      String destination = cmd;
      for (final prefix in [
        'guide me to ', 'take me to ', 'navigate to ', 'go to ',
        'show me the way to ', 'lead me to ', 'bring me to ', 'walk me to ',
        'guide to ', 'directions to ', 'le chalo ', 'rasta batao ',
        'guide me ', 'take me ', 'lead me ', 'walk me ',
      ]) {
        if (destination.contains(prefix)) {
          destination = destination.substring(destination.indexOf(prefix) + prefix.length).trim();
          break;
        }
      }

      // Check for common saved location names
      if (_containsAny(destination, ['home', 'ghar', 'house', 'work', 'office', 'daftar', 'kitchen', 'bedroom'])) {
        return OfflineMatchResult(
          action: 'guide_to', target: destination,
          speech: 'Starting navigation to $destination.',
          confidence: 0.85,
        );
      }

      // Generic guide — forward to navigation
      if (destination.isNotEmpty && destination.length > 2) {
        return OfflineMatchResult(
          action: 'guide_to', target: destination,
          speech: 'Looking for $destination. Opening navigation.',
          confidence: 0.75,
        );
      }
    }
    return null;
  }

  // ═══════════════════════════════════════════════
  //  📍 SAVE LOCATION
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchSaveLocation(String cmd, List<String> words) {
    if (_containsAny(cmd, [
      'save this location as', 'mark this spot as', 'save location as',
      'remember this place as', 'save this place as', 'save here as',
      'is jagah ko save karo', 'is location ko save karo',
    ])) {
      String locationName = cmd;
      for (final prefix in [
        'save this location as ', 'mark this spot as ', 'save location as ',
        'remember this place as ', 'save this place as ', 'save here as ',
        'is jagah ko save karo as ', 'is location ko save karo as '
      ]) {
        if (locationName.contains(prefix)) {
          locationName = locationName.substring(locationName.indexOf(prefix) + prefix.length).trim();
          break;
        }
      }

      if (locationName.isNotEmpty && locationName.length > 2) {
        return OfflineMatchResult(
          action: 'save_location', target: locationName,
          speech: 'Saving your current location as $locationName.',
          confidence: 0.90,
        );
      }
    }
    return null;
  }

  // ═══════════════════════════════════════════════
  //  🛑 STOP NAVIGATION
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchStopNavigation(String cmd, List<String> words) {
    if (_containsAny(cmd, [
      'stop navigation', 'cancel route', 'exit navigation', 'cancel navigation',
      'end navigation', 'stop guiding', 'navigation band karo', 'rasta band karo',
    ])) {
      return const OfflineMatchResult(
        action: 'stop_navigation', target: 'none',
        speech: 'Navigation stopped. Switching to free walk mode.',
        confidence: 0.90,
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════
  //  📱 SCREEN CONTEXT ACTIONS
  // ═══════════════════════════════════════════════
  static OfflineMatchResult? _matchScreenAction(String cmd, List<String> words) {
    // ─── Capture (Read Text Screen) ───
    if (_containsAny(cmd, ['capture', 'take picture', 'scan now', 'read now', 'capture now'])) {
      return const OfflineMatchResult(
        action: 'screen_action',
        target: 'capture',
        speech: '',
        confidence: 0.95,
      );
    }

    // ─── Read Aloud (Read Text Screen) ───
    if (_containsAny(cmd, ['read aloud', 'read out loud', 'speak text', 'sunao', 'padh ke sunao', 'awaz me padho'])) {
      return const OfflineMatchResult(
        action: 'screen_action',
        target: 'read_aloud',
        speech: '',
        confidence: 0.95,
      );
    }
    // ─── Stop Reading (Read Text Screen) ───
    if (_containsAny(cmd, ['stop reading', 'stop text', 'chup karo', 'bas karo', 'stop playback']) || 
        ['stop', 'ruk jao', 'bas', 'chup'].contains(cmd)) {
      return const OfflineMatchResult(
        action: 'screen_action',
        target: 'stop',
        speech: '',
        confidence: 0.95,
      );
    }

    // "Add face" is already handled globally by _matchNavigation.
    return null;
  }

  // ═══════════════════════════════════════════════
  //  🔄 CATCH-ALL FALLBACK (Never leave user hanging)
  // ═══════════════════════════════════════════════
  static OfflineMatchResult _buildFallbackResponse(String command) {
    return OfflineMatchResult(
      action: 'inform',
      target: 'fallback',
      speech: "I'm not sure what you mean. You can say things like: "
          '"open camera", "read text", "recognize face", '
          '"navigate", "what time", "battery status", '
          '"where am I", "read medicine", '
          'or "flashlight". What would you like to do?',
      confidence: 0.20,
    );
  }
}

/// Weighted keyword group for scoring
class _KeywordGroup {
  final double weight; // 0.0 to 1.0
  final List<String> keywords;

  const _KeywordGroup(this.weight, this.keywords);
}

/// The result of a match attempt.
class OfflineMatchResult {
  final String action;
  final String target;
  final String speech;
  final double confidence; // 0.0 to 1.0
  final String? useSkill; // If set, AgentProvider should run this skill to fill speech

  const OfflineMatchResult({
    required this.action,
    required this.target,
    required this.speech,
    required this.confidence,
    this.useSkill,
  });

  /// Convert to the same intent format the online agent returns,
  /// so ActionRouter can consume it identically.
  Map<String, dynamic> toIntent() => {
    'action': action,
    'target': target,
    'speech': speech,
    'language': 'en',
    '_offline': true, // Marker so we know this was handled locally
  };

  @override
  String toString() => 'OfflineMatch(action=$action, target=$target, conf=${(confidence * 100).toStringAsFixed(0)}%)';
}
