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
# Round 23 (Kevin: "should also include mechanics about gathering resources"): gather + build after the heroes.
# Round 28 (Kevin, after Derek Lieu's "Sheepherds" makeover): the core action first and given time (break in, grab
# the King, run; the carry goes wrong; the rescue scores), then the layers (their King fattened until one raider can't
# lift him; getting in; hats), the variety last; few title cards; a struggle and a comedy beat.
SHOTS = ["breakin", "carry2", "throne", "feast", "toofat", "gather", "build", "assault", "heroes", "hatsteal",
         "rampart", "backstab", "clash", "reveal"]
LENGTH = {"breakin": 10.6, "carry2": 7.9, "throne": 4.0, "feast": 4.0, "toofat": 5.5, "gather": 4.0, "build": 4.9,
          "assault": 5.5, "heroes": 4.3, "hatsteal": 5.0, "rampart": 4.0, "backstab": 4.0, "clash": 4.5, "reveal": 9.0}
USE = {"breakin": 10.3, "carry2": 7.6, "throne": 3.8, "feast": 3.8, "toofat": 5.2, "gather": 3.6, "build": 4.6,
       "assault": 4.4, "heroes": 3.9, "hatsteal": 4.7, "rampart": 3.3, "backstab": 3.6, "clash": 4.2}
# Title cards only where the picture can't say it.
CAPTIONS = {"throne": "FIRST TO 3 RESCUES WINS", "clash": "16 VS 16"}
# The Herald, by shot: 15.. = the new read (pending), 1 = "Sixteen against sixteen!", 11 = "This... is FATEBOUND!".
VO_FILE = {"breakin": 15, "carry2": 16, "throne": 17, "feast": 18, "toofat": 19, "gather": 20, "build": 21,
           "assault": 22, "heroes": 23, "hatsteal": 24, "clash": 1, "reveal": 11}
# Where in its shot a line starts (default VO_LEAD): "Rule two: don't drop him" on the drop, the hat line once he's
# fallen, "Or just knock" as they reach the gate.
VO_AT = {"carry2": 1.25, "hatsteal": 0.9, "assault": 1.2, "toofat": 1.0, "clash": 0.0}
HEAD = 0.1          # skip the frames before each shot is staged
XF = 0.4
TITLE_AT = 1.4      # in reveal_fx.avi
SONG_DROP = 72.5    # the song's biggest hit (the first drop is at 42.5)
VO_LEAD = 0.35      # a line starts this far into its shot
# Ducking (Kevin: "the music volume drops too much when voice happens, it needs to blend better"): was threshold
# 0.012 / ratio 12, about 10 dB under every line. Now a gentle, soft-kneed dip with a slow release.
DUCK = "threshold=0.12:ratio=2:attack=40:release=700:knee=6"
VO_GAIN = 1.7
VO_GAIN_FINALE = 2.6
# Lines over louder stretches of the song get more, so every line sits ~10-12 dB over the music (measured with
# --duck-out: the backstab line was only 6 dB over it).
VO_GAIN_SHOT = {"backstab": 2.7}


FINALE_TEXT = "this is fatebound"       # the Herald's last line, as the aligner hears it
FINALE_WORD = "fatebound"               # ... and the word the title pops in on
FINALE_WORD_FALLBACK = 1.11             # measured in Kevin's read (s into the line), if pocketsphinx is missing


def word_onset(path, text, word):
    # Where `word` starts in the recording at `path`: force-align the known text (Kevin: "right when he says
    # 'fatebound' the title of the game pops in").
    try:
        from pocketsphinx import Decoder
    except ImportError:
        return FINALE_WORD_FALLBACK
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", "16000", "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    d = Decoder(samprate=16000)
    if d.lookup_word("fatebound") is None:
        d.add_word("fatebound", "F EY T B AW N D", True)
    d.set_align_text(text)
    d.start_utt()
    d.process_raw(raw, full_utt=True)
    d.end_utt()
    for sg in d.seg():
        if sg.word.split("(")[0] == word:
            return sg.start_frame / 100.0
    return FINALE_WORD_FALLBACK


def caption_png(text, path):
    size = 88
    f = ImageFont.truetype(FONT, size)
    while f.getbbox(text, stroke_width=9)[2] - f.getbbox(text, stroke_width=9)[0] > W - 160 and size > 50:
        size -= 4
        f = ImageFont.truetype(FONT, size)            # long captions shrink to fit
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
    ap.add_argument("--video", default="", help="--stage audio: the finished video to put the new mix on (video copied)")
    ap.add_argument("--duck-out", default="", help="--stage audio: also write the ducked music alone (for measuring)")
    ap.add_argument("--stage", default="all", choices=["segments", "final", "all", "audio"],
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
    segs = [os.path.join(a.dir, f"seg3_{k}_{s}.mp4") for k, s in enumerate(SHOTS)]
    first_drop = 42.5 - song_start
    near = min(range(len(starts)), key=lambda k: abs(starts[k] - first_drop))
    print(f"title {title_global:.2f} s, song from {song_start:.2f} s; first drop at {first_drop:.2f} s "
          f"(nearest cut: {SHOTS[near]} at {starts[near]:.2f} s)", flush=True)
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
    if a.stage not in ("final", "all", "audio"):
        return
    inputs, fl = [], []
    if a.stage == "audio":
        # Just the mix, put on an existing cut (video stream copied): seconds instead of minutes.
        inputs += ["-i", a.video]
    else:
        for k in range(len(SHOTS)):
            inputs += ["-i", segs[k]]
        prev = "0:v"
        for k in range(1, len(SHOTS)):
            tr = "fadeblack" if SHOTS[k] == "reveal" else "fade"
            fl.append(f"[{prev}][{k}:v]xfade=transition={tr}:duration={XF}:offset={starts[k]:.3f}[x{k}]")
            prev = f"x{k}"
        fl.append(f"[{prev}]fade=t=out:st={total - 1.0:.2f}:d=1.0,format=yuv420p[vout]")
    si = 1 if a.stage == "audio" else len(SHOTS)
    # (If the cut grows past the song's lead-in, the song starts late instead of before its beginning.)
    lead_pad = max(0.0, -song_start)
    inputs += ["-ss", f"{max(0.0, song_start):.3f}", "-t", f"{total:.3f}", "-i", a.song]
    fl.append(f"[{si}:a]adelay={int(lead_pad * 1000)}|{int(lead_pad * 1000)},volume=9.5dB,afade=t=in:st=0:d=0.8,afade=t=out:st={total - 1.6:.2f}:d=1.6,aresample=48000[music]")
    vo_files = []
    if a.vo:
        for k in range(len(SHOTS)):
            if SHOTS[k] not in VO_FILE:
                continue                          # shots with no line (the music carries them)
            for ext in ("mp3", "wav", "ogg"):
                f = os.path.join(a.vo, f"{VO_FILE[SHOTS[k]]}.{ext}")
                if os.path.exists(f):
                    vo_files.append((k, f))
                    break
    if vo_files:
        labels = []
        prev_end = 0.0
        for n, (k, f) in enumerate(vo_files):
            inputs += ["-i", f]
            if SHOTS[k] == "reveal":
                # "This... is FATEBOUND!": placed so the word starts exactly as the title pops in (on the drop).
                onset = word_onset(f, FINALE_TEXT, FINALE_WORD)
                at = title_global - onset
                print(f"  '{FINALE_WORD}' starts {onset:.2f} s into the line -> line at {at:.2f} s, the word at {title_global:.2f} s (title)", flush=True)
            else:
                at = starts[k] + VO_AT.get(SHOTS[k], VO_LEAD)
            # Never on top of the line before: a long read tails into the next shot's crossfade, and the
            # next line waits for it (plus a beat).
            vlen = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f],
                                        capture_output=True, text=True).stdout or 0.0)
            if SHOTS[k] != "reveal":
                at = max(at, prev_end + 0.12)     # the finale line is anchored: "FATEBOUND" on the title wins
            prev_end = at + vlen
            print(f"  {SHOTS[k]:8s} line {VO_FILE[SHOTS[k]]:2d} at {at:5.2f}-{prev_end:5.2f} s", flush=True)
            # The last line sits on the drop, the loudest music in the trailer: a little more so it cuts through.
            gain = VO_GAIN_FINALE if SHOTS[k] == "reveal" else VO_GAIN_SHOT.get(SHOTS[k], VO_GAIN)
            fl.append(f"[{si + 1 + n}:a]aresample=48000,volume={gain},adelay={int(at * 1000)}|{int(at * 1000)}[h{n}]")
            labels.append(f"[h{n}]")
        fl.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0,apad=whole_dur={total:.3f}[herald]")
        fl.append("[herald]asplit=2[hsc][hmix]")
        fl.append(f"[music][hsc]sidechaincompress={DUCK}[ducked0]")
        if a.duck_out:
            fl.append("[ducked0]asplit=2[ducked][dk]")
        else:
            fl.append("[ducked0]anull[ducked]")
        # A limiter at -1 dBFS: the Herald on top of the music peaked at +4 dBFS (clipping) without it.
        fl.append(f"[ducked][hmix]amix=inputs=2:normalize=0,alimiter=limit=0.891:attack=5:release=60:level=disabled,atrim=duration={total:.3f}[aout]")
    else:
        fl.append(f"[music]atrim=duration={total:.3f}[aout]")
    tmp = a.out + ".part.mp4"
    vmap = ["-map", "0:v", "-c:v", "copy"] if a.stage == "audio" else \
        ["-map", "[vout]", "-c:v", "libx264", "-preset", "veryfast", "-crf", "17", "-pix_fmt", "yuv420p", "-r", "30"]
    extra = ["-map", "[dk]", "-t", f"{total:.3f}", a.duck_out] if (a.duck_out and vo_files) else []
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(fl)] + vmap + ["-map", "[aout]",
                    "-c:a", "aac", "-b:a", "192k", "-t", f"{total:.3f}", "-movflags", "+faststart", tmp] + extra, check=True)
    os.replace(tmp, a.out)
    print(f"wrote {a.out}: {total:.1f} s, title at {title_global:.2f} s, song from {song_start:.2f} s, {len(vo_files)} VO lines", flush=True)


if __name__ == "__main__":
    main()
