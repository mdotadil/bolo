# Natural voice clips from freevoicereader.com

The app plays bundled MP3 clips instead of the robotic device voice
(order: parent recording, then bundled clip, then device TTS). The clips
come from https://www.freevoicereader.com. The site has no API, so you make
one MP3 per language and `tools/split_voice_clips.py` cuts it into one clip
per card.

## Before you start

- MP3 download needs a paid plan: **Lifetime Boost ($79.99 once)** for the
  basic voices, or a **subscription (from $99.99/year)** for Google
  Neural2/WaveNet/Gemini voices.
- **Rights:** the site's terms do not grant commercial rights to the audio,
  and some voice models carry their own limits. Accepted by Adil on
  2026-11-13. To keep the risk low:
  - never use **Microsoft Edge** voices (meant for reading in Edge, not
    for apps);
  - prefer **Kokoro** voices (open Apache-2.0 model) for en/fr/es;
  - use **Google** voices for ur/ar;
  - write down the voice used per language in ATTRIBUTION.md.
- Pick one voice per language and keep it for every list in that language,
  so the board never mixes voices.

## 1. Make the lists

```bash
cd ~/brain/Personal/Bolo
python3 tools/split_voice_clips.py lists --out ~/Desktop/bolo-voice
```

This writes `<lang>.txt` (paste this into the site) and `<lang>.ids` (card
order, used by the splitter) for en, ur, ar, fr, es. Boards with gendered
words also get `<lang>.f.txt` / `<lang>.f.ids` for the girl forms.

## 2. Record on the site

For each `.txt` file: paste it all, pick the voice, play a few lines to
check, then download the MP3 into the same folder with the same name
(`ur.txt` -> `ur.mp3`, `ur.f.txt` -> `ur.f.mp3`).

## 3. Split

```bash
cd ~/Desktop/bolo-voice
for f in *.mp3; do
  python3 ~/brain/Personal/Bolo/tools/split_voice_clips.py split "$f" "${f%.mp3}.ids"
done
```

If a language says "found N spoken parts but the list has M words",
nothing was written for it. Re-run that one with `--min-silence 0.6`
(too many parts) or `--min-silence 0.3` (too few).

## 4. Ear-check and ship

```bash
afplay ~/brain/Personal/Bolo/assets/voice/ur/eat.mp3
```

Listen to every language, Urdu especially. Each clip must say its own
card's word. If a language sounds bad, delete that folder's MP3s: the app
falls back to device TTS for that language. To redo one language, re-run
its split with `--force`. Then commit `assets/voice/` and build.
