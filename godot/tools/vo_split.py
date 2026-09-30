#!/usr/bin/env python3
"""Split one continuous tutorial voiceover read into per-line files (assets/vo/tutorial/<id>.ogg).

    python3 tools/vo_split.py FULL_READ.mp3 [--out assets/vo/tutorial] [--dry-run]

The read must contain the 36 lines of assets/vo/tutorial/SCRIPT.md in order. Pauses between lines
don't need to be longer than pauses inside lines: the cuts are chosen among all pauses so every
piece's length best fits its line's text length (dynamic programming), preferring longer pauses.
Each piece is then checked by blind speech recognition (PocketSphinx, English model bundled with
`pip install pocketsphinx`): its words must match its own line far better than its neighbours'.
Flagged pieces are reported and nothing is written unless every piece passes.
Export: one shared gain to -16 LUFS for the whole read (keeps the delivery's dynamics), limiter at
-1.5 dB, 10 ms / 60 ms fades, mono 44.1 kHz OGG Vorbis q5. Needs ffmpeg with libvorbis.
"""
import argparse
import json
import os
import re
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "assets", "vo", "tutorial", "SCRIPT.md")
STOP = set("a an the to of and or it is in on at i i'm you your our we us her she he they them their that "
           "this that's it's for with be are was not no yes so but as if by from up out into all just very well".split())


def script_rows():
    rows = []
    for line in open(SCRIPT, encoding="utf-8"):
        m = re.match(r"^\| (\d+) \| `([a-z_0-9]+)` \| [^|]+ \| (.+) \|\s*$", line)
        if m:
            rows.append((int(m.group(1)), m.group(2), m.group(3).replace("\\|", "|")))
    return rows


def words(t):
    return [w.strip("'") for w in re.findall(r"[a-z']+", t.lower().replace("\u2019", "'")) if w.strip("'")]


def pauses(path, total):
    err = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af", "silencedetect=noise=-40dB:d=0.3", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    st = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", err)]
    en = [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", err)]
    lead = en[0] if st and st[0] < 0.05 else 0.0
    tail = st[-1] if en and en[-1] >= total - 0.05 else total
    gaps = [(s, e) for s, e in zip(st, en) if s > 0.05 and e < total - 0.05]
    return lead, tail, gaps


def choose_cuts(rows, lead, tail, gaps):
    chars = [len(t) for _, _, t in rows]
    n, g = len(rows), len(gaps)
    starts = [lead] + [e for _, e in gaps]
    ends = [s for s, _ in gaps] + [tail]
    speech = (tail - lead) - sum(sorted(e - s for s, e in gaps)[-(n - 1):])
    exp = [speech * c / sum(chars) for c in chars]
    inf = float("inf")

    def cost(i, j, k):
        d = ends[j] - starts[i]
        if d <= 0:
            return inf
        c = ((d - exp[k]) / exp[k]) ** 2
        return c - 0.6 * (gaps[j][1] - gaps[j][0]) if j < g else c

    dp = [[inf] * (g + 1) for _ in range(n + 1)]
    back = [[-1] * (g + 1) for _ in range(n + 1)]
    for j in range(g + 1):
        dp[1][j] = cost(0, j, 0)
    for k in range(2, n + 1):
        for j in range(g + 1):
            for i in range(j):
                if dp[k - 1][i] < inf:
                    c = dp[k - 1][i] + cost(i + 1, j, k - 1)
                    if c < dp[k][j]:
                        dp[k][j], back[k][j] = c, i
    cuts, j = [], g
    for k in range(n, 0, -1):
        cuts.append(j)
        j = back[k][j]
    cuts.reverse()
    segs, prev = [], -1
    for k in range(n):
        segs.append({"n": rows[k][0], "id": rows[k][1], "start": starts[prev + 1], "end": ends[cuts[k]],
                     "exp": exp[k]})
        prev = cuts[k]
    return segs


PRON = {"ahem": "AH HH EH M", "bards": "B AA R D Z", "fatebound": "F EY T B AW N D", "peckish": "P EH K IH SH"}


def refine_cuts(rows, segs, path, gaps):
    # Each boundary, left to right: force-align the two lines' text over their two pieces (the union
    # holds both lines even when the length-fit cut drifted by a sentence) and move the cut into the
    # pause between the last word of one and the first word of the next. (The 17-line re-record put
    # "Rescue him three times..." at the end of the piece before it; the word check didn't catch it.)
    from pocketsphinx import Decoder
    raw = tempfile.NamedTemporaryFile(suffix=".raw", delete=False).name
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ac", "1", "-ar", "16000", "-f", "s16le", raw], check=True)
    audio = open(raw, "rb").read()
    os.unlink(raw)
    d = Decoder(samprate=16000)
    for w, ph in PRON.items():
        if d.lookup_word(w) is None:
            d.add_word(w, ph, True)
    moved = 0
    for i in range(len(segs) - 1):
        a, b = segs[i]["start"], segs[i + 1]["end"]
        wa, wb = words(rows[i][2]), words(rows[i + 1][2])
        d.set_align_text(" ".join(wa + wb))
        d.start_utt()
        d.process_raw(audio[int(a * 16000) * 2:int(b * 16000) * 2], full_utt=True)
        d.end_utt()
        # The forced hypothesis's word segmentation carries the timings (get_alignment() stays empty
        # without a second alignment pass in this PocketSphinx).
        ws = [(sg.word, a + sg.start_frame / 100.0, a + (sg.end_frame + 1) / 100.0) for sg in d.seg()
              if sg.word not in ("<sil>", "<s>", "</s>") and not sg.word.startswith("[") and not sg.word.startswith("+")]
        if len(ws) != len(wa) + len(wb):
            continue
        end_prev, start_next = ws[len(wa) - 1][2], ws[len(wa)][1]
        mid = (end_prev + start_next) * 0.5
        best = None
        for g in gaps:
            if g[0] <= start_next + 0.3 and g[1] >= end_prev - 0.3:
                if best is None or abs((g[0] + g[1]) * 0.5 - mid) < abs((best[0] + best[1]) * 0.5 - mid):
                    best = g
        new_end, new_start = (best[0], best[1]) if best else (mid, mid)
        if abs(new_end - segs[i]["end"]) > 0.05:
            moved += 1
        segs[i]["end"], segs[i + 1]["start"] = new_end, new_start
    return moved


def asr_check(rows, segs, path):
    from pocketsphinx import Decoder
    raw = tempfile.NamedTemporaryFile(suffix=".raw", delete=False).name
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ac", "1", "-ar", "16000", "-f", "s16le", raw], check=True)
    audio = open(raw, "rb").read()
    os.unlink(raw)
    content = [set(w for w in words(t) if w not in STOP and len(w) > 2) for _, _, t in rows]
    d = Decoder(samprate=16000)
    flagged = []
    for k, s in enumerate(segs):
        d.start_utt()
        d.process_raw(audio[int(s["start"] * 16000) * 2:int(s["end"] * 16000) * 2], full_utt=True)
        d.end_utt()
        hw = set((d.hyp().hypstr if d.hyp() else "").split())
        own = len(content[k] & hw) / max(1, len(content[k]))
        leak = max([len((content[j] - content[k]) & hw) / max(1, len(content[j] - content[k]))
                    for j in (k - 1, k + 1) if 0 <= j < len(rows)] or [0.0])
        s["own"], s["leak"] = round(own, 2), round(leak, 2)
        hw_list = (d.hyp().hypstr if d.hyp() else "").split()
        s["heard"] = " ".join(hw_list[:3]) + " ... " + " ".join(hw_list[-3:])
        if own < 0.35 or leak > own * 0.6:
            flagged.append((s["n"], s["id"]))
    return flagged


def export(segs, path, out, total):
    meas = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af", "loudnorm=I=-16:TP=-1.5:print_format=json",
                           "-f", "null", "-"], capture_output=True, text=True).stderr
    gain = -16.0 - float(re.search(r'"input_i" : "(-?[0-9.]+)"', meas).group(1))
    os.makedirs(out, exist_ok=True)
    for k, s in enumerate(segs):
        before = s["start"] - segs[k - 1]["end"] if k > 0 else s["start"]
        after = segs[k + 1]["start"] - s["end"] if k + 1 < len(segs) else total - s["end"]
        a = max(0.0, s["start"] - min(0.06, before / 2))
        b = min(total, s["end"] + min(0.20, after / 2))
        dur = b - a
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{a:.3f}", "-t", f"{dur:.3f}", "-i", path, "-af",
                        f"volume={gain:.2f}dB,alimiter=limit=0.84:level=false,afade=t=in:d=0.01,"
                        f"afade=t=out:st={max(0.0, dur - 0.06):.3f}:d=0.06",
                        "-ac", "1", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5",
                        os.path.join(out, s["id"] + ".ogg")], check=True)
    return gain


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("read")
    ap.add_argument("--out", default=os.path.join(HERE, "..", "assets", "vo", "tutorial"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--ids", default="", help="comma-separated line ids: the read holds just these, in this order "
                    "(a partial re-record); default: every line of SCRIPT.md")
    a = ap.parse_args()
    rows = script_rows()
    if a.ids:
        by_id = {r[1]: r for r in rows}
        want = [x.strip() for x in a.ids.split(",") if x.strip()]
        missing = [x for x in want if x not in by_id]
        if missing:
            raise SystemExit("unknown line ids: %s" % missing)
        rows = [by_id[x] for x in want]
    total = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", a.read],
                                 capture_output=True, text=True).stdout)
    lead, tail, gaps = pauses(a.read, total)
    segs = choose_cuts(rows, lead, tail, gaps)
    moved = refine_cuts(rows, segs, a.read, gaps)
    print("alignment moved %d of %d cuts" % (moved, len(segs) - 1))
    flagged = asr_check(rows, segs, a.read)
    for s in segs:
        print("%2d %-14s %7.2f-%7.2f  %5.2fs (expected %5.2f)  words: own %.2f, neighbours %.2f | %s"
              % (s["n"], s["id"], s["start"], s["end"], s["end"] - s["start"], s["exp"], s["own"], s["leak"], s.get("heard", "")))
    if flagged:
        print("FLAGGED (not exported):", flagged)
        raise SystemExit(1)
    if a.dry_run:
        print("all %d pieces pass (dry run: nothing written)" % len(segs))
        return
    gain = export(segs, a.read, a.out, total)
    print("exported %d lines to %s (gain %+.2f dB)" % (len(segs), a.out, gain))


if __name__ == "__main__":
    main()
