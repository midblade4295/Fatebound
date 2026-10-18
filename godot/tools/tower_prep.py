#!/usr/bin/env python3
"""The 5v5's towers as Meshy models that break as they lose health (0.31.172, Kevin: "new tower models"; picked the
Royal A concepts for the lane tower and the King tower; "I want them to visually break as their health gets lower").

Reads a Meshy image-to-3D GLB (one mesh, one 2K base-colour JPEG) and writes OUT_DIR/<name>.glb + <name>_glow.png:
  - the model stood up in its own units: its foot at y 0, centred on its bounds in x and z, 1.0 tall, its front (the
    side the concept faced: the brazier's gem, the King tower's stairs) on +Z;
  - the texture cut to 1K (the blue team's colours: scripts/siege/tower.gdshader turns them red for red);
  - split into CHUNKS that break off in stages. The surface is cut into cells (farthest-point seeds over the triangles,
    one relaxation step, every triangle to its nearest seed; cells too small join a neighbour); each cell's triangles
    get their own copies of their vertices, and every vertex carries UV2 = (stage, chunk): the stage at which that cell
    breaks off -- 1 at 75 % health, 2 at 50 %, 3 at 25 %, 4 when the tower falls, 9 never (the stump). Stages go by
    height (the roof and the brazier first, then the crenellations, holes in the wall, the body; the foot stays) with a
    seeded shuffle so each tower breaks in its own places. The game hides a broken cell in the tower's mesh (the
    shader, by UV2) and drops a copy of it.
  - the glow mask: the fire and the gem in the brazier (texels of their colours on triangles inside BRAZIER).
Prints the measures the view needs (brazier point, foot radius, chunk counts per stage) for scripts/siege/towers.gd.

  python3 tools/tower_prep.py IN.glb OUT_DIR lane|king    (IN: art_sources/towers/meshy_<kind>.glb)
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_building_tex as mbt  # noqa: E402  (read_glb / accessor / hsv)

TEX = 1024
GLOW_TEX = 512
# per model: cell count; brazier box (normalised: height range, radius) for the glow; the stage bands by height
# [h_from, [p_stage1, p_stage2, p_stage3, p_stage4]] from the top down (the rest of a band's cells: never break)
KIND = {
    "lane": {"cells": 56, "brazier": (0.55, 0.68, 0.13), "seed": 31,
             "bands": [(0.70, [0.15, 0.35, 0.50, 0.0]),        # the roof: a hole first, half at 50 %, the rest at 25 %
                       (0.57, [0.35, 0.35, 0.30, 0.0]),        # the brazier, its pillars, the crenellations
                       (0.44, [0.0, 0.20, 0.45, 0.35]),        # the top of the body: holes, then gone at 25 %
                       (0.22, [0.0, 0.0, 0.12, 0.88]),         # the body: falls with the tower
                       (0.15, [0.0, 0.0, 0.0, 0.35]),          # the stump's jagged top
                       (0.0, [0.0, 0.0, 0.0, 0.0])]},          # the foot: stays
    "king": {"cells": 80, "brazier": (0.55, 0.70, 0.16), "seed": 47,
             "bands": [(0.72, [0.15, 0.35, 0.50, 0.0]),
                       (0.57, [0.30, 0.35, 0.35, 0.0]),
                       (0.40, [0.10, 0.20, 0.35, 0.35]),       # the turret tops (outer cells: see TURRET below)
                       (0.22, [0.0, 0.05, 0.15, 0.80]),
                       (0.14, [0.0, 0.0, 0.0, 0.35]),
                       (0.0, [0.0, 0.0, 0.0, 0.0])]},
}
TURRET = (0.25, 0.62, 0.36)      # King: cells in this height range and beyond this radius are the corner turrets


def load(path):
    g, binc = mbt.read_glb(path)
    pr = g["meshes"][0]["primitives"][0]
    P = mbt.accessor(g, binc, pr["attributes"]["POSITION"]).astype(np.float64)
    N = mbt.accessor(g, binc, pr["attributes"]["NORMAL"]).astype(np.float64)
    UV = mbt.accessor(g, binc, pr["attributes"]["TEXCOORD_0"]).astype(np.float64)
    I = mbt.accessor(g, binc, pr["indices"]).reshape(-1, 3).astype(np.int64)
    im = g["images"][mbt.base_color_image(g)]
    bv = g["bufferViews"][im["bufferView"]]
    tex = Image.open(io.BytesIO(binc[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])).convert("RGB")
    return P, N, UV, I, tex


def cells(cen, area, k, rng):
    # farthest-point seeds (height counts a bit less: cells a little taller than wide), one Lloyd step
    w = np.array([1.0, 0.8, 1.0])
    pts = cen * w
    seeds = [int(rng.integers(len(pts)))]
    d = np.linalg.norm(pts - pts[seeds[0]], axis=1)
    for _ in range(k - 1):
        i = int(np.argmax(d))
        seeds.append(i)
        d = np.minimum(d, np.linalg.norm(pts - pts[i], axis=1))
    S = pts[seeds]
    for _ in range(2):
        lab = np.argmin(((pts[:, None, :] - S[None, :, :]) ** 2).sum(-1), axis=1)
        for j in range(len(S)):
            m = lab == j
            if m.any():
                S[j] = (pts[m] * area[m, None]).sum(0) / area[m].sum()
    lab = np.argmin(((pts[:, None, :] - S[None, :, :]) ** 2).sum(-1), axis=1)
    # cells under 24 triangles join the nearest other cell
    while True:
        counts = np.bincount(lab, minlength=len(S))
        small = [j for j in range(len(S)) if 0 < counts[j] < 24]
        if not small:
            break
        j = small[0]
        others = [o for o in range(len(S)) if o != j and counts[o] > 0]
        o = others[int(np.argmin([np.linalg.norm(S[o] - S[j]) for o in others]))]
        lab[lab == j] = o
    ids = sorted(set(lab.tolist()))
    remap = {v: i for i, v in enumerate(ids)}
    return np.array([remap[v] for v in lab])


def stages(kind, cen, lab, rng):
    spec = KIND[kind]
    n = lab.max() + 1
    out = np.full(n, 9, np.int64)
    for c in range(n):
        m = lab == c
        p = cen[m].mean(0)
        h = p[1]
        r = float(np.hypot(p[0], p[2]))
        probs = None
        for h0, pr in spec["bands"]:
            if h >= h0:
                probs = pr
                break
        if kind == "king" and TURRET[0] <= h <= TURRET[1] and r >= TURRET[2]:
            probs = [0.25, 0.35, 0.40, 0.0]          # a corner turret's top: gone by 25 %
        x = rng.random()
        acc = 0.0
        for s, q in enumerate(probs):
            acc += q
            if x < acc:
                out[c] = s + 1
                break
    return out


def supported(st, cen, lab, P, I):
    """No piece left hanging: a cell breaks off no later than the last of the cells under it (the touching cells -- within
    1 % of the height -- whose middles are lower). Worked from the bottom up, so a roof falls with the last pillar
    holding it and nothing floats over a hole."""
    from scipy.spatial import cKDTree
    n = len(st)
    mid = np.array([cen[lab == c].mean(0) for c in range(n)])
    pts, owner = [], []
    for t, c in zip(I, lab):
        for v in t:
            pts.append(P[v])
            owner.append(c)
    pts = np.array(pts)
    owner = np.array(owner)
    pairs = cKDTree(pts).query_pairs(0.01, output_type="ndarray")
    a, b = owner[pairs[:, 0]], owner[pairs[:, 1]]
    keep = a != b
    touch = {c: set() for c in range(n)}
    for x, y in zip(a[keep], b[keep]):
        touch[int(x)].add(int(y))
        touch[int(y)].add(int(x))
    out = st.copy()
    for c in np.argsort(mid[:, 1]):
        under = [o for o in touch[int(c)] if mid[o, 1] < mid[c, 1] - 0.01]
        if under:
            out[c] = min(out[c], max(out[o] for o in under))
    return out


def write_glb(path, P, N, UV, UV2, I, jpeg):
    parts = []
    views = []
    acc = []
    pos = 0

    def add(arr, target, comp, typ, minmax=False):
        nonlocal pos
        b = arr.tobytes()
        pad = (-pos) % 4
        parts.append(b"\0" * pad)
        pos += pad
        views.append({"buffer": 0, "byteOffset": pos, "byteLength": len(b)} | ({"target": target} if target else {}))
        parts.append(b)
        pos += len(b)
        a = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        acc.append(a)
        return len(acc) - 1

    ip = add(P.astype(np.float32), 34962, 5126, "VEC3", True)
    inn = add(N.astype(np.float32), 34962, 5126, "VEC3")
    iuv = add(UV.astype(np.float32), 34962, 5126, "VEC2")
    iuv2 = add(UV2.astype(np.float32), 34962, 5126, "VEC2")
    ii = add(I.reshape(-1).astype(np.uint32), 34963, 5125, "SCALAR")
    pad = (-pos) % 4
    parts.append(b"\0" * pad)
    pos += pad
    views.append({"buffer": 0, "byteOffset": pos, "byteLength": len(jpeg)})
    parts.append(jpeg)
    pos += len(jpeg)
    parts.append(b"\0" * ((-pos) % 4))
    pos += (-pos) % 4
    g = {"asset": {"version": "2.0", "generator": "fatebound tower_prep.py"},
         "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "tower"}],
         "meshes": [{"name": "tower", "primitives": [{"attributes": {"POSITION": ip, "NORMAL": inn, "TEXCOORD_0": iuv,
                                                                     "TEXCOORD_1": iuv2}, "indices": ii, "material": 0}]}],
         "materials": [{"name": "tower", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0,
                                                                  "roughnessFactor": 0.8}}],
         "textures": [{"source": 0}], "images": [{"bufferView": len(views) - 1, "mimeType": "image/jpeg"}],
         "accessors": acc, "bufferViews": views, "buffers": [{"byteLength": pos}]}
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    body = b"".join(parts)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(body)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(body), 0x004E4942) + body)


def main():
    src, out, kind = sys.argv[1:4]
    spec = KIND[kind]
    rng = np.random.default_rng(spec["seed"])
    P, N, UV, I, tex = load(src)
    # stand it up: foot at 0, centred, 1.0 tall
    lo, hi = P.min(0), P.max(0)
    s = 1.0 / (hi[1] - lo[1])
    P = (P - np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])) * s
    tri = P[I]
    cen = tri.mean(1)
    area = 0.5 * np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1)
    lab = cells(cen, area, spec["cells"], rng)
    st = supported(stages(kind, cen, lab, rng), cen, lab, P, I)
    # every cell its own vertices, triangles in cell order
    order = np.argsort(lab, kind="stable")
    I2 = I[order]
    lab2 = lab[order]
    keys = np.stack([I2.reshape(-1), np.repeat(lab2, 3)], 1)
    uniq, inv = np.unique(keys, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    v = uniq[:, 0]
    c = uniq[:, 1]
    P2, N2, UV1 = P[v], N[v], UV[v]
    UV2 = np.stack([st[c].astype(np.float64), c.astype(np.float64)], 1)
    I3 = inv.reshape(-1, 3)
    # the glow: fire and gem colours on triangles in the brazier
    W, H = tex.size
    rgb = np.asarray(tex).astype(np.float32) / 255.0
    hue, sat, val = mbt.hsv(rgb)
    fire = (hue > 12) & (hue < 48) & (sat > 0.55) & (val > 0.82)
    gem = (hue > 180) & (hue < 225) & (sat > 0.40) & (val > 0.70)
    h0, h1, rr = spec["brazier"]
    r = np.hypot(cen[:, 0], cen[:, 2])
    sel = (cen[:, 1] >= h0) & (cen[:, 1] <= h1) & (r <= rr)
    region = Image.new("L", (W, H), 0)
    dr = ImageDraw.Draw(region)
    for t in I[sel]:
        dr.polygon([(float(UV[k, 0]) * W, float(UV[k, 1]) * H) for k in t], fill=255)
    region = np.asarray(region.filter(ImageFilter.MaxFilter(5))) > 0
    glow = ((fire | gem) & region).astype(np.uint8) * 255
    glow_img = Image.fromarray(glow).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.5))
    # the brazier point: the middle of the gem's triangles (else of the brazier's)
    uvc = UV[I].mean(1)
    tc = rgb[np.clip((uvc[:, 1] * H).astype(int), 0, H - 1), np.clip((uvc[:, 0] * W).astype(int), 0, W - 1)]
    th, ts, tv = mbt.hsv(tc)
    gem_t = sel & (th > 180) & (th < 225) & (ts > 0.40) & (tv > 0.70)
    bp = np.median(cen[gem_t if gem_t.sum() >= 3 else sel], axis=0)
    os.makedirs(out, exist_ok=True)
    buf = io.BytesIO()
    tex.resize((TEX, TEX), Image.LANCZOS).save(buf, "JPEG", quality=90)
    name = "tower_" + kind
    write_glb(os.path.join(out, name + ".glb"), P2, N2, UV1, UV2, I3, buf.getvalue())
    glow_img.resize((GLOW_TEX, GLOW_TEX), Image.LANCZOS).save(os.path.join(out, name + "_glow.png"), optimize=True)
    foot = np.hypot(P[P[:, 1] < 0.05][:, 0], P[P[:, 1] < 0.05][:, 2]).max()
    per = np.bincount(st, minlength=10)
    print("%s: %d triangles, %d -> %d vertices, %d cells; cells breaking at stage 1..4: %s, never: %d" % (
        name, len(I), len(P), len(P2), len(st), per[1:5].tolist(), per[9]))
    print("  triangles per stage 1..4: %s" % [int((st[lab] == k).sum()) for k in (1, 2, 3, 4)])
    print("  size x %.3f z %.3f (height 1); foot radius %.3f; brazier at %s; glow texels %d" % (
        np.ptp(P[:, 0]), np.ptp(P[:, 2]), foot, np.round(bp, 3).tolist(), int(glow.astype(bool).sum())))


if __name__ == "__main__":
    main()
