#!/usr/bin/env python3
"""Fatebound: Siege trailer - procedural placeholder score (numpy/scipy). A stand-in until real music:
90 BPM, D minor. Intro (drone + soft drums) -> main (drums, Dm-Bb-F-C pad, plucked ostinato) ->
build (riser + roll) -> title hit (drum + crash + D major chord ringing out).

    python3 tools/trailer_music.py OUT.wav [--length 36] [--hit 31.5]
"""
import argparse
import numpy as np
from scipy.signal import butter, lfilter
from scipy.io import wavfile

SR = 48000
rng = np.random.default_rng(7)


def lp(x, hz, order=2):
    b, a = butter(order, hz / (SR / 2), "low")
    return lfilter(b, a, x)


def hp(x, hz, order=2):
    b, a = butter(order, hz / (SR / 2), "high")
    return lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return lfilter(b, a, x)


def note_hz(n):
    # MIDI note -> Hz
    return 440.0 * 2 ** ((n - 69) / 12)


def add(buf, sig, at):
    i = int(at * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i]


def taiko(gain=1.0, dur=0.9):
    t = np.arange(int(dur * SR)) / SR
    f = 42 + 58 * np.exp(-t * 18)                  # pitch drops 100 -> 42 Hz
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 5.5)
    skin = lp(rng.standard_normal(len(t)), 900) * np.exp(-t * 30) * 0.5
    return (body + skin) * gain


def snare(gain=0.35, dur=0.18):
    t = np.arange(int(dur * SR)) / SR
    return bp(rng.standard_normal(len(t)), 900, 5000) * np.exp(-t * 28) * gain


def crash(gain=0.5, dur=3.5):
    t = np.arange(int(dur * SR)) / SR
    return hp(rng.standard_normal(len(t)), 4000) * np.exp(-t * 1.6) * gain


def saw_voice(hz, dur, detune=(0.0, -0.08, 0.07)):
    t = np.arange(int(dur * SR)) / SR
    out = np.zeros_like(t)
    for d in detune:
        f = hz * 2 ** (d / 12)
        out += 2 * ((t * f) % 1.0) - 1.0
    return out / len(detune)


def pad(notes, dur, gain=0.16, cutoff=900, attack=0.5, release=0.8):
    t = np.arange(int(dur * SR)) / SR
    sig = sum(saw_voice(note_hz(n), dur) for n in notes) / len(notes)
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, np.maximum(0.0, (dur - t) / release))
    return lp(sig, cutoff) * env * gain


def pluck(n, dur=0.32, gain=0.22):
    t = np.arange(int(dur * SR)) / SR
    sig = saw_voice(note_hz(n), dur, (0.0, 0.05))
    return lp(sig, 1400) * np.exp(-t * 11) * gain


def reverb(x, wet=0.25):
    out = x.copy()
    for delay, g in [(0.029, 0.5), (0.037, 0.45), (0.051, 0.4), (0.067, 0.35), (0.113, 0.3), (0.171, 0.25)]:
        d = int(delay * SR)
        y = np.zeros_like(x)
        y[d:] = x[:-d] * g
        out += lp(y, 3500, 1) * wet
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--length", type=float, default=36.0)
    ap.add_argument("--hit", type=float, default=31.5, help="time of the title hit (s)")
    a = ap.parse_args()
    n = int(a.length * SR)
    L = np.zeros(n)
    beat = 60.0 / 90.0
    bar = beat * 4
    intro_end, main_end = 9.0, 27.0
    # D2 drone through the intro and main.
    L += np.pad(pad([38, 45], main_end + 1.0, gain=0.12, cutoff=500, attack=2.0), (0, n))[:n]
    # Intro drums: one hit per bar, growing.
    t = 0.0
    k = 0
    while t < intro_end:
        add(L, taiko(0.35 + 0.08 * k), t)
        t += bar
        k += 1
    # Main: pad chords per bar, drums, ostinato.
    chords = [[50, 53, 57], [46, 50, 53], [53, 57, 60], [48, 52, 55]]   # Dm Bb F C (mid register)
    roots = [38, 34, 41, 36]
    t = intro_end
    i = 0
    while t < main_end:
        add(L, pad(chords[i % 4], bar + 0.6, gain=0.14, cutoff=1100, attack=0.25, release=0.5), t)
        for b in range(4):
            bt = t + b * beat
            add(L, taiko(0.9 if b in (0, 2) else 0.55), bt)
            add(L, snare(0.18), bt + beat * 0.5)
            for e in range(2):
                add(L, pluck(roots[i % 4] + 12 + (7 if (b + e) % 3 == 2 else 0)), bt + e * beat * 0.5)
        t += bar
        i += 1
    # Build: riser + accelerating roll into the hit.
    rise_len = a.hit - main_end
    tr = np.arange(int(rise_len * SR)) / SR
    noise = rng.standard_normal(len(tr))
    riser = np.zeros_like(tr)
    for s0 in range(0, len(tr), SR // 10):                      # sweep the band upward in steps
        seg = noise[s0:s0 + SR // 10]
        frac = s0 / len(tr)
        riser[s0:s0 + len(seg)] = bp(seg, 300 + 3000 * frac, 800 + 7000 * frac)
    add(L, riser * (tr / rise_len) ** 2 * 0.35, main_end)
    add(L, pad([50, 53, 57, 62], rise_len + 0.2, gain=0.12, cutoff=1500, attack=rise_len * 0.8, release=0.2), main_end)
    rt = main_end
    gap = beat / 2
    while rt < a.hit - 0.05:
        add(L, snare(0.12 + 0.3 * (rt - main_end) / rise_len), rt)
        rt += gap
        gap = max(0.06, gap * 0.9)
    # The title hit: drums + crash + D major ringing out.
    add(L, taiko(1.4, 1.6), a.hit)
    add(L, taiko(1.0, 1.4), a.hit + 0.02)
    add(L, crash(0.55), a.hit)
    tail = a.length - a.hit
    add(L, pad([38, 50, 54, 57, 62], tail, gain=0.2, cutoff=1800, attack=0.05, release=tail * 0.7), a.hit)
    # Stereo: slight delay/filter difference, reverb, gentle limiting.
    Rch = np.zeros(n)
    Rch[int(0.011 * SR):] = L[: n - int(0.011 * SR)]
    Rch = 0.8 * L + 0.2 * lp(Rch, 5000, 1)
    st = np.stack([reverb(L), reverb(Rch)], axis=1)
    st = np.tanh(st * 1.3)
    st *= 0.89 / np.max(np.abs(st))
    fade = int(0.05 * SR)
    st[:fade] *= np.linspace(0, 1, fade)[:, None]
    wavfile.write(a.out, SR, (st * 32767).astype(np.int16))
    print("wrote", a.out, f"{a.length:.1f}s")


if __name__ == "__main__":
    main()
