import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/parent_screen.dart';
import 'package:bolo/features/parent/photo_picker.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/speech_service.dart';

const _json =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}}]}]}';

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

class FakePicker implements PhotoPicker {
  @override
  Future<String?> pickPhoto(
      {required bool fromCamera, required Directory saveDir}) async {
    final f = File('${saveDir.path}/fake.jpg')..writeAsBytesSync([1, 2, 3]);
    return f.path;
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_add'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('add card flow appends a custom card with photo', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      boardStoreProvider.overrideWithValue(
          BoardStore(tmp, loadDefault: () async => _json)),
      ttsProvider.overrideWithValue(FakeTts()),
      photoPickerProvider.overrideWithValue(FakePicker()),
    ], child: const MaterialApp(home: ParentScreen())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('add-card-label')), 'blanket');
    await tester.tap(find.byKey(const ValueKey('add-card-gallery')));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(ParentScreen));
    final board =
        ProviderScope.containerOf(ctx).read(boardNotifierProvider).value!;
    final card = board.categories.single.cards.last;
    expect(card.labels['en'], 'blanket');
    expect(card.photoPath, isNotNull);
    expect(File(card.photoPath!).existsSync(), isTrue);
  });
}
