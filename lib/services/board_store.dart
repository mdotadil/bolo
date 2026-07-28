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
        final board = Board.fromJson(raw);
        final fileVersion = raw['version'] as int? ?? 1;
        if (fileVersion >= Board.currentVersion) return board;
        final migrated = _migrate(board,
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

  /// v1 → v2: merge every shipped label/name language set (ur/ar/fr/es) and
  /// default More cards from the bundled default board, by id. Never changes
  /// card order, hidden flags, or custom cards. Board.fromJson already
  /// stamped version/activeLanguage defaults.
  Board _migrate(Board old, Board def) {
    final defCats = {for (final c in def.categories) c.id: c};
    return old.copyWith(categories: [
      for (final cat in old.categories)
        _mergeCategory(cat, defCats[cat.id]),
    ]);
  }

  BoardCategory _mergeCategory(BoardCategory cat, BoardCategory? def) {
    if (def == null) return cat;
    final defCards = {for (final c in [...def.cards, ...def.moreCards]) c.id: c};
    List<SymbolCard> mergeLabels(List<SymbolCard> cards) => [
          for (final card in cards)
            defCards[card.id] == null
                ? card
                : card.copyWith(labels: {
                    ...defCards[card.id]!.labels,
                    ...card.labels,
                  }),
        ];
    return BoardCategory(
      id: cat.id,
      names: {...def.names, ...cat.names},
      cards: mergeLabels(cat.cards),
      moreCards:
          cat.moreCards.isEmpty ? def.moreCards : mergeLabels(cat.moreCards),
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
