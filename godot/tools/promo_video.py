#!/usr/bin/env python3
"""Fatebound's store promo video (0.31.212: the heycatch.ai listing audit's D3.5 -- "Record 15-30 seconds of gameplay
showing a team fight or First Blood moment ... Ensure the first 2 seconds show gameplay action, not a logo intro"; Kevin:
"Build how the audit says"). For Google Play's promo video field (a YouTube link), so landscape, 1920 x 1080.

29 seconds of the real game -- the takes tools/trailer10_shots.gd recorded (Movie Maker, 1080 x 1920, the phone's HUD
and sound as they play; AD_SAFE ones where there are) -- on a phone-shaped card in the middle, from the first frame:
the team fight and its DOUBLE KILL, the lane, FIRST BLOOD, a tower falling, the Grave Wyrm, their King toppled and
VICTORY. Around the card, in the store screenshots' look (tools/store5_compose.py): the same footage blurred behind
it, a two-line headline on the left, the shot's hero in 3D on the right (the HD renders,
store-listing/graphics/raw_renders/store5/art), sliding in as each shot starts. The last 3 seconds are the end card:
the heroes, the title and FAST 5V5 MOBA BATTLES. Sound: each take's own, levelled, and the game's theme under it all;
-14 LUFS.

    python3 tools/promo_video.py --rec <dir of <run>.avi + <run>.log> --out <mp4> [--preview]

Needs numpy, Pillow, ffmpeg.
"""
import argparse
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import store5_compose as S5     # noqa: E402  (text_layer, phone's look, logo_img, rounded_mask)
import trailer8_edit as T8      # noqa: E402  (load, place, fade, lufs, write_wav)

FPS = 30
SR = T8.SR
W, H = 1920, 1080
ART = os.path.join(GODOT, "store-listing", "graphics", "raw_renders", "store5", "art")
MUSIC = os.path.join(GODOT, "assets", "music", "match.ogg")

# (take, from, to [seconds of the take], headline, the hero on the right, the shot's colour)
SHOTS = [
    ("hook", 0.0, 5.3, ("TEAM UP FOR", "5V5 HERO BATTLES"), "stormcaller", (120, 190, 255)),   # the storm, DOUBLE KILL
    ("lane", 0.3, 3.6, ("PUSH", "THE LANES"), "knight", (170, 255, 190)),                      # behind the minions
    ("fight", 1.5, 5.5, ("CLAIM", "FIRST BLOOD"), "mage", (255, 170, 150)),                    # FIRST BLOOD
    ("tower", 2.0, 5.4, ("BREAK", "THEIR TOWERS"), "barbarian", (255, 205, 140)),              # the tower falls
    ("wyrm", 0.5, 5.0, ("SLAY THE", "GRAVE WYRM"), "dragoon", (150, 255, 220)),                # the Grave Wyrm
    ("king", 1.0, 6.6, ("TOPPLE", "THEIR KING"), "king", (255, 220, 150)),                     # their King, VICTORY
]
END_S = 3.0
END_HEROES = [["king", 1.085, 0.5, 0.98], ["dragoon", 1.47, 0.4, 0.86], ["knight", 0.74, 0.56, 0.95],
              ["barbarian", 0.36, 0.58, 1.0], ["stormcaller", 1.8, 0.57, 1.02]]
# the art as rendered looks across to the right (the Dragoon is drawn from his left): here, on the right, they look
# left at the game
FACES_LEFT = {"dragoon"}
GAME_LUFS = -21.0
MUSIC_GAIN = -7.0
TARGET_LUFS = -14.0

CARD_H = int(H * 0.93)
CARD_W = int(round(CARD_H * 1080 / 1920))
CARD_X = (W - CARD_W) // 2
CARD_Y = (H - CARD_H) // 2


def ff(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + args, check=True)


def rec_start(rec, run):
    m = re.search(r"REC_START (\d+)", open(os.path.join(rec, run + ".log")).read())
    return int(m.group(1))


def avi_t(rec, run, tin):
    # (Movie Maker's frame i is the process's frame i + 1: the take's frame 0 is REC_START, as trailer10_edit.py)
    return (rec_start(rec, run) - 1) / FPS + tin


def frames(rec, run, a, b):
    n = int(round((b - a) * FPS))
    p = subprocess.run(["ffmpeg", "-v", "error", "-ss", "%.4f" % avi_t(rec, run, a), "-t", "%.4f" % (b - a), "-i",
                        os.path.join(rec, run + ".avi"), "-vf", "fps=%d,scale=1080:1920" % FPS, "-frames:v", str(n),
                        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    arr = np.frombuffer(p, np.uint8).reshape(-1, 1920, 1080, 3)
    return arr, n


def ease(t):
    t = min(1.0, max(0.0, t))
    return 1.0 - (1.0 - t) ** 3


def card_frame(glow):
    """the card's glow, shadow and rim (store5_compose.phone's look), and the screen's rounded mask"""
    blank = Image.new("RGB", (1080, 1920), (0, 0, 0))
    card, pad = S5.phone(blank, CARD_H, glow)
    mask = S5.rounded_mask((CARD_W, CARD_H), int(CARD_H * 0.045))
    return card, pad, mask


def blurred(fr):
    """the frame behind the card: covering the canvas, out of focus, darker (blurred small, then scaled up: quick)"""
    im = Image.fromarray(fr)
    small = S5.cover(im, (W // 6, H // 6)).filter(ImageFilter.GaussianBlur(5))
    b = small.resize((W, H), Image.BILINEAR)
    b = ImageEnhance.Brightness(ImageEnhance.Color(b).enhance(1.15)).enhance(0.62)
    return b


def hero_img(name):
    im = Image.open(os.path.join(ART, "store_%s_wide.webp" % name)).convert("RGBA")
    if name not in FACES_LEFT:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    side = int(H * 1.35)
    return im.resize((side, side), Image.LANCZOS)


def end_card(last_bg):
    """the heroes together over the blurred last shot, the title and FAST 5V5 MOBA BATTLES"""
    img = last_bg.convert("RGBA")
    art = {n: Image.open(os.path.join(ART, "store_%s_wide.webp" % n)).convert("RGBA") for n, *_ in END_HEROES}
    art["dragoon"] = art["dragoon"].transpose(Image.FLIP_LEFT_RIGHT)
    k = S5.hero_scale((W, H), END_HEROES, True, W)
    img.alpha_composite(S5.hero_layer((W, H), art, END_HEROES, True, k))
    lg = S5.logo_img()
    lw = int(W * 0.5)
    lg = lg.resize((lw, int(lg.height * lw / lg.width)), Image.LANCZOS)
    at = ((W - lw) // 2, int(H * 0.5))
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 255), at, lg.getchannel("A").point(lambda v: int(v * 0.7)))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(H * 0.02)))
    img.alpha_composite(lg, at)
    txt = S5.text_layer((W, H), ("", "FAST 5V5 MOBA BATTLES"), 0, int(H * 0.965), H * 0.62, W)
    bb = txt.getbbox()
    if bb:
        tw = bb[2] - bb[0]
        moved = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        moved.alpha_composite(txt.crop(bb), ((W - tw) // 2, bb[1]))
        img.alpha_composite(moved)
    return img


def picture(rec, out, preview):
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H),
                            "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "veryfast" if preview else "slow",
                            "-crf", "24" if preview else "16", "-pix_fmt", "yuv420p", out], stdin=subprocess.PIPE)
    total = 0
    last_bg = last_frame = None
    for (run, a, b, lines, hero, glow) in SHOTS:
        arr, n = frames(rec, run, a, b)
        card, pad, mask = card_frame(glow)
        him = hero_img(hero)
        side = him.width
        hx, hy = int((CARD_X + CARD_W + W) / 2 + H * 0.02), int(H * 1.05 - side * 0.3)   # its middle: right of the card, feet just off the bottom
        cap = S5.text_layer((W, H), lines, int(H * 0.05), int(H * 0.9), H * 0.72, CARD_X - H * 0.08)
        for i in range(n):
            t = i / FPS
            fr = arr[min(i, len(arr) - 1)]
            bg = blurred(fr).convert("RGBA")
            # the hero slides in from the right, the headline from the left, as the shot starts
            e = ease(t / 0.35)
            bg.alpha_composite(him, (int(hx - side / 2 + (1.0 - e) * W * 0.25), int(hy - side / 2)))
            bg.alpha_composite(card, (CARD_X - pad, CARD_Y - pad))
            scr = Image.fromarray(fr).resize((CARD_W, CARD_H), Image.LANCZOS)
            bg.paste(scr, (CARD_X, CARD_Y), mask)
            c = ease((t - 0.05) / 0.3)
            if c > 0:
                capf = cap if c >= 1 else Image.fromarray((np.asarray(cap) * np.array([1, 1, 1, c])).astype(np.uint8))
                bg.alpha_composite(capf, (int(-(1.0 - c) * W * 0.12), 0))
            last_frame = bg.convert("RGB")
            enc.stdin.write(last_frame.tobytes())
            last_bg = blurred(fr)
        total += n
        print("promo: %s %d frames" % (run, n), flush=True)
    end = end_card(last_bg)
    ne = int(END_S * FPS)
    for i in range(ne):
        t = i / FPS
        f = ease(t / 0.4)
        frame = Image.blend(last_frame, end.convert("RGB"), f)        # (from the last shot as it was, card and all)
        enc.stdin.write(frame.tobytes())
    total += ne
    enc.stdin.close()
    enc.wait()
    return total / FPS


def sound(rec, out, total):
    n = int((total + 1.0) * SR)
    game = np.zeros((n, 2), np.float32)
    at = 0.0
    for (run, a, b, *_rest) in SHOTS:
        tmp = os.path.join(rec, ".promo_%s.wav" % run)
        ff(["-ss", "%.4f" % avi_t(rec, run, a), "-t", "%.4f" % (b - a), "-i", os.path.join(rec, run + ".avi"), "-vn",
            "-ac", "2", "-ar", str(SR), "-c:a", "pcm_f32le", tmp])
        x = T8.load(tmp)
        os.remove(tmp)
        x = x[:int(round((b - a) * FPS)) * SR // FPS]
        if np.abs(x).max() > 1e-4:
            lv = T8.lufs(x)
            if np.isfinite(lv) and lv > -70:
                x = x * (10.0 ** ((GAME_LUFS - lv) / 20.0))
        T8.place(game, T8.fade(x, 0.006, 0.02), at)
        at += int(round((b - a) * FPS)) / FPS
    th = T8.load(MUSIC)
    th = np.concatenate([th, th])[:int(total * SR)]
    music = T8.fade(th, 0.05, 1.6) * (10.0 ** (MUSIC_GAIN / 20.0))
    mix = game.copy()
    mix[:len(music)] += music
    mix = mix[:int(total * SR)]
    lv = T8.lufs(mix)
    mix *= 10.0 ** ((TARGET_LUFS - lv) / 20.0)
    peak = np.abs(mix).max()
    if peak > 0.89:                                     # (a soft knee over -1 dB: no clipping)
        over = np.abs(mix) > 0.7
        mix[over] = np.sign(mix[over]) * (0.7 + 0.19 * np.tanh((np.abs(mix[over]) - 0.7) / 0.19))
    T8.write_wav(out, mix)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rec", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--preview", action="store_true")
    a = ap.parse_args()
    work = os.path.splitext(a.out)[0] + "_work"
    os.makedirs(work, exist_ok=True)
    pic = os.path.join(work, "picture.mp4")
    total = picture(a.rec, pic, a.preview)
    wav = os.path.join(work, "sound.wav")
    sound(a.rec, wav, total)
    ff(["-i", pic, "-i", wav, "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart",
        a.out])
    print("promo: %s (%.1f s)" % (a.out, total))


if __name__ == "__main__":
    main()
