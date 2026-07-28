import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/board/more_page.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/recording_player.dart';
import '../support/fakes.dart';

const _json =
    '{"speechRate":0.45,"categories":['
    '{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}}],'
    '"moreCards":['
    '{"id":"phrase-1","labels":{"en":"I need the toilet"}},'
    '{"id":"phrase-2","labels":{"en":"hidden phrase"},"hidden":true}]}]}';

void main() {
  late Directory tmp;
  late FakeTts tts;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_more');
    tts = FakeTts();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  List<Override> overrides() => [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(tts),
        recordingPlayerProvider.overrideWithValue(FakePlayer()),
        docsDirProvider.overrideWithValue(tmp),
      ];

  Widget app() => ProviderScope(
      overrides: overrides(),
      child: const MaterialApp(home: MorePage(categoryIndex: 0)));

  testWidgets('shows visible more cards, hides hidden ones', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('I need the toilet'), findsOneWidget);
    expect(find.text('hidden phrase'), findsNothing);
  });

  testWidgets('tapping a card speaks it', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('I need the toilet'));
    await tester.pump();
    expect(tts.calls,
        containsAllInOrder(['stop', 'lang:en-US', 'speak:I need the toilet']));
  });

  testWidgets('back button pops the route via zeroDurationRoute',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context)
                    .push(zeroDurationRoute(const MorePage(categoryIndex: 0))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    // Unlike board_screen_test.dart's equivalent test, nothing on this
    // button-only home screen has watched boardNotifierProvider yet, so it's
    // still AsyncLoading right after the push; settle (not a single pump)
    // until it resolves. The route transition itself is still zero-duration.
    await tester.pumpAndSettle();
    expect(find.text('I need the toilet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('more-back')));
    await tester.pumpAndSettle();
    expect(find.text('I need the toilet'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  test('zeroDurationRoute builds a zero-duration PageRouteBuilder both ways',
      () {
    final route = zeroDurationRoute(const SizedBox()) as PageRouteBuilder<void>;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });
}
