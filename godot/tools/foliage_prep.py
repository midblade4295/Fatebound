#!/usr/bin/env python3
"""The Rift's trees and bushes (0.31.173, Kevin: "I want better trees and bush models" -- he picked all sixteen of the
concepts: eight trees and eight bushes from the Summer and Enchanted sheets).

Reads a Meshy image-to-3D GLB (one mesh, one base-colour JPEG) and writes OUT_DIR/<name>.glb (+ <name>_glow.png):
  - stood up: its foot at y 0, centred on its bounds in x and z, scaled so it is HEIGHT metres tall (--height) or
    WIDTH metres across its widest side (--width);
  - the texture cut to --tex (1024 trees, 512 bushes);
  - --round R: a model Meshy built shallow (front-on concepts give trees ~half as deep as wide) stretched along its
    shallow side until its footprint is at least R as deep as wide (default 0.85) -- the game sees it from above and
    from every side;
  - --tall R: a mound Meshy built low stretched up until it is at least R as tall as wide (the berry bush);
  - soft normals: welded and smoothed over the model, then, above --from of its height (the canopy; everything for a
    bush), bent half-way to point out from the canopy's middle -- a painted, puffy shading instead of every small
    facet lit on its own;
  - --glow H0,H1,V,S: a glow mask of the texels in that hue range (degrees) at least that bright and saturated (the
    glowing fruits, the blue flowers), for scripts/siege/foliage.gdshader.
  - --like HI.glb: placed, sized and stretched exactly as HI.glb is by the same options (a Meshy remesh of HI keeps its
    frame but may lose thin parts -- a trunk -- so its own bounds would put it elsewhere);
  - --shadow HI.glb (with --like HI.glb): a tree's shadow copy -- the canopy (above --from) pulled in towards its
    middle by 7 % so it lies just inside HI's own (the tree is never darkened on its sunlit side by its own copy), and
    HI's trunk where the remesh dropped it (a thin trunk: HI's triangles wholly below the remesh's foot, up to --from).
Prints its size and triangle count.

  python3 tools/foliage_prep.py IN.glb OUT_DIR NAME (--height H | --width W) [--tex N] [--round R] [--tall R] [--from F]
                                [--glow H0,H1,V,S] [--like HI.glb [--shadow]]
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_building_tex as mbt  # noqa: E402  (read_glb / accessor / hsv / base_color_image)


def write_glb(path, P, N, UV, I, jpeg):
    parts, views, acc = [], [], []
    pos = 0

    def add(arr, target, comp, typ, minmax=False):
        nonlocal pos
        b = arr.tobytes()
        pad = (-pos) % 4
        parts.append(b"\0" * pad)
        pos += pad
        views.append({"buffer": 0, "byteOffset": pos, "byteLength": len(b), "target": target})
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
    ii = add(I.reshape(-1).astype(np.uint32), 34963, 5125, "SCALAR")
    pad = (-pos) % 4
    parts.append(b"\0" * pad)
    pos += pad
    views.append({"buffer": 0, "byteOffset": pos, "byteLength": len(jpeg)})
    parts.append(jpeg)
    pos += len(jpeg)
    parts.append(b"\0" * ((-pos) % 4))
    pos += (-pos) % 4
    g = {"asset": {"version": "2.0", "generator": "fatebound foliage_prep.py"},
         "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "plant"}],
         "meshes": [{"name": "plant", "primitives": [{"attributes": {"POSITION": ip, "NORMAL": inn, "TEXCOORD_0": iuv},
                                                      "indices": ii, "material": 0}]}],
         "materials": [{"name": "plant", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0,
                                                                  "roughnessFactor": 0.9}}],
         "textures": [{"source": 0}], "images": [{"bufferView": len(views) - 1, "mimeType": "image/jpeg"}],
         "accessors": acc, "bufferViews": views, "buffers": [{"byteLength": pos}]}
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    body = b"".join(parts)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(body)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(body), 0x004E4942) + body)


def soft_normals(P, I, frm):
    """Welded, area-weighted smooth normals; above frm of the height bent half-way out from the canopy's middle."""
    key = np.round(P / 1e-4).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    tri = P[I]
    fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])          # (area-weighted: not normalised)
    acc = np.zeros((weld.max() + 1, 3))
    for k in range(3):
        np.add.at(acc, weld[I[:, k]], fn)
    n = acc[weld]
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    h = np.ptp(P[:, 1])
    top = P[:, 1] >= frm * h
    if top.any():
        c = P[top].mean(0)
        c[1] = P[top, 1].min() + (P[top, 1].max() - P[top, 1].min()) * 0.4
        out = P - c
        out /= np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-9)
        n[top] = n[top] * 0.5 + out[top] * 0.5
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    return n


def opt(name, default=None, kind=str):
    return kind(sys.argv[sys.argv.index(name) + 1]) if name in sys.argv else default


def load(path):
    g, binc = mbt.read_glb(path)
    pr = g["meshes"][0]["primitives"][0]
    P = mbt.accessor(g, binc, pr["attributes"]["POSITION"]).astype(np.float64)
    UV = mbt.accessor(g, binc, pr["attributes"]["TEXCOORD_0"]).astype(np.float64)
    I = mbt.accessor(g, binc, pr["indices"]).reshape(-1, 3)
    im = g["images"][mbt.base_color_image(g)]
    bv = g["bufferViews"][im["bufferView"]]
    tex = Image.open(io.BytesIO(binc[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])).convert("RGB")
    return P, UV, I, tex


def placing(P):
    """(offset, scale, stretch) that stand P up as the options say: P' = (P - offset) * scale * stretch."""
    lo, hi = P.min(0), P.max(0)
    size = hi - lo
    if "--height" in sys.argv:
        s = opt("--height", kind=float) / size[1]
    else:
        s = opt("--width", kind=float) / max(size[0], size[2])
    off = np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])
    Q = (P - off) * s
    # round out a shallow footprint
    rr = opt("--round", 0.85, float)
    ex, ez = np.ptp(Q[:, 0]), np.ptp(Q[:, 2])
    stretch = [1.0, 1.0, 1.0]
    if ez < ex * rr:
        stretch[2] = ex * rr / ez
    elif ex < ez * rr:
        stretch[0] = ez * rr / ex
    # --tall R: a mound Meshy built low stretched up until it is at least R as tall as it is wide
    tall = opt("--tall", 0.0, float)
    if tall > 0.0 and np.ptp(Q[:, 1]) < tall * max(ex, ez):
        stretch[1] = tall * max(ex, ez) / np.ptp(Q[:, 1])
    return off, s, np.array(stretch)


def main():
    src, out, name = sys.argv[1:4]
    P, UV, I, tex = load(src)
    like = opt("--like")
    ref = load(like)[0] if like else P
    off, s, stretch = placing(ref)
    P = (P - off) * s * stretch
    frm = opt("--from", 0.0, float)
    if like and "--shadow" in sys.argv:
        HP, HUV, HI_, _ = load(like)
        HP = (HP - off) * s * stretch
        h = np.ptp(HP[:, 1])
        top = P[:, 1] >= frm * h
        c = HP[HP[:, 1] >= frm * h].mean(0)
        P[top] = c + (P[top] - c) * 0.93
        cut = min(frm * h, P[:, 1].min() + 0.15)                           # (only the part of the trunk it lost)
        trunk = HI_[(HP[HI_][:, :, 1] < cut).all(1)]
        I = np.concatenate([I, trunk + len(P)])
        P = np.concatenate([P, HP])
        UV = np.concatenate([UV, HUV])
        used, I = np.unique(I.reshape(-1), return_inverse=True)        # (only the vertices a triangle uses)
        I = I.reshape(-1, 3)
        P, UV = P[used], UV[used]
    N = soft_normals(P, I, frm)
    n = opt("--tex", 1024, int)
    os.makedirs(out, exist_ok=True)
    buf = io.BytesIO()
    tex.resize((n, n), Image.LANCZOS).save(buf, "JPEG", quality=90)
    write_glb(os.path.join(out, name + ".glb"), P, N, UV, I, buf.getvalue())
    glow = opt("--glow")
    texels = 0
    if glow:
        h0, h1, v0, s0 = [float(x) for x in glow.split(",")]
        rgb = np.asarray(tex).astype(np.float32) / 255.0
        hue, sat, val = mbt.hsv(rgb)
        m = (hue >= h0) & (hue <= h1) & (val >= v0) & (sat >= s0)
        texels = int(m.sum())
        gi = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.5))
        gi.resize((max(n // 2, 256), max(n // 2, 256)), Image.LANCZOS).save(os.path.join(out, name + "_glow.png"), optimize=True)
    sz = P.max(0) - P.min(0)
    print("%-17s %5d triangles  %.2f x %.2f x %.2f m%s%s" % (name, len(I), sz[0], sz[1], sz[2],
          ("  (stretched x%.2f)" % stretch.max()) if stretch.max() > 1.0 else "", ("  glow texels %d" % texels) if glow else ""))


if __name__ == "__main__":
    main()
