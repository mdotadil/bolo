import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/insights_section.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/recording_player.dart';
import '../support/fakes.dart';

const _json =
    '{"speechRate":0.45,"activeLanguage":"en","categories":['
    '{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}},{"id":"water","labels":{"en":"water"}}]}]}';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_insights'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('insights renders week count, top words, new words',
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
        'water': {
          'count': 2,
          'firstUsed':
              now.subtract(const Duration(days: 40)).toIso8601String(),
          'lastUsed': now.toIso8601String(),
        },
      },
      'perDay': {day(now): 5, day(now.subtract(const Duration(days: 2))): 4},
    }));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        docsDirProvider.overrideWithValue(tmp),
        ttsProvider.overrideWithValue(FakeTts()),
        recordingPlayerProvider.overrideWithValue(FakePlayer()),
      ],
      child: const MaterialApp(home: Scaffold(body: InsightsSection())),
    ));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('insights-week-count')), findsOneWidget);
    expect(find.textContaining('9'), findsOneWidget); // 5 + 4 this week
    expect(find.text('eat'), findsWidgets); // top word row
    expect(find.textContaining('7'), findsOneWidget); // its count
    expect(find.text('eat'), findsWidgets); // new word chip too (firstUsed 3d)
  });
}
