import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class RecordingPlayer {
  Future<void> play(String absolutePath);
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
  Future<void> stop() => _player.stop();
}

final recordingPlayerProvider = Provider<RecordingPlayer>(
    (ref) => throw UnimplementedError('override in main'));
