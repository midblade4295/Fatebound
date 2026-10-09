#!/usr/bin/env python3
"""Fatebound trailer 6 -- "Anyone Can Change Fate" -- the cut and the mix.

The four staged runs (tools/trailer6_shots.gd -> /tmp/trailer6/<run>.avi) are cut back to back by CUTS; every sound is
placed on a shot (cut name + a time in that run's recording), so trimming a cut keeps the sounds on their pictures. The
gold title is trailer 4's "golden" shot with its light pass (/tmp/trailer6/golden_fx.mp4).

Music (ElevenLabs, written for the trailer): A carries the courtyard and the run and stops dead on the meteor; B starts
under the ringing, almost silent, and builds through the rally to the throw, where it cuts for the heartbeat; C hits with
the gate and carries the breach into the title. The narrator's lines are in tools/trailer6_script.md.

    python3 tools/trailer6_edit.py --stage segments     # each shot trimmed to its cut (resumable: delete to redo)
    python3 tools/trailer6_edit.py --stage final --out /mnt/user-data/outputs/Fatebound-Trailer-6.mp4
    python3 tools/trailer6_edit.py --stage audio --out ...   # keep the video, rebuild the mix
"""
import argparse, json, os, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
VO = os.path.join(HERE, "trailer6_vo")
SND = os.path.join(HERE, "..", "assets", "sounds")
T = "/tmp/trailer6"
FPS = 30

# (run, source start in its recording, seconds on screen, name) -- back to back from 0. Recording times are video seconds
# (the slow-motion windows of trailer6_shots.gd are already stretched in the recordings).
CUTS = [
    ("court", 0.30, 4.30, "wide"),        # the courtyard: villagers take hats
    ("court", 4.60, 5.00, "shove"),       # a Knight, then a Barbarian, shove him aside
    ("court", 9.80, 3.80, "cower"),       # the villagers who hide (a far-off blast at 11.6)
    ("court", 14.00, 3.00, "bomb"),       # the bomb
    ("court", 17.00, 3.20, "face"),       # mustering the courage
    ("court", 20.20, 3.00, "pickup"),
    ("court", 23.20, 4.25, "out"),        # out of the gate into the battle
    ("run", 0.20, 4.60, "track"),         # war-movie tracking under arrows
    ("run", 5.40, 3.60, "front"),         # (from the bridge on: one of our archers crosses the lens before)
    ("fall", 0.30, 1.00, "approach"),     # him running (the red Archmage far off on the right)
    # (Kevin: "it looks like he's the one that blew them up" -- so where it comes from is shown: the Archmage, close,
    #  raises his staff, a fireball gathers on it, he hurls it; the camera chases it down onto the hero's friends)
    ("fall", 1.30, 1.133, "mage"),        # staff up (1.32), the fire gathering, the throw (2.40)
    ("fall", 2.433, 1.867, "chase"),      # after it, down onto them (slow motion)
    ("fall", 4.30, 6.50, "blast"),        # slower: it streaks down into the frame (lands 4.90); his friends thrown, he goes down
    ("fall", 18.07, 3.80, "down"),        # on his back, ears ringing
    ("fall", 22.22, 2.40, "rise"),
    ("fall", 24.62, 1.80, "pov"),         # their gate -- the snap zoom
    ("fall", 26.42, 3.85, "again"),       # the bomb again
    ("charge", 0.00, 2.25, "rally"),      # his allies fall in round him
    ("charge", 2.25, 2.45, "hammer"),     # slow motion: the Crusader's hammer
    ("charge", 4.72, 1.10, "rogue"),      # the Rogue's leap, the Archer's shot
    ("charge", 5.82, 0.80, "spin"),       # the Berserker
    ("charge", 6.62, 0.95, "shield"),     # arrows from the wall on a Knight's shield
    ("charge", 7.57, 1.38, "throw"),      # released at 7.82
    ("charge", 8.95, 2.27, "flight"),     # the heartbeat
    ("charge", 11.23, 4.00, "boom"),      # it goes off at 12.00; our men run into the smoke
    ("charge", 17.07, 2.70, "hat"),       # a Knight tosses him a helmet (it's on at 18.87)
    ("charge", 20.07, 2.40, "crane"),     # everyone in through the gate
    ("golden", 0.00, 10.00, "title"),     # the title lands at 4.90
]
IMPACT = ("blast", 4.90)     # the meteor lands
RELEASE = ("throw", 7.82)    # the bomb leaves his hand
BOOM = ("boom", 12.00)       # the gate goes up
LAND = ("title", 4.90)       # the title lands (the flash; "FATEBOUND" is spoken on it)

# Narrator (raw/l*.mp3, the takes picked) at (cut, recording time)
LINES = [("l1_a", ("wide", 1.20)),       # Every army has its heroes...
         ("l2_a", ("shove", 8.35)),      # ...and everyone else.
         ("l3_a", ("cower", 10.20), 2.0),  # No hat. No sword. No one expecting a thing.
         ("l4_a", ("face", 17.70), 1.5),  # But courage doesn't need a helmet.
         ("l5_a", ("down", 20.77)),      # Get up.
         ("l67_a", ("pov", 24.52)),      # Sometimes the one who changes everything is the one nobody saw coming.
         ("l8_b", ("rally", 0.40), 2.0),  # One brave step, and the whole army follows.
         ("l9_a", ("hat", 17.95), 7.0),  # Everyone makes a difference.          (+dB: over cue C, Kevin: "the end
         ("l10_a", ("title", 1.10), 8.0),  # Anyone can change fate.             lines are too quiet to hear")
         ("l11_a", ("title", 4.80), 6.0)]  # FATEBOUND
# The music under a line (Kevin: a plain dip "is too noticeable at the end"): only its voice band (800-4000 Hz) dips
# much (x0.4) and the whole of it a little (x0.85), over slow 0.6 s ramps, so the drums and the low end carry on
# under the narrator -- about 3-4 dB in all. The last lines are louder instead. The beds dip x0.5.
DIP_MID, DIP_MID_C = 0.4, 0.35
DIP, DIP_C = 0.88, 0.88
RAMP = 0.6
VO_MEAN = -16.5           # each line brought to this mean level (dB) -- the takes vary by 10 dB; the VO bus is limited

# Music: (file, start, end, gain, fade in, fade out); start/end are cut anchors.
MUSIC = [("musA_a", ("wide", 0.30), IMPACT, 0.80, 0.0, 0.12),
         ("musB_b", IMPACT, RELEASE, 0.95, 0.0, 0.12),    # (its tail goes on under water: SFX)
         ("musC_b", BOOM, None, 0.68, 0.0, 0.0)]       # (a touch lower all through: room for the last lines)

# Sound design: (file, at, gain, filters, until (anchor, loops it) or None, fade in, fade out). Game sounds from
# assets/sounds; beds and stingers from trailer6_vo/raw.
SLOW = "asetrate=44100*{k},aresample=48000"
SFX = [
    ("raw/muffled_a.mp3", ("wide", 0.30), 0.55, "", ("out", 25.0), 0.8, 1.5),        # the battle beyond the walls
    ("tm_land_dirt.wav", ("shove", 6.02), 1.4, "", None, 0, 0),                        # shoved
    ("tm_land_dirt.wav", ("shove", 7.77), 1.4, "", None, 0, 0),
    ("tm_bomb_blast.wav", ("cower", 11.50), 0.2, "lowpass=f=700", None, 0, 0),         # a far-off blast: they flinch
    ("land.wav", ("pickup", 21.45), 0.8, "", None, 0, 0),
    ("raw/battle_a.mp3", ("out", 24.30), 0.75, "", IMPACT, 1.0, 0.1),                  # out in it
    ("raw/arrows_a.mp3", ("track", 1.00), 0.9, "", None, 0, 0),
    ("tm_sword_hit1.wav", ("track", 2.40), 0.8, "", None, 0, 0),
    ("raw/arrows_b.mp3", ("front", 5.60), 0.8, "", None, 0, 0),
    ("tm_sword_hit3.wav", ("front", 6.30), 0.8, "", None, 0, 0),
    # The Archmage's fireball: power gathering on the staff, the crackle of it, the throw (the game's own meteor-cast
    # sound), then its rush through the air, slowed with the picture.
    ("surge.wav", ("mage", 1.62), 0.75, "", None, 0.15, 0.3),
    ("tm_firespray1.wav", ("mage", 1.75), 0.55, "lowpass=f=3500", None, 0.3, 0.3),
    ("tm_fireball1.wav", ("mage", 2.38), 1.2, "", None, 0, 0),
    ("meteor.wav", ("chase", 2.45), 1.0, SLOW.format(k=0.6), None, 0, 0.3),
    ("tm_firespray2.wav", ("chase", 2.50), 0.7, SLOW.format(k=0.55), None, 0.2, 0.4),
    ("raw/slowboom_a.mp3", IMPACT, 1.5, "", None, 0, 0),                              # the meteor, slowed
    ("tm_bomb_blast.wav", IMPACT, 1.2, SLOW.format(k=0.45), None, 0, 0),
    ("raw/ring_a.mp3", ("blast", 5.20), 0.75, "", None, 0.4, 2.5),                     # ears ringing
    ("raw/muffled_b.mp3", ("blast", 5.70), 0.40, "lowpass=f=500", ("down", 20.67), 3.0, 1.5),   # (gone by "Get up")
    ("raw/battle_a.mp3", ("rally", 0.00), 0.40, "", RELEASE, 1.5, 0.3, 12.0),        # the battle again, from the rally
    #   (Kevin: no soldiers' sounds as he gets up -- nothing from "Get up" to the rally but the music)
    ("hammerThrow.wav", ("hammer", 2.40), 0.9, SLOW.format(k=0.6), None, 0, 0),
    ("tm_sword_hit2.wav", ("hammer", 3.13), 1.0, SLOW.format(k=0.6), None, 0, 0),
    ("tm_rock_hit1.wav", ("hammer", 3.13), 1.0, SLOW.format(k=0.5), None, 0, 0),
    ("tm_bow_shot1.wav", ("rogue", 4.82), 1.0, "", None, 0, 0),
    ("tm_bow_hit1.wav", ("rogue", 5.14), 1.1, "", None, 0, 0),
    ("axe.wav", ("spin", 5.87), 1.0, "", None, 0, 0),
    ("tm_sword_hit3.wav", ("spin", 6.10), 0.9, "", None, 0, 0),
    ("shield.wav", ("shield", 6.87), 1.0, "", None, 0, 0),
    ("tm_bow_hit2.wav", ("shield", 7.00), 0.9, "", None, 0, 0),
    ("tm_rock_throw1.wav", RELEASE, 1.2, SLOW.format(k=0.6), None, 0, 0),
    # The throw (Kevin: "it cuts off too abruptly"): no hard stop -- cue B sinks under water (low-passed, echoing,
    # fading by the boom), the battle goes on muffled, the fuse fizzes, the heartbeat, and a reversed boom swells
    # into the real one.
    ("raw/musB_b.mp3", RELEASE, 0.9, "lowpass=f=450,aecho=0.8:0.85:120|260:0.45|0.3", BOOM, 0.05, 2.8, (IMPACT, RELEASE)),
    ("raw/battle_b.mp3", ("throw", 7.60), 0.8, "lowpass=f=380", BOOM, 0.5, 0.2, 3.0),
    ("tm_firespray1.wav", RELEASE, 0.9, SLOW.format(k=0.6), None, 0, 0),             # the fuse catching
    ("tm_firespray2.wav", ("flight", 9.90), 0.8, SLOW.format(k=0.6), None, 0, 0),
    ("raw/heart_a.mp3", ("throw", 7.70), 1.5, "", BOOM, 0.2, 0.05),                  # a heartbeat
    ("raw/slowboom_b.mp3", ("boom", 7.97), 0.75, "areverse,atrim=start=2.0,asetpts=PTS-STARTPTS,afade=t=in:d=3.2:curve=exp",
     None, 0, 0),
    ("land.wav", ("boom", 11.25), 0.8, "lowpass=f=900", None, 0, 0),                # it lands at the gate
    ("tm_bomb_blast.wav", BOOM, 1.6, SLOW.format(k=0.7), None, 0, 0),
    ("raw/slowboom_b.mp3", BOOM, 1.3, "", None, 0, 0),
    ("tm_crumble1.wav", ("boom", 12.15), 1.2, "", None, 0, 0),                         # the gate
    ("raw/roar_a.mp3", ("boom", 13.60), 0.9, "", ("hat", 17.85), 0.3, 1.2),            # the army goes in
    ("equip.wav", ("hat", 18.87), 1.0, "", None, 0, 0),                                # the helmet on
]


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(r.stderr[-2500:])


def dur(p):
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p],
                                capture_output=True, text=True).stdout.strip())


def levels(p):
    r = subprocess.run(["ffmpeg", "-v", "info", "-i", p, "-af", "volumedetect", "-f", "null", "-"], capture_output=True,
                       text=True).stderr
    mean = float(r.split("mean_volume: ")[1].split(" dB")[0])
    peak = float(r.split("max_volume: ")[1].split(" dB")[0])
    return mean, peak


def speech(p):
    # seconds of the take up to its last sound above -40 dB (the takes have a little room tone after the words)
    r = subprocess.run(["ffmpeg", "-v", "info", "-i", p, "-af", "areverse,silencedetect=n=-40dB:d=0.05", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    tail = float(r.split("silence_end: ")[1].split()[0]) if "silence_end: " in r else 0.0
    return dur(p) - tail


def vo_gain(p):
    mean, peak = levels(p)
    return 10 ** ((VO_MEAN - mean) / 20.0)


def plan():
    t, out = 0.0, {}
    rows = []
    for k, (shot, src, d, name) in enumerate(CUTS):
        d = round(d * FPS) / FPS                # (whole frames, as the segments are cut)
        rows.append((k, shot, src, d, name, t))
        out[name] = (t, src)
        t += d
    return rows, out, t


def at(anchor, cuts):
    if anchor is None:
        return None
    name, src_t = anchor
    t0, src0 = cuts[name]
    return t0 + (src_t - src0)


def source(shot):
    return f"{T}/golden_fx.mp4" if shot == "golden" else f"{T}/{shot}.avi"


def segments(only=None):
    rows, _, _ = plan()
    for k, shot, src, d, name, t0 in rows:
        out = f"{T}/seg6_{k:02d}_{name}.mp4"
        if os.path.exists(out) or (only and shot not in only):
            continue
        path = source(shot)
        n = int(round(d * FPS))
        if not os.path.exists(path):        # (a stand-in so a draft cuts together before the title is rendered)
            run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"color=c=0x201008:s=1920x1080:r={FPS}:d={d:.3f}",
                 "-frames:v", str(n), "-c:v", "libx264", "-crf", "16", "-pix_fmt", "yuv420p", out])
            print("SEG", k, name, "(stand-in)")
            continue
        avail = dur(path) - src
        vf = f"fps={FPS},scale=1920:1080:flags=lanczos,setsar=1"
        if avail < d:
            vf += f",tpad=stop_mode=clone:stop_duration={d - avail + 0.1:.3f}"
        run(["ffmpeg", "-v", "error", "-y", "-ss", f"{src:.3f}", "-i", path, "-vf", vf, "-an", "-frames:v", str(n),
             "-c:v", "libx264", "-crf", "16", "-preset", "medium", "-pix_fmt", "yuv420p", out])
        print("SEG", k, name, round(dur(out), 2), "at", round(t0, 2))


def final(out, audio_only=False, mix_only=False):
    rows, cuts, total = plan()
    inputs, fc = [], []
    if mix_only:                    # just the soundtrack, as a wav (to check the mix without the picture)
        pass
    elif audio_only:
        src = out + ".video.mp4"
        os.replace(out, src)
        inputs += ["-i", src]
    else:
        for k, shot, src, d, name, t0 in rows:
            inputs += ["-i", f"{T}/seg6_{k:02d}_{name}.mp4"]
        fc.append("".join(f"[{k}:v]" for k in range(len(rows))) + f"concat=n={len(rows)}:v=1:a=0[vout]")
    j = 0 if mix_only else 1 if audio_only else len(rows)
    ms = 1000

    mute = os.environ.get("MIXMUTE", "")       # (checking the mix: silences parts -- "vo", "mus", "sfx", "bg" = both)

    def place(label, path, start, end, gain, flt, fin, fout, loop=False, ss=0.0):
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
        if fin > 0:
            chain.append(f"afade=t=in:st=0:d={fin:.3f}")
        if fout > 0 and end is None:
            chain.append(f"afade=t=out:st={max(0.0, dur(path) - fout):.3f}:d={fout:.3f}")
        chain += [f"volume={gain}", f"adelay={int(start * ms)}|{int(start * ms)}"]
        fc.append(f"[{j}:a]{','.join(chain)}[{label}]")
        j += 1
        return f"[{label}]"

    mus = [place(f"m{i}", os.path.join(VO, "raw", f + ".mp3"), at(a, cuts), at(b, cuts), g, "", fi, fo)
           for i, (f, a, b, g, fi, fo) in enumerate(MUSIC)]
    vos, dips, lifts = [], [], []
    for i, (f, a, *extra) in enumerate(LINES):
        path = os.path.join(VO, "raw", f + ".mp3")
        vos.append(place(f"v{i}", path, at(a, cuts), None, round(vo_gain(path), 3), "", 0, 0))
        t0 = at(a, cuts)
        if extra:                                # a line's own lift goes on after the VO bus's compressor
            lifts.append((t0 - 0.1, t0 + speech(path) + 0.2, 10 ** (extra[0] / 20.0)))
        late = t0 >= at(BOOM, cuts)
        dips.append((t0 - 0.35, t0 + speech(path) + 0.3, DIP_C if late else DIP, DIP_MID_C if late else DIP_MID)
                    if not os.environ.get("NODIP") else (t0, t0 + 0.1, 1.0, 1.0))      # (NODIP: to measure the dips)
    sfx = []
    for i, (f, a, g, flt, until, fi, fo, *src) in enumerate(SFX):
        path = os.path.join(VO, f) if f.startswith("raw/") else os.path.join(SND, f)
        ss = 0.0
        if src:                                  # where in the file it starts: seconds, or the gap between two anchors
            ss = src[0] if isinstance(src[0], (int, float)) else at(src[0][1], cuts) - at(src[0][0], cuts)
        sfx.append(place(f"s{i}", path, at(a, cuts), at(until, cuts), g, flt, fi, fo, loop=until is not None and not src,
                         ss=ss))
    pad = f"apad=whole_dur={total:.3f}"
    # The music dips under each line (the sidechain alone left the last lines buried in cue C), ramped over 0.25 s.
    def dip_expr(k):
        # product of ramped dips; k picks the gain from each dip tuple (2 = broadband, 3 = voice band, None = beds)
        return "*".join(f"(1-{1 - (d[k] if k else 0.5):.2f}*min(clip((t-{d[0] - RAMP / 2:.2f})/{RAMP},0,1),"
                        f"clip(({d[1] + RAMP / 2:.2f}-t)/{RAMP},0,1)))" for d in dips)
    fc.append(f"{''.join(mus)}amix=inputs={len(mus)}:normalize=0,{pad},volume='{dip_expr(2)}':eval=frame,"
              f"acrossover=split=800 4000[mlo][mmid][mhi]")
    fc.append(f"[mmid]volume='{dip_expr(3)}':eval=frame[mmid2]")
    fc.append("[mlo][mmid2][mhi]amix=inputs=3:normalize=0[mus]")
    lift = "+".join(f"{g - 1:.3f}*between(t,{a0:.2f},{b0:.2f})" for a0, b0, g in lifts) or "0"
    fc.append(f"{''.join(vos)}amix=inputs={len(vos)}:normalize=0,acompressor=threshold=0.18:ratio=2.5:attack=5:release=120,"
              f"{pad},volume='1+{lift}':eval=frame,alimiter=limit=0.89:level=disabled[vos]")      # (lines never overlap)
    fc.append(f"{''.join(sfx)}amix=inputs={len(sfx)}:normalize=0,{pad},volume='{dip_expr(None)}':eval=frame[sfx]")   # (beds too)
    fc.append("[vos]anull[vosb]")
    fc.append("[mus]anull[duck]")             # (no sidechain any more: its fast pumping on every word was what showed)
    off = set(mute.replace("bg", "mus,sfx").split(","))
    fc.append(f"[duck]volume={0 if 'mus' in off else 1}[duck2];[sfx]volume={0 if 'sfx' in off else 1}[sfx2];"
              f"[vosb]volume={0 if 'vo' in off else 1}[vosc]")
    fc.append(f"[duck2][vosc][sfx2]amix=inputs=3:normalize=0,alimiter=limit=0.9:level=disabled,atrim=0:{total:.3f}[mix]")
    # 1) the mix (and the concatenated picture) as an intermediate, 2) its loudness measured, 3) normalised and muxed
    mix = out if mix_only else out + ".mix.wav"
    cmd = ["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(fc), "-map", "[mix]", "-c:a", "pcm_f32le", mix]
    if mix_only:
        run(cmd)
        print("MIX", out, round(total, 2))
        return
    if audio_only:
        video = out + ".video.mp4"
    else:
        video = out + ".video.mkv"
        cmd += ["-map", "[vout]", "-c:v", "libx264", "-crf", "19", "-maxrate", "12M", "-bufsize", "24M", "-preset", "slow", "-pix_fmt", "yuv420p", video]
    run(cmd)
    # loudness: measure, then bring it to -14 LUFS with a true-peak limit
    r = subprocess.run(["ffmpeg", "-v", "info", "-i", mix, "-af", "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json",
                        "-f", "null", "-"], capture_output=True, text=True).stderr
    m = json.loads(r[r.rindex("{"):r.rindex("}") + 1])
    ln = ("loudnorm=I=-14:TP=-1.5:LRA=11:linear=true:measured_I={input_i}:measured_TP={input_tp}:measured_LRA={input_lra}:"
          "measured_thresh={input_thresh}:offset={target_offset}").format(**m)
    run(["ffmpeg", "-v", "error", "-y", "-i", video, "-i", mix, "-map", "0:v", "-map", "1:a", "-c:v", "copy",
         "-af", ln + ",aresample=48000", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", out])
    os.remove(mix)
    os.remove(video)
    print(json.dumps({"total": round(total, 2), "input_lufs": m["input_i"],
                      "cuts": [[name, round(t0, 2)] for _, _, _, _, name, t0 in rows],
                      "impact": round(at(IMPACT, cuts), 2), "release": round(at(RELEASE, cuts), 2),
                      "boom": round(at(BOOM, cuts), 2), "title_lands": round(at(LAND, cuts), 2),
                      "lines": [[f, round(at(a, cuts), 2)] for f, a, *_ in LINES]}))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", choices=["segments", "final", "audio", "mix", "plan"], required=True)
    ap.add_argument("--out", default="/mnt/user-data/outputs/Fatebound-Trailer-6.mp4")
    ap.add_argument("--only", default="", help="segments: only these runs (comma-separated), e.g. court,run")
    a = ap.parse_args()
    if a.stage == "segments":
        segments([x for x in a.only.split(",") if x])
    elif a.stage == "plan":
        rows, cuts, total = plan()
        for k, shot, src, d, name, t0 in rows:
            print(f"{t0:6.2f}  {name:9s} {shot:7s} {src:6.2f} +{d:.2f}")
        print("total", round(total, 2), "impact", round(at(IMPACT, cuts), 2), "release", round(at(RELEASE, cuts), 2),
              "boom", round(at(BOOM, cuts), 2), "title lands", round(at(LAND, cuts), 2))
        for f, a2, *_ in LINES:
            print("  ", f, round(at(a2, cuts), 2))
    else:
        final(a.out, audio_only=a.stage == "audio", mix_only=a.stage == "mix")
