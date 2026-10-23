#!/usr/bin/env python3
"""Fatebound trailer 10, the vertical gameplay trailer (Kevin: "Now make a gameplay trailer that shows the actual game off
from a players perspective. Make the trailer vertical. Make it voiced by herald and make very funny. Show how the game
flow goes and also show some other things like guilds, heros, how battles go ect. Do not put captions so players can
focus on watching gameplay instead of reading").

Cuts the takes recorded by tools/trailer10_shots.gd (Movie Maker AVIs at 1080 x 1920, each with its log's REC_START)
into the trailer and mixes it: the game's own sound from each take, the Royal Herald's narration (tools/trailer10_vo,
ElevenLabs v4, his voice), and the game's theme (assets/music/match.ogg) under it all, dipping under him. No captions:
the only words on screen are the game's own. The plan is in tools/trailer10_script.md.

    python3 tools/trailer10_edit.py --rec <dir of <run>.avi + <run>.log> --out <mp4> [--preview] [--only a:b] [--ad]

1080 x 1920, 30 fps, H.264 + AAC, -14 LUFS (--preview: 540 x 960, quicker). Needs numpy, scipy, ffmpeg.
"""
import argparse
import json
import os
import re
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import trailer8_edit as T8      # noqa: E402  (load, place, fade, band, ramp_env, lufs, write_wav)

SR = T8.SR
FPS = 30
VO_DIR = os.path.join(HERE, "trailer10_vo", "raw")
MUSIC = os.path.join(GODOT, "assets", "music", "match.ogg")

# ---------- the Herald: one read of the whole script, two takes; each line cut from its take by the word timings ----------
LINES = [
    "[delighted] Ah! That's you. Being magnificent.",
    "[beat] Right. Let's back up a bit.",
    "This is Fatebound. Five heroes versus five.",
    "Two Kings... on two very comfortable chairs.",
    "Eighteen heroes. Knights. Wizards.",
    "A large, angry rock. [beat] Pick whoever matches your personality.",
    "Then dress them up. You may still lose... [dry] but you'll lose fabulously.",
    "Join a clan. Friends to fight beside. [beat] And to blame. Mostly to blame.",
    "Press PLAY, and your team assembles.",
    "[dry] Roughly on time.",
    "Follow the minions. Brave little lads. Nobody writes them songs.",
    "See an enemy? Press every button you have. Strategy can wait.",
    "[sighs] And when you die... I announce it. To everyone.",
    "Knock down their towers. They had it coming.",
    "This is the Grave Wyrm. [whispering] Never poke the Grave Wyrm.",
    "[flat] They always poke the Grave Wyrm.",
    "Then knock their King off his chair. [whispering] He'll be furious.",
    "Win, and there's loot. Lovely, shiny loot.",
    "Fatebound.",
    "[beat] Go on, then. Their King won't fall off that chair by himself.",
]
TAKE = {16: 1, 19: 1}               # line (1-based) -> take; the rest take 2 (the tighter read)
VO_LEVEL = -24.0                    # each line's voice-band level before the mix
VO_TEMPO = 1.07                     # his read, a touch brisker (pitch kept): a short's pace


def vo_line(k):
    """line k (1-based): its words' span in its take, a breath either side, faded, levelled"""
    take = TAKE.get(k, 2)
    words = [w for w in json.load(open(os.path.join(VO_DIR, "words_%d.json" % take)))["words"] if w.get("type") == "word"]
    i = 0
    for n, line in enumerate(LINES, 1):
        cnt = len(line.split())
        seg = words[i:i + cnt]
        if " ".join(w["text"] for w in seg) != line:
            raise SystemExit("take %d: line %d doesn't match its words: %s" % (take, n, [w["text"] for w in seg]))
        if n == k:
            spoken = [w for w in seg if not w["text"].startswith("[")]
            a, b = spoken[0]["start"], spoken[-1]["end"]
            nxt = words[i + cnt]["start"] if i + cnt < len(words) else b + 1.0
            prv = words[i - 1]["end"] if i > 0 else 0.0
            a = max(prv + 0.02, a - 0.08)
            b = min(nxt - 0.02, b + 0.22)
            tmp = os.path.join(VO_DIR, ".line%02d.wav" % k)
            ff(["-ss", "%.3f" % a, "-t", "%.3f" % (b - a), "-i", os.path.join(VO_DIR, "vo_herald_%d.mp3" % take),
                "-af", "atempo=%.3f" % VO_TEMPO, "-ac", "2", "-ar", str(SR), "-c:a", "pcm_f32le", tmp])
            ln = T8.fade(T8.load(tmp), 0.012, 0.08)
            os.remove(tmp)
            vb = T8.band(ln, 800, 4000)
            level = 20.0 * np.log10(np.sqrt(np.mean(vb ** 2)) + 1e-9)
            return ln * (10.0 ** ((VO_LEVEL - level) / 20.0))
        i += cnt
    raise SystemExit("no line %d" % k)


# ---------- the cut: (run, from, to [seconds of the take], speed, look) one after another ----------
# look: "" as recorded; "rewind": played backwards, fast, like a tape rewinding
SHOTS = [
    ("hook", 0.0, 5.3, 1.0, ""),           # 0  the teamfight: your static field, your storm -- a kill, DOUBLE KILL
    ("hook", 1.0, 5.3, 6.0, "rewind"),     # 1  ...backwards, like a tape
    ("home", 0.3, 4.7, 1.0, ""),           # 2  Home
    ("chair", 0.25, 4.15, 1.0, ""),        # 3  our King on his chair
    ("armory", 0.25, 1.75, 1.0, ""),       # 4  the Armory: the tanks (knights)
    ("armory", 1.75, 3.6, 2.5, ""),        # 5  ...a flick down the list
    ("armory", 3.6, 4.6, 1.0, ""),         # 6  ...the mages (wizards)
    ("golem", 0.3, 4.5, 1.0, ""),          # 7  the Golem's window
    ("outfit", 0.5, 5.5, 1.0, ""),         # 8  the Stormcaller's outfits tapped in turn
    ("clan", 0.2, 5.2, 1.0, ""),           # 9  the clan's camp, its members
    ("play", 0.3, 2.2, 1.0, ""),           # 10 PLAY -> the hero window, your Stormcaller tapped
    ("lobby", 0.4, 3.9, 1.0, ""),          # 11 the players joining
    ("lane", 0.3, 4.9, 1.0, ""),           # 12 up the middle lane behind the minions
    ("fight", 0.0, 5.3, 1.0, ""),          # 13 their Barbarian: Q W E R -- FIRST BLOOD
    ("death", 0.3, 4.7, 1.0, ""),          # 14 under their tower: slain
    ("tower", 1.2, 5.4, 1.0, ""),          # 15 their tower falls
    ("wyrm", 0.3, 6.9, 1.0, ""),           # 16 the Grave Wyrm
    ("king", 0.0, 6.0, 1.0, ""),           # 17 the King -- VICTORY
    ("chest", 0.3, 4.7, 1.0, ""),          # 18 a chest
    ("title", 0.0, 6.1, 1.0, ""),          # 19 the title slams onto the wall, TAP TO START
]
# the Herald's lines: (line, shot index, seconds into that shot, gain dB)
VO = [
    (1, 0, 1.95, 0.0), (2, 1, 0.0, 0.0),
    (3, 2, 1.25, 0.0), (4, 3, 0.95, 0.0),
    (5, 4, 0.25, 0.0), (6, 7, 0.25, 0.0),
    (7, 8, 0.1, 0.0),
    (8, 9, 0.15, 0.0),
    (9, 10, 0.0, 0.0), (10, 11, 1.9, 0.0),
    (11, 12, 0.2, 0.0),
    (12, 13, 0.1, 0.0),
    (13, 14, 0.6, 0.0),
    (14, 15, 0.4, 1.5),
    (15, 16, 0.2, 3.0), (16, 16, 4.3, 1.0),        # (his whisper: up a little)
    (17, 17, 0.1, 3.0),
    (18, 18, 0.3, 0.0),
    (19, 19, 0.8, 1.0), (20, 19, 2.3, 0.0),
]
GAME_LUFS = -21.0                   # each take's own sound, levelled
GAME_GAIN = {"title": 3.0, "lobby": -2.0}
MUSIC_GAIN = -6.0
MUSIC_END = "title"                 # the theme fades out into the title (its own jingle and slam take over)


def use_ad():
    # --ad: the cut for TikTok's ads (Oct 23 2026, rejected: "FIRST WIN +150", "16 HEROES +1 FREE" and the loot line at
    # 1:06-1:11 -- "guaranteed free in-game rewards tied to user actions"): no chest shot and no "Win, and there's loot"
    # (line 18), from takes recorded with AD_SAFE=1 (trailer10_shots.gd: no rewards or freebies on screen)
    global SHOTS, VO
    keep = [i for i, d in enumerate(SHOTS) if d[0] != "chest"]
    remap = {old: new for new, old in enumerate(keep)}
    SHOTS = [SHOTS[i] for i in keep]
    VO = [(k, remap[si], off, g) for (k, si, off, g) in VO if si in remap and k != 18]


def shot_frames(d):
    return int(round((d[2] - d[1]) / d[3] * FPS))


def timeline():
    t, out = 0.0, []
    for d in SHOTS:
        n = shot_frames(d)
        out.append((d, t, n))
        t += n / FPS
    return out, t


def rec_start(rec, run):
    m = re.search(r"REC_START (\d+)", open(os.path.join(rec, run + ".log")).read())
    return int(m.group(1))


def avi_t(rec, run, tin):
    """a take's second -> its AVI's (Movie Maker's frame i is the process's frame i + 1: the take's frame 0 is REC_START)"""
    return (rec_start(rec, run) - 1) / FPS + tin


def ff(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + args, check=True)


# ---------- picture ----------
def picture(rec, work, W, H, preview):
    tl, total = timeline()
    segs = []
    for i, (d, at, n) in enumerate(tl):
        run, a, b, sp, look = d
        src = os.path.join(rec, run + ".avi")
        seg = os.path.join(work, "seg%02d.mp4" % i)
        vf = ["scale=%d:%d:flags=lanczos" % (W, H)]
        if look == "rewind":
            # backwards and fast, a tape rewinding: colour fringes, a little noise, a wobble of brightness
            vf = ["reverse", "setpts=PTS/%.3f" % sp] + vf + ["rgbashift=rh=-5:bh=5", "noise=alls=14:allf=t",
                                                             "eq=saturation=0.75:contrast=1.08"]
        elif sp != 1.0:
            vf = ["setpts=PTS/%.3f" % sp] + vf
        vf += ["fps=%d" % FPS, "format=yuv420p"]
        ff(["-ss", "%.4f" % avi_t(rec, run, a), "-t", "%.4f" % (b - a), "-i", src, "-vf", ",".join(vf),
            "-frames:v", str(n), "-an", "-c:v", "libx264", "-preset", "veryfast" if preview else "slow",
            "-crf", "22" if preview else "15", seg])
        segs.append(seg)
    lst = os.path.join(work, "segs.txt")
    open(lst, "w").write("".join("file '%s'\n" % s for s in segs))
    out = os.path.join(work, "picture.mp4")
    ff(["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", out])
    return out, total


# ---------- sound ----------
def take_audio(rec, run, a, b, sp, look):
    tmp = os.path.join(rec, ".t10_%s.wav" % run)
    af = []
    if look == "rewind":
        # backwards, and up in pitch as it speeds: a tape rewinding (3x by its rate, the rest by tempo)
        af = ["aresample=%d" % SR, "areverse", "asetrate=%d" % (SR * 3), "aresample=%d" % SR, "atempo=%.3f" % (sp / 3.0)]
    elif sp != 1.0:
        af = ["atempo=%.3f" % sp]
    ff(["-ss", "%.4f" % avi_t(rec, run, a), "-t", "%.4f" % (b - a), "-i", os.path.join(rec, run + ".avi"), "-vn",
        "-ac", "2", "-ar", str(SR)] + (["-af", ",".join(af)] if af else []) + ["-c:a", "pcm_f32le", tmp])
    x = T8.load(tmp)
    os.remove(tmp)
    return x


def tape_stop(x, dur):
    """the last dur seconds of x slowing to a halt (a tape stopping)"""
    n = int(dur * SR)
    rate = np.linspace(1.0, 0.0, n) ** 1.6
    pos = np.cumsum(rate)
    idx = np.clip(pos.astype(np.int64), 0, len(x) - 1)
    return x[idx] * np.linspace(1.0, 0.0, n)[:, None] ** 0.5


def sound(rec, out, total):
    n = int(total * SR) + SR
    tl, _ = timeline()
    starts = [at for (_, at, _) in tl]
    # the game's own sound, take by take
    game = np.zeros((n, 2), np.float32)
    for (d, at, nf) in tl:
        run, a, b, sp, look = d
        x = take_audio(rec, run, a, b, sp, look)
        x = x[:int(nf / FPS * SR)]
        if np.abs(x).max() > 1e-4:
            lv = T8.lufs(x)
            g = (GAME_LUFS - lv) if np.isfinite(lv) and lv > -70 else 0.0
            x = x * (10.0 ** ((g + GAME_GAIN.get(run, 0.0)) / 20.0))
        T8.place(game, T8.fade(x, 0.006, 0.02), at)
    # the theme: from the start, stopping like a tape on the rewind, back from the top after it, out into the title
    th = T8.load(MUSIC)
    th = np.concatenate([th, th])
    music = np.zeros((n, 2), np.float32)
    rw = [i for i, (d, _, _) in enumerate(tl) if d[4] == "rewind"][0]
    t_rw = starts[rw]
    head = th[:int(t_rw * SR)]
    head = np.concatenate([head[:-int(0.35 * SR)], tape_stop(th[int(t_rw * SR) - int(0.35 * SR):], 0.35)])
    T8.place(music, T8.fade(head, 0.02, 0.0), 0.0)
    t_back = starts[rw + 1]
    t_title = starts[[i for i, (d, _, _) in enumerate(tl) if d[0] == MUSIC_END][0]]
    body = th[:int((t_title - t_back + 0.3) * SR)]
    T8.place(music, T8.fade(body, 0.03, 0.6), t_back)
    # the Herald
    vo = np.zeros((n, 2), np.float32)
    spans = []
    for (k, si, off, g) in VO:
        ln = vo_line(k)
        at = starts[si] + off
        T8.place(vo, ln, at, g)
        spans.append((at, at + len(ln) / SR))
    # under him: the theme dips in the voice band and a little overall, the game's sound dips in the voice band
    vb = T8.band(music, 800, 4000)
    music = music - vb + vb * T8.ramp_env(n, spans, -12.0, 0.25)[:, None]
    music *= T8.ramp_env(n, spans, -4.0, 0.25)[:, None]
    gb = T8.band(game, 800, 4000)
    game = game - gb + gb * T8.ramp_env(n, spans, -9.0, 0.2)[:, None]
    mix = music * (10.0 ** (MUSIC_GAIN / 20.0)) + game + vo * 1.5
    if os.environ.get("T10_STEMS"):                        # (to measure him against the rest)
        T8.write_wav(out + ".vo.wav", vo * 1.5)
        T8.write_wav(out + ".bed.wav", music * (10.0 ** (MUSIC_GAIN / 20.0)) + game)
    end = int(total * SR)
    mix = mix[:end]
    tail = int(0.5 * SR)
    mix[end - tail:] *= np.linspace(1, 0, tail)[:, None]
    tmp = out + ".mix.wav"
    T8.write_wav(tmp, mix * (10.0 ** ((-14.0 - T8.lufs(mix)) / 20.0)))
    ff(["-i", tmp, "-af", "alimiter=limit=0.84:attack=4:release=60:level=false", "-ar", str(SR), "-c:a", "pcm_f32le",
        out + ".lim.wav"])
    ff(["-i", out + ".lim.wav", "-c:a", "aac", "-b:a", "256k", out])
    print("mix: %.1f LUFS after the limiter" % T8.lufs(T8.load(out + ".lim.wav")))
    os.remove(tmp)
    os.remove(out + ".lim.wav")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rec", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--times", action="store_true", help="print where each shot and line falls, and stop")
    ap.add_argument("--ad", action="store_true", help="the ad cut (TikTok's review): no chest, no loot line; AD_SAFE takes")
    a = ap.parse_args()
    if a.ad:
        use_ad()
    tl, total = timeline()
    if a.times:
        for i, (d, at, nf) in enumerate(tl):
            print("%2d %6.2f  %-7s %5.2f-%5.2f x%.2f %s" % (i, at, d[0], d[1], d[2], d[3], d[4]))
        for (k, si, off, g) in VO:
            ln = vo_line(k)
            at = tl[si][1] + off
            print("   line %2d %6.2f-%6.2f  %s" % (k, at, at + len(ln) / SR, LINES[k - 1]))
        print("total %.2f s" % total)
        return
    work = a.out + ".work"
    os.makedirs(work, exist_ok=True)
    W, H = (540, 960) if a.preview else (1080, 1920)
    pic, total = picture(a.rec, work, W, H, a.preview)
    aud = os.path.join(work, "sound.m4a")
    sound(a.rec, aud, total)
    ff(["-i", pic, "-i", aud, "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "copy", "-movflags", "+faststart", a.out])
    print("cut", a.out, "%.2f s" % total)


if __name__ == "__main__":
    main()
