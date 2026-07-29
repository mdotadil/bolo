import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/parent_screen.dart';
import 'package:bolo/services/app_channel.dart';
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_channel'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('channel-gated parent widgets match the built channel',
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

    final store = appChannel == AppChannel.store;
    final matcher = store ? findsOneWidget : findsNothing;
    // skipOffstage: false — ParentScreen's ListView is taller than the
    // default 800x600 test surface, so these store-channel widgets (near
    // the bottom) sit outside the viewport's cache extent. The default
    // skipOffstage:true would report them absent even when mounted; this
    // check is about existence in the tree, not on-screen visibility.
    expect(
        find.byKey(const ValueKey('diagnostics-toggle'), skipOffstage: false),
        matcher);
    expect(find.byKey(const ValueKey('supporter-buy'), skipOffstage: false),
        matcher);
    expect(
        find.byKey(const ValueKey('supporter-restore'), skipOffstage: false),
        matcher);
    if (!store) {
      // The sideload family build must show everything unlocked: the
      // insights export never renders a lock outside the store channel.
      expect(find.byIcon(Icons.lock_outline, skipOffstage: false),
          findsNothing);
    }
  });
}
