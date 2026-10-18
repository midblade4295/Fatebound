#!/usr/bin/env python3
"""The heroes' ability icons (0.31.171, step 3 of the plan: hero polish -- Kevin picked "Both, 2 takes": painted icons
and sounds for every ability).

Sources: three ElevenLabs gpt-image-2 sprite sheets, two takes each (art_sources/hero_icons/sheet<N>_<a|b>.png, outside
the Godot project): 6 columns (heroes) x 4 rows (Q, W, E, R) of rounded tiles on a dark background. This script finds
each sheet's tiles, takes the picked take of every icon, cuts a square out of the middle of its tile (the rim and the
rounded corners left out -- the HUD draws it in a circle) and writes assets/ui/abilities/<hero>_<q|w|e|r>.png.

  python3 tools/build_ability_icons.py [SRC_DIR] [OUT_DIR]
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "art_sources", "hero_icons")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "assets", "ui", "abilities")
SIZE = 192
SLOTS = ["q", "w", "e", "r"]

# sheet -> its six heroes, column by column
SHEETS = {
    "sheet1": ["knight", "barbarian", "rogue", "ranger", "mage", "priest"],
    "sheet2": ["crusader", "berserker", "assassin", "sniper", "archmage", "necromancer"],
    "sheet3": ["golem", "dragoon", "duelist", "stormcaller", "musketeer", "druid"],
}
# the take picked for each icon: a string of four takes per hero, Q W E R
PICK = {
    "knight": "aaba", "barbarian": "bbbb", "rogue": "abab", "ranger": "aabb", "mage": "aaab", "priest": "baba",
    "crusader": "bbba", "berserker": "bbbb", "assassin": "aaba", "sniper": "bbbb", "archmage": "abaa", "necromancer": "bbab",
    "golem": "aaba", "dragoon": "baab", "duelist": "bbbb", "stormcaller": "abaa", "musketeer": "aabb", "druid": "abba",
}


def spans(profile, th=0.3, min_len=40):
    out, s = [], None
    for i, v in enumerate(profile > th):
        if v and s is None:
            s = i
        elif not v and s is not None:
            out.append((s, i))
            s = None
    if s is not None:
        out.append((s, len(profile)))
    return [x for x in out if x[1] - x[0] >= min_len]


def tiles(img):
    """The sheet's 6 x 4 tile boxes (left, top, right, bottom), found from where it differs from its background."""
    a = np.asarray(img.convert("RGB")).astype(np.float64)
    bg = a[2:10, 2:10].reshape(-1, 3).mean(0)
    on = np.abs(a - bg).sum(2) > 40
    cols = spans(on.mean(0))
    rows = spans(on.mean(1))
    if len(cols) != 6 or len(rows) != 4:
        raise SystemExit("expected a 6 x 4 grid, found %d x %d" % (len(cols), len(rows)))
    return [[(c[0], r[0], c[1], r[1]) for c in cols] for r in rows]


def cut(img, box, inset=5):
    l, t, r, b = box
    side = min(r - l, b - t) - 2 * inset
    cx, cy = (l + r) / 2.0, (t + b) / 2.0
    x0, y0 = int(round(cx - side / 2.0)), int(round(cy - side / 2.0))
    return img.crop((x0, y0, x0 + side, y0 + side)).resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    grids = {}
    for sheet in SHEETS:
        for take in "ab":
            img = Image.open(os.path.join(SRC, "%s_%s.png" % (sheet, take))).convert("RGB")
            grids[(sheet, take)] = (img, tiles(img))
    n = 0
    for sheet, heroes in SHEETS.items():
        for col, hid in enumerate(heroes):
            picks = PICK[hid]
            for row, slot in enumerate(SLOTS):
                take = picks[row]
                if take not in "ab":
                    raise SystemExit("bad take %r for %s %s" % (take, hid, slot))
                img, grid = grids[(sheet, take)]
                icon = cut(img, grid[row][col])
                icon.save(os.path.join(OUT, "%s_%s.png" % (hid, slot)), optimize=True)
                n += 1
    print("%d icons -> %s" % (n, os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
