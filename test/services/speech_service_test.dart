import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/services/recording_player.dart';
import 'package:bolo/services/speech_service.dart';

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
  Future<void> stop() async => calls.add('stop');
}

void main() {
  late Directory tmp;
  late FakeTts tts;
  late FakePlayer player;
  late SpeechService speech;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_speech');
    tts = FakeTts();
    player = FakePlayer();
    speech = SpeechService(tts, player, docsDir: tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('speakCard stops current utterance then speaks the en label', () async {
    await speech.speakCard(
        const SymbolCard(id: 'eat', labels: {'en': 'eat'}),
        language: 'en');
    expect(tts.calls, containsAllInOrder(['stop', 'lang:en-US', 'speak:eat']));
    expect(player.calls, contains('stop'));
  });

  test('speakCard with no label at all is a silent no-op', () async {
    await speech.speakCard(const SymbolCard(id: 'x', labels: {}),
        language: 'en');
    expect(tts.calls.where((c) => c.startsWith('speak:')), isEmpty);
  });

  test('recording wins over TTS and interrupts everything first', () async {
    Directory('${tmp.path}/recordings').createSync();
    File('${tmp.path}/recordings/eat_ur.m4a').writeAsStringSync('x');
    await speech.speakCard(
        const SymbolCard(
            id: 'eat',
            labels: {'en': 'eat', 'ur': 'کھانا'},
            recordings: {'ur': 'recordings/eat_ur.m4a'}),
        language: 'ur');
    expect(player.calls.last, 'play:${tmp.path}/recordings/eat_ur.m4a');
    expect(tts.calls, contains('stop'));
    expect(tts.calls.where((c) => c.startsWith('speak:')), isEmpty);
  });

  test('missing recording file falls back to ur TTS', () async {
    await speech.speakCard(
        const SymbolCard(
            id: 'eat',
            labels: {'en': 'eat', 'ur': 'کھانا'},
            recordings: {'ur': 'recordings/gone.m4a'}),
        language: 'ur');
    expect(tts.calls, containsAllInOrder(['lang:ur-PK', 'speak:کھانا']));
  });

  test('missing ur label falls back to en TTS with en voice', () async {
    await speech.speakCard(
        const SymbolCard(id: 'ball', labels: {'en': 'ball'}),
        language: 'ur');
    expect(tts.calls, containsAllInOrder(['lang:en-US', 'speak:ball']));
  });

  test('ar label sets lang:ar-SA; missing es label falls back to en voice',
      () async {
    await speech.speakCard(
        const SymbolCard(id: 'hug', labels: {'en': 'hug', 'ar': 'حضن'}),
        language: 'ar');
    expect(tts.calls, containsAllInOrder(['lang:ar-SA', 'speak:حضن']));
    tts.calls.clear();
    await speech.speakCard(
        const SymbolCard(id: 'ball', labels: {'en': 'ball'}),
        language: 'es');
    expect(tts.calls, containsAllInOrder(['lang:en-US', 'speak:ball']));
  });

  test('speakText speaks with the requested language voice', () async {
    await speech.speakText('good night', language: 'en');
    expect(tts.calls, containsAllInOrder(['stop', 'lang:en-US', 'speak:good night']));
    await speech.speakText('   ', language: 'en');
    expect(tts.calls.where((c) => c == 'speak:'), isEmpty);
  });

  test('configure sets rate and language; languageAvailable asks the tts',
      () async {
    await speech.configure(rate: 0.5, language: 'ur');
    expect(tts.calls, containsAllInOrder(['init', 'rate:0.5', 'lang:ur-PK']));
    expect(await speech.languageAvailable('ur'), isTrue);
    tts.unavailable.add('ur-PK');
    expect(await speech.languageAvailable('ur'), isFalse);
    tts.unavailable.add('es-ES');
    expect(await speech.languageAvailable('es'), isFalse);
    expect(await speech.languageAvailable('fr'), isTrue);
  });
}
