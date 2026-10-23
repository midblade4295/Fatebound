#!/usr/bin/env python3
"""TikTok 1, "The King's snack" (Kevin: "I want a short CGI video that will make people on tiktok want to watch right off
the bat. Something that could get a lot of views on tiktok" -- the King's snack, about 15 s).

A vertical 9:16 short that opens on action and loops: the King, mid-bite -- BOOM, the throne hall's doors blow in -- the
five heroes charge at him (his point of view) -- frozen, his crown slides off, GULP, he offers them the turkey leg -- the
game's title slams in -- and back to him biting. The shots are AI video (ElevenLabs flow "Fatebound TikTok 1 (King's
snack)", Veo 3.1 Fast, 9:16, each from a keyframe made from trailer 9's King and heroes; tools/tiktok1_script.md); they
bring their own sound effects. The caption ("POV: you're the boss in a 5v5") sits in TikTok's safe area from the first
frame; --clean leaves it off (for TikTok's own text).

    python3 tools/tiktok1_edit.py --shots <dir of v1.mp4 v2.mp4 v3.mp4> --out <mp4> [--clean] [--preview]

1080 x 1920 at 30 fps (--preview: 540 x 960), -14 LUFS. Needs numpy, Pillow, ffmpeg; trailer8_edit.py (sound helpers).
"""
import argparse
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import trailer8_edit as T8      # noqa: E402

FPS = 30
SR = T8.SR
RAW8 = os.path.join(HERE, "trailer8_vo", "raw")
SOUNDS = os.path.join(GODOT, "assets", "sounds")
NUNITO = os.path.join(GODOT, "store-listing", "tools", "fonts", "Nunito-ExtraBold.ttf")
V2 = os.path.join(GODOT, "assets", "ui", "v2")

# ---------- the cut: (shot, its first second used, its last, its speed) ----------
CUTS = [
    ("v1", 0.0, 3.4, 1.0),      # the King bites -- BOOM (1.27 s in) -- he freezes
    ("v2", 0.0, 3.75, 1.25),    # his view: the five charge through the broken doors at him (quickened: a charge)
    ("v3", 0.0, 5.75, 1.0),     # caught: the crown falls (0.7 s), GULP (1.5 s), a nervous beat, he offers them the turkey leg (4.2 s)
]
END_T = 1.9                 # the title card
SLAM_IN = 0.16              # the logo lands this long into the card (the slam)
CAPTION = ["POV: you're the boss", "in a 5v5"]
CAPTION_T = None            # on from the first frame through every shot (None), or until this second of the cut
TAGLINE = "5V5 HERO BATTLES"
NOTE = "Not actual gameplay footage"
SHOT_LUFS = -20.0
SHOT_GAIN = {"v1": 2.0, "v2": 0.0, "v3": 3.0}
CUE_B_SWELL, CUE_B_HIT = 3.25, 3.9   # trailer 8's cue B: its swell into its hit (seconds of musB_1)


def ff(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + args, check=True)


def timeline():
    # -> [(shot, from, to, where it starts in the cut, speed, its frames)], the cut's length -- each shot a whole number of
    # frames, so the picture and the sound line up to the frame all the way to the title's slam
    t, out = 0.0, []
    for v, a, b, sp in CUTS:
        n = int(round((b - a) / sp * FPS))
        out.append((v, a, b, t, sp, n))
        t += n / FPS
    return out, t


def font(size):
    return ImageFont.truetype(NUNITO, size)


def caption_png(W, H, path):
    # TikTok's look: big white words with a black outline, centred, high in the frame (clear of the app's tabs above and
    # its buttons and caption below)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    f = font(int(W * 0.068))
    y = int(H * 0.15)
    for line in CAPTION:
        w = d.textlength(line, font=f)
        d.text(((W - w) / 2, y), line, font=f, fill=(255, 255, 255, 255), stroke_width=max(3, W // 160),
               stroke_fill=(0, 0, 0, 255))
        y += int(f.size * 1.22)
    im.save(path)


def logo():
    # the game's title: the word, crown and rift (title_rift_base) with its two flags behind (title_logo.gd's places)
    base = Image.open(os.path.join(V2, "title_rift_base.webp")).convert("RGBA")
    out = Image.new("RGBA", base.size, (0, 0, 0, 0))
    for name, at in (("title_flag_l.webp", (0, 153)), ("title_flag_r.webp", (1233, 153))):
        fl = Image.open(os.path.join(V2, name)).convert("RGBA")
        out.alpha_composite(fl, at)
    out.alpha_composite(base)
    return out


def end_card(last_frame, W, H, work, preview):
    """the title card: the King's last frame blurred and darkened, the logo slamming in (a flash, a shake), the tagline,
    the note"""
    bg = Image.open(last_frame).convert("RGB").resize((W, H), Image.LANCZOS)
    bg = bg.filter(ImageFilter.GaussianBlur(W / 60))
    bg = Image.blend(bg, Image.new("RGB", (W, H), (8, 6, 14)), 0.55)
    lg = logo()
    lw = int(W * 0.9)
    lg = lg.resize((lw, int(lg.height * lw / lg.width)), Image.LANCZOS)
    f_tag = font(int(W * 0.06))
    f_note = font(int(W * 0.026))
    n = int(round(END_T * FPS))
    path = os.path.join(work, "seg_end.mp4")
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H),
                            "-r", str(FPS), "-i", "-", "-vf", "format=yuv420p", "-c:v", "libx264", "-preset",
                            "veryfast" if preview else "slow", "-crf", "20" if preview else "14", path], stdin=subprocess.PIPE)
    cy = int(H * 0.40)
    for i in range(n):
        t = i / FPS
        fr = bg.copy().convert("RGBA")
        # the logo: from 1.7x down to 1x by the slam (easing in), a small overshoot, then still
        if t < SLAM_IN:
            k = t / SLAM_IN
            s = 1.7 - 0.7 * (k * k)
            a = min(1.0, k * 2.0)
        else:
            u = t - SLAM_IN
            s = 1.0 + 0.04 * np.exp(-u * 18.0) * np.cos(u * 40.0)
            a = 1.0
        lw2 = max(2, int(lg.width * s))
        lh2 = max(2, int(lg.height * s))
        l2 = lg.resize((lw2, lh2), Image.BILINEAR)
        if a < 1.0:
            l2.putalpha(l2.getchannel("A").point(lambda p, a=a: int(p * a)))
        shake = 0
        if SLAM_IN <= t < SLAM_IN + 0.25:
            shake = int(W * 0.012 * (1.0 - (t - SLAM_IN) / 0.25) * (1 if i % 2 else -1))
        fr.alpha_composite(l2, ((W - lw2) // 2 + shake, cy - lh2 // 2))
        d = ImageDraw.Draw(fr)
        # the tagline, fading up after the slam; the note at the foot
        ta = max(0.0, min(1.0, (t - SLAM_IN - 0.25) / 0.25))
        if ta > 0:
            w = d.textlength(TAGLINE, font=f_tag)
            d.text(((W - w) / 2, cy + lg.height // 2 + int(H * 0.025)), TAGLINE, font=f_tag,
                   fill=(255, 236, 196, int(255 * ta)), stroke_width=max(2, W // 270), stroke_fill=(30, 12, 4, int(255 * ta)))
            w = d.textlength(NOTE, font=f_note)
            d.text(((W - w) / 2, cy + lg.height // 2 + int(H * 0.085)), NOTE, font=f_note, fill=(255, 255, 255, int(140 * ta)))
        # the flash on the slam
        if SLAM_IN <= t < SLAM_IN + 0.12:
            fl = 1.0 - (t - SLAM_IN) / 0.12
            fr = Image.blend(fr, Image.new("RGBA", (W, H), (255, 244, 220, 255)), 0.55 * fl)
        enc.stdin.write(fr.convert("RGB").tobytes())
    enc.stdin.close()
    enc.wait()
    return path


def picture(shots, work, W, H, preview, clean):
    segs = []
    tl, end = timeline()
    cap = os.path.join(work, "caption.png")
    caption_png(W, H, cap)
    for i, (v, a, b, at, sp, nf) in enumerate(tl):
        seg = os.path.join(work, "seg%02d.mp4" % i)
        src = os.path.join(shots, v + ".mp4")
        vf = "setpts=PTS/%.4f,scale=%d:%d:flags=lanczos%s,fps=%d,format=yuv420p" % (sp, W, H, "" if preview else ",unsharp=5:5:0.5:5:5:0.0", FPS)
        args = ["-ss", "%.3f" % a, "-t", "%.3f" % (b - a), "-i", src]
        if not clean and (CAPTION_T is None or at < CAPTION_T):
            # the caption over the shots (to CAPTION_T, however the cut falls; the title card has none)
            until = 1e6 if CAPTION_T is None else CAPTION_T - at
            args += ["-i", cap, "-filter_complex",
                     "[0:v]%s[v];[1:v]format=rgba[c];[v][c]overlay=0:0:enable='lt(t,%.3f)',format=yuv420p" % (vf, until)]
        else:
            args += ["-vf", vf]
        ff(args + ["-frames:v", str(nf), "-an", "-c:v", "libx264", "-preset", "veryfast" if preview else "slow", "-crf", "20" if preview else "14", seg])
        segs.append(seg)
    # the title card from the King's last frame
    v, a, b, at, sp, nf = tl[-1]
    last = os.path.join(work, "last.png")
    ff(["-ss", "%.3f" % (a + (nf - 1) / FPS * sp), "-i", os.path.join(shots, v + ".mp4"), "-frames:v", "1", last])
    segs.append(end_card(last, W, H, work, preview))
    lst = os.path.join(work, "segs.txt")
    open(lst, "w").write("".join("file '%s'\n" % s for s in segs))
    out = os.path.join(work, "picture.mp4")
    ff(["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", out])
    return out, end + END_T


def shot_audio(path, a, b, sp=1.0):
    tmp = path + ".wav"
    ff(["-ss", "%.3f" % a, "-t", "%.3f" % (b - a), "-i", path, "-vn", "-ac", "2", "-ar", str(SR)]
       + (["-af", "atempo=%.4f" % sp] if sp != 1.0 else []) + ["-c:a", "pcm_f32le", tmp])
    x = T8.load(tmp)
    os.remove(tmp)
    return x


def sound(shots, out, total):
    n = int(total * SR) + SR
    fx = np.zeros((n, 2), np.float32)
    mus = np.zeros((n, 2), np.float32)
    tl, end = timeline()
    for (v, a, b, at, sp, nf) in tl:
        x = shot_audio(os.path.join(shots, v + ".mp4"), a, b, sp)
        lv = T8.lufs(x) if np.abs(x).max() > 1e-4 else SHOT_LUFS
        g = SHOT_LUFS - lv if np.isfinite(lv) else 0.0
        T8.place(fx, T8.fade(x * (10.0 ** (g / 20.0)), 0.01, 0.04), at, SHOT_GAIN.get(v, 0.0))
    # the title: trailer 8's cue B swelling under the offered turkey leg, its hit on the slam; the game's title slam
    slam = end + SLAM_IN
    cue_b = T8.load(os.path.join(RAW8, "musB_1.mp3"))
    T8.place(mus, T8.fade(cue_b[int(CUE_B_SWELL * SR):int((CUE_B_HIT + END_T) * SR)], 0.05, 0.4),
             slam - (CUE_B_HIT - CUE_B_SWELL), 0.0)
    T8.place(fx, T8.load(os.path.join(SOUNDS, "titleSlam.wav")), slam - 0.02, -2.0)
    mix = mus * 0.9 + fx
    endi = int(total * SR)
    mix = mix[:endi]
    tmp = out + ".mix.wav"
    T8.write_wav(tmp, mix * (10.0 ** ((-14.0 - T8.lufs(mix)) / 20.0)))
    ff(["-i", tmp, "-af", "alimiter=limit=0.85:attack=3:release=50:level=false", "-ar", str(SR), "-c:a", "pcm_f32le",
        out + ".lim.wav"])
    ff(["-i", out + ".lim.wav", "-c:a", "aac", "-b:a", "256k", out])
    print("mix: %.1f LUFS after the limiter" % T8.lufs(T8.load(out + ".lim.wav")))
    os.remove(tmp)
    os.remove(out + ".lim.wav")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--clean", action="store_true")
    ap.add_argument("--preview", action="store_true")
    a = ap.parse_args()
    work = a.out + ".work"
    os.makedirs(work, exist_ok=True)
    W, H = (540, 960) if a.preview else (1080, 1920)
    pic, total = picture(a.shots, work, W, H, a.preview, a.clean)
    aud = os.path.join(work, "sound.m4a")
    sound(a.shots, aud, total)
    ff(["-i", pic, "-i", aud, "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "copy", "-movflags", "+faststart", a.out])
    print("cut", a.out, "%.2f s" % total)


if __name__ == "__main__":
    main()
