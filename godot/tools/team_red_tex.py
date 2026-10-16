#!/usr/bin/env python3
"""The red team's copy of a Meshy texture painted in the blue team's colours (0.31.159: the 5v5 lane minions and their
props): the saturated blues (hue 195-255, saturation over 0.35) turned deep red at the same saturation and brightness,
softly blended at the edges -- the rule tools/meshy_building_tex.py uses for the hat shops' _red.png.

  team_red_tex.py IN.jpg OUT.jpg [--report]     (--report: how much of the texture is team blue)
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshy_building_tex import hsv, hsv_to_rgb  # noqa: E402


def red(src, out):
    img = Image.open(src).convert("RGB")
    rgb = np.asarray(img).astype(np.float32) / 255.0
    hue, sat, val = hsv(rgb)
    blue = (hue > 195) & (hue < 255) & (sat > 0.35)
    red_rgb = rgb.copy()
    new_h = np.full(hue.shape, 358.0, np.float32)
    red_rgb[blue] = hsv_to_rgb(new_h[blue], np.minimum(sat[blue] * 1.05, 1.0), np.minimum(val[blue] * 0.95, 1.0))
    soft = Image.fromarray((blue * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    k = (np.asarray(soft).astype(np.float32) / 255.0)[..., None]
    red_rgb = rgb * (1 - k) + red_rgb * k
    Image.fromarray((np.clip(red_rgb, 0, 1) * 255).astype(np.uint8)).save(out, quality=90)
    return float(blue.mean())


if __name__ == "__main__":
    share = red(sys.argv[1], sys.argv[2])
    print(os.path.basename(sys.argv[2]), "team blue %.1f %%" % (share * 100))
