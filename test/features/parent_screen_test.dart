import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/parent_screen.dart';
import 'package:bolo/features/parent/record_sheet.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/recording_player.dart';
import '../support/fakes.dart';

const _json =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat","ur":"کھانا","ar":"أكل"}},{"id":"drink","labels":{"en":"drink"}}],'
    '"moreCards":[{"id":"phrase-1","labels":{"en":"I need the toilet"}}]}]}';

void main() {
  late Directory tmp;
  late FakeTts tts;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_parent');
    tts = FakeTts();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget app() => ProviderScope(overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(tts),
        recordingPlayerProvider.overrideWithValue(FakePlayer()),
        docsDirProvider.overrideWithValue(tmp),
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

  // BoardStore.save()/load() do real dart:io file I/O. A plain testWidgets
  // body runs inside a FakeAsync zone, and any async chain that starts there
  // has its post-`await` continuations routed through FakeAsync's own fake
  // microtask queue -- real disk I/O never signals completion back into
  // that queue, so the awaited save inside onChangeEnd/toggleHidden would
  // never resume. `tester.runAsync` forks a zone that routes
  // scheduleMicrotask/createTimer straight to the real root zone, but only
  // for work that happens (synchronously, or via async chains kicked off)
  // *inside* its callback -- so the gesture that triggers the save, the
  // real wait for it to land, and the disk verification all have to happen
  // inside the SAME runAsync call. Calling tester.pump()/pumpAndSettle()
  // from inside that callback is a known deadlock (those drive the fake
  // clock machinery, which is exactly what this zone has escaped), so we
  // only call tester.tap() (no implicit pump) and a bare Future.delayed
  // inside runAsync, then leave it before touching the widget tree again.
  testWidgets(
      'toggle switch through widget persists to disk, verified via a fresh store',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final reloaded = await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('switch-eat')));
      // Give the real event loop time to actually land the disk write
      // (BoardStore.save's writeAsString + renameSync) before we read it
      // back with a fresh store instance.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final fresh = BoardStore(tmp, loadDefault: () async => _json);
      return fresh.load();
    });

    final eatCard =
        reloaded!.categories.single.cards.firstWhere((c) => c.id == 'eat');
    expect(eatCard.hidden, isTrue);
  });

  testWidgets(
      'slider onChangeEnd persists and configures speech rate exactly once',
      (tester) async {
    final tts = FakeTts();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(tts),
        recordingPlayerProvider.overrideWithValue(FakePlayer()),
        docsDirProvider.overrideWithValue(tmp),
      ],
      child: const MaterialApp(home: ParentScreen()),
    ));
    await tester.pumpAndSettle();
    // build() already configured the initial rate (0.45); isolate the
    // calls made by the gesture we're about to simulate.
    tts.calls.clear();

    final slider =
        tester.widget<Slider>(find.byKey(const ValueKey('rate-slider')));

    final board = await tester.runAsync(() async {
      slider.onChanged!(0.6);
      slider.onChangeEnd!(0.6);
      // Let the real save() + TTS reconfigure land before we inspect state.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final ctx = tester.element(find.byType(ParentScreen));
      return ProviderScope.containerOf(ctx).read(boardNotifierProvider).value!;
    });

    expect(board!.speechRate, 0.6);
    expect(tts.calls.where((c) => c == 'rate:0.6').length, 1);
  });

  testWidgets('language dropdown lists all five languages, persists, re-labels',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-switch')));
    await tester.pumpAndSettle();
    for (final lang in supportedLanguages) {
      expect(find.text(languageDisplayNames[lang]!), findsWidgets,
          reason: 'dropdown missing $lang');
    }
    await tester.runAsync(() async {
      await tester.tap(find.text('العربية').last);
      await tester.pumpAndSettle();
    });
    final ctx = tester.element(find.byType(ParentScreen));
    final board =
        ProviderScope.containerOf(ctx).read(boardNotifierProvider).value!;
    expect(board.activeLanguage, 'ar');
    expect(find.text('أكل'), findsOneWidget); // eat's ar label from fixture
  });

  testWidgets('voice-unavailable note appears only when the active voice is missing',
      (tester) async {
    tts.unavailable.add('ar-SA'); // FakeTts set from test/support/fakes.dart
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-unavailable-note')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('language-switch')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('العربية').last);
      await tester.pumpAndSettle();
    });
    expect(find.byKey(const ValueKey('voice-unavailable-note')), findsOneWidget);
    expect(find.textContaining('العربية voice not available'), findsOneWidget);
  });

  testWidgets('divider row separates main and more sections', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-divider')), findsOneWidget);
    // divider sits after the main cards, before phrase-1's row
    final dividerY =
        tester.getTopLeft(find.byKey(const ValueKey('more-divider'))).dy;
    final phraseY =
        tester.getTopLeft(find.byKey(const ValueKey('row-phrase-1'))).dy;
    expect(dividerY, lessThan(phraseY));
  });

  group('reorder index translation', () {
    // mainCount = 2 → indices: 0,1 = main; 2 = divider; 3.. = more
    test('within main', () {
      expect(translateReorder(2, 0, 1), (ReorderAction.mainReorder, 0, 1));
    });
    test('within more', () {
      expect(translateReorder(2, 3, 4), (ReorderAction.moreReorder, 0, 1));
    });
    test('main to more (crossing down past divider)', () {
      expect(translateReorder(2, 0, 4), (ReorderAction.moveToMore, 0, 0));
    });
    test('more to main (crossing up past divider)', () {
      expect(translateReorder(2, 3, 1), (ReorderAction.moveToMain, 0, 1));
    });
    test('dragging the divider itself is a no-op', () {
      expect(translateReorder(2, 2, 0), (ReorderAction.none, 0, 0));
    });
  });
}
