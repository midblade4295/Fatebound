#!/usr/bin/env python3
"""Trailer 9, the CGI trailer: the cut and the mix (Kevin: "I love the quality. Do it except don't have any voice lines. I
want the trailer to tell the story like how world of Warcraft trailers are" / "Just have music and sound effects").

The shots are AI video (ElevenLabs flow "Fatebound trailer 9 (CGI)", Veo 3.1 Fast, 1280 x 720 at 24 fps, each started
from a cinematic keyframe made from the game's own pictures; tools/trailer9_script.md has the story and the prompts).
They come with their own sound effects; the score is four cues made for this cut (score()) and the title is the game's own --
trailer 8's title run (its recording), with trailer 8's cue B under it, cut the same way.

    python3 tools/trailer9_edit.py --shots <dir of vNN.mp4> --rec <trailer 8 recordings> --out <mp4> [--preview]

--preview: missing shots are a card saying which; 1280 x 720, quick. Otherwise 1920 x 1080, 24 fps.
Needs numpy, Pillow, ffmpeg; trailer8_edit.py (loading, placing and fading sound, loudness, the title's grade).
"""
import argparse
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import trailer8_edit as T8      # noqa: E402

FPS = 24
SR = T8.SR
RAW8 = os.path.join(HERE, "trailer8_vo", "raw")
RAW9 = os.path.join(HERE, "trailer9_vo", "raw")
SOUNDS = os.path.join(GODOT, "assets", "sounds")
NUNITO = os.path.join(GODOT, "store-listing", "tools", "fonts", "Nunito-ExtraBold.ttf")

# ---------- the cut: (shot, its first second used, its last), one after another ----------
CUTS = [
    ("v01", 0.0, 7.0),      # dawn over the Rift (fading up from black)
    ("v02", 0.0, 5.5),      # their King on his throne, eating
    ("v03", 0.0, 5.8),      # Aldric's cracked shield; he looks across at their castle
    ("v04", 0.0, 3.6),      # Hroth's war horn (its blast 0.4 s in) -- the drums
    ("v05", 0.0, 5.0),      # our five charge out of the gate
    ("v06", 0.0, 1.9),      # their five charge through the river (before the golem loses his shape)
    ("v07", 0.0, 4.5),      # the knight and the berserker, blade to blade
    ("v08", 0.0, 2.6),      # Elara's ring of fire throws the assassin (before he loses his shape in the smoke)
    ("v09", 0.0, 3.2),      # Gorrak's landslide, Hroth diving clear
    ("v10", 0.0, 5.5),      # the ground shakes; green light from the hills -- the music drops away
    ("v11", 0.0, 8.0),      # the Grave Wyrm rises and roars (6.0 s in) -- the climax
    ("v12", 0.0, 3.0),      # Aldric holds its soul-fire back with his cracked shield, the Priest's light round him...
    ("v12", 6.2, 8.0),      # ...and stands, shield raised, the fire spent
    ("v13", 0.0, 5.0),      # their throne hall's doors burst in; our five walk through
    ("v14", 0.0, 5.6),      # the King, mid-bite -- the music stops; his crown slides; the gulp (5.1 s in)
]
BLACK = 0.5                  # then black, silent
TITLE_RUN = (0.85, 8.45)     # trailer 8's title run, these seconds of it: the lightning at 1.033, the slam at 3.033
TITLE_A, TITLE_B = 1.033, 3.033
FADE_IN = 1.2
FADE_OUT = 1.0
NOTE = "Not actual gameplay footage"

# each shot's own sound: its level (dB, after levelling to SHOT_LUFS)
SHOT_GAIN = {"v01": -4.0, "v02": 2.0, "v03": -2.0, "v04": 2.0, "v05": 1.0, "v06": 1.0, "v07": 2.0, "v08": 2.0,
             "v09": 2.0, "v10": 1.0, "v11": 3.0, "v12": 0.0, "v13": 1.0, "v14": 4.0}
SHOT_LUFS = -24.0

# ---------- the score (tools/trailer9_vo/raw, ElevenLabs Music v2.5, on the flow): (cue, from, to, trailer time, gain dB,
# fade in, fade out). The dawn cue swells under the knight; the battle cue starts on the war horn's blast; the dark cue's
# hit (10.2 s in) lands on the Wyrm's roar; the heroic cue carries the stand and the breach and stops dead when the
# King sees them. Times are filled in by score() from the cut. ----------
HORN_IN_V04 = 0.4
ROAR_IN_V11 = 6.0
M3_HIT = 10.2
STOP_IN_V14 = 0.3


def timeline():
    t, out = 0.0, []
    for (v, a, b) in CUTS:
        out.append((v, a, b, t))
        t += b - a
    return out, t


def card(text, size, path):
    im = Image.new("RGB", size, (12, 14, 22))
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(NUNITO, size[1] // 14)
    w = d.textlength(text, font=f)
    d.text(((size[0] - w) / 2, size[1] / 2 - size[1] // 28), text, font=f, fill=(200, 200, 210))
    im.save(path)


def ff(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + args, check=True)


def picture(shots, rec, work, size, preview):
    W, H = size
    segs = []
    tl, end = timeline()
    for i, (v, a, b, at) in enumerate(tl):
        seg = os.path.join(work, "seg%02d.mp4" % i)          # (a shot may be used twice)
        src = os.path.join(shots, v + ".mp4")
        dur = b - a
        vf = "scale=%d:%d:flags=lanczos,fps=%d,format=yuv420p" % (W, H, FPS)
        if not preview:
            vf = "scale=%d:%d:flags=lanczos,unsharp=5:5:0.45:5:5:0.0,fps=%d,format=yuv420p" % (W, H, FPS)
        if i == 0:
            vf += ",fade=t=in:st=0:d=%.2f" % FADE_IN
        if os.path.exists(src):
            ff(["-ss", "%.3f" % a, "-t", "%.3f" % dur, "-i", src, "-an", "-vf", vf, "-c:v", "libx264", "-preset",
                "veryfast" if preview else "slow", "-crf", "20" if preview else "14", seg])
        else:
            png = os.path.join(work, "card%02d.png" % i)
            card("%s  (not made yet)" % v, (W, H), png)
            ff(["-loop", "1", "-t", "%.3f" % dur, "-i", png, "-vf", "fps=%d,format=yuv420p" % FPS, "-c:v", "libx264",
                "-preset", "veryfast", "-crf", "20", seg])
        segs.append(seg)
    # black
    seg = os.path.join(work, "seg_black.mp4")
    ff(["-f", "lavfi", "-t", "%.3f" % BLACK, "-i", "color=c=black:s=%dx%d:r=%d" % (W, H, FPS), "-vf", "format=yuv420p",
        "-c:v", "libx264", "-crf", "20", seg])
    segs.append(seg)
    # the title: trailer 8's title run, graded like trailer 8 but full frame, the note at its foot, fading out
    t0, t1 = TITLE_RUN
    n = int(round((t1 - t0) * T8.FPS))
    vig = T8.vignette()
    seg = os.path.join(work, "seg_title.mp4")
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (T8.W, T8.H),
                            "-r", str(T8.FPS), "-i", "-", "-vf",
                            "scale=%d:%d:flags=lanczos,fps=%d,drawtext=fontfile=%s:text='%s':x=(w-tw)/2:y=h-th-%d:"
                            "fontsize=%d:fontcolor=white@0.55,fade=t=out:st=%.2f:d=%.2f,format=yuv420p"
                            % (W, H, FPS, NUNITO, NOTE, H // 24, H // 40, (t1 - t0) - FADE_OUT, FADE_OUT),
                            "-c:v", "libx264", "-preset", "veryfast" if preview else "slow", "-crf", "20" if preview else "14",
                            seg], stdin=subprocess.PIPE)
    last = None
    for fr in T8.frames_of(os.path.join(rec, "title.avi"), T8.avi_frame(rec, "title", t0), n):
        fr = last if fr is None else fr
        last = fr
        f = T8.grade(fr.astype(np.float32) / 255.0, vig)
        enc.stdin.write((f * 255.0 + 0.5).astype(np.uint8).tobytes())
    enc.stdin.close()
    enc.wait()
    segs.append(seg)
    lst = os.path.join(work, "segs.txt")
    open(lst, "w").write("".join("file '%s'\n" % s for s in segs))
    out = os.path.join(work, "picture.mp4")
    ff(["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", out])
    return out, end + BLACK + (t1 - t0)


def at_of(v, k=0):
    tl, _ = timeline()
    return [at for (s, a, b, at) in tl if s == v][k]


def score():
    horn = at_of("v04") + HORN_IN_V04
    calm = at_of("v10")
    roar = at_of("v11") + ROAR_IN_V11
    hero = at_of("v12")
    stop = at_of("v14") + STOP_IN_V14
    # (levels: the music leads; the battle's blows and the Wyrm's roar stay on top of it; measured with T9_STEMS)
    return [("m1_b", 0.0, horn - 0.0, 0.0, 5.0, 0.5, 0.35),
            ("m2_b", 0.0, calm - horn + 0.4, horn - 0.05, -6.0, 0.05, 0.6),
            ("m3_b", 0.0, hero - (roar - M3_HIT) + 1.0, roar - M3_HIT, 2.0, 0.3, 1.0),
            ("m4_b", 0.0, stop - hero - 0.3, hero + 0.3, -5.0, 0.8, 0.03)]


def shot_audio(path, a, b):
    tmp = path + ".wav"
    ff(["-ss", "%.3f" % a, "-t", "%.3f" % (b - a), "-i", path, "-vn", "-ac", "2", "-ar", str(SR), "-c:a", "pcm_f32le", tmp])
    x = T8.load(tmp)
    os.remove(tmp)
    return x


def sound(shots, out, total):
    n = int(total * SR) + SR
    fx = np.zeros((n, 2), np.float32)
    tl, end = timeline()
    for (v, a, b, at) in tl:
        src = os.path.join(shots, v + ".mp4")
        if not os.path.exists(src):
            continue
        x = shot_audio(src, a, b)
        lv = T8.lufs(x) if np.abs(x).max() > 1e-4 else SHOT_LUFS
        g = SHOT_LUFS - lv if np.isfinite(lv) else 0.0
        x = T8.fade(x * (10.0 ** (g / 20.0)), 0.02, 0.06)
        T8.place(fx, x, at, SHOT_GAIN.get(v, 0.0))
    # the title: trailer 8's cue B cut as it was (its first hit on the lightning, the swell into the slam), the lightning
    # and the game's own title slam
    title_at = end + BLACK
    a_at = title_at + (TITLE_A - TITLE_RUN[0])
    b_at = title_at + (TITLE_B - TITLE_RUN[0])
    mus = np.zeros((n, 2), np.float32)
    cue_b = T8.load(os.path.join(RAW8, "musB_1.mp3"))
    xf = 0.12
    T8.place(mus, T8.fade(cue_b[0:int((1.10 + xf / 2) * SR)], 0.0, xf), a_at, -0.5)
    T8.place(mus, T8.fade(cue_b[int((3.0 - xf / 2) * SR):int(9.5 * SR)], xf, 1.5), a_at + 1.10 - xf / 2, -0.5)
    T8.place(fx, T8.fade(T8.load(os.path.join(RAW8, "bolt_2.mp3")), 0.0, 1.0), a_at - 0.02, -3.0)
    T8.place(fx, T8.load(os.path.join(SOUNDS, "titleSlam.wav")), b_at - 0.02, -4.0)
    # the Grave Wyrm's roar: trailer 8's under the shot's own
    if os.path.exists(os.path.join(shots, "v11.mp4")):
        v11_at = [at for (v, a, b, at) in tl if v == "v11"][0]
        T8.place(fx, T8.fade(T8.load(os.path.join(RAW8, "roar_1.mp3"), 0.9), 0.01, 0.8), v11_at + ROAR_IN_V11 - 0.1, -9.0)
    for (cue, a, b, at, g, fi, fo) in score():
        x = T8.load(os.path.join(RAW9, cue + ".mp3"))
        x = x[int(a * SR):int(b * SR)]
        T8.place(mus, T8.fade(x, fi, fo), at, g)
    if os.environ.get("T9_STEMS"):
        T8.write_wav(out + ".music.wav", mus[:int(total * SR)])
        T8.write_wav(out + ".fx.wav", fx[:int(total * SR)])
    mix = mus * 0.95 + fx
    endi = int(total * SR)
    tail = int(FADE_OUT * SR)
    mix[endi - tail:endi] *= np.linspace(1, 0, tail)[:, None]
    mix = mix[:endi]
    tmp = out + ".mix.wav"
    T8.write_wav(tmp, mix * (10.0 ** ((-14.0 - T8.lufs(mix)) / 20.0)))
    ff(["-i", tmp, "-af", "alimiter=limit=0.82:attack=4:release=60:level=false", "-ar", str(SR), "-c:a", "pcm_f32le",
        out + ".lim.wav"])
    ff(["-i", out + ".lim.wav", "-c:a", "aac", "-b:a", "256k", out])
    print("mix: %.1f LUFS after the limiter" % T8.lufs(T8.load(out + ".lim.wav")))
    os.remove(tmp)
    os.remove(out + ".lim.wav")



def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", required=True)
    ap.add_argument("--rec", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--preview", action="store_true")
    a = ap.parse_args()
    work = a.out + ".work"
    os.makedirs(work, exist_ok=True)
    size = (1280, 720) if a.preview else (1920, 1080)
    pic, total = picture(a.shots, a.rec, work, size, a.preview)
    aud = os.path.join(work, "sound.m4a")
    sound(a.shots, aud, total)
    ff(["-i", pic, "-i", aud, "-c:v", "copy", "-c:a", "copy", "-shortest", "-movflags", "+faststart", a.out])
    tl, end = timeline()
    print("cut", a.out, "%.2f s" % total, "; shots end %.2f, the title at %.2f" % (end, end + BLACK))


if __name__ == "__main__":
    main()
