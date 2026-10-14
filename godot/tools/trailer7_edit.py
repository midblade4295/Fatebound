#!/usr/bin/env python3
"""Fatebound trailer 7 -- "Bring Him Home" -- the cut and the mix (the plan: tools/trailer7_script.md).

The staged runs (tools/trailer7_shots.gd -> /tmp/trailer7/<run>.avi) are cut back to back by CUTS, timed to the music:
A (the prelude) from 0 to its dead stop; half a second of silence with time frozen; B (the battle) crashing in on the
impact; C (the rise and the final hit) landing on the flash into the title. Every sound is placed on a shot (cut name +
a time in that run's recording), so trimming a cut keeps the sounds on their pictures. The finishing pass (grade,
letterbox, cards, flash, the title) is tools/trailer7_finish.py.

    python3 tools/trailer7_edit.py --stage segments     # each shot trimmed to its cut (resumable: delete to redo)
    python3 tools/trailer7_edit.py --stage cut          # the picture (cut.mp4) and plan.json for the finish
    python3 tools/trailer7_edit.py --stage final --out /mnt/user-data/outputs/Fatebound-Trailer-7.mp4
    python3 tools/trailer7_edit.py --stage plan         # the timeline
"""
import argparse, json, os, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
VO = os.path.join(HERE, "trailer7_vo", "raw")
VO6 = os.path.join(HERE, "trailer6_vo", "raw")
SND = os.path.join(HERE, "..", "assets", "sounds")
T = "/tmp/trailer7"
FPS = 30

# The music's landmarks (seconds in each file; measured from their envelopes).
A_BOOMS = [1.52, 7.71, 13.59, 20.05]
A_STOP = 28.0                 # the crescendo's peak: cut dead here


def resume_v(run, default):
    """When time starts again after the freeze on the blows, in that charge run's recording (its log: RESUME v=)."""
    try:
        for line in open(f"/tmp/trailer7/{run}.log"):
            if line.startswith("RESUME"):
                return float(line.split("v=")[1])
    except OSError:
        pass
    return default
FREEZE = 0.55                 # silence, time frozen, before the impact
B_AT = A_STOP + FREEZE        # B's first downbeat = the impact
BAR = 4 * 60.0 / 139.7        # B (and C) at 139.7 BPM
B_DIP = (20.85, 24.0)         # B's quiet bars (the cell smashed in), back at full force at 24.0
B_FADE = 32.75
C_HIT = 1.70                  # C's riser lands here
TITLE = B_AT + 20 * BAR       # the hit on B's 20th bar: the flash, the title
END = TITLE + 12.1

# (run, source start in its recording (video seconds), seconds on screen, name) -- back to back from 0.
CUTS = [
    ("black", 0.0, A_BOOMS[0], "black0"),
    ("dawn", 0.20, 3.55, "kingdom"),
    ("dawn", 6.80, A_BOOMS[1] - A_BOOMS[0] - 3.55, "river"),
    ("captive", 1.40, A_BOOMS[2] - A_BOOMS[1], "captive"),
    ("muster", 0.50, 3.45, "rank"),
    ("muster", 3.97, 2.60, "gates"),
    ("muster", 6.90, 2.40, "pourout"),
    ("charge2", 0.10, 1.50, "wide"),      # both armies across the field (charge2: the same charge, other angles)
    ("charge", 0.38, 1.25, "line"),       # down our line on a long lens
    ("charge2", 1.20, 1.20, "ours"),      # low in front of ours
    ("charge", 1.633, 0.767, "theirs"),   # low in front of theirs
    ("charge", 2.40, 0.0, "clash"),       # the meeting from the side; time all but stops on the blows (to RESUME)
    ("charge3", 0.0, 1.75 * BAR, "impact"),  # B: time starts again, slowly -- their front rank thrown back (from behind ours)
    ("hammer", 0.10, 1.25 * BAR, "hammer"),
    ("whirl", 0.55, BAR, "whirl"),
    ("meteor", 1.45, 1.5 * BAR, "meteor"),
    ("black", 0.0, 0.5 * BAR, "card16"),
    ("volley", 0.55, BAR, "volley"),
    ("necro", 0.35, BAR, "necro"),
    ("sniper", 1.25, 0.75 * BAR, "sniper"),
    ("rogue", 0.25, 0.75 * BAR, "rogue"),
    ("shield", 1.00, 0.75 * BAR, "shield"),
    ("gate", 1.60, 0.0, "gate"),                                                     # (to the dip: set by plan())
    ("heist", 0.30, B_DIP[1] - B_DIP[0], "smash"),                                   # (the quiet bars: the door smashed in)
    ("heist", 8.35, BAR, "runout"),                                                  # B back at full force: him held high
    ("carry", 0.30, 2.15, "bridge"),
    ("carry", 5.60, 2.90, "ambush"),
    ("carry", 11.40, 0.0, "home"),                                                   # (to C's rise)
    ("throne", 0.03, C_HIT, "throne"),                                               # (ends as he's set down: 1.733)
    ("titlebg", 0.5, END - TITLE, "title"),
]
CARDS = [
    {"text": "TWO KINGDOMS", "at": ("kingdom", 0.75), "dur": 2.7},
    {"text": "ONE STOLEN KING", "at": ("captive", 2.30), "dur": 3.3},
    {"text": "BRING HIM HOME", "at": ("rank", 0.85), "dur": 2.5},
    {"text": "16 VS 16", "at": ("card16", 0.0), "dur": 0.5 * BAR, "size": 104, "snap": True},
]


def plan():
    """[(k, run, src, dur, name, t0)], {name: (t0, src)}, total -- with the derived cuts filled in."""
    cuts = [list(c) for c in CUTS]
    by = {c[3]: c for c in cuts}
    # the clash runs to the freeze's end, on B's first beat; the impact continues it from there
    t = 0.0
    for c in cuts:
        if c[3] == "clash":
            c[2] = B_AT - t
            break
        t += c[2]
    by["clash"][1] = resume_v("charge", 4.2) - by["clash"][2]
    by["impact"][1] = resume_v("charge3", 4.2)
    # the montage runs to B's dip; the gate shot takes what's left
    t = 0.0
    for c in cuts:
        if c[3] == "gate":
            c[2] = (B_AT + B_DIP[0]) - t
            break
        t += c[2]
    # the carry home runs to C's rise; C's rise is the throne
    t = 0.0
    for c in cuts:
        if c[3] == "home":
            c[2] = (TITLE - C_HIT) - t
            break
        t += c[2]
    # (each boundary on a whole frame, from the exact running time: no drift)
    exact, rows, out = 0.0, [], {}
    for k, (shot, src, d, name) in enumerate(cuts):
        t0 = round(exact * FPS) / FPS
        exact += d
        t1 = round(exact * FPS) / FPS
        rows.append((k, shot, src, t1 - t0, name, t0))
        out[name] = (t0, src)
    return rows, out, round(exact * FPS) / FPS


def at(anchor, cuts):
    if anchor is None:
        return None
    if isinstance(anchor, (int, float)):
        return float(anchor)
    name, src_t = anchor
    t0, src0 = cuts[name]
    return t0 + (src_t - src0)


def rel(name, dt, cuts):
    """dt seconds into a cut (rather than a recording time)."""
    return cuts[name][0] + dt


# ---------- sound ----------
SLOW = "asetrate=44100*{k},aresample=48000"


def sounds(cuts):
    """[(path, start, gain, filters, end or None, fade in, fade out, loop)] -- every sound placed on the timeline."""
    g = lambda f: os.path.join(SND, f)
    v6 = lambda f: os.path.join(VO6, f + ".mp3")
    R = lambda n, dt: rel(n, dt, cuts)
    S = []
    # the opening: wind over the kingdom, the river; the dungeon's stillness
    S += [(g("ambience/forest_day.ogg"), R("kingdom", 0.0) - 0.6, 0.55, "lowpass=f=2500", R("captive", 0.4), 1.2, 0.8, True),
          (g("ambience/river.ogg"), R("river", 0.0), 0.22, "lowpass=f=2400", R("captive", 0.3), 0.5, 0.6, True),
          (v6("muffled_a"), R("captive", 0.0), 0.35, "lowpass=f=320", R("rank", 0.0), 0.8, 0.6, True),     # a battle far above
          (g("tm_gate_close.wav"), R("captive", 0.25), 0.35, "lowpass=f=1500,aecho=0.8:0.7:180:0.4", None, 0, 0, False)]
    # the muster: a war horn, the gates, the march
    S += [(g("horn.wav"), R("rank", 0.15), 0.9, "aecho=0.8:0.6:260:0.35", None, 0, 0, False),
          (g("tm_gate_open.wav"), R("gates", 0.75), 0.9, "", None, 0, 0, False),
          (g("tm_gate_open.wav"), R("gates", 0.95), 0.7, "", None, 0, 0, False),
          (v6("battle_b"), R("pourout", 0.0), 0.35, "", R("clash", 0.2), 0.6, 0.6, True),
          (v6("roar_a"), R("line", 0.0), 0.75, "", R("clash", 0.4), 0.4, 0.5, False)]
    for k in range(6):
        S.append((g("tm_step_dirt_chain%d.wav" % (k % 5 + 1)), R("pourout", 0.1 + k * 0.62), 0.55, "", None, 0, 0, False))
    for k in range(5):
        S.append((g("tm_step_dirt_chain%d.wav" % ((k + 2) % 5 + 1)), R("line", k * 0.45), 0.7, "", None, 0, 0, False))
    # the freeze: the music gone, a blade drawn, a breath -- then everything at once
    frz = B_AT - FREEZE
    S += [(g("tm_unsheath1.wav"), frz + 0.02, 1.0, SLOW.format(k=0.7) + ",aecho=0.8:0.8:120:0.3", None, 0, 0, False),
          (v6("slowboom_a"), B_AT, 1.2, "", None, 0, 0, False),
          (g("tm_sword_hit1.wav"), B_AT, 1.2, SLOW.format(k=0.55), None, 0, 0, False),
          (g("tm_sword_hit3.wav"), B_AT + 0.05, 1.0, SLOW.format(k=0.5), None, 0, 0, False),
          (g("tm_land_dirt.wav"), B_AT + 1.1, 1.0, SLOW.format(k=0.6), None, 0, 0, False),
          (v6("battle_a"), B_AT + 1.0, 0.45, "", R("smash", 0.2), 1.5, 0.4, True)]
    # the montage
    S += [(g("hammerThrow.wav"), R("hammer", 0.22), 1.0, SLOW.format(k=0.6), None, 0, 0, False),
          (g("tm_rock_hit1.wav"), R("hammer", 0.58), 1.0, SLOW.format(k=0.55), None, 0, 0, False),
          (g("tm_sword_hit2.wav"), R("hammer", 0.92), 0.9, SLOW.format(k=0.55), None, 0, 0, False),
          (g("axe.wav"), R("whirl", 0.12), 1.0, SLOW.format(k=0.65), None, 0, 0, False),
          (g("tm_sword_swing1.wav"), R("whirl", 0.30), 0.9, SLOW.format(k=0.6), None, 0, 0, False),
          (g("tm_sword_hit3.wav"), R("whirl", 0.60), 0.9, SLOW.format(k=0.6), None, 0, 0, False),
          (g("magic.wav"), R("meteor", 0.0), 0.8, "", None, 0, 0, False),
          (g("meteor.wav"), R("meteor", 0.70), 1.1, SLOW.format(k=0.6), None, 0, 0, False),
          (v6("slowboom_b"), R("meteor", 1.72), 1.0, "", None, 0, 0, False),
          (g("tm_bomb_blast.wav"), R("meteor", 1.72), 1.0, SLOW.format(k=0.55), None, 0, 0, False),
          (g("tm_unsheath2.wav"), R("card16", 0.0), 0.9, "", None, 0, 0, False),
          (g("volley.wav"), R("volley", 0.65), 1.0, SLOW.format(k=0.7), None, 0, 0, False),
          (v6("arrows_a"), R("volley", 0.95), 0.8, "", None, 0, 0.4, False),
          (g("shadow.wav"), R("necro", 0.0), 0.9, SLOW.format(k=0.7), None, 0, 0, False),
          (g("energy.wav"), R("necro", 0.3), 0.6, "", None, 0, 0, False),
          (g("tm_bow_shot2.wav"), R("sniper", 0.22), 1.1, SLOW.format(k=0.5), None, 0, 0, False),
          (g("tm_bow_hit3.wav"), R("sniper", 0.55), 1.0, SLOW.format(k=0.55), None, 0, 0, False),
          (g("tm_jump_dirt.wav"), R("rogue", 0.0), 0.9, "", None, 0, 0, False),
          (g("tm_sword_hit1.wav"), R("rogue", 0.75), 1.0, SLOW.format(k=0.55), None, 0, 0, False),
          (g("shield.wav"), R("shield", 0.80), 1.0, "", None, 0, 0, False),
          (g("tm_sword_block2.wav"), R("shield", 0.92), 0.9, "", None, 0, 0, False),
          (g("tm_bow_hit2.wav"), R("shield", 1.10), 0.8, "", None, 0, 0, False),
          (g("tm_bomb_blast.wav"), R("gate", 1.55), 1.4, SLOW.format(k=0.6), None, 0, 0, False),
          (v6("slowboom_a"), R("gate", 1.55), 1.0, "", None, 0, 0, False),
          (g("tm_crumble1.wav"), R("gate", 1.70), 1.1, "", None, 0, 0, False)]
    # the dip: their cell door smashed in -- a heartbeat, the blow slowed right down
    S += [(v6("heart_a"), R("smash", 0.0), 1.2, "", R("runout", 0.0), 0.2, 0.3, False),
          (g("tm_gate_hit2.wav"), R("smash", 0.78), 1.3, SLOW.format(k=0.5), None, 0, 0, False),
          (g("tm_crumble2.wav"), R("smash", 0.85), 1.0, SLOW.format(k=0.6), None, 0, 0, False),
          (v6("roar_a"), R("runout", 0.0), 0.8, "", R("bridge", 0.8), 0.1, 0.6, False)]
    # the run home
    S += [(v6("battle_b"), R("bridge", 0.0), 0.4, "", R("throne", 0.3), 0.4, 0.6, True),
          (g("tm_step_wood_chain1.wav"), R("bridge", 0.1), 0.9, "", None, 0, 0, False),
          (g("tm_step_wood_chain3.wav"), R("bridge", 0.7), 0.9, "", None, 0, 0, False),
          (g("tm_step_wood_chain2.wav"), R("bridge", 1.3), 0.9, "", None, 0, 0, False),
          (g("hammerThrow.wav"), R("ambush", 0.05), 1.0, SLOW.format(k=0.6), None, 0, 0, False),
          (g("tm_rock_hit2.wav"), R("ambush", 0.80), 1.0, SLOW.format(k=0.55), None, 0, 0, False),
          (g("tm_gate_open.wav"), R("home", 0.0), 0.8, "", None, 0, 0, False)]
    # the throne: the rise, a reversed whoosh into the hit, the slam; then the rope creaking each time he swings back
    v7 = lambda f: os.path.join(VO, f + ".mp3")
    S += [(g("tm_step_stone_chain1.wav"), R("throne", 0.0), 0.8, SLOW.format(k=0.7), None, 0, 0, False),
          (v7("slam_3"), TITLE - 3.1, 0.42, "", TITLE + 0.02, 1.2, 0.05, False),
          (v6("slowboom_b"), TITLE, 1.1, "", None, 0, 0, False),
          (g("tm_crumble2.wav"), TITLE + 0.03, 0.5, "lowpass=f=1800", None, 0, 0, False)]
    # (the King's swing: amplitude 7 + 19 e^(-t/1.5) degrees, period 2.8 s -- trailer7_finish.Title.king_angle)
    import math
    for n in range(8):
        tt = 0.7 + 1.4 * n
        amp = 7.0 + 19.0 * math.exp(-tt / 1.5)
        rate = 0.92 + 0.08 * (n % 3)
        st = TITLE + tt - 0.35
        S.append((v7("creak_3"), st, round(0.55 * amp / 26.0, 3),
                  "atrim=0.15:1.2,asetpts=PTS-STARTPTS," + SLOW.format(k=rate), st + 1.0, 0.05, 0.25, False))
    # the freeze: a held breath under the silence
    S.append((v7("freeze_3"), A_STOP - 0.05, 0.8, "", B_AT + 0.04, 0.06, 0.08, False))
    return S


MUSIC = [("musA_3", 0.0, 0.0, A_STOP, 0.95, 0.0, 0.03),      # (file, at, from, to (file seconds), gain, fade in, out)
         ("musB_1", B_AT, 0.0, None, 0.9, 0.0, 0.0),
         ("musC_3", TITLE - C_HIT, 0.0, None, 1.0, 0.0, 1.5)]


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(r.stderr[-2500:])


def dur(p):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p],
                         capture_output=True, text=True).stdout.strip()
    try:
        return float(out)
    except ValueError:                  # (a recording still being written)
        return 0.0


def segments(only=None):
    rows, _, _ = plan()
    for k, shot, src, d, name, t0 in rows:
        out = f"{T}/seg7_{k:02d}_{name}.mp4"
        if os.path.exists(out) or (only and shot not in only) or d <= 0:
            continue
        n = int(round(d * FPS))
        path = f"{T}/{shot}.avi"
        if shot == "black" or not os.path.exists(path) or dur(path) <= 0.0:
            run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"color=c=black:s=1920x1080:r={FPS}:d={d + 0.2:.3f}",
                 "-frames:v", str(n), "-c:v", "libx264", "-crf", "14", "-pix_fmt", "yuv420p", out])
            print("SEG", k, name, "(black)" if shot == "black" else "(stand-in)")
            continue
        avail = dur(path) - src
        vf = f"fps={FPS},scale=1920:1080:flags=lanczos,setsar=1"
        if avail < d:
            vf += f",tpad=stop_mode=clone:stop_duration={d - avail + 0.1:.3f}"
            print("  (short by %.2f s: last frame held)" % (d - avail))
        run(["ffmpeg", "-v", "error", "-y", "-ss", f"{src:.3f}", "-i", path, "-vf", vf, "-an", "-frames:v", str(n),
             "-c:v", "libx264", "-crf", "14", "-preset", "medium", "-pix_fmt", "yuv420p", out])
        print("SEG", k, name, round(dur(out), 2), "at", round(t0, 2))


def cut():
    rows, cuts, total = plan()
    lst = f"{T}/concat.txt"
    with open(lst, "w") as f:
        for k, shot, src, d, name, t0 in rows:
            if d > 0:
                f.write(f"file '{T}/seg7_{k:02d}_{name}.mp4'\n")
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", f"{T}/cut.mp4"])
    cards = []
    for c in CARDS:
        t0 = at(c["at"], cuts)
        cards.append({"text": c["text"], "t0": t0, "t1": t0 + c["dur"], "size": c.get("size", 72), "snap": c.get("snap", False)})
    p = {"total": total, "title": cuts["title"][0], "cards": cards, "fade_in_start": A_BOOMS[0] - 0.05, "fade_in_end": A_BOOMS[0] + 0.9}
    json.dump(p, open(f"{T}/plan.json", "w"), indent=1)
    print("CUT", f"{T}/cut.mp4", round(dur(f"{T}/cut.mp4"), 2), "planned", round(total, 2))


def mix(out_wav):
    rows, cuts, total = plan()
    inputs, fc = [], []
    j = 0

    def place(label, path, start, ss, end, gain, flt, fin, fout, loop=False):
        nonlocal j
        if loop:
            inputs.extend(["-stream_loop", "-1"])
        if ss > 0:
            inputs.extend(["-ss", f"{ss:.3f}"])
        inputs.extend(["-i", path])
        chain = [flt] if flt else []
        chain += ["aresample=48000", "aformat=sample_fmts=fltp:channel_layouts=stereo"]
        if end is not None:
            chain.append(f"atrim=0:{end - start:.3f}")
            if fout > 0:
                chain.append(f"afade=t=out:st={max(0.0, end - start - fout):.3f}:d={fout:.3f}")
        elif fout > 0:
            chain.append(f"afade=t=out:st={max(0.0, dur(path) - ss - fout):.3f}:d={fout:.3f}")
        if fin > 0:
            chain.append(f"afade=t=in:st=0:d={fin:.3f}")
        st = max(0.0, start)
        chain += [f"volume={gain}", f"adelay={int(st * 1000)}|{int(st * 1000)}"]
        fc.append(f"[{j}:a]{','.join(chain)}[{label}]")
        j += 1
        return f"[{label}]"

    mus = []
    for i, (f, t0, a0, a1, gain, fi, fo) in enumerate(MUSIC):
        end = None if a1 is None else t0 + (a1 - a0)
        mus.append(place(f"m{i}", os.path.join(VO, f + ".mp3"), t0, a0, end, gain, "", fi, fo))
    sfx = []
    for i, (path, start, gain, flt, end, fi, fo, loop) in enumerate(sounds(cuts)):
        sfx.append(place(f"s{i}", path, start, 0.0, end, gain, flt, fi, fo, loop))
    pad = f"apad=whole_dur={total:.3f}"
    fc.append(f"{''.join(mus)}amix=inputs={len(mus)}:normalize=0,{pad}[mus]")
    fc.append(f"{''.join(sfx)}amix=inputs={len(sfx)}:normalize=0,{pad}[sfx]")
    fc.append(f"[mus][sfx]amix=inputs=2:normalize=0,alimiter=limit=0.9:level=disabled,atrim=0:{total:.3f}[mix]")
    run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(fc), "-map", "[mix]", "-c:a", "pcm_f32le", out_wav])
    print("MIX", out_wav, round(total, 2))


def final(out):
    rows, cuts, total = plan()
    wav = f"{T}/mix.wav"
    mix(wav)
    video = f"{T}/finished.mkv"
    r = subprocess.run(["ffmpeg", "-v", "info", "-i", wav, "-af", "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json",
                        "-f", "null", "-"], capture_output=True, text=True).stderr
    m = json.loads(r[r.rindex("{"):r.rindex("}") + 1])
    ln = ("loudnorm=I=-14:TP=-1.5:LRA=11:linear=true:measured_I={input_i}:measured_TP={input_tp}:measured_LRA={input_lra}:"
          "measured_thresh={input_thresh}:offset={target_offset}").format(**m)
    run(["ffmpeg", "-v", "error", "-y", "-i", video, "-i", wav, "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-crf", "18",
         "-preset", "slow", "-maxrate", "14M", "-bufsize", "28M", "-pix_fmt", "yuv420p",
         "-af", ln + ",aresample=48000", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", "-t", f"{total:.3f}", out])
    print(json.dumps({"total": round(total, 2), "input_lufs": m["input_i"], "title": round(TITLE, 2), "impact": round(B_AT, 2),
                      "cuts": [[name, round(t0, 2)] for _, _, _, _, name, t0 in rows]}))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", choices=["segments", "cut", "mix", "final", "plan"], required=True)
    ap.add_argument("--out", default="/mnt/user-data/outputs/Fatebound-Trailer-7.mp4")
    ap.add_argument("--only", default="", help="segments: only these runs (comma-separated)")
    a = ap.parse_args()
    if a.stage == "segments":
        segments([x for x in a.only.split(",") if x])
    elif a.stage == "cut":
        cut()
    elif a.stage == "mix":
        mix(f"{T}/mix.wav")
    elif a.stage == "final":
        final(a.out)
    else:
        rows, cuts, total = plan()
        for k, shot, src, d, name, t0 in rows:
            print(f"{t0:6.2f}  {name:9s} {shot:8s} src {src:6.2f} +{d:.2f}")
        print("total", round(total, 2), "impact", round(B_AT, 2), "title", round(TITLE, 2), "dip", round(B_AT + B_DIP[0], 2),
              round(B_AT + B_DIP[1], 2))
