import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/board.dart';
import 'recording_player.dart';

/// Asset keys of the bundled natural-voice clips
/// (`assets/voice/<lang>/<cardId>.mp3`), generated offline from the default
/// boards by tools/split_voice_clips.py (see tools/VOICE_SETUP.md).
Future<Set<String>> loadBundledVoiceClips() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  return manifest
      .listAssets()
      .where((key) => key.startsWith('assets/voice/') && key.endsWith('.mp3'))
      .toSet();
}

abstract class Tts {
  Future<void> init();
  Future<void> setSpeechRate(double rate);
  Future<void> stop();
  Future<void> speak(String text);
  Future<void> setLanguage(String tag);
  Future<bool> isLanguageAvailable(String tag);
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
  @override
  Future<void> setLanguage(String tag) => _tts.setLanguage(tag);
  @override
  Future<bool> isLanguageAvailable(String tag) async =>
      (await _tts.isLanguageAvailable(tag)) == true;
}

class SpeechService {
  SpeechService(this._tts, this._player,
      {required this._docsDir, Future<Set<String>> Function()? bundledClips})
      : _loadBundledClips = bundledClips ?? loadBundledVoiceClips;

  /// One entry per supportedLanguages member (kept in the same order).
  static const _ttsTag = {
    'en': 'en-US',
    'ur': 'ur-PK',
    'ar': 'ar-SA',
    'fr': 'fr-FR',
    'es': 'es-ES',
  };

  final Tts _tts;
  final RecordingPlayer _player;
  final Directory _docsDir;
  final Future<Set<String>> Function() _loadBundledClips;
  Future<Set<String>>? _clipsFuture;
  bool _initialized = false;

  /// Bundled clip keys, loaded once. A load failure means "no clips", never
  /// an error: the card still speaks through TTS.
  Future<Set<String>> _bundledClips() => _clipsFuture ??= () async {
        try {
          return await _loadBundledClips();
        } catch (_) {
          return <String>{};
        }
      }();

  Future<void> configure({required double rate, String language = 'en'}) async {
    if (!_initialized) {
      await _tts.init();
      _initialized = true;
    }
    await _tts.setSpeechRate(rate);
    await _tts.setLanguage(_ttsTag[language] ?? 'en-US');
  }

  /// Whether the device has a TTS voice for [language] (a supportedLanguages
  /// code). Drives the parent-mode "voice not available" note.
  Future<bool> languageAvailable(String language) =>
      _tts.isLanguageAvailable(_ttsTag[language] ?? 'en-US');

  /// New speech always interrupts everything; nothing queues.
  Future<void> stopAll() async {
    await _player.stop();
    await _tts.stop();
  }

  /// Priority: parent recording, bundled natural-voice clip, device TTS —
  /// first in the active language, then falling back to English.
  Future<void> speakCard(SymbolCard card, {required String language}) async {
    final relative = card.recordings[language];
    if (relative != null) {
      final file = File('${_docsDir.path}/$relative');
      if (file.existsSync()) {
        await stopAll();
        await _player.play(file.path);
        return;
      }
    }
    if (await _playBundledClip(card.id, language)) return;
    final label = card.labels[language];
    if (label != null && label.isNotEmpty) {
      await _speak(label, language);
      return;
    }
    final en = card.labels['en'];
    if (en == null || en.isEmpty) return; // calm silence, never an error
    if (language != 'en' && await _playBundledClip(card.id, 'en')) return;
    await _speak(en, 'en');
  }

  Future<bool> _playBundledClip(String cardId, String language) async {
    final key = 'assets/voice/$language/$cardId.mp3';
    if (!(await _bundledClips()).contains(key)) return false;
    await stopAll();
    await _player.playAsset(key);
    return true;
  }

  Future<void> speakText(String text, {required String language}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _speak(trimmed, language);
  }

  Future<void> _speak(String text, String language) async {
    await stopAll();
    await _tts.setLanguage(_ttsTag[language] ?? 'en-US');
    await _tts.speak(text);
  }
}
