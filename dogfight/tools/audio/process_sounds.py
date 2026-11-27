"""
Turns raw sound-effect takes into the game's audio assets.

    python tools/audio/process_sounds.py <folder of raw takes> assets/audio [name ...]

With names after the two folders, only those sounds are (re)made.

Needs ffmpeg on the PATH and numpy. The raw takes are expected as
<name>_<n>.mp3 (any format ffmpeg reads), several takes per name.

What it does, per kind of sound:
  * Loops (engines, wind, fire): finds the steadiest stretch across all takes
    (the one whose loudness wanders least), then crossfades its tail into its
    head so it repeats with no click or bump. Levelled by average loudness.
  * One-shots (guns, bullet whiz, impacts, explosions ...): trims each take to
    start exactly on its first transient (so a gun sample is in step with the
    round being fired), cuts it to length before any second event, fades the
    tail, and levels by peak. The best takes are kept as variations.
  * Guns additionally get a low shelf and gentle saturation: more thump and
    density without making them longer.
  * Sequences (engine start, undercarriage): sounds that are a little story
    with a quiet part and a loud part, where the timing matters. One chosen
    take is cut at fixed times, its quiet lead-in is lifted so it can be
    heard over a battle, and the end is faded.
Everything is written as mono 16-bit 44.1 kHz WAV.
"""

from __future__ import annotations

import glob
import os
import subprocess
import sys

import numpy as np

RATE = 44100

# name -> (loop seconds, crossfade seconds, target RMS in dBFS)
LOOPS = {
    "engine_hurricane": (7.0, 1.0, -17.0),
    "engine_spitfire": (7.0, 1.0, -17.0),
    "engine_mustang": (7.0, 1.0, -17.0),
    "wind": (6.0, 1.0, -20.0),
    "fire": (6.0, 1.0, -19.0),
    "ground_roll": (6.0, 1.0, -21.0),
}
# name -> (max seconds, how many takes to keep, extra ffmpeg filter, cut at a second event?)
PUNCH = "bass=g=5:f=115:w=0.7,highshelf=g=2:f=3500"
ONE_SHOTS = {
    "gun_browning": (0.42, 3, PUNCH, True),
    "gun_fifty": (0.50, 3, PUNCH, True),
    "gun_hispano": (0.55, 3, PUNCH, True),
    "bullet_whiz": (0.70, 4, "", False),
    "bullet_hit": (0.45, 4, "", True),
    "explosion": (3.6, 2, "bass=g=3:f=90:w=0.7", False),
    "metal_tear": (1.9, 2, "", False),
    "collision": (1.7, 2, "bass=g=2:f=120:w=0.7", False),
    "water_crash": (3.6, 1, "", False),
    "engine_fail": (5.0, 1, "", False),
    "touchdown": (0.9, 2, "", False),
}
# name -> (take, start s, length s, lift the lead-in by dB, lead-in ends at s
# into the cut, fade-out s). The engine start is cut so the engine catches
# about 2 s in, which is how long the game's starter takes; the gear clip is
# a motor whine ending in the clunk of the locks.
SEQUENCES = {
    "engine_start": (3, 0.7, 5.3, 14.0, 1.0, 1.6),
    "gear": (1, 0.1, 2.85, 14.0, 1.75, 0.25),
}
# Sounds that exist once in the game, saved without a take number.
SINGLE_FILE = {"engine_fail"}


def decode(path: str) -> np.ndarray:
    """Any audio file -> mono float32 at RATE, with sub-audible rumble removed."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-af", "highpass=f=28", "-f", "f32le", "-"],
        check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def write_wav(path: str, samples: np.ndarray, audio_filter: str = "") -> None:
    command = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-"]
    if audio_filter:
        command += ["-af", audio_filter]
    command += ["-c:a", "pcm_s16le", path]
    subprocess.run(command, input=samples.astype(np.float32).tobytes(), check=True)


def db(value: float) -> float:
    return 20.0 * np.log10(max(value, 1e-9))


def rms(samples: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(samples)))) if len(samples) else 0.0


def window_rms_db(samples: np.ndarray, seconds: float) -> np.ndarray:
    size = int(seconds * RATE)
    count = len(samples) // size
    if count == 0:
        return np.array([db(rms(samples))])
    blocks = samples[:count * size].reshape(count, size)
    return 20.0 * np.log10(np.maximum(np.sqrt(np.mean(blocks * blocks, axis=1)), 1e-9))


def spectral_centroid(samples: np.ndarray) -> float:
    spectrum = np.abs(np.fft.rfft(samples * np.hanning(len(samples))))
    frequencies = np.fft.rfftfreq(len(samples), 1.0 / RATE)
    return float(np.sum(frequencies * spectrum) / max(np.sum(spectrum), 1e-9))


def strongest_frequency(samples: np.ndarray, low: float = 40.0, high: float = 1200.0) -> float:
    spectrum = np.abs(np.fft.rfft(samples * np.hanning(len(samples))))
    frequencies = np.fft.rfftfreq(len(samples), 1.0 / RATE)
    band = (frequencies >= low) & (frequencies <= high)
    return float(frequencies[band][np.argmax(spectrum[band])])


def soft_limit(samples: np.ndarray, ceiling: float = 0.95) -> np.ndarray:
    """Rounds off anything over the ceiling instead of clipping it."""
    peak = float(np.max(np.abs(samples))) if len(samples) else 0.0
    if peak <= ceiling:
        return samples
    return np.tanh(samples / ceiling) * ceiling


# ---------------------------------------------------------------------------
# Loops
# ---------------------------------------------------------------------------

def make_loop(name: str, takes: list[tuple[str, np.ndarray]], seconds: float, fade: float, target_db: float) -> tuple[np.ndarray, str]:
    length = int(seconds * RATE)
    overlap = int(fade * RATE)
    best = None
    for path, samples in takes:
        levels = window_rms_db(samples, 0.25)
        blocks_needed = int((seconds + fade) / 0.25)
        # Skip the first and last half second: generated clips often fade in and out.
        for start_block in range(2, len(levels) - blocks_needed - 2):
            stretch = levels[start_block:start_block + blocks_needed]
            # Steady, and not a quiet lull either.
            score = float(np.std(stretch)) - 0.05 * float(np.mean(stretch))
            if best is None or score < best[0]:
                best = (score, path, samples, start_block * int(0.25 * RATE), float(np.std(stretch)))
    if best is None:
        raise RuntimeError(f"{name}: no take is long enough for a {seconds}s loop")
    _, path, samples, start, wander = best
    piece = samples[start:start + length + overlap].astype(np.float64)
    loop = piece[:length].copy()
    tail = piece[length:length + overlap]
    # Equal-power crossfade: the loop's first second is a blend of "what came
    # after the end" fading out and the real start fading in, so the sample
    # after the last one is the first one.
    ramp = np.linspace(0.0, 1.0, overlap)
    loop[:overlap] = loop[:overlap] * np.sin(ramp * np.pi / 2.0) + tail * np.cos(ramp * np.pi / 2.0)
    loop *= 10.0 ** ((target_db - db(rms(loop))) / 20.0)
    loop = soft_limit(loop)
    note = f"from {os.path.basename(path)} at {start / RATE:.1f}s, loudness wander {wander:.2f} dB"
    return loop.astype(np.float32), note


def seam_jump(loop: np.ndarray) -> float:
    """How big the step from the last sample to the first is, compared with a
    typical step inside the loop. About 1 means the seam cannot be heard."""
    typical = float(np.percentile(np.abs(np.diff(loop)), 95))
    return abs(float(loop[0] - loop[-1])) / max(typical, 1e-9)


# ---------------------------------------------------------------------------
# One-shots
# ---------------------------------------------------------------------------

def envelope(samples: np.ndarray, seconds: float = 0.002) -> np.ndarray:
    size = max(int(seconds * RATE), 1)
    return np.convolve(np.abs(samples), np.ones(size) / size, mode="same")


def onsets(samples: np.ndarray, threshold: float = 0.45, gap: float = 0.07) -> list[int]:
    """Sample positions where a new loud event begins."""
    level = envelope(samples)
    peak = float(np.max(level))
    if peak <= 0.0:
        return []
    above = level > peak * threshold
    found = []
    last = -10 * RATE
    quiet_for = int(gap * RATE)
    index = 0
    while index < len(above):
        if above[index] and index - last > quiet_for:
            found.append(index)
        if above[index]:
            last = index
        index += 8
    return found


def make_one_shot(samples: np.ndarray, max_seconds: float, cut_at_second_event: bool) -> tuple[np.ndarray, int]:
    level = envelope(samples)
    peak = float(np.max(level))
    first = int(np.argmax(level > peak * 0.12))
    start = max(first - int(0.003 * RATE), 0)
    events = onsets(samples)
    length = int(max_seconds * RATE)
    if cut_at_second_event:
        later = [event for event in events if event > start + int(0.09 * RATE)]
        if later:
            length = min(length, later[0] - start - int(0.012 * RATE))
    piece = samples[start:start + length].astype(np.float64)
    if len(piece) < int(0.05 * RATE):
        return np.zeros(0, dtype=np.float32), len(events)
    # 1 ms fade-in so the cut itself never clicks; long smooth fade on the tail.
    attack = min(int(0.001 * RATE), len(piece))
    piece[:attack] *= np.linspace(0.0, 1.0, attack)
    release = int(len(piece) * 0.4)
    piece[-release:] *= np.linspace(1.0, 0.0, release) ** 1.6
    piece *= 0.89 / max(float(np.max(np.abs(piece))), 1e-9)
    return piece.astype(np.float32), len(events)


def punchiness(piece: np.ndarray) -> float:
    """Higher = more of the energy is in a sharp front edge with weight behind it."""
    if len(piece) == 0:
        return -1e9
    front = rms(piece[:int(0.03 * RATE)])
    spectrum = np.abs(np.fft.rfft(piece))
    frequencies = np.fft.rfftfreq(len(piece), 1.0 / RATE)
    low_share = float(np.sum(spectrum[frequencies < 250.0]) / max(np.sum(spectrum), 1e-9))
    return db(front) + 12.0 * low_share


def saturate(piece: np.ndarray, drive: float = 1.5) -> np.ndarray:
    shaped = np.tanh(piece * drive) / np.tanh(drive)
    return (shaped * 0.89 / max(float(np.max(np.abs(shaped))), 1e-9)).astype(np.float32)


def make_sequence(samples: np.ndarray, start: float, seconds: float, lift_db: float, lift_until: float, fade: float) -> np.ndarray:
    piece = samples[int(start * RATE):int((start + seconds) * RATE)].astype(np.float64)
    # Lift the quiet lead-in, easing back to nothing over 0.3 s before the loud part.
    gain = np.ones(len(piece))
    lift = 10.0 ** (lift_db / 20.0)
    hold = min(int(lift_until * RATE), len(piece))
    ease = min(int(0.3 * RATE), len(piece) - hold)
    gain[:hold] = lift
    gain[hold:hold + ease] = np.linspace(lift, 1.0, ease)
    piece *= gain
    attack = int(0.02 * RATE)
    piece[:attack] *= np.linspace(0.0, 1.0, attack)
    release = min(int(fade * RATE), len(piece))
    piece[-release:] *= np.linspace(1.0, 0.0, release) ** 1.4
    piece *= 0.89 / max(float(np.max(np.abs(piece))), 1e-9)
    return piece.astype(np.float32)


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    raw_folder, out_folder = sys.argv[1], sys.argv[2]
    only = set(sys.argv[3:])
    os.makedirs(out_folder, exist_ok=True)

    def takes_of(name: str) -> list[tuple[str, np.ndarray]]:
        paths = sorted(glob.glob(os.path.join(raw_folder, f"{name}_*.*")))
        if not paths:
            raise RuntimeError(f"no raw takes found for {name}")
        return [(path, decode(path)) for path in paths]

    print("LOOPS")
    for name, (seconds, fade, target_db) in LOOPS.items():
        if only and name not in only:
            continue
        loop, note = make_loop(name, takes_of(name), seconds, fade, target_db)
        write_wav(os.path.join(out_folder, f"{name}.wav"), loop)
        print(f"  {name:<18} {len(loop) / RATE:4.1f}s  rms {db(rms(loop)):6.1f} dB  peak {db(float(np.max(np.abs(loop)))):5.1f} dB  "
              f"centroid {spectral_centroid(loop):5.0f} Hz  strongest {strongest_frequency(loop):4.0f} Hz  seam x{seam_jump(loop):.2f}  ({note})")

    print("ONE-SHOTS")
    for name, (max_seconds, keep, audio_filter, cut) in ONE_SHOTS.items():
        if only and name not in only:
            continue
        candidates = []
        for path, samples in takes_of(name):
            piece, event_count = make_one_shot(samples, max_seconds, cut)
            if len(piece) == 0:
                continue
            candidates.append((punchiness(piece), piece, os.path.basename(path), event_count))
        candidates.sort(key=lambda candidate: candidate[0], reverse=True)
        for number, (_, piece, source, event_count) in enumerate(candidates[:keep], start=1):
            if name.startswith("gun_"):
                piece = saturate(piece)
            file_name = f"{name}.wav" if name in SINGLE_FILE else f"{name}_{number}.wav"
            # The limiter catches whatever the tone shaping pushes over full scale.
            chain = ",".join(part for part in (audio_filter, "alimiter=limit=0.94:level=false") if part)
            write_wav(os.path.join(out_folder, file_name), piece, chain)
            written = decode(os.path.join(out_folder, file_name))
            print(f"  {file_name:<22} {len(written) / RATE:4.2f}s  peak {db(float(np.max(np.abs(written)))):5.1f} dB  rms {db(rms(written)):6.1f} dB  "
                  f"centroid {spectral_centroid(written):5.0f} Hz  events in take {event_count}  (from {source})")


    print("SEQUENCES")
    for name, (take, start, seconds, lift_db, lift_until, fade) in SEQUENCES.items():
        if only and name not in only:
            continue
        path, samples = takes_of(name)[take - 1]
        piece = make_sequence(samples, start, seconds, lift_db, lift_until, fade)
        write_wav(os.path.join(out_folder, f"{name}.wav"), piece, "alimiter=limit=0.94:level=false")
        levels = " ".join(f"{level:.0f}" for level in window_rms_db(piece, 0.25))
        print(f"  {name + '.wav':<22} {len(piece) / RATE:4.2f}s  (from {os.path.basename(path)})  loudness every 0.25 s: {levels}")


if __name__ == "__main__":
    main()
