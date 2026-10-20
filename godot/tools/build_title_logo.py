#!/usr/bin/env python3
"""The title logo, "Rift" (0.31.193, Kevin: "Let's make a brand new title graphic that fits new game style" -> picked C4,
"make the flags on side blow around and the lighting effect in middle show effects").

One painting (art_sources/title_logo/fatebound_rift.png: ElevenLabs gpt-image-2 2K, flow "Fatebound title 0.31.193", the
logo on a white page) -> the layers scripts/app/title_logo.gd puts together:
  assets/ui/v2/title_rift_base.webp   FATEBOUND, the crown and the rift, the two flags taken out
  assets/ui/v2/title_flag_l.webp      the blue flag and its pole (the wave shader moves the cloth, the pole holds)
  assets/ui/v2/title_flag_r.webp      the red flag and its pole
  assets/ui/v2/title_rift_glow.webp   the rift's white-hot core, blurred: an additive glow that flickers over it
  assets/branding/title_logo.webp     the whole title at rest, 640 wide (the first-start download screen)
and prints the numbers title_logo.gd uses (sizes, where the flags sit, each pole's line, the rift's line).
(0.31.113-0.31.192: "All Tied Up", the rope-bound title with the King swinging -- art_sources/title_logo/
fatebound_tied_up.png, the old version of this tool in git history.)

  python3 tools/build_title_logo.py            (needs numpy, scipy, opencv-python, pillow)
"""
import os
import sys

import cv2
import numpy as np
import scipy.ndimage as nd
from PIL import Image

GODOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(GODOT), "art_sources", "title_logo", "fatebound_rift.png")
OUT = os.path.join(GODOT, "assets", "ui", "v2")
WIDTH = 1400                   # the layers' width (the painting is 2048): a phone shows the title at most ~1080 px wide
PAD = 16                       # transparent margin round each flag layer (the cloth waves past its outline), output px

# the flags: everything outside these lines (painting px, (y, x) points) -- the line runs down each pole and then the
# word's outline where the cloth goes behind it; under the cloth's tails (y 780) nothing is flag
EDGE_L = [(0, 200), (418, 205), (440, 200), (470, 212), (640, 205), (660, 192), (775, 184), (780, 0), (1024, 0)]
EDGE_R = [(0, 1810), (420, 1810), (460, 1846), (490, 1862), (593, 1883), (653, 1893), (680, 1903), (700, 1935),
          (775, 1935), (780, 2048), (1024, 2048)]
# each pole's line, where the cloth hangs from (the cloth moves with its distance from it); below the pole, the edge
POLE_L = [(260, 150), (330, 168), (420, 195), (470, 205), (640, 205), (820, 185), (1024, 175)]
POLE_R = [(260, 1897), (330, 1885), (380, 1870), (450, 1850), (490, 1862), (593, 1883), (653, 1893), (700, 1905),
          (1024, 1905)]
RIFT_X = (925, 1020)           # the rift's white-hot core lies between these columns ...
RIFT_Y = (322, 892)            # ... from under the crown's rim to the tip under the word


def page_alpha(im):
    """The white page becomes clear: a flood fill of near-white from the border (3 px soft edge), and the enclosed
    pockets of page (in the letters' counters) too. The rift's white-hot core is kept: it never touches the page but
    at its tip, and the fill stops at the tip's thin end."""
    mn = im.min(axis=2)
    lab, n = nd.label(mn > 238)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    x0, x1 = RIFT_X
    y0, y1 = RIFT_Y
    sizes = nd.sum(np.ones_like(mn), lab, range(1, n + 1))
    for i, sl in enumerate(nd.find_objects(lab)):
        # enclosed pockets of page (150 px or more), but never the rift's core
        if sl is not None and sizes[i] >= 150 and not (sl[1].start >= x0 - 10 and sl[1].stop <= x1 + 10):
            border.add(i + 1)
    bg = np.isin(lab, list(border))
    # the rift's core touches the page at its tip: keep the core (inside the rift's box, above the tip) as logo
    core = np.zeros_like(bg)
    core[y0:y1 - 70, x0:x1] = True
    bg &= ~core
    band = nd.binary_dilation(bg, iterations=3) & ~bg
    a = np.ones(mn.shape)
    a[bg] = 0.0
    a[band] = np.clip((255.0 - mn[band]) / 70.0, 0.0, 1.0)
    rgb = im.copy()
    m = band & (a > 0.01)
    rgb[m] = np.clip((im[m] - (1 - a[m])[:, None] * 255.0) / a[m][:, None], 0, 255)
    return rgb, a


def line_x(pts, H):
    ys = np.arange(H)
    return np.interp(ys, [p[0] for p in pts], [p[1] for p in pts])


def rift_line(im, a):
    """The rift's middle, row by row (the centroid of its white-hot pixels), smoothed, every 12 rows."""
    mn = im.min(axis=2)
    x0, x1 = RIFT_X
    pts = []
    for y in range(RIFT_Y[0], RIFT_Y[1], 4):
        row = (mn[y, x0:x1] > 225) & (a[y, x0:x1] > 0.5)
        xs = np.nonzero(row)[0]
        if len(xs):
            # the run nearest the last point (side cracks branch off the main one)
            runs = np.split(xs, np.nonzero(np.diff(xs) > 2)[0] + 1)
            last = pts[-1][0] if pts else (x0 + x1) / 2 - x0
            best = min(runs, key=lambda r: abs(r.mean() + x0 - last))
            pts.append((best.mean() + x0, y))
    p = np.array(pts, float)
    p[:, 0] = nd.uniform_filter1d(p[:, 0], 3, mode="nearest")
    return p[::3]


def main():
    im = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float64)
    H, W = im.shape[:2]
    rgb, a = page_alpha(im)
    xx = np.arange(W)[None, :]
    left = xx < line_x(EDGE_L, H)[:, None]
    right = xx > line_x(EDGE_R, H)[:, None]
    ys, xs = np.nonzero(a > 0.05)
    bx0, by0, bx1, by1 = max(0, xs.min() - 2), max(0, ys.min() - 2), min(W, xs.max() + 3), min(H, ys.max() + 3)
    s = WIDTH / float(bx1 - bx0)

    def to_out(arr, box):
        x0, y0, x1, y1 = box
        img = Image.fromarray(arr[y0:y1, x0:x1].round().clip(0, 255).astype(np.uint8), "RGBA")
        return img.resize((max(1, round((x1 - x0) * s)), max(1, round((y1 - y0) * s))), Image.LANCZOS)

    full = np.dstack([rgb, a * 255])
    base = full.copy()
    base[left | right, 3] = 0.0
    base_img = to_out(base, (bx0, by0, bx1, by1))
    base_img.save(os.path.join(OUT, "title_rift_base.webp"), "WEBP", quality=92, alpha_quality=100, method=6)
    print("BASE := Vector2(%d, %d)" % base_img.size)
    whole = to_out(full, (bx0, by0, bx1, by1))
    for name, mask, pole in (("l", left, POLE_L), ("r", right, POLE_R)):
        f = full.copy()
        f[~mask, 3] = 0.0
        fy, fx = np.nonzero(f[:, :, 3] > 5)
        p = int(round(PAD / s))
        box = (max(0, fx.min() - p), max(0, fy.min() - p), min(W, fx.max() + 1 + p), min(H, fy.max() + 1 + p))
        img = to_out(f, box)
        img.save(os.path.join(OUT, "title_flag_%s.webp" % name), "WEBP", quality=92, alpha_quality=100, method=6)
        at = ((box[0] - bx0) * s, (box[1] - by0) * s)
        print("FLAG_%s := [Vector2(%.1f, %.1f), Vector2(%d, %d)]   # its corner on the base, its size" %
              (name.upper(), at[0], at[1], img.size[0], img.size[1]))
        # the pole's line in the flag texture's own px, (y, x) pairs (title_flag.gdshader)
        pl = [((py - box[1]) * s, (px - box[0]) * s) for py, px in pole]
        print("POLE_%s := PackedVector2Array([%s])" % (name.upper(), ", ".join("Vector2(%.1f, %.1f)" % q for q in pl)))
    # the rift: its line (base px) and its glow
    rl = rift_line(im, a)
    print("RIFT := PackedVector2Array([%s])" % ", ".join("Vector2(%.1f, %.1f)" % ((x - bx0) * s, (y - by0) * s)
                                                         for x, y in rl))
    mn = im.min(axis=2)
    core = (mn > 225) & (a > 0.5)
    keep = np.zeros_like(core)
    keep[RIFT_Y[0]:RIFT_Y[1], RIFT_X[0]:RIFT_X[1]] = True
    core &= keep
    g = cv2.GaussianBlur(core.astype(np.float32), (0, 0), 7.0) * 2.2 + cv2.GaussianBlur(core.astype(np.float32), (0, 0), 2.0)
    g = np.clip(g, 0, 1)
    gx0, gy0, gx1, gy1 = RIFT_X[0] - 40, RIFT_Y[0] - 40, RIFT_X[1] + 40, RIFT_Y[1] + 30
    glow = np.zeros((H, W, 4))
    glow[:, :, 0], glow[:, :, 1], glow[:, :, 2] = 255, 236, 180
    glow[:, :, 3] = g * 255
    gimg = to_out(glow, (gx0, gy0, gx1, gy1))
    gimg.save(os.path.join(OUT, "title_rift_glow.webp"), "WEBP", quality=90, alpha_quality=100, method=6)
    print("GLOW := [Vector2(%.1f, %.1f), Vector2(%d, %d)]" % ((gx0 - bx0) * s, (gy0 - by0) * s, gimg.size[0], gimg.size[1]))
    small = whole.resize((640, round(whole.size[1] * 640 / whole.size[0])), Image.LANCZOS)
    small.save(os.path.join(GODOT, "assets", "branding", "title_logo.webp"), "WEBP", quality=90, method=6)
    print("title_logo.webp", small.size)


if __name__ == "__main__":
    sys.exit(main())
