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

// A v2-schema file (as produced by the old More-page feature) that still has
// its own moreCards array on disk -- the shape of a real existing install
// (e.g. board.json on a device that upgraded through v2 before the More
// page was removed).
// The `want-eat` moreCards entry also carries a photoPath and a recordings
// map, the shape of a custom More-page card a parent added their own photo
// and voice recording to -- these must survive the fold into `cards` too,
// not just the plain phrase cards.
const _v2JsonWithMoreCards =
    '{"version":2,"speechRate":0.5,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}},'
    '{"id":"drink","labels":{"en":"drink"}}],'
    '"moreCards":['
    '{"id":"want-eat","labels":{"en":"I want to eat"},'
    '"photoPath":"/old/photos/want-eat.jpg",'
    '"recordings":{"en":"recordings/want-eat_en.m4a"}},'
    '{"id":"want-water","labels":{"en":"I want water"}}]}]}';

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

  test(
      'v1 file is migrated: version, all-language merge, former More-page '
      'phrase cards appended, order preserved', () async {
    File('${tmp.path}/board.json').writeAsStringSync(_v1Json);
    final store = BoardStore(tmp,
        loadDefault: () => rootBundle.loadString('assets/board/default_board.json'));
    final board = await store.load();

    expect(board.version, 3);
    expect(board.activeLanguage, 'en');
    final wants = board.categories.single;
    // order and hidden preserved exactly; the default's former more-cards
    // are appended at the end since this file never had any of its own.
    expect([for (final c in wants.cards) c.id],
        ['more', 'eat', 'custom-1', 'want-eat', 'want-water']);
    expect(wants.cards[1].hidden, isTrue);
    // ALL FOUR non-English label sets merged onto default cards by id
    expect(wants.cards.first.labels['ur'], 'اور');
    expect(wants.cards.first.labels['ar'], 'المزيد');
    expect(wants.cards.first.labels['fr'], 'encore');
    expect(wants.cards.first.labels['es'], 'más');
    expect(wants.names['ur'], 'خواہش');
    expect(wants.names['ar'], 'الرغبات');
    // custom card untouched — no language keys appear on it
    expect(wants.cards[2].labels.keys.toList(), ['en']);
    expect(wants.cards[2].photoPath, '/old/photos/b.jpg');
    // migrated file persisted
    final raw = jsonDecode(File('${tmp.path}/board.json').readAsStringSync());
    expect(raw['version'], 3);
  });

  test(
      'v2 file with its own moreCards folds them into cards on migration to '
      'v3, and the moreCards key is dropped', () async {
    File('${tmp.path}/board.json').writeAsStringSync(_v2JsonWithMoreCards);
    final store = BoardStore(tmp,
        loadDefault: () => rootBundle.loadString('assets/board/default_board.json'));
    final board = await store.load();

    expect(board.version, 3);
    final wants = board.categories.single;
    // The file's own moreCards win and are folded in, appended at the end,
    // in order -- nothing is lost, and the default's backfill never kicks
    // in on top of them.
    expect([for (final c in wants.cards) c.id],
        ['eat', 'drink', 'want-eat', 'want-water']);
    // The custom photo + recording on the folded-in moreCards entry survive
    // the fold too, not just its id and labels.
    final wantEat = wants.cards.firstWhere((c) => c.id == 'want-eat');
    expect(wantEat.photoPath, '/old/photos/want-eat.jpg');
    expect(wantEat.recordings, {'en': 'recordings/want-eat_en.m4a'});

    final raw = jsonDecode(File('${tmp.path}/board.json').readAsStringSync())
        as Map<String, dynamic>;
    final wantsRaw = (raw['categories'] as List).single as Map<String, dynamic>;
    expect(raw['version'], 3);
    expect(wantsRaw.containsKey('moreCards'), isFalse);
    expect([for (final c in wantsRaw['cards'] as List) (c as Map)['id']],
        ['eat', 'drink', 'want-eat', 'want-water']);
    final wantEatRaw = (wantsRaw['cards'] as List)
        .firstWhere((c) => (c as Map)['id'] == 'want-eat') as Map;
    expect(wantEatRaw['photoPath'], '/old/photos/want-eat.jpg');
    expect(wantEatRaw['recordings'], {'en': 'recordings/want-eat_en.m4a'});
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
