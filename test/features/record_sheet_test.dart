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

/// Real recorders create the file at `path` the instant recording starts;
/// the shared `FakeRecorder` deliberately does no I/O at all (so unrelated
/// callers like recording_player_test.dart stay side-effect free). This
/// subclass adds that one behavior locally, only for the tests here that
/// exercise the tmp-then-rename / orphaned-tmp-file-cleanup flow end to end.
class _FileCreatingRecorder extends FakeRecorder {
  @override
  Future<void> start(String path) async {
    File(path).createSync(recursive: true);
    await super.start(path);
  }
}

void main() {
  late Directory tmp;
  late FakeRecorder fakeRecorder;
  late FakePlayer fakePlayer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_record');
    fakeRecorder = _FileCreatingRecorder();
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

  testWidgets(
      'recording temp path keeps the .m4a extension '
      '(AVAudioRecorder infers container from extension)', (tester) async {
    await pumpParent(tester);
    await tester.tap(find.byKey(const ValueKey('mic-eat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rec-start-ur')));
    await tester.pump();

    // record_ios calls AVAudioRecorder(url:settings:) directly, and
    // AVAudioRecorder infers the output *container* format from the URL's
    // path extension. A `.tmp` extension there produced a file AVPlayer
    // could not parse even after the later rename to `.m4a` (the bug this
    // pins down). The path handed to the recorder at start-time must
    // already carry a real audio extension.
    final startCall =
        fakeRecorder.calls.firstWhere((c) => c.startsWith('start:'));
    final startPath = startCall.substring('start:'.length);
    expect(startPath, endsWith('.m4a'),
        reason: 'AVAudioRecorder infers its container format from the '
            'path extension -- anything other than a real audio '
            'extension (e.g. .tmp) yields an unparseable recording');

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
      // Scoped to the sheet itself: Task 10's parent-mode language dropdown
      // also renders the active language's display name (e.g. "English") on
      // the page underneath, so an unscoped find.text would double-count.
      expect(
          find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text(languageDisplayNames[lang]!)),
          findsOneWidget);
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

  testWidgets(
      'dismissing the sheet via the barrier while recording stops the mic, '
      'deletes the orphaned tmp file, and leaves the card unchanged',
      (tester) async {
    await pumpParent(tester);
    await tester.tap(find.byKey(const ValueKey('mic-eat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rec-start-ur')));
    await tester.pump();
    expect(find.byKey(const ValueKey('rec-stop-ur')), findsOneWidget);

    // Dismiss via the modal barrier (tap outside the sheet) -- not rec-close
    // -- the route that used to leak the mic because dispose() never
    // stopped the recorder.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(fakeRecorder.isRecording, isFalse);
    final recordingsDir = Directory('${tmp.path}/recordings');
    final leftoverTmp = recordingsDir.existsSync()
        ? recordingsDir
            .listSync()
            .where((f) => f.path.endsWith('.tmp.m4a'))
            .toList()
        : const <FileSystemEntity>[];
    expect(leftoverTmp, isEmpty);
    final board = readBoard(tester);
    final eat = board.categories.first.cards.firstWhere((c) => c.id == 'eat');
    expect(eat.recordings, isEmpty);
  });
}
