import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/board_store.dart';

const _defaultJson =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},'
    '"cards":[{"id":"eat","labels":{"en":"eat"},"symbolAsset":"assets/symbols/eat.svg"}]}]}';

const _v1Json =
    '{"speechRate":0.5,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"more","labels":{"en":"more"}},'
    '{"id":"eat","labels":{"en":"eat"},"hidden":true},'
    '{"id":"custom-1","labels":{"en":"blanket"},"photoPath":"/old/photos/b.jpg"}]}]}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('v1 file is migrated: version, all-language merge, moreCards, order preserved', () async {
    File('${tmp.path}/board.json').writeAsStringSync(_v1Json);
    final store = BoardStore(tmp,
        loadDefault: () => rootBundle.loadString('assets/board/default_board.json'));
    final board = await store.load();

    expect(board.version, 2);
    expect(board.activeLanguage, 'en');
    final wants = board.categories.single;
    // order and hidden preserved exactly
    expect([for (final c in wants.cards) c.id], ['more', 'eat', 'custom-1']);
    expect(wants.cards[1].hidden, isTrue);
    // ALL FOUR non-English label sets merged onto default cards by id
    expect(wants.cards.first.labels['ur'], 'اور');
    expect(wants.cards.first.labels['ar'], 'المزيد');
    expect(wants.cards.first.labels['fr'], 'encore');
    expect(wants.cards.first.labels['es'], 'más');
    expect(wants.names['ur'], 'خواہش');
    expect(wants.names['ar'], 'الرغبات');
    // custom card untouched — no language keys appear on it
    expect(wants.cards.last.labels.keys.toList(), ['en']);
    expect(wants.cards.last.photoPath, '/old/photos/b.jpg');
    // default More cards added because the category had none
    expect([for (final c in wants.moreCards) c.id], ['want-eat', 'want-water']);
    // migrated file persisted
    final raw = jsonDecode(File('${tmp.path}/board.json').readAsStringSync());
    expect(raw['version'], 2);
  });

  test('migration is idempotent', () async {
    File('${tmp.path}/board.json').writeAsStringSync(_v1Json);
    final store = BoardStore(tmp,
        loadDefault: () => rootBundle.loadString('assets/board/default_board.json'));
    final first = await store.load();
    final second = await store.load();
    expect(jsonEncode(second.toJson()), jsonEncode(first.toJson()));
  });
}
