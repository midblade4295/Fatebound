#!/usr/bin/env python3
"""0.31.218 (Kevin: "Performance. Honor of kings gives me 120fps solid. This game I can hardly hit 30"): the lane
minions' Meshy bodies (~10,300 triangles each, every one of up to 36 on the field drawn twice -- the view and its
shadow) and their weapons (3,000-4,000) cut down for a phone, with meshoptimizer's gltfpack (npm gltfpack 0.24.0):
the rig, its joint names and weights, the node names, the material and the embedded texture all kept, only the
triangles fewer. -sv: the texture's seams respected (-sa -- to the ratio whatever the seams -- smeared the paint across
them: speckled minions), -se 0.1: up to 10 % deviation (at the match's distance a minion is ~40 px tall), so the seams
set the floor: a body ~10,350 -> 4,100-7,100, a weapon 2,900-4,100 -> 1,200-3,200. -noq: plain floats (no glTF
extensions for Godot to need).

Sources: the full models as they were at commit SOURCE (git show), so a rerun starts from them and not from the cut
ones; out: the same paths under godot/ (Godot reimports them: generate_lods and shadow meshes as before).

  python3 tools/simplify_models.py          (needs git, node/npx; downloads gltfpack once)
"""
import json
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
REPO = os.path.dirname(GODOT)
SOURCE = "7ef3e48"                      # the last commit with the full models
GLTFPACK = "gltfpack@0.24.0"
# path under godot/ -> the share of its triangles to aim for (the seams stop it first)
MODELS = {
    "assets/meshy/minion_melee/rigged.glb": 0.25,
    "assets/meshy/minion_caster/rigged.glb": 0.25,
    "assets/meshy/minion_siege/rigged.glb": 0.25,
    "assets/meshy/minion_super/rigged.glb": 0.25,
    "assets/meshy/weapons/minion_sword.glb": 0.25,
    "assets/meshy/weapons/minion_buckler.glb": 0.25,
    "assets/meshy/weapons/minion_crossbow.glb": 0.25,
    "assets/meshy/weapons/minion_cannon.glb": 0.25,
    "assets/meshy/weapons/minion_hammer.glb": 0.25,
}


def tris(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    return sum(j["accessors"][p["indices"]]["count"] // 3 for m in j.get("meshes", []) for p in m["primitives"] if "indices" in p)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        for rel, ratio in MODELS.items():
            src = os.path.join(tmp, os.path.basename(rel))
            data = subprocess.run(["git", "-C", REPO, "show", "%s:godot/%s" % (SOURCE, rel)], capture_output=True, check=True).stdout
            open(src, "wb").write(data)
            out = os.path.join(GODOT, rel)
            subprocess.run(["npx", "--yes", GLTFPACK, "-i", src, "-o", out, "-noq", "-kn", "-km", "-ke", "-ac", "-af", "0",
                            "-si", str(ratio), "-sv", "-se", "0.1"], check=True, capture_output=True)
            print("%-46s %6d -> %5d triangles" % (rel, tris(src), tris(out)))


if __name__ == "__main__":
    sys.exit(main())
