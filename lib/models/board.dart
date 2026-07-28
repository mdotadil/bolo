class SymbolCard {
  final String id;
  final Map<String, String> labels;
  final String? symbolAsset;
  final String? photoPath;
  final bool hidden;

  const SymbolCard({
    required this.id,
    required this.labels,
    this.symbolAsset,
    this.photoPath,
    this.hidden = false,
  });

  SymbolCard copyWith({bool? hidden}) => SymbolCard(
        id: id,
        labels: labels,
        symbolAsset: symbolAsset,
        photoPath: photoPath,
        hidden: hidden ?? this.hidden,
      );

  factory SymbolCard.fromJson(Map<String, dynamic> json) => SymbolCard(
        id: json['id'] as String,
        labels: Map<String, String>.from(json['labels'] as Map),
        symbolAsset: json['symbolAsset'] as String?,
        photoPath: json['photoPath'] as String?,
        hidden: json['hidden'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'labels': labels,
        if (symbolAsset != null) 'symbolAsset': symbolAsset,
        if (photoPath != null) 'photoPath': photoPath,
        if (hidden) 'hidden': hidden,
      };
}

class BoardCategory {
  final String id;
  final Map<String, String> names;
  final List<SymbolCard> cards;

  const BoardCategory({required this.id, required this.names, required this.cards});

  BoardCategory copyWith({List<SymbolCard>? cards}) =>
      BoardCategory(id: id, names: names, cards: cards ?? this.cards);

  factory BoardCategory.fromJson(Map<String, dynamic> json) => BoardCategory(
        id: json['id'] as String,
        names: Map<String, String>.from(json['names'] as Map),
        cards: (json['cards'] as List)
            .map((c) => SymbolCard.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'names': names, 'cards': cards.map((c) => c.toJson()).toList()};
}

class Board {
  final double speechRate;
  final List<BoardCategory> categories;

  const Board({required this.speechRate, required this.categories});

  Board copyWith({double? speechRate, List<BoardCategory>? categories}) => Board(
        speechRate: speechRate ?? this.speechRate,
        categories: categories ?? this.categories,
      );

  factory Board.fromJson(Map<String, dynamic> json) => Board(
        speechRate: ((json['speechRate'] as num?)?.toDouble() ?? 0.45)
            .clamp(0.3, 0.7)
            .toDouble(),
        categories: (json['categories'] as List)
            .map((c) => BoardCategory.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'speechRate': speechRate,
        'categories': categories.map((c) => c.toJson()).toList(),
      };
}
