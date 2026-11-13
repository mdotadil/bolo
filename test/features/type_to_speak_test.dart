import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/type_to_speak.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/recording_player.dart';
import '../support/fakes.dart';

const _json =
    '{"speechRate":0.45,"activeLanguage":"en","categories":['
    '{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}}]}]}';

void main() {
  late Directory tmp;
  late FakeTts tts;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_tts');
    tts = FakeTts();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget app() => ProviderScope(overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(tts),
        recordingPlayerProvider.overrideWithValue(FakePlayer()),
        docsDirProvider.overrideWithValue(tmp),
      ], child: const MaterialApp(home: Scaffold(body: TypeToSpeak())));

  Future<void> pumpTool(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  testWidgets('speak button speaks trimmed text in active language and stores a recent',
      (tester) async {
    await pumpTool(tester);
    await tester.enterText(find.byKey(const ValueKey('tts-field')), '  good girl ');
    await tester.tap(find.byKey(const ValueKey('tts-speak')));
    await tester.pump();
    expect(tts.calls, contains('speak:good girl'));
    expect(find.byKey(const ValueKey('tts-recent-0')), findsOneWidget);
    expect(find.text('good girl'), findsWidgets);
  });

  testWidgets('empty input is a no-op', (tester) async {
    await pumpTool(tester);
    await tester.enterText(find.byKey(const ValueKey('tts-field')), '   ');
    await tester.tap(find.byKey(const ValueKey('tts-speak')));
    await tester.pump();
    expect(tts.calls.where((c) => c.startsWith('speak:')), isEmpty);
  });

  testWidgets('recents cap at 10, newest first, tap re-speaks', (tester) async {
    await pumpTool(tester);
    for (var i = 0; i < 12; i++) {
      await tester.enterText(
          find.byKey(const ValueKey('tts-field')), 'word$i');
      await tester.tap(find.byKey(const ValueKey('tts-speak')));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('tts-recent-9')), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-recent-10')), findsNothing);
    expect(find.text('word11'), findsWidgets); // newest first
    tts.calls.clear();
    await tester.tap(find.byKey(const ValueKey('tts-recent-0')));
    await tester.pump();
    expect(tts.calls, contains('speak:word11'));
  });
}
