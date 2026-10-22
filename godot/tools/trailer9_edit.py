#!/usr/bin/env python3
"""Trailer 9, the CGI trailer: the cut and the mix (Kevin: "I love the quality. Do it except don't have any voice lines. I
want the trailer to tell the story like how world of Warcraft trailers are" / "Just have music and sound effects").

The shots are AI video (ElevenLabs flow "Fatebound trailer 9 (CGI)", Veo 3.1 Fast, 1280 x 720 at 24 fps, each started
from a cinematic keyframe made from the game's own pictures; tools/trailer9_script.md has the story and the prompts).
They come with their own sound effects; the score is four cues made for this cut (score()) and the title is the game's own --
trailer 8's title run (its recording) from the moment its logo flies in, straight after the King's gulp, with trailer 8's
cue B swelling into the slam.

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

# ---------- the cut: (shot, its first second used, its last[, a punch-in: (zoom, x, y)]), one after another ----------
# (Kevin's rework: "The wizard shouldn't be holding a shield. The archer is walking with a bow that knocked. The barbarian
# spawns a sword when fighting knight and knight does weird animation during scene. The knight and barbarian should be
# looking towards the green glow instead of away. When barbarian blows horn the smoke doesn't come out of horn." / "Also
# the end scene with king needs a better flow along with game title coming in". v04, v07, v10, v12, v12b and v13 are the
# re-shot ones; trailer9_script.md has which takes.)
CUTS = [
    ("v01", 0.0, 7.0),      # dawn over the Rift (fading up from black)
    ("v02", 0.0, 5.5),      # their King on his throne, eating
    ("v03", 0.0, 5.8),      # Aldric's cracked shield; he looks across at their castle
    ("v04", 0.9, 4.0),      # Hroth's war horn, the mist from its bell (its blast 0.5 s in) -- the drums
    ("v05", 0.0, 5.0),      # our five charge out of the gate
    ("v06", 0.0, 1.9),      # their five charge through the river (before the golem loses his shape)
    ("v07", 0.0, 3.8),      # the knight and the berserker, blades locked (a close-up)
    ("v08", 0.0, 2.6),      # Elara's ring of fire throws the assassin (before he loses his shape in the smoke)
    ("v09", 0.0, 3.2),      # Gorrak's landslide, Hroth diving clear
    ("v10", 1.0, 4.0),      # the ground shakes; they turn to the green light on the hills -- the music drops away
    ("v11", 0.0, 8.0),      # the Grave Wyrm rises and roars (6.0 s in) -- the climax
    ("v12", 0.0, 1.45),     # Aldric holds its soul-fire back with his cracked shield, the Priest's light round him...
    ("v12b", 0.0, 2.8),     # ...and stands, sword raised, the fire spent, Elara and the Priest beside him
    ("v13", 0.6, 5.6),      # their throne hall's doors burst in; our five walk through
    ("v14", 0.0, 2.4),      # the King, mid-bite, sees them -- the music stops dead
    ("v14", 4.0, 5.75, (1.25, 0.6, 0.15)),   # closer: his crown pops off; the gulp (5.1 s in); the swell starts
]
# then straight into the title (no black): trailer 8's title run from the moment the FATEBOUND logo appears, flying in,
# the slam 0.33 s after the cut; trailer 8's cue B swells under the King's stare and hits on the slam
TITLE_RUN = (2.70, 8.45)     # these seconds of trailer 8's title run (the logo appears at 2.70, slams at 3.033)
TITLE_B = 3.033
CUE_B_SWELL, CUE_B_HIT = 3.25, 3.9   # cue B's swell into its hit (seconds of musB_1)
FADE_IN = 1.2
FADE_OUT = 1.0
NOTE = "Not actual gameplay footage"

# each shot's own sound: its level (dB, after levelling to SHOT_LUFS)
SHOT_GAIN = {"v01": -4.0, "v02": 2.0, "v03": -2.0, "v04": 2.0, "v05": 1.0, "v06": 1.0, "v07": 2.0, "v08": 2.0,
             "v09": 2.0, "v10": 1.0, "v11": 3.0, "v12": 0.0, "v12b": -1.0, "v13": 1.0, "v14": 4.0}
SHOT_LUFS = -24.0

# ---------- the score (tools/trailer9_vo/raw, ElevenLabs Music v2.5, on the flow): (cue, from, to, trailer time, gain dB,
# fade in, fade out). The dawn cue swells under the knight; the battle cue starts on the war horn's blast; the dark cue's
# hit (10.2 s in) lands on the Wyrm's roar; the heroic cue carries the stand and the breach and stops dead when the
# King sees them. Times are filled in by score() from the cut. ----------
HORN_IN_V04 = 0.5
ROAR_IN_V11 = 6.0
M3_HIT = 10.2
STOP_IN_V14 = 0.3


def timeline():
    t, out = 0.0, []
    for c in CUTS:
        v, a, b = c[:3]
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
        if len(CUTS[i]) > 3:                                    # a punch-in: (zoom, where across, where down)
            z, cx, cy = CUTS[i][3]
            vf = "crop=iw/%.3f:ih/%.3f:(iw-iw/%.3f)*%.3f:(ih-ih/%.3f)*%.3f," % (z, z, z, cx, z, cy) + vf
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
    return out, end + (t1 - t0)


def at_of(v, k=0):
    tl, _ = timeline()
    return [at for (s, a, b, at) in tl if s == v][k]


def score():
    horn = at_of("v04") + HORN_IN_V04
    calm = at_of("v10")
    roar = at_of("v11") + ROAR_IN_V11
    hero = at_of("v12")
    stop = at_of("v14") + STOP_IN_V14
    # the dark cue starts under the shaking ground (its first seconds are a quiet build; it is cut so its hit still lands
    # on the roar however short the shaking is)
    m3_at = roar - M3_HIT
    m3_a = max(0.0, calm + 0.2 - m3_at)
    # (levels: the music leads; the battle's blows and the Wyrm's roar stay on top of it; measured with T9_STEMS)
    return [("m1_b", 0.0, horn - 0.0, 0.0, 5.0, 0.5, 0.35),
            ("m2_b", 0.0, calm - horn + 0.4, horn - 0.05, -6.0, 0.05, 0.6),
            ("m3_b", m3_a, hero - m3_at + 1.0, m3_at + m3_a, 2.0, 0.6 if m3_a > 0 else 0.3, 1.0),
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
    # the title: trailer 8's cue B from its swell -- rising under the King's stare, its hit on the logo's slam -- and the
    # game's own title slam
    title_at = end
    b_at = title_at + (TITLE_B - TITLE_RUN[0])
    mus = np.zeros((n, 2), np.float32)
    cue_b = T8.load(os.path.join(RAW8, "musB_1.mp3"))
    T8.place(mus, T8.fade(cue_b[int(CUE_B_SWELL * SR):int(9.5 * SR)], 0.1, 1.5), b_at - (CUE_B_HIT - CUE_B_SWELL), -0.5)
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
    print("cut", a.out, "%.2f s" % total, "; the title at %.2f, its slam at %.2f" % (end, end + TITLE_B - TITLE_RUN[0]))


if __name__ == "__main__":
    main()
