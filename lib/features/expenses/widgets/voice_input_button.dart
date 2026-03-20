import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/utils/haptic_utils.dart';

/// Standalone mic button for voice-to-text expense input.
/// // TODO(FEAT-01-P2): wire transcript to Gemini parsing
class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({super.key, required this.onTranscript});
  final void Function(String transcript) onTranscript;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  static const _teal = Color(0xFF14B8A6);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    final available = await _speech.initialize(
      onError: (_) => _stopListening(),
    );
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
      }
      return;
    }
    // HAPTIC-01: recording start feedback
    HapticUtils.primaryTap();
    setState(() => _isListening = true);
    _pulseController.repeat(reverse: true);

    _speech.listen(
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      onResult: (result) {
        if (result.finalResult) {
          final transcript = result.recognizedWords;
          _stopListening();
          if (transcript.isNotEmpty) {
            widget.onTranscript(transcript);
          }
        }
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    _pulseController.stop();
    _pulseController.reset();
    // HAPTIC-01: recording stop feedback
    HapticUtils.lightTap();
    if (mounted) setState(() => _isListening = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isListening) {
      return ScaleTransition(
        scale: _pulseAnimation,
        child: IconButton(
          onPressed: _toggle,
          icon: const Icon(Icons.mic, color: Colors.red),
          style: IconButton.styleFrom(
            backgroundColor: Colors.red.withValues(alpha: 0.15),
          ),
        ),
      );
    }
    return IconButton(
      onPressed: _toggle,
      icon: const Icon(Icons.mic_outlined, color: _teal),
      tooltip: 'Voice input',
    );
  }
}
