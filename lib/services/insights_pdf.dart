import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/board.dart';
import 'usage_store.dart';

/// One-page usage summary for handing to a therapist. Labels render in
/// English: package:pdf's built-in fonts have no Arabic-script glyphs and
/// shipping font files is deliberately out of scope for v3.
Future<Uint8List> buildInsightsPdf(UsageData usage, Board board) async {
  final now = DateTime.now();
  final enLabels = {
    for (final cat in board.categories)
      for (final card in [...cat.cards, ...cat.moreCards])
        card.id: card.labels['en'] ?? card.id,
  };
  final categoryOf = {
    for (final cat in board.categories)
      for (final card in [...cat.cards, ...cat.moreCards])
        card.id: cat.names['en'] ?? cat.id,
  };

  final weekCount = usage.perDay.entries
      .where((e) => DateTime.parse(e.key)
          .isAfter(now.subtract(const Duration(days: 7))))
      .fold<int>(0, (sum, e) => sum + e.value);
  final top = usage.perCard.entries.toList()
    ..sort((a, b) => b.value.count.compareTo(a.value.count));
  final top10 = top.take(10).toList();
  final newWords = usage.perCard.entries
      .where((e) => e.value.firstUsed
          .isAfter(now.subtract(const Duration(days: 14))))
      .map((e) => enLabels[e.key] ?? e.key)
      .toList();
  final perCategory = <String, int>{};
  for (final e in usage.perCard.entries) {
    final cat = categoryOf[e.key] ?? 'Removed cards';
    perCategory[cat] = (perCategory[cat] ?? 0) + e.value.count;
  }

  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    build: (context) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Bolo - usage insights',
            style:
                pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('Generated ${_day(now)} · on-device data only'),
        pw.SizedBox(height: 12),
        pw.Text('Words this week: $weekCount'),
        pw.SizedBox(height: 8),
        pw.Text('Most used words',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: ['Word', 'Taps', 'First used', 'Last used'],
          data: [
            for (final e in top10)
              [
                enLabels[e.key] ?? e.key,
                '${e.value.count}',
                _day(e.value.firstUsed),
                _day(e.value.lastUsed),
              ],
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
            'New words (last 14 days): ${newWords.isEmpty ? 'none' : newWords.join(', ')}'),
        pw.SizedBox(height: 8),
        pw.Text('Taps per category',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        for (final e in perCategory.entries)
          pw.Text('${e.key}: ${e.value}'),
      ],
    ),
  ));
  return doc.save();
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
