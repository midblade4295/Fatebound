#!/usr/bin/env python3
"""The title screen's art and sound (0.31.139, Kevin: "remove the fatebound title and instead put that in a startup
screen and any loading screens. Give the starting title screen a little jingle tune and have title animate in there
like slamming onto the wall or something" ... "Change play button and tutorial button design").

Sources (ElevenLabs, flow "Fatebound title screen"), in art_sources/title_screen/:
  wall.png                 the castle wall the title slams onto (gpt-image-2.5-sunburst, the war room as style)
  play_plaque_green.png    the PLAY plaque on flat green (gpt-image-2): the frame, the enamel, the crossed swords
  jingle_1.mp3             the jingle (eleven_music_v2.5, 3 takes: _1 is used; _2 and _3 kept for a swap)
  slam_1.mp3, slam_3.mp3   the slam (eleven_text_to_sound_v2): _3's hit with _1's ringing tail and rubble

Writes:
  assets/ui/v2/bg_title_wall.webp     the wall (the title screen and the match's warm-up cover)
  assets/ui/v2/play_plaque.webp       the PLAY plaque, keyed out and cropped (its enamel: PLAQUE_FACE below)
  assets/music/title_jingle.ogg       the jingle, its silent lead and tail cut, faded out
  assets/sounds/titleSlam.wav         the slam
  assets/branding/splash.png          the wall for the boot splash and the first-start download screen (the base
                                      build: no pack is there yet; 540 x 1200, 256 colours: 375 KB)
  (assets/branding/title_logo.webp, the title for that download screen: tools/build_title_logo.py since 0.31.193)

  python3 tools/build_title_art.py
"""
import io
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(ROOT), "art_sources", "title_screen")
V2 = os.path.join(ROOT, "assets", "ui", "v2")
PLAQUE_W = 760                    # the plaque's width in the build (about 250 logical px at 3x)
JINGLE = (0.3, 5.4, 0.5)          # keep from, to, fade-out (seconds)


def plaque():
    im = Image.open(os.path.join(SRC, "play_plaque_green.png")).convert("RGB")
    a = np.array(im).astype(float)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    spill = G - np.maximum(R, B)
    alpha = 1.0 - np.clip((spill - 40.0) / 90.0, 0.0, 1.0)
    a[..., 1] = np.where((alpha < 1.0) | (spill > 10), np.minimum(G, np.maximum(R, B) * 1.02), G)
    al = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    out = Image.fromarray(np.dstack([a.clip(0, 255).astype(np.uint8), np.array(al)]), "RGBA")
    out = out.crop(out.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
    h = round(out.size[1] * PLAQUE_W / out.size[0])
    out = out.resize((PLAQUE_W, h), Image.LANCZOS)
    out.save(os.path.join(V2, "play_plaque.webp"), "WEBP", quality=92, method=6)
    print("play_plaque.webp", out.size)


def wall():
    im = Image.open(os.path.join(SRC, "wall.png")).convert("RGB")
    im.save(os.path.join(V2, "bg_title_wall.webp"), "WEBP", quality=88, method=6)
    small = im.resize((540, 1200), Image.LANCZOS)
    small = small.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    small.save(os.path.join(ROOT, "assets", "branding", "splash.png"), optimize=True)   # (the boot splash takes a PNG)
    print("bg_title_wall.webp", im.size, "splash.png", small.size)


def ff(*args):
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", *args], check=True)


def audio():
    a, b, fade = JINGLE
    ff("-i", os.path.join(SRC, "jingle_1.mp3"), "-ss", str(a), "-to", str(b),
       "-af", "afade=t=out:st=%.2f:d=%.2f,loudnorm=I=-14:TP=-1.0" % (b - a - fade, fade),
       "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", os.path.join(ROOT, "assets", "music", "title_jingle.ogg"))
    with tempfile.TemporaryDirectory() as tmp:
        hit = os.path.join(tmp, "hit.wav")
        tail = os.path.join(tmp, "tail.wav")
        ff("-i", os.path.join(SRC, "slam_3.mp3"), "-t", "0.45", "-af", "afade=t=out:st=0.3:d=0.15", "-ac", "1", "-ar", "44100", hit)
        ff("-i", os.path.join(SRC, "slam_1.mp3"), "-t", "1.5", "-af", "afade=t=out:st=1.1:d=0.4", "-ac", "1", "-ar", "44100", tail)
        ff("-i", hit, "-i", tail, "-filter_complex", "[0][1]amix=inputs=2:normalize=0,volume=0.8,alimiter=limit=0.95",
           "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", os.path.join(ROOT, "assets", "sounds", "titleSlam.wav"))
    print("title_jingle.ogg, titleSlam.wav")


if __name__ == "__main__":
    plaque()
    wall()
    audio()
