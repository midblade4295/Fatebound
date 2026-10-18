#!/usr/bin/env python3
"""The towers' crack texture (0.31.172, Kevin: towers that "visually break as their health gets lower").

A tileable 512 x 512 RGB texture the tower shader (scripts/siege/tower.gdshader) lays over the stone, box-mapped in the
model's own space:
  R  the cracks: thin, jagged lines along the edges of a Worley cell network (a crack, 1; plain stone, 0)
  G  where they show first: smooth tileable noise -- a texel's crack shows once the tower's damage passes it, so the
     cracks spread over the tower as it loses health instead of fading in everywhere at once
  B  0 (unused)

  python3 tools/tower_cracks.py [OUT.png]      (default assets/meshy/towers/cracks.png)
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "assets", "meshy", "towers", "cracks.png")
N = 512


def tile_dist(px, py, pts):
    # distances from every pixel to every point on the torus (the texture repeats)
    dx = np.abs(px[..., None] - pts[:, 0])
    dy = np.abs(py[..., None] - pts[:, 1])
    dx = np.minimum(dx, 1.0 - dx)
    dy = np.minimum(dy, 1.0 - dy)
    return np.sqrt(dx * dx + dy * dy)


def value_noise(rng, cells):
    # smooth tileable noise: a random lattice, bicubic-ish (smoothstep) interpolation, wraps at the edges
    g = rng.random((cells, cells))
    t = np.arange(N) / N * cells
    i0 = np.floor(t).astype(int)
    f = t - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    a = g[i0[:, None], i0[None, :]]
    b = g[i0[:, None], i1[None, :]]
    c = g[i1[:, None], i0[None, :]]
    d = g[i1[:, None], i1[None, :]]
    fy, fx = f[:, None], f[None, :]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def main():
    rng = np.random.default_rng(172)
    ys, xs = np.mgrid[0:N, 0:N] / N
    # jitter the lookup with noise so the cell edges wander like real cracks
    wob = (value_noise(rng, 16) - 0.5) * 0.035 + (value_noise(rng, 48) - 0.5) * 0.012
    wob2 = (value_noise(rng, 16) - 0.5) * 0.035 + (value_noise(rng, 48) - 0.5) * 0.012
    pts = rng.random((22, 2))
    d = tile_dist((xs + wob) % 1.0, (ys + wob2) % 1.0, pts)
    d.sort(axis=-1)
    edge = d[..., 1] - d[..., 0]                       # 0 on a cell's edge
    width = 0.016 + 0.014 * value_noise(rng, 8)        # thicker in places (read from the game camera)
    crack = np.clip(1.0 - edge / width, 0.0, 1.0) ** 0.7
    # leave out a share of the edges (cracks, not a tiled floor): the network only where this noise allows
    keep = np.clip((value_noise(rng, 6) - 0.32) * 4.0, 0.0, 1.0)
    crack *= keep
    order = value_noise(rng, 5) * 0.75 + value_noise(rng, 13) * 0.25
    order = (order - order.min()) / (order.max() - order.min())
    img = np.zeros((N, N, 3), np.uint8)
    img[..., 0] = (crack * 255).astype(np.uint8)
    img[..., 1] = (order * 255).astype(np.uint8)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(img).save(OUT, optimize=True)
    print("cracks -> %s (%.1f %% cracked)" % (os.path.normpath(OUT), 100.0 * float((crack > 0.3).mean())))


if __name__ == "__main__":
    main()
