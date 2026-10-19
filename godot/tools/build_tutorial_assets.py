#!/usr/bin/env python3
"""The 5v5 tutorial's voice, the Herald's portrait and the recall's sounds (0.31.181, Kevin: "Now create a tutorial
walking player through the basics of a match ... Make it voiced and make it humorous and sarcastic" and "Also add a
teleport back to castle mechanic").

Sources (art_sources/tutorial, ElevenLabs; README.txt there has the prompts and costs):
  script.json         [id, audio tag, line] -- the lines as scripts/siege/tutorial.gd shows them (the tag is only spoken)
  vo/<id>.mp3         eleven_v4, the Herald's voice (Edward), one take a line
  eleven/herald_1.png gpt-image-2, the Herald (take 1 of 2), on white
  sfx/recall_*.mp3    eleven_text_to_sound_v2, two takes each
Out:
  assets/vo/tutorial/<id>.ogg   silence trimmed at both ends, loudness-matched (EBU R128 -16 LUFS), mono vorbis 44.1 kHz
                                (as the Herald's match calls)
  assets/ui/tutorial/herald.png cut out of its white ground (tools/build_kill_banners.py's matte), cropped
  assets/sounds/recall_start.wav, recall_done.wav   cut and levelled as tools/build_hero_sfx.py does the heroes'

  python3 tools/build_tutorial_assets.py      (numpy, scipy, pillow, ffmpeg)
"""
import json
import os
import subprocess
import sys

import numpy as np
import scipy.io.wavfile as wf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.argv = sys.argv[:1]                       # (build_hero_sfx reads its own arguments)
import build_hero_sfx as hs  # noqa: E402
import build_kill_banners as kb  # noqa: E402

GODOT = os.path.dirname(HERE)
SRC = os.path.join(os.path.dirname(GODOT), "art_sources", "tutorial")
VO = os.path.join(GODOT, "assets", "vo", "tutorial")
UI = os.path.join(GODOT, "assets", "ui", "tutorial")
SOUNDS = os.path.join(GODOT, "assets", "sounds")

# the recall: take 2 of the start (a clear rising shimmer; take 1 a denser hiss), take 2 of the arrival (it lands at
# once -- take 1 swells for 0.3 s first, late for the moment you appear)
RECALL = {
    "recall_start": hs.one("recall_start_2", 0.0, 2.0, 0.8, 250, 0.11),
    "recall_done": hs.one("recall_done_2", 0.0, 1.45, 0.9, 250, 0.13),
}


def vo():
    os.makedirs(VO, exist_ok=True)
    lines = json.load(open(os.path.join(SRC, "script.json")))
    # trim: silence (below -45 dB) off the start, and off the end by reversing; loudness to -16 LUFS; tiny fades
    af = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse,"
          "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.12,areverse,"
          "loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=in:d=0.01")
    for lid, _tag, _text in lines:
        src = os.path.join(SRC, "vo", lid + ".mp3")
        out = os.path.join(VO, lid + ".ogg")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-af", af, "-ac", "1", "-ar", "44100",
                        "-c:a", "libvorbis", "-q:a", "5", out], check=True)
        dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", out],
                                   capture_output=True, text=True).stdout.strip() or 0)
        print("%-16s %5.2f s" % (lid, dur))
    print("%d lines" % len(lines))


def portrait():
    # The figurine style has no dark outline to stop a flood of near-white (kill banners' matte ate his white plume and
    # ruff): here the ground is only the pure white (>= 0.975) reaching the edge, and pure-white pockets bigger than
    # 600 px (between the trumpet and his shoulder); the figure's edge pulled in 2 px (no white fringe) and softened.
    from PIL import Image
    import scipy.ndimage as nd
    os.makedirs(UI, exist_ok=True)
    rgb = np.asarray(Image.open(os.path.join(SRC, "eleven", "herald_1.png")).convert("RGB")).astype(np.float64) / 255.0
    mn = rgb.min(2)
    lab, n = nd.label(mn >= 0.975)
    sizes = nd.sum(np.ones_like(mn), lab, range(1, n + 1))
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    pockets = {i + 1 for i, sz in enumerate(sizes) if sz > 600} - edge
    fg = ~np.isin(lab, list(edge | pockets))
    fg = nd.binary_erosion(fg, iterations=2)
    fg = nd.binary_fill_holes(fg) & ~np.isin(lab, list(pockets))
    alpha = nd.gaussian_filter(fg.astype(np.float64), 1.0)
    alpha[alpha < 0.03] = 0.0
    rgba = kb.crop(alpha, rgb, 6)
    kb.OUT = UI
    kb.save(rgba, "herald", 420)


def sounds():
    hs.SRC = os.path.join(SRC, "sfx")
    for cue, spec in RECALL.items():
        mix = hs.build(spec)
        wf.write(os.path.join(SOUNDS, cue + ".wav"), hs.SR, (mix * 32767).astype(np.int16))
        print("%-16s %.2f s  peak %.2f  rms(150ms) %.3f" % (cue, len(mix) / hs.SR, np.abs(mix).max(), hs.loudest_rms(mix)))


if __name__ == "__main__":
    vo()
    portrait()
    sounds()
