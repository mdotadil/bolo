import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/board.dart';
import '../../services/board_store.dart';
import '../../services/speech_service.dart';

final boardStoreProvider =
    Provider<BoardStore>((ref) => throw UnimplementedError('override in main'));

final ttsProvider =
    Provider<Tts>((ref) => throw UnimplementedError('override in main'));

final speechServiceProvider =
    Provider<SpeechService>((ref) => SpeechService(ref.watch(ttsProvider)));

final selectedCategoryProvider = StateProvider<int>((ref) => 0);

final boardNotifierProvider =
    AsyncNotifierProvider<BoardNotifier, Board>(BoardNotifier.new);

class BoardNotifier extends AsyncNotifier<Board> {
  @override
  Future<Board> build() async {
    final board = await ref.read(boardStoreProvider).load();
    await ref.read(speechServiceProvider).configure(rate: board.speechRate);
    return board;
  }

  Future<void> _update(Board next) async {
    state = AsyncData(next);
    await ref.read(boardStoreProvider).save(next);
  }

  Board get _board => state.value!;

  Future<void> toggleHidden(String cardId) => _update(_board.copyWith(
        categories: [
          for (final cat in _board.categories)
            cat.copyWith(cards: [
              for (final card in cat.cards)
                card.id == cardId ? card.copyWith(hidden: !card.hidden) : card
            ])
        ],
      ));

  Future<void> reorderCard(String categoryId, int oldIndex, int newIndex) {
    return _update(_board.copyWith(categories: [
      for (final cat in _board.categories)
        if (cat.id == categoryId)
          cat.copyWith(cards: _moved(cat.cards, oldIndex, newIndex))
        else
          cat
    ]));
  }

  List<SymbolCard> _moved(List<SymbolCard> cards, int oldIndex, int newIndex) {
    final list = [...cards];
    // onReorderItem already adjusts newIndex for the removed item, no decrement needed
    list.insert(newIndex, list.removeAt(oldIndex));
    return list;
  }

  Future<void> addCustomCard(
      {required String categoryId,
      required String label,
      required String photoPath}) {
    final card = SymbolCard(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      labels: {'en': label},
      photoPath: photoPath,
    );
    return _update(_board.copyWith(categories: [
      for (final cat in _board.categories)
        if (cat.id == categoryId)
          cat.copyWith(cards: [...cat.cards, card])
        else
          cat
    ]));
  }

  Future<void> setSpeechRate(double rate) async {
    await _update(_board.copyWith(speechRate: rate));
    await ref.read(speechServiceProvider).configure(rate: rate);
  }
}
