import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/services/insights_pdf.dart';
import 'package:bolo/services/usage_store.dart';

void main() {
  test('buildInsightsPdf renders a parseable PDF from usage + board',
      () async {
    const board = Board(speechRate: 0.45, categories: [
      BoardCategory(id: 'wants', names: {'en': 'Wants'}, cards: [
        SymbolCard(id: 'eat', labels: {'en': 'eat'}),
        SymbolCard(id: 'water', labels: {'en': 'water'}),
      ]),
    ]);
    final usage = UsageData(perCard: {
      'eat': CardUsage(
          count: 7,
          firstUsed: DateTime(2026, 7, 1),
          lastUsed: DateTime(2026, 7, 28)),
      'water': CardUsage(
          count: 2,
          firstUsed: DateTime(2026, 7, 27),
          lastUsed: DateTime(2026, 7, 28)),
    }, perDay: {
      '2026-07-28': 9
    });
    final bytes = await buildInsightsPdf(usage, board);
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('empty usage still renders a valid PDF', () async {
    const board = Board(speechRate: 0.45, categories: []);
    final bytes = await buildInsightsPdf(
        const UsageData(perCard: {}, perDay: {}), board);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
