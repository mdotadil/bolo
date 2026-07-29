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
    '{"id":"eat","labels":{"en":"eat","ur":"کھانا"}},'
    '{"id":"drink","labels":{"en":"drink"},"hidden":true},'
    '{"id":"phrase-1","labels":{"en":"I need the toilet","ur":"مجھے ٹوائلٹ جانا ہے"}}]},'
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

  Future<void> pumpBoard(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  testWidgets('shows visible cards of selected category, hides hidden ones',
      (tester) async {
    await pumpBoard(tester);
    expect(find.text('eat'), findsOneWidget);
    expect(find.text('drink'), findsNothing); // hidden
    expect(find.text('help me'), findsNothing); // other category
  });

  testWidgets('tapping a card speaks it', (tester) async {
    await pumpBoard(tester);
    await tester.tap(find.text('eat'));
    await tester.pump();
    expect(tts.calls, containsAllInOrder(['stop', 'lang:en-US', 'speak:eat']));
  });

  testWidgets('category tab switches the grid', (tester) async {
    await pumpBoard(tester);
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(find.text('help me'), findsOneWidget);
    expect(find.text('eat'), findsNothing);
  });

  testWidgets('former More-page card is listed directly in the grid',
      (tester) async {
    await pumpBoard(tester);
    expect(find.text('I need the toilet'), findsOneWidget);
  });

  // BoardStore.save() does real dart:io file I/O; a plain testWidgets body
  // can't await that chain without deadlocking (see parent_screen_test.dart's
  // comment for the full explanation of why). Run the notifier call through
  // tester.runAsync, then leave that zone before touching the widget tree.
  testWidgets('labels follow activeLanguage', (tester) async {
    await pumpBoard(tester); // fixture activeLanguage stays 'en'
    final ctx = tester.element(find.byType(BoardScreen));
    final container = ProviderScope.containerOf(ctx);

    await tester.runAsync(() async {
      await container
          .read(boardNotifierProvider.notifier)
          .setActiveLanguage('ur');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    await tester.pump();
    expect(find.text('کھانا'), findsOneWidget); // the ur label from the fixture
  });
}
