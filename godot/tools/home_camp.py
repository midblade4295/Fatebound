#!/usr/bin/env python3
"""Home's camp (0.31.194, Kevin: "Now let's design a new home screen" -> he picked B2, the champions' camp).

Sources (ElevenLabs, flow "Fatebound home 0.31.194"), in art_sources/home_camp/:
  camp.png                 the painting behind Home: concept B2 (art_sources/home_redesign/concept_b2_camp.jpg) with its
                           UI painted out and the ground carried down to the bottom (gpt-image-2.5-sunburst, B2 as the
                           reference; 1024 x 2048)
  play_plaque_green.png    the PLAY plaque in B2's style, its face blank, on flat green (gpt-image-2)

Writes:
  assets/ui/v2/bg_camp.webp        the painting (scripts/app/camp_scene.gd lays it out and brings it to life)
  assets/ui/v2/play_plaque.webp    the PLAY plaque, keyed out and cropped, PLAQUE_W wide (its enamel face: printed, as
                                   fractions of the plaque, for screens.gd PLAQUE_FACE)
and prints the lit castle windows it finds (camp_scene.gd WINDOWS).
(0.31.139-0.31.193 the plaque was tools/build_title_art.py's, with a crown and crossed swords; the war room behind
Home was tools/home_war_room.py's.)

  python3 tools/home_camp.py
"""
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(ROOT), "art_sources", "home_camp")
V2 = os.path.join(ROOT, "assets", "ui", "v2")
PLAQUE_W = 760                    # (about 250 logical px at 3x)
CASTLE = (300, 230, 860, 470)     # where to look for lit windows (x0, y0, x1, y1), the painting's px


def camp():
    im = Image.open(os.path.join(SRC, "camp.png")).convert("RGB")
    assert im.size == (1024, 2048), im.size
    im.save(os.path.join(V2, "bg_camp.webp"), "WEBP", quality=90, method=6)
    print("bg_camp.webp", im.size, os.path.getsize(os.path.join(V2, "bg_camp.webp")))
    # the lit windows: warm bright blobs in the castle
    a = np.asarray(im).astype(float)
    x0, y0, x1, y1 = CASTLE
    c = a[y0:y1, x0:x1]
    lit = (c[..., 0] > 200) & (c[..., 1] > 150) & (c[..., 2] < 140)
    from scipy import ndimage
    lab, n = ndimage.label(lit)
    out = []
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        if len(xs) < 12:
            continue
        out.append((round(float(xs.mean()) + x0), round(float(ys.mean()) + y0), len(xs)))
    out.sort(key=lambda t: -t[2])
    print("windows:", ", ".join("Vector2(%d, %d)" % (x, y) for x, y, _ in out[:16]))


def plaque():
    im = Image.open(os.path.join(SRC, "play_plaque_green.png")).convert("RGB")
    a = np.array(im).astype(float)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    spill = G - np.maximum(R, B)
    alpha = 1.0 - np.clip((spill - 40.0) / 90.0, 0.0, 1.0)
    a[..., 1] = np.where((alpha < 1.0) | (spill > 10), np.minimum(G, np.maximum(R, B) * 1.02), G)
    al = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    out = Image.fromarray(np.dstack([a.clip(0, 255).astype(np.uint8), np.array(al)]), "RGBA")
    out = out.crop(out.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
    h = round(out.size[1] * PLAQUE_W / out.size[0])
    out = out.resize((PLAQUE_W, h), Image.LANCZOS)
    out.save(os.path.join(V2, "play_plaque.webp"), "WEBP", quality=92, method=6)
    # its enamel face: the orange (saturated, warm, bright) inside the gold frame
    p = np.asarray(out).astype(float)
    r, g, b, al = p[..., 0], p[..., 1], p[..., 2], p[..., 3]
    face = (al > 200) & (r > 200) & (g > 70) & (g < 175) & (b < 60)
    rows = np.where(face.sum(1) > out.size[0] * 0.5)[0]
    cols = np.where(face.sum(0) > out.size[1] * 0.4)[0]
    fx0, fx1, fy0, fy1 = cols.min(), cols.max(), rows.min(), rows.max()
    print("play_plaque.webp", out.size, "aspect %.4f" % (out.size[1] / out.size[0]),
          "face Rect2(%.3f, %.3f, %.3f, %.3f)" % (fx0 / out.size[0], fy0 / out.size[1], (fx1 - fx0) / out.size[0],
                                                  (fy1 - fy0) / out.size[1]))


if __name__ == "__main__":
    camp()
    plaque()
