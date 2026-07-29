import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/telemetry_service.dart';

void main() {
  test('default service is a no-op in the sideload channel (test env)',
      () async {
    // Must not throw despite no Firebase anywhere in the test environment.
    await TelemetryService().log(ParentEvent.languageChanged,
        params: {'language': 'ur'});
  });

  test('log sends snake_case names and params to the sink', () async {
    final names = <String>[];
    final params = <Map<String, String>>[];
    final t = TelemetryService(send: (n, p) async {
      names.add(n);
      params.add(p);
    });
    await t.log(ParentEvent.languageChanged, params: {'language': 'ar'});
    await t.log(ParentEvent.supporterRestored);
    expect(names, ['language_changed', 'supporter_restored']);
    expect(params.first, {'language': 'ar'});
    expect(params.last, isEmpty);
  });

  test('every ParentEvent maps to a name (closed taxonomy is total)',
      () async {
    final names = <String>[];
    final t = TelemetryService(send: (n, _) async => names.add(n));
    for (final event in ParentEvent.values) {
      await t.log(event);
    }
    expect(names, [
      'language_changed',
      'custom_card_added',
      'recording_created',
      'more_page_configured',
      'backup_created',
      'backup_restored',
      'insights_viewed',
      'supporter_purchased',
      'supporter_restored',
    ]);
  });

  test('a throwing sink never propagates', () async {
    final t = TelemetryService(send: (_, _) async => throw Exception('boom'));
    await t.log(ParentEvent.backupCreated); // must not throw
  });
}
