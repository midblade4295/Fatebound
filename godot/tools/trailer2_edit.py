#!/usr/bin/env python3
"""Fatebound trailer 2 - the edit.

    python3 tools/trailer2_edit.py --song Spooky_3.wav --out Fatebound-Trailer-2.mp4 [--vo DIR]

Shots from /tmp/trailer2 (tools/trailer2_shots.gd; the finale is reveal_fx.avi from tools/trailer2_reveal_fx.py),
0.4 s crossfades (a dip to black into the reveal), a gold caption per shot, Kevin's song placed so its drop
(SONG_DROP) lands on the title. --vo DIR: the Herald's lines as 1..9.(mp3|wav|ogg), one per shot, placed a beat
into each shot (line 9 after the title lands); the music ducks under him (sidechain compression).
"""
import argparse
import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "assets", "fonts", "LuckiestGuy-Regular.ttf")
W, H = 1920, 1080
# Round 22 (Kevin: show what you actually do -- what hats are -- and pump the 16 v 16 multiplayer): the armies
# clash, the goal (they stole our King), hats (a villager becomes a Knight; all seven classes), the action,
# fattening their King, carrying ours home, how you win (the throne), the reveal.
SHOTS = ["clash", "captive", "heroes", "lineup", "assault", "rampart", "whirl", "feast", "carry", "throne", "reveal"]
LENGTH = {"clash": 4.5, "captive": 4.0, "heroes": 4.0, "lineup": 4.0, "assault": 5.5, "rampart": 4.0, "whirl": 3.0,
          "feast": 4.0, "carry": 5.0, "throne": 4.0, "reveal": 9.0}
# Shots used shorter than they were rendered (trimmed from the start + HEAD).
USE = {"captive": 3.6, "heroes": 3.4, "lineup": 3.8, "assault": 4.6, "rampart": 3.6, "whirl": 2.9, "feast": 3.8,
       "carry": 4.2, "throne": 3.8}
CAPTIONS = {"clash": "16 VS 16 CASTLE SIEGE", "captive": "THEY STOLE OUR KING!", "heroes": "GRAB A HAT...",
            "lineup": "...BECOME A HERO", "assault": "STORM THEIR CASTLE", "rampart": "RAIN ARROWS FROM THE WALLS",
            "whirl": "SPIN! SMASH! REPEAT!", "feast": "STUFF THEIR KING WITH FISH", "carry": "CARRY YOUR KING HOME",
            "throne": "FIRST TO 3 RESCUES WINS"}
HEAD = 0.1          # skip the frames before each shot is staged
XF = 0.4
TITLE_AT = 1.4      # in reveal_fx.avi
SONG_DROP = 42.5    # seconds into Kevin's song
VO_LEAD = 0.35      # a line starts this far into its shot


def caption_png(text, path):
    f = ImageFont.truetype(FONT, 88)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bb = f.getbbox(text, stroke_width=9)
    x, y = (W - (bb[2] - bb[0])) // 2 - bb[0], H - 190 - bb[1]
    sh = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh).text((x + 5, y + 9), text, font=f, fill=150, stroke_width=9, stroke_fill=150)
    img.paste((0, 0, 0, 255), (0, 0), sh.filter(ImageFilter.GaussianBlur(8)))
    ImageDraw.Draw(img).text((x, y), text, font=f, fill=(46, 25, 8, 255), stroke_width=9, stroke_fill=(46, 25, 8, 255))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).text((x, y), text, font=f, fill=255)
    grad = Image.new("RGBA", (W, H))
    gd = ImageDraw.Draw(grad)
    for yy in range(y, y + (bb[3] - bb[1]) + 1):
        t = (yy - y) / max(1, bb[3] - bb[1])
        gd.line([(0, yy), (W, yy)], fill=(255, int(244 - 80 * t), int(170 - 130 * t), 255))
    img.paste(grad, (0, 0), mask)
    img.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--song", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--vo", default="")
    ap.add_argument("--dir", default="/tmp/trailer2")
    ap.add_argument("--stage", default="all", choices=["segments", "final", "all"],
                    help="segments: each shot trimmed with its caption burned in (resumable: existing ones are kept); "
                         "final: crossfades + audio. Split so each step fits a short time limit.")
    a = ap.parse_args()
    dur = [min(USE.get(s, 99.0), LENGTH[s] - HEAD - 0.05) for s in SHOTS]
    starts = []
    t = 0.0
    for k, d in enumerate(dur):
        starts.append(t)
        t += d - XF
    total = starts[-1] + dur[-1]
    title_global = starts[-1] + (TITLE_AT - HEAD)
    song_start = SONG_DROP - title_global
    segs = [os.path.join(a.dir, f"seg_{k}_{s}.mp4") for k, s in enumerate(SHOTS)]
    if a.stage in ("segments", "all"):
        for k, s in enumerate(SHOTS):
            if os.path.exists(segs[k]):
                continue
            src = os.path.join(a.dir, "reveal_fx.avi" if s == "reveal" else s + ".avi")
            inputs = ["-ss", f"{HEAD}", "-t", f"{dur[k]:.3f}", "-i", src]
            fl = "[0:v]setpts=PTS-STARTPTS,fps=30,format=yuv420p[v]"
            if s in CAPTIONS:
                p = os.path.join(a.dir, f"cap_{s}.png")
                caption_png(CAPTIONS[s], p)
                inputs += ["-loop", "1", "-t", f"{dur[k]:.3f}", "-i", p]
                t0, t1 = 0.3, dur[k] - XF - 0.1
                fl = ("[0:v]setpts=PTS-STARTPTS,fps=30[b];"
                      f"[1:v]format=rgba,fade=t=in:st={t0:.2f}:d=0.25:alpha=1,fade=t=out:st={t1 - 0.25:.2f}:d=0.25:alpha=1[c];"
                      f"[b][c]overlay=0:0:enable='between(t,{t0:.2f},{t1:.2f})',format=yuv420p[v]")
            tmp = segs[k] + ".part.mp4"
            subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", fl, "-map", "[v]", "-an",
                            "-c:v", "libx264", "-preset", "veryfast", "-crf", "14", "-t", f"{dur[k]:.3f}", tmp], check=True)
            os.replace(tmp, segs[k])
            print("segment", k, s, flush=True)
    if a.stage not in ("final", "all"):
        return
    inputs, fl = [], []
    for k in range(len(SHOTS)):
        inputs += ["-i", segs[k]]
    prev = "0:v"
    for k in range(1, len(SHOTS)):
        tr = "fadeblack" if SHOTS[k] == "reveal" else "fade"
        fl.append(f"[{prev}][{k}:v]xfade=transition={tr}:duration={XF}:offset={starts[k]:.3f}[x{k}]")
        prev = f"x{k}"
    fl.append(f"[{prev}]fade=t=out:st={total - 1.0:.2f}:d=1.0,format=yuv420p[vout]")
    si = len(SHOTS)
    inputs += ["-ss", f"{song_start:.3f}", "-t", f"{total:.3f}", "-i", a.song]
    fl.append(f"[{si}:a]volume=9.5dB,afade=t=in:st=0:d=0.8,afade=t=out:st={total - 1.6:.2f}:d=1.6,aresample=48000[music]")
    vo_files = []
    if a.vo:
        for k in range(len(SHOTS)):
            for ext in ("mp3", "wav", "ogg"):
                f = os.path.join(a.vo, f"{k + 1}.{ext}")
                if os.path.exists(f):
                    vo_files.append((k, f))
                    break
    if vo_files:
        labels = []
        for n, (k, f) in enumerate(vo_files):
            inputs += ["-i", f]
            at = (title_global + 0.9) if SHOTS[k] == "reveal" else (starts[k] + VO_LEAD)
            fl.append(f"[{si + 1 + n}:a]aresample=48000,volume=2.0,adelay={int(at * 1000)}|{int(at * 1000)}[h{n}]")
            labels.append(f"[h{n}]")
        fl.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0,apad=whole_dur={total:.3f}[herald]")
        fl.append("[herald]asplit=2[hsc][hmix]")
        fl.append("[music][hsc]sidechaincompress=threshold=0.02:ratio=8:attack=15:release=350[ducked]")
        fl.append(f"[ducked][hmix]amix=inputs=2:normalize=0,atrim=duration={total:.3f}[aout]")
    else:
        fl.append(f"[music]atrim=duration={total:.3f}[aout]")
    tmp = a.out + ".part.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(fl), "-map", "[vout]", "-map", "[aout]",
                    "-c:v", "libx264", "-preset", "faster", "-crf", "18", "-pix_fmt", "yuv420p", "-r", "30",
                    "-c:a", "aac", "-b:a", "192k", "-t", f"{total:.3f}", "-movflags", "+faststart", tmp], check=True)
    os.replace(tmp, a.out)
    print(f"wrote {a.out}: {total:.1f} s, title at {title_global:.2f} s, song from {song_start:.2f} s, {len(vo_files)} VO lines", flush=True)


if __name__ == "__main__":
    main()
