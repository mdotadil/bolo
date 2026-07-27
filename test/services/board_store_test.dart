import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/board_store.dart';

const _defaultJson =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},'
    '"cards":[{"id":"eat","labels":{"en":"eat"},"symbolAsset":"assets/symbols/eat.svg"}]}]}';

void main() {
  late Directory tmp;
  late BoardStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_store');
    store = BoardStore(tmp, loadDefault: () async => _defaultJson);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('load falls back to bundled default when no file exists', () async {
    final board = await store.load();
    expect(board.categories.single.cards.single.id, 'eat');
  });

  test('save then load round-trips and leaves no tmp file', () async {
    final board = await store.load();
    await store.save(board.copyWith(speechRate: 0.6));
    expect(File('${tmp.path}/board.json.tmp').existsSync(), isFalse);
    expect((await store.load()).speechRate, 0.6);
  });

  test('corrupt file recovers to default and is kept aside', () async {
    File('${tmp.path}/board.json').writeAsStringSync('{not json');
    final board = await store.load();
    expect(board.categories.single.id, 'wants');
    expect(File('${tmp.path}/board.json.corrupt').existsSync(), isTrue);
  });

  test('photosDir is created under the store dir', () {
    expect(store.photosDir.existsSync(), isTrue);
    expect(store.photosDir.path, '${tmp.path}/photos');
  });
}
