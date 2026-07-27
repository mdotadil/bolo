# Bolo — AAC App MVP Design

**Date:** 2026-07-27
**Status:** Approved design, pending spec review
**Working name:** "Bolo" (Urdu: "speak") — placeholder, rename anytime.

## What this is

A tap-to-speak AAC (Augmentative and Alternative Communication) app for a nonverbal autistic child aged 3–7. The child taps a picture card; the phone speaks the word. That is the entire product in v1.

Two goals, in priority order:

1. **A specific child Adil knows can request food, drink, toilet, play, and help at home.** v1 is done when this happens. Nothing else gates v1.
2. Longer term, grow into an affordable Arabic/Urdu/English AAC product for the MENA/Pakistan market, where no good affordable option exists (the gap vs Proloquo2Go, Goally, Otsimo). v1 decisions must not block this, but v1 does not build it.

## Users

- **The child (primary):** nonverbal, 3–7 years old. Uses the board screen only. Cannot read; navigates by pictures. Needs absolute predictability.
- **The parent (secondary):** owns the phone, curates the board, adds custom cards. Enters parent mode through a grown-up gate.

## Approach chosen

**Tap-to-speak core board** (Approach A of three considered). No sentence strip in v1: beginning communicators at this age start with single-symbol requests, and a strip adds cognitive load before the tap-to-request habit exists. Custom parent photo cards are included (borrowed from the photo-first approach) because real photos of the child's own things are often easier for young autistic kids than abstract symbols.

Rejected for v1: sentence-strip AAC (build it when the child chains symbols), photo-only board (no transferable symbol vocabulary, high setup burden).

## Product & UX

### Child screen (the whole app, 95% of the time)

- Grid of large symbol cards, 2–3 columns on a phone. Tap a card → the word is spoken immediately.
- Gentle visual confirmation on tap (brief highlight). No bounce, no sound effects, no celebration animations.
- Categories as large tabs along the bottom:
  - **Wants** — eat, drink, more, all done
  - **Toilet/Body** — toilet, hurts, tired
  - **Play** — favorite toys/activities
  - **Feelings** — happy, sad, angry, scared
  - **Help** — help me, come here
- ~25–35 cards at launch. Small enough to learn, big enough for real needs. The exact card list will be wrong on the first try; adjusting it with the family is part of v1 (see Testing).

### Sensory-friendly rules (hard requirements, not styling preferences)

- Muted color palette.
- No animation beyond the tap highlight.
- No sounds except speech.
- Identical layout on every launch. Cards never move, reflow, or reorder on their own. Predictability is the feature.

### Parent mode

- Entered via grown-up gate: press-and-hold 3 seconds. No visible countdown (nothing for the child to find interesting). Release = harmless no-op.
- Capabilities, complete list for v1:
  - Hide/show any card
  - Reorder cards
  - Add a custom card: photo (camera or library) + typed label
  - Adjust speech rate
- Setup guidance recommends iOS **Guided Access** / Android **screen pinning** to lock the phone into the app when handing it to the child. We do not build our own kiosk mode.

## Technical architecture

**Stack: Flutter (Dart), one codebase for Android + iOS.** Chosen over native SwiftUI because the target market (Pakistan/MENA) is overwhelmingly Android; an iOS-only AAC app structurally misses the families the product exists for. Also reuses the already-installed Flutter toolchain, and this app's scope (grid UI, local storage, TTS plugin) absorbs the learning curve cheaply.

**Architecture: MVVM-shaped, no Clean Architecture ceremony.** Views ↔ state (Riverpod notifiers) ↔ services. Clean's use-case/domain layering is not justified by a card grid with one speech call and a JSON file.

### Structure

```
lib/
  features/
    board/      # child screen: grid, category tabs, tap-to-speak
    parent/     # grown-up gate, board editing, custom cards, settings
  services/
    speech_service.dart    # wraps flutter_tts
    board_store.dart       # JSON persistence
    symbol_library.dart    # bundled symbol assets + manifest
  models/
    symbol_card.dart       # id, symbol ref or photo path, labels by language, hidden, sort order
    board_category.dart    # id, name labels by language, card list
```

### Key components

- **SpeechService** — wraps `flutter_tts` (AVSpeechSynthesizer on iOS, native TTS engine on Android). English voice in v1. The interface takes a `SymbolCard`, not a string, so a card can later carry a recorded-audio path or Urdu cloud-TTS reference with zero UI changes. This is the seam the multilingual future depends on.
- **SymbolLibrary** — ~35 bundled SVGs from **Mulberry Symbols** (CC-BY-SA, commercial use permitted — chosen over ARASAAC, whose non-commercial license would block charging for the app later). Rendered with `flutter_svg`. A JSON manifest maps symbol id → asset path → labels keyed by language (`en` now; `ur`, `ar` slot in later).
- **BoardStore** — board state (card order, hidden flags, custom cards, speech rate) as one JSON file in app documents. ~35 cards does not justify a database. Writes are atomic (write temp file, rename). Custom photos are copied into the app's own directory so cards survive deletion of the source photo.
- **Localization & RTL** — `flutter_localizations` wired from day one; all layouts direction-agnostic (leading/trailing, never left/right) so Urdu/Arabic becomes a translation task, not a refactor.

### Explicitly absent in v1

No backend. No accounts. No analytics. Fully offline. A child's communication data never leaves the device — this is also the privacy story the product ships with later.

### Distribution (v1 = one family)

- **Android APK, signed, side-loaded** — the reliable daily driver if the family has any Android phone. Permanent install, no expiry.
- **iOS build** — Adil's own testing. The free personal team's 7-day re-sign expiry is unacceptable for a child who depends on the app daily, so the iPhone is not the daily driver until a paid Apple account / TestFlight decision is made (open question below).

## Edge cases & error handling

- **Silent switch / mute:** configure the audio session as media playback so speech plays with the iPhone silent switch on. Android: speak on the media stream. An AAC app that goes silent because of the mute switch fails at its one job.
- **Rapid taps:** a new tap interrupts the current utterance and speaks the new word. Never queue speech.
- **Missing/unavailable TTS voice:** fall back to system default voice. No error surface the child can see — any failure is handled invisibly.
- **Persistence failure:** board config saves atomically after every parent edit; a failed write keeps the in-memory board intact and retries on next edit.
- **Corrupt board file:** recover to the default bundled board rather than crashing; keep the corrupt file aside for diagnosis.

## Testing

- **Unit:** `BoardStore` round-trip + corrupt-file recovery; symbol manifest loading; `SpeechService` against a mocked TTS.
- **Widget:** board renders all visible cards; tap triggers a speech call; gate opens parent mode; hidden cards don't render.
- **Maestro smoke flow** (`.maestro/board-smoke.yaml`, per standing convention): launch → tap a card → enter parent mode → add a card → verify it appears on the board.
- **The real test:** sessions with the child and family. The co-design loop — observe use, adjust the card set, retry — is part of v1 scope, not post-launch polish.

## Out of scope for v1

Sentence strip / phrase building; Urdu and Arabic speech (architected for, not built); parent-recorded audio per card; multiple child profiles; cloud sync or backup; therapist/data/reporting features; App Store / Play Store submission; monetization; iPad-optimized layouts beyond basic responsiveness.

## Open questions (do not block the build)

1. **iOS signing:** paid Apple Developer account vs. staying Android-primary for the family. Decide before the child's iPhone (if any) becomes the daily device.
2. **Does the design-partner family have an Android phone?** Determines whether the APK path covers the daily driver.
3. **Name:** "Bolo" is a working title. Check App Store/Play Store collisions before any public release.
4. **Exact v1 card list:** draft from the five categories above, then correct it with the family in the first co-design session.
