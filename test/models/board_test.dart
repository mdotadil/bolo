import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';

void main() {
  test('Board JSON round-trips', () {
    const board = Board(speechRate: 0.45, categories: [
      BoardCategory(id: 'wants', names: {'en': 'Wants'}, cards: [
        SymbolCard(id: 'eat', labels: {'en': 'eat'}, symbolAsset: 'assets/symbols/eat.svg'),
        SymbolCard(id: 'custom-1', labels: {'en': 'blanket'}, photoPath: '/tmp/p.jpg', hidden: true),
      ]),
    ]);
    final decoded = Board.fromJson(board.toJson());
    expect(decoded.speechRate, 0.45);
    expect(decoded.categories.single.cards.first.symbolAsset, 'assets/symbols/eat.svg');
    expect(decoded.categories.single.cards.last.hidden, isTrue);
    expect(decoded.categories.single.cards.last.photoPath, '/tmp/p.jpg');
  });

  test('hidden defaults to false when absent in JSON', () {
    final card = SymbolCard.fromJson({'id': 'eat', 'labels': {'en': 'eat'}, 'symbolAsset': 'a.svg'});
    expect(card.hidden, isFalse);
  });

  test('copyWith toggles hidden without touching other fields', () {
    const card = SymbolCard(id: 'eat', labels: {'en': 'eat'}, symbolAsset: 'a.svg');
    final hidden = card.copyWith(hidden: true);
    expect(hidden.hidden, isTrue);
    expect(hidden.labels['en'], 'eat');
    expect(hidden.symbolAsset, 'a.svg');
  });

  test('speechRate is clamped to the slider range when out of bounds', () {
    final tooHigh = Board.fromJson({'speechRate': 1.5, 'categories': []});
    final tooLow = Board.fromJson({'speechRate': -0.2, 'categories': []});
    expect(tooHigh.speechRate, 0.7);
    expect(tooLow.speechRate, 0.3);
  });

  test('v2 fields round-trip through json', () {
    const card = SymbolCard(
        id: 'eat',
        labels: {'en': 'eat', 'ur': 'کھانا'},
        recordings: {'ur': 'recordings/eat_ur.m4a'});
    const cat = BoardCategory(
        id: 'wants',
        names: {'en': 'Wants'},
        cards: [card],
        moreCards: [SymbolCard(id: 'p1', labels: {'en': 'I need the toilet'})]);
    const board = Board(
        speechRate: 0.45,
        categories: [cat],
        activeLanguage: 'ur');

    final decoded = Board.fromJson(board.toJson());
    expect(decoded.version, 2);
    expect(decoded.activeLanguage, 'ur');
    expect(decoded.categories.single.moreCards.single.id, 'p1');
    expect(decoded.categories.single.cards.single.recordings['ur'],
        'recordings/eat_ur.m4a');
  });

  test('v2 fields default when absent from json (v1 files)', () {
    final board = Board.fromJson({
      'speechRate': 0.45,
      'categories': [
        {'id': 'wants', 'names': {'en': 'Wants'}, 'cards': [
          {'id': 'eat', 'labels': {'en': 'eat'}}
        ]}
      ]
    });
    expect(board.version, 2); // fromJson always normalizes to current version
    expect(board.activeLanguage, 'en');
    expect(board.categories.single.moreCards, isEmpty);
    expect(board.categories.single.cards.single.recordings, isEmpty);
  });

  test('copyWith supports new fields', () {
    const card = SymbolCard(id: 'x', labels: {'en': 'x'});
    expect(card.copyWith(recordings: {'en': 'r.m4a'}).recordings['en'], 'r.m4a');
    expect(card.copyWith(labels: {'en': 'y'}).labels['en'], 'y');
    const board = Board(speechRate: 0.4, categories: []);
    expect(board.copyWith(activeLanguage: 'ur').activeLanguage, 'ur');
  });

  test('supportedLanguages is the closed five-language list, in UI order', () {
    expect(supportedLanguages, ['en', 'ur', 'ar', 'fr', 'es']);
  });
}
