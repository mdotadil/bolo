import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/parent_screen.dart';
import 'package:bolo/features/parent/record_sheet.dart';
import 'package:bolo/services/audio_recorder.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/recording_player.dart';
import '../support/fakes.dart';

void main() {
  late Directory tmp;
  late FakeRecorder fakeRecorder;
  late FakePlayer fakePlayer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_record');
    fakeRecorder = FakeRecorder();
    fakePlayer = FakePlayer();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  // Board fixture: one default card 'eat' (symbolAsset) and one custom card
  // 'custom-1' (photoPath), so both sheet variants (five-language rows only,
  // vs. five-language rows + label fields) can be pumped.
  String defaultJson() =>
      '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
      '{"id":"eat","labels":{"en":"eat"},"symbolAsset":"assets/symbols/eat.svg"},'
      '{"id":"custom-1","labels":{"en":"blanket"},"photoPath":"${tmp.path}/custom-1.jpg"}'
      ']}]}';

  String seededJson() =>
      '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
      '{"id":"eat","labels":{"en":"eat"},"symbolAsset":"assets/symbols/eat.svg",'
      '"recordings":{"ur":"recordings/eat_ur.m4a"}},'
      '{"id":"custom-1","labels":{"en":"blanket"},"photoPath":"${tmp.path}/custom-1.jpg"}'
      ']}]}';

  Widget app({required String json}) => ProviderScope(overrides: [
        boardStoreProvider
            .overrideWithValue(BoardStore(tmp, loadDefault: () async => json)),
        ttsProvider.overrideWithValue(FakeTts()),
        recordingPlayerProvider.overrideWithValue(fakePlayer),
        recorderProvider.overrideWithValue(fakeRecorder),
        docsDirProvider.overrideWithValue(tmp),
      ], child: const MaterialApp(home: ParentScreen()));

  Future<void> pumpParent(WidgetTester tester) async {
    File('${tmp.path}/custom-1.jpg').writeAsBytesSync([1, 2, 3]);
    await tester.pumpWidget(app(json: defaultJson()));
    await tester.pumpAndSettle();
  }

  Future<void> pumpParentWithRecording(WidgetTester tester) async {
    File('${tmp.path}/custom-1.jpg').writeAsBytesSync([1, 2, 3]);
    Directory('${tmp.path}/recordings').createSync(recursive: true);
    File('${tmp.path}/recordings/eat_ur.m4a').writeAsBytesSync([1, 2, 3]);
    await tester.pumpWidget(app(json: seededJson()));
    await tester.pumpAndSettle();
  }

  Board readBoard(WidgetTester tester) {
    final ctx = tester.element(find.byType(ParentScreen));
    return ProviderScope.containerOf(ctx).read(boardNotifierProvider).value!;
  }

  testWidgets('record→stop stores a relative recording path on the card',
      (tester) async {
    await pumpParent(tester);
    await tester.tap(find.byKey(const ValueKey('mic-eat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rec-start-ur')));
    await tester.pump();
    expect(find.byKey(const ValueKey('rec-stop-ur')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('rec-stop-ur')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final board = readBoard(tester);
    final eat = board.categories.first.cards.firstWhere((c) => c.id == 'eat');
    expect(eat.recordings['ur'], 'recordings/eat_ur.m4a');
  });

  testWidgets('play button plays the recording; delete removes it',
      (tester) async {
    await pumpParentWithRecording(tester);
    await tester.tap(find.byKey(const ValueKey('mic-eat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rec-play-ur')));
    await tester.pump();
    expect(fakePlayer.calls.any((c) => c.startsWith('play:')), isTrue);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('rec-delete-ur')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final board = readBoard(tester);
    expect(board.categories.first.cards.first.recordings, isEmpty);
  });

  testWidgets('record sheet shows one row per supported language',
      (tester) async {
    await pumpParent(tester);
    await tester.tap(find.byKey(const ValueKey('mic-eat')));
    await tester.pumpAndSettle();
    for (final lang in supportedLanguages) {
      expect(find.byKey(ValueKey('rec-start-$lang')), findsOneWidget,
          reason: 'missing record row for $lang');
      expect(find.text(languageDisplayNames[lang]!), findsOneWidget);
    }
  });

  testWidgets('label fields shown for custom cards only and save edits',
      (tester) async {
    await pumpParent(tester);
    await tester.tap(find.byKey(const ValueKey('mic-eat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rec-label-en')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('rec-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mic-custom-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('rec-label-ur')), 'کمبل');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('rec-save-labels')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final board = readBoard(tester);
    final custom =
        board.categories.first.cards.firstWhere((c) => c.id == 'custom-1');
    expect(custom.labels['ur'], 'کمبل');
  });
}
