import 'package:bolo/services/audio_recorder.dart';
import 'package:bolo/services/recording_player.dart';
import 'package:bolo/services/speech_service.dart';

/// Shared test fakes for the TTS/recording/playback seams. Kept in one place
/// so widget and provider tests don't grow their own copy-pasted variant
/// every time the `Tts`/`Recorder`/`RecordingPlayer` interfaces gain a member.
///
/// Standard `ParentScreen` override set (see `parent_screen_test.dart` and
/// `diagnostics_toggle_test.dart`): boardStoreProvider, ttsProvider,
/// recordingPlayerProvider, recorderProvider, docsDirProvider, and — as of
/// the store-channel bootstrap (Task 18) — `settingsStoreProvider.overrideWithValue(SettingsStore(tmp))`.
/// `settingsProvider` is only ever watched behind the store-channel
/// `appChannel == AppChannel.store` branch (the diagnostics toggle), but the
/// override belongs in every pump helper so the same helpers pump cleanly
/// under both the sideload suite here and the store-channel twin in
/// Task 21's `channel_test.dart`.
class FakeTts implements Tts {
  final calls = <String>[];

  /// TTS tags to report as missing (e.g. add 'ur-PK' to simulate a phone
  /// without an Urdu voice).
  final unavailable = <String>{};
  @override
  Future<void> init() async => calls.add('init');
  @override
  Future<void> setSpeechRate(double rate) async => calls.add('rate:$rate');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> speak(String text) async => calls.add('speak:$text');
  @override
  Future<void> setLanguage(String tag) async => calls.add('lang:$tag');
  @override
  Future<bool> isLanguageAvailable(String tag) async =>
      !unavailable.contains(tag);
}

class FakePlayer implements RecordingPlayer {
  final calls = <String>[];
  @override
  Future<void> play(String p) async => calls.add('play:$p');
  @override
  Future<void> playAsset(String key) async => calls.add('asset:$key');
  @override
  Future<void> stop() async => calls.add('stop');
}

class FakeRecorder implements Recorder {
  final calls = <String>[];
  bool _rec = false;
  @override
  bool get isRecording => _rec;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start(String path) async {
    calls.add('start:$path');
    _rec = true;
  }

  @override
  Future<String?> stop() async {
    if (!_rec) return null;
    _rec = false;
    final path = calls.last.substring('start:'.length);
    calls.add('stop');
    return path;
  }
}
