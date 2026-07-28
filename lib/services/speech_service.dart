import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/board.dart';

abstract class Tts {
  Future<void> init();
  Future<void> setSpeechRate(double rate);
  Future<void> stop();
  Future<void> speak(String text);
}

/// Production adapter. The iOS audio category is the load-bearing part:
/// `playback` makes speech audible with the silent switch on.
class FlutterTtsAdapter implements Tts {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> init() async {
    if (Platform.isIOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.duckOthers],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }
    await _tts.setLanguage('en-US');
    await _tts.awaitSpeakCompletion(false);
  }

  @override
  Future<void> setSpeechRate(double rate) => _tts.setSpeechRate(rate);
  @override
  Future<void> stop() => _tts.stop();
  @override
  Future<void> speak(String text) => _tts.speak(text);
}

class SpeechService {
  SpeechService(this._tts);
  final Tts _tts;
  bool _initialized = false;

  Future<void> configure({required double rate}) async {
    if (!_initialized) {
      await _tts.init();
      _initialized = true;
    }
    await _tts.setSpeechRate(rate);
  }

  Future<void> speakCard(SymbolCard card) async {
    final text = card.labels['en'];
    if (text == null || text.isEmpty) return;
    await _tts.stop(); // new tap always interrupts; speech never queues
    await _tts.speak(text);
  }
}
