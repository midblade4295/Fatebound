#!/usr/bin/env python3
"""The 5v5 tutorial's voice, the Herald's portrait and the recall's sounds (0.31.181, Kevin: "Now create a tutorial
walking player through the basics of a match ... Make it voiced and make it humorous and sarcastic" and "Also add a
teleport back to castle mechanic").

Sources (art_sources/tutorial, ElevenLabs; README.txt there has the prompts and costs):
  script.json         [id, audio tag, line] -- the lines as scripts/siege/tutorial.gd shows them (the tag is only spoken)
  vo/<id>.mp3         eleven_v4, the Herald's voice (Edward), one take a line
  sfx/recall_*.mp3    eleven_text_to_sound_v2, two takes each
  poses/<pose>.png    (0.31.182, Kevin: concept D, "but also have him doing some funny stuff with the scroll like
                      sometimes he's laying on top of it and sometimes leaning on it ect") the Herald with his
                      proclamation scroll, eight ways (hold, lying, leaning, sitting, peeking, napping, pointing,
                      hanging), gpt-image-2 / gpt-image-2.5-sunburst, on white
Out:
  assets/vo/tutorial/<id>.ogg   silence trimmed at both ends, loudness-matched (EBU R128 -16 LUFS), mono vorbis 44.1 kHz
                                (as the Herald's match calls)
  assets/ui/tutorial/scroll_<pose>.png  cut out of its white ground, cropped; and scripts/siege/tutorial_poses.gd: each
                                        one's size, its parchment and the clear part of it for the text (its pixels)
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
ARGS = sys.argv[1:]                           # (vo, poses, sounds: which to build; all by default)
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


POSES = ["hold", "lying", "leaning", "sitting", "peeking", "napping", "pointing", "hanging"]
POSE_W = 1100                                 # (the parchment ~900 px of it: the phone's 1080-wide screen, a little under)


def cut(rgb):
    """(rgba) the art cut out of its white ground. The figurine style has no dark outline to stop a flood of near-white:
    the ground is only the pure white (>= 0.975) reaching the edge, and pure-white pockets bigger than 600 px; the
    edge pulled in 2 px (no white fringe) and softened."""
    import scipy.ndimage as nd
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
    return np.dstack([rgb, alpha])


def parchment(rgba):
    """(parchment rect, clear rect) in the image's pixels: the parchment the biggest patch of its beige; the clear part
    the rows and columns of it the Herald (feet, a stick, fingers) and the seal leave uncovered"""
    import scipy.ndimage as nd
    c = (rgba[..., :3] * 255.0).astype(int)
    m = (c[..., 0] > 195) & (c[..., 1] > 172) & (c[..., 2] > 120) & (c[..., 2] < 238) & (c[..., 0] - c[..., 2] > 22) \
        & (rgba[..., 3] > 0.5)
    m = nd.binary_opening(m, iterations=2)
    lab, n = nd.label(m)
    sizes = nd.sum(m, lab, range(1, n + 1))
    k = int(np.argmax(sizes)) + 1
    pm = nd.binary_fill_holes(lab == k)
    ys, xs = np.nonzero(pm)
    px0, px1, py0, py1 = xs.min(), xs.max(), ys.min(), ys.max()
    # the clear part: the biggest rectangle of uncovered beige (on a 4 px grid), pulled in from the parchment's curled
    # edges a little
    cell = 4
    clean = (lab == k)[py0:py1 + 1, px0:px1 + 1]
    gh, gw = clean.shape[0] // cell, clean.shape[1] // cell
    g = clean[:gh * cell, :gw * cell].reshape(gh, cell, gw, cell).mean(axis=(1, 3)) > 0.9
    best, heights = (0, 0, 0, 0, 0), np.zeros(gw, dtype=int)
    for r in range(gh):
        heights = np.where(g[r], heights + 1, 0)
        stack = []
        for c in range(gw + 1):
            hh = heights[c] if c < gw else 0
            start_c = c
            while stack and stack[-1][1] >= hh:
                sc_, sh = stack.pop()
                area = sh * (c - sc_)
                if area > best[0]:
                    best = (area, r - sh + 1, sc_, sh, c - sc_)
                start_c = sc_
            stack.append((start_c, hh))
    _, r0, c0, nh, nw = best
    tx0, ty0 = px0 + c0 * cell, py0 + r0 * cell
    tw, th = nw * cell, nh * cell
    ix, iy = int((px1 - px0) * 0.02), int((py1 - py0) * 0.035)
    tx0, ty0, tw, th = tx0 + ix, ty0 + iy, tw - 2 * ix, th - 2 * iy
    tx1, ty1 = tx0 + tw, ty0 + th
    return (int(px0), int(py0), int(px1 - px0), int(py1 - py0)), (int(tx0), int(ty0), int(tx1 - tx0), int(ty1 - ty0))


def poses():
    from PIL import Image
    os.makedirs(UI, exist_ok=True)
    out = {}
    for pose in POSES:
        rgb = np.asarray(Image.open(os.path.join(SRC, "poses", pose + ".png")).convert("RGB")).astype(np.float64) / 255.0
        rgba = cut(rgb)
        a = rgba[..., 3]
        ys, xs = np.nonzero(a > 0.06)
        x0, x1, y0, y1 = max(0, xs.min() - 6), min(a.shape[1], xs.max() + 7), max(0, ys.min() - 6), min(a.shape[0], ys.max() + 7)
        rgba = rgba[y0:y1, x0:x1]
        k = min(1.0, POSE_W / float(rgba.shape[1]))
        kb.OUT = UI
        im = kb.save(rgba, "scroll_" + pose, POSE_W)
        p, t = parchment(rgba)
        sc = lambda r: [round(v * k, 1) for v in r]
        out[pose] = {"size": [im.width, im.height], "parch": sc(p), "text": sc(t)}
        print("%-9s parchment %s  clear %s" % (pose, sc(p), sc(t)))
    lines = ["extends RefCounted", "# generated by tools/build_tutorial_assets.py (0.31.182) -- don't edit: each pose of the Herald with his",
             "# scroll (assets/ui/tutorial/scroll_<pose>.png): its size, its parchment and the clear part of it for the text, in",
             "# its pixels", "const POSES := {"]
    for pose in POSES:
        o = out[pose]
        lines.append('\t"%s": {"size": Vector2(%d, %d), "parch": Rect2(%s), "text": Rect2(%s)},' % (
            pose, o["size"][0], o["size"][1], ", ".join(str(v) for v in o["parch"]), ", ".join(str(v) for v in o["text"])))
    lines.append("}")
    open(os.path.join(GODOT, "scripts", "siege", "tutorial_poses.gd"), "w").write("\n".join(lines) + "\n")


def sounds():
    hs.SRC = os.path.join(SRC, "sfx")
    for cue, spec in RECALL.items():
        mix = hs.build(spec)
        wf.write(os.path.join(SOUNDS, cue + ".wav"), hs.SR, (mix * 32767).astype(np.int16))
        print("%-16s %.2f s  peak %.2f  rms(150ms) %.3f" % (cue, len(mix) / hs.SR, np.abs(mix).max(), hs.loudest_rms(mix)))


if __name__ == "__main__":
    which = ARGS or ["vo", "poses", "sounds"]
    if "vo" in which:
        vo()
    if "poses" in which:
        poses()
    if "sounds" in which:
        sounds()
