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
        return Board.fromJson(
            jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        // Keep the broken file for diagnosis, fall through to default.
        try {
          _file.renameSync('${_file.path}.corrupt');
        } catch (_) {}
      }
    }
    return Board.fromJson(jsonDecode(await _loadDefault()) as Map<String, dynamic>);
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
