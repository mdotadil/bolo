import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import 'board_providers.dart';
import 'card_tile.dart';

Route<void> zeroDurationRoute(Widget page) => PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );

/// Child-facing second page of a category. Static, calm, zero animation.
class MorePage extends ConsumerWidget {
  const MorePage({super.key, required this.categoryIndex});
  final int categoryIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(boardNotifierProvider);
    return Scaffold(
      body: SafeArea(
        child: boardAsync.when(
          loading: () => const SizedBox.expand(),
          error: (_, _) => const SizedBox.expand(),
          data: (board) {
            final category = board.categories[categoryIndex];
            final cards = category.moreCards
                .where((c) => !c.hidden)
                .toList(growable: false);
            return Column(children: [
              Align(
                alignment: AlignmentDirectional.topStart,
                child: IconButton(
                  key: const ValueKey('more-back'),
                  icon: const Icon(Icons.arrow_back,
                      color: BoloTheme.text, size: 32),
                  onPressed: () => Navigator.of(context).pop(),
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
                  itemCount: cards.length,
                  itemBuilder: (context, i) => CardTile(
                    card: cards[i],
                    language: board.activeLanguage,
                    onTap: () => ref
                        .read(boardNotifierProvider.notifier)
                        .speakAndCount(cards[i]),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
