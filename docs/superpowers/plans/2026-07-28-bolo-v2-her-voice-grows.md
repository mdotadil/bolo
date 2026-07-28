# Bolo v2 "Her Voice Grows" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add parent voice recording, a bilingual Urdu/English board, More-words pages, local usage insights, a type-to-speak parent tool, and backup/restore to the shipped Bolo v1 AAC app.

**Architecture:** All state stays in the existing `Board` JSON + Riverpod `BoardNotifier` pattern; v2 adds a versioned migration in `BoardStore`, a separate debounced `UsageStore`, and two new audio seams (`Recorder`, `RecordingPlayer`) mirroring the v1 `Tts` seam. Child-facing UI gains only labels-by-language, a fixed "More…" tile, and a zero-animation More page; everything else lives behind the grown-up gate.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12, flutter_riverpod, flutter_tts, flutter_svg, path_provider, image_picker + new: record, audioplayers, archive, share_plus, file_selector.

**Spec:** `docs/superpowers/specs/2026-07-28-bolo-v2-design.md` (approved). Read its "Non-goals" before inventing anything.

## Global Constraints

- Work on branch `feature/v2`, cut from `main` (never from dev).
- Dependencies: EXACTLY the v1 five (flutter_riverpod, flutter_tts, flutter_svg, path_provider, image_picker) plus EXACTLY five new (record, audioplayers, archive, share_plus, file_selector). flutter_lints stays dev-only. No codegen, nothing else.
- **The board never rearranges itself.** No feature may change existing card order, position, or grid placement. The "More…" tile is always the LAST grid position.
- Sensory rules: muted palette from `lib/theme.dart` only; no animation except the 150 ms tap highlight — child-facing navigation (More page) uses zero-duration routes; no sounds except speech (recordings are speech); portrait stays locked.
- One active language at a time (`Board.activeLanguage`, `"en"` or `"ur"`). The child never sees mixed-language UI.
- All card/category display strings come from `labels`/`names` maps. Fixed UI chrome may use small const language-keyed maps (e.g. the More… tile label).
- RTL-safe: `EdgeInsetsDirectional`, `AlignmentDirectional`, leading/trailing. Never left/right variants.
- Errors are never surfaced on the child screen (calm blank / silent skip). Persistence failures keep the in-memory board.
- Speech interrupt rule: a new tap stops ALL current audio (TTS and recorded) before speaking. Nothing queues.
- Speech resolution order: recording(activeLanguage) → TTS(activeLanguage label) → TTS(en label).
- Testing gotcha (cost v1 three review rounds): real dart:io writes never complete inside testWidgets' FakeAsync zone, and `pumpAndSettle` inside `tester.runAsync` deadlocks. Wrap disk-touching widget interactions in `tester.runAsync` with bounded `tester.pump(...)` calls. See `test/features/parent_screen_test.dart` for the working pattern.
- Every task: `flutter analyze` must be clean, full `flutter test` green before its commit.
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- Existing tests must keep passing; when a constructor/signature changes (Task 5 changes `SpeechService`), the same task updates every call site and test.

## File Structure

```
lib/
  models/board.dart                     # M: v2 fields (version, activeLanguage, recordings, moreCards)
  services/board_store.dart             # M: v1→v2 migration + Urdu merge
  services/usage_store.dart             # C: debounced tap counters (usage.json)
  services/speech_service.dart          # M: language + recording resolution, speakText
  services/audio_recorder.dart          # C: Recorder seam + record-pkg adapter
  services/recording_player.dart        # C: RecordingPlayer seam + audioplayers adapter
  services/backup_service.dart          # C: .bolo zip create/restore
  features/board/board_providers.dart   # M: v2 mutations, speakAndCount, new providers
  features/board/board_screen.dart      # M: labels by language, More tile
  features/board/card_tile.dart         # M: language param
  features/board/more_page.dart         # C: child-facing static More page
  features/parent/parent_screen.dart    # M: language switch, mic buttons, sections, backup row
  features/parent/record_sheet.dart     # C: per-card record/play/delete + custom label edit
  features/parent/insights_section.dart # C: local usage insights
  features/parent/type_to_speak.dart    # C: parent type-to-speak tool
  features/parent/add_card_sheet.dart   # M: "put on More page" toggle
assets/board/default_board.json         # M: Urdu labels/names + starter More cards
assets/symbols/more-dots.svg            # C: distinct three-dots tile icon
android/app/src/main/AndroidManifest.xml# M: RECORD_AUDIO permission
ios/Runner/Info.plist                   # M: NSMicrophoneUsageDescription
.maestro/board-smoke.yaml               # M: More-page hop
pubspec.yaml                            # M: five new deps, version 2.0.0+2
```

---

### Task 1: Dependencies + v2 data model

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/models/board.dart`
- Test: `test/models/board_test.dart` (extend)

**Interfaces:**
- Consumes: v1 `Board`/`BoardCategory`/`SymbolCard` (all fields keep current names).
- Produces (later tasks rely on these EXACT names):
  - `Board`: `int version` (always serialized as 2), `String activeLanguage` (default `'en'`), `copyWith({double? speechRate, List<BoardCategory>? categories, String? activeLanguage})`
  - `SymbolCard`: `Map<String, String> recordings` (default `{}`), `copyWith({bool? hidden, Map<String, String>? recordings, Map<String, String>? labels})`
  - `BoardCategory`: `List<SymbolCard> moreCards` (default `[]`), `copyWith({List<SymbolCard>? cards, List<SymbolCard>? moreCards})`

- [ ] **Step 1: Add the five packages**

```bash
cd /path/to/Bolo && flutter pub add record audioplayers archive share_plus file_selector
```

`flutter pub add` picks the latest compatible versions — do not hand-pin. Expected: pubspec gains the five deps, `flutter pub get` succeeds. If any package's latest major fails to resolve against Flutter 3.44.2, add it with the previous major (`flutter pub add 'record:^X.0.0'`) and note which in your report.

- [ ] **Step 2: Write the failing model tests**

Append to `test/models/board_test.dart`:

```dart
  test('v2 fields round-trip through json', () {
    const card = SymbolCard(
        id: 'eat',
        labels: {'en': 'eat', 'ur': 'کھانا'},
        recordings: {'ur': 'recordings/eat_ur.m4a'});
    const cat = BoardCategory(
        id: 'wants',
        names: {'en': 'Wants'},
        cards: [card],
        moreCards: [SymbolCard(id: 'p1', labels: {'en': 'I need the toilet'})]);
    const board = Board(
        speechRate: 0.45,
        categories: [cat],
        activeLanguage: 'ur');

    final decoded = Board.fromJson(board.toJson());
    expect(decoded.version, 2);
    expect(decoded.activeLanguage, 'ur');
    expect(decoded.categories.single.moreCards.single.id, 'p1');
    expect(decoded.categories.single.cards.single.recordings['ur'],
        'recordings/eat_ur.m4a');
  });

  test('v2 fields default when absent from json (v1 files)', () {
    final board = Board.fromJson({
      'speechRate': 0.45,
      'categories': [
        {'id': 'wants', 'names': {'en': 'Wants'}, 'cards': [
          {'id': 'eat', 'labels': {'en': 'eat'}}
        ]}
      ]
    });
    expect(board.version, 2); // fromJson always normalizes to current version
    expect(board.activeLanguage, 'en');
    expect(board.categories.single.moreCards, isEmpty);
    expect(board.categories.single.cards.single.recordings, isEmpty);
  });

  test('copyWith supports new fields', () {
    const card = SymbolCard(id: 'x', labels: {'en': 'x'});
    expect(card.copyWith(recordings: {'en': 'r.m4a'}).recordings['en'], 'r.m4a');
    expect(card.copyWith(labels: {'en': 'y'}).labels['en'], 'y');
    const board = Board(speechRate: 0.4, categories: []);
    expect(board.copyWith(activeLanguage: 'ur').activeLanguage, 'ur');
  });
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/models/board_test.dart`
Expected: FAIL — `recordings`, `moreCards`, `activeLanguage`, `version` are not defined.

- [ ] **Step 4: Implement the model changes**

Replace `lib/models/board.dart` with:

```dart
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
```

Note: `Board.fromJson` normalizes `version` to 2 — whether the FILE was v1 is decided in `BoardStore.load()` by inspecting the raw json before parsing (Task 2), not here.

- [ ] **Step 5: Run tests, full suite, analyze**

Run: `flutter test test/models/board_test.dart && flutter test && flutter analyze`
Expected: all PASS (existing suite is unaffected: new constructor params are optional), analyze clean.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/models/board.dart test/models/board_test.dart
git commit -m "feat: v2 data model (activeLanguage, recordings, moreCards) + v2 deps

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Urdu default board + v1→v2 migration

**Files:**
- Modify: `assets/board/default_board.json`
- Modify: `lib/services/board_store.dart`
- Test: `test/services/board_store_test.dart` (extend), `test/assets/default_board_test.dart` (extend)

**Interfaces:**
- Consumes: Task 1 model fields.
- Produces: `BoardStore.load()` returns a fully-migrated v2 `Board`; migration merges Urdu labels/names AND default `moreCards` into pre-existing v1 boards by id, preserves card order/hidden/custom cards, and persists the migrated file. Idempotent.

- [ ] **Step 1: Replace `assets/board/default_board.json`**

Urdu translations authored for review by Adil (native speaker) — flagged lines carry a `_note` nowhere in the file; review happens in the task report. Two gendered/idiomatic picks to call out in the report: "tired" → "تھکن ہو رہی ہے" (neutral phrasing) and "I love you" → "آپ سے پیار ہے" (neutral). Quick phrases live as ordinary cards on More pages (Wants + Help), reusing existing symbols:

```json
{
  "version": 2,
  "speechRate": 0.45,
  "activeLanguage": "en",
  "categories": [
    {"id": "wants", "names": {"en": "Wants", "ur": "خواہش"}, "cards": [
      {"id": "eat", "labels": {"en": "eat", "ur": "کھانا"}, "symbolAsset": "assets/symbols/eat.svg"},
      {"id": "drink", "labels": {"en": "drink", "ur": "پینا"}, "symbolAsset": "assets/symbols/drink.svg"},
      {"id": "water", "labels": {"en": "water", "ur": "پانی"}, "symbolAsset": "assets/symbols/water.svg"},
      {"id": "snack", "labels": {"en": "snack", "ur": "سنیک"}, "symbolAsset": "assets/symbols/snack.svg"},
      {"id": "more", "labels": {"en": "more", "ur": "اور"}, "symbolAsset": "assets/symbols/more.svg"},
      {"id": "all-done", "labels": {"en": "all done", "ur": "ہو گیا"}, "symbolAsset": "assets/symbols/all-done.svg"}
    ], "moreCards": [
      {"id": "want-eat", "labels": {"en": "I want to eat", "ur": "مجھے کھانا چاہیے"}, "symbolAsset": "assets/symbols/eat.svg"},
      {"id": "want-water", "labels": {"en": "I want water", "ur": "مجھے پانی چاہیے"}, "symbolAsset": "assets/symbols/water.svg"}
    ]},
    {"id": "body", "names": {"en": "Body", "ur": "جسم"}, "cards": [
      {"id": "toilet", "labels": {"en": "toilet", "ur": "ٹوائلٹ"}, "symbolAsset": "assets/symbols/toilet.svg"},
      {"id": "wash-hands", "labels": {"en": "wash hands", "ur": "ہاتھ دھونا"}, "symbolAsset": "assets/symbols/wash-hands.svg"},
      {"id": "hurts", "labels": {"en": "it hurts", "ur": "درد ہو رہا ہے"}, "symbolAsset": "assets/symbols/hurts.svg"},
      {"id": "tired", "labels": {"en": "tired", "ur": "تھکن ہو رہی ہے"}, "symbolAsset": "assets/symbols/tired.svg"},
      {"id": "sick", "labels": {"en": "I feel sick", "ur": "طبیعت خراب ہے"}, "symbolAsset": "assets/symbols/sick.svg"}
    ]},
    {"id": "play", "names": {"en": "Play", "ur": "کھیل"}, "cards": [
      {"id": "play", "labels": {"en": "play", "ur": "کھیلنا"}, "symbolAsset": "assets/symbols/play.svg"},
      {"id": "outside", "labels": {"en": "outside", "ur": "باہر"}, "symbolAsset": "assets/symbols/outside.svg"},
      {"id": "ball", "labels": {"en": "ball", "ur": "گیند"}, "symbolAsset": "assets/symbols/ball.svg"},
      {"id": "book", "labels": {"en": "book", "ur": "کتاب"}, "symbolAsset": "assets/symbols/book.svg"},
      {"id": "music", "labels": {"en": "music", "ur": "گانا"}, "symbolAsset": "assets/symbols/music.svg"},
      {"id": "tv", "labels": {"en": "TV", "ur": "ٹی وی"}, "symbolAsset": "assets/symbols/tv.svg"},
      {"id": "bubbles", "labels": {"en": "bubbles", "ur": "بلبلے"}, "symbolAsset": "assets/symbols/bubbles.svg"}
    ]},
    {"id": "feelings", "names": {"en": "Feelings", "ur": "احساس"}, "cards": [
      {"id": "happy", "labels": {"en": "happy", "ur": "خوش"}, "symbolAsset": "assets/symbols/happy.svg"},
      {"id": "sad", "labels": {"en": "sad", "ur": "اداس"}, "symbolAsset": "assets/symbols/sad.svg"},
      {"id": "angry", "labels": {"en": "angry", "ur": "غصہ"}, "symbolAsset": "assets/symbols/angry.svg"},
      {"id": "scared", "labels": {"en": "scared", "ur": "ڈر لگ رہا ہے"}, "symbolAsset": "assets/symbols/scared.svg"},
      {"id": "love", "labels": {"en": "I love you", "ur": "آپ سے پیار ہے"}, "symbolAsset": "assets/symbols/love.svg"}
    ]},
    {"id": "help", "names": {"en": "Help", "ur": "مدد"}, "cards": [
      {"id": "help", "labels": {"en": "help me", "ur": "مدد کریں"}, "symbolAsset": "assets/symbols/help.svg"},
      {"id": "come-here", "labels": {"en": "come here", "ur": "یہاں آئیں"}, "symbolAsset": "assets/symbols/come-here.svg"},
      {"id": "hug", "labels": {"en": "hug", "ur": "جپھی"}, "symbolAsset": "assets/symbols/hug.svg"},
      {"id": "stop", "labels": {"en": "stop", "ur": "رکو"}, "symbolAsset": "assets/symbols/stop.svg"}
    ], "moreCards": [
      {"id": "need-toilet", "labels": {"en": "I need the toilet", "ur": "مجھے ٹوائلٹ جانا ہے"}, "symbolAsset": "assets/symbols/toilet.svg"},
      {"id": "help-fast", "labels": {"en": "help me now", "ur": "جلدی مدد کریں"}, "symbolAsset": "assets/symbols/help.svg"}
    ]}
  ]
}
```

- [ ] **Step 2: Extend `test/assets/default_board_test.dart`**

Add (inside `main()`, matching the file's existing style of loading the asset JSON):

```dart
  test('every default card and category has an ur label/name', () {
    for (final cat in board.categories) {
      expect(cat.names['ur'], isNotEmpty, reason: 'category ${cat.id}');
      for (final card in [...cat.cards, ...cat.moreCards]) {
        expect(card.labels['ur'], isNotEmpty, reason: 'card ${card.id}');
      }
    }
  });

  test('More pages exist for wants and help with phrase cards', () {
    final byId = {for (final c in board.categories) c.id: c};
    expect(byId['wants']!.moreCards, hasLength(2));
    expect(byId['help']!.moreCards, hasLength(2));
    expect(byId['help']!.moreCards.first.labels['en'], 'I need the toilet');
  });
```

(`board` here is however the existing test file names its parsed default board — reuse its existing loading helper.)

- [ ] **Step 3: Write the failing migration tests**

Append to `test/services/board_store_test.dart`:

```dart
  const _v1Json =
      '{"speechRate":0.5,"categories":[{"id":"wants","names":{"en":"Wants"},"cards":['
      '{"id":"more","labels":{"en":"more"}},'
      '{"id":"eat","labels":{"en":"eat"},"hidden":true},'
      '{"id":"custom-1","labels":{"en":"blanket"},"photoPath":"/old/photos/b.jpg"}]}]}';

  test('v1 file is migrated: version, ur merge, moreCards, order preserved', () async {
    File('${tmp.path}/board.json').writeAsStringSync(_v1Json);
    final store = BoardStore(tmp,
        loadDefault: () => rootBundle.loadString('assets/board/default_board.json'));
    final board = await store.load();

    expect(board.version, 2);
    expect(board.activeLanguage, 'en');
    final wants = board.categories.single;
    // order and hidden preserved exactly
    expect([for (final c in wants.cards) c.id], ['more', 'eat', 'custom-1']);
    expect(wants.cards[1].hidden, isTrue);
    // ur merged onto default cards by id
    expect(wants.cards.first.labels['ur'], 'اور');
    expect(wants.names['ur'], 'خواہش');
    // custom card untouched
    expect(wants.cards.last.labels.containsKey('ur'), isFalse);
    expect(wants.cards.last.photoPath, '/old/photos/b.jpg');
    // default More cards added because the category had none
    expect([for (final c in wants.moreCards) c.id], ['want-eat', 'want-water']);
    // migrated file persisted
    final raw = jsonDecode(File('${tmp.path}/board.json').readAsStringSync());
    expect(raw['version'], 2);
  });

  test('migration is idempotent', () async {
    File('${tmp.path}/board.json').writeAsStringSync(_v1Json);
    final store = BoardStore(tmp,
        loadDefault: () => rootBundle.loadString('assets/board/default_board.json'));
    final first = await store.load();
    final second = await store.load();
    expect(jsonEncode(second.toJson()), jsonEncode(first.toJson()));
  });
```

Note: `rootBundle.loadString` in tests requires `TestWidgetsFlutterBinding.ensureInitialized();` at the top of `main()` — add it if the file doesn't have it. If asset loading is awkward in this test file's setup, inline the default-board JSON string instead; the merge logic doesn't care where the default text comes from.

- [ ] **Step 4: Run tests to verify they fail**

Run: `flutter test test/services/board_store_test.dart`
Expected: FAIL — no migration exists; `version` stays absent, no ur labels.

- [ ] **Step 5: Implement migration in `lib/services/board_store.dart`**

Replace the `load()` method with:

```dart
  Future<Board> load() async {
    if (_file.existsSync()) {
      try {
        final raw =
            jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
        final board = Board.fromJson(raw);
        final fileVersion = raw['version'] as int? ?? 1;
        if (fileVersion >= Board.currentVersion) return board;
        final migrated = _migrate(board,
            Board.fromJson(jsonDecode(await _loadDefault()) as Map<String, dynamic>));
        await save(migrated);
        return migrated;
      } catch (_) {
        // Keep the broken file for diagnosis, fall through to default.
        try {
          _file.renameSync('${_file.path}.corrupt');
        } catch (_) {}
      }
    }
    return Board.fromJson(jsonDecode(await _loadDefault()) as Map<String, dynamic>);
  }

  /// v1 → v2: merge Urdu labels/names and default More cards from the bundled
  /// default board, by id. Never changes card order, hidden flags, or custom
  /// cards. Board.fromJson already stamped version/activeLanguage defaults.
  Board _migrate(Board old, Board def) {
    final defCats = {for (final c in def.categories) c.id: c};
    return old.copyWith(categories: [
      for (final cat in old.categories)
        _mergeCategory(cat, defCats[cat.id]),
    ]);
  }

  BoardCategory _mergeCategory(BoardCategory cat, BoardCategory? def) {
    if (def == null) return cat;
    final defCards = {for (final c in [...def.cards, ...def.moreCards]) c.id: c};
    List<SymbolCard> mergeUr(List<SymbolCard> cards) => [
          for (final card in cards)
            defCards[card.id] == null
                ? card
                : card.copyWith(labels: {
                    ...defCards[card.id]!.labels,
                    ...card.labels,
                  }),
        ];
    return BoardCategory(
      id: cat.id,
      names: {...def.names, ...cat.names},
      cards: mergeUr(cat.cards),
      moreCards:
          cat.moreCards.isEmpty ? def.moreCards : mergeUr(cat.moreCards),
    );
  }
```

Add `import '../models/board.dart';` stays as-is; no other changes to save()/photosDir. Note the merge order `{...default, ...existing}` — existing labels always win, so a parent's custom label edit is never overwritten by migration.

- [ ] **Step 6: Run tests, full suite, analyze**

Run: `flutter test test/services/board_store_test.dart && flutter test && flutter analyze`
Expected: all PASS, analyze clean.

- [ ] **Step 7: Commit**

```bash
git add assets/board/default_board.json lib/services/board_store.dart test/
git commit -m "feat: bilingual default board + v1-to-v2 migration with Urdu merge

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: UsageStore (local tap counters)

**Files:**
- Create: `lib/services/usage_store.dart`
- Test: `test/services/usage_store_test.dart`

**Interfaces:**
- Consumes: nothing app-specific (Directory + clock).
- Produces:
  - `class CardUsage { final int count; final DateTime firstUsed; final DateTime lastUsed; }`
  - `class UsageData { final Map<String, CardUsage> perCard; final Map<String, int> perDay; }` (perDay key = `'YYYY-MM-DD'`)
  - `class UsageStore { UsageStore(Directory dir, {DateTime Function()? clock}); void recordTap(String cardId); Future<void> flush(); Future<UsageData> load(); }`
  - Auto-flushes every 5 buffered taps. `clock` injectable for tests (defaults to `DateTime.now`).

- [ ] **Step 1: Write the failing tests**

`test/services/usage_store_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/usage_store.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_usage'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File file() => File('${tmp.path}/usage.json');

  test('recordTap buffers; 5th tap auto-flushes one write', () async {
    final store = UsageStore(tmp, clock: () => DateTime(2026, 7, 28, 10));
    for (var i = 0; i < 4; i++) {
      store.recordTap('eat');
    }
    expect(file().existsSync(), isFalse); // still buffered
    store.recordTap('water');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(file().existsSync(), isTrue);
    final data = await store.load();
    expect(data.perCard['eat']!.count, 4);
    expect(data.perCard['water']!.count, 1);
    expect(data.perDay['2026-07-28'], 5);
  });

  test('explicit flush writes buffered taps', () async {
    final store = UsageStore(tmp, clock: () => DateTime(2026, 7, 28));
    store.recordTap('eat');
    await store.flush();
    expect((await store.load()).perCard['eat']!.count, 1);
  });

  test('counts accumulate across instances and firstUsed survives', () async {
    final s1 = UsageStore(tmp, clock: () => DateTime(2026, 7, 1));
    s1.recordTap('eat');
    await s1.flush();
    final s2 = UsageStore(tmp, clock: () => DateTime(2026, 7, 28));
    s2.recordTap('eat');
    await s2.flush();
    final u = (await s2.load()).perCard['eat']!;
    expect(u.count, 2);
    expect(u.firstUsed, DateTime(2026, 7, 1));
    expect(u.lastUsed, DateTime(2026, 7, 28));
  });

  test('perDay entries older than 90 days are pruned on flush', () async {
    final s1 = UsageStore(tmp, clock: () => DateTime(2026, 1, 1));
    s1.recordTap('eat');
    await s1.flush();
    final s2 = UsageStore(tmp, clock: () => DateTime(2026, 7, 28));
    s2.recordTap('eat');
    await s2.flush();
    final data = await s2.load();
    expect(data.perDay.containsKey('2026-01-01'), isFalse);
    expect(data.perDay['2026-07-28'], 1);
  });

  test('corrupt usage.json is set aside and counting starts fresh', () async {
    file().writeAsStringSync('{not json');
    final store = UsageStore(tmp, clock: () => DateTime(2026, 7, 28));
    store.recordTap('eat');
    await store.flush();
    expect((await store.load()).perCard['eat']!.count, 1);
    expect(File('${tmp.path}/usage.json.corrupt').existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/usage_store_test.dart`
Expected: FAIL — `usage_store.dart` does not exist.

- [ ] **Step 3: Implement `lib/services/usage_store.dart`**

```dart
import 'dart:convert';
import 'dart:io';

class CardUsage {
  final int count;
  final DateTime firstUsed;
  final DateTime lastUsed;
  const CardUsage(
      {required this.count, required this.firstUsed, required this.lastUsed});
}

class UsageData {
  final Map<String, CardUsage> perCard;
  final Map<String, int> perDay;
  const UsageData({required this.perCard, required this.perDay});
}

/// On-device tap counters. Separate file from board.json on purpose: a corrupt
/// counter file must never take the board down, and taps write on a different
/// cadence (debounced) than board edits.
class UsageStore {
  UsageStore(this._dir, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const _flushEvery = 5;
  static const _keepDays = 90;

  final Directory _dir;
  final DateTime Function() _clock;
  final List<(String, DateTime)> _buffer = [];

  File get _file => File('${_dir.path}/usage.json');

  void recordTap(String cardId) {
    _buffer.add((cardId, _clock()));
    if (_buffer.length >= _flushEvery) {
      flush(); // fire and forget; speech must never wait on disk
    }
  }

  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final taps = List.of(_buffer);
    _buffer.clear();
    try {
      final raw = _readRaw();
      final perCard =
          (raw['perCard'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final perDay =
          (raw['perDay'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      for (final (id, at) in taps) {
        final prev = perCard[id] as Map<String, dynamic>?;
        perCard[id] = {
          'count': ((prev?['count'] as int?) ?? 0) + 1,
          'firstUsed': (prev?['firstUsed'] as String?) ?? at.toIso8601String(),
          'lastUsed': at.toIso8601String(),
        };
        final day = _dayKey(at);
        perDay[day] = ((perDay[day] as int?) ?? 0) + 1;
      }
      final cutoff = _clock().subtract(const Duration(days: _keepDays));
      perDay.removeWhere((day, _) => DateTime.parse(day).isBefore(cutoff));
      final tmpFile = File('${_file.path}.tmp');
      await tmpFile.writeAsString(
          jsonEncode({'perCard': perCard, 'perDay': perDay}),
          flush: true);
      tmpFile.renameSync(_file.path);
    } catch (_) {
      // Counters are best-effort; never let them break anything.
    }
  }

  Future<UsageData> load() async {
    final raw = _readRaw();
    final perCard = <String, CardUsage>{};
    ((raw['perCard'] as Map<String, dynamic>?) ?? {}).forEach((id, v) {
      final m = v as Map<String, dynamic>;
      perCard[id] = CardUsage(
        count: m['count'] as int,
        firstUsed: DateTime.parse(m['firstUsed'] as String),
        lastUsed: DateTime.parse(m['lastUsed'] as String),
      );
    });
    final perDay = <String, int>{};
    ((raw['perDay'] as Map<String, dynamic>?) ?? {})
        .forEach((day, n) => perDay[day] = n as int);
    return UsageData(perCard: perCard, perDay: perDay);
  }

  Map<String, dynamic> _readRaw() {
    if (!_file.existsSync()) return {};
    try {
      return jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      try {
        _file.renameSync('${_file.path}.corrupt');
      } catch (_) {}
      return {};
    }
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 4: Run tests, full suite, analyze**

Run: `flutter test test/services/usage_store_test.dart && flutter test && flutter analyze`
Expected: PASS, clean.

- [ ] **Step 5: Commit**

```bash
git add lib/services/usage_store.dart test/services/usage_store_test.dart
git commit -m "feat: debounced on-device usage counters (usage.json)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Recorder + RecordingPlayer seams and platform permissions

**Files:**
- Create: `lib/services/audio_recorder.dart`, `lib/services/recording_player.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
- Test: `test/services/recording_player_test.dart` (fake-based contract test)

**Interfaces:**
- Consumes: `record` and `audioplayers` packages.
- Produces (later tasks rely on these EXACT names):
  - `abstract class Recorder { Future<bool> hasPermission(); Future<void> start(String path); Future<String?> stop(); bool get isRecording; }` — `stop()` returns the recorded file path, or null if nothing was recording / it failed.
  - `class RecordPackageRecorder implements Recorder` (uses `AudioRecorder` from `record`, `AudioEncoder.aacLc`)
  - `abstract class RecordingPlayer { Future<void> play(String absolutePath); Future<void> stop(); }`
  - `class AudioplayersRecordingPlayer implements RecordingPlayer` (uses `AudioPlayer` + `DeviceFileSource`)
  - Riverpod: `recorderProvider = Provider<Recorder>(...)`, `recordingPlayerProvider = Provider<RecordingPlayer>(...)` — both `throw UnimplementedError('override in main')` like `ttsProvider` (overridden in Task 6).

- [ ] **Step 1: Implement `lib/services/audio_recorder.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

abstract class Recorder {
  Future<bool> hasPermission();
  Future<void> start(String path);

  /// Returns the recorded file's path, or null if not recording / failed.
  Future<String?> stop();
  bool get isRecording;
}

class RecordPackageRecorder implements Recorder {
  final AudioRecorder _rec = AudioRecorder();
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<void> start(String path) async {
    await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
        path: path);
    _recording = true;
  }

  @override
  Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    try {
      return await _rec.stop();
    } catch (_) {
      return null;
    }
  }
}

final recorderProvider =
    Provider<Recorder>((ref) => throw UnimplementedError('override in main'));
```

- [ ] **Step 2: Implement `lib/services/recording_player.dart`**

```dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class RecordingPlayer {
  Future<void> play(String absolutePath);
  Future<void> stop();
}

class AudioplayersRecordingPlayer implements RecordingPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> play(String absolutePath) async {
    await _player.stop();
    await _player.play(DeviceFileSource(absolutePath));
  }

  @override
  Future<void> stop() => _player.stop();
}

final recordingPlayerProvider = Provider<RecordingPlayer>(
    (ref) => throw UnimplementedError('override in main'));
```

If either adapter's API differs in the resolved package version (e.g. `RecordConfig` parameter names), adjust the ADAPTER ONLY — the abstract interfaces are frozen; later tasks depend on them exactly as written.

- [ ] **Step 3: Platform permissions**

`android/app/src/main/AndroidManifest.xml` — inside `<manifest>`, above `<application>`:

```xml
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

`ios/Runner/Info.plist` — inside the top-level `<dict>`, next to the existing camera/photo strings:

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Record your voice for a card so the app speaks in your voice.</string>
```

- [ ] **Step 4: Contract test with fakes**

`test/services/recording_player_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/audio_recorder.dart';
import 'package:bolo/services/recording_player.dart';

class FakeRecorder implements Recorder {
  final calls = <String>[];
  bool _rec = false;
  @override
  bool get isRecording => _rec;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start(String path) async {
    calls.add('start:$path');
    _rec = true;
  }

  @override
  Future<String?> stop() async {
    if (!_rec) return null;
    _rec = false;
    final path = calls.last.substring('start:'.length);
    calls.add('stop');
    return path;
  }
}

class FakePlayer implements RecordingPlayer {
  final calls = <String>[];
  @override
  Future<void> play(String p) async => calls.add('play:$p');
  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  test('recorder stop returns the started path once', () async {
    final r = FakeRecorder();
    await r.start('/tmp/a.m4a');
    expect(r.isRecording, isTrue);
    expect(await r.stop(), '/tmp/a.m4a');
    expect(await r.stop(), isNull);
  });

  test('player records play/stop calls', () async {
    final p = FakePlayer();
    await p.play('/tmp/a.m4a');
    await p.stop();
    expect(p.calls, ['play:/tmp/a.m4a', 'stop']);
  });
}
```

These fakes are the SAME shape later tasks use — keep them importable by copying them into later test files as written here.

- [ ] **Step 5: Run tests, full suite, analyze**

Run: `flutter test test/services/recording_player_test.dart && flutter test && flutter analyze`
Expected: PASS, clean.

- [ ] **Step 6: Commit**

```bash
git add lib/services/audio_recorder.dart lib/services/recording_player.dart android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist test/services/recording_player_test.dart
git commit -m "feat: recorder and recording-player seams + mic permissions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: SpeechService v2 — language + recording resolution

**Files:**
- Modify: `lib/services/speech_service.dart`
- Modify: `lib/features/board/board_providers.dart` (provider wiring only — the `speechServiceProvider` constructor call)
- Modify: `lib/main.dart` (pass docsDir + player overrides)
- Test: `test/services/speech_service_test.dart` (rewrite/extend)

**Interfaces:**
- Consumes: Task 4 `RecordingPlayer`; Task 1 `SymbolCard.recordings`.
- Produces (frozen for later tasks):
  - `abstract class Tts` gains: `Future<void> setLanguage(String tag);` and `Future<bool> isLanguageAvailable(String tag);`
  - `class SpeechService { SpeechService(this._tts, this._player, {required Directory docsDir}); Future<void> configure({required double rate, String language = 'en'}); Future<void> speakCard(SymbolCard card, {required String language}); Future<void> speakText(String text, {required String language}); Future<bool> urduAvailable(); Future<void> stopAll(); }`
  - Language tags: `'en'` → TTS `'en-US'`, `'ur'` → TTS `'ur-PK'` (private `_ttsTag` map).
  - Resolution in `speakCard`: recording at `docsDir/<card.recordings[language]>` exists → `stopAll` then play it; else label `labels[language]` → set TTS language, speak; else `labels['en']` → set `en-US`, speak; no label at all → silent no-op. Every path calls `stopAll()` first.

- [ ] **Step 1: Write the failing tests**

Replace `test/services/speech_service_test.dart` content with (preserving the two existing test names so coverage doesn't regress — they appear below adapted to the new constructor):

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/models/board.dart';
import 'package:bolo/services/recording_player.dart';
import 'package:bolo/services/speech_service.dart';

class FakeTts implements Tts {
  final calls = <String>[];
  bool urAvailable = true;
  @override
  Future<void> init() async => calls.add('init');
  @override
  Future<void> setSpeechRate(double rate) async => calls.add('rate:$rate');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> speak(String text) async => calls.add('speak:$text');
  @override
  Future<void> setLanguage(String tag) async => calls.add('lang:$tag');
  @override
  Future<bool> isLanguageAvailable(String tag) async =>
      tag == 'ur-PK' ? urAvailable : true;
}

class FakePlayer implements RecordingPlayer {
  final calls = <String>[];
  @override
  Future<void> play(String p) async => calls.add('play:$p');
  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  late Directory tmp;
  late FakeTts tts;
  late FakePlayer player;
  late SpeechService speech;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bolo_speech');
    tts = FakeTts();
    player = FakePlayer();
    speech = SpeechService(tts, player, docsDir: tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('speakCard stops current utterance then speaks the en label', () async {
    await speech.speakCard(
        const SymbolCard(id: 'eat', labels: {'en': 'eat'}),
        language: 'en');
    expect(tts.calls, containsAllInOrder(['stop', 'lang:en-US', 'speak:eat']));
    expect(player.calls, contains('stop'));
  });

  test('speakCard with no label at all is a silent no-op', () async {
    await speech.speakCard(const SymbolCard(id: 'x', labels: {}),
        language: 'en');
    expect(tts.calls.where((c) => c.startsWith('speak:')), isEmpty);
  });

  test('recording wins over TTS and interrupts everything first', () async {
    Directory('${tmp.path}/recordings').createSync();
    File('${tmp.path}/recordings/eat_ur.m4a').writeAsStringSync('x');
    await speech.speakCard(
        const SymbolCard(
            id: 'eat',
            labels: {'en': 'eat', 'ur': 'کھانا'},
            recordings: {'ur': 'recordings/eat_ur.m4a'}),
        language: 'ur');
    expect(player.calls.last, 'play:${tmp.path}/recordings/eat_ur.m4a');
    expect(tts.calls, contains('stop'));
    expect(tts.calls.where((c) => c.startsWith('speak:')), isEmpty);
  });

  test('missing recording file falls back to ur TTS', () async {
    await speech.speakCard(
        const SymbolCard(
            id: 'eat',
            labels: {'en': 'eat', 'ur': 'کھانا'},
            recordings: {'ur': 'recordings/gone.m4a'}),
        language: 'ur');
    expect(tts.calls, containsAllInOrder(['lang:ur-PK', 'speak:کھانا']));
  });

  test('missing ur label falls back to en TTS with en voice', () async {
    await speech.speakCard(
        const SymbolCard(id: 'ball', labels: {'en': 'ball'}),
        language: 'ur');
    expect(tts.calls, containsAllInOrder(['lang:en-US', 'speak:ball']));
  });

  test('speakText speaks with the requested language voice', () async {
    await speech.speakText('good night', language: 'en');
    expect(tts.calls, containsAllInOrder(['stop', 'lang:en-US', 'speak:good night']));
    await speech.speakText('   ', language: 'en');
    expect(tts.calls.where((c) => c == 'speak:'), isEmpty);
  });

  test('configure sets rate and language; urduAvailable asks the tts', () async {
    await speech.configure(rate: 0.5, language: 'ur');
    expect(tts.calls, containsAllInOrder(['init', 'rate:0.5', 'lang:ur-PK']));
    expect(await speech.urduAvailable(), isTrue);
    tts.urAvailable = false;
    expect(await speech.urduAvailable(), isFalse);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/speech_service_test.dart`
Expected: FAIL — new constructor/members don't exist.

- [ ] **Step 3: Implement the new `lib/services/speech_service.dart`**

```dart
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/board.dart';
import 'recording_player.dart';

abstract class Tts {
  Future<void> init();
  Future<void> setSpeechRate(double rate);
  Future<void> stop();
  Future<void> speak(String text);
  Future<void> setLanguage(String tag);
  Future<bool> isLanguageAvailable(String tag);
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
  @override
  Future<void> setLanguage(String tag) => _tts.setLanguage(tag);
  @override
  Future<bool> isLanguageAvailable(String tag) async =>
      (await _tts.isLanguageAvailable(tag)) == true;
}

class SpeechService {
  SpeechService(this._tts, this._player, {required Directory docsDir})
      : _docsDir = docsDir;

  static const _ttsTag = {'en': 'en-US', 'ur': 'ur-PK'};

  final Tts _tts;
  final RecordingPlayer _player;
  final Directory _docsDir;
  bool _initialized = false;

  Future<void> configure({required double rate, String language = 'en'}) async {
    if (!_initialized) {
      await _tts.init();
      _initialized = true;
    }
    await _tts.setSpeechRate(rate);
    await _tts.setLanguage(_ttsTag[language] ?? 'en-US');
  }

  Future<bool> urduAvailable() => _tts.isLanguageAvailable('ur-PK');

  /// New speech always interrupts everything; nothing queues.
  Future<void> stopAll() async {
    await _player.stop();
    await _tts.stop();
  }

  Future<void> speakCard(SymbolCard card, {required String language}) async {
    final relative = card.recordings[language];
    if (relative != null) {
      final file = File('${_docsDir.path}/$relative');
      if (file.existsSync()) {
        await stopAll();
        await _player.play(file.path);
        return;
      }
    }
    final label = card.labels[language];
    if (label != null && label.isNotEmpty) {
      await _speak(label, language);
      return;
    }
    final en = card.labels['en'];
    if (en == null || en.isEmpty) return; // calm silence, never an error
    await _speak(en, 'en');
  }

  Future<void> speakText(String text, {required String language}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _speak(trimmed, language);
  }

  Future<void> _speak(String text, String language) async {
    await stopAll();
    await _tts.setLanguage(_ttsTag[language] ?? 'en-US');
    await _tts.speak(text);
  }
}
```

- [ ] **Step 4: Update the two call sites**

`lib/features/board/board_providers.dart` — replace the `speechServiceProvider` declaration with:

```dart
final docsDirProvider =
    Provider<Directory>((ref) => throw UnimplementedError('override in main'));

final speechServiceProvider = Provider<SpeechService>((ref) => SpeechService(
    ref.watch(ttsProvider), ref.watch(recordingPlayerProvider),
    docsDir: ref.watch(docsDirProvider)));
```

with imports `import 'dart:io';`, `import '../../services/recording_player.dart';` added.

`lib/main.dart` — add overrides so the app still boots (current file wires `boardStoreProvider` + `ttsProvider`; add these beside them):

```dart
        docsDirProvider.overrideWithValue(docsDir),
        recordingPlayerProvider.overrideWithValue(AudioplayersRecordingPlayer()),
        recorderProvider.overrideWithValue(RecordPackageRecorder()),
```

(where `docsDir` is the existing `getApplicationDocumentsDirectory()` result variable; add the two service imports).

Existing widget tests that override `ttsProvider` now ALSO need `recordingPlayerProvider` + `docsDirProvider` overrides — update every `ProviderScope(overrides: [...])` in `test/features/*.dart` to add:

```dart
        recordingPlayerProvider.overrideWithValue(FakePlayer()),
        docsDirProvider.overrideWithValue(tmp),
```

using the `FakePlayer` from Task 4's test (copy the class into each test file that needs it, or define it once in a new `test/support/fakes.dart` and import — prefer `test/support/fakes.dart` holding FakeTts, FakePlayer, FakeRecorder to stop the copy-paste growth; move the Task 4/5 fakes there and import everywhere).

- [ ] **Step 5: Run tests, full suite, analyze**

Run: `flutter test && flutter analyze`
Expected: all PASS (including updated widget tests), analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/services/speech_service.dart lib/features/board/board_providers.dart lib/main.dart test/
git commit -m "feat: speech resolution (recording > active-language TTS > en TTS)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: BoardNotifier v2 mutations + usage provider

**Files:**
- Modify: `lib/features/board/board_providers.dart`
- Test: `test/features/board_providers_test.dart` (extend)

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces (frozen):
  - `usageStoreProvider = Provider<UsageStore>(...)` — `UsageStore(ref.watch(docsDirProvider))`
  - On `BoardNotifier`:
    - `Future<void> setActiveLanguage(String lang)` — persists + `configure(rate, language)`
    - `Future<void> setRecording(String cardId, String lang, String relativePath)`
    - `Future<void> removeRecording(String cardId, String lang)`
    - `Future<void> setCustomLabels(String cardId, {String? en, String? ur})`
    - `Future<void> moveCardToPage(String categoryId, String cardId, {required bool toMore})` — removes from source list, APPENDS to target list end
    - `reorderCard(String categoryId, int oldIndex, int newIndex, {bool inMore = false})`
    - `addCustomCard({required String categoryId, required String label, required String photoPath, bool toMorePage = false})`
    - `Future<void> speakAndCount(SymbolCard card)` — speech + `usageStore.recordTap(card.id)`; speech first, count fire-and-forget
  - Card-lookup mutations (`toggleHidden`, `setRecording`, `removeRecording`, `setCustomLabels`) walk BOTH `cards` and `moreCards`.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/board_providers_test.dart` (reuse that file's existing container/fixture helpers; the fixture JSON needs a `moreCards` entry — extend the fixture with one More card `{'id': 'phrase-1', 'labels': {'en': 'I need the toilet'}}` in its first category):

```dart
  test('setActiveLanguage persists and reconfigures speech', () async {
    final n = container.read(boardNotifierProvider.notifier);
    await container.read(boardNotifierProvider.future);
    tts.calls.clear();
    await n.setActiveLanguage('ur');
    expect(container.read(boardNotifierProvider).value!.activeLanguage, 'ur');
    expect(tts.calls, contains('lang:ur-PK'));
    final reloaded = await store.load();
    expect(reloaded.activeLanguage, 'ur');
  });

  test('setRecording/removeRecording reach cards on both pages', () async {
    final n = container.read(boardNotifierProvider.notifier);
    await container.read(boardNotifierProvider.future);
    await n.setRecording('eat', 'ur', 'recordings/eat_ur.m4a');
    await n.setRecording('phrase-1', 'en', 'recordings/phrase-1_en.m4a');
    var board = container.read(boardNotifierProvider).value!;
    expect(board.categories.first.cards.firstWhere((c) => c.id == 'eat')
        .recordings['ur'], 'recordings/eat_ur.m4a');
    expect(board.categories.first.moreCards.single.recordings['en'],
        'recordings/phrase-1_en.m4a');
    await n.removeRecording('eat', 'ur');
    board = container.read(boardNotifierProvider).value!;
    expect(board.categories.first.cards.firstWhere((c) => c.id == 'eat')
        .recordings, isEmpty);
  });

  test('setCustomLabels updates both languages', () async {
    final n = container.read(boardNotifierProvider.notifier);
    await container.read(boardNotifierProvider.future);
    await n.setCustomLabels('eat', ur: 'کھانا کھانا');
    final board = container.read(boardNotifierProvider).value!;
    final eat = board.categories.first.cards.firstWhere((c) => c.id == 'eat');
    expect(eat.labels['ur'], 'کھانا کھانا');
    expect(eat.labels['en'], 'eat'); // untouched
  });

  test('moveCardToPage moves between main and more, appending at end', () async {
    final n = container.read(boardNotifierProvider.notifier);
    await container.read(boardNotifierProvider.future);
    final catId = container
        .read(boardNotifierProvider).value!.categories.first.id;
    await n.moveCardToPage(catId, 'eat', toMore: true);
    var cat = container.read(boardNotifierProvider).value!.categories.first;
    expect(cat.cards.any((c) => c.id == 'eat'), isFalse);
    expect(cat.moreCards.last.id, 'eat');
    await n.moveCardToPage(catId, 'eat', toMore: false);
    cat = container.read(boardNotifierProvider).value!.categories.first;
    expect(cat.cards.last.id, 'eat');
  });

  test('reorderCard inMore reorders the More page only', () async {
    final n = container.read(boardNotifierProvider.notifier);
    await container.read(boardNotifierProvider.future);
    final catId = container
        .read(boardNotifierProvider).value!.categories.first.id;
    await n.moveCardToPage(catId, 'eat', toMore: true); // more: [phrase-1, eat]
    await n.reorderCard(catId, 1, 0, inMore: true);
    final cat = container.read(boardNotifierProvider).value!.categories.first;
    expect([for (final c in cat.moreCards) c.id], ['eat', 'phrase-1']);
  });

  test('addCustomCard toMorePage lands on the More page', () async {
    final n = container.read(boardNotifierProvider.notifier);
    await container.read(boardNotifierProvider.future);
    final catId = container
        .read(boardNotifierProvider).value!.categories.first.id;
    await n.addCustomCard(
        categoryId: catId,
        label: 'blanket',
        photoPath: '/tmp/b.jpg',
        toMorePage: true);
    final cat = container.read(boardNotifierProvider).value!.categories.first;
    expect(cat.moreCards.last.labels['en'], 'blanket');
  });

  test('speakAndCount speaks and buffers a usage tap', () async {
    final n = container.read(boardNotifierProvider.notifier);
    await container.read(boardNotifierProvider.future);
    final eat = container.read(boardNotifierProvider).value!
        .categories.first.cards.firstWhere((c) => c.id == 'eat');
    await n.speakAndCount(eat);
    expect(tts.calls.any((c) => c.startsWith('speak:')), isTrue);
    final usage = container.read(usageStoreProvider);
    await usage.flush();
    expect((await usage.load()).perCard['eat']!.count, 1);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/board_providers_test.dart`
Expected: FAIL — methods don't exist.

- [ ] **Step 3: Implement in `lib/features/board/board_providers.dart`**

Add provider + imports:

```dart
import '../../services/usage_store.dart';

final usageStoreProvider =
    Provider<UsageStore>((ref) => UsageStore(ref.watch(docsDirProvider)));
```

In `BoardNotifier`: update `build()`'s configure call to `configure(rate: board.speechRate, language: board.activeLanguage)` (keep the existing try/catch), keep `_update`/`_board` as-is, change `setSpeechRate`'s configure call the same way, and add:

```dart
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

  /// Applies [change] to the card with [cardId] wherever it lives —
  /// main page or More page.
  Future<void> _mapCard(String cardId, SymbolCard Function(SymbolCard) change) {
    return _update(_board.copyWith(categories: [
      for (final cat in _board.categories)
        cat.copyWith(
          cards: [
            for (final c in cat.cards) c.id == cardId ? change(c) : c
          ],
          moreCards: [
            for (final c in cat.moreCards) c.id == cardId ? change(c) : c
          ],
        )
    ]));
  }

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

  Future<void> moveCardToPage(String categoryId, String cardId,
      {required bool toMore}) {
    return _update(_board.copyWith(categories: [
      for (final cat in _board.categories)
        if (cat.id != categoryId)
          cat
        else
          _moveInCategory(cat, cardId, toMore: toMore)
    ]));
  }

  BoardCategory _moveInCategory(BoardCategory cat, String cardId,
      {required bool toMore}) {
    final source = toMore ? cat.cards : cat.moreCards;
    final idx = source.indexWhere((c) => c.id == cardId);
    if (idx < 0) return cat;
    final card = source[idx];
    final newSource = [...source]..removeAt(idx);
    if (toMore) {
      return cat.copyWith(cards: newSource, moreCards: [...cat.moreCards, card]);
    }
    return cat.copyWith(cards: [...cat.cards, card], moreCards: newSource);
  }

  Future<void> speakAndCount(SymbolCard card) async {
    await ref
        .read(speechServiceProvider)
        .speakCard(card, language: _board.activeLanguage);
    ref.read(usageStoreProvider).recordTap(card.id); // fire-and-forget buffer
  }
```

Change `reorderCard` and `addCustomCard` signatures:

```dart
  Future<void> reorderCard(String categoryId, int oldIndex, int newIndex,
      {bool inMore = false}) {
    return _update(_board.copyWith(categories: [
      for (final cat in _board.categories)
        if (cat.id != categoryId)
          cat
        else if (inMore)
          cat.copyWith(moreCards: _moved(cat.moreCards, oldIndex, newIndex))
        else
          cat.copyWith(cards: _moved(cat.cards, oldIndex, newIndex))
    ]));
  }
```

```dart
  Future<void> addCustomCard(
      {required String categoryId,
      required String label,
      required String photoPath,
      bool toMorePage = false}) {
    final card = SymbolCard(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      labels: {'en': label},
      photoPath: photoPath,
    );
    return _update(_board.copyWith(categories: [
      for (final cat in _board.categories)
        if (cat.id != categoryId)
          cat
        else if (toMorePage)
          cat.copyWith(moreCards: [...cat.moreCards, card])
        else
          cat.copyWith(cards: [...cat.cards, card])
    ]));
  }
```

Also rewrite `toggleHidden` to use `_mapCard`:

```dart
  Future<void> toggleHidden(String cardId) =>
      _mapCard(cardId, (c) => c.copyWith(hidden: !c.hidden));
```

- [ ] **Step 4: Run tests, full suite, analyze**

Run: `flutter test && flutter analyze`
Expected: PASS, clean. (`board_screen`'s existing `speakCard` call site still compiles — it changes in Task 7.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/board/board_providers.dart test/features/board_providers_test.dart
git commit -m "feat: v2 board mutations (language, recordings, More page, usage)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Child board v2 — active-language labels, More tile, More page

**Files:**
- Create: `lib/features/board/more_page.dart`, `assets/symbols/more-dots.svg`
- Modify: `lib/features/board/board_screen.dart`, `lib/features/board/card_tile.dart`, `pubspec.yaml` (asset already covered by the `assets/symbols/` folder entry — verify, only add if v1 listed files individually)
- Test: `test/features/board_screen_test.dart` (extend), `test/features/more_page_test.dart` (create)

**Interfaces:**
- Consumes: Task 6 `speakAndCount`, `Board.activeLanguage`, `BoardCategory.moreCards`.
- Produces: `CardTile` gains `required String language` param (label = `labels[language] ?? labels['en'] ?? ''`); `MorePage(categoryIndex: int)` widget; `zeroDurationRoute(Widget)` helper in `more_page.dart`:

```dart
Route<void> zeroDurationRoute(Widget page) => PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
```

- [ ] **Step 1: Create `assets/symbols/more-dots.svg`**

Distinct from the word-card `more.svg` — three sketchy dots, matching the app-icon pencil style:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <g fill="none" stroke="#4A4A44" stroke-width="6" stroke-linecap="round">
    <path d="M 22 50 c 5 -7 14 -4 14 3 c 0 7 -10 10 -14 5 c -4 -5 0 -12 7 -12"/>
    <path d="M 48 52 c 5 -7 14 -4 14 3 c 0 7 -10 10 -14 5 c -4 -5 0 -12 7 -12"/>
    <path d="M 74 50 c 5 -7 14 -4 14 3 c 0 7 -10 10 -14 5 c -4 -5 0 -12 7 -12"/>
  </g>
</svg>
```

- [ ] **Step 2: Write the failing widget tests**

Extend `test/features/board_screen_test.dart` fixture JSON: give its first category a `"moreCards"` list with one card `{"id": "phrase-1", "labels": {"en": "I need the toilet", "ur": "مجھے ٹوائلٹ جانا ہے"}}`, and give an existing main card an `"ur"` label. Add tests (using the file's existing pump helper, with the Task 5 provider overrides in place):

```dart
  testWidgets('More tile shows as the last tile when moreCards exist',
      (tester) async {
    await pumpBoard(tester);
    expect(find.byKey(const ValueKey('more-tile')), findsOneWidget);
  });

  testWidgets('tapping More opens the static More page and back returns',
      (tester) async {
    await pumpBoard(tester);
    await tester.tap(find.byKey(const ValueKey('more-tile')));
    await tester.pump(); // zero-duration route: one pump, no settle needed
    expect(find.text('I need the toilet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('more-back')));
    await tester.pump();
    expect(find.text('I need the toilet'), findsNothing);
  });

  testWidgets('labels follow activeLanguage', (tester) async {
    await pumpBoard(tester); // fixture activeLanguage stays 'en'
    final ctx = tester.element(find.byType(BoardScreen));
    final container = ProviderScope.containerOf(ctx);
    await container.read(boardNotifierProvider.notifier).setActiveLanguage('ur');
    await tester.pump();
    expect(find.text('کھانا'), findsOneWidget); // the ur label from the fixture
  });

  testWidgets('More tile absent when category has no visible more cards',
      (tester) async {
    // pump with a fixture whose moreCards are all hidden or empty
    await pumpBoard(tester, categoryWithoutMore: true);
    expect(find.byKey(const ValueKey('more-tile')), findsNothing);
  });
```

(Adapt helper names to the file's existing style; `categoryWithoutMore` means selecting the fixture category that has no moreCards — add one to the fixture if needed.)

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/board_screen_test.dart`
Expected: FAIL — no `more-tile` key exists.

- [ ] **Step 4: Implement**

`lib/features/board/card_tile.dart` — add the language param; the label line changes:

```dart
  const CardTile(
      {super.key,
      required this.card,
      required this.onTap,
      required this.language});
  final SymbolCard card;
  final VoidCallback onTap;
  final String language;
```

and in `build`: `final label = widget.card.labels[widget.language] ?? widget.card.labels['en'] ?? '';`

`lib/features/board/more_page.dart`:

```dart
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
```

`lib/features/board/board_screen.dart` — three changes inside `data:`:

1. Tabs use active language: `names: [for (final c in board.categories) c.names[board.activeLanguage] ?? c.names['en'] ?? '']`
2. Card tiles get `language: board.activeLanguage` and `onTap: () => ref.read(boardNotifierProvider.notifier).speakAndCount(cards[i])` (replacing the direct `speechServiceProvider` call).
3. More tile: the grid's `itemCount` becomes `cards.length + (hasMore ? 1 : 0)` where `final hasMore = category.moreCards.any((c) => !c.hidden);`, and `itemBuilder` returns, for `i == cards.length` (the last slot):

```dart
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
```

Add `_MoreTile` at the bottom of the file (same chrome as CardTile, no speech, fixed label):

```dart
class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.language, required this.onTap});
  final String language;
  final VoidCallback onTap;

  static const _label = {'en': 'More…', 'ur': 'مزید…'};

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
```

(add `import 'package:flutter_svg/flutter_svg.dart';` and `import 'more_page.dart';`). Check `pubspec.yaml`: if assets are declared as the folder `assets/symbols/`, nothing to add; if individual files, add `assets/symbols/more-dots.svg`.

- [ ] **Step 5: Run tests, full suite, analyze**

Run: `flutter test && flutter analyze`
Expected: PASS (update any existing CardTile constructions in tests to pass `language: 'en'`), clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/board assets/symbols/more-dots.svg pubspec.yaml test/features
git commit -m "feat: child board speaks active language; More tile and static More page

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Usage flush on lifecycle + parent Insights section

**Files:**
- Modify: `lib/main.dart`
- Create: `lib/features/parent/insights_section.dart`
- Modify: `lib/features/parent/parent_screen.dart` (mount the section)
- Test: `test/features/insights_section_test.dart`

**Interfaces:**
- Consumes: Task 3 `UsageStore`/`UsageData`, Task 6 `usageStoreProvider`.
- Produces: `InsightsSection` — a `ConsumerWidget` that loads usage once per build via `FutureBuilder` and renders: "Words this week: N", top-5 most-used rows (label in active language + count), "New words (14 days)" chips. Keys: `ValueKey('insights-section')`, `ValueKey('insights-week-count')`.

- [ ] **Step 1: Flush on app pause**

In `lib/main.dart`, after creating the `ProviderScope`'s container-less overrides we cannot reach the store directly, so wire the observer where the store exists: change `runApp(...)` to build the scope with a child that installs an `AppLifecycleListener`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final docsDir = await getApplicationDocumentsDirectory();
  runApp(ProviderScope(
    overrides: [
      boardStoreProvider.overrideWithValue(BoardStore(docsDir,
          loadDefault: () =>
              rootBundle.loadString('assets/board/default_board.json'))),
      ttsProvider.overrideWithValue(FlutterTtsAdapter()),
      docsDirProvider.overrideWithValue(docsDir),
      recordingPlayerProvider.overrideWithValue(AudioplayersRecordingPlayer()),
      recorderProvider.overrideWithValue(RecordPackageRecorder()),
    ],
    child: const _LifecycleFlush(child: BoloApp()),
  ));
}

/// Flushes buffered usage taps when the app goes to background.
class _LifecycleFlush extends ConsumerStatefulWidget {
  const _LifecycleFlush({required this.child});
  final Widget child;
  @override
  ConsumerState<_LifecycleFlush> createState() => _LifecycleFlushState();
}

class _LifecycleFlushState extends ConsumerState<_LifecycleFlush> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
        onPause: () => ref.read(usageStoreProvider).flush());
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

(Keep the existing v1 main.dart override values — the snippet shows the final shape; merge, don't blindly replace, if Task 5 already edited this file.)

- [ ] **Step 2: Write the failing widget test**

`test/features/insights_section_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/board/board_providers.dart';
import 'package:bolo/features/parent/insights_section.dart';
import 'package:bolo/services/board_store.dart';
// Inline a _json board fixture const in this file (existing convention in
// test/features/*): it must contain cards with ids 'eat' and 'water' so the
// insights rows can resolve labels.

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bolo_insights'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('insights renders week count, top words, new words',
      (tester) async {
    final now = DateTime.now();
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    File('${tmp.path}/usage.json').writeAsStringSync(jsonEncode({
      'perCard': {
        'eat': {
          'count': 7,
          'firstUsed': now.subtract(const Duration(days: 3)).toIso8601String(),
          'lastUsed': now.toIso8601String(),
        },
        'water': {
          'count': 2,
          'firstUsed':
              now.subtract(const Duration(days: 40)).toIso8601String(),
          'lastUsed': now.toIso8601String(),
        },
      },
      'perDay': {day(now): 5, day(now.subtract(const Duration(days: 2))): 4},
    }));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        boardStoreProvider.overrideWithValue(
            BoardStore(tmp, loadDefault: () async => boardFixtureJson)),
        docsDirProvider.overrideWithValue(tmp),
        // + the standard tts/player fakes per test/support/fakes.dart
      ],
      child: const MaterialApp(home: Scaffold(body: InsightsSection())),
    ));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(find.byKey(const ValueKey('insights-week-count')), findsOneWidget);
    expect(find.textContaining('9'), findsOneWidget); // 5 + 4 this week
    expect(find.text('eat'), findsWidgets); // top word row
    expect(find.textContaining('7'), findsOneWidget); // its count
    expect(find.text('eat'), findsWidgets); // new word chip too (firstUsed 3d)
  });
}
```

(Fixture note: the board fixture must contain cards with ids `eat`/`water` so labels resolve; reuse the shared fixture JSON from earlier feature tests. Real disk I/O in this test → the `runAsync` + bounded pump pattern per Global Constraints.)

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/insights_section_test.dart`
Expected: FAIL — `insights_section.dart` missing.

- [ ] **Step 4: Implement `lib/features/parent/insights_section.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/board.dart';
import '../../services/usage_store.dart';
import '../board/board_providers.dart';

/// On-device usage insights. Everything is computed from usage.json locally;
/// nothing ever leaves the phone.
class InsightsSection extends ConsumerWidget {
  const InsightsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              .where((e) =>
                  DateTime.parse(e.key)
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
              Text('Insights',
                  style: Theme.of(context).textTheme.titleMedium),
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
            ],
          );
        },
      ),
    );
  }

  Map<String, String> _labelIndex(Board board) => {
        for (final cat in board.categories)
          for (final card in [...cat.cards, ...cat.moreCards])
            card.id: card.labels[board.activeLanguage] ??
                card.labels['en'] ??
                card.id
      };
}
```

Where `BoloThemeBar.color` is shorthand — use `BoloTheme.tabActive` (import `../../theme.dart`); no new colors.

Mount in `lib/features/parent/parent_screen.dart`: wrap the existing `Column`'s `Expanded(child: ReorderableListView…)` area so insights appear under the slider — add after the speech-speed `Padding`:

```dart
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: 12),
              child: InsightsSection(),
            ),
```

with import `import 'insights_section.dart';`. If vertical space gets tight, the whole parent body may be wrapped in a `ListView` in Task 12's restructure — for now the Column stays.

- [ ] **Step 5: Run tests, full suite, analyze**

Run: `flutter test && flutter analyze`
Expected: PASS, clean.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/features/parent/insights_section.dart lib/features/parent/parent_screen.dart test/features/insights_section_test.dart
git commit -m "feat: local usage insights in parent mode + flush on background

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Record sheet (record / play / delete + custom label editing)

**Files:**
- Create: `lib/features/parent/record_sheet.dart`
- Modify: `lib/features/parent/parent_screen.dart` (mic button per row)
- Test: `test/features/record_sheet_test.dart`

**Interfaces:**
- Consumes: Task 4 `Recorder`/`recorderProvider`, Task 6 `setRecording`/`removeRecording`/`setCustomLabels`, Task 5 `RecordingPlayer` via `recordingPlayerProvider`, `docsDirProvider`.
- Produces: `void showRecordSheet(BuildContext context, WidgetRef ref, SymbolCard card)`; recordings saved to `recordings/<cardId>_<lang>.m4a` under docsDir (relative path stored on the card). Keys: `ValueKey('rec-start-<lang>')`, `ValueKey('rec-stop-<lang>')`, `ValueKey('rec-play-<lang>')`, `ValueKey('rec-delete-<lang>')`, `ValueKey('rec-label-en')`, `ValueKey('rec-label-ur')`, mic row button `ValueKey('mic-<cardId>')`.

- [ ] **Step 1: Write the failing widget tests**

`test/features/record_sheet_test.dart` (uses the shared fakes; FakeRecorder from Task 4):

```dart
// Standard fixture + overrides per test/support/fakes.dart, plus:
//   recorderProvider.overrideWithValue(fakeRecorder)
// Board fixture: one default card 'eat' (symbolAsset) and one custom card
// 'custom-1' (photoPath) so both sheet variants can be pumped.

testWidgets('record→stop stores a relative recording path on the card',
    (tester) async {
  await pumpParent(tester); // helper: pumps ParentScreen with overrides
  await tester.tap(find.byKey(const ValueKey('mic-eat')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('rec-start-ur')));
  await tester.pump();
  expect(find.byKey(const ValueKey('rec-stop-ur')), findsOneWidget);
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const ValueKey('rec-stop-ur')));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  final board = readBoard(tester); // helper: containerOf().read(...).value!
  final eat = board.categories.first.cards.firstWhere((c) => c.id == 'eat');
  expect(eat.recordings['ur'], 'recordings/eat_ur.m4a');
});

testWidgets('play button plays the recording; delete removes it',
    (tester) async {
  // seed: card 'eat' already has recordings{'ur': 'recordings/eat_ur.m4a'}
  // and the file exists under tmp
  await pumpParentWithRecording(tester);
  await tester.tap(find.byKey(const ValueKey('mic-eat')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('rec-play-ur')));
  await tester.pump();
  expect(fakePlayer.calls.any((c) => c.startsWith('play:')), isTrue);
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const ValueKey('rec-delete-ur')));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  final board = readBoard(tester);
  expect(board.categories.first.cards.first.recordings, isEmpty);
});

testWidgets('label fields shown for custom cards only and save edits',
    (tester) async {
  await pumpParent(tester);
  await tester.tap(find.byKey(const ValueKey('mic-eat')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('rec-label-en')), findsNothing);
  await tester.tap(find.byKey(const ValueKey('rec-close')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('mic-custom-1')));
  await tester.pumpAndSettle();
  await tester.enterText(
      find.byKey(const ValueKey('rec-label-ur')), 'کمبل');
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const ValueKey('rec-save-labels')));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  final board = readBoard(tester);
  final custom = board.categories.first.cards
      .firstWhere((c) => c.id == 'custom-1');
  expect(custom.labels['ur'], 'کمبل');
});
```

Write the small helpers (`pumpParent`, `pumpParentWithRecording`, `readBoard`) at the top of this test file; they are ~10 lines each following `parent_screen_test.dart`'s existing pattern.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/record_sheet_test.dart`
Expected: FAIL — no mic key exists.

- [ ] **Step 3: Implement `lib/features/parent/record_sheet.dart`**

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/board.dart';
import '../../services/audio_recorder.dart';
import '../../services/recording_player.dart';
import '../board/board_providers.dart';

void showRecordSheet(BuildContext context, WidgetRef ref, SymbolCard card) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecordSheet(card: card),
  );
}

class _RecordSheet extends ConsumerStatefulWidget {
  const _RecordSheet({required this.card});
  final SymbolCard card;
  @override
  ConsumerState<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends ConsumerState<_RecordSheet> {
  static const _langs = [('en', 'English'), ('ur', 'اردو')];
  static const _maxSeconds = 10;

  String? _recordingLang;
  int _elapsed = 0;
  Timer? _ticker;
  late final TextEditingController _en;
  late final TextEditingController _ur;

  bool get _isCustom => widget.card.photoPath != null;

  @override
  void initState() {
    super.initState();
    _en = TextEditingController(text: widget.card.labels['en'] ?? '');
    _ur = TextEditingController(text: widget.card.labels['ur'] ?? '');
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _en.dispose();
    _ur.dispose();
    super.dispose();
  }

  /// The live card from the provider, so recording changes render immediately.
  SymbolCard get _card {
    final board = ref.watch(boardNotifierProvider).value;
    if (board == null) return widget.card;
    for (final cat in board.categories) {
      for (final c in [...cat.cards, ...cat.moreCards]) {
        if (c.id == widget.card.id) return c;
      }
    }
    return widget.card;
  }

  Future<void> _start(String lang) async {
    final recorder = ref.read(recorderProvider);
    if (!await recorder.hasPermission()) return;
    final docs = ref.read(docsDirProvider);
    Directory('${docs.path}/recordings').createSync(recursive: true);
    final tmpPath = '${docs.path}/recordings/${widget.card.id}_$lang.m4a.tmp';
    await recorder.start(tmpPath);
    if (!mounted) return;
    setState(() {
      _recordingLang = lang;
      _elapsed = 0;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= _maxSeconds) _stop(lang);
    });
  }

  Future<void> _stop(String lang) async {
    _ticker?.cancel();
    final recorder = ref.read(recorderProvider);
    final tmpPath = await recorder.stop();
    if (!mounted) return;
    setState(() => _recordingLang = null);
    if (tmpPath == null) return;
    final finalPath = tmpPath.replaceFirst(RegExp(r'\.tmp$'), '');
    try {
      File(tmpPath).renameSync(finalPath);
    } catch (_) {
      return; // failed save = no recording; card unchanged
    }
    await ref.read(boardNotifierProvider.notifier).setRecording(
        widget.card.id, lang, 'recordings/${widget.card.id}_$lang.m4a');
  }

  Future<void> _play(String lang) async {
    final rel = _card.recordings[lang];
    if (rel == null) return;
    final docs = ref.read(docsDirProvider);
    await ref.read(recordingPlayerProvider).play('${docs.path}/$rel');
  }

  Future<void> _delete(String lang) async {
    final rel = _card.recordings[lang];
    if (rel != null) {
      final docs = ref.read(docsDirProvider);
      try {
        File('${docs.path}/$rel').deleteSync();
      } catch (_) {}
    }
    await ref
        .read(boardNotifierProvider.notifier)
        .removeRecording(widget.card.id, lang);
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    return Padding(
      padding: EdgeInsetsDirectional.only(
          start: 16,
          end: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
              child: Text(card.labels['en'] ?? card.id,
                  style: Theme.of(context).textTheme.titleMedium)),
          IconButton(
            key: const ValueKey('rec-close'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ]),
        for (final (lang, name) in _langs)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
            child: Row(children: [
              SizedBox(width: 72, child: Text(name)),
              if (_recordingLang == lang) ...[
                Text('${_elapsed}s'),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: ValueKey('rec-stop-$lang'),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  onPressed: () => _stop(lang),
                ),
              ] else ...[
                OutlinedButton.icon(
                  key: ValueKey('rec-start-$lang'),
                  icon: const Icon(Icons.mic),
                  label: Text(card.recordings[lang] == null
                      ? 'Record'
                      : 'Re-record'),
                  onPressed:
                      _recordingLang == null ? () => _start(lang) : null,
                ),
                if (card.recordings[lang] != null) ...[
                  IconButton(
                    key: ValueKey('rec-play-$lang'),
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => _play(lang),
                  ),
                  IconButton(
                    key: ValueKey('rec-delete-$lang'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(lang),
                  ),
                ],
              ],
            ]),
          ),
        if (_isCustom) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('rec-label-en'),
            controller: _en,
            decoration: const InputDecoration(labelText: 'Label (English)'),
          ),
          TextField(
            key: const ValueKey('rec-label-ur'),
            controller: _ur,
            decoration: const InputDecoration(labelText: 'Label (اردو)'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: const ValueKey('rec-save-labels'),
              onPressed: () async {
                await ref.read(boardNotifierProvider.notifier).setCustomLabels(
                    widget.card.id,
                    en: _en.text,
                    ur: _ur.text);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ]),
    );
  }
}
```

Add the mic button in `parent_screen.dart` — the row's `trailing` becomes a `Row(mainAxisSize: MainAxisSize.min, children: [...])` with an `IconButton(key: ValueKey('mic-${card.id}'), icon: const Icon(Icons.mic_none), onPressed: () => showRecordSheet(context, ref, card))` before the existing Semantics-wrapped Switch. Import `record_sheet.dart`.

- [ ] **Step 4: Run tests, full suite, analyze**

Run: `flutter test && flutter analyze`
Expected: PASS, clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/parent/record_sheet.dart lib/features/parent/parent_screen.dart test/features/record_sheet_test.dart
git commit -m "feat: per-card voice recording sheet with custom label editing

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Language switch + Urdu availability note (parent mode)

**Files:**
- Modify: `lib/features/parent/parent_screen.dart`
- Test: `test/features/parent_screen_test.dart` (extend)

**Interfaces:**
- Consumes: Task 6 `setActiveLanguage`, Task 5 `urduAvailable()`.
- Produces: `SegmentedButton<String>` with key `ValueKey('language-switch')` at the top of the parent body; parent card rows show `labels[activeLanguage] ?? labels['en']`; a `ValueKey('ur-unavailable-note')` Text shown only when active language is `ur` AND `urduAvailable()` is false.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/parent_screen_test.dart`:

```dart
  testWidgets('language switch persists and re-labels rows', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('اردو'));
      await tester.pumpAndSettle();
    });
    final ctx = tester.element(find.byType(ParentScreen));
    final board =
        ProviderScope.containerOf(ctx).read(boardNotifierProvider).value!;
    expect(board.activeLanguage, 'ur');
    expect(find.text('کھانا'), findsOneWidget); // eat's ur label from fixture
  });

  testWidgets('ur-unavailable note appears only when voice missing',
      (tester) async {
    tts.urAvailable = false; // FakeTts flag from test/support/fakes.dart
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ur-unavailable-note')), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('اردو'));
      await tester.pumpAndSettle();
    });
    expect(find.byKey(const ValueKey('ur-unavailable-note')), findsOneWidget);
  });
```

(The fixture `_json` in this file needs `"ur": "کھانا"` added to the eat card's labels.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/parent_screen_test.dart`
Expected: FAIL — no اردو segment exists.

- [ ] **Step 3: Implement in `parent_screen.dart`**

At the top of the `data:` builder's `Column` children (before the category dropdown Row), insert:

```dart
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 0),
              child: Column(children: [
                SegmentedButton<String>(
                  key: const ValueKey('language-switch'),
                  segments: const [
                    ButtonSegment(value: 'en', label: Text('English')),
                    ButtonSegment(value: 'ur', label: Text('اردو')),
                  ],
                  selected: {board.activeLanguage},
                  onSelectionChanged: (s) => ref
                      .read(boardNotifierProvider.notifier)
                      .setActiveLanguage(s.first),
                ),
                if (board.activeLanguage == 'ur')
                  FutureBuilder<bool>(
                    future: ref.read(speechServiceProvider).urduAvailable(),
                    builder: (context, snap) => snap.data == false
                        ? const Padding(
                            padding: EdgeInsetsDirectional.only(top: 4),
                            child: Text(
                              'Urdu voice not available on this phone — recordings will be used.',
                              key: ValueKey('ur-unavailable-note'),
                              style: TextStyle(fontSize: 12),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
              ]),
            ),
```

And update the two `labels['en']` reads in the parent list to `labels[board.activeLanguage] ?? labels['en']` (row `title` and the category dropdown's `names['en']` similarly → `names[board.activeLanguage] ?? names['en']`).

- [ ] **Step 4: Run tests, full suite, analyze**

Run: `flutter test && flutter analyze`
Expected: PASS, clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/parent/parent_screen.dart test/features/parent_screen_test.dart
git commit -m "feat: parent-mode language switch with Urdu availability note

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Type-to-speak (parent tool)

**Files:**
- Create: `lib/features/parent/type_to_speak.dart`
- Modify: `lib/features/parent/parent_screen.dart` (mount above InsightsSection)
- Test: `test/features/type_to_speak_test.dart`

**Interfaces:**
- Consumes: Task 5 `speakText`, `Board.activeLanguage`.
- Produces: `TypeToSpeak` ConsumerStatefulWidget. Keys: `ValueKey('tts-field')`, `ValueKey('tts-speak')`, recent chips `ValueKey('tts-recent-<index>')`. Max 10 recents, newest first, session-only.

- [ ] **Step 1: Write the failing tests**

`test/features/type_to_speak_test.dart` (standard overrides; pump `TypeToSpeak` directly inside a MaterialApp Scaffold with a ProviderScope whose board fixture is the shared one):

```dart
testWidgets('speak button speaks trimmed text in active language and stores a recent',
    (tester) async {
  await pumpTool(tester);
  await tester.enterText(find.byKey(const ValueKey('tts-field')), '  good girl ');
  await tester.tap(find.byKey(const ValueKey('tts-speak')));
  await tester.pump();
  expect(tts.calls, contains('speak:good girl'));
  expect(find.byKey(const ValueKey('tts-recent-0')), findsOneWidget);
  expect(find.text('good girl'), findsWidgets);
});

testWidgets('empty input is a no-op', (tester) async {
  await pumpTool(tester);
  await tester.enterText(find.byKey(const ValueKey('tts-field')), '   ');
  await tester.tap(find.byKey(const ValueKey('tts-speak')));
  await tester.pump();
  expect(tts.calls.where((c) => c.startsWith('speak:')), isEmpty);
});

testWidgets('recents cap at 10, newest first, tap re-speaks', (tester) async {
  await pumpTool(tester);
  for (var i = 0; i < 12; i++) {
    await tester.enterText(
        find.byKey(const ValueKey('tts-field')), 'word$i');
    await tester.tap(find.byKey(const ValueKey('tts-speak')));
    await tester.pump();
  }
  expect(find.byKey(const ValueKey('tts-recent-9')), findsOneWidget);
  expect(find.byKey(const ValueKey('tts-recent-10')), findsNothing);
  expect(find.text('word11'), findsWidgets); // newest first
  tts.calls.clear();
  await tester.tap(find.byKey(const ValueKey('tts-recent-0')));
  await tester.pump();
  expect(tts.calls, contains('speak:word11'));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/type_to_speak_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement `lib/features/parent/type_to_speak.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../board/board_providers.dart';

/// Parent tool: type anything, the phone speaks it in the active language.
/// Session-only recents; nothing is persisted.
class TypeToSpeak extends ConsumerStatefulWidget {
  const TypeToSpeak({super.key});
  @override
  ConsumerState<TypeToSpeak> createState() => _TypeToSpeakState();
}

class _TypeToSpeakState extends ConsumerState<TypeToSpeak> {
  final _controller = TextEditingController();
  final List<String> _recents = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _speak([String? text]) async {
    final t = (text ?? _controller.text).trim();
    if (t.isEmpty) return;
    final lang = ref.read(boardNotifierProvider).value?.activeLanguage ?? 'en';
    await ref.read(speechServiceProvider).speakText(t, language: lang);
    if (text == null) {
      setState(() {
        _recents.remove(t);
        _recents.insert(0, t);
        if (_recents.length > 10) _recents.removeLast();
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Type to speak', style: Theme.of(context).textTheme.titleMedium),
      Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('tts-field'),
            controller: _controller,
            decoration: const InputDecoration(hintText: 'Type a word or sentence'),
            onSubmitted: (_) => _speak(),
          ),
        ),
        IconButton(
          key: const ValueKey('tts-speak'),
          icon: const Icon(Icons.volume_up),
          onPressed: _speak,
        ),
      ]),
      if (_recents.isNotEmpty)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 4),
          child: Wrap(spacing: 8, children: [
            for (var i = 0; i < _recents.length; i++)
              ActionChip(
                key: ValueKey('tts-recent-$i'),
                label: Text(_recents[i]),
                onPressed: () => _speak(_recents[i]),
              ),
          ]),
        ),
    ]);
  }
}
```

Mount in `parent_screen.dart` directly above the `InsightsSection` mount, inside the same horizontal padding. Import it.

- [ ] **Step 4: Run tests, full suite, analyze**

Run: `flutter test && flutter analyze`
Expected: PASS, clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/parent/type_to_speak.dart lib/features/parent/parent_screen.dart test/features/type_to_speak_test.dart
git commit -m "feat: type-to-speak parent tool with session recents

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Parent Main/More management (sectioned reorder + add-sheet toggle)

**Files:**
- Modify: `lib/features/parent/parent_screen.dart`, `lib/features/parent/add_card_sheet.dart`
- Test: `test/features/parent_screen_test.dart` + `test/features/add_card_test.dart` (extend)

**Interfaces:**
- Consumes: Task 6 `moveCardToPage`, `reorderCard(..., inMore:)`, `addCustomCard(..., toMorePage:)`.
- Produces: the parent reorder list renders `[...main rows, divider(ValueKey('more-divider')), ...more rows]`; index math per the implementation below; add-card sheet gains `SwitchListTile` key `ValueKey('add-card-more-toggle')`. Parent body becomes a `ListView` (the Column is out of vertical room by now) — the reorder list gets `shrinkWrap: true, physics: const NeverScrollableScrollPhysics()`.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/parent_screen_test.dart` (fixture now needs a `moreCards` entry — add `{"id":"phrase-1","labels":{"en":"I need the toilet"}}` to the fixture category):

```dart
  testWidgets('divider row separates main and more sections', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-divider')), findsOneWidget);
    // divider sits after the main cards, before phrase-1's row
    final dividerY =
        tester.getTopLeft(find.byKey(const ValueKey('more-divider'))).dy;
    final phraseY =
        tester.getTopLeft(find.byKey(const ValueKey('row-phrase-1'))).dy;
    expect(dividerY, lessThan(phraseY));
  });
```

Cross-divider moves and in-section reorders are exercised at the notifier level (Task 6 tests) — the widget test for drag simulation of ReorderableListView is flaky; instead unit-test the INDEX-TRANSLATION function this task extracts (see Step 3):

```dart
  group('reorder index translation', () {
    // mainCount = 2 → indices: 0,1 = main; 2 = divider; 3.. = more
    test('within main', () {
      expect(translateReorder(2, 0, 1), (ReorderAction.mainReorder, 0, 1));
    });
    test('within more', () {
      expect(translateReorder(2, 3, 4), (ReorderAction.moreReorder, 0, 1));
    });
    test('main to more (crossing down past divider)', () {
      expect(translateReorder(2, 0, 4), (ReorderAction.moveToMore, 0, 0));
    });
    test('more to main (crossing up past divider)', () {
      expect(translateReorder(2, 3, 1), (ReorderAction.moveToMain, 0, 1));
    });
    test('dragging the divider itself is a no-op', () {
      expect(translateReorder(2, 2, 0), (ReorderAction.none, 0, 0));
    });
  });
```

And to `test/features/add_card_test.dart`:

```dart
  testWidgets('More-page toggle routes the new card to moreCards',
      (tester) async {
    await pumpParentAndOpenSheet(tester); // existing helper in this file
    await tester.enterText(
        find.byKey(const ValueKey('add-card-label')), 'blanket');
    await tester.tap(find.byKey(const ValueKey('add-card-more-toggle')));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('add-card-gallery')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final board = readBoard(tester);
    expect(board.categories.first.moreCards.last.labels['en'], 'blanket');
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/parent_screen_test.dart test/features/add_card_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `parent_screen.dart`, add the pure translation function at top level (exported for the unit test):

```dart
enum ReorderAction { mainReorder, moreReorder, moveToMore, moveToMain, none }

/// Translates ReorderableListView indices over the combined
/// [main..., divider, more...] children list into a section-level action.
/// Returns (action, oldIndex, newIndex) in SECTION-LOCAL indices.
(ReorderAction, int, int) translateReorder(
    int mainCount, int oldIndex, int newIndex) {
  final divider = mainCount;
  if (oldIndex == divider) return (ReorderAction.none, 0, 0);
  final fromMain = oldIndex < divider;
  // onReorderItem semantics: newIndex is already adjusted for removal.
  final toMain = newIndex <= divider - (fromMain ? 1 : 0);
  if (fromMain && toMain) return (ReorderAction.mainReorder, oldIndex, newIndex);
  if (!fromMain && !toMain) {
    return (
      ReorderAction.moreReorder,
      oldIndex - divider - 1,
      newIndex - divider - 1,
    );
  }
  if (fromMain) {
    return (ReorderAction.moveToMore, oldIndex, 0);
  }
  return (ReorderAction.moveToMain, oldIndex - divider - 1, newIndex);
}
```

The reorder list children become:

```dart
                children: [
                  for (final card in category.cards) _cardRow(board, card),
                  const ListTile(
                    key: ValueKey('more-divider'),
                    dense: true,
                    title: Text('— More page —',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12)),
                  ),
                  for (final card in category.moreCards) _cardRow(board, card),
                ],
```

with `_cardRow(Board board, SymbolCard card)` extracted from the existing row builder (unchanged content: thumb, title, mic, switch). `onReorderItem` becomes:

```dart
                onReorderItem: (oldIndex, newIndex) {
                  final n = ref.read(boardNotifierProvider.notifier);
                  final (action, from, to) = translateReorder(
                      category.cards.length, oldIndex, newIndex);
                  switch (action) {
                    case ReorderAction.mainReorder:
                      n.reorderCard(category.id, from, to);
                    case ReorderAction.moreReorder:
                      n.reorderCard(category.id, from, to, inMore: true);
                    case ReorderAction.moveToMore:
                      n.moveCardToPage(category.id,
                          category.cards[from].id, toMore: true);
                    case ReorderAction.moveToMain:
                      n.moveCardToPage(category.id,
                          category.moreCards[from].id, toMore: false);
                    case ReorderAction.none:
                      break;
                  }
                },
```

Restructure the parent body Column into a `ListView` (children unchanged order: language switch, dropdown+add row, reorder list with `shrinkWrap: true, physics: NeverScrollableScrollPhysics()`, slider, TypeToSpeak, InsightsSection). Remove the `Expanded` wrappers that a ListView makes invalid.

In `add_card_sheet.dart`: convert the builder content to a `StatefulBuilder` (or small StatefulWidget) holding `var toMore = false;`, add above the buttons row:

```dart
        SwitchListTile(
          key: const ValueKey('add-card-more-toggle'),
          contentPadding: EdgeInsetsDirectional.zero,
          title: const Text('Put on More page'),
          value: toMore,
          onChanged: (v) => setSheetState(() => toMore = v),
        ),
```

and pass `toMorePage: toMore` through `_pick` into `addCustomCard` (add a `{required bool toMorePage}` param to `_pick`).

- [ ] **Step 4: Run tests, full suite, analyze**

Run: `flutter test && flutter analyze`
Expected: PASS, clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/parent test/features
git commit -m "feat: main/More card management in parent mode

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 13: Backup / restore

**Files:**
- Create: `lib/services/backup_service.dart`
- Modify: `lib/features/parent/parent_screen.dart` (Backup/Restore row at the bottom)
- Test: `test/services/backup_service_test.dart`

**Interfaces:**
- Consumes: `archive` (ZipEncoder/ZipDecoder), `share_plus`, `file_selector`, Task 1 models.
- Produces:
  - `class BackupService { BackupService(Directory docsDir); Future<File> createBackup(); Future<void> restore(File backupFile); }`
  - Backup file: `<systemTemp>/bolo-backup-YYYY-MM-DD.bolo` — a zip containing `board.json`, `usage.json` (if present), `photos/**`, `recordings/**`.
  - `restore` throws `FormatException` on invalid archives; on success the docs dir contains the restored files and every `photoPath` is REWRITTEN to `<docsDir>/photos/<basename>` (v1 stored absolute paths from the old phone — they must be re-anchored).
  - UI: `ValueKey('backup-button')`, `ValueKey('restore-button')`, confirm dialog `ValueKey('restore-confirm')`.

- [ ] **Step 1: Write the failing tests**

`test/services/backup_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/services/backup_service.dart';

void main() {
  late Directory docs;
  setUp(() {
    docs = Directory.systemTemp.createTempSync('bolo_backup');
    Directory('${docs.path}/photos').createSync();
    Directory('${docs.path}/recordings').createSync();
    File('${docs.path}/board.json').writeAsStringSync(jsonEncode({
      'version': 2,
      'speechRate': 0.45,
      'activeLanguage': 'ur',
      'categories': [
        {
          'id': 'wants',
          'names': {'en': 'Wants'},
          'cards': [
            {
              'id': 'custom-1',
              'labels': {'en': 'blanket'},
              'photoPath': '${docs.path}/photos/b.jpg',
            }
          ],
        }
      ],
    }));
    File('${docs.path}/photos/b.jpg').writeAsStringSync('img');
    File('${docs.path}/recordings/eat_ur.m4a').writeAsStringSync('aud');
    File('${docs.path}/usage.json').writeAsStringSync('{"perCard":{},"perDay":{}}');
  });
  tearDown(() => docs.deleteSync(recursive: true));

  test('backup → wipe → restore round-trips content and re-anchors photoPath',
      () async {
    final service = BackupService(docs);
    final backup = await service.createBackup();
    expect(backup.path, endsWith('.bolo'));

    // Restore into a FRESH directory (simulates a new phone).
    final newDocs = Directory.systemTemp.createTempSync('bolo_newphone');
    addTearDown(() => newDocs.deleteSync(recursive: true));
    await BackupService(newDocs).restore(backup);

    final board = jsonDecode(
            File('${newDocs.path}/board.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(board['activeLanguage'], 'ur');
    final card = board['categories'][0]['cards'][0] as Map<String, dynamic>;
    expect(card['photoPath'], '${newDocs.path}/photos/b.jpg'); // re-anchored
    expect(File('${newDocs.path}/photos/b.jpg').readAsStringSync(), 'img');
    expect(File('${newDocs.path}/recordings/eat_ur.m4a').readAsStringSync(),
        'aud');
    expect(File('${newDocs.path}/usage.json').existsSync(), isTrue);
  });

  test('invalid archive throws and leaves existing data untouched', () async {
    final bad = File('${Directory.systemTemp.path}/not-a-backup.bolo')
      ..writeAsStringSync('garbage');
    addTearDown(() => bad.deleteSync());
    final before = File('${docs.path}/board.json').readAsStringSync();
    await expectLater(
        BackupService(docs).restore(bad), throwsA(isA<FormatException>()));
    expect(File('${docs.path}/board.json').readAsStringSync(), before);
  });

  test('zip without a parseable board.json is rejected', () async {
    final service = BackupService(docs);
    final backup = await service.createBackup();
    // Corrupt the board entry by rebuilding a zip with junk board.json
    final tampered = await tamperBoardEntry(backup); // helper below
    await expectLater(
        BackupService(docs).restore(tampered), throwsA(isA<FormatException>()));
  });
}
```

(`tamperBoardEntry` helper: decode the zip with `ZipDecoder`, replace the `board.json` entry bytes with `{not json`, re-encode with `ZipEncoder` to a new temp file — ~12 lines, write it in the test file.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/backup_service_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement `lib/services/backup_service.dart`**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import '../models/board.dart';

/// Creates and restores `.bolo` backups: a zip of board.json, usage.json,
/// photos/ and recordings/. Restore is staged: nothing in the live docs dir
/// changes until the archive has fully validated.
class BackupService {
  BackupService(this._docsDir);
  final Directory _docsDir;

  Future<File> createBackup() async {
    final archive = Archive();
    void addFile(String relative) {
      final f = File('${_docsDir.path}/$relative');
      if (!f.existsSync()) return;
      final bytes = f.readAsBytesSync();
      archive.addFile(ArchiveFile(relative, bytes.length, bytes));
    }

    addFile('board.json');
    addFile('usage.json');
    for (final dir in ['photos', 'recordings']) {
      final d = Directory('${_docsDir.path}/$dir');
      if (!d.existsSync()) continue;
      for (final f in d.listSync().whereType<File>()) {
        addFile('$dir/${f.uri.pathSegments.last}');
      }
    }

    final now = DateTime.now();
    final name = 'bolo-backup-${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}.bolo';
    final out = File('${Directory.systemTemp.path}/$name');
    out.writeAsBytesSync(ZipEncoder().encode(archive));
    return out;
  }

  Future<void> restore(File backupFile) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(backupFile.readAsBytesSync());
    } catch (_) {
      throw const FormatException('Not a Bolo backup file.');
    }

    final boardEntry = archive.findFile('board.json');
    if (boardEntry == null) {
      throw const FormatException('Backup contains no board.');
    }
    final Board board;
    try {
      board = Board.fromJson(jsonDecode(utf8.decode(boardEntry.content))
          as Map<String, dynamic>);
    } catch (_) {
      throw const FormatException('Backup board is not readable.');
    }

    // Stage everything first; only touch the live dir after full success.
    final staging = Directory.systemTemp.createTempSync('bolo_restore');
    try {
      for (final entry in archive.files.where((f) => f.isFile)) {
        final out = File('${staging.path}/${entry.name}');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(entry.content);
      }

      // Re-anchor photo paths to THIS device's docs dir.
      final reanchored = board.copyWith(categories: [
        for (final cat in board.categories)
          cat.copyWith(
            cards: [for (final c in cat.cards) _reanchor(c)],
            moreCards: [for (final c in cat.moreCards) _reanchor(c)],
          )
      ]);
      File('${staging.path}/board.json')
          .writeAsStringSync(jsonEncode(reanchored.toJson()));

      // Swap into place.
      for (final dir in ['photos', 'recordings']) {
        final target = Directory('${_docsDir.path}/$dir');
        final staged = Directory('${staging.path}/$dir');
        if (target.existsSync()) target.deleteSync(recursive: true);
        if (staged.existsSync()) {
          target.createSync(recursive: true);
          for (final f in staged.listSync().whereType<File>()) {
            f.copySync('${target.path}/${f.uri.pathSegments.last}');
          }
        }
      }
      for (final name in ['board.json', 'usage.json']) {
        final staged = File('${staging.path}/$name');
        if (staged.existsSync()) {
          staged.copySync('${_docsDir.path}/$name');
        }
      }
    } finally {
      try {
        staging.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  SymbolCard _reanchor(SymbolCard card) {
    final photo = card.photoPath;
    if (photo == null) return card;
    final base = photo.split('/').last;
    // SymbolCard has no copyWith(photoPath:) — rebuild explicitly.
    return SymbolCard(
      id: card.id,
      labels: card.labels,
      symbolAsset: card.symbolAsset,
      photoPath: '${_docsDir.path}/photos/$base',
      hidden: card.hidden,
      recordings: card.recordings,
    );
  }
}
```

- [ ] **Step 4: Parent UI row**

In `parent_screen.dart`, append to the ListView (after InsightsSection):

```dart
            Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('backup-button'),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Backup'),
                    onPressed: () async {
                      final docs = ref.read(docsDirProvider);
                      await ref.read(usageStoreProvider).flush();
                      final file =
                          await BackupService(docs).createBackup();
                      await SharePlus.instance.share(
                          ShareParams(files: [XFile(file.path)]));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('restore-button'),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Restore'),
                    onPressed: () => _restoreFlow(context),
                  ),
                ),
              ]),
            ),
```

with the flow method on the state class:

```dart
  Future<void> _restoreFlow(BuildContext context) async {
    const typeGroup = XTypeGroup(label: 'Bolo backup', extensions: ['bolo']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('restore-confirm'),
        title: const Text('Restore backup?'),
        content: Text(
            'This replaces the current board, photos, and recordings with the backup "${picked.name}". This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await BackupService(ref.read(docsDirProvider))
          .restore(File(picked.path));
      ref.invalidate(boardNotifierProvider); // reload from disk
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
```

Imports: `backup_service.dart`, `package:share_plus/share_plus.dart`, `package:file_selector/file_selector.dart`, `dart:io`. (If the resolved share_plus major still uses the static `Share.shareXFiles([XFile(...)])` API instead of `SharePlus.instance.share`, use that form — adapter-level detail, the button contract stands.)

- [ ] **Step 5: Run tests, full suite, analyze**

Run: `flutter test && flutter analyze`
Expected: PASS, clean.

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup_service.dart lib/features/parent/parent_screen.dart test/services/backup_service_test.dart
git commit -m "feat: .bolo backup and staged restore with photo re-anchoring

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 14: Maestro More-hop, version bump, full verification

**Files:**
- Modify: `.maestro/board-smoke.yaml`, `pubspec.yaml` (version)

**Interfaces:**
- Consumes: everything.
- Produces: v2.0.0+2, green suite, passing Maestro on iOS sim AND Android emulator, release APK builds.

- [ ] **Step 1: Version bump**

`pubspec.yaml`: `version: 2.0.0+2`

- [ ] **Step 2: Extend the Maestro flow**

In `.maestro/board-smoke.yaml`, after the existing tap-card assertion block and BEFORE the gate step, insert the More-page hop (the default board's Wants category now has a More page):

```yaml
# More page: fixed last tile opens a static page; back returns
- tapOn: "More…"
- assertVisible: "I want to eat"
- tapOn: "I want to eat"
- assertVisible: "I want to eat"
- tapOn:
    id: "more-back"
- assertVisible: "eat"
```

Add `Semantics(identifier: 'more-back', ...)` around the MorePage back IconButton if Maestro cannot see the ValueKey (same pattern as the v1 `switch-<id>` semantics identifiers; do this in `more_page.dart`).

- [ ] **Step 3: Full local verification**

```bash
flutter analyze && flutter test
flutter run -d <ios-sim> --dart-define=BOLO_GATE_MS=800   # background task
maestro test .maestro/board-smoke.yaml                     # run TWICE back-to-back
```

Then Android: boot the `bolo` AVD, install a `--dart-define=BOLO_GATE_MS=800` debug build, run the flow twice, then `flutter build apk --release` and confirm `✓ Built`.
Expected: Maestro 9+6 steps pass twice on both platforms; release build succeeds.
Known flake: Maestro's iOS driver occasionally times out on install — retry once before investigating.

- [ ] **Step 4: Migration smoke on a real v1 board**

On the iOS simulator (or emulator): install v1.0.0 (tag `v1.0.0` build or the release APK), tap a few cards, toggle one hidden in parent mode; then install the v2 build OVER it and verify: board order unchanged, hidden card still hidden, Urdu switch shows translated labels, More… tile appeared. Report what you observed — this is the one test no unit test covers end-to-end on device.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml .maestro/board-smoke.yaml lib/features/board/more_page.dart
git commit -m "chore: v2.0.0, Maestro More-page hop

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Post-plan (controller, not a task)

Merge flow after final review: merge `feature/v2` → `main`, tag `v2.0.0`, GitHub release with updated `bolo.apk` + `bolo-v2.0.0.apk` assets (QR keeps working via `latest`), sync `release`/`sandbox`/`dev` branches. Adil reviews the Urdu translations (Task 2 report) before family rollout.
