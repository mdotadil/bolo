import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

/// A function that performs the actual network fetch: GET [uri], bounded by
/// [timeout], returning the response body as text. Exists as a seam so tests
/// can simulate success/failure without touching a real socket; production
/// code uses [PolicyService._defaultFetch] (plain `dart:io` `HttpClient`, no
/// new package).
typedef PolicyFetcher = Future<String> Function(Uri uri, Duration timeout);

/// Fetches the privacy policy text with a resolution chain that never
/// throws:
///
///  1. HTTPS GET of [endpoint] (5-second timeout). On success, the text is
///     returned immediately and cached to `<docsDir>/privacy_cache.txt` in
///     the background (fire-and-forget — a slow or failing disk write must
///     never delay showing the parent text they already have).
///  2. On any failure (no network, timeout, bad status, ...), fall back to
///     the cached copy on disk, if one exists.
///  3. If there is no cache either, fall back to the bundled offline asset
///     (`assets/legal/privacy.txt`) via `rootBundle.loadString`.
///
/// The network is touched ONLY when [load] is called — i.e. only when a
/// parent opens the About and privacy page — never at app start.
class PolicyService {
  PolicyService(this._docsDir,
      {this.endpoint = canonicalPrivacyUrl, PolicyFetcher? fetcher})
      : _fetcher = fetcher ?? _defaultFetch;

  /// The hosted source of truth. Adil keeps `docs/legal/privacy.txt` (this
  /// repo) in sync with this URL by hand; `assets/legal/privacy.txt` is the
  /// offline fallback bundled into the app.
  static const canonicalPrivacyUrl =
      'https://mdotadil.vercel.app/bolo/privacy.txt';

  static const _bundledAssetPath = 'assets/legal/privacy.txt';
  static const _timeout = Duration(seconds: 5);

  final Directory _docsDir;
  final String endpoint;
  final PolicyFetcher _fetcher;

  File get _cacheFile => File('${_docsDir.path}/privacy_cache.txt');

  Future<String> load() async {
    try {
      // The outer .timeout applies regardless of which fetcher is in play:
      // the default one already bounds itself internally, but an injected
      // (e.g. test) fetcher that ignores its own [timeout] argument must
      // not be able to make `load()` hang.
      final text =
          await _fetcher(Uri.parse(endpoint), _timeout).timeout(_timeout);
      // Fire-and-forget, same pattern as UsageStore.flush(): the parent
      // already has the text they asked for, so a slow or failing disk
      // write must never delay (or break) showing it.
      unawaited(_writeCache(text));
      return text;
    } catch (_) {
      // Any failure (offline, timeout, bad status, ...) falls through to
      // the cache, then the bundled asset. Never propagate to the caller.
    }

    try {
      if (_cacheFile.existsSync()) {
        return await _cacheFile.readAsString();
      }
    } catch (_) {
      // Corrupt/unreadable cache: fall through to the bundled asset.
    }

    return rootBundle.loadString(_bundledAssetPath);
  }

  Future<void> _writeCache(String text) async {
    try {
      await _cacheFile.writeAsString(text, flush: true);
    } catch (_) {
      // Cache write is best-effort: still return the freshly fetched text
      // even if this phone can't persist it (e.g. storage full).
    }
  }

  static Future<String> _defaultFetch(Uri uri, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        throw HttpException(
            'Unexpected status ${response.statusCode}', uri: uri);
      }
      return await response.transform(utf8.decoder).join().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }
}
