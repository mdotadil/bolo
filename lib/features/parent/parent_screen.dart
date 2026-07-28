import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/board.dart';
import '../board/board_providers.dart';

class ParentScreen extends ConsumerStatefulWidget {
  const ParentScreen({super.key});
  @override
  ConsumerState<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends ConsumerState<ParentScreen> {
  int _categoryIndex = 0;
  double? _pendingRate;

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(boardNotifierProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Parent mode')),
      body: boardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load board: $e')),
        data: (board) {
          final category = board.categories[_categoryIndex];
          return Column(children: [
            Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Row(children: [
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _categoryIndex,
                    items: [
                      for (var i = 0; i < board.categories.length; i++)
                        DropdownMenuItem(
                            value: i,
                            child: Text(board.categories[i].names['en'] ?? ''))
                    ],
                    onChanged: (i) => setState(() => _categoryIndex = i ?? 0),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: null, // wired in Task 11
                  icon: const Icon(Icons.add),
                  label: const Text('Add card'),
                ),
              ]),
            ),
            Expanded(
              child: ReorderableListView(
                onReorderItem: (oldIndex, newIndex) => ref
                    .read(boardNotifierProvider.notifier)
                    .reorderCard(category.id, oldIndex, newIndex),
                children: [
                  for (final card in category.cards)
                    ListTile(
                      key: ValueKey('row-${card.id}'),
                      leading: SizedBox(width: 40, height: 40, child: _thumb(card)),
                      title: Text(card.labels['en'] ?? ''),
                      trailing: Switch(
                        key: ValueKey('switch-${card.id}'),
                        value: !card.hidden,
                        onChanged: (_) => ref
                            .read(boardNotifierProvider.notifier)
                            .toggleHidden(card.id),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Row(children: [
                const Text('Speech speed'),
                Expanded(
                  child: Slider(
                    key: const ValueKey('rate-slider'),
                    value: _pendingRate ?? board.speechRate,
                    min: 0.3,
                    max: 0.7,
                    onChanged: (v) => setState(() => _pendingRate = v),
                    onChangeEnd: (v) async {
                      await ref
                          .read(boardNotifierProvider.notifier)
                          .setSpeechRate(v);
                      if (!mounted) return;
                      setState(() => _pendingRate = null);
                    },
                  ),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _thumb(SymbolCard card) {
    if (card.photoPath != null) {
      return Image.file(File(card.photoPath!), fit: BoxFit.cover);
    }
    if (card.symbolAsset != null) return SvgPicture.asset(card.symbolAsset!);
    return const SizedBox.shrink();
  }
}
