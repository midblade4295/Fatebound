#!/usr/bin/env python3
# python3 tools/cut_vfx_sheet.py OUT_DIR  (run in the folder holding the sheets s1.png..s4.png; 0.31.100)
# Cut the ElevenLabs (gpt-image-2) VFX sheets into grayscale particle textures: each sprite is the union of the bright
# blobs (cores > 45, grown back 10 px for the glow) whose centre falls in its grid cell (so a sprite poking into a neighbour's cell is still whole, and the
# neighbour's bits are left out), squared with a margin, levelled (black floor 0, peak 255), 128 px.
import sys, numpy as np
from PIL import Image
from scipy import ndimage
NAMES = "sparkle flame smoke lightning rays snowflake shard leaf feather rune sigil crescent wisp vortex stars ring".split()
OUT = sys.argv[1]
def sprites(sheet):
    im = np.asarray(Image.open(sheet).convert('L')).astype(np.float32)
    H, W = im.shape
    mask = ndimage.binary_dilation(im > 45, iterations=5)
    lab, n = ndimage.label(mask)
    cells = {}
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        ys, xs = np.where(lab[sl] == i)
        cy, cx = ys.mean() + sl[0].start, xs.mean() + sl[1].start
        k = int(cy // (H / 4)) * 4 + int(cx // (W / 4))
        cells.setdefault(k, []).append(i)
    out = {}
    for k, ids in cells.items():
        m = ndimage.binary_dilation(np.isin(lab, ids), iterations=10) & (im > 6)
        ys, xs = np.where(m)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        crop = np.where(m, im, 0)[y0:y1, x0:x1]
        out[NAMES[k]] = crop
    return out
def square(crop, size=128, margin=0.06):
    h, w = crop.shape
    s = int(max(h, w) * (1 + 2 * margin)) + 2
    sq = np.zeros((s, s), np.float32)
    sq[(s - h) // 2:(s - h) // 2 + h, (s - w) // 2:(s - w) // 2 + w] = crop
    sq = np.clip((sq - 8.0) / max(sq.max() - 8.0, 1.0), 0, 1) * 255
    return Image.fromarray(sq.astype(np.uint8)).resize((size, size), Image.LANCZOS)
pick = {"sparkle": 2, "flame": 2, "smoke": 3, "lightning": 1, "rays": 4, "snowflake": 2, "shard": 3, "leaf": 1,
        "feather": 2, "sigil": 2, "crescent": 3, "wisp": 2, "vortex": 3, "stars": 2, "ring": 3}
sheets = {s: sprites("s%d.png" % s) for s in range(1, 5)}
for name, s in pick.items():
    square(sheets[s][name]).save("%s/%s.png" % (OUT, name))
# the runes: all four variants in a 2x2 atlas (a particle picks one)
atlas = Image.new('L', (256, 256), 0)
for i, s in enumerate(range(1, 5)):
    atlas.paste(square(sheets[s]["rune"]), ((i % 2) * 128, (i // 2) * 128))
atlas.save("%s/runes.png" % OUT)
# a soft round dot (procedural) for motes and embers
yy, xx = np.mgrid[0:64, 0:64]
r = np.hypot(xx - 31.5, yy - 31.5) / 32.0
dot = np.clip(1 - r, 0, 1) ** 2.2 * 255
Image.fromarray(dot.astype(np.uint8)).save("%s/dot.png" % OUT)
print("ok", sorted(pick) + ["runes", "dot"])
