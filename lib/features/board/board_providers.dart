import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/board.dart';
import '../../services/board_store.dart';
import '../../services/recording_player.dart';
import '../../services/speech_service.dart';
import '../../services/usage_store.dart';

final boardStoreProvider =
    Provider<BoardStore>((ref) => throw UnimplementedError('override in main'));

final ttsProvider =
    Provider<Tts>((ref) => throw UnimplementedError('override in main'));

final docsDirProvider =
    Provider<Directory>((ref) => throw UnimplementedError('override in main'));

final speechServiceProvider = Provider<SpeechService>((ref) => SpeechService(
    ref.watch(ttsProvider), ref.watch(recordingPlayerProvider),
    docsDir: ref.watch(docsDirProvider)));

final usageStoreProvider =
    Provider<UsageStore>((ref) => UsageStore(ref.watch(docsDirProvider)));

final selectedCategoryProvider = StateProvider<int>((ref) => 0);

final boardNotifierProvider =
    AsyncNotifierProvider<BoardNotifier, Board>(BoardNotifier.new);

class BoardNotifier extends AsyncNotifier<Board> {
  @override
  Future<Board> build() async {
    final board = await ref.read(boardStoreProvider).load();
    try {
      await ref
          .read(speechServiceProvider)
          .configure(rate: board.speechRate, language: board.activeLanguage);
    } catch (_) {
      // TTS platform channel can throw (no engine, missing voice). Speech
      // becomes silently unavailable rather than blanking the whole app.
    }
    return board;
  }

  Future<void> _update(Board next) async {
    state = AsyncData(next);
    await ref.read(boardStoreProvider).save(next);
  }

  Board get _board => state.value!;

  /// Applies [change] to the card with [cardId], wherever its category is.
  Future<void> _mapCard(String cardId, SymbolCard Function(SymbolCard) change) {
    return _update(_board.copyWith(categories: [
      for (final cat in _board.categories)
        cat.copyWith(cards: [
          for (final c in cat.cards) c.id == cardId ? change(c) : c
        ])
    ]));
  }

  Future<void> toggleHidden(String cardId) =>
      _mapCard(cardId, (c) => c.copyWith(hidden: !c.hidden));

  Future<void> setRecording(String cardId, String lang, String relativePath) =>
      _mapCard(cardId,
          (c) => c.copyWith(recordings: {...c.recordings, lang: relativePath}));

  Future<void> removeRecording(String cardId, String lang) =>
      _mapCard(cardId, (c) {
        final next = Map<String, String>.from(c.recordings)..remove(lang);
        return c.copyWith(recordings: next);
      });

  Future<void> setCustomLabels(String cardId, {String? en, String? ur}) =>
      _mapCard(cardId, (c) {
        final labels = Map<String, String>.from(c.labels);
        if (en != null && en.trim().isNotEmpty) labels['en'] = en.trim();
        if (ur != null && ur.trim().isNotEmpty) labels['ur'] = ur.trim();
        return c.copyWith(labels: labels);
      });

  Future<void> reorderCard(String categoryId, int oldIndex, int newIndex) {
    return _update(_board.copyWith(categories: [
      for (final cat in _board.categories)
        if (cat.id != categoryId)
          cat
        else
          cat.copyWith(cards: _moved(cat.cards, oldIndex, newIndex))
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
        if (cat.id != categoryId)
          cat
        else
          cat.copyWith(cards: [...cat.cards, card])
    ]));
  }

  Future<void> setSpeechRate(double rate) async {
    await _update(_board.copyWith(speechRate: rate));
    await ref
        .read(speechServiceProvider)
        .configure(rate: rate, language: _board.activeLanguage);
  }

  Future<void> setActiveLanguage(String lang) async {
    await _update(_board.copyWith(activeLanguage: lang));
    try {
      await ref
          .read(speechServiceProvider)
          .configure(rate: _board.speechRate, language: lang);
    } catch (_) {
      // Speech config failure never blocks the board (same rule as build()).
    }
  }

  Future<void> speakAndCount(SymbolCard card) async {
    await ref
        .read(speechServiceProvider)
        .speakCard(card, language: _board.activeLanguage);
    ref.read(usageStoreProvider).recordTap(card.id); // fire-and-forget buffer
  }
}
