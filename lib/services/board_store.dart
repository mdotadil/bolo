import 'dart:convert';
import 'dart:io';
import '../models/board.dart';

class BoardStore {
  BoardStore(this._dir, {required this._loadDefault});

  final Directory _dir;
  final Future<String> Function() _loadDefault;

  File get _file => File('${_dir.path}/board.json');

  Directory get photosDir =>
      Directory('${_dir.path}/photos')..createSync(recursive: true);

  Future<Board> load() async {
    if (_file.existsSync()) {
      try {
        final raw =
            jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
        final fileVersion = raw['version'] as int? ?? 1;
        if (fileVersion >= Board.currentVersion) return Board.fromJson(raw);
        final migrated = _migrate(raw,
            Board.fromJson(jsonDecode(await _loadDefault()) as Map<String, dynamic>));
        await save(migrated);
        return migrated;
      } catch (_) {
        // Keep the broken file for diagnosis, fall through to default.
        try {
          _file.renameSync('${_file.path}.corrupt');
        } catch (_) {}
      }
    }
    return Board.fromJson(jsonDecode(await _loadDefault()) as Map<String, dynamic>);
  }

  /// v1/v2 → v3: fold each category's on-disk `moreCards` (from the removed
  /// More-page feature) into `cards` (append at end, preserving order),
  /// backfill the default's own former more-cards for a category that never
  /// had any of its own (a pre-v2 file), and merge every shipped label/name
  /// language set (ur/ar/fr/es) from the bundled default by id. Never changes
  /// existing card order, hidden flags, or custom cards. `raw` is read
  /// directly because BoardCategory no longer has a moreCards field to parse
  /// it into.
  Board _migrate(Map<String, dynamic> raw, Board def) {
    final defCats = {for (final c in def.categories) c.id: c};
    final rawCats = raw['categories'] as List;
    final hadOwnMoreCards = <String, bool>{};
    final foldedCats = rawCats.map((c) {
      final cat = Map<String, dynamic>.from(c as Map<String, dynamic>);
      final more = cat.remove('moreCards') as List?;
      hadOwnMoreCards[cat['id'] as String] = more != null && more.isNotEmpty;
      if (more != null && more.isNotEmpty) {
        cat['cards'] = [...(cat['cards'] as List), ...more];
      }
      return cat;
    }).toList();
    final board = Board.fromJson({...raw, 'categories': foldedCats});

    return board.copyWith(categories: [
      for (final cat in board.categories)
        _mergeCategory(cat, hadOwnMoreCards[cat.id] ?? false, defCats[cat.id]),
    ]);
  }

  // Cards that used to live on the removed More page, keyed by category id.
  // Used only to backfill a category that had no moreCards of its own on
  // disk (e.g. a pre-v2 file), so it still gains them -- exactly as it would
  // have if the device had upgraded through v2 first. A historical snapshot
  // taken when the More page was removed; never add to this for new
  // features -- new cards belong directly in default_board.json's `cards`.
  static const _legacyMoreCardIds = {
    'wants': ['want-eat', 'want-water'],
    'help': ['need-toilet', 'help-fast'],
  };

  BoardCategory _mergeCategory(
      BoardCategory cat, bool hadOwnMoreCards, BoardCategory? def) {
    if (def == null) return cat;
    final defCards = {for (final c in def.cards) c.id: c};
    SymbolCard mergeLabels(SymbolCard card) => defCards[card.id] == null
        ? card
        : card.copyWith(labels: {
            ...defCards[card.id]!.labels,
            ...card.labels,
          });

    // The file's own more-cards (already folded into cat.cards above) always
    // win. Only when the file had none at all do we backfill the default's
    // historical more-cards for this category, matching what v1->v2 used to
    // do automatically.
    final existingIds = {for (final c in cat.cards) c.id};
    final backfill = hadOwnMoreCards
        ? const <SymbolCard>[]
        : [
            for (final id in _legacyMoreCardIds[cat.id] ?? const <String>[])
              if (!existingIds.contains(id)) defCards[id]!,
          ];

    return BoardCategory(
      id: cat.id,
      names: {...def.names, ...cat.names},
      cards: [for (final c in cat.cards) mergeLabels(c), ...backfill],
    );
  }

  Future<void> save(Board board) async {
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(board.toJson()), flush: true);
      tmp.renameSync(_file.path);
    } catch (_) {
      // Persistence must never take down the app; in-memory board stays valid.
    }
  }
}
