import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/board.dart';
import '../board/board_providers.dart';
import 'add_card_sheet.dart';
import 'insights_section.dart';
import 'record_sheet.dart';
import 'type_to_speak.dart';

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
              padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  const Text('Board language'),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    key: const ValueKey('language-switch'),
                    value: board.activeLanguage,
                    items: [
                      for (final lang in supportedLanguages)
                        DropdownMenuItem(
                            value: lang,
                            child: Text(languageDisplayNames[lang]!)),
                    ],
                    onChanged: (lang) {
                      if (lang == null) return;
                      ref
                          .read(boardNotifierProvider.notifier)
                          .setActiveLanguage(lang);
                    },
                  ),
                ]),
                FutureBuilder<bool>(
                  future: ref
                      .read(speechServiceProvider)
                      .languageAvailable(board.activeLanguage),
                  builder: (context, snap) => snap.data == false
                      ? Padding(
                          padding: const EdgeInsetsDirectional.only(top: 4),
                          child: Text(
                            '${languageDisplayNames[board.activeLanguage]} voice not available on this phone — recordings will be used.',
                            key: const ValueKey('voice-unavailable-note'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ]),
            ),
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
                            child: Text(board.categories[i].names[board.activeLanguage] ??
                                board.categories[i].names['en'] ??
                                ''))
                    ],
                    onChanged: (i) => setState(() => _categoryIndex = i ?? 0),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () =>
                      showAddCardSheet(context, ref, category.id),
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
                      title: Text(
                          card.labels[board.activeLanguage] ?? card.labels['en'] ?? ''),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          key: ValueKey('mic-${card.id}'),
                          icon: const Icon(Icons.mic_none),
                          onPressed: () => showRecordSheet(context, ref, card),
                        ),
                        Semantics(
                          identifier: 'switch-${card.id}',
                          child: Switch(
                            key: ValueKey('switch-${card.id}'),
                            value: !card.hidden,
                            onChanged: (_) => ref
                                .read(boardNotifierProvider.notifier)
                                .toggleHidden(card.id),
                          ),
                        ),
                      ]),
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
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: 12),
              child: TypeToSpeak(),
            ),
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: 12),
              child: InsightsSection(),
            ),
          ]);
        },
      ),
    );
  }

  Widget _thumb(SymbolCard card) {
    if (card.photoPath != null) {
      return Image.file(File(card.photoPath!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink());
    }
    if (card.symbolAsset != null) return SvgPicture.asset(card.symbolAsset!);
    return const SizedBox.shrink();
  }
}
