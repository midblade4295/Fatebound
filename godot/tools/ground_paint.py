#!/usr/bin/env python3
"""The map's painted ground (0.31.216, Kevin: "use eleven to draw detailed paint on ground"): ElevenLabs painted the
pictures (GPT Image 2.5, flow "Fatebound ground paint"), this turns the picks into the game's textures.

  python3 tools/ground_paint.py SRC      SRC: the downloaded pictures (lane_stone_a.img, grass_a.img, ...)

Writes assets/terrain/paint/:
  lane.webp grass.webp grass2.webp dirt.webp keep.webp rock.webp riverbed.webp      seamless (their wrap seams eased)
  circle.png ring.png                                                               decals, keyed off their magenta
  flowers.png (3 x 3 patches)  blades.png (4 x 2 clumps)  brush.png (2 bushes)      keyed sheets (magenta / red)
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "terrain", "paint")

# name -> (source, size)
TILES = {
    "lane": ("lane_stone_a", 2048), "grass": ("grass_a", 2048), "grass2": ("grass_b", 2048), "dirt": ("dirt_a", 1024),
    "keep": ("keep_b", 1024), "rock": ("rock_b", 1024), "riverbed": ("riverbed_a", 1024),
}


def heal(a: np.ndarray, band: int = 40) -> np.ndarray:
    """Ease the wrap seams: the jump between the last and first column (row), smoothed along the edge, spread back
    over a band either side so the picture's colour meets itself across the wrap."""
    a = a.astype(np.float32)
    for axis in (1, 0):
        b = np.moveaxis(a, axis, 0)                   # the seam runs between b[-1] and b[0]
        d = b[0] - b[-1]                             # (n, 3)
        k = 9
        ker = np.exp(-0.5 * (np.arange(-3 * k, 3 * k + 1) / k) ** 2)
        ker /= ker.sum()
        d = np.stack([np.convolve(np.pad(d[:, c], 3 * k, mode="wrap"), ker, mode="valid") for c in range(3)], axis=1)
        w = np.linspace(1.0, 0.0, band)[:, None, None]
        b[:band] -= 0.5 * d[None] * w
        b[-band:] += 0.5 * d[None] * w[::-1]
        a = np.moveaxis(b, 0, axis)
    return np.clip(a, 0, 255).astype(np.uint8)


def key(img: Image.Image, colour: str, lo: float, hi: float) -> Image.Image:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    if colour == "magenta":
        m = np.minimum(r, b) - g
        kc = np.array([255.0, 0.0, 255.0])
    else:
        m = r - np.maximum(g, b)
        kc = np.array([255.0, 0.0, 0.0])
    t = np.clip((m - lo) / (hi - lo), 0.0, 1.0)
    alpha = 1.0 - t * t * (3.0 - 2.0 * t)
    # unmix the key from the soft edges: c = alpha * fg + (1 - alpha) * key
    al = np.maximum(alpha, 0.05)[..., None]
    fg = (a - (1.0 - alpha)[..., None] * kc) / al
    fg = np.clip(fg, 0, 255)
    # what's left of the key's hue in the opaque part (a magenta / red rim the painter left): pull it to its neighbours' green
    if colour == "magenta":
        spill = np.clip(np.minimum(fg[..., 0], fg[..., 2]) - fg[..., 1], 0, None)
        fg[..., 0] -= spill
        fg[..., 2] -= spill
    else:
        spill = np.clip(fg[..., 0] - np.maximum(fg[..., 1], fg[..., 2]), 0, None)
        fg[..., 0] -= spill
    out = np.dstack([fg, alpha * 255.0]).astype(np.uint8)
    o = Image.fromarray(out, "RGBA")
    return o


def bleed(o: Image.Image) -> Image.Image:
    """Colour under the transparent pixels from their nearest opaque ones, so the mipmaps don't fade the edges to black."""
    a = np.asarray(o).astype(np.float32)
    rgb = a[..., :3].copy()
    al = a[..., 3] / 255.0
    acc = rgb * al[..., None]
    wsum = al.copy()
    small_rgb, small_w = acc, wsum
    for _ in range(6):                     # a few box-blur passes of the weighted colour
        small_rgb = (np.roll(small_rgb, 1, 0) + np.roll(small_rgb, -1, 0) + np.roll(small_rgb, 1, 1) + np.roll(small_rgb, -1, 1) + small_rgb * 2) / 6.0
        small_w = (np.roll(small_w, 1, 0) + np.roll(small_w, -1, 0) + np.roll(small_w, 1, 1) + np.roll(small_w, -1, 1) + small_w * 2) / 6.0
    fill = small_rgb / np.maximum(small_w, 1e-4)[..., None]
    rgb = np.where(al[..., None] > 0.02, rgb, fill)
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a[..., 3]]).astype(np.uint8), "RGBA")


def main() -> None:
    src = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    for name, (f, size) in TILES.items():
        im = Image.open(os.path.join(src, f + ".img")).convert("RGB")
        im = Image.fromarray(heal(np.asarray(im)))
        if im.size[0] != size:
            im = im.resize((size, size), Image.LANCZOS)
        im.save(os.path.join(OUT, name + ".webp"), quality=92, method=6)
        print("tile", name, im.size)
    # decals
    c = key(Image.open(os.path.join(src, "circle_a.img")), "magenta", 40, 150).resize((1024, 1024), Image.LANCZOS)
    bleed(c).save(os.path.join(OUT, "circle.png"), optimize=True)
    r = key(Image.open(os.path.join(src, "ring_a.img")), "magenta", 40, 150)
    bleed(r).save(os.path.join(OUT, "ring.png"), optimize=True)
    fl = key(Image.open(os.path.join(src, "flowers_a.img")), "magenta", 40, 150)
    bleed(fl).save(os.path.join(OUT, "flowers.png"), optimize=True)
    # grass blades: the two sheets side by side (4 x 2 clumps)
    ba = key(Image.open(os.path.join(src, "blades_a.img")), "magenta", 30, 140)
    bb = key(Image.open(os.path.join(src, "blades_b.img")), "magenta", 30, 140)
    sheet = Image.new("RGBA", (2048, 1024))
    sheet.paste(ba, (0, 0))
    sheet.paste(bb, (1024, 0))
    bleed(sheet.resize((1024, 512), Image.LANCZOS)).save(os.path.join(OUT, "blades.png"), optimize=True)
    br = key(Image.open(os.path.join(src, "brush_a.img")), "red", 40, 150)
    bleed(br).save(os.path.join(OUT, "brush.png"), optimize=True)
    print("decals done")


if __name__ == "__main__":
    main()
