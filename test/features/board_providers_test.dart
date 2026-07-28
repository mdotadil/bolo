import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/speech_service.dart';

const _defaultJson =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"},"symbolAsset":"assets/symbols/eat.svg"},'
    '{"id":"drink","labels":{"en":"drink"},"symbolAsset":"assets/symbols/drink.svg"}]}]}';

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
  late Directory tmp;
  late ProviderContainer container;
  late FakeTts tts;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_prov');
    tts = FakeTts();
    container = ProviderContainer(overrides: [
      boardStoreProvider.overrideWithValue(
          BoardStore(tmp, loadDefault: () async => _defaultJson)),
      ttsProvider.overrideWithValue(tts),
    ]);
  });
  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('build loads board and configures speech with its rate', () async {
    final board = await container.read(boardNotifierProvider.future);
    expect(board.categories.single.cards.length, 2);
    expect(tts.calls, ['init', 'rate:0.45']);
  });

  test('toggleHidden flips the flag and persists', () async {
    await container.read(boardNotifierProvider.future);
    final notifier = container.read(boardNotifierProvider.notifier);
    await notifier.toggleHidden('eat');
    expect(container.read(boardNotifierProvider).value!
        .categories.single.cards.first.hidden, isTrue);
    // persisted: a fresh store sees it
    final reloaded = await BoardStore(tmp, loadDefault: () async => _defaultJson).load();
    expect(reloaded.categories.single.cards.first.hidden, isTrue);
  });

  test('reorderCard moves a card within its category', () async {
    await container.read(boardNotifierProvider.future);
    await container.read(boardNotifierProvider.notifier).reorderCard('wants', 0, 2);
    final ids = container.read(boardNotifierProvider).value!
        .categories.single.cards.map((c) => c.id).toList();
    expect(ids, ['drink', 'eat']);
  });

  test('addCustomCard appends a photo card', () async {
    await container.read(boardNotifierProvider.future);
    await container.read(boardNotifierProvider.notifier).addCustomCard(
        categoryId: 'wants', label: 'blanket', photoPath: '/p/b.jpg');
    final card = container.read(boardNotifierProvider).value!
        .categories.single.cards.last;
    expect(card.labels['en'], 'blanket');
    expect(card.photoPath, '/p/b.jpg');
    expect(card.symbolAsset, isNull);
  });

  test('setSpeechRate persists and reconfigures speech', () async {
    await container.read(boardNotifierProvider.future);
    await container.read(boardNotifierProvider.notifier).setSpeechRate(0.6);
    expect(container.read(boardNotifierProvider).value!.speechRate, 0.6);
    expect(tts.calls.last, 'rate:0.6');
  });
}
