import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/audio_recorder.dart';
import 'package:bolo/services/recording_player.dart';

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

class FakePlayer implements RecordingPlayer {
  final calls = <String>[];
  @override
  Future<void> play(String p) async => calls.add('play:$p');
  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  test('recorder stop returns the started path once', () async {
    final r = FakeRecorder();
    await r.start('/tmp/a.m4a');
    expect(r.isRecording, isTrue);
    expect(await r.stop(), '/tmp/a.m4a');
    expect(await r.stop(), isNull);
  });

  test('player records play/stop calls', () async {
    final p = FakePlayer();
    await p.play('/tmp/a.m4a');
    await p.stop();
    expect(p.calls, ['play:/tmp/a.m4a', 'stop']);
  });
}
