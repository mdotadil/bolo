import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
  tearDown(() => docs.deleteSync(recursive: true));

  test('backup → wipe → restore round-trips content and re-anchors photoPath',
      () async {
    final service = BackupService(docs);
    final backup = await service.createBackup();
    expect(backup.path, endsWith('.bolo'));

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
}
