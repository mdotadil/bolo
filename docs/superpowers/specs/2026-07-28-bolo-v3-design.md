# Bolo v3 — "Her Voice Grows" + Product Track — Design Spec

Date: 2026-07-28
Status: approved (supersedes `2026-07-28-bolo-v2-design.md`; v2 never ships — its
bundle is folded into this one release)
Baseline: v1.0.0 (`main`, tag v1.0.0) — shipped tap-to-speak MVP

## Context and goal

v1 is on the family phone: a static tap-to-speak board the child is currently
learning. v3 merges two tracks into ONE release, shipping as 3.0.0:

**Family track ("Her voice grows"):**

1. Parent voice recording per card, per language
2. Five-language board — English, Urdu, Arabic, French, Spanish — one active
   language at a time
3. More-words pages per category
4. Local usage insights
5. Type-to-speak parent tool
6. Backup / restore

**Product track (Play Store readiness, without touching the family story):**

7. A build-time channel split (`BOLO_CHANNEL`): the sideload family build stays
   exactly what v1 was — offline, unlocked, zero telemetry
8. Store-channel telemetry: Crashlytics + a closed 9-event Analytics taxonomy,
   parent mode only, toggleable
9. A one-time supporter unlock IAP (`bolo_supporter_unlock`) gating only the
   shareable insights PDF; core communication is never gated
10. Child-safety build flags (AAID stripped, all auto-collection off)

The design law carried from v1: **the board never rearranges itself.** The child
learns card positions as motor memory; every v3 feature must leave existing card
positions untouched.

## Channels: one codebase, two builds

`--dart-define=BOLO_CHANNEL=store|sideload` (default `sideload`) resolves at
compile time to `appChannel` (`AppChannel.store` / `AppChannel.sideload`), the
master gate for the whole product track. Same pattern as `BOLO_GATE_MS`.

| | sideload (family build) | store (Play build) |
|---|---|---|
| Firebase | **never initialized** | initialized at boot |
| Crashlytics / Analytics | absent | on, gated by the diagnostics toggle (default ON) |
| IAP | **never constructed** | supporter unlock available |
| Insights PDF export | free | supporter-gated |
| Feature set | everything unlocked | core free forever; PDF export behind unlock |
| Network | none, ever | Firebase + Play billing only |

The sideload build's runtime behavior is identical to a build with no product
track at all: `appChannel` is a compile-time const, so the store-only branches
are tree-shaken out of the family APK.

## Non-goals (deliberate)

- Sentence strip — revisit when the child starts combining words; it changes the
  interaction model she is mid-learning.
- Grid-size setting, multiple profiles, scanning access.
- **Registration / accounts — still a non-goal in BOTH channels.** No sign-in,
  no cloud identity, nothing to forget a password for.
- "No telemetry / no network" is now **channel-scoped**: absolute in the
  sideload channel (unchanged from v1); in the store channel telemetry exists
  but is disclosed, parent-toggleable, parent-mode-only, and stripped of
  ad/device identifiers. The child board is event-free in both channels,
  CI-enforced.
- Ads — never, in any channel. Subscriptions — never; the only purchase is the
  one-time supporter unlock.
- Auto-suggested / contextual vocabulary. "Relevant more words" is delivered as
  static parent-curated More pages, never algorithmic reordering.
- Shipped synthetic voice packs — future idea only (Bark was evaluated and
  rejected: no Urdu). Human recordings beat models for the 31 default cards.

## Dependencies (new closed list — fifteen packages)

v1's five (`flutter_riverpod`, `flutter_tts`, `flutter_svg`, `path_provider`,
`image_picker`) plus exactly five family packages and exactly five product
packages, each tied to one feature:

| Package | Feature | Why |
|---|---|---|
| `record` | Recording | mic capture to m4a |
| `audioplayers` | Recording | play recorded files (flutter_tts cannot) |
| `archive` | Backup | zip/unzip, pure Dart |
| `share_plus` | Backup + PDF export | hand files to the OS share sheet |
| `file_selector` | Restore | pick a `.bolo` file |
| `firebase_core` | Telemetry | Firebase bootstrap (store channel only) |
| `firebase_crashlytics` | Telemetry | crash reports |
| `firebase_analytics` | Telemetry | the 9-event taxonomy |
| `in_app_purchase` | Supporter unlock | one-time non-consumable IAP |
| `pdf` | Insights export | one-page therapist PDF, pure Dart |

No codegen, no build_runner, nothing else. `flutter_lints` stays dev-only.

## Five languages

- `const supportedLanguages = ['en', 'ur', 'ar', 'fr', 'es']` lives in the
  models layer (`lib/models/board.dart`) and is the **single source of truth**:
  the parent language dropdown, the record sheet's rows, the TTS tag map, and
  the migration merge all derive from it.
- One language active at a time (`Board.activeLanguage`); the switch is
  complete — the child never sees mixed-language UI.
- TTS tags: `en` → `en-US`, `ur` → `ur-PK`, `ar` → `ar-SA`, `fr` → `fr-FR`,
  `es` → `es-ES`.
- Urdu and Arabic ride the proven RTL path (directional layout primitives from
  v1; no layout work expected).
- If the device lacks a voice for the active language, speech falls back per
  the resolution order (recordings, else English TTS) and parent mode shows one
  plain line under the language dropdown:
  "«DisplayName» voice not available on this phone — recordings will be used."
  (driven by `SpeechService.languageAvailable`, which asks the platform's
  `isLanguageAvailable(tag)`).
- Translation review: Adil authors/reviews Urdu (two neutral picks flagged:
  تھکن ہو رہی ہے, آپ سے پیار ہے); Arabic needs a native-speaking colleague
  (several gendered adjectives and one addressee-gendered imperative flagged);
  French/Spanish are opportunistic (gendered adjectives default masculine,
  flagged). Flags live in the plan's Task 2 and are reported at execution time.
- Punjabi/Pashto remain future candidates; the data model needs no change to
  add them later.

## Data model and migration

### board.json (schema version 2 — unchanged from the v2 draft)

- `Board`: `version: 2`, `activeLanguage` (any of `supportedLanguages`,
  default `"en"`). `speechRate`, `categories` unchanged.
- `SymbolCard`: `recordings: {"<lang>": "<relative path>"}` — language-keyed
  like `labels`, paths relative to the app documents dir. Absent key = no
  recording.
- `Category`: optional `moreCards: [SymbolCard]`. Empty/absent = no More page.
- The schema version stays 2: v2 never shipped, so the only migration in the
  wild is v1 → 2, and five-language labels are just more keys in the existing
  `labels`/`names` maps.

### usage.json (separate file)

Separate from board.json on purpose: different write cadence, and a corrupt
counter file must never take the board down. Per-card `{count, firstUsed,
lastUsed}`, per-day buckets kept ~90 days. Atomic tmp+rename writes; corrupt →
rename `.corrupt`, start fresh.

### settings.json (separate file — new)

`SettingsStore` persists `telemetryEnabled` (default `true`) and
`supporterUnlocked` (default `false`) in its own `settings.json`, with
board.json's tmp+rename atomic write and corrupt → `.corrupt` + defaults
recovery. Deliberately NOT part of board.json, for two reasons:

1. **Backups must not carry consent or entitlement.** A `.bolo` backup restored
   onto another phone must not flip that phone's privacy choice or grant a
   purchase that wasn't made there.
2. **Corrupt-reset must not flip privacy.** board.json's corrupt-recovery
   rebuilds the board from defaults; that path must never silently reset a
   parent's telemetry opt-out (or drop a real entitlement — the store keeps
   restore as the recovery for that).

### Migration

`BoardStore.load()` reads a file without `version` → v1. In memory: stamp
`version: 2`, `activeLanguage: "en"`, empty `recordings`, no `moreCards`; merge
the shipped ur/ar/fr/es labels and names into **default cards by card id**
(existing labels always win; custom cards untouched); adopt default `moreCards`
for categories that have none; save back atomically. Card order and hidden
flags are never modified. Corrupt-recovery unchanged. Idempotent, covered by
tests.

### Five-language label set

The default board's 31 cards (27 main + 4 More-page phrases) and 5 category
names ship with labels in all five languages in
`assets/board/default_board.json`. A test asserts every default card and
category has a non-empty label for every entry in `supportedLanguages`.

## Feature: voice recording

Parent mode only. No recording UI ever appears on the child board.

- Each card row in parent mode gets a mic button → **Record sheet** for that
  card: one row per supported language (five rows: English / اردو / العربية /
  Français / Español, names from a shared `languageDisplayNames` const), each
  with record (tap start/stop, 10 s max, visible timer), play, re-record,
  delete.
- The Record sheet is also where a **custom** card's labels can be edited
  (English + Urdu fields — the family's two home languages; other languages
  fall back to English for custom cards). Default cards' labels are not
  editable (they ship curated).
- Files: `recordings/<cardId>_<lang>.m4a`, AAC mono. Written to a tmp path then
  renamed. Re-record overwrites; delete removes file + map entry.
- Recorder and player sit behind `Recorder` / `RecordingPlayer` interfaces
  (mirroring v1's `Tts` seam) with fakes for tests.

### Speech resolution (child tap)

recording(activeLanguage) → TTS(activeLanguage) → TTS(en).

Interrupt-don't-queue extends across both engines: a new tap stops whatever is
playing (recorded audio and TTS both) before speaking. Playback failures are
silent on the child screen (calm blank rule); the card highlight still plays.

## Feature: language switch (parent mode)

- `DropdownButton<String>` over `supportedLanguages` (display names from
  `languageDisplayNames`) → sets `activeLanguage`, persists, points TTS at the
  language's tag, board re-renders labels in that language.
- The voice-availability note (see Five languages) appears only when the active
  language's voice is missing.

## Feature: More-words pages

- Category with non-empty `moreCards` → child board shows a **"More…" tile at
  the fixed last grid position**: same card chrome, distinct three-dots sketch
  icon, tile label localized per active language via a small const map.
- Tap → full-screen static page: same grid, same tap behavior, hidden
  respected, usage counted, back arrow at the leading edge. One level deep
  only. Child-facing navigation uses a **zero-duration route**.
- Parent mode reorder list shows Main and More as two sections with a divider;
  dragging across the divider moves a card between pages. Add-card sheet gains
  a "put on More page" toggle.
- Quick phrases are ordinary cards whose label is a phrase; no special type.

## Feature: insights (+ PDF export)

- Every child tap increments the card's counter. Writes are debounced (batch
  every ~5 taps, flush on app pause) so speech never waits on disk.
- Parent mode Insights section: words this week, top words, newly-tried words
  (firstUsed within 14 days), per-category totals. Counting is card-id based,
  so language switching does not split stats.
- **Insights PDF export** (`buildInsightsPdf(UsageData, Board)`): a one-page
  summary (week count, top-10 table with first/last used, new words,
  per-category totals) rendered with `package:pdf` and handed to the OS share
  sheet via the existing share_plus flow — built for handing to a therapist.
  Labels render in English (the bundled PDF fonts have no Arabic-script
  glyphs; shipping font files is deliberately out of scope for v3).
- Gating: free in the sideload channel; supporter-gated in the store channel.
- Everything is computed from local files; nothing leaves the phone except the
  file the parent explicitly shares.

## Feature: type-to-speak

- Parent mode: text field + Speak button, uses the active language's TTS voice.
  RTL text input works natively.
- Memory-only list of the session's last ~10 utterances, tap to re-speak.
- Same interrupt rules via the existing `SpeechService`.

## Feature: backup / restore

- **Backup**: zip `board.json` + `usage.json` + `photos/` + `recordings/` →
  `bolo-backup-YYYY-MM-DD.bolo` → OS share sheet. `settings.json` is
  deliberately excluded (see settings.json rationale).
- **Restore**: pick a `.bolo` file → validate (unzip to temp, schema-check the
  board, reject unknown versions) → confirmation dialog stating that restore
  **overwrites the current board** → atomic swap (stage in temp dirs, then
  move into place, photo paths re-anchored to this device). Any failure leaves
  current data untouched.

## Telemetry (store channel only)

**Crashlytics:** `FlutterError.onError` + `PlatformDispatcher.onError` route
fatal errors to Crashlytics. Collection is enabled at boot only from the
persisted `telemetryEnabled` setting.

**Analytics — a closed 9-event taxonomy.** `TelemetryService.log(ParentEvent)`
accepts ONLY the enum below; there is no free-text event or parameter path.
The single parameter ever sent is a language code from `supportedLanguages`.

| `ParentEvent` case | Analytics name | fired when (parent mode only) |
|---|---|---|
| `languageChanged` | `language_changed` | board language switched |
| `customCardAdded` | `custom_card_added` | custom photo card created |
| `recordingCreated` | `recording_created` | voice recording saved |
| `morePageConfigured` | `more_page_configured` | card moved across the Main/More divider, or added directly to More |
| `backupCreated` | `backup_created` | backup handed to the share sheet |
| `backupRestored` | `backup_restored` | restore completed |
| `insightsViewed` | `insights_viewed` | insights section shown |
| `supporterPurchased` | `supporter_purchased` | supporter unlock purchased |
| `supporterRestored` | `supporter_restored` | supporter unlock restored |

- **The child board is event-free.** Nothing under `lib/features/board/` may
  import the telemetry service — a CI guard test greps the tree and fails the
  build on violation. Card labels, recordings, photos, typed text, and tap
  contents never leave the phone in any channel (tap counters exist only in
  the local usage.json).
- **Consent:** parent-mode "Share anonymous diagnostics" toggle (store channel
  only, default ON, persisted in settings.json) drives BOTH
  `setCrashlyticsCollectionEnabled` and `setAnalyticsCollectionEnabled` live
  and at every boot.
- In the sideload channel `TelemetryService.log` is a compiled-in no-op and
  Firebase is never initialized.

## Supporter unlock (IAP)

- One product: `bolo_supporter_unlock`, a **one-time non-consumable**. No ads,
  no subscription, no consumables, ever.
- **Core communication is never gated**: cards, speech, all five languages,
  recordings, More pages, on-screen insights, type-to-speak, backup/restore
  are free in both channels forever.
- The unlock gates: the insights PDF export (store channel), and grandfathers
  the buyer into future premium extras (e.g. cloud backup when it ships).
- Sideload channel = unlocked by definition (IAP code never constructed).
- Flow: `PurchaseGateway` seam over `in_app_purchase` (mirrors the `Tts`
  seam) → `purchaseStream` subscription from boot (store channel),
  `buyNonConsumable`, `restorePurchases`, and `completePurchase` called for
  **every** delivered purchase regardless of status (Play redelivers
  uncompleted purchases forever).
- Entitlement is persisted as `supporterUnlocked` in settings.json:
  **offline-forever** — once unlocked, no network check ever again. Recovery
  path on a new phone is the Restore button.
- Purchases go through Play's own purchase authentication (see policy facts);
  the supporter UI additionally sits behind the 3 s grown-up gate like all of
  parent mode.

## Child-safety build flags

Baked into the manifests so no build can regress them; the runtime
`set*CollectionEnabled` calls are the only way collection turns on, and only in
the store channel with consent.

`android/app/src/main/AndroidManifest.xml` (manifest tag gains
`xmlns:tools="http://schemas.android.com/tools"`):

```xml
<uses-permission android:name="com.google.android.gms.permission.AD_ID"
    tools:node="remove"/>
<meta-data android:name="google_analytics_adid_collection_enabled"
    android:value="false"/>
<meta-data android:name="google_analytics_default_allow_ad_personalization_signals"
    android:value="false"/>
<meta-data android:name="firebase_analytics_collection_enabled"
    android:value="false"/>
<meta-data android:name="firebase_crashlytics_collection_enabled"
    android:value="false"/>
```

`ios/Runner/Info.plist`:

```xml
<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key> <false/>
<key>GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS</key> <false/>
<key>GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED</key> <false/>
<key>FirebaseCrashlyticsCollectionEnabled</key> <false/>
```

A config guard test asserts these lines exist so they cannot be silently
dropped.

## Store policy facts (researched July 2026)

- **Play Families:** an app targeting children must not transmit the
  advertising ID. Firebase Analytics is compatible with the Families policy
  only with the `AD_ID` permission stripped, AAID collection disabled, ad
  personalization signals off, and auto-collection off (exactly the flags
  above) — declared in the Data safety form.
  Sources: https://support.google.com/googleplay/android-developer/answer/9893335
  and https://support.google.com/googleplay/android-developer/answer/6048248
- **Purchases in kids-capable apps:** Play force-authenticates purchases in
  apps targeting children; combined with Bolo's 3 s parent gate the supporter
  flow is compliant.
  Sources: https://support.google.com/googleplay/android-developer/answer/9893335
  (Families monetization) and https://support.google.com/googleplay/answer/1626831
- **New personal Play developer accounts** must run a closed test with at
  least 12 testers opted in for 14 continuous days before production access —
  this is the store rollout's critical path and is external to this repo.
  Source: https://support.google.com/googleplay/android-developer/answer/14151465
- **Apple: do NOT enroll in the Kids Category.** Standard practice for AAC
  apps (Proloquo-class) is an Education/Medical listing; the Kids Category
  would ban the third-party analytics SDKs outright (guideline 1.3) while
  offering nothing an AAC listing needs. Bolo still ships the child-safety
  plist flags regardless.
  Source: https://developer.apple.com/app-store/review/guidelines/#kids-category
- **Firebase auto-collection kill-switches** (manifest/plist keys above):
  https://firebase.google.com/docs/analytics/configure-data-collection?platform=android
  and https://firebase.google.com/docs/crashlytics/customize-crash-reports?platform=flutter
- **AGP risk:** the Crashlytics gradle plugin (3.0.7) may not yet support the
  repo's AGP 9.0.1; documented fallback is pinning AGP 8.13.x in
  `android/settings.gradle.kts`.
  Source: https://firebase.google.com/support/release-notes/android

## Carried invariants (unchanged from v1)

Muted palette from `theme.dart` only; no animation beyond the 150 ms tap
highlight (child navigation is zero-duration); no sounds except speech
(recordings are speech); portrait lock; RTL-safe layout primitives; errors
never surface on the child screen; persistence failures keep the in-memory
board; grown-up gate unchanged (3 s, `BOLO_GATE_MS` override).

## Testing

- Unit: v1→v2 migration (idempotency + all four non-English label merges),
  speech resolution order across five languages, usage debounce/flush, backup
  round-trip, corrupt usage.json/settings.json recovery, `SettingsStore`
  round-trip, `TelemetryService` name mapping + sideload no-op,
  `PurchaseService` against a fake `PurchaseGateway` (purchase/restore/cancel/
  error/foreign-product, completePurchase always), `buildInsightsPdf` output.
- Widget: Record sheet state machine (five language rows), More-page
  navigation and fixed tile position, insights rendering, type-to-speak,
  language dropdown re-render + availability note, diagnostics toggle and
  supporter section **absent** in sideload.
- Channel proof: one dedicated widget test file run twice — plain (sideload
  assertions) in the normal suite, and `flutter test
  --dart-define=BOLO_CHANNEL=store test/features/channel_test.dart` asserting
  the store widgets exist.
- Guards (ride the normal `flutter test` gate in CI): child board imports no
  telemetry; child-safety manifest/plist flags present.
- Known harness rule from v1 (cost 3 review rounds): real dart:io writes never
  complete in testWidgets' FakeAsync zone; wrap disk-touching interactions in
  `tester.runAsync` with bounded pumps — `pumpAndSettle` inside `runAsync`
  deadlocks.
- Maestro: extend `board-smoke.yaml` with a More-page hop; keep it idempotent
  (`clearState: true`).

## Rollout

- Branch `feature/v3` off `main` (never off dev — house convention).
- Version **3.0.0+2** (major bump per convention; there is no 2.0.0 release).
- Same pipeline as v1 plus channel proofs: full test suite + Maestro on
  sim/emulator, signed sideload release APK, store-channel AAB built in CI,
  GitHub release with `bolo.apk` asset (QR already points at latest).
- Install over v1 upgrades in place; migration runs on first launch.
- The STORE rollout is a separate clock gated on external items (Play account
  + 12 closed testers, Firebase project, listing/data-safety) — it never
  blocks the family release.

## Open inputs (needed from Adil, not blocking plan execution)

1. Translation reviews: Urdu (author/review, two flagged picks), Arabic
   (native-speaking colleague — gendered forms flagged in the plan's Task 2),
   French/Spanish opportunistic.
2. Play Console personal account + 12 closed testers (14-day clock — start
   immediately; store critical path). Paperclip BRA-44.
3. Firebase project for `com.mdotadil.bolo` + hosted privacy policy; then
   rerun `flutterfire configure` if the plan executed with the placeholder.
   Paperclip BRA-45.
4. Play listing, target-audience + Data safety forms, content rating,
   `bolo_supporter_unlock` product creation, license testers. Paperclip
   BRA-46.
5. Try the family phone's Urdu/Arabic TTS voices once (Settings → TTS) to know
   which fallback reality to expect.
