import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/parent_screen.dart';
import 'package:bolo/services/audio_recorder.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/recording_player.dart';
import 'package:bolo/services/settings_store.dart';
import '../support/fakes.dart';

const _json = '{"version":2,"speechRate":0.45,"activeLanguage":"en",'
    '"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}}]}]}';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_diag'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('diagnostics toggle is absent in the sideload channel',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(FakeTts()),
        recordingPlayerProvider.overrideWithValue(FakePlayer()),
        recorderProvider.overrideWithValue(FakeRecorder()),
        docsDirProvider.overrideWithValue(tmp),
        settingsStoreProvider.overrideWithValue(SettingsStore(tmp)),
      ],
      child: const MaterialApp(home: ParentScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('diagnostics-toggle')), findsNothing);
  });
}
