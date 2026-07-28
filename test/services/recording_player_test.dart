import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';

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
