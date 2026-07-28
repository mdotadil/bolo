import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/recording_player.dart';
import 'package:bolo/services/speech_service.dart';
import '../support/fakes.dart';

const _defaultJson =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"},"symbolAsset":"assets/symbols/eat.svg"},'
    '{"id":"drink","labels":{"en":"drink"},"symbolAsset":"assets/symbols/drink.svg"}]}]}';

const _threeCardJson =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"a","labels":{"en":"a"},"symbolAsset":"assets/symbols/eat.svg"},'
    '{"id":"b","labels":{"en":"b"},"symbolAsset":"assets/symbols/drink.svg"},'
    '{"id":"c","labels":{"en":"c"},"symbolAsset":"assets/symbols/drink.svg"}]}]}';

/// Simulates a platform TTS channel that has no engine/voice installed.
class ThrowingTts implements Tts {
  @override
  Future<void> init() async => throw StateError('no TTS engine available');
  @override
  Future<void> setSpeechRate(double rate) async =>
      throw StateError('no TTS engine available');
  @override
  Future<void> stop() async => throw StateError('no TTS engine available');
  @override
  Future<void> speak(String text) async =>
      throw StateError('no TTS engine available');
  @override
  Future<void> setLanguage(String tag) async =>
      throw StateError('no TTS engine available');
  @override
  Future<bool> isLanguageAvailable(String tag) async =>
      throw StateError('no TTS engine available');
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
      recordingPlayerProvider.overrideWithValue(FakePlayer()),
      docsDirProvider.overrideWithValue(tmp),
    ]);
  });
  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('build loads board and configures speech with its rate', () async {
    final board = await container.read(boardNotifierProvider.future);
    expect(board.categories.single.cards.length, 2);
    expect(tts.calls, ['init', 'rate:0.45', 'lang:en-US']);
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

  test('reorderCard moves a card within its category (down)', () async {
    await container.read(boardNotifierProvider.future);
    // onReorderItem passes adjusted newIndex: drag 0 down past 1 → newIndex=1
    await container.read(boardNotifierProvider.notifier).reorderCard('wants', 0, 1);
    final ids = container.read(boardNotifierProvider).value!
        .categories.single.cards.map((c) => c.id).toList();
    expect(ids, ['drink', 'eat']);
  });

  test('reorderCard moves a card up within its category', () async {
    final threeContainer = ProviderContainer(overrides: [
      boardStoreProvider.overrideWithValue(
          BoardStore(tmp, loadDefault: () async => _threeCardJson)),
      ttsProvider.overrideWithValue(tts),
      recordingPlayerProvider.overrideWithValue(FakePlayer()),
      docsDirProvider.overrideWithValue(tmp),
    ]);
    await threeContainer.read(boardNotifierProvider.future);
    // Starting with [a, b, c], move c up to position 0
    await threeContainer.read(boardNotifierProvider.notifier).reorderCard('wants', 2, 0);
    final ids = threeContainer.read(boardNotifierProvider).value!
        .categories.single.cards.map((c) => c.id).toList();
    expect(ids, ['c', 'a', 'b']);
    threeContainer.dispose();
  });

  test('reorderCard moves a card down past two others', () async {
    final threeContainer = ProviderContainer(overrides: [
      boardStoreProvider.overrideWithValue(
          BoardStore(tmp, loadDefault: () async => _threeCardJson)),
      ttsProvider.overrideWithValue(tts),
      recordingPlayerProvider.overrideWithValue(FakePlayer()),
      docsDirProvider.overrideWithValue(tmp),
    ]);
    await threeContainer.read(boardNotifierProvider.future);
    // Starting with [a, b, c], move a down to the end → newIndex=2 (end of list after removal)
    await threeContainer.read(boardNotifierProvider.notifier).reorderCard('wants', 0, 2);
    final ids = threeContainer.read(boardNotifierProvider).value!
        .categories.single.cards.map((c) => c.id).toList();
    expect(ids, ['b', 'c', 'a']);
    threeContainer.dispose();
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
    expect(tts.calls, containsAllInOrder(['rate:0.6', 'lang:en-US']));
  });

  test('build still returns the board when TTS init throws', () async {
    final throwingContainer = ProviderContainer(overrides: [
      boardStoreProvider.overrideWithValue(
          BoardStore(tmp, loadDefault: () async => _defaultJson)),
      ttsProvider.overrideWithValue(ThrowingTts()),
      recordingPlayerProvider.overrideWithValue(FakePlayer()),
      docsDirProvider.overrideWithValue(tmp),
    ]);
    final board = await throwingContainer.read(boardNotifierProvider.future);
    expect(board.categories.single.cards.length, 2);
    expect(
        throwingContainer.read(boardNotifierProvider), isA<AsyncData<Board>>());
    throwingContainer.dispose();
  });
}
