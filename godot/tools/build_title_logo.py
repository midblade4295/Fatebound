#!/usr/bin/env python3
"""Home's title logo, "All Tied Up" (0.31.113, Kevin: "I like the all tied up one. Can you also make it so the king
swings back and forth from the rope").

Cuts the one painting (art_sources/title_logo/fatebound_tied_up.png, the logo on a white page) into two layers:
  assets/ui/v2/logo_base.webp   the logo and the tagline scroll with the hanging King painted out (the D's outline and
                                face carried on behind him, the page left clear where he hung over it)
  assets/ui/v2/logo_king.webp   the King with his two rope ends, from just under the knot down
scripts/app/title_logo.gd turns the King about the knot. The King's outline is the white page around him, plus hand-traced
rope ends and crown where he hangs in front of the D, refined with GrabCut. Prints the numbers title_logo.gd uses.

  python3 tools/build_title_logo.py            (needs numpy, scipy, opencv-python, pillow)
"""
import os
import sys

import cv2
import numpy as np
import scipy.ndimage as nd
from PIL import Image

GODOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(GODOT), "art_sources", "title_logo", "fatebound_tied_up.png")
OUT = os.path.join(GODOT, "assets", "ui", "v2")

PIVOT = (1081.0, 284.0)        # under the knot, between the two rope ends (painting pixels)
CUT = 393                      # below this the King hangs over the white page only
TOP0, TOP1 = 286, 294          # the King's rope ends fade in over these rows; the base keeps the rope there
# rope ends and crown where they hang in front of the D (painting pixels, traced on a 4x/6x grid)
LEFT_ROPE = [(1063, 286), (1080, 286), (1078, 300), (1075, 320), (1071, 340), (1063, 360), (1058, 380), (1054, 393),
             (1034, 393), (1037, 380), (1044, 360), (1050, 340), (1056, 320), (1061, 300)]
RIGHT_ROPE = [(1083, 286), (1100, 286), (1103, 300), (1107, 320), (1113, 340), (1117, 365), (1098, 365), (1096, 340),
              (1091, 320), (1086, 300)]
CROWN = [(1060, 393), (1062, 370), (1071, 357), (1077, 350), (1078, 341), (1083, 334), (1091, 341), (1092, 351),
         (1097, 360), (1108, 351), (1116, 344), (1119, 338), (1125, 334), (1131, 340), (1132, 351), (1137, 366),
         (1148, 362), (1150, 358), (1163, 358), (1163, 369), (1158, 378), (1167, 376), (1177, 376), (1180, 386),
         (1192, 393)]
BODY_SEED = (1060, 500)        # a pixel of the ropes round his middle


def page_alpha(im):
    """The white page around the logo becomes clear (flood fill of near-white from the border, 3px soft edge)."""
    mn = im.min(axis=2)
    lab, _ = nd.label(mn > 238)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    band = nd.binary_dilation(bg, iterations=3) & ~bg
    a = np.ones(mn.shape)
    a[bg] = 0.0
    a[band] = np.clip((255.0 - mn[band]) / 70.0, 0.0, 1.0)
    rgb = im.copy()
    m = band & (a > 0.01)
    rgb[m] = np.clip((im[m] - (1 - a[m])[:, None] * 255.0) / a[m][:, None], 0, 255)
    return rgb, a


def poly(shape, pts):
    m = np.zeros(shape, np.uint8)
    cv2.fillPoly(m, [np.array(pts, np.int32)], 1)
    return m.astype(bool)


def king_mask(rgb, a):
    H, W = a.shape
    rough = poly((H, W), LEFT_ROPE) | poly((H, W), RIGHT_ROPE) | poly((H, W), CROWN)
    below = a > 0.3
    below[:CUT, :] = False
    lab, _ = nd.label(below)
    body = lab == lab[BODY_SEED[1], BODY_SEED[0]]
    x0, y0, x1, y1 = 1020, 270, 1200, 410
    roi = np.ascontiguousarray(rgb[y0:y1, x0:x1][:, :, ::-1].astype(np.uint8))
    gm = np.full(roi.shape[:2], cv2.GC_PR_BGD, np.uint8)
    r = rough[y0:y1, x0:x1]
    gm[r] = cv2.GC_PR_FGD
    gm[nd.binary_erosion(r, iterations=3)] = cv2.GC_FGD
    gm[~nd.binary_dilation(r, iterations=5)] = cv2.GC_BGD
    gm[body[y0:y1, x0:x1]] = cv2.GC_FGD
    gm[:TOP0 - y0, :] = cv2.GC_BGD
    gm[a[y0:y1, x0:x1] < 0.3] = cv2.GC_BGD
    cv2.setRNGSeed(7)
    cv2.grabCut(roi, gm, None, np.zeros((1, 65)), np.zeros((1, 65)), 6, cv2.GC_INIT_WITH_MASK)
    top = np.zeros((H, W), bool)
    top[y0:y1, x0:x1] = (gm == cv2.GC_FGD) | (gm == cv2.GC_PR_FGD)
    top[CUT:, :] = False
    king = body | top
    lab2, _ = nd.label(king)
    king = lab2 == lab2[BODY_SEED[1], BODY_SEED[0]]
    return (nd.binary_closing(king, iterations=1) | king) & ((a > 0.3) | top)


def main():
    im = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float64)
    rgb, a = page_alpha(im)
    H, W = a.shape
    king = king_mask(rgb, a)
    # the King: the painting inside his outline (1px soft edge), his rope ends fading in under the knot
    kf = np.clip(cv2.GaussianBlur(king.astype(np.float32), (0, 0), 0.7) * 1.6 - 0.3, 0, 1)
    ramp = np.clip((np.arange(H)[:, None] - TOP0) / float(TOP1 - TOP0), 0, 1)
    ka = kf * a * ramp
    # the base: the King painted out. Colours come only from the logo (never the white page); the logo's edge carries on
    # behind him where he hung in front of the D, and the page stays clear where he hung over it
    hole = nd.binary_dilation(king, iterations=3)
    hole[:TOP1, :] = False
    unknown = hole | (nd.binary_dilation(hole, iterations=30) & (a < 0.6))
    bgr = np.ascontiguousarray(np.clip(rgb, 0, 255).astype(np.uint8)[:, :, ::-1])
    fill = cv2.inpaint(bgr, unknown.astype(np.uint8) * 255, 7, cv2.INPAINT_TELEA)[:, :, ::-1].astype(np.float64)
    af = cv2.inpaint((a * 255).astype(np.uint8), hole.astype(np.uint8) * 255, 7, cv2.INPAINT_TELEA) / 255.0
    af = cv2.GaussianBlur(np.clip((af - 0.5) * 10 + 0.5, 0, 1), (0, 0), 0.6)
    base_rgb = np.where(hole[:, :, None], fill, rgb)
    base_a = np.where(hole, af, a)
    base_a[400:, :][hole[400:, :]] = 0.0
    ys, xs = np.where(base_a > 0.05)
    ky, kx = np.where(ka > 0.05)
    x0, y0 = max(0, min(xs.min(), kx.min()) - 2), max(0, min(ys.min(), ky.min()) - 2)
    x1, y1 = min(W, max(xs.max(), kx.max()) + 3), min(H, max(ys.max(), ky.max()) + 3)
    base = np.dstack([base_rgb, base_a * 255]).round().astype(np.uint8)[y0:y1, x0:x1]
    kx0, kx1, ky0, ky1 = kx.min() - 2, kx.max() + 3, ky.min() - 2, ky.max() + 3
    spr = np.dstack([rgb, ka * 255]).round().astype(np.uint8)[ky0:ky1, kx0:kx1]
    Image.fromarray(base, "RGBA").save(os.path.join(OUT, "logo_base.webp"), lossless=True, quality=100, method=6)
    Image.fromarray(spr, "RGBA").save(os.path.join(OUT, "logo_king.webp"), lossless=True, quality=100, method=6)
    print("BASE := Vector2(%d, %d)" % (x1 - x0, y1 - y0))
    print("KING_AT := Vector2(%d, %d)" % (kx0 - x0, ky0 - y0))
    print("KING_SIZE := Vector2(%d, %d)" % (kx1 - kx0, ky1 - ky0))
    print("PIVOT := Vector2(%g, %g)" % (PIVOT[0] - x0, PIVOT[1] - y0))


if __name__ == "__main__":
    sys.exit(main())
