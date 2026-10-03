#!/usr/bin/env python3
"""Fatebound trailer 4 -- the cut (trailer 2's rules: crossfades, a dip to black into the reveal, the song's hit on the title,
the Herald dropped into his shots and the music ducking gently under him). Kevin: no captions -- only the final title.

    python3 tools/trailer4_edit.py --stage segments      # each shot trimmed + captioned (resumable)
    python3 tools/trailer4_edit.py --stage final --out /mnt/user-data/outputs/Fatebound-Trailer-4.mp4
"""
import argparse, os, subprocess, json

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "assets", "fonts", "LuckiestGuy-Regular.ttf")
VO_DIR = os.path.join(HERE, "trailer4_vo")   # the Herald's trailer-4 lines (ElevenLabs, Edward, one take, split per shot)
SONG = "/mnt/user-data/uploads/Fatebound-Theme-Spooky_3.wav"
SONG_HIT = 72.64         # the beat on the song's biggest hit (72.5 s, trailer 3) on the 0.31.12 beat grid: the title lands here
T = "/tmp/trailer4"
# 0.31.12 recut (Kevin: "a lot of slowness ... I want it to have more energy"): every shot a beat-sized slice from the
# middle of its render, sped up, hard cuts on the song's beats (126.5 BPM, beat 0.474 s, measured: tools notes), the
# title landing on the song's hit. The slow opening line is gone; the Herald's short lines ride the cuts.
BEAT = 0.4743
# shot, source start (s), beats on screen, speed, Herald line (trailer4_vo/N.ogg) or 0
#  2 "Rivers to cross."  3 "Islands to seize."  4 "Hills to hold."  5 "And a castle to storm. Theirs, preferably."
#  6 "Archers! To the towers!"  7 "Need a ladder? Chop a tree."  8 "Sixteen... against sixteen!"  9 "This... is FATEBOUND!"
SHOTS = [
    ("sky", 1.7, 6, 1.25, 0),            # from 1.7 s: past the empty sky at the top of the crane
    ("river", 1.0, 5, 1.25, 2),
    ("island", 1.2, 5, 1.25, 3),
    ("hills", 1.0, 4, 1.25, 4),
    ("castle", 1.5, 5, 1.25, 5),
    ("deck", 1.0, 5, 1.25, 6),
    ("logs", 0.4, 5, 1.15, 7),
    ("clash", 1.2, 6, 1.25, 8),
    ("golden", None, None, 1.0, 9),     # from the title pass: TITLE_BEATS before the landing, to its end
]
TITLE_BEATS = 5
TITLE_LAND = 4.9         # seconds into "golden" (tools/trailer4_title_fx.py --land)
FATEBOUND_ONSET = 0.98   # "FATEBOUND" starts 0.98 s into line 9 (word timing from the recogniser)
VO_GAIN, FINALE_GAIN = 2.3, 3.5  # trailer 2's 1.7 / 2.6, +2.7 dB: this take is 2.7 dB quieter (-16.9 vs -14.2 LUFS)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(r.stderr[-2000:])


def dur(path):
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                                capture_output=True, text=True).stdout.strip())


def seg_len(k):
    name, _, beats, _, _ = SHOTS[k]
    if name == "golden":
        return dur(f"{T}/golden_fx.mp4") - (TITLE_LAND - TITLE_BEATS * BEAT)
    return beats * BEAT


def segments():
    for k, (name, start, beats, speed, _) in enumerate(SHOTS):
        out = f"{T}/seg_{name}.mp4"
        if os.path.exists(out):
            continue
        length = seg_len(k)
        if name == "golden":
            src, start = f"{T}/golden_fx.mp4", TITLE_LAND - TITLE_BEATS * BEAT
        else:
            src = f"{T}/{name}.avi"
        vf = f"setpts=PTS/{speed},fps=30,scale=1920:1080,setsar=1"
        run(["ffmpeg", "-v", "error", "-y", "-ss", f"{start:.3f}", "-i", src, "-t", f"{length * speed:.3f}", "-vf", vf, "-an",
             "-frames:v", str(int(round(length * 30))), "-c:v", "libx264", "-crf", "16", "-preset", "medium", "-pix_fmt", "yuv420p", out])
        print("SEG", name, round(dur(out), 2))


def final(out, audio_only=False):
    # audio_only: keep the video of an existing cut (stream copy) and rebuild just the mix (~10 s instead of minutes)
    segs = [f"{T}/seg_{n}.mp4" for n, *_ in SHOTS]
    lens = [seg_len(k) for k in range(len(SHOTS))]
    starts, t = [], 0.0
    for L in lens:
        starts.append(t)
        t += L
    total = t
    land = starts[-1] + TITLE_BEATS * BEAT
    inputs, fc = [], []
    if audio_only:
        src = out + ".video.mp4"
        os.replace(out, src)
        inputs += ["-i", src]
    else:
        for p in segs:
            inputs += ["-i", p]
        fc.append("".join(f"[{k}:v]" for k in range(len(segs))) + f"concat=n={len(segs)}:v=1:a=0[vout]")
    song_from = SONG_HIT - land
    vo, prev_end = [], 0.0
    for k, (name, _, _, _, line) in enumerate(SHOTS):
        if not line:
            continue
        f = os.path.join(VO_DIR, f"{line}.ogg")
        d = dur(f)
        at = land - FATEBOUND_ONSET if name == "golden" else max(starts[k] + 0.15, prev_end + 0.12)
        vo.append((f, at, FINALE_GAIN if name == "golden" else VO_GAIN))
        prev_end = at + d
    ai = 1 if audio_only else len(segs)
    inputs += ["-ss", f"{song_from:.3f}", "-i", SONG]
    fc.append(f"[{ai}:a]atrim=0:{total:.3f},afade=t=in:d=0.12,afade=t=out:st={total - 1.6:.3f}:d=1.6,volume=0.9[mus]")
    vl = []
    for jx, (f, at, g) in enumerate(vo):
        inputs += ["-i", f]
        fc.append(f"[{ai + 1 + jx}:a]aresample=48000,aformat=channel_layouts=stereo,volume={g},adelay={int(at * 1000)}|{int(at * 1000)}[vo{jx}]")
        vl.append(f"[vo{jx}]")
    fc.append(f"{''.join(vl)}amix=inputs={len(vl)}:normalize=0,apad=whole_dur={total:.3f}[vos]")
    fc.append("[vos]asplit=2[vosa][vosb]")
    fc.append("[mus]aresample=48000,aformat=channel_layouts=stereo[mus48]")
    fc.append("[mus48][vosa]sidechaincompress=threshold=0.12:ratio=2:knee=6:attack=40:release=700[duck]")
    fc.append(f"[duck][vosb]amix=inputs=2:normalize=0,alimiter=limit=0.70:level=disabled,atrim=0:{total:.3f}[aout]")
    vmap = ["-map", "0:v", "-c:v", "copy"] if audio_only else ["-map", "[vout]", "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p"]
    run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(fc)] + vmap + ["-map", "[aout]",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out])
    if audio_only:
        os.remove(out + ".video.mp4")
    print(json.dumps({"total": round(total, 2), "title_land": round(land, 2), "song_from": round(song_from, 2),
                      "cuts": [round(x, 2) for x in starts], "vo": [[os.path.basename(f), round(a, 2)] for f, a, _ in vo]}))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", choices=["segments", "final", "audio"], required=True)
    ap.add_argument("--out", default="/mnt/user-data/outputs/Fatebound-Trailer-4.mp4")
    a = ap.parse_args()
    if a.stage == "segments":
        segments()
    else:
        final(a.out, audio_only=a.stage == "audio")
