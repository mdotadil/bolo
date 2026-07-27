# Bolo AAC MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter tap-to-speak AAC app: a nonverbal child (3–7) taps a picture card and the phone speaks the word; a parent curates the board behind a grown-up gate.

**Architecture:** MVVM-shaped Flutter app — widgets ↔ Riverpod notifiers ↔ three services (`SpeechService`, `BoardStore`, bundled assets). All state is one `Board` object persisted as a JSON file in app documents. No backend, no accounts, no analytics, fully offline.

**Tech Stack:** Flutter (stable channel, Dart 3), flutter_riverpod, flutter_tts, flutter_svg, path_provider, image_picker. Mulberry Symbols (CC-BY-SA) bundled as SVG assets. Maestro for the smoke flow.

## Global Constraints

- Repo root: `/Users/adil/brain/Personal/Bolo` (spec lives in `docs/`; the Flutter project is created **in the repo root**, not a subfolder).
- Bundle/app id: `com.mdotadil.bolo`. App display name: "Bolo".
- Dependencies: ONLY `flutter_riverpod`, `flutter_tts`, `flutter_svg`, `path_provider`, `image_picker` (+ `flutter_lints` dev). No codegen, no build_runner, no other packages.
- Sensory rules (hard requirements): muted palette from `lib/theme.dart` only; no animation except the 150 ms tap highlight; no sounds except speech; cards never move/reflow on their own; portrait-locked.
- Speech must play through the iPhone silent switch: iOS audio category `playback` (Task 6).
- All card/category display strings come from `labels`/`names` maps keyed by language code (`en` only in v1). No hardcoded user-facing card text in widgets.
- RTL-safe layout: use `EdgeInsetsDirectional`, `Alignment.centerStart`, etc. Never `left`/`right` variants.
- Grown-up gate hold: `const int.fromEnvironment('BOLO_GATE_MS', defaultValue: 3000)` — release builds 3000 ms, Maestro builds override with `--dart-define=BOLO_GATE_MS=800`.
- Errors are never surfaced on the child screen. Persistence failures keep the in-memory board; corrupt files recover to the bundled default.
- Every task: run `flutter analyze` (must be clean) before its commit step.
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## File Structure

```
pubspec.yaml
assets/
  board/default_board.json      # default categories + 27 cards (the symbol manifest)
  symbols/*.svg                 # Mulberry SVGs, renamed to card ids
lib/
  main.dart                     # wiring: docs dir, provider overrides, orientation
  app.dart                      # MaterialApp, theme, home = BoardScreen
  theme.dart                    # muted palette + text styles (single source of color)
  models/board.dart             # Board, BoardCategory, SymbolCard (+ JSON)
  services/board_store.dart     # atomic JSON persistence + corrupt recovery
  services/speech_service.dart  # Tts interface, FlutterTtsAdapter, SpeechService
  features/board/board_providers.dart  # all Riverpod providers + BoardNotifier
  features/board/board_screen.dart     # child screen: grid + category tabs + gate
  features/board/card_tile.dart        # one symbol card (tap highlight, SVG/photo)
  features/parent/hold_to_open.dart    # 3 s press-and-hold gate widget
  features/parent/parent_screen.dart   # hide/show, reorder, speech rate
  features/parent/add_card_sheet.dart  # custom card: label + photo
  features/parent/photo_picker.dart    # PhotoPicker interface + image_picker impl
test/ (mirrors lib/)
tool/select_symbols.sh          # pulls Mulberry SVGs into assets/symbols/
.maestro/board-smoke.yaml
ATTRIBUTION.md
```

---

### Task 1: Flutter project scaffold

**Files:**
- Create: Flutter template at repo root, `analysis_options.yaml` (template), edits to `pubspec.yaml`

**Interfaces:**
- Consumes: nothing
- Produces: a building Flutter project with all five dependencies resolved; asset folders declared

- [ ] **Step 1: Create the project in the repo root**

```bash
cd /Users/adil/brain/Personal/Bolo
flutter create --org com.mdotadil --project-name bolo --platforms ios,android .
```

Expected: template files created alongside the existing `docs/` folder.

- [ ] **Step 2: Add dependencies**

```bash
flutter pub add flutter_riverpod flutter_tts flutter_svg path_provider image_picker
```

- [ ] **Step 3: Declare assets and app description in pubspec.yaml**

In `pubspec.yaml` set `description: Tap-to-speak AAC board for nonverbal kids.` and under `flutter:` add:

```yaml
  assets:
    - assets/board/
    - assets/symbols/
```

Create empty dirs with keep files so the build doesn't fail before Task 3:

```bash
mkdir -p assets/board assets/symbols
```

- [ ] **Step 4: Remove template counter app test**

Delete `test/widget_test.dart` (it tests the counter template we're about to delete).

- [ ] **Step 5: Verify toolchain**

Run: `flutter analyze && flutter test`
Expected: analyze clean; test reports "No tests ran" (exit 0 with `--reporter` default prints a note; `flutter test` with no test files exits 0 — if it exits 1 for no tests, that's fine, note it and move on).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: scaffold Flutter project with deps

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Domain models + JSON

**Files:**
- Create: `lib/models/board.dart`, `test/models/board_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces (exact API used by every later task):

```dart
class SymbolCard {
  final String id;
  final Map<String, String> labels;   // {'en': 'eat'}
  final String? symbolAsset;          // 'assets/symbols/eat.svg' (bundled cards)
  final String? photoPath;            // absolute file path (custom cards)
  final bool hidden;                  // default false
  const SymbolCard({required this.id, required this.labels, this.symbolAsset, this.photoPath, this.hidden = false});
  SymbolCard copyWith({bool? hidden});
  factory SymbolCard.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

class BoardCategory {
  final String id;
  final Map<String, String> names;    // {'en': 'Wants'}
  final List<SymbolCard> cards;       // list order IS display order
  const BoardCategory({required this.id, required this.names, required this.cards});
  BoardCategory copyWith({List<SymbolCard>? cards});
  factory BoardCategory.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

class Board {
  final double speechRate;            // flutter_tts rate, default 0.45
  final List<BoardCategory> categories;
  const Board({required this.speechRate, required this.categories});
  Board copyWith({double? speechRate, List<BoardCategory>? categories});
  factory Board.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

- [ ] **Step 1: Write the failing test**

`test/models/board_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';

void main() {
  test('Board JSON round-trips', () {
    const board = Board(speechRate: 0.45, categories: [
      BoardCategory(id: 'wants', names: {'en': 'Wants'}, cards: [
        SymbolCard(id: 'eat', labels: {'en': 'eat'}, symbolAsset: 'assets/symbols/eat.svg'),
        SymbolCard(id: 'custom-1', labels: {'en': 'blanket'}, photoPath: '/tmp/p.jpg', hidden: true),
      ]),
    ]);
    final decoded = Board.fromJson(board.toJson());
    expect(decoded.speechRate, 0.45);
    expect(decoded.categories.single.cards.first.symbolAsset, 'assets/symbols/eat.svg');
    expect(decoded.categories.single.cards.last.hidden, isTrue);
    expect(decoded.categories.single.cards.last.photoPath, '/tmp/p.jpg');
  });

  test('hidden defaults to false when absent in JSON', () {
    final card = SymbolCard.fromJson({'id': 'eat', 'labels': {'en': 'eat'}, 'symbolAsset': 'a.svg'});
    expect(card.hidden, isFalse);
  });

  test('copyWith toggles hidden without touching other fields', () {
    const card = SymbolCard(id: 'eat', labels: {'en': 'eat'}, symbolAsset: 'a.svg');
    final hidden = card.copyWith(hidden: true);
    expect(hidden.hidden, isTrue);
    expect(hidden.labels['en'], 'eat');
    expect(hidden.symbolAsset, 'a.svg');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/board_test.dart`
Expected: FAIL — `board.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/models/board.dart`**

```dart
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
        speechRate: (json['speechRate'] as num?)?.toDouble() ?? 0.45,
        categories: (json['categories'] as List)
            .map((c) => BoardCategory.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'speechRate': speechRate,
        'categories': categories.map((c) => c.toJson()).toList(),
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/board_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/board.dart test/models/board_test.dart
git commit -m "feat: Board/BoardCategory/SymbolCard models with JSON

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Mulberry symbol assets + attribution

**Files:**
- Create: `tool/select_symbols.sh`, `assets/symbols/<27 ids>.svg`, `ATTRIBUTION.md`

**Interfaces:**
- Consumes: nothing
- Produces: one SVG per card id below, at `assets/symbols/<id>.svg`. **These 27 ids are the contract** used verbatim by Task 4's `default_board.json`:
  `eat, drink, water, snack, more, all-done, toilet, wash-hands, hurts, tired, sick, play, outside, ball, book, music, tv, bubbles, happy, sad, angry, scared, love, help, come-here, hug, stop`

- [ ] **Step 1: Write the selection script**

`tool/select_symbols.sh`:

```bash
#!/usr/bin/env bash
# Copies Mulberry Symbols into assets/symbols/, renamed to Bolo card ids.
# Mulberry Symbols: https://mulberrysymbols.org (CC-BY-SA 2.0 UK)
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
git clone --depth 1 https://github.com/mulberrysymbols/mulberry-symbols.git "$WORK/mulberry"
SVG_DIR=$(find "$WORK/mulberry" -type d -name '*' | while read -r d; do
  [ "$(find "$d" -maxdepth 1 -name '*.svg' | head -1)" ] && echo "$d" && break; done)
echo "SVGs found under: $SVG_DIR"

# card-id:search-term (first match wins; adjust term if a mapping misses)
MAP="eat:eat drink:drink water:water snack:snack more:more all-done:finished
toilet:toilet wash-hands:wash_hands hurts:pain tired:tired sick:sick
play:play outside:outside ball:ball book:book music:music tv:television bubbles:bubbles
happy:happy sad:sad angry:angry scared:scared love:love
help:help come-here:come hug:hug stop:stop"

MISSING=""
for pair in $MAP; do
  id="${pair%%:*}"; term="${pair##*:}"
  match=$(find "$SVG_DIR" -maxdepth 1 -iname "${term}.svg" | head -1)
  [ -z "$match" ] && match=$(find "$SVG_DIR" -maxdepth 1 -iname "*${term}*.svg" | sort | head -1)
  if [ -n "$match" ]; then
    cp "$match" "assets/symbols/${id}.svg"
    echo "OK   ${id}  <-  $(basename "$match")"
  else
    MISSING="$MISSING ${id}(${term})"
  fi
done
[ -n "$MISSING" ] && echo "MISSING:$MISSING — pick manually from $SVG_DIR" && exit 1
echo "All 27 symbols copied."
```

```bash
chmod +x tool/select_symbols.sh
```

- [ ] **Step 2: Run it**

Run: `tool/select_symbols.sh`
Expected: `OK` line per card. If any `MISSING`, browse the printed SVG dir for a sensible synonym (e.g. `hurt`, `come_here`, `cuddle`, `frightened`), copy it manually to `assets/symbols/<id>.svg`, and update the `MAP` term so the script is re-runnable. **Visually spot-check** a few SVGs (open in browser) — a wrong symbol (e.g. "more" matching "morning") must be caught here.

- [ ] **Step 3: Verify count**

Run: `ls assets/symbols/*.svg | wc -l`
Expected: `27`

- [ ] **Step 4: Write ATTRIBUTION.md** (CC-BY-SA requires this)

```markdown
# Attribution

Symbol images are from **Mulberry Symbols** (https://mulberrysymbols.org),
© Steve Lee / Garry Paxton, licensed under CC-BY-SA 2.0 UK
(https://creativecommons.org/licenses/by-sa/2.0/uk/).
Symbols were renamed to app-internal ids but not otherwise modified.
```

- [ ] **Step 5: Commit**

```bash
git add tool/select_symbols.sh assets/symbols ATTRIBUTION.md
git commit -m "feat: bundle 27 Mulberry symbols with attribution

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Default board JSON + integrity test

**Files:**
- Create: `assets/board/default_board.json`, `test/assets/default_board_test.dart`

**Interfaces:**
- Consumes: `Board.fromJson` (Task 2); symbol files (Task 3)
- Produces: the bundled default board every fresh install starts from; loaded by `BoardStore` (Task 5) via asset path `assets/board/default_board.json`

- [ ] **Step 1: Write the failing integrity test** (pure Dart file I/O — no asset bundle needed)

`test/assets/default_board_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';

void main() {
  test('default board parses, has 27 cards, and every symbol file exists', () {
    final raw = File('assets/board/default_board.json').readAsStringSync();
    final board = Board.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    expect(board.categories.length, 5);
    final cards = board.categories.expand((c) => c.cards).toList();
    expect(cards.length, 27);
    for (final card in cards) {
      expect(card.labels['en'], isNotEmpty, reason: card.id);
      expect(card.symbolAsset, isNotNull, reason: card.id);
      expect(File(card.symbolAsset!).existsSync(), isTrue, reason: card.symbolAsset);
      expect(card.hidden, isFalse, reason: card.id);
    }
    final ids = cards.map((c) => c.id).toSet();
    expect(ids.length, 27, reason: 'card ids must be unique');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/assets/default_board_test.dart`
Expected: FAIL — `default_board.json` missing.

- [ ] **Step 3: Write `assets/board/default_board.json`**

```json
{
  "speechRate": 0.45,
  "categories": [
    {"id": "wants", "names": {"en": "Wants"}, "cards": [
      {"id": "eat", "labels": {"en": "eat"}, "symbolAsset": "assets/symbols/eat.svg"},
      {"id": "drink", "labels": {"en": "drink"}, "symbolAsset": "assets/symbols/drink.svg"},
      {"id": "water", "labels": {"en": "water"}, "symbolAsset": "assets/symbols/water.svg"},
      {"id": "snack", "labels": {"en": "snack"}, "symbolAsset": "assets/symbols/snack.svg"},
      {"id": "more", "labels": {"en": "more"}, "symbolAsset": "assets/symbols/more.svg"},
      {"id": "all-done", "labels": {"en": "all done"}, "symbolAsset": "assets/symbols/all-done.svg"}
    ]},
    {"id": "body", "names": {"en": "Body"}, "cards": [
      {"id": "toilet", "labels": {"en": "toilet"}, "symbolAsset": "assets/symbols/toilet.svg"},
      {"id": "wash-hands", "labels": {"en": "wash hands"}, "symbolAsset": "assets/symbols/wash-hands.svg"},
      {"id": "hurts", "labels": {"en": "it hurts"}, "symbolAsset": "assets/symbols/hurts.svg"},
      {"id": "tired", "labels": {"en": "tired"}, "symbolAsset": "assets/symbols/tired.svg"},
      {"id": "sick", "labels": {"en": "I feel sick"}, "symbolAsset": "assets/symbols/sick.svg"}
    ]},
    {"id": "play", "names": {"en": "Play"}, "cards": [
      {"id": "play", "labels": {"en": "play"}, "symbolAsset": "assets/symbols/play.svg"},
      {"id": "outside", "labels": {"en": "outside"}, "symbolAsset": "assets/symbols/outside.svg"},
      {"id": "ball", "labels": {"en": "ball"}, "symbolAsset": "assets/symbols/ball.svg"},
      {"id": "book", "labels": {"en": "book"}, "symbolAsset": "assets/symbols/book.svg"},
      {"id": "music", "labels": {"en": "music"}, "symbolAsset": "assets/symbols/music.svg"},
      {"id": "tv", "labels": {"en": "TV"}, "symbolAsset": "assets/symbols/tv.svg"},
      {"id": "bubbles", "labels": {"en": "bubbles"}, "symbolAsset": "assets/symbols/bubbles.svg"}
    ]},
    {"id": "feelings", "names": {"en": "Feelings"}, "cards": [
      {"id": "happy", "labels": {"en": "happy"}, "symbolAsset": "assets/symbols/happy.svg"},
      {"id": "sad", "labels": {"en": "sad"}, "symbolAsset": "assets/symbols/sad.svg"},
      {"id": "angry", "labels": {"en": "angry"}, "symbolAsset": "assets/symbols/angry.svg"},
      {"id": "scared", "labels": {"en": "scared"}, "symbolAsset": "assets/symbols/scared.svg"},
      {"id": "love", "labels": {"en": "I love you"}, "symbolAsset": "assets/symbols/love.svg"}
    ]},
    {"id": "help", "names": {"en": "Help"}, "cards": [
      {"id": "help", "labels": {"en": "help me"}, "symbolAsset": "assets/symbols/help.svg"},
      {"id": "come-here", "labels": {"en": "come here"}, "symbolAsset": "assets/symbols/come-here.svg"},
      {"id": "hug", "labels": {"en": "hug"}, "symbolAsset": "assets/symbols/hug.svg"},
      {"id": "stop", "labels": {"en": "stop"}, "symbolAsset": "assets/symbols/stop.svg"}
    ]}
  ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/assets/default_board_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add assets/board/default_board.json test/assets/default_board_test.dart
git commit -m "feat: default board with 27 cards across 5 categories

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: BoardStore (atomic persistence + corrupt recovery)

**Files:**
- Create: `lib/services/board_store.dart`, `test/services/board_store_test.dart`

**Interfaces:**
- Consumes: `Board` (Task 2)
- Produces:

```dart
class BoardStore {
  /// [dir]: app documents directory. [loadDefault]: returns default board JSON
  /// string (production: rootBundle.loadString('assets/board/default_board.json')).
  BoardStore(Directory dir, {required Future<String> Function() loadDefault});
  Future<Board> load();       // board.json → default on missing/corrupt (corrupt file kept as board.json.corrupt)
  Future<void> save(Board b); // atomic: write board.json.tmp, rename over board.json; never throws
  Directory get photosDir;    // <dir>/photos, created on first access
}
```

- [ ] **Step 1: Write the failing tests**

`test/services/board_store_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/services/board_store.dart';

const _defaultJson =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},'
    '"cards":[{"id":"eat","labels":{"en":"eat"},"symbolAsset":"assets/symbols/eat.svg"}]}]}';

void main() {
  late Directory tmp;
  late BoardStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_store');
    store = BoardStore(tmp, loadDefault: () async => _defaultJson);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('load falls back to bundled default when no file exists', () async {
    final board = await store.load();
    expect(board.categories.single.cards.single.id, 'eat');
  });

  test('save then load round-trips and leaves no tmp file', () async {
    final board = await store.load();
    await store.save(board.copyWith(speechRate: 0.6));
    expect(File('${tmp.path}/board.json.tmp').existsSync(), isFalse);
    expect((await store.load()).speechRate, 0.6);
  });

  test('corrupt file recovers to default and is kept aside', () async {
    File('${tmp.path}/board.json').writeAsStringSync('{not json');
    final board = await store.load();
    expect(board.categories.single.id, 'wants');
    expect(File('${tmp.path}/board.json.corrupt').existsSync(), isTrue);
  });

  test('photosDir is created under the store dir', () {
    expect(store.photosDir.existsSync(), isTrue);
    expect(store.photosDir.path, '${tmp.path}/photos');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/board_store_test.dart`
Expected: FAIL — `board_store.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/services/board_store.dart`**

```dart
import 'dart:convert';
import 'dart:io';
import '../models/board.dart';

class BoardStore {
  BoardStore(this._dir, {required Future<String> Function() loadDefault})
      : _loadDefault = loadDefault;

  final Directory _dir;
  final Future<String> Function() _loadDefault;

  File get _file => File('${_dir.path}/board.json');

  Directory get photosDir =>
      Directory('${_dir.path}/photos')..createSync(recursive: true);

  Future<Board> load() async {
    if (_file.existsSync()) {
      try {
        return Board.fromJson(
            jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        // Keep the broken file for diagnosis, fall through to default.
        try {
          _file.renameSync('${_file.path}.corrupt');
        } catch (_) {}
      }
    }
    return Board.fromJson(jsonDecode(await _loadDefault()) as Map<String, dynamic>);
  }

  Future<void> save(Board board) async {
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(board.toJson()), flush: true);
      tmp.renameSync(_file.path);
    } catch (_) {
      // Persistence must never take down the app; in-memory board stays valid.
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/board_store_test.dart`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/board_store.dart test/services/board_store_test.dart
git commit -m "feat: BoardStore with atomic save and corrupt recovery

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: SpeechService + flutter_tts adapter

**Files:**
- Create: `lib/services/speech_service.dart`, `test/services/speech_service_test.dart`

**Interfaces:**
- Consumes: `SymbolCard` (Task 2)
- Produces:

```dart
abstract class Tts {
  Future<void> init();                      // platform setup (audio category etc.)
  Future<void> setSpeechRate(double rate);
  Future<void> stop();
  Future<void> speak(String text);
}

class FlutterTtsAdapter implements Tts {}   // production impl

class SpeechService {
  SpeechService(Tts tts);
  Future<void> configure({required double rate}); // init once + set rate; safe to re-call for rate changes
  Future<void> speakCard(SymbolCard card);        // stop() then speak(labels['en']); silently no-ops on missing label
}
```

- [ ] **Step 1: Write the failing tests**

`test/services/speech_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/services/speech_service.dart';

class FakeTts implements Tts {
  final calls = <String>[];
  @override
  Future<void> init() async => calls.add('init');
  @override
  Future<void> setSpeechRate(double rate) async => calls.add('rate:$rate');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> speak(String text) async => calls.add('speak:$text');
}

void main() {
  test('configure inits once and sets rate each time', () async {
    final tts = FakeTts();
    final speech = SpeechService(tts);
    await speech.configure(rate: 0.45);
    await speech.configure(rate: 0.6);
    expect(tts.calls, ['init', 'rate:0.45', 'rate:0.6']);
  });

  test('speakCard stops current utterance then speaks the en label', () async {
    final tts = FakeTts();
    await SpeechService(tts)
        .speakCard(const SymbolCard(id: 'eat', labels: {'en': 'eat'}));
    expect(tts.calls, ['stop', 'speak:eat']);
  });

  test('speakCard with no en label is a silent no-op', () async {
    final tts = FakeTts();
    await SpeechService(tts).speakCard(const SymbolCard(id: 'x', labels: {}));
    expect(tts.calls, isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/speech_service_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement `lib/services/speech_service.dart`**

```dart
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/board.dart';

abstract class Tts {
  Future<void> init();
  Future<void> setSpeechRate(double rate);
  Future<void> stop();
  Future<void> speak(String text);
}

/// Production adapter. The iOS audio category is the load-bearing part:
/// `playback` makes speech audible with the silent switch on.
class FlutterTtsAdapter implements Tts {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> init() async {
    if (Platform.isIOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.duckOthers],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }
    await _tts.setLanguage('en-US');
    await _tts.awaitSpeakCompletion(false);
  }

  @override
  Future<void> setSpeechRate(double rate) => _tts.setSpeechRate(rate);
  @override
  Future<void> stop() => _tts.stop();
  @override
  Future<void> speak(String text) => _tts.speak(text);
}

class SpeechService {
  SpeechService(this._tts);
  final Tts _tts;
  bool _initialized = false;

  Future<void> configure({required double rate}) async {
    if (!_initialized) {
      await _tts.init();
      _initialized = true;
    }
    await _tts.setSpeechRate(rate);
  }

  Future<void> speakCard(SymbolCard card) async {
    final text = card.labels['en'];
    if (text == null || text.isEmpty) return;
    await _tts.stop(); // new tap always interrupts; speech never queues
    await _tts.speak(text);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/speech_service_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/speech_service.dart test/services/speech_service_test.dart
git commit -m "feat: SpeechService with tts adapter, silent-switch playback

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Riverpod providers + BoardNotifier

**Files:**
- Create: `lib/features/board/board_providers.dart`, `test/features/board_providers_test.dart`

**Interfaces:**
- Consumes: `BoardStore` (Task 5), `SpeechService`/`Tts` (Task 6), models (Task 2)
- Produces (every widget task builds on these exact names):

```dart
final boardStoreProvider = Provider<BoardStore>((ref) => throw UnimplementedError('override in main'));
final ttsProvider = Provider<Tts>((ref) => throw UnimplementedError('override in main'));
final speechServiceProvider = Provider<SpeechService>(...);      // real impl over ttsProvider
final selectedCategoryProvider = StateProvider<int>((ref) => 0); // index into board.categories
final boardNotifierProvider = AsyncNotifierProvider<BoardNotifier, Board>(BoardNotifier.new);

class BoardNotifier extends AsyncNotifier<Board> {
  Future<Board> build();                                   // store.load() + speech.configure(rate)
  Future<void> toggleHidden(String cardId);
  Future<void> reorderCard(String categoryId, int oldIndex, int newIndex);
  Future<void> addCustomCard({required String categoryId, required String label, required String photoPath});
  Future<void> setSpeechRate(double rate);                 // also re-configures SpeechService
}
```

- [ ] **Step 1: Write the failing tests**

`test/features/board_providers_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/speech_service.dart';

const _defaultJson =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"},"symbolAsset":"assets/symbols/eat.svg"},'
    '{"id":"drink","labels":{"en":"drink"},"symbolAsset":"assets/symbols/drink.svg"}]}]}';

class FakeTts implements Tts {
  final calls = <String>[];
  @override
  Future<void> init() async => calls.add('init');
  @override
  Future<void> setSpeechRate(double rate) async => calls.add('rate:$rate');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> speak(String text) async => calls.add('speak:$text');
}

void main() {
  late Directory tmp;
  late ProviderContainer container;
  late FakeTts tts;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_prov');
    tts = FakeTts();
    container = ProviderContainer(overrides: [
      boardStoreProvider.overrideWithValue(
          BoardStore(tmp, loadDefault: () async => _defaultJson)),
      ttsProvider.overrideWithValue(tts),
    ]);
  });
  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('build loads board and configures speech with its rate', () async {
    final board = await container.read(boardNotifierProvider.future);
    expect(board.categories.single.cards.length, 2);
    expect(tts.calls, ['init', 'rate:0.45']);
  });

  test('toggleHidden flips the flag and persists', () async {
    await container.read(boardNotifierProvider.future);
    final notifier = container.read(boardNotifierProvider.notifier);
    await notifier.toggleHidden('eat');
    expect(container.read(boardNotifierProvider).value!
        .categories.single.cards.first.hidden, isTrue);
    // persisted: a fresh store sees it
    final reloaded = await BoardStore(tmp, loadDefault: () async => _defaultJson).load();
    expect(reloaded.categories.single.cards.first.hidden, isTrue);
  });

  test('reorderCard moves a card within its category', () async {
    await container.read(boardNotifierProvider.future);
    await container.read(boardNotifierProvider.notifier).reorderCard('wants', 0, 2);
    final ids = container.read(boardNotifierProvider).value!
        .categories.single.cards.map((c) => c.id).toList();
    expect(ids, ['drink', 'eat']);
  });

  test('addCustomCard appends a photo card', () async {
    await container.read(boardNotifierProvider.future);
    await container.read(boardNotifierProvider.notifier).addCustomCard(
        categoryId: 'wants', label: 'blanket', photoPath: '/p/b.jpg');
    final card = container.read(boardNotifierProvider).value!
        .categories.single.cards.last;
    expect(card.labels['en'], 'blanket');
    expect(card.photoPath, '/p/b.jpg');
    expect(card.symbolAsset, isNull);
  });

  test('setSpeechRate persists and reconfigures speech', () async {
    await container.read(boardNotifierProvider.future);
    await container.read(boardNotifierProvider.notifier).setSpeechRate(0.6);
    expect(container.read(boardNotifierProvider).value!.speechRate, 0.6);
    expect(tts.calls.last, 'rate:0.6');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/board_providers_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement `lib/features/board/board_providers.dart`**

```dart
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
    if (newIndex > oldIndex) newIndex -= 1; // ReorderableListView convention
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/board_providers_test.dart`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/board/board_providers.dart test/features/board_providers_test.dart
git commit -m "feat: Riverpod BoardNotifier with persistence-backed mutations

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Theme + CardTile + BoardScreen (child screen)

**Files:**
- Create: `lib/theme.dart`, `lib/features/board/card_tile.dart`, `lib/features/board/board_screen.dart`, `lib/app.dart`, `test/features/board_screen_test.dart`

**Interfaces:**
- Consumes: providers (Task 7), models (Task 2)
- Produces:
  - `BoloTheme` — static muted palette (`background`, `card`, `cardBorder`, `text`, `tabActive`, `tabInactive`) and `ThemeData boloThemeData()`
  - `CardTile({required SymbolCard card, required VoidCallback onTap})` — pressed-state highlight 150 ms, SVG or photo, label underneath
  - `BoardScreen` — grid (2 columns portrait phone, 3 when width ≥ 600) of **visible** cards of the selected category; bottom category tabs; gate placeholder slot (real gate wired in Task 9)
  - `BoloApp` — `MaterialApp(home: BoardScreen(), theme: boloThemeData())`

- [ ] **Step 1: Write the failing widget tests**

`test/features/board_screen_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/board/board_screen.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/speech_service.dart';

const _json =
    '{"speechRate":0.45,"categories":['
    '{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}},'
    '{"id":"drink","labels":{"en":"drink"},"hidden":true}]},'
    '{"id":"help","names":{"en":"Help"},"cards":[{"id":"help","labels":{"en":"help me"}}]}]}';

class FakeTts implements Tts {
  final calls = <String>[];
  @override
  Future<void> init() async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> speak(String text) async => calls.add('speak:$text');
}

void main() {
  late Directory tmp;
  late FakeTts tts;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_ui');
    tts = FakeTts();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget app() => ProviderScope(overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(tts),
      ], child: const MaterialApp(home: BoardScreen()));

  testWidgets('shows visible cards of selected category, hides hidden ones',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('eat'), findsOneWidget);
    expect(find.text('drink'), findsNothing); // hidden
    expect(find.text('help me'), findsNothing); // other category
  });

  testWidgets('tapping a card speaks it', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('eat'));
    await tester.pump();
    expect(tts.calls, ['stop', 'speak:eat']);
  });

  testWidgets('category tab switches the grid', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(find.text('help me'), findsOneWidget);
    expect(find.text('eat'), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/board_screen_test.dart`
Expected: FAIL — `board_screen.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/theme.dart`**

```dart
import 'package:flutter/material.dart';

/// The ONLY place colors are defined. Muted, low-stimulation palette.
class BoloTheme {
  static const background = Color(0xFFF6F4EF);
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFD8D3C8);
  static const cardPressed = Color(0xFFE8E4DA);
  static const text = Color(0xFF4A4A44);
  static const tabActive = Color(0xFFA8BCA1);
  static const tabInactive = Color(0xFFE3E0D8);
}

ThemeData boloThemeData() => ThemeData(
      scaffoldBackgroundColor: BoloTheme.background,
      colorScheme: ColorScheme.fromSeed(
          seedColor: BoloTheme.tabActive, surface: BoloTheme.background),
      splashFactory: NoSplash.splashFactory, // no ripple animations
      useMaterial3: true,
    );
```

- [ ] **Step 4: Implement `lib/features/board/card_tile.dart`**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/board.dart';
import '../../theme.dart';

class CardTile extends StatefulWidget {
  const CardTile({super.key, required this.card, required this.onTap});
  final SymbolCard card;
  final VoidCallback onTap;

  @override
  State<CardTile> createState() => _CardTileState();
}

class _CardTileState extends State<CardTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.card.labels['en'] ?? '';
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _pressed ? BoloTheme.cardPressed : BoloTheme.card,
          border: Border.all(color: BoloTheme.cardBorder, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(children: [
          Expanded(child: _image()),
          const SizedBox(height: 8),
          Text(label,
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

  Widget _image() {
    final photo = widget.card.photoPath;
    if (photo != null) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(photo), fit: BoxFit.cover, width: double.infinity));
    }
    final asset = widget.card.symbolAsset;
    if (asset != null) return SvgPicture.asset(asset);
    return const SizedBox.shrink();
  }
}
```

- [ ] **Step 5: Implement `lib/features/board/board_screen.dart`** (gate slot is a plain `SizedBox` until Task 9)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import 'board_providers.dart';
import 'card_tile.dart';

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
          error: (_, __) => const SizedBox.expand(),
          data: (board) {
            final category = board.categories[selected];
            final cards =
                category.cards.where((c) => !c.hidden).toList(growable: false);
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
                  itemCount: cards.length,
                  itemBuilder: (context, i) => CardTile(
                    card: cards[i],
                    onTap: () => ref
                        .read(speechServiceProvider)
                        .speakCard(cards[i]),
                  ),
                ),
              ),
              _CategoryTabs(
                  names: [for (final c in board.categories) c.names['en'] ?? ''],
                  selected: selected,
                  onSelect: (i) =>
                      ref.read(selectedCategoryProvider.notifier).state = i),
            ]);
          },
        ),
      ),
    );
  }

  /// Replaced with the parent-mode gate in Task 9.
  Widget gateSlot(BuildContext context) => const SizedBox(width: 48, height: 48);
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
```

- [ ] **Step 6: Implement `lib/app.dart`** and replace template `lib/main.dart` body

`lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'features/board/board_screen.dart';
import 'theme.dart';

class BoloApp extends StatelessWidget {
  const BoloApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bolo',
        debugShowCheckedModeBanner: false,
        theme: boloThemeData(),
        home: const BoardScreen(),
      );
}
```

`lib/main.dart` (temporary — final wiring with overrides lands in Task 12):

```dart
import 'package:flutter/material.dart';
import 'app.dart';

void main() => runApp(const BoloApp());
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/features/board_screen_test.dart && flutter analyze`
Expected: 3 tests PASS, analyze clean.

- [ ] **Step 8: Commit**

```bash
git add lib/theme.dart lib/app.dart lib/main.dart lib/features/board test/features/board_screen_test.dart
git commit -m "feat: child board screen with card grid, tabs, tap-to-speak

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Grown-up gate (HoldToOpen)

**Files:**
- Create: `lib/features/parent/hold_to_open.dart`, `test/features/hold_to_open_test.dart`
- Modify: `lib/features/board/board_screen.dart` (replace `gateSlot`)

**Interfaces:**
- Consumes: nothing new
- Produces: `HoldToOpen({required Widget child, required VoidCallback onOpen, Duration? holdDuration})` — fires `onOpen` after an uninterrupted hold; default duration `int.fromEnvironment('BOLO_GATE_MS', defaultValue: 3000)` ms; **no visible countdown or feedback during the hold**; releasing early is a harmless no-op. Carries `Semantics(identifier: 'grownup-gate')` for Maestro.

- [ ] **Step 1: Write the failing widget tests**

`test/features/hold_to_open_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/parent/hold_to_open.dart';

void main() {
  Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: Center(child: w)));

  testWidgets('fires onOpen after the full hold', (tester) async {
    var opened = false;
    await tester.pumpWidget(wrap(HoldToOpen(
      holdDuration: const Duration(milliseconds: 300),
      onOpen: () => opened = true,
      child: const SizedBox(width: 48, height: 48),
    )));
    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldToOpen)));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('releasing early does nothing', (tester) async {
    var opened = false;
    await tester.pumpWidget(wrap(HoldToOpen(
      holdDuration: const Duration(milliseconds: 300),
      onOpen: () => opened = true,
      child: const SizedBox(width: 48, height: 48),
    )));
    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldToOpen)));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, isFalse);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/hold_to_open_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement `lib/features/parent/hold_to_open.dart`**

```dart
import 'dart:async';
import 'package:flutter/material.dart';

const _gateMs = int.fromEnvironment('BOLO_GATE_MS', defaultValue: 3000);

/// Press-and-hold gate. Deliberately boring: no countdown, no feedback,
/// nothing for a child to find interesting. Early release is a no-op.
class HoldToOpen extends StatefulWidget {
  const HoldToOpen(
      {super.key, required this.child, required this.onOpen, this.holdDuration});
  final Widget child;
  final VoidCallback onOpen;
  final Duration? holdDuration;

  @override
  State<HoldToOpen> createState() => _HoldToOpenState();
}

class _HoldToOpenState extends State<HoldToOpen> {
  Timer? _timer;

  Duration get _duration =>
      widget.holdDuration ?? const Duration(milliseconds: _gateMs);

  void _start(_) {
    _timer?.cancel();
    _timer = Timer(_duration, widget.onOpen);
  }

  void _cancel([dynamic _]) {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        identifier: 'grownup-gate',
        button: true,
        label: 'parent mode',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _start,
          onTapUp: _cancel,
          onTapCancel: _cancel,
          child: widget.child,
        ),
      );
}
```

- [ ] **Step 4: Wire into BoardScreen**

In `lib/features/board/board_screen.dart`, replace the `gateSlot` method with:

```dart
  Widget gateSlot(BuildContext context) => HoldToOpen(
        onOpen: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ParentScreen())),
        child: const Padding(
          padding: EdgeInsetsDirectional.all(12),
          child: Icon(Icons.settings_outlined, size: 24, color: BoloTheme.cardBorder),
        ),
      );
```

Add imports for `hold_to_open.dart` and `parent_screen.dart`. Until Task 10 exists, create a minimal placeholder `lib/features/parent/parent_screen.dart` so it compiles:

```dart
import 'package:flutter/material.dart';

class ParentScreen extends StatelessWidget {
  const ParentScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Parent mode')));
}
```

- [ ] **Step 5: Run all tests**

Run: `flutter test && flutter analyze`
Expected: all suites PASS, analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/parent lib/features/board/board_screen.dart test/features/hold_to_open_test.dart
git commit -m "feat: 3s press-and-hold grown-up gate

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Parent screen (hide/show, reorder, speech rate)

**Files:**
- Modify: `lib/features/parent/parent_screen.dart` (replace placeholder)
- Create: `test/features/parent_screen_test.dart`

**Interfaces:**
- Consumes: `boardNotifierProvider` + methods (Task 7)
- Produces: `ParentScreen` — AppBar "Parent mode"; category picker (`DropdownButton<int>` of category names); `ReorderableListView` of that category's cards, each row = symbol/photo thumbnail + label + visibility `Switch` (key: `ValueKey('switch-<cardId>')`); a speech-rate `Slider` (0.3–0.7, key `ValueKey('rate-slider')`); an "Add card" `FilledButton` (wired to sheet in Task 11, disabled `onPressed: null` for now)

- [ ] **Step 1: Write the failing widget tests**

`test/features/parent_screen_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/parent_screen.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/speech_service.dart';

const _json =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}},{"id":"drink","labels":{"en":"drink"}}]}]}';

class FakeTts implements Tts {
  @override
  Future<void> init() async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> speak(String text) async {}
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_parent'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget app() => ProviderScope(overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => _json)),
        ttsProvider.overrideWithValue(FakeTts()),
      ], child: const MaterialApp(home: ParentScreen()));

  testWidgets('lists all cards of the category including hidden toggles',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('eat'), findsOneWidget);
    expect(find.text('drink'), findsOneWidget);
    expect(find.byKey(const ValueKey('switch-eat')), findsOneWidget);
  });

  testWidgets('toggling a switch hides the card in board state',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('switch-eat')));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(ParentScreen));
    final board = ProviderScope.containerOf(ctx)
        .read(boardNotifierProvider).value!;
    expect(board.categories.single.cards.first.hidden, isTrue);
  });

  testWidgets('rate slider exists with board value', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final slider =
        tester.widget<Slider>(find.byKey(const ValueKey('rate-slider')));
    expect(slider.value, 0.45);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/parent_screen_test.dart`
Expected: FAIL — placeholder has none of this.

- [ ] **Step 3: Implement `lib/features/parent/parent_screen.dart`**

```dart
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
                onReorder: (oldIndex, newIndex) => ref
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
                    value: board.speechRate,
                    min: 0.3,
                    max: 0.7,
                    onChanged: (v) => ref
                        .read(boardNotifierProvider.notifier)
                        .setSpeechRate(v),
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/parent_screen_test.dart && flutter test && flutter analyze`
Expected: all PASS, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/parent/parent_screen.dart test/features/parent_screen_test.dart
git commit -m "feat: parent mode with hide/show, reorder, speech rate

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Add custom photo card

**Files:**
- Create: `lib/features/parent/photo_picker.dart`, `lib/features/parent/add_card_sheet.dart`, `test/features/add_card_test.dart`
- Modify: `lib/features/parent/parent_screen.dart` (enable "Add card" button)

**Interfaces:**
- Consumes: `boardNotifierProvider.addCustomCard` (Task 7), `boardStoreProvider.photosDir` (Task 5)
- Produces:

```dart
abstract class PhotoPicker {
  /// Copies the picked image into [saveDir]; returns the saved absolute path,
  /// or null if the user cancelled.
  Future<String?> pickPhoto({required bool fromCamera, required Directory saveDir});
}
class ImagePickerPhotoPicker implements PhotoPicker {}
final photoPickerProvider = Provider<PhotoPicker>(...); // defaults to ImagePickerPhotoPicker
void showAddCardSheet(BuildContext context, WidgetRef ref, String categoryId);
```

- [ ] **Step 1: Write the failing widget test**

`test/features/add_card_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/parent_screen.dart';
import 'package:bolo/features/parent/photo_picker.dart';
import 'package:bolo/services/board_store.dart';
import 'package:bolo/services/speech_service.dart';

const _json =
    '{"speechRate":0.45,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
    '{"id":"eat","labels":{"en":"eat"}}]}]}';

class FakeTts implements Tts {
  @override
  Future<void> init() async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> speak(String text) async {}
}

class FakePicker implements PhotoPicker {
  @override
  Future<String?> pickPhoto(
      {required bool fromCamera, required Directory saveDir}) async {
    final f = File('${saveDir.path}/fake.jpg')..writeAsBytesSync([1, 2, 3]);
    return f.path;
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_add'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('add card flow appends a custom card with photo', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      boardStoreProvider.overrideWithValue(
          BoardStore(tmp, loadDefault: () async => _json)),
      ttsProvider.overrideWithValue(FakeTts()),
      photoPickerProvider.overrideWithValue(FakePicker()),
    ], child: const MaterialApp(home: ParentScreen())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('add-card-label')), 'blanket');
    await tester.tap(find.byKey(const ValueKey('add-card-gallery')));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(ParentScreen));
    final board =
        ProviderScope.containerOf(ctx).read(boardNotifierProvider).value!;
    final card = board.categories.single.cards.last;
    expect(card.labels['en'], 'blanket');
    expect(card.photoPath, isNotNull);
    expect(File(card.photoPath!).existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/add_card_test.dart`
Expected: FAIL — `photo_picker.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/features/parent/photo_picker.dart`**

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

abstract class PhotoPicker {
  Future<String?> pickPhoto(
      {required bool fromCamera, required Directory saveDir});
}

class ImagePickerPhotoPicker implements PhotoPicker {
  @override
  Future<String?> pickPhoto(
      {required bool fromCamera, required Directory saveDir}) async {
    final picked = await ImagePicker().pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return null;
    // Copy into our own directory so the card survives source-photo deletion.
    final dest =
        '${saveDir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(picked.path).copy(dest);
    return dest;
  }
}

final photoPickerProvider =
    Provider<PhotoPicker>((ref) => ImagePickerPhotoPicker());
```

- [ ] **Step 4: Implement `lib/features/parent/add_card_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../board/board_providers.dart';
import 'photo_picker.dart';

void showAddCardSheet(BuildContext context, WidgetRef ref, String categoryId) {
  final controller = TextEditingController();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsetsDirectional.only(
          start: 16,
          end: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const ValueKey('add-card-label'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Word to speak'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('add-card-camera'),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take photo'),
              onPressed: () => _pick(sheetContext, ref, categoryId,
                  controller.text, fromCamera: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('add-card-gallery'),
              icon: const Icon(Icons.photo_outlined),
              label: const Text('Choose photo'),
              onPressed: () => _pick(sheetContext, ref, categoryId,
                  controller.text, fromCamera: false),
            ),
          ),
        ]),
      ]),
    ),
  );
}

Future<void> _pick(BuildContext sheetContext, WidgetRef ref, String categoryId,
    String label, {required bool fromCamera}) async {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return;
  final path = await ref.read(photoPickerProvider).pickPhoto(
      fromCamera: fromCamera,
      saveDir: ref.read(boardStoreProvider).photosDir);
  if (path == null) return; // user cancelled the picker
  await ref
      .read(boardNotifierProvider.notifier)
      .addCustomCard(categoryId: categoryId, label: trimmed, photoPath: path);
  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
}
```

- [ ] **Step 5: Enable the button in `parent_screen.dart`**

Replace the disabled button with:

```dart
                FilledButton.icon(
                  onPressed: () =>
                      showAddCardSheet(context, ref, category.id),
                  icon: const Icon(Icons.add),
                  label: const Text('Add card'),
                ),
```

Add the `add_card_sheet.dart` import.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all PASS, analyze clean.

- [ ] **Step 7: Commit**

```bash
git add lib/features/parent test/features/add_card_test.dart
git commit -m "feat: add custom photo cards from camera or gallery

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Final wiring + platform config

**Files:**
- Modify: `lib/main.dart`, `ios/Runner/Info.plist`
- Verify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: everything
- Produces: a bootable app on simulator/emulator with providers overridden, portrait lock, and photo permissions declared

- [ ] **Step 1: Final `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'features/board/board_providers.dart';
import 'services/board_store.dart';
import 'services/speech_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  final docsDir = await getApplicationDocumentsDirectory();
  runApp(ProviderScope(
    overrides: [
      boardStoreProvider.overrideWithValue(BoardStore(
        docsDir,
        loadDefault: () =>
            rootBundle.loadString('assets/board/default_board.json'),
      )),
      ttsProvider.overrideWithValue(FlutterTtsAdapter()),
    ],
    child: const BoloApp(),
  ));
}
```

- [ ] **Step 2: iOS Info.plist additions** (inside the top-level `<dict>`)

```xml
	<key>NSCameraUsageDescription</key>
	<string>Take a photo to create a new picture card.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Choose a photo to create a new picture card.</string>
	<key>CFBundleDisplayName</key>
	<string>Bolo</string>
```

Also confirm `UISupportedInterfaceOrientations` lists only `UIInterfaceOrientationPortrait` (edit if the template added landscape entries; leave the `~ipad` variant as generated).

- [ ] **Step 3: Android manifest check**

`image_picker` on modern Android uses the system photo picker / camera intent — no manifest permissions needed. Confirm no `<uses-permission>` additions are required and `android:label="Bolo"` (edit `application` label if it says `bolo`).

- [ ] **Step 4: Boot on iOS simulator**

```bash
flutter run -d "$(xcrun simctl list devices available | grep -m1 -Eo 'iPhone [^(]+\(([A-F0-9-]+)\)' | grep -Eo '[A-F0-9-]{36}')"
```

(Or simply `flutter run` and pick the iPhone simulator.) Manually verify: board shows, tap "eat" speaks, gate needs a real 3 s hold, parent mode hide/show + rate slider work, app relaunch preserves edits. Then quit.

- [ ] **Step 5: Run everything**

Run: `flutter test && flutter analyze`
Expected: all PASS, clean.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart ios/Runner/Info.plist android
git commit -m "feat: app wiring, portrait lock, photo permissions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 13: Maestro smoke flow

**Files:**
- Create: `.maestro/board-smoke.yaml`

**Interfaces:**
- Consumes: the built app; `grownup-gate` semantics identifier (Task 9); card labels (Task 4)
- Produces: the per-feature smoke flow required by standing convention

- [ ] **Step 1: Write `.maestro/board-smoke.yaml`**

```yaml
# Smoke: child taps a card; parent gate opens; hide/show works.
# Build with a short gate so Maestro's longPressOn (~1s) clears it:
#   flutter run --dart-define=BOLO_GATE_MS=800   (keep it running, then: maestro test .maestro/board-smoke.yaml)
appId: com.mdotadil.bolo
---
- launchApp
- assertVisible: "eat"
- tapOn: "eat"          # speaks; no navigation
- assertVisible: "eat"
- longPressOn:
    id: "grownup-gate"
- assertVisible: "Parent mode"
- tapOn:
    id: "switch-eat"
- back
- assertNotVisible: "eat"   # hidden card gone from child board
```

Note: `- back` works on Android; on iOS simulator replace with `- tapOn: point: 6%,6%` (the AppBar back button) or run the flow on the Android emulator, which is the primary target device anyway.

- [ ] **Step 2: Give the Switch a Maestro-visible id**

In `parent_screen.dart`, wrap the `Switch` in `Semantics(identifier: 'switch-${card.id}', child: ...)` (keep the existing `ValueKey`).

- [ ] **Step 3: Run the flow on the Android emulator**

```bash
flutter emulators --launch "$(flutter emulators 2>/dev/null | awk '/•/{print $1; exit}')" || true
flutter run --dart-define=BOLO_GATE_MS=800 &
# wait for "Flutter run key commands" then:
maestro test .maestro/board-smoke.yaml
```

Expected: flow PASSES. (Maestro CLI is `maestro@1.38` per toolchain notes — plain `maestro` may resolve to the desktop cask.)

- [ ] **Step 4: Re-run unit/widget suites once more**

Run: `flutter test && flutter analyze`
Expected: all PASS, clean.

- [ ] **Step 5: Commit**

```bash
git add .maestro/board-smoke.yaml lib/features/parent/parent_screen.dart
git commit -m "test: Maestro board smoke flow

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 14: Signed Android release APK

**Files:**
- Create: `android/key.properties` (gitignored), keystore at `~/keys/bolo-release.keystore` (OUTSIDE the repo)
- Modify: `android/app/build.gradle.kts` (or `build.gradle` if the template generated Groovy — same fields, Groovy syntax), `.gitignore`

**Interfaces:**
- Consumes: the finished app
- Produces: `build/app/outputs/flutter-apk/app-release.apk` signed for permanent side-load on the family's phone

- [ ] **Step 1: Generate the keystore (interactive — asks for passwords)**

```bash
mkdir -p ~/keys
keytool -genkeypair -v -keystore ~/keys/bolo-release.keystore \
  -alias bolo -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Muhammad Adil, OU=Bolo, O=Bolo, C=PK"
```

Store the password in the keychain or password manager. **Never commit the keystore.**

- [ ] **Step 2: `android/key.properties`** (fill in the real password)

```properties
storeFile=/Users/adil/keys/bolo-release.keystore
storePassword=<password>
keyAlias=bolo
keyPassword=<password>
```

Append to `.gitignore`:

```
android/key.properties
*.keystore
```

- [ ] **Step 3: Wire signing into `android/app/build.gradle.kts`**

At the top (after existing imports):

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}
```

Inside `android { }`:

```kotlin
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
```

And in `buildTypes` → `release`, replace the debug signing line with:

```kotlin
            signingConfig = signingConfigs.getByName("release")
```

- [ ] **Step 4: Build and verify**

```bash
flutter build apk --release
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-release.apk`. Verify signing:

```bash
keytool -printcert -jarfile build/app/outputs/flutter-apk/app-release.apk | head -5
```

Expected: certificate owner `CN=Muhammad Adil`.

- [ ] **Step 5: Install on the emulator as a final sanity check**

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Launch Bolo on the emulator; tap a card; confirm speech.

- [ ] **Step 6: Write `README.md` with family setup instructions** (spec: "Setup guidance recommends Guided Access / screen pinning")

```markdown
# Bolo

Tap-to-speak AAC board for nonverbal kids. Tap a picture, the phone speaks the word.

## Handing the phone to your child

Lock the phone into Bolo first, so home button / gestures don't exit the app:

- **Android:** Settings → Security → App pinning → on. Open Bolo, then Recents → tap the Bolo icon → Pin.
- **iPhone:** Settings → Accessibility → Guided Access → on, set a passcode. Open Bolo and triple-click the side button.

## Parent mode

Press and hold the small gear in the top corner for 3 seconds.

Symbols: Mulberry Symbols (CC-BY-SA) — see ATTRIBUTION.md.
```

- [ ] **Step 7: Commit**

```bash
git add android .gitignore README.md
git commit -m "build: release APK signing config + family setup README

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Spec coverage self-check (for the executor)

- Tap-to-speak board, ~27 cards, 5 categories → Tasks 4, 8
- Instant speech, interrupt-don't-queue, silent-switch playback → Task 6
- Sensory rules (muted palette, 150 ms highlight only, static layout) → Task 8 (`theme.dart` is the single color source)
- Grown-up gate 3 s, no countdown, harmless release → Task 9
- Parent mode: hide/show, reorder, custom photo card, speech rate → Tasks 10–11
- Offline JSON persistence, atomic writes, corrupt recovery, photos copied in → Tasks 5, 11
- Urdu/Arabic-ready: labels/names maps, directional layout, `SpeechService` seam → Tasks 2, 6, Global Constraints
- Mulberry licensing + attribution → Task 3
- Maestro smoke flow → Task 13
- Android APK daily driver → Task 14
- Guided Access / screen pinning setup guidance → Task 14 README
- Out of scope (sentence strip, profiles, sync, stores) → nothing here builds it
