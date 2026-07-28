# Bolo v2 — "Her voice grows" — Design Spec

Date: 2026-07-28
Status: approved pending user review
Baseline: v1.0.0 (`main`, tag v1.0.0) — shipped tap-to-speak MVP

## Context and goal

v1 is on the family phone: a static tap-to-speak board the child is currently learning.
v2 serves the same single family (explicitly NOT productizing yet). Home language is
mixed Urdu and English. The bundle, agreed as "A: Her voice grows":

1. Parent voice recording per card, per language
2. Bilingual Urdu/English board (one active language at a time)
3. More-words pages per category
4. Local usage insights
5. Type-to-speak parent tool
6. Backup / restore

The design law carried from v1: **the board never rearranges itself.** The child
learns card positions as motor memory; every v2 feature must leave existing card
positions untouched.

## Non-goals (deliberate)

- Sentence strip — revisit when the child starts combining words; it changes the
  interaction model she is mid-learning.
- Grid-size setting, multiple profiles, scanning access, Play Store readiness.
- Any network feature. No telemetry, no cloud, no analytics SDK. Insights are
  local files on the phone, full stop.
- Auto-suggested / contextual vocabulary. "Relevant more words" is delivered as
  static parent-curated More pages, never algorithmic reordering.

## Dependencies (new closed list)

v1's five (`flutter_riverpod`, `flutter_tts`, `flutter_svg`, `path_provider`,
`image_picker`) plus exactly five more, each tied to one feature:

| Package | Feature | Why |
|---|---|---|
| `record` | Recording | mic capture to m4a |
| `audioplayers` | Recording | play recorded files (flutter_tts cannot) |
| `archive` | Backup | zip/unzip, pure Dart |
| `share_plus` | Backup | hand backup file to the OS share sheet |
| `file_selector` | Restore | pick a `.bolo` file |

No codegen, no build_runner, nothing else. `flutter_lints` stays dev-only.

## Data model and migration

### board.json v2

- `Board`: add `version: 2`, `activeLanguage: "en" | "ur"` (default `"en"`).
  `speechRate`, `categories` unchanged.
- `SymbolCard`: add `recordings: {"<lang>": "<relative path>"}` — language-keyed
  like `labels`, paths relative to the app documents dir (same convention as
  `photoPath`). Absent key = no recording.
- `Category`: add optional `moreCards: [SymbolCard]`. Empty/absent = no More page.

### usage.json (new, separate file)

Separate from board.json on purpose: different write cadence, and a corrupt
counter file must never take the board down. Structure:

- per-card: `{count, firstUsed, lastUsed}` (ISO dates, card id keyed)
- per-day buckets: `{"2026-07-28": totalTaps}` (kept ~90 days, pruned on write)

Written with the same tmp-file + rename atomic pattern as board.json.
Corrupt usage.json → rename `.corrupt`, start fresh, board unaffected.

### Migration

`BoardStore.load()` reads a file without `version` → v1. In memory: add
`version: 2`, `activeLanguage: "en"`, empty `recordings`, no `moreCards`; merge
shipped Urdu labels into **default cards by card id** (custom cards untouched);
save back atomically. Card order and hidden flags are never modified. The
corrupt-recovery path is unchanged. Migration is idempotent and covered by tests.

### Urdu label set

The default board's 27 cards ship with reviewed Urdu labels (`labels.ur`) in
`assets/board/default_board.json`. Adil authors/reviews the translations (native
speaker input required — see Open inputs).

## Feature: voice recording

Parent mode only. No recording UI ever appears on the child board.

- Each card row in parent mode gets a mic button → **Record sheet** for that card:
  two rows (English / اردو), each with record (tap start/stop, 10 s max, visible
  timer), play, re-record, delete.
- The Record sheet is also where both language labels of a **custom** card can be
  edited. Default cards' labels are not editable (they ship curated).
- Files: `recordings/<cardId>_<lang>.m4a`, AAC mono. Written to a tmp path then
  renamed. Re-record overwrites; delete removes file + map entry.
- Recorder and player sit behind `Recorder` / `RecordingPlayer` interfaces
  (mirroring v1's `Tts` seam) with fakes for tests.

### Speech resolution (child tap)

recording(activeLanguage) → TTS(activeLanguage) → TTS(en).

Interrupt-don't-queue extends across both engines: a new tap stops whatever is
playing (recorded audio and TTS both) before speaking. Playback failures are
silent on the child screen (calm blank rule); the card highlight still plays.

## Feature: bilingual board

- Parent mode: English / اردو segmented switch → sets `activeLanguage`, persists,
  points TTS at `ur-PK` / `en-US`, board re-renders labels in that language.
- One language at a time everywhere. The child never sees a mixed board.
- Urdu renders RTL via the existing directional layouts; no layout work expected.
- If the device has no Urdu TTS voice: fall back per speech resolution
  (recordings, else English TTS) and show one plain line under the switch:
  "Urdu voice not available on this phone — recordings will be used."

## Feature: More-words pages

- Category with non-empty `moreCards` → child board shows a **"More…" tile at the
  fixed last grid position**: same card chrome, distinct three-dots sketch icon
  (must not be confusable with the core word card "more").
- Tap → full-screen static page: same grid, same tap behavior, hidden respected,
  usage counted, back arrow at the leading edge. One level deep only.
- Child-facing navigation uses a **zero-duration route** (v1 no-animation rule;
  the parent screen's animated push stays sanctioned because it is behind the gate).
- Parent mode reorder list shows Main and More as two sections with a divider;
  dragging across the divider moves a card between pages. Add-card sheet gains a
  "put on More page" toggle.
- Quick phrases are ordinary cards whose label is a phrase (e.g. "I need the
  toilet"); no special card type.

## Feature: insights

- Every child tap increments the card's counter. Writes are debounced (batch
  every ~5 taps or ~10 s, flush on app pause) so speech never waits on disk.
- Parent mode Insights section: words this week, top-10 words, newly-tried words
  (firstUsed within 14 days), per-category totals. Counting is card-id based, so
  language switching does not split stats.
- No export, no charts library — simple rows and bars from existing widgets.

## Feature: type-to-speak

- Parent mode: text field + Speak button, uses the active language's TTS voice.
  Urdu text input works natively (RTL field).
- Memory-only list of the session's last ~10 utterances, tap to re-speak.
- Same interrupt rules via the existing `SpeechService`.

## Feature: backup / restore

- **Backup**: zip `board.json` + `usage.json` + `photos/` + `recordings/` →
  `bolo-backup-YYYY-MM-DD.bolo` → OS share sheet.
- **Restore**: pick a `.bolo` file → validate (unzip to temp, schema-check the
  board, reject unknown versions) → confirmation dialog stating the backup's
  date and that restore **overwrites the current board** → atomic swap (stage in
  temp dirs, then rename into place). Any failure leaves current data untouched.

## Carried invariants (unchanged from v1)

Muted palette from `theme.dart` only; no animation beyond the 150 ms tap
highlight (now including zero-duration child navigation); no sounds except
speech (recordings are speech); portrait lock; RTL-safe layout primitives;
errors never surface on the child screen; persistence failures keep the
in-memory board; grown-up gate unchanged (3 s, `BOLO_GATE_MS` override).

## Testing

- Unit: v1→v2 migration (including idempotency and Urdu merge), speech
  resolution order, usage debounce/flush, backup round-trip (backup → restore →
  identical board+files), corrupt usage.json recovery.
- Widget: Record sheet state machine (record/play/re-record/delete, both
  languages), More-page navigation and fixed tile position, insights rendering,
  type-to-speak, language switch re-render.
- Known harness rule from v1 (cost 3 review rounds): real dart:io writes never
  complete in testWidgets' FakeAsync zone; wrap disk-touching interactions in
  `tester.runAsync` with bounded pumps — `pumpAndSettle` inside `runAsync`
  deadlocks.
- Maestro: extend `board-smoke.yaml` with a More-page hop; keep it idempotent
  (`clearState: true`).

## Rollout

- Branch `feature/v2` off `main` (never off dev — house convention).
- Version 2.0.0+2 (major bump per convention).
- Same pipeline as v1: full test suite + Maestro on sim/emulator, signed release
  APK, GitHub release with `bolo.apk` asset (QR already points at latest).
- Install over v1 upgrades in place; migration runs on first launch.

## Open inputs (needed from Adil, not blocking plan-writing)

1. Urdu translations for the 27 default cards (author or review).
2. Try the family phone's Urdu TTS voice once (Settings → TTS) to know which
   fallback reality to expect.
3. Decide More-page starter content per category (can also be done live in
   parent mode after shipping).
