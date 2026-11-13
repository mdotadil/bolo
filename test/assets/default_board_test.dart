import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';

void main() {
  final raw = File('assets/board/default_board.json').readAsStringSync();
  final board = Board.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  test('default board parses, has 31 cards, and every symbol file exists', () {
    expect(board.categories.length, 5);
    final cards = board.categories.expand((c) => c.cards).toList();
    expect(cards.length, 31);
    for (final card in cards) {
      expect(card.labels['en'], isNotEmpty, reason: card.id);
      expect(card.symbolAsset, isNotNull, reason: card.id);
      expect(File(card.symbolAsset!).existsSync(), isTrue, reason: card.symbolAsset);
      expect(card.hidden, isFalse, reason: card.id);
    }
    final ids = cards.map((c) => c.id).toSet();
    expect(ids.length, 31, reason: 'card ids must be unique');
  });

  test('every default card and category has a label in every supported language',
      () {
    for (final cat in board.categories) {
      for (final lang in supportedLanguages) {
        expect(cat.names[lang], isNotEmpty,
            reason: 'category ${cat.id} [$lang]');
        for (final card in cat.cards) {
          expect(card.labels[lang], isNotEmpty,
              reason: 'card ${card.id} [$lang]');
        }
      }
    }
  });

  test('former More-page phrase cards are listed directly in wants and help',
      () {
    final byId = {for (final c in board.categories) c.id: c};
    final wantsIds = byId['wants']!.cards.map((c) => c.id).toList();
    final helpIds = byId['help']!.cards.map((c) => c.id).toList();
    expect(wantsIds, containsAll(['want-eat', 'want-water']));
    expect(helpIds, containsAll(['need-toilet', 'help-fast']));
    final helpFast = byId['help']!.cards.firstWhere((c) => c.id == 'need-toilet');
    expect(helpFast.labels['en'], 'I need the toilet');
  });
}
