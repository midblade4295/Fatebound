#!/usr/bin/env python3
"""The heroes' ability sounds (0.31.171, step 3 of the plan: hero polish -- Kevin picked "Both, 2 takes": painted icons
and a sound of its own for every ability, the ultimates, and the new heroes' shots and hits).

Sources: ElevenLabs sound-effect generations (eleven_text_to_sound_v2, two takes per prompt; the better one picked by
its waveform and spectrogram), kept in art_sources/hero_sfx/<key>_<take>.mp3 (outside the Godot project). This script
cuts, layers, filters and levels them into assets/sounds/<cue>.wav, as tools/build_menu_sfx.py does the menu's -- but
mono (a match's sounds are placed by distance, not panned) at 44.1 kHz, 16-bit:
  - each layer: a cut [start, end) of its source, a short fade in, a curved fade out, a high-pass (phone speakers
    play nothing under ~100 Hz, and a rumble there only eats headroom), a gain and a time offset;
  - the mix: levelled to the cue's loudness (RMS of its loudest 150 ms), then a soft limiter so nothing clips.

  python3 tools/build_hero_sfx.py [SRC_DIR] [OUT_DIR]
"""
import os
import subprocess
import sys

import numpy as np
import scipy.io.wavfile as wf
import scipy.signal as ss

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "art_sources", "hero_sfx")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "assets", "sounds")
SR = 44100

# loudness (RMS of the loudest 150 ms): the borrowed combat cues they replace sit at 0.06-0.15 (played at gain 1) and the
# old synthesized ultimates at 0.2-0.3 (played at 0.6-0.8)
AB = 0.16        # a Q, W or E
ULT = 0.20       # an ultimate
SHOT = 0.10      # a basic attack (many a second in a fight)
HIT = 0.10       # a basic attack landing


def one(src, start, end, fade, hp=120, rms=AB):
    return {"rms": rms, "layers": [(src, start, end, 0.0, 0, hp, fade)]}


# cue -> {"rms": loudness, "layers": [(source, start, end, offset, gain_db, highpass_hz, fade_out_s)]}
CUES = {
    # ---- Knight: SHIELD (Q, and the Crusader's W: "block_up"), SHIELD BASH, RALLY, BULWARK
    "ab_shield":      one("ab_shield_1", 0.0, 0.90, 0.40, 150, 0.12),
    "ab_bash":        one("ab_bash_1", 0.0, 1.20, 0.50),
    "ab_rally":       one("ab_rally_1", 0.0, 1.80, 0.70),
    "ult_knight":     one("ult_knight_1", 0.0, 2.20, 0.90, 100, ULT),
    # ---- Barbarian: LEAP (the jump; its landing is "slam"), BLOODLUST, WAR CRY
    "ab_leap":        one("ab_leap_1", 0.0, 0.55, 0.20),
    "ab_leap_land":   one("ab_leap_1", 1.58, 2.00, 0.25, 90),
    "ab_bloodlust":   one("ab_bloodlust_2", 0.0, 0.80, 0.30, 50),        # (heartbeats: little over 100 Hz)
    "ult_barbarian":  one("ult_barbarian_2", 0.0, 1.30, 0.50, 100, ULT),
    # ---- Rogue: CALTROPS, POISON BLADES, EXECUTE
    "ab_caltrops":    one("ab_caltrops_1", 0.0, 1.20, 0.45),
    "ab_poison":      one("ab_poison_1", 0.0, 1.00, 0.30),
    "ult_rogue":      one("ult_rogue_2", 0.0, 1.50, 0.40, 120, ULT),
    # ---- Ranger: TUMBLE, SNARE ARROW, ARROW RAIN
    "ab_tumble":      one("ab_tumble_2", 0.0, 1.00, 0.40),
    "ab_snare":       one("ab_snare_1", 0.0, 0.90, 0.30),
    "ult_ranger":     one("ult_ranger_1", 0.0, 0.90, 0.40, 120, ULT),
    # ---- Mage: FIRE PILLAR (the eruption, "pillar"), BLINK, INFERNO
    "ab_pillar":      one("ab_pillar_1", 0.0, 1.40, 0.60, 100),
    "ab_blink":       one("ab_blink_1", 0.0, 0.80, 0.40),
    "ult_mage":       one("ult_mage_1", 0.0, 1.50, 0.60, 100, ULT),
    # ---- Priest: HOLY LIGHT, DAZZLE, GRACE
    "ab_holylight":   one("ab_holylight_1", 0.0, 1.50, 0.70),
    "ab_dazzle":      one("ab_dazzle_1", 0.0, 0.80, 0.40),
    "ult_priest":     one("ult_priest_1", 0.0, 1.50, 0.60, 120, ULT),
    # ---- Crusader: CONSECRATE, JUDGMENT
    "ab_consecrate":  one("ab_consecrate_1", 0.0, 1.20, 0.50),
    "ult_crusader":   one("ult_crusader_2", 0.0, 1.10, 0.50, 100, ULT),
    # ---- Berserker: WHIRLWIND, RECKLESS CHARGE, FRENZY, UNDYING
    "ab_whirl":       one("ab_whirl_2", 0.15, 1.50, 0.40),
    "ab_charge":      one("ab_charge_1", 0.0, 0.70, 0.25),
    "ab_frenzy":      one("ab_frenzy_1", 0.35, 1.20, 0.30, 50),
    "ult_berserker":  one("ult_berserker_2", 0.0, 1.40, 0.50, 100, ULT),
    # ---- Assassin: VANISH, SHADOW STEP (the dash, then the stab), FAN OF KNIVES, FLURRY (the dash off; each strike
    # is "flurry_hit": the take's three sharpest slashes)
    "ab_vanish":      one("ab_vanish_1", 0.0, 0.45, 0.20),
    "ab_shadowstep":  {"rms": AB, "layers": [("ab_shadowstep_2", 0.0, 0.40, 0.0, 0, 120, 0.15),
                                             ("ab_shadowstep_2", 0.95, 1.40, 0.30, 0, 120, 0.20)]},
    "ab_knives":      one("ab_knives_1", 0.0, 0.75, 0.30),
    "ult_assassin":   one("ult_assassin_1", 0.04, 0.34, 0.12, 150, ULT),
    "flurry1":        one("ult_assassin_1", 2.30, 2.70, 0.25, 150, 0.13),
    "flurry2":        one("ult_assassin_1", 2.86, 3.30, 0.25, 150, 0.13),
    "flurry3":        one("ult_assassin_1", 3.46, 3.90, 0.25, 150, 0.13),
    # ---- Sniper: PIERCE, BEAR TRAP (set; caught: "trap_snap"), HUNTER'S MARK, DEADEYE
    "ab_pierce":      one("ab_pierce_2", 0.30, 1.00, 0.30),
    "ab_trap":        one("ab_trap_1", 0.0, 1.00, 0.35),
    "ab_trap_snap":   one("ab_trap_snap_2", 0.0, 0.60, 0.25, 120),
    "ab_mark":        one("ab_mark_1", 0.0, 1.00, 0.45),
    "ult_sniper":     one("ult_sniper_1", 0.0, 2.20, 0.80, 120, ULT),
    # ---- Archmage: ARCANE MISSILES, MANA SHIELD, METEORS
    "ab_missiles":    one("ab_missiles_1", 0.0, 1.20, 0.45),
    "ab_manashield":  one("ab_manashield_1", 0.0, 1.00, 0.45),
    "ult_archmage":   one("ult_archmage_2", 0.0, 1.00, 0.40, 100, ULT),
    # ---- Necromancer: BONE SHIELD, CURSE, LEGION
    "ab_boneshield":  one("ab_boneshield_2", 0.0, 1.30, 0.50),
    "ab_curse":       one("ab_curse_2", 0.0, 0.90, 0.40),
    "ult_necromancer": one("ult_necromancer_1", 0.0, 1.50, 0.50, 100, ULT),
    # ---- Golem: BOULDER, STONESKIN, QUAKE, LANDSLIDE; his swing and its hit
    "ab_boulder":     one("ab_boulder_1", 0.0, 1.30, 0.50, 90),
    "ab_stoneskin":   one("ab_stoneskin_1", 0.0, 1.30, 0.50),
    "ab_quake":       one("ab_quake_1", 0.0, 0.90, 0.40, 90),
    "ult_golem":      one("ult_golem_2", 0.0, 1.40, 0.50, 90, ULT),
    "atk_golem":      one("atk_golem_1", 0.08, 0.50, 0.15, 120, SHOT),
    "hit_golem":      one("hit_golem_2", 0.0, 0.60, 0.30, 100, HIT),
    # ---- Dragoon: SWEEP, IMPALE, VAULT (the jump and the landing), DRAGON DIVE (the leap; the crash is "slam")
    "ab_sweep":       one("ab_sweep_2", 0.0, 0.75, 0.30),
    "ab_impale":      one("ab_impale_1", 0.0, 0.90, 0.30),
    "ab_vault":       {"rms": AB, "layers": [("ab_vault_2", 0.0, 0.25, 0.0, 0, 120, 0.10),
                                             ("ab_vault_2", 0.80, 1.50, 0.35, 0, 100, 0.35)]},
    "ult_dragoon":    one("ult_dragoon_1", 0.0, 0.50, 0.20, 120, ULT),
    "ult_dragoon_land": one("ult_dragoon_1", 2.00, 2.90, 0.40, 90, ULT),
    # ---- Duelist: LUNGE, RIPOSTE (the answer: "riposte"), FEINT, GRAND CHALLENGE
    "ab_thrust":      one("ab_thrust_1", 0.0, 0.30, 0.12),
    "ab_riposte":     one("ab_riposte_1", 0.0, 0.70, 0.30, 150),
    "ab_feint":       one("ab_feint_1", 0.0, 0.80, 0.35),
    "ult_duelist":    one("ult_duelist_1", 0.0, 1.20, 0.50, 120, ULT),
    # ---- Stormcaller: CHAIN LIGHTNING, STATIC FIELD, GUST, THUNDERSTORM; his bolt and its hit (and the storm's)
    "ab_chain":       one("ab_chain_2", 0.0, 0.85, 0.30),
    "ab_static":      one("ab_static_1", 0.0, 1.00, 0.40),
    "ab_gust":        one("ab_gust_1", 0.0, 1.00, 0.50),
    "ult_stormcaller": one("ult_stormcaller_2", 0.0, 1.00, 0.40, 100, ULT),
    "atk_bolt":       one("atk_bolt_2", 0.0, 0.50, 0.25, 150, SHOT),
    "hit_bolt":       one("hit_bolt_2", 0.0, 0.55, 0.30, 150, HIT),
    # ---- Musketeer: BUCKSHOT, POWDER KEG (the lob; the blast is "burst"), SMOKE ROLL (the puff, then the roll),
    # QUICKDRAW (three shots on top of each other); his musket and its hit
    "ab_buckshot":    one("ab_buckshot_2", 0.0, 0.75, 0.35, 100),
    "ab_keg":         one("ab_keg_2", 0.0, 1.00, 0.40),
    "ab_smokeroll":   {"rms": AB, "layers": [("ab_smokeroll_1", 0.0, 0.50, 0.0, 0, 120, 0.20),
                                             ("ab_smokeroll_1", 1.10, 1.70, 0.30, -2, 120, 0.25)]},
    "ult_musketeer":  {"rms": ULT, "layers": [("ult_musketeer_1", 0.0, 0.60, 0.0, 0, 100, 0.40),
                                              ("ult_musketeer_1", 0.0, 0.60, 0.11, -2, 100, 0.40),
                                              ("ult_musketeer_1", 0.0, 0.60, 0.22, -4, 100, 0.40)]},
    "atk_musket":     one("atk_musket_1", 0.0, 0.45, 0.20, 100, SHOT),
    "hit_musket":     one("hit_musket_2", 0.0, 0.30, 0.15, 120, HIT),
    # ---- Druid: REJUVENATE, ENTANGLE (the roots: "burst"), BARKSKIN, WILD GROWTH; her thorn and its hit
    "ab_rejuv":       one("ab_rejuv_2", 0.0, 1.20, 0.50),
    "ab_entangle":    one("ab_entangle_2", 0.0, 0.65, 0.25),
    "ab_barkskin":    one("ab_barkskin_1", 0.0, 0.60, 0.25),
    "ult_druid":      one("ult_druid_2", 0.0, 1.40, 0.50, 100, ULT),
    "atk_thorn":      one("atk_thorn_2", 0.0, 0.40, 0.20, 150, SHOT),
    "hit_thorn":      one("hit_thorn_2", 0.0, 0.25, 0.12, 150, HIT),
}


def load(name):
    path = os.path.join(SRC, name + ".mp3")
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ar", str(SR), "-ac", "1", "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


_cache = {}


def layer(name, start, end, hp, fade_out):
    if name not in _cache:
        x = load(name)
        _cache[name] = x / max(1e-6, np.abs(x).max())          # (the decoded mp3s overshoot 1.0)
    x = _cache[name][int(start * SR):int(end * SR)].copy()
    if hp > 0:
        sos = ss.butter(2, hp, "highpass", fs=SR, output="sos")
        x = ss.sosfiltfilt(sos, x)
    n_in = min(len(x), int(0.002 * SR))
    x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    n_out = min(len(x), int(fade_out * SR))
    if n_out > 0:
        x[-n_out:] *= (np.cos(np.linspace(0.0, np.pi, n_out)) * 0.5 + 0.5) ** 1.5
    return x


def loudest_rms(x, win=0.15):
    m = x ** 2
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


def build(spec):
    parts = []
    for (name, start, end, offset, gain_db, hp, fade) in spec["layers"]:
        parts.append((int(offset * SR), layer(name, start, end, hp, fade) * 10 ** (gain_db / 20.0)))
    n = max(o + len(p) for o, p in parts)
    mix = np.zeros(n)
    for o, p in parts:
        mix[o:o + len(p)] += p
    mix *= spec["rms"] / max(1e-6, loudest_rms(mix))
    mix = limit(mix)
    last = np.where(np.abs(mix) > 1e-4)[0]          # trim the silence the fades left at the end
    return mix[:last[-1] + 1] if len(last) else mix


def main():
    os.makedirs(OUT, exist_ok=True)
    for cue, spec in CUES.items():
        mix = build(spec)
        wf.write(os.path.join(OUT, cue + ".wav"), SR, (mix * 32767).astype(np.int16))
        print("%-16s %.2f s  peak %.2f  rms(150ms) %.3f" % (cue, len(mix) / SR, np.abs(mix).max(), loudest_rms(mix)))
    print("%d cues" % len(CUES))


if __name__ == "__main__":
    main()
