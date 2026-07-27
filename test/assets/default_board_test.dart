import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';

void main() {
  test('default board parses, has 27 cards, and every symbol file exists', () {
    final raw = File('assets/board/default_board.json').readAsStringSync();
    final board = Board.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    expect(board.categories.length, 5);
    final cards = board.categories.expand((c) => c.cards).toList();
    expect(cards.length, 27);
    for (final card in cards) {
      expect(card.labels['en'], isNotEmpty, reason: card.id);
      expect(card.symbolAsset, isNotNull, reason: card.id);
      expect(File(card.symbolAsset!).existsSync(), isTrue, reason: card.symbolAsset);
      expect(card.hidden, isFalse, reason: card.id);
    }
    final ids = cards.map((c) => c.id).toSet();
    expect(ids.length, 27, reason: 'card ids must be unique');
  });
}
