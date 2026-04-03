import 'dart:async';
import 'dart:convert';

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
      onError: (error) => debugPrint('[VoiceEntry] STT error: $error'),
    );
    return _initialized;
  }

  /// Listen until silence or 30s timeout. Returns transcript.
  Future<String> listen({
    void Function(String partial)? onPartial,
  }) async {
    if (!await initialize()) throw Exception('STT not available');

    final completer = Completer<String>();
    String lastResult = '';

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
      localeId: 'en_US',
      listenOptions: SpeechListenOptions(cancelOnError: true),
    );

    // Timeout fallback
    Future.delayed(const Duration(seconds: 30), () {
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
    String defaultCurrency,
  ) async {
    final response = await http.post(
      Uri.parse(AuthConfig.netlifyVoiceEntryUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'transcript': transcript,
        'groups': groups,
        'defaultCurrency': defaultCurrency,
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
