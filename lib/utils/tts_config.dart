import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Centralized TTS Configuration — Single source of truth for voice settings.
///
/// Ensures every provider in the app uses the same high-quality,
/// human-like voice configuration. Optimized for accessibility use-case
/// (visually impaired users) with warm, natural pacing.
class TtsConfig {
  TtsConfig._();

  // ═══════════════════════════════════════════════
  //  VOICE TUNING PARAMETERS
  // ═══════════════════════════════════════════════

  /// Speech rate: 0.0 (slowest) to 1.0 (fastest)
  /// 0.45 is slightly slower than normal conversation — gives
  /// blind users time to process information without sounding robotic.
  static const double speechRate = 0.45;

  /// Pitch: 0.5 (deep) to 2.0 (high)
  /// 1.05 is natural human pitch — avoids the "robot voice" feel.
  /// Keeping it close to 1.0 sounds most realistic.
  static const double pitch = 1.05;

  /// Volume: 0.0 to 1.0
  static const double volume = 1.0;

  /// Primary language / locale for the TTS engine
  static const String language = 'en-US';

  /// Preferred Android TTS engine — Google's engine has the most
  /// natural-sounding neural voices.
  static const String androidEngine = 'com.google.android.tts';

  // ═══════════════════════════════════════════════
  //  APPLY TO ANY FlutterTts INSTANCE
  // ═══════════════════════════════════════════════

  /// Apply the standard, human-like voice configuration to a FlutterTts instance.
  ///
  /// Call this once during `_initTts()` in any provider. This replaces
  /// all scattered setLanguage/setSpeechRate/setPitch/setVolume calls.
  ///
  /// Example:
  /// ```dart
  /// final tts = FlutterTts();
  /// await TtsConfig.apply(tts);
  /// ```
  static Future<void> apply(FlutterTts tts) async {
    try {
      // 1. Set engine first (Android only) — Google TTS has the best neural voices
      if (Platform.isAndroid) {
        await tts.setEngine(androidEngine);

        // Attempt to pick the best available voice
        // Google's en-us-x-iom-network voice is a high-quality WaveNet model
        final voices = await tts.getVoices;
        if (voices is List) {
          final voiceList = List<Map<Object?, Object?>>.from(voices);

          // Priority order for the best-sounding English voices
          const preferredVoices = [
            'en-us-x-iom-network',     // WaveNet — most human
            'en-us-x-iob-network',     // WaveNet Female
            'en-us-x-iol-network',     // WaveNet
            'en-us-x-iog-network',     // WaveNet
            'en-us-x-sfg-network',     // Neural2
            'en-us-x-tpc-network',     // Neural2
            'en-us-x-tpd-network',     // Neural2
            'en-us-x-tpf-network',     // Neural2
          ];

          Map<Object?, Object?>? bestVoice;
          for (final preferred in preferredVoices) {
            try {
              bestVoice = voiceList.firstWhere(
                (v) => v['name']?.toString().toLowerCase() == preferred,
              );
              break; // Found a match
            } catch (e) {
              debugPrint('[TtsConfig] Voice $preferred not found: $e');
              continue; // Not available, try next
            }
          }

          if (bestVoice != null) {
            await tts.setVoice({
              'name': bestVoice['name']?.toString() ?? '',
              'locale': bestVoice['locale']?.toString() ?? language,
            });
            debugPrint('[TtsConfig] Using premium voice: ${bestVoice['name']}');
          } else {
            debugPrint('[TtsConfig] No premium voice found, using system default');
          }
        }
      }

      // 2. Core voice parameters
      await tts.setLanguage(language);
      await tts.setSpeechRate(speechRate);
      await tts.setPitch(pitch);
      await tts.setVolume(volume);

      debugPrint('[TtsConfig] Applied — rate=$speechRate, pitch=$pitch, vol=$volume');
    } catch (e) {
      debugPrint('[TtsConfig] Error during apply: $e — falling back to defaults');
      // Fallback: at minimum set language and rate
      await tts.setLanguage(language);
      await tts.setSpeechRate(speechRate);
      await tts.setPitch(pitch);
      await tts.setVolume(volume);
    }
  }
}
