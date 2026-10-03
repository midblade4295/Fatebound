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
SONG_HIT = 72.5          # the song's biggest hit (measured for trailer 3): lands on the title
T = "/tmp/trailer4"
XF = 0.5
# shot, length used (s), caption (none: Kevin), Herald line (trailer4_vo/N.ogg) or 0
#  1 "Once upon a time, there were two kingdoms. They did not get along."   2 "Rivers to cross."   3 "Islands to seize."
#  4 "Hills to hold."   5 "And a castle to storm. Theirs, preferably."   6 "Archers! To the towers!"
#  7 "Need a ladder? Chop a tree."   8 "Sixteen... against sixteen!"   9 "This... is FATEBOUND!"
SHOTS = [
    ("sky", 5.5, "", 1),
    ("river", 6.0, "", 2),
    ("island", 5.5, "", 3),
    ("hills", 5.0, "", 4),
    ("castle", 6.0, "", 5),
    ("deck", 5.0, "", 6),
    ("logs", 4.5, "", 7),
    ("clash", 5.0, "", 8),
    ("golden", 10.0, "", 9),
]
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


def segments():
    for name, length, cap, _ in SHOTS:
        out = f"{T}/seg_{name}.mp4"
        if os.path.exists(out):
            continue
        src = f"{T}/golden_fx.mp4" if name == "golden" else f"{T}/{name}.avi"
        vf = "fps=30,scale=1920:1080,setsar=1"
        if cap:
            a_in, a_out = 0.45, length - 0.55
            alpha = f"if(lt(t,{a_in}),0,if(lt(t,{a_in + 0.35}),(t-{a_in})/0.35,if(lt(t,{a_out}),1,max(0,1-(t-{a_out})/0.35))))"
            vf += (f",drawtext=fontfile={FONT}:text='{cap}':fontsize=78:fontcolor=0xFFD46A:borderw=7:bordercolor=0x341C08"
                   f":shadowcolor=0x000000AA:shadowx=4:shadowy=6:x=(w-text_w)/2:y=h*0.80:alpha='{alpha}'")
        start = 0.0 if name == "golden" else 0.07
        run(["ffmpeg", "-v", "error", "-y", "-ss", str(start), "-i", src, "-t", str(length), "-vf", vf, "-an",
             "-c:v", "libx264", "-crf", "16", "-preset", "medium", "-pix_fmt", "yuv420p", out])
        print("SEG", name, round(dur(out), 2))


def final(out, audio_only=False):
    # audio_only: keep the video of an existing cut (stream copy) and rebuild just the mix (~10 s instead of minutes)
    segs = [f"{T}/seg_{n}.mp4" for n, *_ in SHOTS]
    lens = [dur(p) for p in segs]
    # video: crossfades, a dip to black into the reveal
    inputs, fc, last, t = [], [], "0:v", lens[0]
    starts = [0.0]
    if audio_only:
        src = out + ".video.mp4"
        os.replace(out, src)
        inputs += ["-i", src]
    else:
        for p in segs:
            inputs += ["-i", p]
    for k in range(1, len(segs)):
        off = t - XF
        kind = "fadeblack" if SHOTS[k][0] == "golden" else "fade"
        lbl = f"v{k}"
        if not audio_only:
            fc.append(f"[{last}][{k}:v]xfade=transition={kind}:duration={XF}:offset={off:.3f}[{lbl}]")
        starts.append(off)
        last, t = lbl, off + lens[k]
    total = t
    land = starts[-1] + TITLE_LAND
    # audio: the song placed so its hit lands on the title; the Herald in his shots (never overlapping); ducking
    song_from = SONG_HIT - land
    vo = []
    prev_end = 0.0
    for k, (name, _, _, line) in enumerate(SHOTS):
        if not line:
            continue
        f = os.path.join(VO_DIR, f"{line}.ogg")
        d = dur(f)
        at = land - FATEBOUND_ONSET if name == "golden" else max(starts[k] + 0.35, prev_end + 0.12)
        vo.append((f, at, FINALE_GAIN if name == "golden" else VO_GAIN))
        prev_end = at + d
    ai = 1 if audio_only else len(segs)
    inputs += ["-ss", f"{max(song_from, 0):.3f}", "-i", SONG]
    pad = max(0.0, -song_from)
    fc.append(f"[{ai}:a]adelay={int(pad * 1000)}|{int(pad * 1000)},atrim=0:{total:.3f},afade=t=in:d=0.6,"
              f"afade=t=out:st={total - 1.6:.3f}:d=1.6,volume=0.9[mus]")
    vlabels = []
    for j, (f, at, g) in enumerate(vo):
        inputs += ["-i", f]
        idx = ai + 1 + j
        fc.append(f"[{idx}:a]aresample=48000,aformat=channel_layouts=stereo,volume={g},adelay={int(at * 1000)}|{int(at * 1000)}[vo{j}]")
        vlabels.append(f"[vo{j}]")
    fc.append(f"{''.join(vlabels)}amix=inputs={len(vlabels)}:normalize=0,apad=whole_dur={total:.3f}[vos]")
    fc.append("[vos]asplit=2[vosa][vosb]")
    fc.append("[mus]aresample=48000,aformat=channel_layouts=stereo[mus48]")
    fc.append("[mus48][vosa]sidechaincompress=threshold=0.12:ratio=2:knee=6:attack=40:release=700[duck]")
    fc.append(f"[duck][vosb]amix=inputs=2:normalize=0,alimiter=limit=0.70:level=disabled,atrim=0:{total:.3f}[aout]")
    vmap = ["-map", "0:v", "-c:v", "copy"] if audio_only else ["-map", f"[{last}]", "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p"]
    run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(fc)] + vmap + ["-map", "[aout]",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out])
    if audio_only:
        os.remove(out + ".video.mp4")
    print(json.dumps({"total": round(total, 2), "title_land": round(land, 2), "song_from": round(song_from, 2),
                      "vo": [[os.path.basename(f), round(a, 2)] for f, a, _ in vo]}))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", choices=["segments", "final", "audio"], required=True)
    ap.add_argument("--out", default="/mnt/user-data/outputs/Fatebound-Trailer-4.mp4")
    a = ap.parse_args()
    if a.stage == "segments":
        segments()
    else:
        final(a.out, audio_only=a.stage == "audio")
