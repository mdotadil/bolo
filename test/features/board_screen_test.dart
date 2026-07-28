import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/board/board_screen.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/recording_player.dart';
import '../support/fakes.dart';

const _json =
    '{"speechRate":0.45,"categories":['
    '{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}},'
    '{"id":"drink","labels":{"en":"drink"},"hidden":true}]},'
    '{"id":"help","names":{"en":"Help"},"cards":[{"id":"help","labels":{"en":"help me"}}]}]}';

void main() {
  late Directory tmp;
  late FakeTts tts;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_ui');
    tts = FakeTts();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget app() => ProviderScope(overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(tts),
        recordingPlayerProvider.overrideWithValue(FakePlayer()),
        docsDirProvider.overrideWithValue(tmp),
      ], child: const MaterialApp(home: BoardScreen()));

  testWidgets('shows visible cards of selected category, hides hidden ones',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('eat'), findsOneWidget);
    expect(find.text('drink'), findsNothing); // hidden
    expect(find.text('help me'), findsNothing); // other category
  });

  testWidgets('tapping a card speaks it', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('eat'));
    await tester.pump();
    expect(tts.calls, containsAllInOrder(['stop', 'lang:en-US', 'speak:eat']));
  });

  testWidgets('category tab switches the grid', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(find.text('help me'), findsOneWidget);
    expect(find.text('eat'), findsNothing);
  });
}
