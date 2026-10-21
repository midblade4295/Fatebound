#!/usr/bin/env python3
"""Fatebound trailer 8 (the 5v5) -- the cut, the finish and the mix.

Kevin: "I want a trailer now. Very cinematic and showing gameplay. Also voice it. I want it to feature the dragon roaring
for climax along with music ramping up to climax then showing the title animating in".

The picture: the staged runs Movie Maker recorded (tools/trailer8_render.sh -> REC/<run>.avi + .log), cut to the score's
landmarks (CUTS), then per frame a filmic grade (a gentle S-curve, cool shadows and warm highlights, a vignette), the
2.39:1 letterbox, fades and flashes. The title is a run of its own (tools/trailer8_shots.gd "title": the game's animated
title, title_logo.gd, slammed in over the Rift at dusk).

The sound (all at 48 kHz, mixed in numpy): the score (ElevenLabs Music v2.5 -- cue A, the dark opening, the battle, the
drop and the climax; cue B, the title's two hits and its ring-out; their silent stretches cut out, SCORE), the narrator
(the game's Royal Herald: ElevenLabs v4, his voice Edward), the Grave
Wyrm's roar, the ground breaking, the lightning, the game's own title slam, and the game's sounds from the recordings
under the action. The music dips only in its voice band (800-4000 Hz) under each line, on slow ramps (Kevin on trailer 6:
"the music volume drops too much when voice happens, it needs to blend better"). -14 LUFS.

    python3 tools/trailer8_edit.py --rec REC --out Fatebound-Trailer-8.mp4 [--still T] [--only T0:T1]
Sources (tools/trailer8_vo/raw): vo_1.mp3, musA_1.mp3, musB_1.mp3, roar_1.mp3, roar_4.mp3, rumble_1.mp3, rumble_2.mp3,
bolt_2.mp3. Needs numpy, scipy, Pillow, ffmpeg.
"""
import argparse
import json
import os
import re
import subprocess
import sys

import numpy as np
from scipy import signal

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
RAW = os.environ.get("T8_RAW", os.path.join(HERE, "trailer8_vo", "raw"))
SOUNDS = os.environ.get("T8_SOUNDS", os.path.join(GODOT, "assets", "sounds"))
W, H, FPS = 1920, 1080, 30
SR = 48000
BAR = 138                                   # 2.39:1 inside 16:9

# ---------- the score: cue A and cue B, cut so the music never stops (Kevin: "fix pacing because there's several spots
# where there is no music and nothing happening") ----------
# Cue A (musA_1): its first sound 0.5; a breath of silence before the drums (15.6-16.4) crash in at 16.53 (120 BPM, bars
# on x.53); the drop 32.55, near silence 33.1-34.4 until the climax crashes in at 34.53; it ends 42.6. Cue B (musB_1): a
# hit at 0.0 dying to near silence by 1.5, a swell from 3.3 into a second hit at 3.9, a chord to 7.5, ringing out.
# The pieces kept: (source, from, to, trailer time), joined by short crossfades (XF).
XF = 0.12
SCORE = [
    ("musA_1", 0.40, 15.45, 0.00),            # the opening
    ("musA_1", 16.38, 33.10, 15.05),          # the battle (its drums crash in at 15.20)
    ("musA_1", 34.28, 42.70, 31.77),          # a short drop, then the climax (crashing in at 32.02)
    ("musB_1", 0.00, 1.10, 40.19),            # the title's first hit (the lightning)
    ("musB_1", 3.00, 9.50, 41.29),            # the swell into its second hit (the slam, at 42.19), the chord
]
HIT = 15.20                                   # the drums
HIT2 = 32.02                                  # the climax
B_AT = 40.19                                  # the lightning
B_SLAM = 42.19                                # the slam
TOTAL = 47.20

# ---------- the cut: (trailer start, end, run, the run's recording second at the start) ----------
CUTS = [
    (0.00, 4.55, "vista", 0.1),
    (4.55, 9.35, "kingred", 0.6),
    (9.35, HIT, "charge", 4.0),
    (HIT, 17.20, "clash", 0.95),
    (17.20, 18.70, "meteor", 0.9),
    (18.70, 20.20, "dive", 1.1),
    (20.20, 21.70, "slide", 1.0),
    (21.70, 23.20, "duel", 0.9),
    (23.20, 25.20, "tower", 1.3),
    (25.20, 31.20, "breach", 0.2),
    (31.20, HIT2, "pit", 3.6),
    (HIT2, 36.09, "rise", 1.6),
    (36.09, 37.89, "roar", 2.3),
    (37.89, B_AT, "roar2", 4.1),
    (B_AT, TOTAL, "title", 1.033),            # (its lightning fired at 1.033: on cue B's first hit)
]
FADES = [(0.0, 0.6, "in"), (TOTAL - 1.0, TOTAL, "out")]            # from / to black
FLASHES = [(HIT, 0.25), (HIT2, 0.30)]                               # white, on the hits (fading over the seconds given)

# ---------- the narrator, the Royal Herald (Edward): (line, trailer time) ----------
VO_LINES = [(1, 0.90), (2, 5.40), (3, 10.30), (4, 17.35), (5, 23.40), (6, 26.30), (7, 30.75), (8, 32.70), (9, 42.35),
            (10, 44.00)]


def rec_start(rec, run):
    m = re.search(r"REC_START (\d+)", open(os.path.join(rec, run + ".log")).read())
    return int(m.group(1))


def avi_frame(rec, run, rin):
    """the recording's frame at rin seconds after the staging (Movie Maker's frame i is the run's process frame i + 1;
    the staging frame is REC_START, its first filmed frame the next)"""
    return rec_start(rec, run) - 1 + int(round(rin * FPS))


# ---------- picture ----------
def grade(f, vig):
    lum = (f[..., 0] * 0.2126 + f[..., 1] * 0.7152 + f[..., 2] * 0.0722)[..., None]
    s = f * f * (3.0 - 2.0 * f)                                   # S-curve
    f = f * 0.74 + s * 0.26
    f = lum + (f - lum) * 0.88                                    # a little less saturation (the game's greens are loud)
    sh = (1.0 - lum) ** 2
    hi = lum ** 2
    f = f + sh * np.array([-0.014, 0.008, 0.034], np.float32) + hi * np.array([0.032, 0.012, -0.024], np.float32)
    return np.clip(f * vig, 0.0, 1.0)


def vignette():
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.sqrt(((x - W / 2) / (W / 2)) ** 2 + ((y - H / 2) / (H / 2)) ** 2)
    return (1.0 - 0.32 * np.clip((r - 0.55) / 0.85, 0.0, 1.0) ** 1.6)[..., None].astype(np.float32)


def frames_of(path, start_frame, n):
    """n RGB frames of the AVI from start_frame (decoded by ffmpeg)."""
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-vf", "select=gte(n\\,%d),scale=%d:%d" % (start_frame, W, H),
           "-vsync", "0", "-frames:v", str(n), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    got = 0
    while got < n:
        b = p.stdout.read(W * H * 3)
        if len(b) < W * H * 3:
            break
        got += 1
        yield np.frombuffer(b, np.uint8).reshape(H, W, 3)
    p.stdout.close()
    p.wait()
    for _ in range(n - got):                                   # (a run cut short: hold its last frame)
        yield None


def picture(rec, out, only=None, still=-1.0):
    vig = vignette()
    n_total = int(round(TOTAL * FPS))
    t0, t1 = (0, n_total) if only is None else (int(only[0] * FPS), int(only[1] * FPS))
    if still >= 0.0:
        t0, t1 = int(still * FPS), int(still * FPS) + 1
    enc = None
    if still < 0.0:
        enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H),
                                "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "14",
                                "-pix_fmt", "yuv420p", out], stdin=subprocess.PIPE)
    black = np.zeros((H, W, 3), np.uint8)
    fi = t0
    for (a, b, run, rin) in CUTS:
        fa, fb = int(round(a * FPS)), int(round(b * FPS))
        if fb <= t0 or fa >= t1:
            continue
        while fi < fa and fi < t1:                               # gaps: black
            if enc:
                enc.stdin.write(black.tobytes())
            fi += 1
        lo, hi = max(fa, t0), min(fb, t1)
        src0 = avi_frame(rec, run, rin) + (lo - fa)
        last = None
        for k, fr in enumerate(frames_of(os.path.join(rec, run + ".avi"), src0, hi - lo)):
            fr = last if fr is None else fr
            last = fr
            t = (lo + k) / FPS
            f = fr.astype(np.float32) / 255.0
            f = grade(f, vig)
            for (fa2, fb2, kind) in FADES:
                if fa2 <= t < fb2:
                    u = (t - fa2) / (fb2 - fa2)
                    f = f * (u if kind == "in" else 1.0 - u)
            for (ft, fl) in FLASHES:
                if ft <= t < ft + fl:
                    w = 0.85 * (1.0 - (t - ft) / fl) ** 2
                    f = f * (1.0 - w) + w
            img = (f * 255.0 + 0.5).astype(np.uint8)
            img[:BAR] = 0
            img[H - BAR:] = 0
            if still >= 0.0:
                from PIL import Image
                Image.fromarray(img).save(out)
                return
            enc.stdin.write(img.tobytes())
            fi += 1
    while fi < t1:
        enc.stdin.write(black.tobytes())
        fi += 1
    enc.stdin.close()
    enc.wait()


# ---------- sound ----------
def load(path, speed=1.0):
    """mono or stereo file -> stereo float32 at SR (speed < 1: slower and lower, as tape)"""
    sr_in = int(SR * speed)
    b = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "2", "-ar", str(sr_in), "-f", "f32le", "-"],
                       capture_output=True, check=True).stdout
    return np.frombuffer(b, np.float32).reshape(-1, 2).copy()


def place(bus, clip, at, gain_db=0.0):
    i = int(round(at * SR))
    if i < 0:
        clip = clip[-i:]
        i = 0
    n = min(len(clip), len(bus) - i)
    if n > 0:
        bus[i:i + n] += clip[:n] * (10.0 ** (gain_db / 20.0))


def fade(clip, fin=0.0, fout=0.0):
    c = clip.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a > 0:
        c[:a] *= np.linspace(0, 1, a)[:, None]
    if b > 0:
        c[-b:] *= np.linspace(1, 0, b)[:, None]
    return c


# the Herald's take (vo_herald_1) cut at its nine pauses (ffmpeg silencedetect, -36 dB for 0.18 s: their middles)
VO_TAKE = "vo_herald_1.mp3"
VO_CUTS = [1.164, 2.536, 4.016, 5.693, 7.208, 8.859, 10.592, 12.857, 14.191]
VO_LEVEL = -24.0                             # each line's voice-band level (dBFS) before the mix


def vo_lines():
    """the narrator's take cut into its ten lines, each trimmed to its sound"""
    x = load(os.path.join(RAW, VO_TAKE))
    bounds = [0] + [int(c * SR) for c in VO_CUTS] + [len(x)]
    lines = []
    for a, b in zip(bounds[:-1], bounds[1:]):
        seg = x[a:b]
        nz = np.where(np.abs(seg).max(1) > 10 ** (-42 / 20))[0]
        ln = fade(seg[max(0, nz[0] - int(0.03 * SR)):nz[-1] + int(0.15 * SR)], 0.01, 0.10)
        vb = band(ln, 800, 4000)
        level = 20.0 * np.log10(np.sqrt(np.mean(vb ** 2)) + 1e-9)
        lines.append(ln * (10.0 ** ((VO_LEVEL - level) / 20.0)))       # (each line levelled: the whispers too)
    return lines


def band(x, lo, hi):
    sos = signal.butter(4, [lo, hi], btype="bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0).astype(np.float32)


def lowpass(x, f):
    sos = signal.butter(4, f, btype="lowpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0).astype(np.float32)


def ramp_env(n, spans, depth_db, ramp=0.6):
    """1.0, dipping by depth_db over each span (a, b), on smooth ramps"""
    env = np.zeros(n, np.float32)
    for a, b in spans:
        ia, ib = int((a - ramp) * SR), int((b + ramp) * SR)
        r = int(ramp * SR)
        seg = np.ones(ib - ia, np.float32)
        seg[:r] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, r))
        seg[-r:] = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, r))
        lo, hi = max(0, ia), min(n, ib)
        env[lo:hi] = np.maximum(env[lo:hi], seg[lo - ia:hi - ia])
    return 10.0 ** (depth_db * env / 20.0)


def rec_time(rec, run, t):
    """the recording second (after the staging) at the run's game time t (its TT log: frame, game time)"""
    pts = [(int(k), float(v)) for k, v in re.findall(r"TT (\d+) ([\d.]+)", open(os.path.join(rec, run + ".log")).read())]
    ks = np.array([p[0] for p in pts], np.float64)
    ts = np.array([p[1] for p in pts], np.float64)
    return float(np.interp(t, ts, ks)) / FPS


def trailer_time(rec, run, t):
    """where the run's game time t lands in the trailer (None: not in any of its cuts)"""
    r = rec_time(rec, run, t)
    for (a, b, cr, rin) in CUTS:
        if cr == run and rin <= r < rin + (b - a):
            return a + (r - rin)
    return None


def sound(rec, out):
    n = int(TOTAL * SR) + SR
    music = np.zeros((n, 2), np.float32)
    cues = {}
    for (src, a, b, at) in SCORE:
        if src not in cues:
            cues[src] = load(os.path.join(RAW, src + ".mp3"))
        x = cues[src]
        i0, i1 = int(max(0.0, a - XF / 2) * SR), int((b + XF / 2) * SR)
        place(music, fade(x[i0:i1], XF, XF), at - XF / 2, -0.5 if src == "musB_1" else 0.0)
    # the climax ramps: cue A from its crash to the roar, rising 3 dB into it
    i0, i1 = int(HIT2 * SR), int((ROAR_AT + 1.5) * SR)
    music[i0:i1] *= np.linspace(10 ** (-3 / 20), 1.0, i1 - i0)[:, None]
    fx = np.zeros((n, 2), np.float32)
    # the Grave Wyrm: the ground breaking under the pit and as it rises; its roar (slowed with the picture, two takes)
    place(fx, fade(load(os.path.join(RAW, "rumble_2.mp3")), 0.6, 1.0), 30.9, -6.0)
    place(fx, fade(load(os.path.join(RAW, "rumble_1.mp3")), 0.02, 1.5), HIT2 - 0.05, -2.0)
    roar = fade(load(os.path.join(RAW, "roar_1.mp3"), 0.86), 0.01, 0.6)
    roar2 = fade(load(os.path.join(RAW, "roar_4.mp3"), 0.8), 0.05, 0.8)
    place(fx, roar, ROAR_AT, 0.0)
    place(fx, roar2, ROAR_AT + 0.08, -7.0)
    # the title: the lightning on cue B's first hit, the game's own title slam on its second
    place(fx, fade(load(os.path.join(RAW, "bolt_2.mp3")), 0.0, 1.0), B_AT - 0.02, -3.0)
    place(fx, load(os.path.join(SOUNDS, "titleSlam.wav")), B_SLAM - 0.02, -4.0)
    # the game's own sounds on the action (Movie Maker's track is all but silent: the game hears from your hero, not
    # the camera), each placed on its moment and slowed with the picture where it's in slow motion
    game = np.zeros((n, 2), np.float32)
    cache = {}
    for (run, t, name, gain, speed) in SFX:
        at = trailer_time(rec, run, t) if run else t
        if at is None:
            continue
        key = (name, speed)
        if key not in cache:
            cache[key] = fade(load(os.path.join(SOUNDS, name + ".wav"), speed), 0.0, 0.05)
        place(game, cache[key], at, gain)
    # the narrator
    lines = vo_lines()
    vo = np.zeros((n, 2), np.float32)
    spans = []
    for (k, at) in VO_LINES:
        ln = lines[k - 1]
        place(vo, ln, at, VO_GAIN.get(k, 0.0))
        spans.append((at, at + len(ln) / SR))
    # the music and the effects dip in the voice band under each line (slow ramps), a little overall
    vb = band(music, 800, 4000)
    music = music - vb + vb * ramp_env(n, spans, -10.0)[:, None]
    music *= ramp_env(n, spans, -3.0)[:, None]
    for bus in (fx, game):
        bb = band(bus, 800, 4000)
        bus -= bb - bb * ramp_env(n, spans, -8.0)[:, None]
    mix = music * 0.9 + fx * 0.95 + game + vo * 1.45
    if os.environ.get("T8_STEMS"):                         # (to measure the narration against the rest)
        write_wav(out + ".vo.wav", vo * 1.45)
        write_wav(out + ".bed.wav", music * 0.9 + fx * 0.95 + game)
    mix[int(TOTAL * SR):] = 0.0
    tail = int(1.2 * SR)
    end = int(TOTAL * SR)
    mix[end - tail:end] *= np.linspace(1, 0, tail)[:, None]
    mix = mix[:end]
    # to -14 LUFS by one gain (measured), then a limiter keeps the peaks under -1 dB
    tmp = out + ".mix.wav"
    write_wav(tmp, mix * (10.0 ** ((-14.0 - lufs(mix)) / 20.0)))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-af", "alimiter=limit=0.82:attack=4:release=60:level=false",
                    "-ar", str(SR), "-c:a", "pcm_f32le", out + ".lim.wav"], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", out + ".lim.wav", "-c:a", "aac", "-b:a", "256k", out], check=True)
    print("mix: %.1f LUFS after the limiter" % lufs(load(out + ".lim.wav")))
    os.remove(tmp)
    os.remove(out + ".lim.wav")


ROAR_AT = 36.41                              # (the roar shot: the Wyrm rears up)
# the game's sounds: (run, its game time -- or "" and a trailer time, name in assets/sounds, gain dB, speed)
SFX = [("", 9.55, "horn", -7.0, 0.9),
       ("clash", 1.04, "tm_sword_hit1", -6.0, 0.6), ("clash", 1.08, "tm_sword_block2", -8.0, 0.55),
       ("clash", 1.12, "tm_spell_hit1", -9.0, 0.6), ("clash", 1.18, "tm_sword_hit3", -7.0, 0.5),
       ("clash", 1.25, "axe", -8.0, 0.5), ("clash", 1.33, "tm_spell_hit2", -10.0, 0.5),
       ("meteor", 0.9, "tm_bomb_blast", -5.0, 0.6), ("meteor", 1.2, "tm_bomb_blast", -7.0, 0.55),
       ("meteor", 1.5, "tm_bomb_blast", -7.0, 0.6), ("meteor", 1.8, "tm_bomb_blast", -8.0, 0.55),
       ("meteor", 0.65, "meteor", -8.0, 0.7), ("meteor", 0.95, "meteor", -9.0, 0.6), ("meteor", 1.25, "meteor", -10.0, 0.6),
       ("dive", 0.6, "ult_dragoon", -8.0, 0.6), ("dive", 1.03, "ult_dragoon_land", -3.0, 0.55), ("dive", 1.05, "crit", -7.0, 0.5),
       ("slide", 0.55, "ult_golem", -6.0, 0.6), ("slide", 0.66, "tm_rock_hit1", -6.0, 0.55),
       ("slide", 0.74, "tm_rock_hit2", -7.0, 0.55), ("slide", 0.86, "ab_quake", -4.0, 0.6),
       ("duel", 0.66, "tm_sword_swing2", -9.0, 0.5), ("duel", 0.72, "tm_sword_block3", -4.0, 0.45),
       ("duel", 0.74, "parry", -8.0, 0.5),
       ("tower", 0.6, "tm_gate_hit1", -10.0, 0.9), ("tower", 1.0, "tm_gate_hit2", -10.0, 0.9),
       ("tower", 1.55, "tm_bomb_blast", -3.0, 0.5), ("tower", 1.56, "tm_crumble1", -4.0, 0.55),
       ("tower", 1.8, "tm_crumble2", -5.0, 0.55),
       ("breach", 0.1, "tm_gate_hit1", -6.0, 0.8), ("breach", 0.4, "tm_gate_hit2", -6.0, 0.8),
       ("breach", 0.7, "tm_gate_hit1", -5.0, 0.8), ("breach", 0.9, "tm_bomb_blast", -3.0, 0.5),
       ("breach", 0.92, "tm_crumble1", -4.0, 0.55), ("breach", 1.15, "tm_crumble2", -6.0, 0.55)]
VO_GAIN = {7: 1.0, 8: 4.0, 9: 8.0, 10: 6.0}            # (the climax and the title are loud under them)


def lufs(x):
    """integrated loudness (ffmpeg's ebur128) of a stereo float array"""
    p = subprocess.run(["ffmpeg", "-v", "info", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-af", "ebur128",
                        "-f", "null", "-"], input=np.clip(x, -4, 4).astype(np.float32).tobytes(), capture_output=True)
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", p.stderr.decode())
    return float(m[-1])


def write_wav(path, x):
    x = np.clip(x, -2.0, 2.0)
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                          "-c:a", "pcm_f32le", path], stdin=subprocess.PIPE)
    p.stdin.write(x.astype(np.float32).tobytes())
    p.stdin.close()
    p.wait()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rec", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--still", type=float, default=-1.0)
    ap.add_argument("--only", default="")
    ap.add_argument("--sound-only", action="store_true")
    a = ap.parse_args()
    if a.still >= 0.0:
        picture(a.rec, a.out, still=a.still)
        return
    only = tuple(float(v) for v in a.only.split(":")) if a.only else None
    pic = a.out + ".pic.mp4"
    snd = a.out + ".mix.m4a"
    sound(a.rec, snd)
    if a.sound_only:
        return
    picture(a.rec, pic, only)
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", pic, "-i", snd]
    if only:
        cmd += ["-ss", "%.3f" % only[0], "-t", "%.3f" % (only[1] - only[0])]
        cmd = ["ffmpeg", "-v", "error", "-y", "-i", pic, "-ss", "%.3f" % only[0], "-t", "%.3f" % (only[1] - only[0]), "-i", snd]
    cmd += ["-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart",
            a.out]
    subprocess.run(cmd, check=True)
    os.remove(pic)
    os.remove(snd)
    print("wrote", a.out)


if __name__ == "__main__":
    main()
