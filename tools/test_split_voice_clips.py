"""Run: python3 -m unittest tools/test_split_voice_clips.py  (needs ffmpeg)"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_voice_clips as svc  # noqa: E402


class SplitVoiceClipsTest(unittest.TestCase):
    def test_lists_put_female_forms_in_their_own_list(self):
        lists = svc.build_lists([
            ("eat", {"en": "eat", "ur": "کھانا"}),
            ("tired", {"en": "tired", "ur": {"m": "تھک گیا", "f": "تھک گئی"}}),
        ])
        self.assertEqual(lists["ur"], [("eat", "کھانا"), ("tired", "تھک گیا")])
        self.assertEqual(lists["ur.f"], [("tired", "تھک گئی")])
        self.assertNotIn("en.f", lists)

    def test_speech_is_the_gaps_between_silences(self):
        segments = svc.speech_segments([(0.4, 1.2), (1.6, 2.4)], 2.8, pad=0)
        self.assertEqual(segments, [(0.0, 0.4), (1.2, 1.6), (2.4, 2.8)])

    def test_split_end_to_end_and_refuses_on_count_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            mp3 = tmp / "three.mp3"
            # Three 0.4 s tones separated by 0.8 s of silence.
            subprocess.run(
                ["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
                 "aevalsrc='if(lt(mod(t,1.2),0.4),sin(2*PI*440*t),0)':d=3.6",
                 str(mp3)], check=True)
            (tmp / "en.ids").write_text("a\nb\nc\n")
            (tmp / "ur.f.ids").write_text("a\nb\nc\nd\n")

            svc.split(mp3, tmp / "en.ids", tmp / "voice", -40, 0.45, force=False)
            self.assertEqual(sorted(p.name for p in (tmp / "voice" / "en").iterdir()),
                             ["a.mp3", "b.mp3", "c.mp3"])

            with self.assertRaises(SystemExit):
                svc.split(mp3, tmp / "ur.f.ids", tmp / "voice", -40, 0.45, force=False)
            self.assertFalse((tmp / "voice" / "ur").exists())


if __name__ == "__main__":
    unittest.main()
