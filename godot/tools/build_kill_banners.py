#!/usr/bin/env python3
"""The 5v5's kill banners in paint (0.31.180, Kevin: "I want the banner art created by eleven so they look more
detailed").

Sources (art_sources/killbanners/eleven, ElevenLabs gpt-image-2, one take each; README.txt there has the prompts):
  plaques.png        the "X has slain Y" plaque twice on white: navy (top) and crimson (bottom), a portrait socket at
                     each end
  first_blood.png, double.png, triple.png, shutdown.png   the 2:1 banners, their titles painted in
  quadra.png, penta.png, ace.png                          the 1:1 crests
Each is cut out of its white ground as tools/build_menu_icons.py cuts the icons (the white round it flooded in from
the edge, stopped by the art's dark outline; soft edges and white glints kept), cropped to the art with a small
margin, and written to assets/ui/banners/<name>.png. The plaques are split in two (plaque_blue, plaque_red) and the
centre and radius of each end's socket printed (as fractions of the plaque) for siege_hud.gd's PLAQUE_SOCKETS.

  python3 tools/build_kill_banners.py      (numpy, scipy, pillow)
"""
import os

import numpy as np
import scipy.ndimage as nd
from PIL import Image

GODOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(GODOT), "art_sources", "killbanners", "eleven")
OUT = os.path.join(GODOT, "assets", "ui", "banners")
BANNERS = ["first_blood", "double", "triple", "quadra", "penta", "ace", "shutdown"]
MAX_W = 1100                                  # (a banner is at most ~430 of the HUD's 420-wide units: 2.6x)


def matte(rgb):
    """(alpha, colour) of the art on its white ground."""
    c = rgb.astype(np.float64) / 255.0
    a0 = 1.0 - c.min(2)                                   # how far from white (colour to alpha)
    lab, _ = nd.label(a0 < 0.5)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(edge))
    alpha = np.where(bg, a0, 1.0)
    alpha[alpha < 0.04] = 0.0
    safe = np.maximum(alpha, 1e-6)[..., None]
    col = np.where(bg[..., None], np.clip((c - (1.0 - safe)) / safe, 0.0, 1.0), c)
    return alpha, col


def crop(alpha, col, margin=8):
    ys, xs = np.nonzero(alpha > 0.06)
    y0, y1 = max(0, ys.min() - margin), min(alpha.shape[0], ys.max() + 1 + margin)
    x0, x1 = max(0, xs.min() - margin), min(alpha.shape[1], xs.max() + 1 + margin)
    return np.dstack([col, alpha])[y0:y1, x0:x1]


def save(rgba, name, max_w=MAX_W):
    h, w = rgba.shape[:2]
    im = Image.fromarray((np.clip(rgba, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGBA")
    if w > max_w:
        # resize premultiplied (no white fringes from the clear pixels)
        pm = rgba.copy()
        pm[..., :3] *= pm[..., 3:4]
        im = Image.fromarray((pm * 255.0 + 0.5).astype(np.uint8), "RGBA").resize((max_w, int(round(h * max_w / w))), Image.LANCZOS)
        p = np.asarray(im).astype(np.float64) / 255.0
        a = p[..., 3:4]
        p[..., :3] = np.where(a > 1e-4, p[..., :3] / np.maximum(a, 1e-4), 0.0)
        im = Image.fromarray((np.clip(p, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGBA")
    im.save(os.path.join(OUT, name + ".png"), optimize=True)
    print("%-12s %dx%d" % (name, im.width, im.height))
    return im


def sockets(rgba):
    """the two dark round sockets' centres and radius (each end's darkest round blob), as fractions of the plaque's
    width and height"""
    a = rgba[..., 3]
    lum = rgba[..., :3].mean(2)
    h, w = a.shape
    out = []
    for x0, x1 in ((0, w // 4), (w - w // 4, w)):
        dark = np.zeros_like(a, dtype=bool)
        dark[:, x0:x1] = (a[:, x0:x1] > 0.9) & (lum[:, x0:x1] < 0.12)
        lab, n = nd.label(dark)
        sizes = nd.sum(np.ones_like(lum), lab, index=np.arange(1, n + 1))
        i = int(np.argmax(sizes)) + 1
        cy, cx = nd.center_of_mass(lab == i)
        r = np.sqrt(sizes[i - 1] / np.pi)
        out.append((cx / w, cy / h, r / h))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    # the two plaques: one picture, top and bottom halves
    pl = np.asarray(Image.open(os.path.join(SRC, "plaques.png")).convert("RGB"))
    H = pl.shape[0]
    for name, half in (("plaque_blue", pl[:H // 2]), ("plaque_red", pl[H // 2:])):
        a, c = matte(half)
        rgba = crop(a, c)
        save(rgba, name)
        print("   sockets (x, y, r):", ["(%.4f, %.4f, %.4f)" % s for s in sockets(rgba)])
    for name in BANNERS:
        rgb = np.asarray(Image.open(os.path.join(SRC, name + ".png")).convert("RGB"))
        a, c = matte(rgb)
        save(crop(a, c), name)


if __name__ == "__main__":
    main()
