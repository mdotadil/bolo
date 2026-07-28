/// The closed set of board languages, in parent-UI order. SINGLE SOURCE OF
/// TRUTH: the language dropdown, record-sheet rows, the TTS tag map, and the
/// migration merge all derive from this list. Adding a language later means
/// adding it here + a `_ttsTag` entry + a `languageDisplayNames` entry +
/// default-board labels; nothing else.
const supportedLanguages = ['en', 'ur', 'ar', 'fr', 'es'];

class SymbolCard {
  final String id;
  final Map<String, String> labels;
  final String? symbolAsset;
  final String? photoPath;
  final bool hidden;
  final Map<String, String> recordings;

  const SymbolCard({
    required this.id,
    required this.labels,
    this.symbolAsset,
    this.photoPath,
    this.hidden = false,
    this.recordings = const {},
  });

  SymbolCard copyWith(
          {bool? hidden,
          Map<String, String>? recordings,
          Map<String, String>? labels}) =>
      SymbolCard(
        id: id,
        labels: labels ?? this.labels,
        symbolAsset: symbolAsset,
        photoPath: photoPath,
        hidden: hidden ?? this.hidden,
        recordings: recordings ?? this.recordings,
      );

  factory SymbolCard.fromJson(Map<String, dynamic> json) => SymbolCard(
        id: json['id'] as String,
        labels: Map<String, String>.from(json['labels'] as Map),
        symbolAsset: json['symbolAsset'] as String?,
        photoPath: json['photoPath'] as String?,
        hidden: json['hidden'] as bool? ?? false,
        recordings: json['recordings'] == null
            ? const {}
            : Map<String, String>.from(json['recordings'] as Map),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'labels': labels,
        if (symbolAsset != null) 'symbolAsset': symbolAsset,
        if (photoPath != null) 'photoPath': photoPath,
        if (hidden) 'hidden': hidden,
        if (recordings.isNotEmpty) 'recordings': recordings,
      };
}

class BoardCategory {
  final String id;
  final Map<String, String> names;
  final List<SymbolCard> cards;
  final List<SymbolCard> moreCards;

  const BoardCategory(
      {required this.id,
      required this.names,
      required this.cards,
      this.moreCards = const []});

  BoardCategory copyWith(
          {List<SymbolCard>? cards, List<SymbolCard>? moreCards}) =>
      BoardCategory(
          id: id,
          names: names,
          cards: cards ?? this.cards,
          moreCards: moreCards ?? this.moreCards);

  factory BoardCategory.fromJson(Map<String, dynamic> json) => BoardCategory(
        id: json['id'] as String,
        names: Map<String, String>.from(json['names'] as Map),
        cards: (json['cards'] as List)
            .map((c) => SymbolCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        moreCards: json['moreCards'] == null
            ? const []
            : (json['moreCards'] as List)
                .map((c) => SymbolCard.fromJson(c as Map<String, dynamic>))
                .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'names': names,
        'cards': cards.map((c) => c.toJson()).toList(),
        if (moreCards.isNotEmpty)
          'moreCards': moreCards.map((c) => c.toJson()).toList(),
      };
}

class Board {
  static const currentVersion = 2;

  final int version;
  final double speechRate;
  final String activeLanguage;
  final List<BoardCategory> categories;

  const Board({
    required this.speechRate,
    required this.categories,
    this.version = currentVersion,
    this.activeLanguage = 'en',
  });

  Board copyWith(
          {double? speechRate,
          List<BoardCategory>? categories,
          String? activeLanguage}) =>
      Board(
        version: currentVersion,
        speechRate: speechRate ?? this.speechRate,
        activeLanguage: activeLanguage ?? this.activeLanguage,
        categories: categories ?? this.categories,
      );

  factory Board.fromJson(Map<String, dynamic> json) => Board(
        version: currentVersion,
        speechRate: ((json['speechRate'] as num?)?.toDouble() ?? 0.45)
            .clamp(0.3, 0.7)
            .toDouble(),
        activeLanguage: json['activeLanguage'] as String? ?? 'en',
        categories: (json['categories'] as List)
            .map((c) => BoardCategory.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'speechRate': speechRate,
        'activeLanguage': activeLanguage,
        'categories': categories.map((c) => c.toJson()).toList(),
      };
}
