import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Forbidden substrings (case-insensitive): anything wider than the original
// 'telemetry_service' check, so a stray import of firebase/analytics
// tooling directly into the child board also trips the guard.
const _forbidden = ['telemetry_service', 'telemetry', 'firebase', 'analytics'];

void main() {
  test('nothing under lib/features/board/ references telemetry or analytics',
      () {
    final boardDir = Directory('lib/features/board');
    expect(boardDir.existsSync(), isTrue,
        reason: 'flutter test must run from the repo root');
    final offenders = <String>[];
    for (final f in boardDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final content = f.readAsStringSync().toLowerCase();
      if (_forbidden.any(content.contains)) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'The child board must stay event-free. '
            'Move the instrumentation to a parent-mode call site: $offenders');
  });
}
