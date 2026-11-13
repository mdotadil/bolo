import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class RecordingPlayer {
  Future<void> play(String absolutePath);

  /// Plays a bundled asset by its full key ("assets/voice/en/eat.mp3").
  /// Shares the player (and thus the iOS audio session) with recordings.
  Future<void> playAsset(String assetKey);
  Future<void> stop();
}

class AudioplayersRecordingPlayer implements RecordingPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> play(String absolutePath) async {
    await _player.stop();
    await _player.play(DeviceFileSource(absolutePath));
  }

  @override
  Future<void> playAsset(String assetKey) async {
    await _player.stop();
    // AssetSource resolves relative to the "assets/" prefix.
    final path = assetKey.startsWith('assets/')
        ? assetKey.substring('assets/'.length)
        : assetKey;
    await _player.play(AssetSource(path));
  }

  @override
  Future<void> stop() => _player.stop();
}

final recordingPlayerProvider = Provider<RecordingPlayer>(
    (ref) => throw UnimplementedError('override in main'));
