#!/usr/bin/env python3
"""Fatebound trailer 4 -- light over the finale (the 3D gold title is rendered in-engine by tools/trailer4_shots.gd).

    python3 tools/trailer4_title_fx.py --shot /tmp/trailer4/golden.avi --sun /tmp/trailer4/golden_sun.json \\
        --out /tmp/trailer4/golden_fx.mp4 [--land 4.9] [--tag-at 7.0]

Per frame: god rays -- the bright sky round the low sun zoom-blurred out from its screen position, so the letters in front
of it cut shafts through the light -- ramping up as the title flies in; a horizontal lens streak through the sun; a soft
flash as the title lands (--land); then the tagline under it (--tag-at). Needs numpy, Pillow, ffmpeg.
"""
import argparse, json, os, subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS = 1920, 1080, 30
HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "assets", "fonts", "LuckiestGuy-Regular.ttf")
QW, QH = 480, 270


def tag_layer():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    big = ImageFont.truetype(FONT, 64)
    small = ImageFont.truetype(FONT, 38)
    for text, f, y, fill in [("THE ULTIMATE 16 VS 16 CASTLE SIEGE", big, 600, (255, 226, 150, 255)),
                             ("GRAB A HAT. STORM THE CASTLE. BRING YOUR KING HOME.", small, 680, (255, 246, 228, 255))]:
        bb = d.textbbox((0, 0), text, font=f, stroke_width=6)
        x = (W - (bb[2] - bb[0])) // 2 - bb[0]
        sh = Image.new("L", (W, H), 0)
        ImageDraw.Draw(sh).text((x + 3, y + 6), text, font=f, fill=150, stroke_width=6)
        img.paste((0, 0, 0, 200), (0, 0), sh.filter(ImageFilter.GaussianBlur(6)))
        d.text((x, y), text, font=f, fill=fill, stroke_width=6, stroke_fill=(52, 28, 8, 255))
    return np.asarray(img).astype(np.float32) / 255.0


def rays(frame_q, sx, sy):
    # bright pass, then a zoom blur towards (sx, sy) in quarter-res pixels
    lum = frame_q.mean(axis=2)
    bright = np.clip((lum - 0.80) / 0.2, 0.0, 1.0)[..., None] * frame_q
    acc = np.zeros_like(bright)
    ys, xs = np.mgrid[0:QH, 0:QW].astype(np.float32)
    n = 28
    for k in range(n):
        s = 1.0 - 0.6 * k / n
        u = np.clip((sx + (xs - sx) * s).astype(np.int32), 0, QW - 1)
        v = np.clip((sy + (ys - sy) * s).astype(np.int32), 0, QH - 1)
        acc += bright[v, u] * (0.965 ** k)
    return acc / n * 3.2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot", required=True)
    ap.add_argument("--sun", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--land", type=float, default=4.9)
    ap.add_argument("--tag-at", type=float, default=-1.0, help="seconds; -1 (default) = no tagline: only the title")
    a = ap.parse_args()
    sun = json.load(open(a.sun))
    tag = tag_layer()
    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", a.shot, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
                            "-i", "-", "-c:v", "libx264", "-crf", "15", "-preset", "medium", "-pix_fmt", "yuv420p", a.out], stdin=subprocess.PIPE)
    i = 0
    warm = np.array([1.0, 0.80, 0.52], np.float32)
    while True:
        raw = dec.stdout.read(W * H * 3)
        if len(raw) < W * H * 3:
            break
        f = np.frombuffer(raw, np.uint8).reshape(H, W, 3).astype(np.float32) / 255.0
        t = i / FPS
        s = sun[min(i, len(sun) - 1)]
        sx, sy, vis = float(s[0]), float(s[1]), bool(s[2])
        out = f
        if vis:
            q = np.asarray(Image.fromarray((f * 255).astype(np.uint8)).resize((QW, QH), Image.BILINEAR)).astype(np.float32) / 255.0
            amt = 0.35 + 0.65 * np.clip((t - 2.0) / max(a.land - 2.0, 0.1), 0.0, 1.0)
            r = rays(q, sx * QW, sy * QH) * amt
            r_full = np.asarray(Image.fromarray((np.clip(r, 0, 1) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)).astype(np.float32) / 255.0
            out = 1.0 - (1.0 - out) * (1.0 - r_full * warm)               # screen
            # lens streak: a thin horizontal line through the sun, brightest at the sun
            yy = np.arange(H, dtype=np.float32)[:, None]
            xx = np.arange(W, dtype=np.float32)[None, :]
            streak = np.exp(-((yy - sy * H) / 3.0) ** 2) * np.exp(-np.abs(xx - sx * W) / 520.0) * 0.55 * amt
            out = 1.0 - (1.0 - out) * (1.0 - streak[..., None] * np.array([1.0, 0.86, 0.66], np.float32))
        # the landing flash
        fl = max(0.0, 1.0 - abs(t - a.land) / 0.18) * 0.32
        if fl > 0:
            out = out + (1.0 - out) * fl
        # tagline
        ta = np.clip((t - a.tag_at) / 0.6, 0.0, 1.0) if a.tag_at >= 0 else 0.0
        if ta > 0:
            al = tag[..., 3:4] * ta
            out = out * (1.0 - al) + tag[..., :3] * al
        # fade out over the last 0.8 s
        n_total = len(sun)
        tail = (n_total - 1 - i) / FPS
        if tail < 0.8:
            out = out * max(0.0, tail / 0.8)
        enc.stdin.write((np.clip(out, 0, 1) * 255).astype(np.uint8).tobytes())
        i += 1
    enc.stdin.close()
    enc.wait()
    print("TITLE_FX %d frames -> %s" % (i, a.out))


if __name__ == "__main__":
    main()
