import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/usage_store.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_usage'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File file() => File('${tmp.path}/usage.json');

  test('recordTap buffers; 5th tap auto-flushes one write', () async {
    final store = UsageStore(tmp, clock: () => DateTime(2026, 7, 28, 10));
    for (var i = 0; i < 4; i++) {
      store.recordTap('eat');
    }
    expect(file().existsSync(), isFalse); // still buffered
    store.recordTap('water');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(file().existsSync(), isTrue);
    final data = await store.load();
    expect(data.perCard['eat']!.count, 4);
    expect(data.perCard['water']!.count, 1);
    expect(data.perDay['2026-07-28'], 5);
  });

  test('explicit flush writes buffered taps', () async {
    final store = UsageStore(tmp, clock: () => DateTime(2026, 7, 28));
    store.recordTap('eat');
    await store.flush();
    expect((await store.load()).perCard['eat']!.count, 1);
  });

  test('counts accumulate across instances and firstUsed survives', () async {
    final s1 = UsageStore(tmp, clock: () => DateTime(2026, 7, 1));
    s1.recordTap('eat');
    await s1.flush();
    final s2 = UsageStore(tmp, clock: () => DateTime(2026, 7, 28));
    s2.recordTap('eat');
    await s2.flush();
    final u = (await s2.load()).perCard['eat']!;
    expect(u.count, 2);
    expect(u.firstUsed, DateTime(2026, 7, 1));
    expect(u.lastUsed, DateTime(2026, 7, 28));
  });

  test('perDay entries older than 90 days are pruned on flush', () async {
    final s1 = UsageStore(tmp, clock: () => DateTime(2026, 1, 1));
    s1.recordTap('eat');
    await s1.flush();
    final s2 = UsageStore(tmp, clock: () => DateTime(2026, 7, 28));
    s2.recordTap('eat');
    await s2.flush();
    final data = await s2.load();
    expect(data.perDay.containsKey('2026-01-01'), isFalse);
    expect(data.perDay['2026-07-28'], 1);
  });

  test('corrupt usage.json is set aside and counting starts fresh', () async {
    file().writeAsStringSync('{not json');
    final store = UsageStore(tmp, clock: () => DateTime(2026, 7, 28));
    store.recordTap('eat');
    await store.flush();
    expect((await store.load()).perCard['eat']!.count, 1);
    expect(File('${tmp.path}/usage.json.corrupt').existsSync(), isTrue);
  });
}
