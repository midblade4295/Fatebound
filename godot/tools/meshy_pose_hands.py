#!/usr/bin/env python3
"""Pose every Meshy body's hands (0.31.190, Kevin: "Go through all models and make sure weapons and shields are being
held correctly and try to make hands actually gripping them").

Each hand that holds something closes into a fist round the handle, the free hand bends a little: tools/meshy_hand_pose.py
per hand (grip / relax), from the ORIGINAL rigged GLB and rig.json (posing twice bends twice), read from git at --from
(the last commit before the hands were posed). The Knight, Rogue and Assassin were made with closed hands; the Worker
was posed in 0.31.77. A tome lies on an open hand (the Archmage's left).

  python3 tools/meshy_pose_hands.py [--from e08df3d] [--only body,body]   (run from godot/)

PLAN: body -> hand -> (grip|relax, knuckle line in metres past the wrist, read off the bind-pose hand renders). The thumb
line (--thumb-z) is measured: the index finger's outer edge at the fingertips + 4 mm (the thumb sits further out).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshy_building_tex import read_glb  # noqa: E402
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location("mhp", os.path.join(os.path.dirname(os.path.abspath(__file__)), "meshy_hand_pose.py"))
mhp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mhp)

PLAN = {
    "barbarian": {"r": ("grip", 0.090), "l": ("grip", 0.090)},
    "ranger": {"r": ("relax", 0.070), "l": ("grip", 0.065)},
    "mage": {"r": ("grip", 0.065), "l": ("relax", 0.065)},
    "priest": {"r": ("grip", 0.085), "l": ("relax", 0.085)},
    "crusader": {"r": ("grip", 0.055), "l": ("grip", 0.055)},
    "berserker": {"r": ("grip", 0.055), "l": ("grip", 0.060)},
    "sniper": {"r": ("grip", 0.070), "l": ("relax", 0.060)},
    "archmage": {"r": ("grip", 0.050), "l": ("relax", 0.050)},
    "necromancer": {"r": ("grip", 0.070), "l": ("relax", 0.065)},
    "golem": {"r": ("grip", 0.075), "l": ("grip", 0.080)},
    "dragoon": {"r": ("grip", 0.045), "l": ("grip", 0.050)},
    "duelist": {"r": ("grip", 0.080), "l": ("grip", 0.085)},
    "stormcaller": {"r": ("grip", 0.080), "l": ("relax", 0.090)},
    "musketeer": {"r": ("grip", 0.075), "l": ("relax", 0.080)},
    "druid": {"r": ("grip", 0.070), "l": ("relax", 0.070)},
    "minion_melee": {"r": ("grip", 0.080), "l": ("grip", 0.080)},
    "minion_caster": {"r": ("grip", 0.100), "l": ("relax", 0.105)},
    "minion_siege": {"r": ("grip", 0.085), "l": ("relax", 0.090)},
    "minion_super": {"r": ("grip", 0.150), "l": ("grip", 0.150)},
}


def thumb_z(path, side):
    g, binc = read_glb(path)
    at = g["meshes"][0]["primitives"][0]["attributes"]
    _, P = mhp.view(g, binc, at["POSITION"])
    _, J = mhp.view(g, binc, at["JOINTS_0"])
    _, W = mhp.view(g, binc, at["WEIGHTS_0"])
    P = P.astype(np.float64)
    skin = g["skins"][0]
    names = [g["nodes"][j]["name"] for j in skin["joints"]]
    _, ibm = mhp.view(g, binc, skin["inverseBindMatrices"])
    BIND = np.linalg.inv(ibm.reshape(-1, 4, 4).transpose(0, 2, 1).astype(np.float64))
    hi = names.index(("Right" if side == "r" else "Left") + "Hand")
    fi = names.index(("Right" if side == "r" else "Left") + "ForeArm")
    wh = sum(np.where(J[:, k] == hi, W[:, k], 0.0) for k in range(4))
    wr = BIND[hi][:3, 3]
    u = wr - BIND[fi][:3, 3]
    u[1] = 0.0
    u /= np.linalg.norm(u)
    d = (P - wr) @ u
    z = P[:, 2] - wr[2]
    hand = wh > 0.5
    dmax = float(d[hand].max())
    tips = hand & (d > dmax - 0.025) & (d < dmax - 0.003)
    return float(z[tips].max()) + 0.004


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="rev", default="e08df3d")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="pose_hands_")
    for body, plan in PLAN.items():
        if a.only and body not in a.only.split(","):
            continue
        cur = os.path.join(tmp, body + "_0.glb")
        rig = os.path.join(tmp, body + "_rig.json")
        for src, dst in (("rigged.glb", cur), ("rig.json", rig)):
            with open(dst, "wb") as f:
                f.write(subprocess.run(["git", "show", "%s:godot/assets/meshy/%s/%s" % (a.rev, body, src)],
                                       capture_output=True, check=True).stdout)
        kr = plan.get("r", ("", 0.08))[1]
        kl = plan.get("l", ("", 0.08))[1]
        for n, side in enumerate(s for s in "rl" if s in plan):
            mode = plan[side][0]
            tz = thumb_z(cur, side)
            nxt = os.path.join(tmp, "%s_%d.glb" % (body, n + 1))
            r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "meshy_hand_pose.py"),
                                cur, nxt, rig, "--" + mode, side, "--knuckle-r", str(kr), "--knuckle-l", str(kl),
                                "--thumb-z", "%.4f" % tz], capture_output=True, text=True, check=True)
            print(body, side, mode, "thumb_z %.3f |" % tz, r.stdout.strip().replace("\n", " | "))
            cur = nxt
        shutil.copy(cur, os.path.join("assets", "meshy", body, "rigged.glb"))
        shutil.copy(rig, os.path.join("assets", "meshy", body, "rig.json"))
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
