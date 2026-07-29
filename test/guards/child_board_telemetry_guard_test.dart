import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nothing under lib/features/board/ references telemetry', () {
    final boardDir = Directory('lib/features/board');
    expect(boardDir.existsSync(), isTrue,
        reason: 'flutter test must run from the repo root');
    final offenders = <String>[];
    for (final f in boardDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.readAsStringSync().contains('telemetry_service')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'The child board must stay event-free. '
            'Move the instrumentation to a parent-mode call site: $offenders');
  });
}
