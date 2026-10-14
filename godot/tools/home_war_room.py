#!/usr/bin/env python3
"""Home's war room backdrop (0.31.138, Kevin picked the war room concept: "Make sure to bring the scene to life with
candles emitting light glow along with the glow effect of sun. Also maybe glimmer of the water and birds flying in sky").

The painting (ElevenLabs gpt-image-2.5-sunburst, flow "Fatebound war table": the approved concept with its table,
heroes and UI taken out, 1152 x 2560) is art_sources/home_war_room/room.png. This writes, from it:

  assets/ui/v2/bg_war_room.webp        the painting Home stands its 3D war table and heroes in
  assets/ui/v2/bg_war_room_mask.png    a quarter-size mask: R = the window's opening (the sky and the land seen through
                                       it: the sun's glow, the clouds and the birds are drawn there, under the room),
                                       G = the water in the view (the river, the lake and the sea: they glimmer)

and prints what scripts/app/home_scene.gd places by hand (the flames, the sun, the rug).

  python3 tools/home_war_room.py [art_sources/home_war_room/room.png]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(ROOT), "art_sources", "home_war_room", "room.png")
OUT = os.path.join(ROOT, "assets", "ui", "v2")
CX = 570                    # the window's middle (its arch is traced outward from here)
SILL = 812                  # the window sill's top edge
JAMBS = (190, 950)          # the window's sides below the arch
HORIZON = 468
# seeds in the river, the lake and the sea (the water mask keeps the water these touch)
WATER_SEEDS = [(480, 700), (520, 640), (430, 760), (560, 600), (590, 575), (230, 500), (280, 560), (250, 480),
               (200, 530), (470, 780)]


def window_mask(a):
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    sky = (B > 0.62 * R) | ((R + G + B) > 600)
    left, right = [], []
    for y in range(30, 246):
        row = sky[y]
        if not row[CX]:
            continue
        ends = []
        for step in (-1, 1):
            x, miss = CX, 0
            while 120 < x < 1030:
                miss = miss + 1 if not row[x] else 0
                if miss > 6:
                    break
                x += step
            ends.append(x - step * 7)
        left.append((ends[0], y))
        right.append((ends[1], y))

    def smooth(p):
        p = np.array(p, float)
        q = p.copy()
        for i in range(len(p)):
            q[i, 0] = p[max(0, i - 4):i + 5, 0].mean()
        return [tuple(v) for v in q]

    poly = [(JAMBS[0], SILL), (JAMBS[0] + 4, 330)] + list(reversed(smooth(left))) + smooth(right) + \
        [(JAMBS[1] - 2, 330), (JAMBS[1], SILL)]
    m = Image.new("L", (a.shape[1], a.shape[0]), 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    return np.array(m.filter(ImageFilter.GaussianBlur(1.5))).astype(float) / 255.0


def water_mask(a, win):
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    H, W = R.shape
    lum = 0.3 * R + 0.59 * G + 0.11 * B
    yy = np.arange(H)[:, None] * np.ones((1, W))
    water = ((B > G + 18) & (B > 95) & (lum > 70)) | ((R > 170) & (B > 90) & (G < R - 40) & (yy > HORIZON + 2))
    water &= (yy > HORIZON) & (win > 0.99)
    lab, _ = ndimage.label(water)
    keep = set()
    for (x, y) in WATER_SEEDS:
        for dy in range(-12, 13, 3):
            for dx in range(-12, 13, 3):
                v = int(lab[y + dy, x + dx])
                if v:
                    keep.add(v)
    w = np.isin(lab, list(keep))
    w[:575, 340:] = False                  # (the hazy hills right of the left castle are not sea)
    img = Image.fromarray((w * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(2))
    return np.array(img).astype(float) / 255.0


def flames(a):
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    hot = (R > 248) & (G > 225) & (B > 140)
    lab, _ = ndimage.label(hot)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        ys, xs = sl
        w, h = xs.stop - xs.start, ys.stop - ys.start
        if 15 <= h <= 30 and w <= 8:                      # a flame: thin and tall (a lit candle top is wider)
            cy, cx = ndimage.center_of_mass(lab == i + 1)
            out.append((int(cx), int(cy)))
    return sorted(out)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else SRC
    im = Image.open(src).convert("RGB")
    a = np.array(im).astype(float)
    win = window_mask(a)
    wat = water_mask(a, win)
    H, W = win.shape
    rgb = np.stack([win, wat, np.zeros_like(win)], -1)
    small = Image.fromarray((rgb * 255).astype(np.uint8)).resize((W // 4, H // 4), Image.BILINEAR)
    small.save(os.path.join(OUT, "bg_war_room_mask.png"), optimize=True)
    im.save(os.path.join(OUT, "bg_war_room.webp"), "WEBP", quality=90, method=6)
    print("window rows %d..%d, water %.1f%% of the window" % (np.nonzero(win.max(1) > 0.5)[0].min(),
          np.nonzero(win.max(1) > 0.5)[0].max(), 100.0 * wat.sum() / max(1.0, win.sum())))
    print("flames (painting px):", flames(a))
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    red = (R > 70) & (R > 1.8 * G) & (R > 1.6 * B)
    red[:850] = False
    red = ndimage.binary_opening(red, iterations=2)
    lab, n = ndimage.label(red)
    k = int(np.argmax(ndimage.sum(red, lab, range(1, n + 1)))) + 1
    ys, xs = np.nonzero(lab == k)
    print("rug: centre (%d, %d), half-width %d, half-height %d" % ((xs.min() + xs.max()) // 2, (ys.min() + ys.max()) // 2,
          (xs.max() - xs.min()) // 2, (ys.max() - ys.min()) // 2))


if __name__ == "__main__":
    main()
