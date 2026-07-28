import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

abstract class Recorder {
  Future<bool> hasPermission();
  Future<void> start(String path);

  /// Returns the recorded file's path, or null if not recording / failed.
  Future<String?> stop();
  bool get isRecording;
}

class RecordPackageRecorder implements Recorder {
  final AudioRecorder _rec = AudioRecorder();
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<void> start(String path) async {
    await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
        path: path);
    _recording = true;
  }

  @override
  Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    try {
      return await _rec.stop();
    } catch (_) {
      return null;
    }
  }
}

final recorderProvider =
    Provider<Recorder>((ref) => throw UnimplementedError('override in main'));
