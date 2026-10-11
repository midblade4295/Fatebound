#!/usr/bin/env python3
"""The embers' glow on the rendered currency art (0.31.105; tools/render_currency_icons.gd renders, this runs after it):
the molten cracks bloom, and a soft orange halo sits round each ember. The spin strips are done frame by frame.
  python3 tools/currency_glow.py"""
import os
import numpy as np
from PIL import Image, ImageFilter

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui", "currency")
HALO = np.array([255, 118, 34], float) / 255


def blur(a, r):
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r))).astype(float) / 255


def glow(img):
    a = np.asarray(img.convert("RGBA")).astype(float) / 255
    rgb, al = a[..., :3], a[..., 3]
    n = img.width
    r, b = rgb[..., 0], rgb[..., 2]
    hot = np.clip((r - 0.5) / 0.3, 0, 1) * np.clip((r - b - 0.25) / 0.3, 0, 1) * al
    bloom = np.stack([blur(rgb[..., c] * hot, n * 0.012) for c in range(3)], -1) * 0.9
    rgb = np.clip(rgb + bloom, 0, 1)
    halo = blur(al, n * 0.05) * 0.5
    lum = bloom.max(-1)
    # the halo behind the ember, the bloom spilling just past its edge
    out_a = al + (1 - al) * np.clip(halo + lum * 0.8, 0, 1)
    under = HALO[None, None, :] * (halo[..., None]) + bloom * 0.9
    col = (rgb * al[..., None] + under * (1 - al[..., None])) / np.maximum(out_a[..., None], 1e-4)
    out = np.dstack([np.clip(col, 0, 1), np.clip(out_a, 0, 1)])
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")


for name in ["ember", "embers"]:
    p = os.path.join(DIR, name + ".png")
    glow(Image.open(p)).save(p)
    print("glow", name)
p = os.path.join(DIR, "ember_spin.png")
strip = Image.open(p).convert("RGBA")
h = strip.height
out = Image.new("RGBA", strip.size)
for f in range(strip.width // h):
    out.paste(glow(strip.crop((f * h, 0, f * h + h, h))), (f * h, 0))
out.save(p)
print("glow ember_spin")
