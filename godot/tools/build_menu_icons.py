#!/usr/bin/env python3
"""The 5v5's menus in paint (0.31.175, Kevin: "Use eleven or meshy to make these menus better looking and more high
quality" -- the hero picker and the in-match shop).

Sources (art_sources/menus, ElevenLabs gpt-image-2, two takes each; prompts.txt):
  icons_a.png, icons_b.png   6 x 4 sheets on white, in the style of the menus' own icons (assets/ui/v2/icons): the
                             fifteen items, gold coins, a padlock, a coin pouch, and the six role badges
  backdrop_a.png             the champions' hall behind the picked hero (2:1)
  shop_a.png                 the keep's armory over the shop (3:1)
Each icon is cut out of its cell: the white round it -- flooded in from the cell's edge and stopped by the icon's dark
outline -- becomes clear, the soft glows half-clear in their own colour (white taken out of them: "colour to alpha"),
then the icon is cropped, centred on a square with a small margin and scaled to SIZE.
Writes assets/ui/items/<item>.png, assets/ui/roles/<role>.png, assets/ui/menu/lock.png and the two paintings as
assets/ui/menu/hero_hall.webp and shop_banner.webp (the sheets' coins and coin pouch aren't used yet: not written).

  python3 tools/build_menu_icons.py      (numpy, scipy, pillow)
"""
import os

import numpy as np
import scipy.ndimage as nd
from PIL import Image

GODOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(GODOT), "art_sources", "menus")
UI = os.path.join(GODOT, "assets", "ui")
SIZE = 256
GRID = [["sword", "ruby", "dagger", "boots", "tome", "fang"],
        ["bead", "cloth", "greaves", "bloodthirster", "titan", "phantom"],
        ["archon", "thorn", "relic", "coins", "lock", "pouch"],
        ["tank", "fighter", "assassin", "mage", "marksman", "support"]]
# the take each icon is cut from
PICK = {"sword": "a", "ruby": "b", "dagger": "a", "boots": "a", "tome": "a", "fang": "a",
        "bead": "a", "cloth": "a", "greaves": "a", "bloodthirster": "b", "titan": "b", "phantom": "b",
        "archon": "b", "thorn": "b", "relic": "a", "coins": "b", "lock": "a", "pouch": "a",
        "tank": "b", "fighter": "b", "assassin": "b", "mage": "b", "marksman": "b", "support": "b"}
# a smaller size in its square than the rest (the dagger beside the long sword)
SCALE = {"dagger": 0.82}
ROLES = {"tank", "fighter", "assassin", "mage", "marksman", "support"}
UNUSED = {"coins", "pouch"}


def cut(cell, scale=1.0):
    """RGBA square SIZE: the icon out of its white cell."""
    c = cell.astype(np.float64) / 255.0
    a0 = 1.0 - c.min(2)                                   # how far from white (colour to alpha)
    lab, _ = nd.label(a0 < 0.5)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(edge))
    # white the icon itself closes round (the inside of the bead's cord loop, the padlock's shackle): a big pure-white
    # pocket ringed by the dark outline is background too; a white glint or the fang's sheen (fading into the colour
    # round it) and the small glints on steel and gems are not
    pocket, n = nd.label((a0 < 0.03) & ~bg)
    if n:
        sizes = nd.sum(np.ones_like(a0), pocket, index=np.arange(1, n + 1))
        for i, sz in enumerate(sizes):
            if sz > 0.02 * a0.size:
                m = pocket == i + 1
                ring = nd.binary_dilation(m, iterations=6) & ~nd.binary_dilation(m, iterations=2)
                if a0[ring].mean() > 0.45:
                    bg |= nd.binary_dilation(m, iterations=4) & (a0 < 0.5)       # (with its soft edge)
    alpha = np.where(bg, a0, 1.0)
    alpha[alpha < 0.04] = 0.0
    # the icon and what hangs on it: its biggest piece and any piece close by (glows, sparkles, drips); bits of the
    # next cell's icon that strayed over the line, away at the edge, go
    parts, n2 = nd.label(alpha > 0.1)
    if n2 > 1:
        sizes = nd.sum(np.ones_like(a0), parts, index=np.arange(1, n2 + 1))
        main = int(np.argmax(sizes)) + 1
        sl = nd.find_objects(parts)
        my0, my1, mx0, mx1 = sl[main - 1][0].start, sl[main - 1][0].stop, sl[main - 1][1].start, sl[main - 1][1].stop
        pad = 0.06 * max(a0.shape)
        drop = np.zeros_like(bg)
        for i in range(1, n2 + 1):
            if i == main:
                continue
            ys, xs = sl[i - 1]
            near = ys.start >= my0 - pad and ys.stop <= my1 + pad and xs.start >= mx0 - pad and xs.stop <= mx1 + pad
            if not near:
                drop |= parts == i
        # (and the faint halo round a dropped piece)
        drop = nd.binary_dilation(drop, iterations=4) & (alpha < 1.0) | drop
        alpha[drop] = 0.0
    safe = np.maximum(alpha, 1e-6)[..., None]
    rgb = np.where(bg[..., None], np.clip((c - (1.0 - safe)) / safe, 0.0, 1.0), c)
    ys, xs = np.nonzero(alpha > 0.06)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgba = np.dstack([rgb, alpha])[y0:y1, x0:x1]
    h, w = rgba.shape[:2]
    side = int(max(h, w) / (0.94 * scale))
    out = np.zeros((side, side, 4))
    oy, ox = (side - h) // 2, (side - w) // 2
    out[oy:oy + h, ox:ox + w] = rgba
    # resize premultiplied (no white fringes from the clear pixels)
    pm = out.copy()
    pm[..., :3] *= pm[..., 3:4]
    im = Image.fromarray((pm * 255.0 + 0.5).astype(np.uint8), "RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    p = np.asarray(im).astype(np.float64) / 255.0
    a = p[..., 3:4]
    p[..., :3] = np.where(a > 1e-4, p[..., :3] / np.maximum(a, 1e-4), 0.0)
    return Image.fromarray((np.clip(p, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGBA")


def main():
    sheets = {k: np.asarray(Image.open(os.path.join(SRC, "icons_%s.png" % k)).convert("RGB")) for k in "ab"}
    for d in ["items", "roles", "menu"]:
        os.makedirs(os.path.join(UI, d), exist_ok=True)
    for r, row in enumerate(GRID):
        for col, name in enumerate(row):
            if name in UNUSED:
                continue
            s = sheets[PICK[name]]
            H, W = s.shape[:2]
            cell = s[int(r * H / 4):int((r + 1) * H / 4), int(col * W / 6):int((col + 1) * W / 6)]
            im = cut(cell, SCALE.get(name, 1.0))
            sub = "roles" if name in ROLES else ("menu" if name == "lock" else "items")
            im.save(os.path.join(UI, sub, name + ".png"), optimize=True)
            print("%-14s %s/%s.png (take %s)" % (name, sub, name, PICK[name]))
    hall = Image.open(os.path.join(SRC, "backdrop_a.png")).convert("RGB").resize((1024, 512), Image.LANCZOS)
    hall.save(os.path.join(UI, "menu", "hero_hall.webp"), quality=86, method=6)
    shop = Image.open(os.path.join(SRC, "shop_a.png")).convert("RGB").resize((1200, 400), Image.LANCZOS)
    shop.save(os.path.join(UI, "menu", "shop_banner.webp"), quality=86, method=6)
    print("menu/hero_hall.webp, menu/shop_banner.webp")


if __name__ == "__main__":
    main()
