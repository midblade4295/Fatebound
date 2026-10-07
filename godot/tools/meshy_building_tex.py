#!/usr/bin/env python3
"""Prepare a Meshy building model for the game (0.31.67, Knight shop = giant helm).

Reads Meshy's GLB (one mesh, one 2K baseColor JPEG) and writes, into OUT_DIR:
  <name>.glb        same geometry, texture shrunk to 1K (the blue team's colours)
  <name>_red.png    the 1K texture with the team blue turned red (plume, shields, banners)
  <name>_glow.png   1K emission mask: the bright-yellow window texels inside the glow box (model space)

Usage: meshy_building_tex.py in.glb OUT_DIR name [--glow xmin,xmax,ymin,ymax,zmin,zmax]
"""
import io
import json
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TEX = 1024


def read_glb(path):
    b = open(path, "rb").read()
    jl = struct.unpack_from("<I", b, 12)[0]
    g = json.loads(b[20:20 + jl])
    bl = struct.unpack_from("<I", b, 20 + jl)[0]
    binc = b[20 + jl + 8:20 + jl + 8 + bl]
    return g, binc


def accessor(g, binc, i):
    a = g["accessors"][i]
    bv = g["bufferViews"][a["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a["componentType"]]
    o = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    arr = np.frombuffer(binc, dtype=dt, count=a["count"] * n, offset=o)
    return arr.reshape(a["count"], n) if n > 1 else arr


def hsv(rgb):
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn + 1e-6
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.where(mx == r, (60 * (g - b) / d) % 360, np.where(mx == g, 60 * (b - r) / d + 120, 60 * (r - g) / d + 240))
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    return hue, sat, mx


def hsv_to_rgb(h, s, v):
    h = (h % 360) / 60.0
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    out = np.zeros(h.shape + (3,), np.float32)
    for k, (a, b2, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k
        out[m] = np.stack([a[m], b2[m], c[m]], -1)
    return out


def write_glb(path, g, binc, jpeg):
    # Replace image 0's bytes: rebuild the binary chunk with the new image appended, old view dropped.
    img = g["images"][0]
    old = img["bufferView"]
    views = g["bufferViews"]
    chunks, new_views, remap = [], [], {}
    pos = 0
    for k, v in enumerate(views):
        if k == old:
            continue
        data = binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        pad = (-pos) % 4
        chunks.append(b"\0" * pad)
        pos += pad
        nv = dict(v)
        nv["byteOffset"] = pos
        nv["buffer"] = 0
        remap[k] = len(new_views)
        new_views.append(nv)
        chunks.append(data)
        pos += len(data)
    pad = (-pos) % 4
    chunks.append(b"\0" * pad)
    pos += pad
    new_views.append({"buffer": 0, "byteOffset": pos, "byteLength": len(jpeg)})
    chunks.append(jpeg)
    pos += len(jpeg)
    pad = (-pos) % 4
    chunks.append(b"\0" * pad)
    pos += pad
    for a in g["accessors"]:
        if "bufferView" in a:
            a["bufferView"] = remap[a["bufferView"]]
    for im in g["images"]:
        im["bufferView"] = len(new_views) - 1 if im is img else remap[im["bufferView"]]
        im["mimeType"] = "image/jpeg" if im is img else im.get("mimeType")
    g["bufferViews"] = new_views
    g["buffers"] = [{"byteLength": pos}]
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    body = b"".join(chunks)
    total = 12 + 8 + len(js) + 8 + len(body)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(body), 0x004E4942) + body)


def main():
    src, out, name = sys.argv[1:4]
    box = None
    if "--glow" in sys.argv:
        box = [float(x) for x in sys.argv[sys.argv.index("--glow") + 1].split(",")]
    g, binc = read_glb(src)
    im0 = g["images"][0]
    bv = g["bufferViews"][im0["bufferView"]]
    tex = Image.open(io.BytesIO(binc[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])).convert("RGB")
    W, H = tex.size
    rgb = np.asarray(tex).astype(np.float32) / 255.0
    hue, sat, val = hsv(rgb)

    # Red team: the saturated blues (hue 195-255) turned to a deep red, same saturation and brightness.
    blue = (hue > 195) & (hue < 255) & (sat > 0.35)
    red_rgb = rgb.copy()
    new_h = np.full(hue.shape, 358.0, np.float32)
    red_rgb[blue] = hsv_to_rgb(new_h[blue], np.minimum(sat[blue] * 1.05, 1.0), np.minimum(val[blue] * 0.95, 1.0))
    soft = Image.fromarray((blue * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    k = (np.asarray(soft).astype(np.float32) / 255.0)[..., None]
    red_rgb = rgb * (1 - k) + red_rgb * k

    # Glow: bright, saturated yellow texels used by triangles whose centroid is inside the glow box.
    glow = np.zeros((H, W), np.uint8)
    if box is not None:
        prim = g["meshes"][0]["primitives"][0]
        P = accessor(g, binc, prim["attributes"]["POSITION"])
        UV = accessor(g, binc, prim["attributes"]["TEXCOORD_0"])
        I = accessor(g, binc, prim["indices"]).reshape(-1, 3)
        cen = P[I].mean(1)
        x0, x1, y0, y1, z0, z1 = box
        sel = (cen[:, 0] >= x0) & (cen[:, 0] <= x1) & (cen[:, 1] >= y0) & (cen[:, 1] <= y1) & (cen[:, 2] >= z0) & (cen[:, 2] <= z1)
        region = Image.new("L", (W, H), 0)
        dr = ImageDraw.Draw(region)
        for tri in I[sel]:
            dr.polygon([(float(UV[v, 0]) * W, float(UV[v, 1]) * H) for v in tri], fill=255)
        region = np.asarray(region.filter(ImageFilter.MaxFilter(5))) > 0
        yel = (hue > 36) & (hue < 62) & (val > 0.78) & (sat > 0.62)
        glow = (region & yel).astype(np.uint8) * 255
        print("glow tris in box", int(sel.sum()), "glow texels", int((glow > 0).sum()))
    glow_img = Image.fromarray(glow).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.5))

    small = lambda a: Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)).resize((TEX, TEX), Image.LANCZOS)
    buf = io.BytesIO()
    small(rgb).save(buf, "JPEG", quality=90)
    write_glb(f"{out}/{name}.glb", g, binc, buf.getvalue())
    small(red_rgb).save(f"{out}/{name}_red.png")
    glow_img.resize((TEX, TEX), Image.LANCZOS).save(f"{out}/{name}_glow.png")
    print("blue texels", int(blue.sum()), "->", out)


if __name__ == "__main__":
    main()
