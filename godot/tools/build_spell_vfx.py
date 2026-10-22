#!/usr/bin/env python3
"""The spell effects' sprites (assets/vfx/spell): grayscale, brightness = the sprite, drawn by scripts/siege/fx_sprite.gdshader
in the effect's colour (scripts/siege/spell_fx.gd). Procedural, so every hero's ability can have its own shape without
a painted sheet: a four-point sparkle, a soft ring, a streak, a rock shard, a star, radial cracks, sun rays, a swirl, and
a 2x2 atlas of rune glyphs.

    python3 tools/build_spell_vfx.py            # writes godot/assets/vfx/spell/*.png (then let Godot import them)
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "assets", "vfx", "spell")
N = 128


def grid(n=N):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    x = (x + 0.5) / n * 2.0 - 1.0
    y = (y + 0.5) / n * 2.0 - 1.0
    return x, y


def save(name, a):
    a = np.clip(a, 0.0, 1.0)
    Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "L").save(os.path.join(OUT, name + ".png"))
    print(name)


def sparkle():
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    ang = np.arctan2(y, x)
    # four long points and four short ones between, a hot core
    pts = np.abs(np.cos(ang * 2.0)) ** 14.0 * 1.0 + np.abs(np.sin(ang * 2.0)) ** 30.0 * 0.45
    a = np.clip(pts * np.clip(1.0 - r, 0, 1) ** 1.4 * 1.3, 0, 1)
    a = np.maximum(a, np.exp(-(r * 5.0) ** 2))
    return a


def star5():
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    ang = np.arctan2(y, x)
    pts = np.abs(np.cos(ang * 2.5 + 0.3)) ** 6.0
    a = np.clip(pts * np.clip(1.0 - r, 0, 1) ** 1.2 * 1.4, 0, 1)
    a = np.maximum(a, np.exp(-(r * 4.0) ** 2))
    return a


def ring():
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    a = np.exp(-((r - 0.72) / 0.11) ** 2) + 0.35 * np.exp(-((r - 0.72) / 0.28) ** 2)
    return a * (r < 0.98)


def streak():
    x, y = grid()
    a = np.exp(-(y / 0.11) ** 2) * np.exp(-(x / 0.75) ** 4) * (1.0 - 0.6 * np.abs(x))
    a = np.maximum(a, np.exp(-(x / 0.22) ** 2) * np.exp(-(y / 0.06) ** 2))
    return a


def shard():
    im = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(im)
    random.seed(7)
    for k in range(3):
        c = (N * (0.3 + 0.2 * k), N * (0.35 + 0.15 * (k % 2)))
        pts = []
        for i in range(6):
            ang = i / 6.0 * math.tau + random.uniform(-0.3, 0.3)
            rr = N * random.uniform(0.14, 0.3) * (1.0 - 0.15 * k)
            pts.append((c[0] + math.cos(ang) * rr, c[1] + math.sin(ang) * rr * 0.75))
        d.polygon(pts, fill=int(140 + 40 * k))
        for i in range(len(pts)):
            d.line([pts[i], pts[(i + 1) % len(pts)]], fill=255, width=2)
    a = np.asarray(im).astype(np.float32) / 255.0
    return a


def cracks():
    im = Image.new("L", (N * 2, N * 2), 0)
    d = ImageDraw.Draw(im)
    random.seed(3)
    c = (N, N)
    for i in range(9):
        ang = i / 9.0 * math.tau + random.uniform(-0.25, 0.25)
        p = c
        w = 7
        for seg in range(7):
            ang += random.uniform(-0.45, 0.45)
            ln = N * random.uniform(0.12, 0.2)
            q = (p[0] + math.cos(ang) * ln, p[1] + math.sin(ang) * ln)
            d.line([p, q], fill=255, width=max(1, int(w)))
            if seg >= 2 and random.random() < 0.5:
                a2 = ang + random.choice([-1, 1]) * random.uniform(0.6, 1.2)
                q2 = (q[0] + math.cos(a2) * ln * 0.6, q[1] + math.sin(a2) * ln * 0.6)
                d.line([q, q2], fill=200, width=max(1, int(w * 0.5)))
            p = q
            w *= 0.78
    im = im.filter(ImageFilter.GaussianBlur(1.6)).resize((N, N), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    a = a * np.clip(1.25 - r, 0, 1) + 0.9 * np.exp(-(r * 3.5) ** 2)
    return a


def rays():
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    ang = np.arctan2(y, x)
    a = 0.0
    for k, (n, ph, w) in enumerate([(12, 0.0, 10.0), (7, 0.9, 4.0)]):
        a = a + (0.5 + 0.5 * np.cos(ang * n + ph)) ** w * (0.8 if k else 1.0)
    a = np.clip(a, 0, 1) * np.clip(1.0 - r, 0, 1) ** 0.8
    a = np.maximum(a, np.exp(-(r * 3.0) ** 2))
    return a


def swirl():
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    ang = np.arctan2(y, x)
    a = (0.5 + 0.5 * np.cos(ang * 3.0 - r * 9.0)) ** 3.0
    a = a * np.clip(1.0 - r, 0, 1) * np.clip(r * 4.0, 0, 1)
    return a


def runes():
    # a 2x2 atlas of glyphs, drawn as strokes
    im = Image.new("L", (N * 2, N * 2), 0)
    d = ImageDraw.Draw(im)
    glyphs = [
        [[(0.5, 0.1), (0.5, 0.9)], [(0.5, 0.3), (0.8, 0.5)], [(0.5, 0.3), (0.2, 0.5)], [(0.3, 0.75), (0.7, 0.75)]],
        [[(0.2, 0.2), (0.8, 0.8)], [(0.8, 0.2), (0.2, 0.8)], [(0.5, 0.1), (0.5, 0.35)], [(0.5, 0.65), (0.5, 0.9)]],
        [[(0.25, 0.15), (0.25, 0.85)], [(0.25, 0.15), (0.75, 0.4)], [(0.25, 0.5), (0.75, 0.4)], [(0.25, 0.5), (0.75, 0.85)]],
        [[(0.5, 0.12), (0.82, 0.5), (0.5, 0.88), (0.18, 0.5), (0.5, 0.12)], [(0.5, 0.35), (0.5, 0.65)], [(0.35, 0.5), (0.65, 0.5)]],
    ]
    for gi, g in enumerate(glyphs):
        ox = (gi % 2) * N
        oy = (gi // 2) * N
        for stroke in g:
            pts = [(ox + px * N, oy + py * N) for (px, py) in stroke]
            d.line(pts, fill=255, width=7, joint="curve")
            for p in pts:
                d.ellipse([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], fill=255)
    glow = im.filter(ImageFilter.GaussianBlur(5.0))
    a = np.maximum(np.asarray(im).astype(np.float32) / 255.0, np.asarray(glow).astype(np.float32) / 255.0 * 0.8)
    return a


def main():
    os.makedirs(OUT, exist_ok=True)
    save("sparkle", sparkle())
    save("star", star5())
    save("ring", ring())
    save("streak", streak())
    save("shard", shard())
    save("cracks", cracks())
    save("rays", rays())
    save("swirl", swirl())
    save("runes", runes())
    with open(os.path.join(OUT, "SOURCE.txt"), "w") as f:
        f.write("The spell effects' sprites, made by tools/build_spell_vfx.py (procedural, grayscale; runes is a 2x2 atlas).\n")


if __name__ == "__main__":
    main()
