import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no symbol SVG uses <style> or class= (flutter_svg has no CSS '
      'support: a class-styled shape has no fill/stroke of its own, so it '
      'renders solid black -- this is the bug users actually hit)', () {
    final symbolsDir = Directory('assets/symbols');
    expect(symbolsDir.existsSync(), isTrue,
        reason: 'flutter test must run from the repo root');
    final offenders = <String>[];
    for (final f in symbolsDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.svg')) continue;
      final content = f.readAsStringSync();
      if (content.contains('<style') || content.contains('class=')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'flutter_svg cannot style these shapes via CSS classes, so '
            'they render solid black. Inline the styles as direct '
            'fill/stroke attributes instead: $offenders');
  });
}
