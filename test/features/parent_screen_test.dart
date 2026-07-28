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
  @override
  Future<void> init() async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> speak(String text) async {}
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

}
