#!/usr/bin/env python3
"""Armory Reforged: Meshy weapon models (Kevin, 2026-10-09: "begin the weapon models").

Pipeline per piece (a sword, a shield, a staff ...):
  1. a parts sheet (every piece of a class drawn on its own, front view, from the approved concept sheet; ElevenLabs)
  2. crop     -> one square PNG per piece
  3. model    -> Meshy image-to-3D (low-poly, one small texture)
  4. fetch    -> the GLB
  5. fit      -> the same GLB placed in the space of the KayKit model it replaces ("template"), so the game's hand
                 slots, fits and rolls for that template apply unchanged: same length along +Y (blade up, grip at the
                 template's), same facing (+Z), texture shrunk to 512.

  crop  SHEET OUTDIR name1 name2 ...      pieces in reading order (rows top to bottom, left to right)
  model PNG NAME WORKDIR [--ai meshy-6-lite|meshy-6|meshy-7.1] [--poly N]
  wait  WORKDIR NAME                      poll until done, download NAME.glb + NAME_thumb.png
  fit   IN.glb TEMPLATE OUT.glb KIND [--len F] [--tex N] [--axes X,Y,Z]
        KIND sword|blade|pole (length on +Y, grip at the template's) | shield|handheld (face area, face +Z) |
        box (longest side, centred); TEMPLATE a KayKit .gltf; --len scales the size vs the template;
        --axes turns the piece onto the template's axes first ("-X,Y,Z" mirrors: a left-hand claw from a right one;
        "-X,-Y,Z" stands up a piece drawn blade-down); auto / autoy / automirror: the turn that lays it over the
        template best (all 24 / about +Y only / mirrored). 0.31.96: then the handle onto the hand -- a long weapon's
        shaft through the grip, a shield's back at the knuckles, a tome's back cover at the palm (tools/weapon_grip.py;
        --grip 0 skips it)
Key from MESHY_KEY (never written to disk).
"""
import base64
import io
import json
import os
import struct
import sys
import time
import urllib.request

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_building_tex as mbt  # noqa: E402  (read_glb / write_glb / base_color_image)

API = "https://api.meshy.ai/openapi/v1"


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": "Bearer " + os.environ["MESHY_KEY"], "Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=120) as f:
        return json.loads(f.read())


# ---------------- crop ----------------
def crop(sheet, outdir, names):
    os.makedirs(outdir, exist_ok=True)
    im = Image.open(sheet).convert("RGB")
    a = np.asarray(im).astype(np.int16)
    bg = np.median(np.concatenate([a[:8].reshape(-1, 3), a[-8:].reshape(-1, 3), a[:, :8].reshape(-1, 3),
                                   a[:, -8:].reshape(-1, 3)]), axis=0)
    ink = np.abs(a - bg).max(-1) > 22
    from scipy import ndimage
    ink = ndimage.binary_closing(ink, iterations=6)
    ink = ndimage.binary_fill_holes(ink)
    lab, n = ndimage.label(ink)
    sizes = ndimage.sum(ink, lab, range(1, n + 1))
    keep = [i + 1 for i, s in enumerate(sizes) if s > ink.size * 0.002]
    boxes = []
    for i in keep:
        ys, xs = np.where(lab == i)
        boxes.append([xs.min(), ys.min(), xs.max(), ys.max(), i])
    # merge boxes that overlap (a piece split by a highlight)
    merged = True
    while merged:
        merged = False
        for p in range(len(boxes)):
            for q in range(p + 1, len(boxes)):
                A, B = boxes[p], boxes[q]
                if A[0] <= B[2] and B[0] <= A[2] and A[1] <= B[3] and B[1] <= A[3]:
                    boxes[p] = [min(A[0], B[0]), min(A[1], B[1]), max(A[2], B[2]), max(A[3], B[3]), A[4]]
                    del boxes[q]
                    merged = True
                    break
            if merged:
                break
    if len(boxes) != len(names):
        raise SystemExit("found %d pieces, expected %d: %s" % (len(boxes), len(names), [b[:4] for b in boxes]))
    # reading order: cluster rows by centre y
    boxes.sort(key=lambda b: (b[1] + b[3]) / 2)
    rows, cur = [], [boxes[0]]
    for b in boxes[1:]:
        if (b[1] + b[3]) / 2 - (cur[-1][1] + cur[-1][3]) / 2 > im.height * 0.12:
            rows.append(cur)
            cur = [b]
        else:
            cur.append(b)
    rows.append(cur)
    order = [b for r in rows for b in sorted(r, key=lambda b: b[0])]
    for name, (x0, y0, x1, y1, _) in zip(names, order):
        w, h = x1 - x0, y1 - y0
        side = int(max(w, h) * 1.15)
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        sq = Image.new("RGB", (side, side), tuple(int(c) for c in bg))
        sq.paste(im.crop((cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)), (0, 0))
        # the crop window may reach into a neighbour: blank everything outside this piece's own box
        m = Image.new("L", (side, side), 0)
        from PIL import ImageDraw
        ImageDraw.Draw(m).rectangle((x0 - (cx - side // 2) - 6, y0 - (cy - side // 2) - 6,
                                     x1 - (cx - side // 2) + 6, y1 - (cy - side // 2) + 6), fill=255)
        clean = Image.new("RGB", (side, side), tuple(int(c) for c in bg))
        clean.paste(sq, (0, 0), m)
        if "sword" in name or "blade" in name:
            # hilt down: the crossguard (the widest row) belongs in the lower half; the sheet sometimes draws a sword
            # point down
            ca = np.abs(np.asarray(clean).astype(np.int16) - bg).max(-1) > 22
            widths = ca.sum(1)
            rows_ink = np.where(widths > 0)[0]
            guard = int(np.argmax(widths))
            if rows_ink.size and guard < (rows_ink[0] + rows_ink[-1]) / 2:
                clean = clean.rotate(180)
                print(name, "turned hilt-down")
        if side < 768:
            clean = clean.resize((768, 768), Image.LANCZOS)
        clean.save(os.path.join(outdir, name + ".png"))
        print(name, (x0, y0, x1, y1), "->", clean.size)


# ---------------- Meshy ----------------
def model(png, name, workdir, ai="meshy-6-lite", poly=4000):
    os.makedirs(workdir, exist_ok=True)
    b64 = base64.b64encode(open(png, "rb").read()).decode()
    body = {"image_url": "data:image/png;base64," + b64, "ai_model": ai, "should_texture": True, "enable_pbr": False,
            "should_remesh": True, "topology": "triangle", "target_polycount": int(poly), "target_formats": ["glb"]}
    r = req("POST", "/image-to-3d", body)
    open(os.path.join(workdir, name + ".task"), "w").write(json.dumps({"id": r["result"], "ai": ai, "poly": poly}))
    print(name, "task", r["result"], ai, poly)


def wait(workdir, name, timeout=900):
    t = json.load(open(os.path.join(workdir, name + ".task")))
    t0 = time.time()
    while True:
        s = req("GET", "/image-to-3d/" + t["id"])
        if s["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
            break
        if time.time() - t0 > timeout:
            raise SystemExit("%s still %s after %d s" % (name, s["status"], timeout))
        time.sleep(10)
    if s["status"] != "SUCCEEDED":
        raise SystemExit("%s %s: %s" % (name, s["status"], s.get("task_error")))
    urllib.request.urlretrieve(s["model_urls"]["glb"], os.path.join(workdir, name + ".glb"))
    if s.get("thumbnail_url"):
        urllib.request.urlretrieve(s["thumbnail_url"], os.path.join(workdir, name + "_thumb.png"))
    print(name, "done", s.get("consumed_credits"), "credits")


# ---------------- fit ----------------
def _points(path):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gltf_bounds import points
    return points(path)


def axes_matrix(spec):
    """'X,Y,Z' style: out.x = in.<first>, out.y = in.<second>, out.z = in.<third>, each optionally negated ('-Y')."""
    M = np.zeros((3, 3))
    for row, s in enumerate(spec.split(",")):
        s = s.strip().upper()
        sign = -1.0 if s.startswith("-") else 1.0
        M[row, "XYZ".index(s.lstrip("+-"))] = sign
    if abs(abs(np.linalg.det(M)) - 1) > 1e-6 or (np.abs(M).sum(0) != 1).any():
        raise SystemExit("bad --axes " + spec)
    return M


def _rotations(mode="auto"):
    """auto: the 24 turns; autoy: the 4 turns about the length (+Y stays +Y); automirror: the 24 turns of the
    mirrored piece (the other hand's claw)."""
    out = []
    import itertools
    for perm in itertools.permutations(range(3)):
        for signs in itertools.product((1, -1), repeat=3):
            M = np.zeros((3, 3))
            for r in range(3):
                M[r, perm[r]] = signs[r]
            d = np.linalg.det(M)
            if mode == "automirror" and d < 0 or mode != "automirror" and d > 0:
                if mode != "autoy" or (M[1] == [0, 1, 0]).all():
                    out.append(M)
    return out


def _spec(M):
    return ",".join(("-" if M[r].sum() < 0 else "") + "XYZ"[int(np.abs(M[r]).argmax())] for r in range(3))


def auto_axes(src, template, show=3, mode="auto"):
    """The turn (of the 24) that lays the piece over the template best: surface samples of both, each centred on its
    box and scaled to a longest side of 1, scored by the mean nearest-point distance both ways."""
    from scipy.spatial import cKDTree
    import gltf_bounds as gb

    def norm(p):
        lo, hi = p.min(0), p.max(0)
        return (p - (lo + hi) / 2) / (hi - lo).max()
    T = norm(gb.surface(template))
    tt = cKDTree(T)
    P0 = gb.surface(src)
    res = []
    for M in _rotations(mode):
        P = norm((M @ P0.T).T)
        res.append((tt.query(P)[0].mean() + cKDTree(P).query(T)[0].mean(), _spec(M)))
    res.sort()
    for sc, sp in res[:show]:
        print("   axes %-8s %.4f" % (sp, sc))
    return res[0][1]


def fit(src, template, out, kind, length=1.0, tex=512, axes="X,Y,Z", grip=True):
    """Place the Meshy piece in the template's space, baked into the vertices; shrink the texture.

    axes: turn (or mirror) the piece first -- Meshy builds a piece facing +Z, upright as drawn; a bow or crossbow
    template lies along Z or X, so the drawn piece is turned onto the template's axes before it is measured.
    KIND box: the longest side matched to the template's longest side (x --len), centred on the template."""
    g, binc = mbt.read_glb(src)
    if axes.startswith("auto"):
        axes = auto_axes(src, template, mode=axes)
    R = axes_matrix(axes)
    v = (R @ _points(src).T).T
    lo, hi = v.min(0), v.max(0)
    size = hi - lo
    T = _points(template)
    tlo, thi = T.min(0), T.max(0)
    tsize = thi - tlo
    if kind == "box":
        s = tsize.max() / size.max() * length
        off = (tlo + thi) / 2 - (lo + hi) / 2 * s
    elif kind in ("shield", "handheld"):
        # the same face area as the template (a kite shield replacing a round one keeps its own outline), no side more
        # than 25 % past the template's; face toward +Z like the template; centred like the template
        s = (tsize[0] * tsize[1] / (size[0] * size[1])) ** 0.5
        s = min(s, 1.25 * tsize[0] / size[0], 1.25 * tsize[1] / size[1]) * length
        c = (lo + hi) / 2
        tc = (tlo + thi) / 2
        off = np.array([tc[0] - c[0] * s, tc[1] - c[1] * s, thi[2] - hi[2] * s])
    else:
        # long weapons: same length along +Y, the bottom (pommel / butt) where the template's is, centred on X/Z
        s = tsize[1] / size[1] * length
        c = (lo + hi) / 2
        off = np.array([-c[0] * s, tlo[1] * length - lo[1] * s, -c[2] * s])
    # Baked into the vertices: Godot drops the transform of a glTF's single root node on import.
    binc = bytearray(binc)
    import gltf_bounds as gb
    done = set()
    mirror = np.linalg.det(R) < 0

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
                pts = (R @ pts.T).T * s + off
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
                if mirror and "indices" in p:
                    # a mirrored piece (the other hand's claw): reverse each triangle so its front stays outside
                    ia = g["accessors"][p["indices"]]
                    ibv = g["bufferViews"][ia["bufferView"]]
                    dt = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32}[ia["componentType"]]
                    io_ = ibv.get("byteOffset", 0) + ia.get("byteOffset", 0)
                    n = ia["count"] * np.dtype(dt).itemsize
                    idx = np.frombuffer(bytes(binc[io_:io_ + n]), dt).reshape(-1, 3)[:, ::-1].copy()
                    binc[io_:io_ + n] = idx.tobytes()
        for k in ("matrix", "translation", "rotation", "scale"):
            node.pop(k, None)
        for c in node.get("children", []):
            bake(c, world)

    for r in g["scenes"][g.get("scene", 0)]["nodes"]:
        bake(r, np.eye(4))
    binc = bytes(binc)
    bv = g["bufferViews"][g["images"][mbt.base_color_image(g)]["bufferView"]]
    raw = binc[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
    img = Image.open(io.BytesIO(raw)).convert("RGB").resize((tex, tex), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    mbt.write_glb(out, g, binc, buf.getvalue())
    print("fit", os.path.basename(src), "->", os.path.basename(out), "axes", axes, "scale %.4f" % s, "tris",
          sum(g["accessors"][p["indices"]]["count"] // 3 for m in g["meshes"] for p in m["primitives"] if "indices" in p))
    gk = {"pole": "pole", "sword": "pole", "blade": "pole", "shield": "shield"}.get(kind)
    if kind == "handheld" and "spellbook" in os.path.basename(template):
        gk = "book"
    if gk and grip:
        import weapon_grip
        move, _info = weapon_grip.measure(out, template, gk)
        weapon_grip.translate_glb(out, out, move)
        print("grip", gk, "move %+.3f %+.3f %+.3f" % tuple(move))


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    opt = {}
    pos = []
    i = 0
    while i < len(args):
        if args[i].startswith("--"):
            opt[args[i][2:]] = args[i + 1]
            i += 2
        else:
            pos.append(args[i])
            i += 1
    if cmd == "crop":
        crop(pos[0], pos[1], pos[2:])
    elif cmd == "model":
        model(pos[0], pos[1], pos[2], opt.get("ai", "meshy-6-lite"), int(opt.get("poly", 4000)))
    elif cmd == "wait":
        wait(pos[0], pos[1])
    elif cmd == "fit":
        fit(pos[0], pos[1], pos[2], pos[3], float(opt.get("len", 1.0)), int(opt.get("tex", 512)), opt.get("axes", "X,Y,Z"),
            opt.get("grip", "1") != "0")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
