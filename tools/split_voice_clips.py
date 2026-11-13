#!/usr/bin/env python3
"""Turn freevoicereader.com recordings into per-card voice clips.

freevoicereader.com has no API, so clips are made in bulk:

  1. `lists` writes, per language, a text file to paste into the site (one
     card label per line, each ending in a full stop so the voice pauses)
     and a matching .ids file (card ids in the same order).
  2. Adil pastes each text file into the site and downloads one MP3.
  3. `split` cuts that MP3 on silence into assets/voice/<lang>/<id>.mp3
     (or <id>.f.mp3 for female forms). It refuses to write anything when
     the number of clips does not match the number of ids, so a merged or
     missed word can never be filed under the wrong card.

A label is either a string or {"m": ..., "f": ...} (gendered forms); the
female forms go to <lang>.f.txt / <lang>.f.ids and become <id>.f.mp3.

Examples:
  python3 tools/split_voice_clips.py lists --out /tmp/bolo-voice
  python3 tools/split_voice_clips.py split ~/Downloads/ur.mp3 /tmp/bolo-voice/ur.ids
  python3 tools/split_voice_clips.py split ~/Downloads/ur.mp3 /tmp/bolo-voice/ur.ids --min-silence 0.6
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
BOARDS = [REPO_ROOT / "assets" / "board" / name
          for name in ("default_board.json", "core_board.json")]
VOICE_DIR = REPO_ROOT / "assets" / "voice"
LANGUAGES = ["en", "ur", "ar", "fr", "es"]
STOPS = ".!?؟۔"


def load_words(paths):
    """Yields (id, labels) for every card/word, first occurrence of an id wins."""
    seen = set()
    for path in paths:
        if not path.exists():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        items = [card for category in data.get("categories", [])
                 for card in category["cards"]] + data.get("words", [])
        for item in items:
            if item["id"] not in seen:
                seen.add(item["id"])
                yield item["id"], item["labels"]


def build_lists(words):
    """Returns {list name: [(id, text)]}, e.g. {"ur": [...], "ur.f": [...]}."""
    lists = {}
    for word_id, labels in words:
        for lang in LANGUAGES:
            label = labels.get(lang)
            if isinstance(label, dict):
                forms = [(lang, label.get("m")), (f"{lang}.f", label.get("f"))]
            else:
                forms = [(lang, label)]
            for name, text in forms:
                if text:
                    lists.setdefault(name, []).append((word_id, text))
    return lists


def spoken(text, lang):
    return text if text[-1] in STOPS else text + ("۔" if lang == "ur" else ".")


def write_lists(lists, out):
    out.mkdir(parents=True, exist_ok=True)
    for name, entries in sorted(lists.items()):
        (out / f"{name}.txt").write_text(
            "\n\n".join(spoken(text, name.split(".")[0]) for _, text in entries) + "\n", encoding="utf-8")
        (out / f"{name}.ids").write_text(
            "\n".join(word_id for word_id, _ in entries) + "\n", encoding="utf-8")
        print(f"  {name}: {len(entries)} words -> {out / (name + '.txt')}")


def detect_silences(mp3, noise_db, min_silence):
    result = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(mp3), "-af",
         f"silencedetect=noise={noise_db}dB:d={min_silence}", "-f", "null", "-"],
        capture_output=True, text=True, check=True)
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", result.stderr)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", result.stderr)]
    duration = re.search(r"Duration: (\d+):(\d+):([\d.]+)", result.stderr)
    h, m, s = duration.groups()
    return list(zip(starts, ends + [None] * (len(starts) - len(ends)))), \
        int(h) * 3600 + int(m) * 60 + float(s)


def speech_segments(silences, duration, pad=0.08):
    """Speech = the gaps between silences, padded a little on each side."""
    segments, cursor = [], 0.0
    for start, end in silences:
        if start - cursor > 0.05:
            segments.append((max(0.0, cursor - pad), start + pad))
        cursor = end if end is not None else duration
    if duration - cursor > 0.05:
        segments.append((max(0.0, cursor - pad), duration))
    return segments


def split(mp3, ids_file, voice_dir, noise_db, min_silence, force):
    name = ids_file.name[:-len(".ids")]  # "ur" or "ur.f"
    lang, female = name.split(".")[0], name.endswith(".f")
    if lang not in LANGUAGES:
        raise SystemExit(f"{ids_file.name}: expected <lang>.ids or <lang>.f.ids")
    ids = [line.strip() for line in ids_file.read_text(encoding="utf-8").splitlines()
           if line.strip()]
    silences, duration = detect_silences(mp3, noise_db, min_silence)
    segments = speech_segments(silences, duration)
    if len(segments) != len(ids):
        raise SystemExit(
            f"{mp3.name}: found {len(segments)} spoken parts but {ids_file.name} has "
            f"{len(ids)} words. Nothing written. Try --min-silence "
            f"{'higher' if len(segments) > len(ids) else 'lower'} (now {min_silence}).")
    target_dir = voice_dir / lang
    target_dir.mkdir(parents=True, exist_ok=True)
    suffix = ".f.mp3" if female else ".mp3"
    for word_id, (start, end) in zip(ids, segments):
        target = target_dir / f"{word_id}{suffix}"
        if target.exists() and not force:
            print(f"  skip {target.name} (exists, use --force)")
            continue
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(mp3),
             "-ss", f"{start:.3f}", "-to", f"{end:.3f}", "-ac", "1",
             "-codec:a", "libmp3lame", "-q:a", "4", str(target)],
            check=True)
    print(f"  {len(ids)} clips -> {target_dir}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    lists = sub.add_parser("lists", help="write the text to paste into the site")
    lists.add_argument("--out", type=Path, required=True)
    cut = sub.add_parser("split", help="cut one downloaded MP3 into clips")
    cut.add_argument("mp3", type=Path)
    cut.add_argument("ids", type=Path, help="the <lang>.ids file written by `lists`")
    cut.add_argument("--voice-dir", type=Path, default=VOICE_DIR)
    cut.add_argument("--noise-db", type=int, default=-40)
    cut.add_argument("--min-silence", type=float, default=0.45)
    cut.add_argument("--force", action="store_true", help="overwrite existing clips")
    args = parser.parse_args()

    if args.command == "lists":
        write_lists(build_lists(load_words(BOARDS)), args.out)
    else:
        split(args.mp3, args.ids, args.voice_dir, args.noise_db, args.min_silence,
              args.force)


if __name__ == "__main__":
    sys.exit(main())
