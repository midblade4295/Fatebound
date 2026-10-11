#!/usr/bin/env python3
"""Line a fitted Armory Reforged weapon's handle up with the hand (0.31.96, Kevin: "go through every weapon and shield
to make sure and line them up correctly with the hands gripping them").

A fitted piece (tools/meshy_weapon.py fit) sits in the space of the KayKit model it replaces, whose hand grips the
origin: for a long weapon the handle runs up +Y through it, centred on X/Z. The fit centred the piece's whole box, so an
axe or a scythe whose head hangs to one side had its handle off to the other side of the hand -- the fist closed on air
next to the haft. This finds the handle and moves the piece onto the hand:

  pole (swords, daggers, axes, hammers, staffs, spears, scythes, wands):
    X/Z  the shaft: of all the columns of the piece, the one that runs through the whole grip band (+-BAND along Y) --
         a blade, a lantern or a feather fills only part of it; then refined to the handle's own centre at the hand.
    Y    only where the hand closes on a guard (swords and daggers: the hand window much wider than the handle just
         below), the nearest stretch of plain handle, at most MAX_DY away.
  shield: the board's back at the middle (where the fist is) GAP in front of the fist's centre. The KayKit shields have
         a handle on the back that the fist closes on; a Meshy board has none, and was fitted by its front face, so a
         thin board floated a hand's width in front of the fist and a thick or domed one swallowed it. The fist sits
         SHIELD_OUT behind the model's origin (siege_view._fit_weapon moves every shield out along the slot's Z),
         shrunk by the template's WEAPON_SCALE.
  book:   a tome's back cover where the open spellbook's cover is at the spine (the hand rests on it): the closed
         tomes are three times as thick and were fitted by their front, so the hand vanished inside them.

  weapon_grip.py measure PIECE.glb TEMPLATE KIND        print the move
  weapon_grip.py apply PIECE.glb TEMPLATE KIND OUT.glb  write the moved piece (the vertices shift; nothing else changes)
"""
import json
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_bounds as gb  # noqa: E402

S = 0.01        # bin size (m in the template's space)
BAND = 0.5      # the grip region looked at, either side of the hand (a hanging lantern or a blade fills only part)
H = 0.14        # the hand's height along the handle
EPS = 0.03      # point-cluster link distance
MAX_DY = 0.08
N = 60000       # surface samples
GAP = 0.07      # a shield board's back in front of the fist's centre (slot units): the knuckles just touch it
VIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "siege", "siege_view.gd")


def _template_name(path):
    d, f = os.path.split(path)
    return ("bits/" if os.path.basename(d) == "bits" else "") + os.path.splitext(f)[0]


def _weapon_scale(name):
    import re
    src = open(VIEW).read()
    m = re.search(r'const WEAPON_SCALE := \{([^}]*)\}', src)
    return float(dict(re.findall(r'"([^"]+)":([0-9.]+)', m.group(1))).get(name, 1.0))


def _clusters(q):
    from scipy.spatial import cKDTree
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    if len(q) < 4:
        return []
    pr = cKDTree(q).query_pairs(EPS, output_type="ndarray")
    n = len(q)
    A = coo_matrix((np.ones(len(pr)), (pr[:, 0], pr[:, 1])), shape=(n, n)) if len(pr) else coo_matrix((n, n))
    _, lab = connected_components(A, directed=False)
    return [q[lab == j] for j in np.unique(lab) if (lab == j).sum() >= 4]


def _column(P, ax):
    m = np.abs(P[:, 1]) <= BAND
    q = P[m]
    xb = np.floor(q[:, ax] / S).astype(int)
    yb = np.floor((q[:, 1] + BAND) / S).astype(int)
    cov = {}
    for x, y in zip(xb, yb):
        cov.setdefault(int(x), set()).add(int(y))
    xs = np.arange(xb.min(), xb.max() + 1)
    c = np.array([len(cov.get(int(x), ())) for x in xs], float)
    good = c >= 0.85 * c.max()
    runs, cur = [], []
    for x, g in zip(xs, good):
        if g:
            cur.append(int(x))
        elif cur:
            runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    r = min(runs, key=lambda r: min(abs(v + 0.5) for v in r))
    return (r[0] + r[-1] + 1) / 2 * S


def _shaft(P, cx, cz):
    """per y-slice near the hand: the width and centre of the point cluster on the shaft"""
    a = P[:, 1]
    ys = np.arange(-BAND, BAND + S / 2, S)
    W = np.full(len(ys), np.nan)
    C = np.full((len(ys), 2), np.nan)
    for i, y in enumerate(ys):
        cs = _clusters(P[np.abs(a - y) <= S][:, [0, 2]])
        if not cs:
            continue
        d = [np.min(np.linalg.norm(c - [cx, cz], axis=1)) for c in cs]
        j = int(np.argmin(d))
        if d[j] > 0.06:
            continue
        b = cs[j]
        W[i] = (b.max(0) - b.min(0)).max()
        C[i] = (b.min(0) + b.max(0)) / 2
    return ys, W, C


def _pole(P, guard):
    cx, cz = _column(P, 0), _column(P, 2)
    ys, W, C = _shaft(P, cx, cz)
    k = int(round(H / 2 / S))
    i0 = int(np.argmin(np.abs(ys)))
    win = np.array([np.nanmax(W[max(0, i - k):i + k + 1]) if np.isfinite(W[max(0, i - k):i + k + 1]).any() else np.nan
                    for i in range(len(ys))])
    dy = 0.0
    if guard and np.isfinite(win[i0]):
        wh = np.nanmin(win[np.abs(ys) <= MAX_DY])
        if win[i0] > 1.25 * wh:
            cand = [i for i in range(len(ys)) if abs(ys[i]) <= MAX_DY and win[i] <= 1.12 * wh]
            dy = float(ys[min(cand, key=lambda i: abs(ys[i]))])
    # the handle's own centre where the hand will be (a curved haft), unless that strays off the column
    near = np.abs(ys - dy) <= H / 2
    c = np.nanmedian(C[near], 0) if np.isfinite(C[near]).any() else np.array([cx, cz])
    if np.linalg.norm(c - [cx, cz]) > 0.08:
        c = np.array([cx, cz])
    return np.array([-c[0], -dy, -c[1]]), dict(column=(cx, cz), centre=tuple(c), dy=dy,
                                                hand_width=float(win[i0]) if np.isfinite(win[i0]) else None)


def _back(P, r=0.12):
    """a shield's back where the fist is (over the slot: x = y = 0)"""
    m = np.hypot(P[:, 0], P[:, 1]) <= r
    return float(np.percentile(P[m][:, 2], 3))


def measure(piece, template, kind):
    P = gb.surface(piece, N)
    if kind == "pole":
        tname = os.path.basename(template)
        return _pole(P, guard=("sword" in tname or "dagger" in tname))
    if kind == "shield":
        name = _template_name(template)
        sc = _weapon_scale(name)
        out = 0.14 if name.startswith("bits/") else 0.15          # (siege_view._fit_weapon)
        fist = -out / sc
        want = fist + GAP / sc
        back = _back(P)
        return np.array([0.0, 0.0, want - back]), dict(fist=fist, back=back, want=want, scale=sc)
    if kind == "book":
        tb, pb = _back(gb.surface(template, N)), _back(P)
        return np.array([0.0, 0.0, tb - pb]), dict(template_back=tb, back=pb)
    raise SystemExit("kind: pole | shield | book")


def translate_glb(src, out, off):
    """the same GLB with every mesh's vertices moved by off (the fitted pieces carry no node transforms)"""
    b = open(src, "rb").read()
    jl = struct.unpack_from("<I", b, 12)[0]
    g = json.loads(b[20:20 + jl])
    bl = struct.unpack_from("<I", b, 20 + jl)[0]
    binc = bytearray(b[28 + jl:28 + jl + bl])
    for n in g["nodes"]:
        if any(k in n for k in ("matrix", "translation", "rotation", "scale")):
            raise SystemExit("%s: node transforms present" % src)
    done = set()
    for m in g["meshes"]:
        for p in m["primitives"]:
            ai = p["attributes"]["POSITION"]
            if ai in done:
                continue
            done.add(ai)
            a = g["accessors"][ai]
            bv = g["bufferViews"][a["bufferView"]]
            if bv.get("byteStride", 12) != 12 or a["componentType"] != 5126:
                raise SystemExit("only packed float positions")
            o = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
            v = np.frombuffer(bytes(binc[o:o + a["count"] * 12]), np.float32).reshape(-1, 3).astype(np.float64) + off
            binc[o:o + a["count"] * 12] = v.astype(np.float32).tobytes()
            a["min"] = [float(x) for x in v.min(0)]
            a["max"] = [float(x) for x in v.max(0)]
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(binc), b"BIN\x00") + bytes(binc)
    with open(out, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def main():
    cmd, a = sys.argv[1], sys.argv[2:]
    off, info = measure(a[0], a[1], a[2])
    print(os.path.basename(a[0]), "move %+.3f %+.3f %+.3f" % tuple(off), info)
    if cmd == "apply":
        translate_glb(a[0], a[3], off)


if __name__ == "__main__":
    main()
