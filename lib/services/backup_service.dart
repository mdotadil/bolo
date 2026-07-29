import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import '../models/board.dart';

/// Creates and restores `.bolo` backups: a zip of board.json, usage.json,
/// photos/ and recordings/. Restore is staged: nothing in the live docs dir
/// changes until the archive has fully validated.
class BackupService {
  BackupService(this._docsDir);
  final Directory _docsDir;

  Future<File> createBackup() async {
    final archive = Archive();
    void addFile(String relative) {
      final f = File('${_docsDir.path}/$relative');
      if (!f.existsSync()) return;
      final bytes = f.readAsBytesSync();
      archive.addFile(ArchiveFile(relative, bytes.length, bytes));
    }

    addFile('board.json');
    addFile('usage.json');
    for (final dir in ['photos', 'recordings']) {
      final d = Directory('${_docsDir.path}/$dir');
      if (!d.existsSync()) continue;
      for (final f in d.listSync().whereType<File>()) {
        addFile('$dir/${f.uri.pathSegments.last}');
      }
    }

    final now = DateTime.now();
    final name = 'bolo-backup-${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}.bolo';
    final out = File('${Directory.systemTemp.path}/$name');
    out.writeAsBytesSync(ZipEncoder().encode(archive));
    return out;
  }

  Future<void> restore(File backupFile) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(backupFile.readAsBytesSync());
    } catch (_) {
      throw const FormatException('Not a Bolo backup file.');
    }

    final boardEntry = archive.findFile('board.json');
    if (boardEntry == null) {
      throw const FormatException('Backup contains no board.');
    }
    final Map<String, dynamic> raw;
    try {
      raw = jsonDecode(utf8.decode(boardEntry.content)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Backup board is not readable.');
    }
    // Reject backups written by a future Bolo version: this build doesn't
    // know that schema and Board.fromJson would silently drop fields.
    final v = raw['version'] as int? ?? 1;
    if (v > Board.currentVersion) {
      throw const FormatException(
          'Backup was made by a newer version of Bolo.');
    }
    final Board board;
    try {
      board = Board.fromJson(raw);
    } catch (_) {
      throw const FormatException('Backup board is not readable.');
    }
    if (board.categories.isEmpty) {
      throw const FormatException('Backup board has no categories.');
    }

    // Stage everything first; only touch the live dir after full success.
    final staging = Directory.systemTemp.createTempSync('bolo_restore');
    try {
      for (final entry in archive.files.where((f) => f.isFile)) {
        final name = entry.name;
        // Reject zip-slip entries: only the exact backup layout is trusted.
        final safe = !name.contains('..') &&
            !name.startsWith('/') &&
            (name == 'board.json' ||
                name == 'usage.json' ||
                name.startsWith('photos/') ||
                name.startsWith('recordings/'));
        if (!safe) {
          throw const FormatException('Not a Bolo backup file.');
        }
        final out = File('${staging.path}/$name');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(entry.content);
      }

      // Re-anchor photo paths to THIS device's docs dir.
      final reanchored = board.copyWith(categories: [
        for (final cat in board.categories)
          cat.copyWith(
            cards: [for (final c in cat.cards) _reanchor(c)],
            moreCards: [for (final c in cat.moreCards) _reanchor(c)],
          )
      ]);
      File('${staging.path}/board.json')
          .writeAsStringSync(jsonEncode(reanchored.toJson()));

      // Swap into place.
      for (final dir in ['photos', 'recordings']) {
        final target = Directory('${_docsDir.path}/$dir');
        final staged = Directory('${staging.path}/$dir');
        if (target.existsSync()) target.deleteSync(recursive: true);
        if (staged.existsSync()) {
          target.createSync(recursive: true);
          for (final f in staged.listSync().whereType<File>()) {
            f.copySync('${target.path}/${f.uri.pathSegments.last}');
          }
        }
      }
      // board.json is always staged (validated above).
      File('${staging.path}/board.json')
          .copySync('${_docsDir.path}/board.json');

      // usage.json: restore fully "becomes the backup" — if the archive
      // carried no usage.json, the live one must go too, not survive as a
      // stale leftover referencing cards that may no longer exist.
      final stagedUsage = File('${staging.path}/usage.json');
      final liveUsage = File('${_docsDir.path}/usage.json');
      if (stagedUsage.existsSync()) {
        stagedUsage.copySync(liveUsage.path);
      } else if (liveUsage.existsSync()) {
        liveUsage.deleteSync();
      }
    } finally {
      try {
        staging.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  SymbolCard _reanchor(SymbolCard card) {
    final photo = card.photoPath;
    if (photo == null) return card;
    final base = photo.split('/').last;
    // SymbolCard has no copyWith(photoPath:) — rebuild explicitly.
    return SymbolCard(
      id: card.id,
      labels: card.labels,
      symbolAsset: card.symbolAsset,
      photoPath: '${_docsDir.path}/photos/$base',
      hidden: card.hidden,
      recordings: card.recordings,
    );
  }
}
