import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService._internal();
  static final TtsService instance = TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  String? _selectedLanguage;

  Future<void> init() async {
    if (_ready) return;
    try {
      // probe available languages safely
      try {
        final langs = await _tts.getLanguages;
        if (langs != null && langs is List) {
          // prefer Marathi variants
          final candidates = ['mr-IN', 'mr_IN', 'mr'];
          for (final c in candidates) {
            if (langs.contains(c)) {
              _selectedLanguage = c;
              break;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('TTS getLanguages failed: $e');
      }

      // set language only if we found a candidate
      if (_selectedLanguage != null) {
        try {
          final res = await _tts.setLanguage(_selectedLanguage!);
          if (kDebugMode) print('TTS setLanguage result: $res');
        } on PlatformException catch (e) {
          if (kDebugMode) print('setLanguage PlatformException: $e');
        } catch (e) {
          if (kDebugMode) print('setLanguage error: $e');
        }
      }

      // set other parameters defensively
      try {
        await _tts.setSpeechRate(0.45);
      } catch (e) {
        if (kDebugMode) print('setSpeechRate error: $e');
      }
      try {
        await _tts.setVolume(1.0);
      } catch (e) {
        if (kDebugMode) print('setVolume error: $e');
      }
      try {
        await _tts.setPitch(1.0);
      } catch (e) {
        if (kDebugMode) print('setPitch error: $e');
      }

      _ready = true;
    } catch (e) {
      if (kDebugMode) {
        print('TTS init error (outer): $e');
      }
    }
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await init();
    try {
      await _tts.stop();
      // speak can throw platform exceptions — catch them
      try {
        await _tts.speak(text);
      } on PlatformException catch (e) {
        if (kDebugMode) print('TTS speak PlatformException: $e');
      } catch (e) {
        if (kDebugMode) print('TTS speak error: $e');
      }
    } catch (e) {
      if (kDebugMode) {
        print('TTS speak top-level error: $e');
      }
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      if (kDebugMode) print('TTS stop error: $e');
    }
  }
}
