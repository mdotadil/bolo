import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/settings_store.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_settings'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('defaults when no file exists: telemetry on, supporter locked',
      () async {
    final s = await SettingsStore(tmp).load();
    expect(s.telemetryEnabled, isTrue);
    expect(s.supporterUnlocked, isFalse);
  });

  test('save/load round-trips both fields atomically', () async {
    final store = SettingsStore(tmp);
    await store.save(
        const Settings(telemetryEnabled: false, supporterUnlocked: true));
    final s = await store.load();
    expect(s.telemetryEnabled, isFalse);
    expect(s.supporterUnlocked, isTrue);
    expect(File('${tmp.path}/settings.json.tmp').existsSync(), isFalse);
  });

  test('missing keys fall back to defaults (forward compatibility)',
      () async {
    File('${tmp.path}/settings.json').writeAsStringSync('{}');
    final s = await SettingsStore(tmp).load();
    expect(s.telemetryEnabled, isTrue);
    expect(s.supporterUnlocked, isFalse);
  });

  test('corrupt settings.json is set aside and defaults returned', () async {
    File('${tmp.path}/settings.json').writeAsStringSync('{not json');
    final s = await SettingsStore(tmp).load();
    expect(s.telemetryEnabled, isTrue);
    expect(File('${tmp.path}/settings.json.corrupt').existsSync(), isTrue);
  });

  test('notifier loads, mutates, persists', () async {
    final container = ProviderContainer(overrides: [
      settingsStoreProvider.overrideWithValue(SettingsStore(tmp)),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await container.read(settingsProvider.notifier).setTelemetryEnabled(false);
    await container.read(settingsProvider.notifier).setSupporterUnlocked(true);
    expect(container.read(settingsProvider).value!.telemetryEnabled, isFalse);
    final raw = jsonDecode(File('${tmp.path}/settings.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(raw['telemetryEnabled'], false);
    expect(raw['supporterUnlocked'], true);
  });
}
