import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/board.dart';
import '../../services/app_channel.dart';
import '../../services/insights_pdf.dart';
import '../../services/settings_store.dart';
import '../../services/telemetry_service.dart';
import '../../services/usage_store.dart';
import '../../theme.dart';
import '../board/board_providers.dart';

/// On-device usage insights. Everything is computed from usage.json locally;
/// nothing ever leaves the phone.
class InsightsSection extends ConsumerStatefulWidget {
  const InsightsSection({super.key});

  @override
  ConsumerState<InsightsSection> createState() => _InsightsSectionState();
}

class _InsightsSectionState extends ConsumerState<InsightsSection> {
  @override
  void initState() {
    super.initState();
    // Insights shown to the parent — once per mount, no-op in sideload.
    ref.read(telemetryProvider).log(ParentEvent.insightsViewed);
  }

  bool get _exportUnlocked =>
      appChannel == AppChannel.sideload ||
      (ref.watch(settingsProvider).value?.supporterUnlocked ?? false);

  Future<void> _export(Board board) async {
    final usage = await ref.read(usageStoreProvider).load();
    final bytes = await buildInsightsPdf(usage, board);
    final now = DateTime.now();
    final file = File('${Directory.systemTemp.path}/bolo-insights-'
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}.pdf');
    file.writeAsBytesSync(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(boardNotifierProvider);
    return boardAsync.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (board) => FutureBuilder<UsageData>(
        future: ref.read(usageStoreProvider).load(),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          final usage = snap.data!;
          final labels = _labelIndex(board);
          final now = DateTime.now();

          final weekCount = usage.perDay.entries
              .where((e) => DateTime.parse(e.key)
                  .isAfter(now.subtract(const Duration(days: 7))))
              .fold<int>(0, (sum, e) => sum + e.value);

          final top = usage.perCard.entries.toList()
            ..sort((a, b) => b.value.count.compareTo(a.value.count));
          final top5 = top.take(5).toList();
          final maxCount = top5.isEmpty ? 1 : top5.first.value.count;

          final newWords = usage.perCard.entries
              .where((e) => e.value.firstUsed
                  .isAfter(now.subtract(const Duration(days: 14))))
              .map((e) => labels[e.key] ?? e.key)
              .toList();

          return Column(
            key: const ValueKey('insights-section'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Insights', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Words this week: $weekCount',
                  key: const ValueKey('insights-week-count')),
              const SizedBox(height: 8),
              for (final e in top5)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 4),
                  child: Row(children: [
                    SizedBox(width: 96, child: Text(labels[e.key] ?? e.key)),
                    Expanded(
                      child: FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: e.value.count / maxCount,
                        child:
                            Container(height: 10, color: BoloTheme.tabActive),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${e.value.count}'),
                  ]),
                ),
              if (newWords.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('New words (14 days): ${newWords.join(', ')}'),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _exportUnlocked
                    ? OutlinedButton.icon(
                        key: const ValueKey('insights-export'),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Export PDF for therapist'),
                        onPressed: () => _export(board),
                      )
                    : OutlinedButton.icon(
                        key: const ValueKey('insights-export'),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Export PDF (supporter)'),
                        onPressed: () => ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                                content: Text(
                                    'Unlock the report export in "Support Bolo" below.'))),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Map<String, String> _labelIndex(Board board) => {
        for (final cat in board.categories)
          for (final card in cat.cards)
            card.id: card.labels[board.activeLanguage] ??
                card.labels['en'] ??
                card.id
      };
}
