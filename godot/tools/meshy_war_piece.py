#!/usr/bin/env python3
"""The war table's places as Meshy miniatures (0.31.136, Kevin: "I want the war map to be made by you, utilize Meshy
and Eleven").

Pipeline: ElevenLabs concept sheets (gpt-image-2, six miniatures on hex bases a sheet; flow "Fatebound war table"),
Kevin's picks -> tools/meshy_weapon.py crop (one square PNG a place) -> tools/meshy_weapon.py model / wait (Meshy
image-to-3D) -> fit (here) -> assets/meshy/war/<place>.glb, which scripts/app/war_table.gd stands on the place's tile.

  fit IN.glb OUT.glb [--apothem A] [--bottom Y] [--tex N]
      The miniature's hex base laid onto the table's grid: turned about +Y so its sides face the neighbours (corners on
      +-X, flats on +-Z -- the tightest hex around the base's outline, whatever the angle Meshy built it at), scaled so
      that hex's apothem is A (default 1.04: the table's places are 2.4 apart, their coloured ledges 1.19), centred on
      the base, its bottom at Y (default -0.27, the ledge's top). Baked into the vertices (Godot drops a glTF's single
      root transform); the texture shrunk to N (default 1024).
Key from MESHY_KEY for the Meshy steps (never written to disk).
"""
import io
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_bounds as gb  # noqa: E402
import meshy_building_tex as mbt  # noqa: E402

FLATS = [math.radians(a) for a in (0, 60, 120, 180, 240, 300)]   # flat normals: +Z and every 60 deg (corners on +-X)


def hex_fit(xz):
    """-> (turn about +Y in radians, apothem): the turn that makes the smallest hex with flats on FLATS hold xz."""
    best = None
    for k in range(240):
        phi = math.radians(k * 0.25)
        c, s = math.cos(phi), math.sin(phi)
        x = xz[:, 0] * c + xz[:, 1] * s
        z = -xz[:, 0] * s + xz[:, 1] * c
        ap = max(float((x * math.sin(f) + z * math.cos(f)).max()) for f in FLATS)
        if best is None or ap < best[1]:
            best = (phi, ap)
    return best


def fit(src, out, apothem=1.04, bottom=-0.27, tex=1024):
    g, binc = mbt.read_glb(src)
    P = gb.points(src)
    ylo, yhi = P[:, 1].min(), P[:, 1].max()
    base = P[P[:, 1] < ylo + 0.12 * (yhi - ylo)]
    lo, hi = base[:, [0, 2]].min(0), base[:, [0, 2]].max(0)
    centre = (lo + hi) / 2
    phi, ap = hex_fit(base[:, [0, 2]] - centre)
    c, s_ = math.cos(phi), math.sin(phi)
    R = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])
    # re-centre on the fitted hex (the middle between each pair of opposite sides, not the outline's box)
    xz = base[:, [0, 2]] - centre
    rx = xz[:, 0] * c + xz[:, 1] * s_
    rz = -xz[:, 0] * s_ + xz[:, 1] * c
    A, b, half = [], [], []
    for f in FLATS[:3]:
        n = np.array([math.sin(f), math.cos(f)])
        pr = rx * n[0] + rz * n[1]
        A.append(n)
        b.append((pr.max() + pr.min()) / 2)
        half.append((pr.max() - pr.min()) / 2)
    d = np.linalg.lstsq(np.array(A), np.array(b), rcond=None)[0]       # the hex's centre, in the turned frame
    ap = max(half)
    centre = centre + np.array([d[0] * c - d[1] * s_, d[0] * s_ + d[1] * c])   # back to the model's frame
    sc = apothem / ap
    off = np.array([0.0, bottom - ylo * sc, 0.0])
    shift = np.array([centre[0], 0.0, centre[1]])

    binc = bytearray(binc)
    done = set()

    def vec3(ai):
        a = g["accessors"][ai]
        bv = g["bufferViews"][a["bufferView"]]
        if bv.get("byteStride", 12) != 12 or a.get("componentType") != 5126:
            raise SystemExit("only packed float vec3 is handled")
        o = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        return a, o, np.frombuffer(bytes(binc[o:o + a["count"] * 12]), np.float32).reshape(-1, 3).astype(np.float64)

    def bake(ni, parent):
        node = g["nodes"][ni]
        world = parent @ gb.mat(node)
        if "mesh" in node:
            for p in g["meshes"][node["mesh"]]["primitives"]:
                ai = p["attributes"]["POSITION"]
                if ai in done:
                    continue
                done.add(ai)
                a, o, pts = vec3(ai)
                pts = (world[:3, :3] @ pts.T).T + world[:3, 3]
                pts = (R @ (pts - shift).T).T * sc + off
                binc[o:o + a["count"] * 12] = pts.astype(np.float32).tobytes()
                a["min"] = [float(x) for x in pts.min(0)]
                a["max"] = [float(x) for x in pts.max(0)]
                if "NORMAL" in p["attributes"]:
                    na, no, nrm = vec3(p["attributes"]["NORMAL"])
                    nrm = (R @ np.linalg.inv(world[:3, :3]).T @ nrm.T).T
                    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
                    binc[no:no + na["count"] * 12] = nrm.astype(np.float32).tobytes()
                    na["min"] = [float(x) for x in nrm.min(0)]
                    na["max"] = [float(x) for x in nrm.max(0)]
        for k in ("matrix", "translation", "rotation", "scale"):
            node.pop(k, None)
        for ch in node.get("children", []):
            bake(ch, world)

    for r in g["scenes"][g.get("scene", 0)]["nodes"]:
        bake(r, np.eye(4))
    binc = bytes(binc)
    bv = g["bufferViews"][g["images"][mbt.base_color_image(g)]["bufferView"]]
    raw = binc[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
    img = Image.open(io.BytesIO(raw)).convert("RGB")
    if img.size[0] != tex:
        img = img.resize((tex, tex), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=88)
    mbt.write_glb(out, g, binc, buf.getvalue())
    Q = gb.points(out)
    tris = sum(g["accessors"][p["indices"]]["count"] // 3 for m in g["meshes"] for p in m["primitives"] if "indices" in p)
    print("%s: turned %.1f deg, scale %.4f, height %.2f, base %.2f..%.2f x %.2f..%.2f, %d tris" % (
        os.path.basename(out), math.degrees(phi), sc, Q[:, 1].max() - Q[:, 1].min(), Q[:, 0].min(), Q[:, 0].max(),
        Q[:, 2].min(), Q[:, 2].max(), tris))


def main():
    a = sys.argv[1:]
    if len(a) < 3 or a[0] != "fit":
        raise SystemExit(__doc__)
    opt = {"--apothem": 1.04, "--bottom": -0.27, "--tex": 1024}
    rest = []
    i = 1
    while i < len(a):
        if a[i] in opt:
            opt[a[i]] = type(opt[a[i]])(a[i + 1])
            i += 2
        else:
            rest.append(a[i])
            i += 1
    fit(rest[0], rest[1], opt["--apothem"], opt["--bottom"], opt["--tex"])


if __name__ == "__main__":
    main()
