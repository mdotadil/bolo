import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/parent/about_page.dart';
import 'package:bolo/services/policy_service.dart';

const _sampleDoc = '# Bolo Privacy\n'
    '\n'
    'Some intro paragraph about the app.\n'
    '\n'
    '# If you got Bolo from Google Play\n'
    '\n'
    '- Crash reports, so bugs can get fixed.\n'
    '- A short list of parent actions.\n'
    '\n'
    '# Questions\n'
    '\n'
    'Email mdotadil@gmail.com with any questions.\n';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_about'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('renders headings and bullets from a sample document',
      (tester) async {
    final service = PolicyService(tmp,
        fetcher: (uri, timeout) async => _sampleDoc);

    await tester.pumpWidget(MaterialApp(
      home: AboutPage(policyService: service),
    ));
    // load() resolves as soon as the fetch succeeds — the cache write to
    // disk is fire-and-forget in the background (see PolicyService.load),
    // so a plain pumpAndSettle is enough; no real-I/O wait needed here.
    await tester.pumpAndSettle();

    expect(find.text('About and privacy'), findsOneWidget);
    expect(find.text('Bolo Privacy'), findsOneWidget);
    expect(find.text('If you got Bolo from Google Play'), findsOneWidget);
    expect(find.text('Questions'), findsOneWidget);
    expect(find.textContaining('Crash reports, so bugs can get fixed.'),
        findsOneWidget);
    expect(find.textContaining('A short list of parent actions.'),
        findsOneWidget);
    expect(find.textContaining('Some intro paragraph about the app.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('about-loading')), findsNothing);
  });

  testWidgets('shows a plain loading state before the text resolves',
      (tester) async {
    final completer = Completer<String>();
    final service = PolicyService(tmp,
        fetcher: (uri, timeout) => completer.future);

    await tester.pumpWidget(MaterialApp(
      home: AboutPage(policyService: service),
    ));
    await tester.pump();

    expect(find.text('Loading…'), findsOneWidget);

    completer.complete(_sampleDoc);
    await tester.pumpAndSettle();
    expect(find.text('Loading…'), findsNothing);
  });
}
