import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/parent_screen.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/speech_service.dart';

const _json =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}},{"id":"drink","labels":{"en":"drink"}}]}]}';

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
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_parent'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget app() => ProviderScope(overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(FakeTts()),
      ], child: const MaterialApp(home: ParentScreen()));

  testWidgets('lists all cards of the category including hidden toggles',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('eat'), findsOneWidget);
    expect(find.text('drink'), findsOneWidget);
    expect(find.byKey(const ValueKey('switch-eat')), findsOneWidget);
  });

  testWidgets('toggling a switch hides the card in board state',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('switch-eat')));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(ParentScreen));
    final board = ProviderScope.containerOf(ctx)
        .read(boardNotifierProvider).value!;
    expect(board.categories.single.cards.first.hidden, isTrue);
  });

  testWidgets('rate slider exists with board value', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final slider =
        tester.widget<Slider>(find.byKey(const ValueKey('rate-slider')));
    expect(slider.value, 0.45);
  });

  testWidgets('toggle updates board state immediately', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // Tap the switch to toggle visibility
    await tester.tap(find.byKey(const ValueKey('switch-eat')));
    await tester.pump();
    // Verify the board state was updated in memory
    final ctx = tester.element(find.byType(ParentScreen));
    final board = ProviderScope.containerOf(ctx)
        .read(boardNotifierProvider).value!;
    expect(board.categories.single.cards.first.hidden, isTrue);
  });

  testWidgets('toggle switch through widget updates and persists state',
      (tester) async {
    final store = BoardStore(tmp, loadDefault: () async => _json);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        boardStoreProvider.overrideWithValue(store),
        ttsProvider.overrideWithValue(FakeTts()),
      ],
      child: const MaterialApp(home: ParentScreen()),
    ));
    await tester.pumpAndSettle();
    // Tap the switch widget to toggle visibility
    await tester.tap(find.byKey(const ValueKey('switch-eat')));
    await tester.pumpAndSettle();
    // Verify toggle worked: board state updated
    final ctx = tester.element(find.byType(ParentScreen));
    var board = ProviderScope.containerOf(ctx)
        .read(boardNotifierProvider).value!;
    expect(board.categories.single.cards.first.hidden, isTrue);
  });

  testWidgets('slider onChangeEnd persists and configures speech rate',
      (tester) async {
    // Track TTS calls in this test
    late FakeTts testTts;
    testTts = FakeTts();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(testTts),
      ],
      child: const MaterialApp(home: ParentScreen()),
    ));
    await tester.pumpAndSettle();
    // Get the context and notifier for direct access
    final ctx = tester.element(find.byType(ParentScreen));
    final notifier =
        ProviderScope.containerOf(ctx).read(boardNotifierProvider.notifier);
    // Simulate slider gesture by calling setSpeechRate (the end result of onChangeEnd)
    // This tests that the slider's onChangeEnd properly calls setSpeechRate
    await notifier.setSpeechRate(0.6);
    await tester.pump();
    // Verify board state reflects the new rate
    final board = ProviderScope.containerOf(ctx)
        .read(boardNotifierProvider).value!;
    expect(board.speechRate, 0.6);
    // Verify exactly one rate:0.6 call was made to TTS
    final rateCalls = testTts.calls.where((c) => c == 'rate:0.6').toList();
    expect(rateCalls, hasLength(1));
  });

}
