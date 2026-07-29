import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/parent_screen.dart';
import 'package:bolo/features/parent/photo_picker.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/recording_player.dart';
import '../support/fakes.dart';

const _json =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}}]}]}';

class FakePicker implements PhotoPicker {
  @override
  Future<String?> pickPhoto(
      {required bool fromCamera, required Directory saveDir}) async {
    final f = File('${saveDir.path}/fake.jpg')..writeAsBytesSync([1, 2, 3]);
    return f.path;
  }
}

/// Returns null the first [failCount] calls (covers both user-cancel and the
/// picker/copy-throws-so-we-return-null path), then behaves like [FakePicker].
class FlakyPicker implements PhotoPicker {
  FlakyPicker(this.failCount);
  final int failCount;
  int _calls = 0;

  @override
  Future<String?> pickPhoto(
      {required bool fromCamera, required Directory saveDir}) async {
    _calls++;
    if (_calls <= failCount) return null;
    final f = File('${saveDir.path}/fake.jpg')..writeAsBytesSync([1, 2, 3]);
    return f.path;
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_add'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget app({PhotoPicker? picker}) => ProviderScope(overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(FakeTts()),
        recordingPlayerProvider.overrideWithValue(FakePlayer()),
        docsDirProvider.overrideWithValue(tmp),
        photoPickerProvider.overrideWithValue(picker ?? FakePicker()),
      ], child: const MaterialApp(home: ParentScreen()));

  Future<void> pumpParentAndOpenSheet(WidgetTester tester,
      {PhotoPicker? picker}) async {
    await tester.pumpWidget(app(picker: picker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();
  }

  Board readBoard(WidgetTester tester) {
    final ctx = tester.element(find.byType(ParentScreen));
    return ProviderScope.containerOf(ctx).read(boardNotifierProvider).value!;
  }

  testWidgets('add card flow appends a custom card with photo', (tester) async {
    await pumpParentAndOpenSheet(tester);
    await tester.enterText(
        find.byKey(const ValueKey('add-card-label')), 'blanket');
    await tester.tap(find.byKey(const ValueKey('add-card-gallery')));
    await tester.pumpAndSettle();

    final board = readBoard(tester);
    final card = board.categories.single.cards.last;
    expect(card.labels['en'], 'blanket');
    expect(card.photoPath, isNotNull);
    expect(File(card.photoPath!).existsSync(), isTrue);
  });

  testWidgets('empty label does not add a card and leaves the sheet open',
      (tester) async {
    await pumpParentAndOpenSheet(tester);
    // Leave the label blank (whitespace only) and try to pick anyway.
    await tester.enterText(
        find.byKey(const ValueKey('add-card-label')), '   ');
    await tester.tap(find.byKey(const ValueKey('add-card-gallery')));
    await tester.pumpAndSettle();

    // Sheet is still open: its label field is still in the tree.
    expect(find.byKey(const ValueKey('add-card-label')), findsOneWidget);

    final board = readBoard(tester);
    expect(board.categories.single.cards, hasLength(1));
  });

  testWidgets(
      'cancelled (or failed) picker does not add a card and leaves the sheet '
      'open; a subsequent pick still works', (tester) async {
    await pumpParentAndOpenSheet(tester, picker: FlakyPicker(1));
    await tester.enterText(
        find.byKey(const ValueKey('add-card-label')), 'blanket');
    await tester.tap(find.byKey(const ValueKey('add-card-gallery')));
    await tester.pumpAndSettle();

    // First pick returned null (cancel/error): sheet stays open, no card added.
    expect(find.byKey(const ValueKey('add-card-label')), findsOneWidget);
    expect(readBoard(tester).categories.single.cards, hasLength(1));

    // Retry from the still-open sheet: second pick succeeds.
    await tester.tap(find.byKey(const ValueKey('add-card-gallery')));
    await tester.pumpAndSettle();

    final card = readBoard(tester).categories.single.cards.last;
    expect(card.labels['en'], 'blanket');
    expect(card.photoPath, isNotNull);
    expect(File(card.photoPath!).existsSync(), isTrue);
  });

}
