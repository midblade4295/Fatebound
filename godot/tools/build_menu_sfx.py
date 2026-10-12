#!/usr/bin/env python3
"""The menu's sound effects (0.31.109, Kevin: "make all new high quality sound effects for the menu. I don't want these
to be cheap 8bit sounds. I want them to be sounds you'd hear in AAA game").

Sources: ElevenLabs sound-effect generations (eleven_text_to_sound_v2, four takes per prompt, the best picked by their
waveforms and spectrograms), kept in art_sources/menu_sfx/ (outside the Godot project). This script cuts, layers,
filters and levels them into assets/sounds/<cue>.wav (44.1 kHz, 16-bit stereo):
  - each layer: a cut [start, end) of its source, a short fade in, a curved fade out, a high-pass (phone speakers
    play nothing under ~100 Hz, and a rumble there only eats headroom), a gain and a time offset;
  - the mix: levelled to the cue's loudness (RMS of its loudest 150 ms), then a soft limiter so nothing clips.

  python3 tools/build_menu_sfx.py [SRC_DIR] [OUT_DIR]
"""
import os
import subprocess
import sys

import numpy as np
import scipy.io.wavfile as wf
import scipy.signal as ss

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "art_sources", "menu_sfx")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "assets", "sounds")
SR = 44100

# cue -> {"rms": loudness of its loudest 150 ms, "layers": [(source, start, end, offset, gain_db, highpass_hz, fade_out_s)]}
CUES = {
    # a crisp polished-wood tap (every button)
    "tap":        {"rms": 0.16, "layers": [("tap_1", 0.122, 0.30, 0.0, 0, 140, 0.12)]},
    # a soft whoosh into a cloth thud (back / close)
    "menuClose":  {"rms": 0.13, "layers": [("menuClose_1", 0.17, 0.55, 0.0, 0, 160, 0.20)]},
    # a clean crystal bell (confirm)
    "confirm":    {"rms": 0.12, "layers": [("confirm_3", 0.0, 0.62, 0.0, 0, 200, 0.40)]},
    # a blade slides home and clanks (equip)
    "equip":      {"rms": 0.14, "layers": [("equip_4", 0.22, 1.05, 0.0, 0, 150, 0.45)]},
    # a gold coin rings (a coin lands in the counter)
    "coin":       {"rms": 0.11, "layers": [("coin_3", 0.0, 0.55, 0.0, 0, 300, 0.40)]},
    # a crystal clinks (a gem lands)
    "gem":        {"rms": 0.11, "layers": [("gem_4", 0.0, 0.70, 0.0, 0, 300, 0.45)]},
    # a little fire puff with crackles (an Ember lands)
    "ember":      {"rms": 0.12, "layers": [("ember_2", 0.0, 0.50, 0.0, 0, 120, 0.30)]},
    # coins into a pouch, a sparkle over them (anything bought)
    "purchase":   {"rms": 0.15, "layers": [("coins_4", 0.0, 0.72, 0.0, 0, 180, 0.25),
                                           ("sparkle_2", 0.0, 0.85, 0.05, -7, 1500, 0.45)]},
    # two dull wooden knocks (not allowed / not enough)
    "error":      {"rms": 0.15, "layers": [("error_3", 0.255, 0.42, 0.0, 0, 110, 0.10),
                                           ("error_3", 0.775, 0.96, 0.12, -1, 110, 0.14)]},
    # a thick card flips (lobby: a player joins)
    "flip":       {"rms": 0.12, "layers": [("flip_2", 0.595, 0.80, 0.0, 0, 200, 0.18)]},
    # a deep wooden clock tick (lobby countdown)
    "countdown":  {"rms": 0.14, "layers": [("tick_3", 0.115, 0.45, 0.0, 0, 110, 0.30)]},
    # a war drum and a horn (PLAY)
    "matchStart": {"rms": 0.18, "layers": [("drum_2", 0.0, 1.1, 0.0, 0, 70, 0.70),
                                           ("horn_4", 0.0, 1.45, 0.06, -3, 120, 0.55)]},
    # the lid creaks, magic swells into the burst at 0.45 s (the flash), sparkles after (a chest opens)
    "chestOpen":  {"rms": 0.15, "layers": [("lid_3", 0.0, 0.42, 0.0, -2, 160, 0.15),
                                           ("burst_4", 0.12, 1.55, 0.0, -2, 250, 0.55),
                                           ("sparkle_2", 0.0, 0.85, 0.44, -4, 1500, 0.45)]},
    # a hammer rings on the anvil, a shimmer after (a Forge star)
    "forge":      {"rms": 0.15, "layers": [("forge_4", 0.0, 0.95, 0.0, 0, 150, 0.50),
                                           ("sparkle_1", 0.0, 0.80, 0.08, -8, 1500, 0.45)]},
    # a short brass-and-chimes fanfare (a reward claimed: pass tiers, orders, quests)
    "claim":      {"rms": 0.15, "layers": [("fanfare_4", 0.0, 1.25, 0.0, 0, 150, 0.60)]},
    # ---- 0.31.110 (Kevin: "I want more menu sound effects")
    # a soft rustle into a wooden click (the tab bar)
    "tab":        {"rms": 0.12, "layers": [("tab_1", 0.54, 0.82, 0.0, 0, 160, 0.16)]},
    # an airy whoosh with a soft tone after (a panel or a detail opens)
    "menuOpen":   {"rms": 0.10, "layers": [("menuOpen_7", 0.22, 1.60, 0.0, 0, 200, 0.60)]},
    # a solid switch click and its latch (settings toggles)
    "toggle":     {"rms": 0.12, "layers": [("toggle_4", 0.245, 0.42, 0.0, 0, 300, 0.10)]},
    # one tiny ratchet tick (a volume slider moves)
    "slider":     {"rms": 0.08, "layers": [("slider_1", 0.028, 0.068, 0.0, 0, 400, 0.02)]},
    # a key turns: ka-chunk, metal ringing (a chest starts unlocking)
    "unlock":     {"rms": 0.14, "layers": [("unlock_4", 1.15, 2.00, 0.0, 0, 150, 0.45)]},
    # a rich two-note golden chord, a sparkle over it (the premium pass bought)
    "premium":    {"rms": 0.16, "layers": [("premium_3", 0.0, 0.85, 0.0, 0, 150, 0.40),
                                           ("sparkle_2", 0.0, 0.85, 0.06, -8, 1500, 0.45)]},
    # a bright rising chime (pass tiers skipped)
    "tierUp":     {"rms": 0.15, "layers": [("tierUp_1", 0.0, 0.88, 0.0, 0, 200, 0.45)]},
    # crystal bells (a rare item revealed)
    "revealRare": {"rms": 0.12, "layers": [("revealRare_3", 0.0, 1.40, 0.0, 0, 250, 0.60)]},
    # a magic swell with a shimmer (an epic item revealed)
    "revealEpic": {"rms": 0.15, "layers": [("revealEpic_3", 0.0, 0.95, 0.0, 0, 150, 0.45),
                                           ("revealEpic_2", 0.0, 0.95, 0.0, -7, 1200, 0.45)]},
    # a golden swell and bells (a legendary item revealed)
    "revealLegendary": {"rms": 0.17, "layers": [("revealLegendary_2", 0.0, 1.60, 0.0, 0, 120, 0.70),
                                                ("revealLegendary_3", 0.0, 0.85, 0.0, -5, 600, 0.45)]},
    # gems pour out, glassy and bright (a gem pack bought)
    "gemPack":    {"rms": 0.14, "layers": [("gemPack_4", 0.0, 1.55, 0.0, 0, 300, 0.70)]},
    # an ascending chime arpeggio (account level up)
    "levelUp":    {"rms": 0.15, "layers": [("levelUp_2", 0.0, 1.50, 0.0, 0, 200, 0.70)]},
    # brass and drums, da-DAA (results: won)
    "resultWin":  {"rms": 0.18, "layers": [("resultWin_3", 0.0, 1.80, 0.0, 0, 90, 0.80)]},
    # low strings and a soft horn (results: lost)
    "resultLose": {"rms": 0.15, "layers": [("resultLose_3", 0.0, 1.55, 0.0, 0, 80, 0.75)]},
    # ---- 0.31.111 (Kevin: "Build a global chat ... Also add the quick chat pings")
    # a bright metal pluck that rings (a teammate's quick-chat ping)
    "ping":       {"rms": 0.12, "layers": [("ping_1", 0.0, 0.60, 0.0, 0, 300, 0.35)]},
    # a soft pop with a little bell shimmer (a chat message, a friend request, a party invite)
    "chatPop":    {"rms": 0.09, "layers": [("chatPop_3", 0.0, 0.50, 0.0, 0, 300, 0.30)]},
}


def load(name):
    path = os.path.join(SRC, name + ".mp3")
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ar", str(SR), "-ac", "2", "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


_cache = {}


def layer(name, start, end, hp, fade_out):
    if name not in _cache:
        _cache[name] = load(name)
    x = _cache[name][int(start * SR):int(end * SR)].copy()
    if hp > 0:
        sos = ss.butter(2, hp, "highpass", fs=SR, output="sos")
        x = ss.sosfiltfilt(sos, x, axis=0)
    n_in = min(len(x), int(0.002 * SR))
    x[:n_in] *= np.linspace(0.0, 1.0, n_in)[:, None]
    n_out = min(len(x), int(fade_out * SR))
    if n_out > 0:
        x[-n_out:] *= (np.cos(np.linspace(0.0, np.pi, n_out)) * 0.5 + 0.5)[:, None] ** 1.5
    return x


def loudest_rms(x, win=0.15):
    m = (x ** 2).mean(axis=1)
    k = max(1, int(win * SR))
    if len(m) <= k:
        return float(np.sqrt(m.mean()))
    c = np.convolve(m, np.ones(k) / k, mode="valid")
    return float(np.sqrt(c.max()))


def limit(x, ceiling=0.94):
    # soft knee: untouched below 0.7 of the ceiling, tanh above
    a = np.abs(x)
    knee = ceiling * 0.7
    over = a > knee
    y = x.copy()
    y[over] = np.sign(x[over]) * (knee + (ceiling - knee) * np.tanh((a[over] - knee) / (ceiling - knee)))
    return y


def build(cue, spec):
    parts = []
    for (name, start, end, offset, gain_db, hp, fade) in spec["layers"]:
        parts.append((int(offset * SR), layer(name, start, end, hp, fade) * 10 ** (gain_db / 20.0)))
    n = max(o + len(p) for o, p in parts)
    mix = np.zeros((n, 2))
    for o, p in parts:
        mix[o:o + len(p)] += p
    mix *= spec["rms"] / max(1e-6, loudest_rms(mix))
    mix = limit(mix)
    # trim the silence the fades left at the end
    e = np.abs(mix).max(axis=1)
    last = np.where(e > 1e-4)[0]
    mix = mix[:last[-1] + 1] if len(last) else mix
    return mix


def main():
    os.makedirs(OUT, exist_ok=True)
    for cue, spec in CUES.items():
        mix = build(cue, spec)
        wf.write(os.path.join(OUT, cue + ".wav"), SR, (mix * 32767).astype(np.int16))
        print("%-11s %.2f s  peak %.2f  rms(150ms) %.3f" % (cue, len(mix) / SR, np.abs(mix).max(), loudest_rms(mix)))


if __name__ == "__main__":
    main()
