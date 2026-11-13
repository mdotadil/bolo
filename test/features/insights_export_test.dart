import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/insights_section.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/recording_player.dart';
import 'package:bolo/services/settings_store.dart';
import '../support/fakes.dart';

const _json =
    '{"speechRate":0.45,"activeLanguage":"en","categories":['
    '{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}},{"id":"water","labels":{"en":"water"}}]}]}';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_export'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('sideload: export button is present and unlocked',
      (tester) async {
    final now = DateTime.now();
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    File('${tmp.path}/usage.json').writeAsStringSync(jsonEncode({
      'perCard': {
        'eat': {
          'count': 7,
          'firstUsed': now.subtract(const Duration(days: 3)).toIso8601String(),
          'lastUsed': now.toIso8601String(),
        },
      },
      'perDay': {day(now): 5},
    }));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        docsDirProvider.overrideWithValue(tmp),
        ttsProvider.overrideWithValue(FakeTts()),
        recordingPlayerProvider.overrideWithValue(FakePlayer()),
        settingsStoreProvider.overrideWithValue(SettingsStore(tmp)),
      ],
      child: const MaterialApp(home: Scaffold(body: InsightsSection())),
    ));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('insights-export')), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });
}
