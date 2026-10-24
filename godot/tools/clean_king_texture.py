#!/usr/bin/env python3
"""The King's textures cleaned up for the 3D app icon (tools/render_app_icon.gd): his Meshy texture is 512 px with the
lighting smeared into it, fine at match distance but blotchy in a close-up. Here it is redrawn in his own colours as
clean flat paint at 2048 (each pixel to the nearest of his palette, the smears between two colours given to whichever
surrounds them; his face and hands keep their own paint), and a second map says what each colour is made of -- gold that shines like metal, gems like glass,
velvet, fur -- so the renderer's lighting does the shading instead.

  art_sources/app_icon/king_clean/albedo.png   2048, RGB
  art_sources/app_icon/king_clean/orm.png      2048: G roughness, B metallic (R 255)

    python3 tools/clean_king_texture.py
"""
import os

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
SRC = os.path.join(GODOT, "assets", "kings", "king_blue_fat_texture_0.png")
OUT = os.path.join(os.path.dirname(GODOT), "art_sources", "app_icon", "king_clean")
N = 2048

# his palette (k-means of the texture, the in-between smears left out) -> [colour, roughness, metallic]
PALETTE = {
    "robe":       [(84, 36, 120), 0.62, 0.0],
    "robe_dark":  [(80, 34, 115), 0.64, 0.0],      # (his painted shading: the light does that now)
    "fur":        [(244, 238, 224), 0.88, 0.0],
    "fur_shade":  [(238, 232, 218), 0.9, 0.0],     # (likewise)
    "gold":       [(226, 176, 80), 0.3, 0.9],
    "gold_dark":  [(196, 146, 66), 0.36, 0.9],
    "red":        [(152, 30, 40), 0.45, 0.0],
    "black":      [(18, 14, 16), 0.5, 0.0],
    "skin":       [(238, 194, 152), 0.58, 0.0],
    "belt":       [(78, 46, 26), 0.6, 0.0],
    "leather":    [(165, 114, 67), 0.6, 0.0],
    "gem_blue":   [(30, 120, 196), 0.14, 0.0],
}


def lab(rgb):
    a = np.asarray(rgb, np.float32) / 255.0
    a = np.where(a > 0.04045, ((a + 0.055) / 1.055) ** 2.4, a / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]], np.float32)
    xyz = a @ m.T / np.array([0.9505, 1.0, 1.089], np.float32)
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def main():
    os.makedirs(OUT, exist_ok=True)
    src = Image.open(SRC).convert("RGB").resize((N, N), Image.LANCZOS)
    names = list(PALETTE)
    cols = np.array([PALETTE[k][0] for k in names], np.float32)
    px = lab(np.asarray(src))
    d = ((px[:, :, None, :] - lab(cols)[None, None, :, :]) ** 2).sum(-1)
    label = d.argmin(-1)
    far = d.min(-1) > 18.0 ** 2          # a smear between colours: decided by its neighbours below
    # the smears and specks: each takes the colour most of its 9 x 9 neighbourhood has (a vote per colour)
    votes = np.stack([ndimage.uniform_filter(((label == i) & ~far).astype(np.float32), 9) for i in range(len(names))], -1)
    label = np.where(far, votes.argmax(-1), label)
    votes = np.stack([ndimage.uniform_filter((label == i).astype(np.float32), 5) for i in range(len(names))], -1)
    label = votes.argmax(-1)
    albedo = cols[label]
    # his face and hands keep their own paint (the blush, the nose, the eyes' whites and glints are too small and too
    # soft to redraw in flat colours): the skin and everything within 20 px of it, feathered into the clean paint
    srgb = np.asarray(src).astype(np.float32)
    skin = (label == names.index("skin")) | ((srgb[..., 0] > 190) & (srgb[..., 0] - srgb[..., 1] > 40) & (srgb[..., 2] > 80))
    skin = ndimage.binary_opening(skin, iterations=2)
    keep = ndimage.gaussian_filter(ndimage.binary_dilation(skin, iterations=20).astype(np.float32), 6.0)[..., None]
    soft = np.asarray(src.filter(ImageFilter.UnsharpMask(radius=5, percent=70, threshold=2))).astype(np.float32)
    albedo = (keep * soft + (1.0 - keep) * albedo).clip(0, 255).astype(np.uint8)
    Image.fromarray(albedo, "RGB").filter(ImageFilter.GaussianBlur(0.8)).save(os.path.join(OUT, "albedo.png"), optimize=True)
    rough = np.array([PALETTE[k][1] for k in names], np.float32)[label]
    metal = np.array([PALETTE[k][2] for k in names], np.float32)[label]
    orm = np.stack([np.full_like(rough, 1.0), rough, metal], -1)
    Image.fromarray((orm * 255).astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(0.8)).save(os.path.join(OUT, "orm.png"), optimize=True)
    share = np.bincount(label.ravel(), minlength=len(names)) / label.size
    print("king textures ->", OUT, {k: round(float(s), 3) for k, s in zip(names, share)})


if __name__ == "__main__":
    main()
