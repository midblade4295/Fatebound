#!/usr/bin/env python3
"""The war map's land (0.31.137, Kevin: "I don't like how static the map looks. I want it to look like a real natural
land mass but in map form").

One continent in the sea, grown around the places of scripts/meta/war_map.gd: a coast with bays, mountains in the
north (High Pass, Deep Mine, Grey Cliffs, behind Stags' Keep), a river from the mountains under King's Bridge into
Silver Lake, out across the Ford and down to the south coast, marsh and fen in the south-east, farmland around the
Lions, forest at Kingswood, dirt roads along the links, and a rocky ridge on every border two places share without a
link (so the land says where an attack can go). Each place's miniature stands on a flat clearing.

  python3 tools/war_land.py [OUT_DIR]      (default assets/war_land)

Writes (table units: x right, z toward the viewer, y up; sea level 0 -- the same frame as war_table.gd):
  land.glb         the land mesh (a height grid, UV over the whole map)
  land_color.jpg   its painted colours (texture over UV)
  land_regions.png R = place index (255 = sea), G = distance to a border (0 at the line), B = 255 on a border with no
                   link (a ridge), A = height (0 = sea floor -0.4 .. 255 = 2.15), for the shaders (sea depth, foam)
  scripts/app/war_land_data.gd   the grid, each place's spot (x, z, ground height, its miniature, how it stands)
"""
import json
import math
import os
import re
import struct
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "war_land")
DATA = os.path.join(ROOT, "scripts", "app", "war_land_data.gd")
X0, X1, Z0, Z1 = -6.0, 6.0, -9.0, 9.0     # the map's square in table units
STEP = 0.09                               # the mesh's grid
TEX_W, TEX_H = 1024, 1536                 # colours
REG_W, REG_H = 512, 768                   # regions
H_MIN, H_MAX = -0.4, 2.15                 # what the A channel spans
RNG = np.random.default_rng(1179)

# ---------------- the places (scripts/meta/war_map.gd) ----------------
src = open(os.path.join(ROOT, "scripts", "meta", "war_map.gd")).read()
PL = {}
for m in re.finditer(r'"(\w+)":\s*\{"name": "([^"]+)",\s*"p": Vector2\(([\d.]+), ([\d.]+)\),\s*"home": "(\w*)"', src):
    px, py = float(m.group(3)), float(m.group(4))
    PL[m.group(1)] = {"name": m.group(2), "x": (py - 2.65) * 2.0, "z": (3.8 - px) * 2.0, "home": m.group(5)}
LINKS = set(tuple(sorted(l)) for l in re.findall(r'\["(\w+)", "(\w+)"\]', src))
IDS = list(PL)                            # region index = order in war_map.gd's T
assert len(IDS) == 18 and len(LINKS) == 30, (len(IDS), len(LINKS))

# what stands on each place: a Meshy miniature sunk into its clearing (base top just under the ground), or the land
# itself (the lake and the ford are the water) -- scale, the base's top (model units) and a turn (degrees)
PIECES = {   # scale, the ground's height in the trimmed model (tools/meshy_war_piece.py trim), turn
    "home_lions": (0.72, 0.075, 0), "home_stags": (0.72, 0.05, 0), "home_ravens": (0.72, 0.069, 0),
    "mill": (0.62, 0.065, 0), "tower": (0.62, 0.111, 0), "abbey": (0.62, 0.036, 0), "pass": (0.6, 0.222, 0),
    "quarry": (0.6, 0.162, 0), "bridge": (0.6, 0.054, 90), "mine": (0.62, 0.167, 0), "marsh": (0.6, 0.199, 0),
    "woods": (0.62, 0.129, 0), "forge": (0.62, 0.046, 0), "cliffs": (0.6, 0.124, 0), "fen": (0.6, 0.16, 0),
    "port": (0.62, 0.182, 0),
}
LAND_ONLY = {"lake", "ford"}


def grid(w, h):
    xs = np.linspace(X0, X1, w)
    zs = np.linspace(Z0, Z1, h)
    return np.meshgrid(xs, zs)


def noise(w, h, cells, amp=1.0, seed_off=0):
    """smooth value noise: a random lattice cells wide, cubic-upsampled to w x h"""
    r = np.random.default_rng(1179 + seed_off)
    cw = max(2, int(cells))
    ch = max(2, int(round(cells * h / w)))
    lat = r.standard_normal((ch + 4, cw + 4))
    z = ndimage.zoom(lat, (h * (ch + 4) / ch / (ch + 4), w * (cw + 4) / cw / (cw + 4)), order=3)
    return z[:h, :w] * amp


def fbm(w, h, base_cells, octaves=5, seed_off=0, gain=0.5):
    out = np.zeros((h, w))
    a, c, tot = 1.0, base_cells, 0.0
    for o in range(octaves):
        out += noise(w, h, c, a, seed_off + o * 17)
        tot += a
        a *= gain
        c *= 2
    return out / tot


def segdist(X, Z, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    t = np.clip(((X - ax) * dx + (Z - az) * dz) / (dx * dx + dz * dz + 1e-9), 0, 1)
    return np.hypot(X - (ax + t * dx), Z - (az + t * dz))


def polydist(X, Z, pts):
    d = np.full(X.shape, 1e9)
    for i in range(len(pts) - 1):
        d = np.minimum(d, segdist(X, Z, pts[i], pts[i + 1]))
    return d


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def P(i):
    return (PL[i]["x"], PL[i]["z"])


def meander(pts, amp, seed):
    """a line through pts with bends between them"""
    r = np.random.default_rng(seed)
    out = []
    for i in range(len(pts) - 1):
        (ax, az), (bx, bz) = pts[i], pts[i + 1]
        nx, nz = -(bz - az), bx - ax
        ln = math.hypot(nx, nz) + 1e-9
        nx, nz = nx / ln, nz / ln
        ph = r.uniform(0, math.tau)
        for t in np.linspace(0, 1, 7)[:-1]:
            off = math.sin(t * math.pi * 2 + ph) * amp * math.sin(t * math.pi)
            out.append((ax + (bx - ax) * t + nx * off, az + (bz - az) * t + nz * off))
    out.append(pts[-1])
    return out


# the river: from the northern mountains past the mine, under King's Bridge, through Silver Lake, across the Ford, to
# the south coast between the Quarry and the Marsh
RIVER = meander([(0.3, -8.6), (0.0, -6.9), (-0.45, -5.6), (-0.6, -3.7), (-1.0, -2.3), (-1.0, -0.9), (-1.0, 0.6),
                 (-1.05, 1.4), (-1.0, 2.2), (-0.5, 3.0), (-0.15, 4.2), (0.05, 5.4), (0.0, 6.6), (0.25, 8.6)], 0.16, 7)
# mountain ranges: (line, half width, height)
RANGES = [
    ([(-5.0, -7.6), (-3.4, -7.9), (-1.6, -8.0), (0.4, -7.7), (2.2, -7.1), (3.4, -6.0)], 0.95, 1.45),   # the north
    ([(-4.6, -6.4), (-4.4, -4.6), (-4.2, -3.0)], 0.55, 1.05),                                        # west of the pass
    ([(-2.4, -5.4), (-2.05, -3.2)], 0.45, 0.95),                                                     # east of the pass
    ([(0.4, -5.6), (1.1, -4.6), (2.2, -4.3)], 0.6, 1.2),                                             # above the cliffs
    ([(2.6, -4.6), (3.7, -3.9)], 0.45, 0.85),                                                        # the east cliffs
]
FORESTS = [("woods", 1.45, 1.0), ("home_stags", 1.15, 0.9), ("pass", 0.8, 0.6), ("abbey", 0.75, 0.55), ("tower", 0.7, 0.45),
           ("cliffs", 0.6, 0.4), ("forge", 0.55, 0.35)]
FARMS = [("home_lions", 1.5), ("mill", 1.3), ("quarry", 0.8)]


def build(w, h):
    """everything at one resolution: heights, the masks the colours use, the regions"""
    X, Z = grid(w, h)
    wx = fbm(w, h, 4, 4, 1) * 0.45
    wz = fbm(w, h, 4, 4, 2) * 0.45
    pts = np.array([P(i) for i in IDS])
    # ---- regions: nearest place in a warped frame; the second nearest says which border is near
    WX, WZ = X + wx, Z + wz
    dd = np.sqrt((WX[..., None] - pts[:, 0]) ** 2 + (WZ[..., None] - pts[:, 1]) ** 2)
    order = np.argsort(dd, -1)
    lab, second = order[..., 0], order[..., 1]
    srt = np.take_along_axis(dd, order[..., :2], -1)
    gap = (srt[..., 1] - srt[..., 0]) * 0.5
    del dd, order
    unlinked = np.zeros(X.shape, bool)
    for a in range(len(IDS)):
        for b in range(len(IDS)):
            if a != b and tuple(sorted((IDS[a], IDS[b]))) not in LINKS:
                unlinked |= (lab == a) & (second == b)
    # ---- the coast: one land, within reach of the places (homes further), bays and capes from noise
    reach = np.full(X.shape, -9.0)
    for i in IDS:
        R = 2.0 if PL[i]["home"] else 1.75
        reach = np.maximum(reach, 1 - np.hypot(X + wx * 1.6 - PL[i]["x"], Z + wz * 1.6 - PL[i]["z"]) / R)
    coast = reach + fbm(w, h, 6, 5, 3) * 0.22
    land0 = coast > 0
    lb, n = ndimage.label(land0)
    sizes = ndimage.sum(land0, lb, range(1, n + 1))
    main = lb == (int(np.argmax(sizes)) + 1)
    # a few islets off the coast, where the noise made them big enough
    near = ndimage.distance_transform_edt(~main) * ((X1 - X0) / w) < 1.1
    keep = main.copy()
    for k in range(1, n + 1):
        if k - 1 != int(np.argmax(sizes)) and sizes[k - 1] > w * h * 0.0004:
            m = lb == k
            if (m & near).any():
                keep |= m
    inland = ndimage.distance_transform_edt(keep) * ((X1 - X0) / w)
    seadist = ndimage.distance_transform_edt(~keep) * ((X1 - X0) / w)
    land = smooth(0.0, 0.5, inland)
    hgt = np.where(keep, 0.04 + 0.2 * land, -0.06 - 0.5 * smooth(0.0, 1.6, seadist))
    hgt += fbm(w, h, 16, 4, 4) * 0.05 * land
    # gentle hills everywhere inland
    hills = fbm(w, h, 8, 4, 8)
    hgt += np.clip(hills, 0, None) * 0.35 * land
    # ---- mountain ranges, and a rocky ridge on every border without a link
    ridged = np.clip(1 - np.abs(fbm(w, h, 10, 5, 5)), 0, 1) ** 2.0
    mount = np.zeros(X.shape)
    for line, hw, ht in RANGES:
        d = polydist(X + wx * 0.6, Z + wz * 0.6, line)
        prof = np.exp(-(d / hw) ** 2)
        mount = np.maximum(mount, prof * ht)
    hgt += land * mount * (0.35 + 0.95 * ridged)
    ridge = np.exp(-(gap / 0.2) ** 2) * unlinked * land
    hgt += ridge * (0.22 + 0.5 * ridged)
    rocky = np.clip(mount * 1.1 + ridge * 0.9, 0, 1)
    # ---- water: the river, Silver Lake, the marsh and the fen
    rd = polydist(X + wx * 0.15, Z + wz * 0.15, RIVER)
    width = 0.07 + 0.06 * smooth(-3, 6, Z)
    river = smooth(width + 0.07, width, rd) * keep
    lake_d = np.hypot((X - P("lake")[0]) + wx * 0.7, (Z - P("lake")[1]) * 0.8 + wz * 0.7)
    lake = smooth(0.92, 0.68, lake_d)
    wet = np.zeros(X.shape)
    for i, r in (("marsh", 1.05), ("fen", 1.15)):
        wet = np.maximum(wet, smooth(r, r * 0.45, np.hypot(X - P(i)[0] + wx * 0.5, Z - P(i)[1] + wz * 0.5)))
    wet *= keep
    pools = fbm(w, h, 26, 3, 6)
    hgt = np.where(wet > 0, hgt * (1 - wet) + (0.03 + 0.05 * pools) * wet, hgt)
    pool = (wet > 0.35) & (pools < -0.1)
    # the port: the sea comes up to its quay on the east
    port_d = np.hypot((X - (P("port")[0] + 0.75)) * 0.8, Z - P("port")[1])
    harbour = smooth(0.62, 0.4, port_d)
    # ---- the clearings: each miniature on level ground at about the height around it
    pre = hgt.copy()
    blur = ndimage.gaussian_filter(hgt, 0.5 / ((X1 - X0) / w))
    pads = {}
    for i in IDS:
        if i in LAND_ONLY:
            continue
        r = np.hypot(X - P(i)[0], Z - P(i)[1])
        gi, gj = int((P(i)[0] - X0) / (X1 - X0) * (w - 1)), int((P(i)[1] - Z0) / (Z1 - Z0) * (h - 1))
        target = float(np.clip(blur[gj, gi], 0.12, 0.55))
        if i in ("marsh", "fen", "port"):
            target = 0.1
        k = smooth(0.72, 0.42, r)
        hgt = hgt * (1 - k) + target * k
        pads[i] = target
    # water last (the bridge's clearing keeps its river)
    hgt = hgt * (1 - river) + np.minimum(hgt, -0.08) * river
    hgt = hgt * (1 - lake) + np.minimum(hgt, -0.15) * lake
    hgt = np.where(pool, np.minimum(hgt, -0.03), hgt)
    hgt = hgt * (1 - harbour) + np.minimum(hgt, -0.14) * harbour
    return {"h": hgt, "pre": pre, "lab": lab, "gap": gap, "unlinked": unlinked, "land": land, "keep": keep,
            "river": river, "lake": lake, "wet": wet, "pool": pool, "rocky": rocky, "mount": mount, "ridge": ridge,
            "X": X, "Z": Z, "wx": wx, "wz": wz, "pads": pads, "seadist": seadist}


def colours(m):
    hgt, pre = m["h"], m["pre"]
    X, Z = m["X"], m["Z"]
    h, w = hgt.shape
    gz, gx = np.gradient(pre, (Z1 - Z0) / (h - 1), (X1 - X0) / (w - 1))
    slope = np.hypot(gx, gz)
    n1 = fbm(w, h, 24, 4, 11)
    n2 = fbm(w, h, 70, 3, 12)
    n3 = fbm(w, h, 140, 2, 14)
    C = lambda s: np.array([int(s[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])
    mix = lambda a, b, t: a * (1 - t[..., None]) + b * t[..., None]
    t = np.clip(0.5 + n1 * 1.3, 0, 1)
    col = mix(np.broadcast_to(C("#5e9a3a"), X.shape + (3,)), np.broadcast_to(C("#8bb956"), X.shape + (3,)), t)
    col = mix(col, np.broadcast_to(C("#4a8233"), col.shape), np.clip(n2 * 1.6, 0, 0.4))
    # farmland: a patchwork of fields with hedges around the Lions, the Mill, the Quarry
    farm = np.zeros(X.shape)
    for i, r in FARMS:
        farm = np.maximum(farm, smooth(r, r * 0.6, np.hypot(X - P(i)[0] + m["wx"] * 0.8, Z - P(i)[1] + m["wz"] * 0.8)))
    farm *= (slope < 0.7) * (m["mount"] < 0.3) * m["keep"]
    ang = 0.35
    u = (X * math.cos(ang) + Z * math.sin(ang)) * 4.6 + m["wx"] * 0.6
    v = (-X * math.sin(ang) + Z * math.cos(ang)) * 3.3 + m["wz"] * 0.6
    ci = np.floor(u).astype(int) * 7 + np.floor(v).astype(int) * 13
    pal = [C("#c8b25a"), C("#9cbf56"), C("#b39d4a"), C("#76a845"), C("#d6c46e"), C("#8aa94e")]
    fc = np.zeros_like(col)
    for k, c in enumerate(pal):
        fc[(ci % len(pal)) == k] = c
    rnd = (np.sin(ci * 12.9898) * 43758.5453) % 1.0
    fc = fc * (0.86 + 0.18 * rnd)[..., None] * (0.95 + 0.05 * np.clip(n3 * 3, -1, 1))[..., None]
    # furrows along each field, a hedge round it
    furrow = 0.5 + 0.5 * np.sin((u if True else v) * math.tau * 9.0)
    fc = fc * (0.93 + 0.07 * furrow)[..., None]
    hedge = (np.abs((u % 1.0) - 0.5) > 0.47) | (np.abs((v % 1.0) - 0.5) > 0.465)
    fc[hedge] = C("#557a35")
    col = mix(col, fc, farm * 0.6)
    # forests: dark canopy with lighter crowns
    forest = np.zeros(X.shape)
    for i, r, a in FORESTS:
        forest = np.maximum(forest, a * smooth(r, r * 0.35, np.hypot(X - P(i)[0] + m["wx"] * 0.9, Z - P(i)[1] + m["wz"] * 0.9)))
    forest = np.maximum(forest, smooth(0.32, 0.5, fbm(w, h, 11, 4, 13)) * 0.85)
    forest *= (1 - farm) * (pre > 0.1) * (m["rocky"] < 0.55) * (1 - m["wet"])
    n4 = fbm(w, h, 260, 1, 15)
    crowns = np.clip(n4 * 3.0 + 0.5, 0, 1)
    lit = np.clip((np.roll(n4, 2, 0) - n4) * 6 + 0.5, 0, 1)        # each crown lit on its north side
    canopy = mix(np.broadcast_to(C("#24502a"), col.shape), np.broadcast_to(C("#4f8f3e"), col.shape), crowns * 0.7 + lit * 0.3)
    col = mix(col, canopy, np.clip(forest * 1.25, 0, 1))
    # marsh and fen: olive reed beds and dark pools
    reeds = mix(np.broadcast_to(C("#7b8a4a"), col.shape), np.broadcast_to(C("#5c6b3a"), col.shape), np.clip(n2 * 2 + 0.5, 0, 1))
    col = mix(col, reeds, m["wet"] * 0.85)
    # rock and snow on the mountains
    rock = np.clip(smooth(0.5, 1.0, slope) * smooth(0.12, 0.3, pre) + smooth(0.55, 0.85, pre) + m["ridge"] * 0.6, 0, 1)
    rc = mix(np.broadcast_to(C("#7b766c"), col.shape), np.broadcast_to(C("#a8a296"), col.shape), np.clip(n1 + n3 + 0.5, 0, 1))
    col = mix(col, rc, rock)
    snow = smooth(1.15, 1.4, pre + n2 * 0.2)
    col = mix(col, np.broadcast_to(C("#f0f3f6"), col.shape), snow)
    # beaches, river banks, the sea floor
    beach = smooth(0.1, 0.04, hgt) * (1 - m["wet"]) * smooth(0.6, 0.0, m["seadist"]) * m["keep"]
    col = mix(col, np.broadcast_to(C("#dcc791"), col.shape), beach)
    under = smooth(0.0, -0.1, hgt)
    col = mix(col, np.broadcast_to(C("#c2b080"), col.shape), under)
    col = mix(col, np.broadcast_to(C("#16324a"), col.shape), smooth(-0.12, -0.35, hgt))
    # roads along the links (dirt, not through water)
    road = np.zeros(X.shape)
    for a, b in LINKS:
        ax, az = P(a)
        bx, bz = P(b)
        path = meander([(ax, az), (bx, bz)], 0.12, hash((a, b)) % 1000)
        road = np.maximum(road, smooth(0.04, 0.018, polydist(X, Z, path)))
    road *= (hgt > 0.02) * (1 - snow) * (1 - m["wet"])
    col = mix(col, np.broadcast_to(C("#b8996a"), col.shape), road * 0.8)
    # relief: the slopes lit from the north-west, so the land reads on a small screen
    hz, hx = np.gradient(hgt, (Z1 - Z0) / (h - 1), (X1 - X0) / (w - 1))
    shade = np.clip(1.0 + (hx * 0.28 + hz * 0.28), 0.72, 1.18)
    col *= shade[..., None]
    m["forest"] = forest
    m["road"] = road
    return np.clip(col, 0, 1)


def write_glb(path, pos, nrm, uv, idx):
    pos = pos.astype(np.float32)
    nrm = nrm.astype(np.float32)
    uv = uv.astype(np.float32)
    idx = idx.astype(np.uint32)
    blobs = [pos.tobytes(), nrm.tobytes(), uv.tobytes(), idx.tobytes()]
    offs, b = [], b""
    for bl in blobs:
        offs.append(len(b))
        b += bl + b"\0" * ((4 - len(bl) % 4) % 4)
    g = {"asset": {"version": "2.0", "generator": "war_land.py"}, "scene": 0, "scenes": [{"nodes": [0]}],
         "nodes": [{"mesh": 0, "name": "land"}],
         "meshes": [{"name": "land", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                                                     "indices": 3, "material": 0}]}],
         "materials": [{"name": "land", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0,
                                                                 "roughnessFactor": 0.95}}],
         "buffers": [{"byteLength": len(b)}],
         "bufferViews": [{"buffer": 0, "byteOffset": offs[0], "byteLength": len(blobs[0]), "target": 34962},
                         {"buffer": 0, "byteOffset": offs[1], "byteLength": len(blobs[1]), "target": 34962},
                         {"buffer": 0, "byteOffset": offs[2], "byteLength": len(blobs[2]), "target": 34962},
                         {"buffer": 0, "byteOffset": offs[3], "byteLength": len(blobs[3]), "target": 34963}],
         "accessors": [{"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3",
                        "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
                       {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
                       {"bufferView": 2, "componentType": 5126, "count": len(uv), "type": "VEC2"},
                       {"bufferView": 3, "componentType": 5125, "count": len(idx), "type": "SCALAR"}]}
    js = json.dumps(g).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(b))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(b), 0x004E4942) + b
    open(path, "wb").write(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    MW, MH = TEX_W, TEX_H
    m = build(MW, MH)
    hm = m["h"]
    # ---- colours
    col = colours(m)
    Image.fromarray((col * 255).astype(np.uint8)).save(os.path.join(OUT, "land_color.jpg"), quality=90)
    # ---- the mesh: the heights sampled on its grid
    w = int(round((X1 - X0) / STEP)) + 1
    h = int(round((Z1 - Z0) / STEP)) + 1
    X, Z = grid(w, h)
    fi = (X - X0) / (X1 - X0) * (MW - 1)
    fj = (Z - Z0) / (Z1 - Z0) * (MH - 1)
    hs = ndimage.gaussian_filter(hm, 0.8)
    hg = ndimage.map_coordinates(hs, [fj.ravel(), fi.ravel()], order=1).reshape(h, w)
    hg = np.maximum(hg, H_MIN)
    pos = np.stack([X, hg, Z], -1).reshape(-1, 3)
    gz, gx = np.gradient(hg, (Z1 - Z0) / (h - 1), (X1 - X0) / (w - 1))
    nrm = np.stack([-gx, np.ones_like(gx), -gz], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    uv = np.stack([(X - X0) / (X1 - X0), (Z - Z0) / (Z1 - Z0)], -1).reshape(-1, 2)
    ii = np.arange(w * h).reshape(h, w)
    a, b, c, d = ii[:-1, :-1], ii[:-1, 1:], ii[1:, :-1], ii[1:, 1:]
    idx = np.stack([a, c, b, b, c, d], -1).reshape(-1)        # (counter-clockwise from above)
    write_glb(os.path.join(OUT, "land.glb"), pos, nrm.reshape(-1, 3), uv, idx)
    # ---- regions (half the colours' size)
    sl = (slice(None, None, 2), slice(None, None, 2))
    lab = m["lab"][sl]
    landmask = m["keep"][sl] | (m["lake"][sl] > 0.3)
    R = np.where(landmask, lab, 255).astype(np.uint8)
    edge = np.zeros(R.shape, bool)
    edge[:, 1:] |= (R[:, 1:] != R[:, :-1]) & (R[:, 1:] != 255) & (R[:, :-1] != 255)
    edge[1:, :] |= (R[1:, :] != R[:-1, :]) & (R[1:, :] != 255) & (R[:-1, :] != 255)
    dist = ndimage.distance_transform_edt(~edge) * ((X1 - X0) / R.shape[1])
    G = np.clip(dist / 0.4 * 255, 0, 255).astype(np.uint8)
    B = (m["unlinked"][sl] & (m["gap"][sl] < 0.22) & landmask).astype(np.uint8) * 255
    A = np.clip((hm[sl] - H_MIN) / (H_MAX - H_MIN) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(np.stack([R, G, B, A], -1), "RGBA").save(os.path.join(OUT, "land_regions.png"))
    # ---- where things stand
    def h_at(x, z):
        return float(ndimage.map_coordinates(hg, [[(z - Z0) / STEP], [(x - X0) / STEP]], order=1)[0])
    places = {}
    for i in IDS:
        x, z = P(i)
        e = {"x": round(x, 3), "z": round(z, 3), "y": round(h_at(x, z), 3), "index": IDS.index(i)}
        if i in PIECES:
            sc, top, yaw = PIECES[i]
            e.update({"piece": i, "scale": sc, "sink": round(-(top + 0.035) * sc, 4), "yaw": yaw})
        places[i] = e
    # trees: 3D ones over the painted forests (a jittered grid, thinned by the forest's density), not on a clearing,
    # a road or water
    r = np.random.default_rng(42)
    trees = []
    sp = 0.15
    for zz in np.arange(Z0 + 0.2, Z1 - 0.2, sp):
        for xx in np.arange(X0 + 0.2, X1 - 0.2, sp):
            x = xx + r.uniform(-0.45, 0.45) * sp
            z = zz + r.uniform(-0.45, 0.45) * sp
            ti = int((x - X0) / (X1 - X0) * (MW - 1))
            tj = int((z - Z0) / (Z1 - Z0) * (MH - 1))
            f = m["forest"][tj, ti]
            if f < 0.5 or r.random() > (f - 0.4) * 1.4 or m["road"][tj, ti] > 0.2 or hm[tj, ti] < 0.06 or m["rocky"][tj, ti] > 0.5:
                continue
            if any(math.hypot(x - P(i)[0], z - P(i)[1]) < 0.62 for i in IDS):
                continue
            trees.append([round(x, 3), round(h_at(x, z), 3), round(z, 3), round(r.uniform(0.22, 0.34), 3), int(r.integers(0, 2))])
    # the numbers the game needs, as a script (always in the build, unlike a .json)
    lines = ["extends RefCounted",
             "# Made by tools/war_land.py with assets/war_land/ -- don't edit by hand: run it again.",
             "const X0 := %.3f" % X0, "const X1 := %.3f" % X1, "const Z0 := %.3f" % Z0, "const Z1 := %.3f" % Z1,
             "const H_MIN := %.3f" % H_MIN, "const H_MAX := %.3f" % H_MAX,
             "const IDS := %s" % json.dumps(IDS), "const PLACES := {"]
    for i in IDS:
        lines.append('\t"%s": %s,' % (i, json.dumps(places[i])))
    lines.append("}")
    lines.append("# [x, ground, z, size, kind]: the 3D trees over the forests")
    lines.append("const TREES := %s" % json.dumps(trees))
    data = DATA if OUT == os.path.join(ROOT, "assets", "war_land") else os.path.join(OUT, "war_land_data.gd")
    open(data, "w").write("\n".join(lines) + "\n")
    print("land: %dx%d grid, %d tris, heights %.2f..%.2f; colours %dx%d; regions %dx%d; %d trees" % (
        w, h, len(idx) // 3, hg.min(), hg.max(), MW, MH, R.shape[1], R.shape[0], len(trees)))


if __name__ == "__main__":
    main()
