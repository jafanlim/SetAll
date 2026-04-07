import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';

import '../config/auth_config.dart';
import '../models/voice_entry_result.dart';

class VoiceEntryService {
  static final VoiceEntryService _instance = VoiceEntryService._();
  static VoiceEntryService get instance => _instance;
  VoiceEntryService._();

  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _stt.initialize(
      onError: (error) {
        if (kDebugMode) debugPrint('[VoiceEntry] STT error: $error');
      },
    );
    return _initialized;
  }

  /// Listen until silence or 30s timeout. Returns transcript.
  Future<String> listen({
    void Function(String partial)? onPartial,
    String? preferredLocale,
  }) async {
    if (!await initialize()) throw Exception('STT not available');

    final completer = Completer<String>();
    String lastResult = '';

    // Determine best locale
    String? localeToUse = preferredLocale;
    if (localeToUse == null) {
      try {
        final available = await _stt.locales();
        // Try to match device locale (e.g. 'ru_RU' → find 'ru-RU' or 'ru_RU')
        final deviceLang = Platform.localeName.split('_').first.toLowerCase();
        final match = available.firstWhereOrNull(
          (l) => l.localeId.toLowerCase().startsWith(deviceLang),
        );
        localeToUse = match?.localeId; // null = engine default
      } catch (_) {
        localeToUse = null; // fallback to engine default
      }
    }

    await _stt.listen(
      onResult: (result) {
        lastResult = result.recognizedWords;
        if (onPartial != null) onPartial(lastResult);
        if (result.finalResult) {
          _stt.stop();
          if (!completer.isCompleted) completer.complete(lastResult);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: localeToUse,
      listenOptions: SpeechListenOptions(cancelOnError: true),
    );

    // Timeout fallback
    Future.delayed(const Duration(seconds: 31), () {
      if (!completer.isCompleted) {
        _stt.stop();
        completer.complete(lastResult);
      }
    });

    return completer.future;
  }

  Future<void> stop() async => _stt.stop();
  Future<void> cancel() async => _stt.cancel();
  bool get isListening => _stt.isListening;

  Future<VoiceEntryResult> parse(
    String transcript,
    List<Map<String, dynamic>> groups,
    String defaultCurrency, {
    String language = 'en',
  }) async {
    final response = await http.post(
      Uri.parse(AuthConfig.netlifyVoiceEntryUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'transcript': transcript,
        'groups': groups,
        'defaultCurrency': defaultCurrency,
        'language': language,
        'knownCategories': [
          'Food & drink',
          'Transport',
          'Travel',
          'Entertainment',
          'Bills & utilities',
          'Shopping',
          'General',
          'Other',
        ],
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Voice parse failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return VoiceEntryResult.fromJson(json);
  }
}
