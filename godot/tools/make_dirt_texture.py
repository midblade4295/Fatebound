#!/usr/bin/env python3
"""The map's dirt paths' texture (0.31.126, Kevin: "Make the paths on the map more natural looking like it's a dirt path").

Writes assets/terrain/dirt.png: 1024x1024, tiles seamlessly, in the painted look of grass.png and rock.png -- soft,
low-contrast cells of trodden earth, warmer and cooler patches, scattered pebbles lit from the top left, a fine grain.
terrain.gdshader lays it over the baked path mask (PATH_SCALE metres a tile) and adds the worn middle and the darker,
grassy edge itself. Deterministic (fixed seed), so running it again gives the same file.

  python3 godot/tools/make_dirt_texture.py [out.png]
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

N = 1024
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "terrain", "dirt.png")
rng = np.random.default_rng(1260)

# palette: light sand, mid earth, dark earth, pebble
LIGHT = np.array([196, 160, 112], float)
MID = np.array([168, 128, 86], float)
DARK = np.array([132, 96, 62], float)


def fft_noise(beta: float, seed: int) -> np.ndarray:
    # tileable 1/f^beta noise in 0..1 (an FFT field is periodic by construction)
    r = np.random.default_rng(seed)
    f = np.fft.fftfreq(N)
    fx, fy = np.meshgrid(f, f)
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1.0
    spec = (r.normal(size=(N, N)) + 1j * r.normal(size=(N, N))) / k ** beta
    spec[0, 0] = 0.0
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    return out / out.max()


def cells(n_pts: int, seed: int):
    # tileable Voronoi: per pixel the nearest site's id, and how close it is to a cell border (0 at the border)
    r = np.random.default_rng(seed)
    pts = r.random((n_pts, 2)) * N
    tree = cKDTree(pts, boxsize=N)
    yy, xx = np.mgrid[0:N, 0:N]
    q = np.stack([xx.ravel() + 0.5, yy.ravel() + 0.5], axis=1) % N
    d, idx = tree.query(q, k=2)
    border = (d[:, 1] - d[:, 0]).reshape(N, N)
    return idx[:, 0].reshape(N, N), border


# 1. trodden-earth cells: each cell a slightly different shade, a soft darker seam between them (like the grass)
cid, border = cells(90, 7)
shade = np.random.default_rng(8).uniform(-1.0, 1.0, 90)[cid]
seam = np.clip(border / 14.0, 0.0, 1.0) ** 0.5
# 2. patches: big warm/cool blotches and a mid-scale mottle
blot = fft_noise(2.4, 11)
mott = fft_noise(1.6, 12)
clump = fft_noise(1.1, 13)
t = 0.5 + 0.07 * shade + 0.70 * (blot - 0.5) + 0.35 * (mott - 0.5) + 0.18 * (clump - 0.5)
t = np.clip(t, 0.0, 1.0)
col = np.where(t[..., None] < 0.5,
               DARK + (MID - DARK) * (t[..., None] / 0.5),
               MID + (LIGHT - MID) * ((t[..., None] - 0.5) / 0.5))
col *= (0.96 + 0.04 * seam)[..., None]

# 3. pebbles: small rounded stones, lighter on top-left, a soft shadow below-right (drawn wrapped round the tile)
yy, xx = np.mgrid[0:N, 0:N].astype(float)
peb = np.zeros((N, N))
lit_map = np.ones((N, N))
shadow = np.zeros((N, N))
pr = np.random.default_rng(21)
for _ in range(150):
    cx, cy = pr.random(2) * N
    rad = pr.uniform(3.0, 7.0) * (2.0 if pr.random() < 0.1 else 1.0)
    sq = pr.uniform(0.6, 1.0)
    ang = pr.uniform(0, np.pi)
    tone = pr.uniform(0.8, 1.05)
    x0, x1 = int(cx - rad * 2.5), int(cx + rad * 2.5)
    y0, y1 = int(cy - rad * 2.5), int(cy + rad * 2.5)
    ys = np.arange(y0, y1) % N
    xs = np.arange(x0, x1) % N
    gy, gx = np.meshgrid(np.arange(y0, y1) - cy, np.arange(x0, x1) - cx, indexing="ij")
    ca, sa = np.cos(ang), np.sin(ang)
    u = (gx * ca + gy * sa) / rad
    v = (-gx * sa + gy * ca) / (rad * sq)
    dd = np.sqrt(u * u + v * v)
    body = np.clip((1.0 - dd) * 3.0, 0.0, 1.0)
    lit = np.clip(0.95 - 0.30 * (gx + gy) / (rad * 1.4), 0.6, 1.15) * tone
    su = ((gx - rad * 0.35) * ca + (gy - rad * 0.45) * sa) / rad
    sv = (-(gx - rad * 0.35) * sa + (gy - rad * 0.45) * ca) / (rad * sq)
    sh = np.clip((1.15 - np.sqrt(su * su + sv * sv)) * 2.0, 0.0, 1.0)
    sub_p = peb[np.ix_(ys, xs)]
    sub_s = shadow[np.ix_(ys, xs)]
    sub_l = lit_map[np.ix_(ys, xs)]
    newer = body > sub_p
    peb[np.ix_(ys, xs)] = np.maximum(sub_p, body)
    lit_map[np.ix_(ys, xs)] = np.where(newer, lit, sub_l)
    shadow[np.ix_(ys, xs)] = np.maximum(sub_s, sh * (1.0 - body))
pebble_col = np.array([176, 156, 126], float)
col *= (1.0 - 0.22 * shadow)[..., None]
pm = np.clip(peb, 0.0, 1.0)[..., None]
col = col * (1.0 - pm) + pebble_col * lit_map[..., None] * pm

# 4. fine grain
grain = np.random.default_rng(31).normal(0.0, 1.0, (N, N))
col *= (1.0 + 0.035 * grain)[..., None]

img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB")
img.save(OUT, optimize=True)
print("wrote", OUT, img.size)
