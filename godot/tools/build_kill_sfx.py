#!/usr/bin/env python3
"""The kill banners' sounds and the Herald's three new calls (0.31.180, Kevin's League banners: "a sharper audio cue"
for the multi-kills, "a unique, map-wide sound effect" for a PENTAKILL, "a distinct audio chime" for FIRST BLOOD).

Sources (art_sources/killbanners/sfx, ElevenLabs, two takes each; the better picked by waveform, spectrogram and how
much of it a phone's speaker can play -- most of a sub-bass boom can't):
  kb_<cue>_<take>.mp3   eleven_text_to_sound_v2 (prompts in art_sources/killbanners/README.txt)
  herald_<take>.mp3     eleven_v4, the Herald's voice (Edward): "First blood!", "Shutdown!", "Ace!" in one take
Cut, layered, high-passed and levelled as tools/build_hero_sfx.py does the heroes' (its functions), into
assets/sounds/kb_<cue>.wav; the Herald's three lines cut from his take into assets/vo/herald/kb_<line>.ogg (as his
other calls: mono vorbis, 44.1 kHz).

  python3 tools/build_kill_sfx.py      (numpy, scipy, ffmpeg)
"""
import os
import subprocess
import sys

import numpy as np
import scipy.io.wavfile as wf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.argv = sys.argv[:1]                       # (build_hero_sfx reads its own arguments)
import build_hero_sfx as hs  # noqa: E402

SRC = os.path.join(HERE, "..", "..", "art_sources", "killbanners", "sfx")
OUT = os.path.join(HERE, "..", "assets", "sounds")
VO = os.path.join(HERE, "..", "assets", "vo", "herald")
hs.SRC = SRC
SR = hs.SR
BANNER = 0.17                                 # (an ability's 0.16: these are the match's big moments)

# cue -> {"rms", "layers": [(source, start, end, offset, gain_db, highpass_hz, fade_out_s)]}
CUES = {
    # a plain kill: the whoosh (take 1, mids) over the thump (take 2, mostly under 500 Hz)
    "kb_kill": {"rms": 0.12, "layers": [("kb_kill_1", 0.0, 0.40, 0.0, 0, 150, 0.15),
                                         ("kb_kill_2", 0.0, 0.60, 0.07, -2, 90, 0.25)]},
    # FIRST BLOOD: the sword's ring (take 1) over the bell's strike and rings (take 2, its boom filtered off)
    "kb_first_blood": {"rms": BANNER, "layers": [("kb_first_blood_1", 0.0, 1.30, 0.0, -1, 150, 0.60),
                                                  ("kb_first_blood_2", 0.0, 2.40, 0.0, 0, 160, 1.00)]},
    "kb_double": hs.one("kb_double_1", 0.0, 1.05, 0.40, 140, BANNER),
    "kb_triple": hs.one("kb_triple_1", 0.0, 1.70, 0.50, 140, BANNER),
    "kb_quadra": hs.one("kb_quadra_2", 0.0, 2.10, 0.80, 110, BANNER),
    "kb_penta": hs.one("kb_penta_2", 0.0, 3.90, 1.00, 100, 0.20),
    "kb_shutdown": hs.one("kb_shutdown_1", 0.0, 2.10, 0.60, 140, BANNER),
    "kb_ace": hs.one("kb_ace_2", 0.0, 1.90, 0.70, 120, BANNER),
}
# the Herald: his take 2, cut at its silences
HERALD = {"kb_first_blood": (0.20, 1.50), "kb_shutdown": (1.97, 3.17), "kb_ace": (3.73, 4.67)}


def main():
    os.makedirs(OUT, exist_ok=True)
    for cue, spec in CUES.items():
        mix = hs.build(spec)
        wf.write(os.path.join(OUT, cue + ".wav"), SR, (mix * 32767).astype(np.int16))
        print("%-16s %.2f s  peak %.2f  rms(150ms) %.3f" % (cue, len(mix) / SR, np.abs(mix).max(), hs.loudest_rms(mix)))
    src = os.path.join(SRC, "herald_2.mp3")
    for line, (a, b) in HERALD.items():
        out = os.path.join(VO, line + ".ogg")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-ss", "%.2f" % a, "-to", "%.2f" % b, "-ac", "1",
                        "-ar", "44100", "-af", "afade=t=in:d=0.01,areverse,afade=t=in:d=0.08,areverse",
                        "-c:a", "libvorbis", "-q:a", "5", out], check=True)
        print("%-16s herald %.2f-%.2f s" % (line, a, b))


if __name__ == "__main__":
    main()
