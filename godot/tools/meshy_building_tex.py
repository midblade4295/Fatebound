#!/usr/bin/env python3
"""Prepare a Meshy building model for the game (0.31.67, Knight shop = giant helm).

Reads Meshy's GLB (one mesh, one 2K baseColor JPEG) and writes, into OUT_DIR:
  <name>.glb        same geometry, texture shrunk to 1K (the blue team's colours)
  <name>_red.png    the 1K texture with the team blue turned red (plume, shields, banners)
  <name>_glow.png   1K emission mask: the bright-yellow window texels inside the glow box (model space)

Usage: meshy_building_tex.py in.glb OUT_DIR name [--glow BOX[:RULE]]... [--color-glow]
  BOX  = xmin,xmax,ymin,ymax,zmin,zmax (model units; a triangle counts if its centroid is inside)
  RULE = hue_lo,hue_hi,min_value,min_saturation (default 36,62,0.78,0.62 = lit yellow windows)
  --color-glow: the mask carries the texture's own colours (stained glass, water) -- use with a white emission colour.
  --dilate N: grow each glow box's triangles by N texels before the colour rule (default 5; the outposts use 3, as
    Meshy's small UV islands sit next to unrelated ones and a wider margin lights their texels too)
  --tex N: the texture's size (default 1024; small props use 512)
  --no-red: skip <name>_red.png -- the outposts (0.31.73) recolour the one texture in a shader (team_swap.gdshader).
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


def base_color_image(g):
    # The image the first material's base colour uses (Meshy's remeshed models carry normal and
    # metallic-roughness maps too, in another order).
    try:
        tex = g["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
        return g["textures"][tex]["source"]
    except (KeyError, IndexError):
        return 0


def write_glb(path, g, binc, jpeg):
    # Keep only the base colour texture, as the given JPEG: every image's old buffer view is dropped, the
    # material keeps just its base colour (the shaders here use the colour texture only).
    image_views = {im["bufferView"] for im in g["images"] if "bufferView" in im}
    views = g["bufferViews"]
    chunks, new_views, remap = [], [], {}
    pos = 0
    for k, v in enumerate(views):
        if k in image_views:
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
    for acc in g["accessors"]:
        if "bufferView" in acc:
            acc["bufferView"] = remap[acc["bufferView"]]
    g["bufferViews"] = new_views
    g["buffers"] = [{"byteLength": pos}]
    g["images"] = [{"bufferView": len(new_views) - 1, "mimeType": "image/jpeg"}]
    sampler = g["textures"][0].get("sampler") if g.get("textures") else None
    g["textures"] = [{"source": 0} if sampler is None else {"source": 0, "sampler": sampler}]
    mat = g["materials"][0]
    pbr = dict(mat.get("pbrMetallicRoughness", {}))
    pbr.pop("metallicRoughnessTexture", None)
    pbr["baseColorTexture"] = {"index": 0}
    mat["pbrMetallicRoughness"] = pbr
    mat.pop("normalTexture", None)
    mat.pop("occlusionTexture", None)
    mat.pop("emissiveTexture", None)
    g["materials"] = [mat]
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
    specs = []
    for k, a in enumerate(sys.argv):
        if a == "--glow":
            box_s, _, rule_s = sys.argv[k + 1].partition(":")
            specs.append(([float(x) for x in box_s.split(",")], [float(x) for x in (rule_s or "36,62,0.78,0.62").split(",")]))
    color_glow = "--color-glow" in sys.argv
    dilate = int(sys.argv[sys.argv.index("--dilate") + 1]) if "--dilate" in sys.argv else 5
    global TEX
    TEX = int(sys.argv[sys.argv.index("--tex") + 1]) if "--tex" in sys.argv else TEX
    g, binc = read_glb(src)
    im0 = g["images"][base_color_image(g)]
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

    # Glow: texels matching a colour rule, on triangles whose centroid lies inside that rule's box.
    glow = np.zeros((H, W), np.uint8)
    if specs:
        prim = g["meshes"][0]["primitives"][0]
        P = accessor(g, binc, prim["attributes"]["POSITION"])
        UV = accessor(g, binc, prim["attributes"]["TEXCOORD_0"])
        I = accessor(g, binc, prim["indices"]).reshape(-1, 3)
        cen = P[I].mean(1)
        for box, rule in specs:
            x0, x1, y0, y1, z0, z1 = box
            h0, h1, v0, s0 = rule
            sel = (cen[:, 0] >= x0) & (cen[:, 0] <= x1) & (cen[:, 1] >= y0) & (cen[:, 1] <= y1) & (cen[:, 2] >= z0) & (cen[:, 2] <= z1)
            region = Image.new("L", (W, H), 0)
            dr = ImageDraw.Draw(region)
            for tri in I[sel]:
                dr.polygon([(float(UV[v, 0]) * W, float(UV[v, 1]) * H) for v in tri], fill=255)
            region = np.asarray(region.filter(ImageFilter.MaxFilter(dilate)) if dilate > 1 else region) > 0
            col = (hue > h0) & (hue < h1) & (val > v0) & (sat > s0)
            hit = region & col
            glow[hit] = 255
            print("glow box", box, "rule", rule, "tris", int(sel.sum()), "texels", int(hit.sum()))
    glow_img = Image.fromarray(glow).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.5))
    if color_glow:
        k = (np.asarray(glow_img).astype(np.float32) / 255.0)[..., None]
        glow_img = Image.fromarray(np.clip(rgb * k * 255 + 0.5, 0, 255).astype(np.uint8))

    small = lambda a: Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)).resize((TEX, TEX), Image.LANCZOS)
    buf = io.BytesIO()
    small(rgb).save(buf, "JPEG", quality=90)
    write_glb(f"{out}/{name}.glb", g, binc, buf.getvalue())
    if "--no-red" not in sys.argv:
        small(red_rgb).save(f"{out}/{name}_red.png")
    glow_img.resize((TEX, TEX), Image.LANCZOS).save(f"{out}/{name}_glow.png")
    print("blue texels", int(blue.sum()), "->", out)


if __name__ == "__main__":
    main()
