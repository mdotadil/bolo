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
}
