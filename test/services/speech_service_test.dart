import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/services/speech_service.dart';

class FakeTts implements Tts {
  final calls = <String>[];
  @override
  Future<void> init() async => calls.add('init');
  @override
  Future<void> setSpeechRate(double rate) async => calls.add('rate:$rate');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> speak(String text) async => calls.add('speak:$text');
}

void main() {
  test('configure inits once and sets rate each time', () async {
    final tts = FakeTts();
    final speech = SpeechService(tts);
    await speech.configure(rate: 0.45);
    await speech.configure(rate: 0.6);
    expect(tts.calls, ['init', 'rate:0.45', 'rate:0.6']);
  });

  test('speakCard stops current utterance then speaks the en label', () async {
    final tts = FakeTts();
    await SpeechService(tts)
        .speakCard(const SymbolCard(id: 'eat', labels: {'en': 'eat'}));
    expect(tts.calls, ['stop', 'speak:eat']);
  });

  test('speakCard with no en label is a silent no-op', () async {
    final tts = FakeTts();
    await SpeechService(tts).speakCard(const SymbolCard(id: 'x', labels: {}));
    expect(tts.calls, isEmpty);
  });
}
