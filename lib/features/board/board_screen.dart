import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme.dart';
import '../parent/hold_to_open.dart';
import '../parent/parent_screen.dart';
import 'board_providers.dart';
import 'card_tile.dart';
import 'more_page.dart';

class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(boardNotifierProvider);
    final selected = ref.watch(selectedCategoryProvider);

    return Scaffold(
      body: SafeArea(
        child: boardAsync.when(
          // Child-facing screen: loading/error states are calm empty screens.
          loading: () => const SizedBox.expand(),
          error: (_, _) => const SizedBox.expand(),
          data: (board) {
            final category = board.categories[selected];
            final cards =
                category.cards.where((c) => !c.hidden).toList(growable: false);
            final hasMore = category.moreCards.any((c) => !c.hidden);
            return Column(children: [
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(4),
                  child: gateSlot(context),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsetsDirectional.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        MediaQuery.sizeOf(context).width >= 600 ? 3 : 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: cards.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == cards.length) {
                      return _MoreTile(
                          language: board.activeLanguage,
                          onTap: () => Navigator.of(context).push(
                              zeroDurationRoute(
                                  MorePage(categoryIndex: selected))));
                    }
                    return CardTile(
                      card: cards[i],
                      language: board.activeLanguage,
                      onTap: () => ref
                          .read(boardNotifierProvider.notifier)
                          .speakAndCount(cards[i]),
                    );
                  },
                ),
              ),
              _CategoryTabs(
                  names: [
                    for (final c in board.categories)
                      c.names[board.activeLanguage] ?? c.names['en'] ?? ''
                  ],
                  selected: selected,
                  onSelect: (i) =>
                      ref.read(selectedCategoryProvider.notifier).state = i),
            ]);
          },
        ),
      ),
    );
  }

  Widget gateSlot(BuildContext context) => HoldToOpen(
        onOpen: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ParentScreen())),
        child: const Padding(
          padding: EdgeInsetsDirectional.all(12),
          child: Icon(Icons.settings_outlined, size: 24, color: BoloTheme.cardBorder),
        ),
      );
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs(
      {required this.names, required this.selected, required this.onSelect});
  final List<String> names;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 8),
      child: Row(
        children: [
          for (var i = 0; i < names.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: Container(
                  margin: const EdgeInsetsDirectional.all(4),
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: i == selected
                        ? BoloTheme.tabActive
                        : BoloTheme.tabInactive,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(names[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: BoloTheme.text)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.language, required this.onTap});
  final String language;
  final VoidCallback onTap;

  // One entry per supportedLanguages member (fixed chrome, not board data).
  static const _label = {
    'en': 'More…',
    'ur': 'مزید…',
    'ar': 'المزيد…',
    'fr': 'Plus…',
    'es': 'Más…',
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('more-tile'),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: BoloTheme.card,
          border: Border.all(color: BoloTheme.cardBorder, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(children: [
          Expanded(child: SvgPicture.asset('assets/symbols/more-dots.svg')),
          const SizedBox(height: 8),
          Text(_label[language] ?? _label['en']!,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: BoloTheme.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
