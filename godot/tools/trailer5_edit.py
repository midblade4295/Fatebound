#!/usr/bin/env python3
"""Fatebound trailer 5 -- the cut. The score (tools/trailer5_vo/score.mp3, 58 s) is the timeline: its first-frame impact
opens on the slow-motion axe, its drop (37.5-40 s) carries the King home, the slow-motion trio rides its build, and its
climax hit (48.69 s) cuts to the title with the Herald's "FATEBOUND" landing as the title does. No captions (Kevin).

    python3 tools/trailer5_edit.py --stage segments     # each shot trimmed/retimed (resumable)
    python3 tools/trailer5_edit.py --stage final --out /mnt/user-data/outputs/Fatebound-Trailer-5.mp4
    python3 tools/trailer5_edit.py --stage audio --out ...   # keep the video, rebuild the mix
"""
import argparse, json, os, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
VO = os.path.join(HERE, "trailer5_vo")
SND = os.path.join(HERE, "..", "assets", "sounds")
T = "/tmp/trailer5"
TOTAL = 58.0
HIT = 48.69               # the score's climax hit: cut to the title
# (shot, source start, seconds on screen, playback speed) -- back to back from 0
CUTS = [
    ("hook", 0.30, 6.00, 1.0),
    ("dawn", 0.30, 4.60, 1.0),
    ("captive", 0.50, 1.80, 1.0),
    ("feast", 0.00, 4.10, 1.0),
    ("toofat", 0.00, 3.50, 0.6),     # a slow push on a very fat King
    ("heroes", 0.20, 4.00, 1.0),
    ("gather", 0.60, 1.40, 1.0),
    ("build", 2.30, 4.00, 1.0),      # hammering, the ladder swings up, three heroes climb it
    ("breakin", 1.50, 5.20, 1.0),
    ("toofat", 2.10, 3.10, 1.0),     # ...and LIFT
    ("carry2", 1.00, 2.30, 1.0),
    ("necro", 2.00, 1.50, 1.0),      # slow motion in the render
    ("hammer", 0.20, 1.65, 1.5),     # from just before the throw (Kevin); slow motion in the render, 1.5x here
    ("whirl", 0.30, 2.78, 1.5),      # three charge, he spins: slow motion in the render, 1.5x here
    ("throne", 0.80, 2.76, 1.0),
    ("golden", 4.40, None, 1.0),     # to the end; the last frame held
]
# Herald lines (trailer5_vo/N.ogg) at trailer seconds; "shout" timed so FATEBOUND (1.93 s into it, measured from its
# energy -- the recogniser's 1.04 s was off) lands as the title does, HIT + 0.5
LINES = [(1, 2.40), (2, 6.20), (3, 10.75), (4, 12.50), (5, 20.80), (6, 25.70), (7, 31.55), (8, 34.70), (9, 35.80),
         (10, 37.80), (11, 40.00), (12, 41.55), (13, 42.80), (15, 44.85), ("shout", HIT + 0.50 - 1.93), (16, 55.20)]
VO_GAIN, SHOUT_GAIN = 2.1, 2.6
# sound design from the game's own sounds: (file, at, gain, filters)
SFX = [("tm_sword_hit2.wav", 1.50, 1.6, "asetrate=44100*0.55,aresample=48000"),     # the slowed axe impact
       ("tm_rock_hit1.wav", 1.50, 1.2, "asetrate=44100*0.6,aresample=48000"),       # ...with a deep boom under it
       ("tm_crumble1.wav", 32.6, 1.0, "aresample=48000"),                          # the cell smashed
       ("hammerThrow.wav", 41.50, 1.2, "asetrate=44100*0.8,aresample=48000")]      # the hammer, slowed


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(r.stderr[-2500:])


def dur(p):
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p],
                                capture_output=True, text=True).stdout.strip())


def plan():
    t, out = 0.0, []
    for k, (shot, src, d, speed) in enumerate(CUTS):
        if d is None:
            d = TOTAL - t
        out.append((k, shot, src, d, speed, t))
        t += d
    return out


def segments():
    for k, shot, src, d, speed, at in plan():
        out = f"{T}/seg5_{k:02d}_{shot}.mp4"
        if os.path.exists(out):
            continue
        path = f"{T}/golden_fx.mp4" if shot == "golden" else f"{T}/{shot}.avi"
        tail = 0.85 if shot == "golden" else 0.0       # the light pass fades out over its last 0.8 s: hold before that
        avail = (dur(path) - src - tail) / speed
        vf = f"trim=0:{avail * speed:.3f},setpts=PTS/{speed},fps=30,scale=1920:1080,setsar=1"
        if avail < d:                                   # hold the last frame (the title) to fill
            vf += f",tpad=stop_mode=clone:stop_duration={d - avail + 0.1:.3f}"
        if shot == "golden":
            vf += f",fade=t=out:st={d - 0.6:.3f}:d=0.6"
        run(["ffmpeg", "-v", "error", "-y", "-ss", f"{src:.3f}", "-i", path, "-vf", vf, "-an", "-frames:v", str(int(round(d * 30))),
             "-c:v", "libx264", "-crf", "16", "-preset", "medium", "-pix_fmt", "yuv420p", out])
        print("SEG", k, shot, round(dur(out), 2), "at", round(at, 2))


def final(out, audio_only=False):
    p = plan()
    inputs, fc = [], []
    if audio_only:
        src = out + ".video.mp4"
        os.replace(out, src)
        inputs += ["-i", src]
    else:
        for k, shot, *_ in p:
            inputs += ["-i", f"{T}/seg5_{k:02d}_{shot}.mp4"]
        fc.append("".join(f"[{k}:v]" for k in range(len(p))) + f"concat=n={len(p)}:v=1:a=0[vout]")
    base = 1 if audio_only else len(p)
    inputs += ["-i", os.path.join(VO, "score.mp3")]
    fc.append(f"[{base}:a]aresample=48000,aformat=channel_layouts=stereo,atrim=0:{TOTAL},volume=0.85[mus]")
    vl, j = [], base + 1
    for line, at in LINES:
        inputs += ["-i", os.path.join(VO, f"{line}.ogg")]
        g = SHOUT_GAIN if line == "shout" else VO_GAIN
        fc.append(f"[{j}:a]aresample=48000,aformat=channel_layouts=stereo,volume={g},adelay={int(at * 1000)}|{int(at * 1000)}[v{j}]")
        vl.append(f"[v{j}]")
        j += 1
    sl = []
    for f, at, g, flt in SFX:
        inputs += ["-i", os.path.join(SND, f)]
        fc.append(f"[{j}:a]{flt},aformat=channel_layouts=stereo,volume={g},adelay={int(at * 1000)}|{int(at * 1000)}[s{j}]")
        sl.append(f"[s{j}]")
        j += 1
    fc.append(f"{''.join(vl)}amix=inputs={len(vl)}:normalize=0,apad=whole_dur={TOTAL}[vos]")
    fc.append(f"{''.join(sl)}amix=inputs={len(sl)}:normalize=0,apad=whole_dur={TOTAL}[sfx]")
    fc.append("[vos]asplit=2[vosa][vosb]")
    fc.append("[mus][vosa]sidechaincompress=threshold=0.10:ratio=2.5:knee=6:attack=30:release=600[duck]")
    fc.append(f"[duck][vosb][sfx]amix=inputs=3:normalize=0,alimiter=limit=0.70:level=disabled,atrim=0:{TOTAL}[aout]")
    vmap = ["-map", "0:v", "-c:v", "copy"] if audio_only else ["-map", "[vout]", "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p"]
    run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(fc)] + vmap + ["-map", "[aout]",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out])
    if audio_only:
        os.remove(out + ".video.mp4")
    print(json.dumps({"cuts": [[s, round(a, 2)] for _, s, _, _, _, a in p], "title_hit": HIT}))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", choices=["segments", "final", "audio"], required=True)
    ap.add_argument("--out", default="/mnt/user-data/outputs/Fatebound-Trailer-5.mp4")
    a = ap.parse_args()
    if a.stage == "segments":
        segments()
    else:
        final(a.out, audio_only=a.stage == "audio")
