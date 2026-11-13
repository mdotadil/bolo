import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/policy_service.dart';

void main() {
  // rootBundle.loadString (the bundled-asset fallback) needs a Flutter test
  // binding even outside a testWidgets body.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_policy'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// A loopback endpoint nothing is listening on: bind a socket, read its
  /// port, then release it immediately. Connecting to that port fails fast
  /// (connection refused) with no DNS lookup and no dependency on real
  /// internet access — the failure path stays entirely offline.
  Future<String> unreachableEndpoint() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return 'http://127.0.0.1:$port/privacy.txt';
  }

  test('fetch failure falls back to the cached copy on disk', () async {
    File('${tmp.path}/privacy_cache.txt').writeAsStringSync('CACHED TEXT');
    final service = PolicyService(tmp, endpoint: await unreachableEndpoint());

    final text = await service.load();

    expect(text, 'CACHED TEXT');
  });

  test('fetch failure with no cache falls back to the bundled asset',
      () async {
    final service = PolicyService(tmp, endpoint: await unreachableEndpoint());

    final text = await service.load();

    final bundled = await File('assets/legal/privacy.txt').readAsString();
    expect(text, bundled);
    expect(File('${tmp.path}/privacy_cache.txt').existsSync(), isFalse);
  });

  test('successful fetch writes the cache and returns the fetched text',
      () async {
    final service = PolicyService(tmp,
        fetcher: (uri, timeout) async => 'FRESH TEXT FROM THE SERVER');

    final text = await service.load();
    expect(text, 'FRESH TEXT FROM THE SERVER');

    // The cache write is fire-and-forget (load() returns as soon as the
    // fetch succeeds, same "must never block on disk" pattern as
    // UsageStore.flush()), so poll briefly for its content to land rather
    // than assuming it's flushed and complete the instant load() resolves.
    final cacheFile = File('${tmp.path}/privacy_cache.txt');
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    String? seen;
    while (DateTime.now().isBefore(deadline)) {
      if (cacheFile.existsSync()) {
        seen = cacheFile.readAsStringSync();
        if (seen == 'FRESH TEXT FROM THE SERVER') break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(seen, 'FRESH TEXT FROM THE SERVER');
  });

  test('a slow fetch times out and falls back instead of hanging', () async {
    File('${tmp.path}/privacy_cache.txt').writeAsStringSync('CACHED TEXT');
    final service = PolicyService(tmp,
        fetcher: (uri, timeout) => Future.delayed(
            const Duration(seconds: 30), () => 'too slow'));

    final text = await service.load().timeout(const Duration(seconds: 10));

    expect(text, 'CACHED TEXT');
  });

  test('never throws even when the fetcher itself throws synchronously',
      () async {
    final service = PolicyService(tmp,
        fetcher: (uri, timeout) => throw StateError('boom'));

    final text = await service.load();

    expect(text, isNotEmpty);
  });

  test('default endpoint is the canonical hosted privacy URL', () {
    expect(PolicyService.canonicalPrivacyUrl,
        'https://mdotadil.vercel.app/bolo/privacy.txt');
    expect(PolicyService(tmp).endpoint, PolicyService.canonicalPrivacyUrl);
  });
}
