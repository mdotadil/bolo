import 'dart:convert';
import 'dart:io';

class CardUsage {
  final int count;
  final DateTime firstUsed;
  final DateTime lastUsed;
  const CardUsage(
      {required this.count, required this.firstUsed, required this.lastUsed});
}

class UsageData {
  final Map<String, CardUsage> perCard;
  final Map<String, int> perDay;
  const UsageData({required this.perCard, required this.perDay});
}

/// On-device tap counters. Separate file from board.json on purpose: a corrupt
/// counter file must never take the board down, and taps write on a different
/// cadence (debounced) than board edits.
class UsageStore {
  UsageStore(this._dir, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const _flushEvery = 5;
  static const _keepDays = 90;

  final Directory _dir;
  final DateTime Function() _clock;
  final List<(String, DateTime)> _buffer = [];

  File get _file => File('${_dir.path}/usage.json');

  void recordTap(String cardId) {
    _buffer.add((cardId, _clock()));
    if (_buffer.length >= _flushEvery) {
      flush(); // fire and forget; speech must never wait on disk
    }
  }

  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final taps = List.of(_buffer);
    _buffer.clear();
    try {
      final raw = _readRaw();
      final perCard =
          (raw['perCard'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final perDay =
          (raw['perDay'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      for (final (id, at) in taps) {
        final prev = perCard[id] as Map<String, dynamic>?;
        perCard[id] = {
          'count': ((prev?['count'] as int?) ?? 0) + 1,
          'firstUsed': (prev?['firstUsed'] as String?) ?? at.toIso8601String(),
          'lastUsed': at.toIso8601String(),
        };
        final day = _dayKey(at);
        perDay[day] = ((perDay[day] as int?) ?? 0) + 1;
      }
      final cutoff = _clock().subtract(const Duration(days: _keepDays));
      perDay.removeWhere((day, _) => DateTime.parse(day).isBefore(cutoff));
      final tmpFile = File('${_file.path}.tmp');
      await tmpFile.writeAsString(
          jsonEncode({'perCard': perCard, 'perDay': perDay}),
          flush: true);
      tmpFile.renameSync(_file.path);
    } catch (_) {
      // Counters are best-effort; never let them break anything.
    }
  }

  Future<UsageData> load() async {
    final raw = _readRaw();
    try {
      final perCard = <String, CardUsage>{};
      ((raw['perCard'] as Map<String, dynamic>?) ?? {}).forEach((id, v) {
        final m = v as Map<String, dynamic>;
        perCard[id] = CardUsage(
          count: m['count'] as int,
          firstUsed: DateTime.parse(m['firstUsed'] as String),
          lastUsed: DateTime.parse(m['lastUsed'] as String),
        );
      });
      final perDay = <String, int>{};
      ((raw['perDay'] as Map<String, dynamic>?) ?? {})
          .forEach((day, n) => perDay[day] = n as int);
      return UsageData(perCard: perCard, perDay: perDay);
    } catch (_) {
      // Valid JSON but semantically malformed (wrong types, bad dates, etc.):
      // quarantine like a syntax error, never let a parse error escape.
      try {
        if (_file.existsSync()) _file.renameSync('${_file.path}.corrupt');
      } catch (_) {}
      return const UsageData(perCard: {}, perDay: {});
    }
  }

  Map<String, dynamic> _readRaw() {
    if (!_file.existsSync()) return {};
    try {
      return jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      try {
        _file.renameSync('${_file.path}.corrupt');
      } catch (_) {}
      return {};
    }
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
