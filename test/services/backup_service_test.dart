import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/services/backup_service.dart';

/// Decodes [backup], replaces the board.json entry's bytes with invalid
/// JSON, and re-encodes to a new temp .bolo file.
Future<File> tamperBoardEntry(File backup) async {
  final archive = ZipDecoder().decodeBytes(backup.readAsBytesSync());
  final tampered = Archive();
  for (final entry in archive.files.where((f) => f.isFile)) {
    if (entry.name == 'board.json') {
      final bad = utf8.encode('{not json');
      tampered.addFile(ArchiveFile('board.json', bad.length, bad));
    } else {
      tampered.addFile(ArchiveFile(entry.name, entry.size, entry.content));
    }
  }
  final out = File('${Directory.systemTemp.path}/tampered-${DateTime.now().microsecondsSinceEpoch}.bolo');
  out.writeAsBytesSync(ZipEncoder().encode(tampered));
  return out;
}

/// Decodes [backup], replaces the board.json entry with [boardJson], and
/// re-encodes to a new temp .bolo file.
Future<File> replaceBoardEntry(
    File backup, Map<String, dynamic> boardJson) async {
  final archive = ZipDecoder().decodeBytes(backup.readAsBytesSync());
  final replaced = Archive();
  final bytes = utf8.encode(jsonEncode(boardJson));
  for (final entry in archive.files.where((f) => f.isFile)) {
    if (entry.name == 'board.json') {
      replaced.addFile(ArchiveFile('board.json', bytes.length, bytes));
    } else {
      replaced.addFile(ArchiveFile(entry.name, entry.size, entry.content));
    }
  }
  final out = File(
      '${Directory.systemTemp.path}/replaced-${DateTime.now().microsecondsSinceEpoch}.bolo');
  out.writeAsBytesSync(ZipEncoder().encode(replaced));
  return out;
}

void main() {
  late Directory docs;
  setUp(() {
    docs = Directory.systemTemp.createTempSync('bolo_backup');
    Directory('${docs.path}/photos').createSync();
    Directory('${docs.path}/recordings').createSync();
    File('${docs.path}/board.json').writeAsStringSync(jsonEncode({
      'version': 2,
      'speechRate': 0.45,
      'activeLanguage': 'ur',
      'categories': [
        {
          'id': 'wants',
          'names': {'en': 'Wants'},
          'cards': [
            {
              'id': 'custom-1',
              'labels': {'en': 'blanket'},
              'photoPath': '${docs.path}/photos/b.jpg',
            }
          ],
        }
      ],
    }));
    File('${docs.path}/photos/b.jpg').writeAsStringSync('img');
    File('${docs.path}/recordings/eat_ur.m4a').writeAsStringSync('aud');
    File('${docs.path}/usage.json').writeAsStringSync('{"perCard":{},"perDay":{}}');
    // Privacy pin: settings.json lives alongside board.json/usage.json in
    // the docs dir but must never be swept into a .bolo archive — a backup
    // must not carry consent/entitlement onto another phone.
    File('${docs.path}/settings.json').writeAsStringSync(
        jsonEncode({'telemetryEnabled': false, 'supporterUnlocked': false}));
  });
  tearDown(() => docs.deleteSync(recursive: true));

  test('backup → wipe → restore round-trips content and re-anchors photoPath',
      () async {
    final service = BackupService(docs);
    final backup = await service.createBackup();
    expect(backup.path, endsWith('.bolo'));

    final archive = ZipDecoder().decodeBytes(backup.readAsBytesSync());
    expect(archive.files.map((f) => f.name),
        isNot(contains('settings.json')));

    // Restore into a FRESH directory (simulates a new phone).
    final newDocs = Directory.systemTemp.createTempSync('bolo_newphone');
    addTearDown(() => newDocs.deleteSync(recursive: true));
    await BackupService(newDocs).restore(backup);

    final board = jsonDecode(
            File('${newDocs.path}/board.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(board['activeLanguage'], 'ur');
    final card = board['categories'][0]['cards'][0] as Map<String, dynamic>;
    expect(card['photoPath'], '${newDocs.path}/photos/b.jpg'); // re-anchored
    expect(File('${newDocs.path}/photos/b.jpg').readAsStringSync(), 'img');
    expect(File('${newDocs.path}/recordings/eat_ur.m4a').readAsStringSync(),
        'aud');
    expect(File('${newDocs.path}/usage.json').existsSync(), isTrue);
  });

  test('invalid archive throws and leaves existing data untouched', () async {
    final bad = File('${Directory.systemTemp.path}/not-a-backup.bolo')
      ..writeAsStringSync('garbage');
    addTearDown(() => bad.deleteSync());
    final before = File('${docs.path}/board.json').readAsStringSync();
    await expectLater(
        BackupService(docs).restore(bad), throwsA(isA<FormatException>()));
    expect(File('${docs.path}/board.json').readAsStringSync(), before);
  });

  test('zip without a parseable board.json is rejected', () async {
    final service = BackupService(docs);
    final backup = await service.createBackup();
    // Corrupt the board entry by rebuilding a zip with junk board.json
    final tampered = await tamperBoardEntry(backup); // helper below
    await expectLater(
        BackupService(docs).restore(tampered), throwsA(isA<FormatException>()));
  });

  test('backup made by a newer Bolo version is rejected', () async {
    final service = BackupService(docs);
    final backup = await service.createBackup();
    final tooNew = await replaceBoardEntry(backup, {
      'version': Board.currentVersion + 1,
      'speechRate': 0.45,
      'activeLanguage': 'en',
      'categories': [
        {
          'id': 'wants',
          'names': {'en': 'Wants'},
          'cards': [
            {'id': 'eat', 'labels': {'en': 'eat'}}
          ],
        }
      ],
    });
    addTearDown(() => tooNew.deleteSync());
    await expectLater(
        BackupService(docs).restore(tooNew), throwsA(isA<FormatException>()));
  });

  test('backup with an empty categories list is rejected', () async {
    final service = BackupService(docs);
    final backup = await service.createBackup();
    final empty = await replaceBoardEntry(backup, {
      'version': 2,
      'speechRate': 0.45,
      'activeLanguage': 'en',
      'categories': <Map<String, dynamic>>[],
    });
    addTearDown(() => empty.deleteSync());
    await expectLater(
        BackupService(docs).restore(empty), throwsA(isA<FormatException>()));
  });

  test('archive entry with a path-traversal name (zip-slip) is rejected',
      () async {
    final archive = Archive();
    final boardBytes = utf8.encode(jsonEncode({
      'version': 2,
      'speechRate': 0.45,
      'activeLanguage': 'en',
      'categories': [
        {
          'id': 'wants',
          'names': {'en': 'Wants'},
          'cards': [
            {'id': 'eat', 'labels': {'en': 'eat'}}
          ],
        }
      ],
    }));
    archive.addFile(ArchiveFile('board.json', boardBytes.length, boardBytes));
    final evilBytes = utf8.encode('pwned');
    archive
        .addFile(ArchiveFile('../evil.txt', evilBytes.length, evilBytes));
    final malicious = File(
        '${Directory.systemTemp.path}/evil-${DateTime.now().microsecondsSinceEpoch}.bolo')
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    addTearDown(() => malicious.deleteSync());

    await expectLater(BackupService(docs).restore(malicious),
        throwsA(isA<FormatException>()));

    // Nothing escaped staging: neither in the docs dir nor its parent (the
    // system temp dir the malicious entry's `../` resolves into).
    expect(File('${docs.path}/evil.txt').existsSync(), isFalse);
    expect(
        File('${Directory.systemTemp.path}/evil.txt').existsSync(), isFalse);
  });

  test(
      'restoring a v2-era backup folds moreCards into cards, keeping photo '
      'and recording cards that would otherwise be silently dropped',
      () async {
    // Shape of a real pre-v3 install: a category still carrying its own
    // on-disk moreCards array, including a custom photo card with a
    // recording -- exactly what Board.fromJson (v3) no longer knows how to
    // parse on its own.
    final v2Docs = Directory.systemTemp.createTempSync('bolo_v2backup');
    addTearDown(() => v2Docs.deleteSync(recursive: true));
    Directory('${v2Docs.path}/photos').createSync();
    Directory('${v2Docs.path}/recordings').createSync();
    File('${v2Docs.path}/board.json').writeAsStringSync(jsonEncode({
      'version': 2,
      'speechRate': 0.45,
      'activeLanguage': 'en',
      'categories': [
        {
          'id': 'wants',
          'names': {'en': 'Wants'},
          'cards': [
            {'id': 'eat', 'labels': {'en': 'eat'}}
          ],
          'moreCards': [
            {
              'id': 'custom-more-1',
              'labels': {'en': 'my blanket'},
              'photoPath': '${v2Docs.path}/photos/more.jpg',
              // recordings are stored relative to the docs dir (unlike
              // photoPath), which is why restore never needs to re-anchor
              // them -- only the recordings/ directory itself gets copied.
              'recordings': {'en': 'recordings/more_en.m4a'},
            }
          ],
        }
      ],
    }));
    File('${v2Docs.path}/photos/more.jpg').writeAsStringSync('img2');
    File('${v2Docs.path}/recordings/more_en.m4a').writeAsStringSync('aud2');
    final v2Backup = await BackupService(v2Docs).createBackup();
    addTearDown(() => v2Backup.deleteSync());

    final newDocs = Directory.systemTemp.createTempSync('bolo_v2restore');
    addTearDown(() => newDocs.deleteSync(recursive: true));
    await BackupService(newDocs).restore(v2Backup);

    final board = jsonDecode(
            File('${newDocs.path}/board.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(board['version'], 3);
    final wants = (board['categories'] as List).single as Map<String, dynamic>;
    expect(wants.containsKey('moreCards'), isFalse);
    final cards = wants['cards'] as List;
    expect([for (final c in cards) (c as Map)['id']],
        ['eat', 'custom-more-1']);
    final moreCard = cards.last as Map<String, dynamic>;
    expect(moreCard['photoPath'], '${newDocs.path}/photos/more.jpg');
    expect(moreCard['recordings'], {'en': 'recordings/more_en.m4a'});
    expect(File('${newDocs.path}/photos/more.jpg').readAsStringSync(), 'img2');
    expect(File('${newDocs.path}/recordings/more_en.m4a').readAsStringSync(),
        'aud2');
  });

  test(
      'restore fully becomes the backup: usage.json is deleted (not left over) '
      'when the archive has none, matching the photos/recordings wipe',
      () async {
    // Sparse backup: board.json only, no usage.json, no photos/recordings.
    final sparseDocs = Directory.systemTemp.createTempSync('bolo_sparse');
    addTearDown(() => sparseDocs.deleteSync(recursive: true));
    File('${sparseDocs.path}/board.json').writeAsStringSync(jsonEncode({
      'version': 2,
      'speechRate': 0.45,
      'activeLanguage': 'en',
      'categories': [
        {
          'id': 'wants',
          'names': {'en': 'Wants'},
          'cards': [
            {
              'id': 'eat',
              'labels': {'en': 'eat'},
            }
          ],
        }
      ],
    }));
    final sparseBackup = await BackupService(sparseDocs).createBackup();
    addTearDown(() => sparseBackup.deleteSync());

    // Restore over the populated `docs` dir from setUp (which has
    // usage.json, photos/b.jpg, recordings/eat_ur.m4a).
    await BackupService(docs).restore(sparseBackup);

    final board =
        jsonDecode(File('${docs.path}/board.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(board['categories'][0]['cards'][0]['id'], 'eat');
    expect(File('${docs.path}/usage.json').existsSync(), isFalse);
    final photosDir = Directory('${docs.path}/photos');
    expect(!photosDir.existsSync() || photosDir.listSync().isEmpty, isTrue);
    final recordingsDir = Directory('${docs.path}/recordings');
    expect(!recordingsDir.existsSync() || recordingsDir.listSync().isEmpty,
        isTrue);
  });
}
