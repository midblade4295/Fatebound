#!/usr/bin/env python3
"""Fatebound trailer 2 - the finale reveal's VFX, composited over the rendered "reveal" shot.

    python3 tools/trailer2_reveal_fx.py --shot /tmp/trailer2/reveal.avi --sun /tmp/trailer2/reveal_sun.json \\
        --out /tmp/trailer2/reveal_fx.avi [--title-at 1.3]

The title lands at --title-at seconds (on the music's drop): a white flash, FATEBOUND (gold Luckiest Guy) settling
from 112 %, god rays -- the sun's light, occluded by the letters, zoom-blurred out from the sun's screen position
(recorded per frame by tools/trailer2_shots.gd) -- a warm rim glow on the letters, a horizontal lens streak through
the sun, rising embers, then the tagline. Needs numpy, Pillow, ffmpeg.
"""
import argparse
import json
import math
import os
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1920, 1080
FPS = 30
TITLE_TOP = 108             # the sun (16 % down) sits behind the letters' upper half: its light bursts through them
HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, "..", "assets", "fonts")


def title_layer():
    # Gold-gradient FATEBOUND with a dark outline and a soft drop shadow (RGBA, full frame) + its mask.
    f = ImageFont.truetype(os.path.join(FONTS, "LuckiestGuy-Regular.ttf"), 250)
    text = "FATEBOUND"
    stroke = 15
    bb = f.getbbox(text, stroke_width=stroke)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    x, y = (W - w) // 2 - bb[0], TITLE_TOP - bb[1]
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh).text((x + 6, y + 12), text, font=f, fill=170, stroke_width=stroke, stroke_fill=170)
    img.paste((0, 0, 0, 255), (0, 0), sh.filter(ImageFilter.GaussianBlur(12)))
    ImageDraw.Draw(img).text((x, y), text, font=f, fill=(46, 25, 8, 255), stroke_width=stroke, stroke_fill=(46, 25, 8, 255))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).text((x, y), text, font=f, fill=255)
    grad = Image.new("RGBA", (W, H))
    gd = ImageDraw.Draw(grad)
    top, bot = TITLE_TOP, TITLE_TOP + h
    for yy in range(H):
        t = min(1.0, max(0.0, (yy - top) / max(1, bot - top)))
        gd.line([(0, yy), (W, yy)], fill=(255, int(244 - 80 * t), int(170 - 130 * t), 255))
    img.paste(grad, (0, 0), mask)
    full = Image.new("L", (W, H), 0)
    ImageDraw.Draw(full).text((x, y), text, font=f, fill=255, stroke_width=stroke, stroke_fill=255)
    return img, full, (W // 2, TITLE_TOP + h // 2)


def tagline_layer():
    fred = os.path.join(FONTS, "Fredoka-Variable.ttf")
    out = []
    for text, size, y, col in [("Storm castles. Steal hats. Rescue the King.", 64, 470, (255, 255, 255, 255)),
                               ("16 vs 16  \u00b7  Online or offline with bots", 44, 560, (240, 230, 210, 255))]:
        f = ImageFont.truetype(fred, size)
        try:
            f.set_variation_by_name("SemiBold")
        except Exception:
            pass
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        bb = f.getbbox(text, stroke_width=4)
        ImageDraw.Draw(img).text(((W - (bb[2] - bb[0])) // 2 - bb[0], y - bb[1]), text, font=f, fill=col,
                                 stroke_width=4, stroke_fill=(30, 18, 8, 255))
        out.append(np.asarray(img).astype(np.float32) / 255.0)
    return out


def zoom_blur(src, cx, cy, samples=40, spread=0.95):
    # Sum of copies of src scaled up about (cx, cy): light streaks radiating from the centre.
    h, w = src.shape[:2]
    acc = np.zeros_like(src)
    wsum = 0.0
    im = Image.fromarray(np.clip(src * 255.0, 0, 255).astype(np.uint8))
    for k in range(samples):
        s = 1.0 + spread * k / samples
        wgt = (1.0 - k / samples) ** 1.5
        nw, nh = int(w * s), int(h * s)
        big = im.resize((nw, nh), Image.BILINEAR)
        ox, oy = int(cx * s - cx), int(cy * s - cy)
        acc += np.asarray(big.crop((ox, oy, ox + w, oy + h))).astype(np.float32) / 255.0 * wgt
        wsum += wgt
    return acc / wsum


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot", default="/tmp/trailer2/reveal.avi")
    ap.add_argument("--sun", default="/tmp/trailer2/reveal_sun.json")
    ap.add_argument("--out", default="/tmp/trailer2/reveal_fx.avi")
    ap.add_argument("--title-at", type=float, default=1.3)
    a = ap.parse_args()
    sun = json.load(open(a.sun))
    title_img, title_full, title_c = title_layer()
    title_np = np.asarray(title_img).astype(np.float32) / 255.0
    occl_small = np.asarray(title_full.resize((W // 4, H // 4), Image.BILINEAR)).astype(np.float32) / 255.0
    rim = np.asarray(title_full.filter(ImageFilter.GaussianBlur(16))).astype(np.float32) / 255.0
    tags = tagline_layer()
    rng = np.random.default_rng(3)
    embers = []
    reader = subprocess.Popen(["ffmpeg", "-v", "error", "-i", a.shot, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                              stdout=subprocess.PIPE)
    writer = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                               "-r", str(FPS), "-i", "-", "-c:v", "mjpeg", "-q:v", "2", a.out], stdin=subprocess.PIPE)
    yy, xx = np.mgrid[0:H // 4, 0:W // 4].astype(np.float32)
    fi = 0
    while True:
        raw = reader.stdout.read(W * H * 3)
        if len(raw) < W * H * 3:
            break
        frame = np.frombuffer(raw, np.uint8).reshape(H, W, 3).astype(np.float32) / 255.0
        tau = fi / FPS
        sx, sy, vis = sun[min(max(fi - 1, 0), len(sun) - 1)]
        sx, sy = sx * W, sy * H
        dt = tau - a.title_at                      # < 0 before the title lands
        # Sun light: a warm disc + halo, stronger once the title lands (breathing a little).
        swell = min(1.0, 0.35 + 0.65 * max(0.0, tau / max(0.01, a.title_at)))
        power = swell * (1.0 + (0.25 * math.sin(dt * 2.2) if dt > 0 else 0.0))
        d2 = ((xx - sx / 4) ** 2 + (yy - sy / 4) ** 2)
        # A bright disc and wide halo, broken into slowly turning rays (sunbeams show even where no
        # letter blocks them; the letters cut their own shadow streaks through it).
        ang = np.arctan2(yy - sy / 4, xx - sx / 4)
        beams = 0.55 + 0.45 * (0.5 + 0.5 * np.sin(ang * 13.0 + tau * 0.35)) * (0.5 + 0.5 * np.sin(ang * 7.0 - tau * 0.22 + 1.3))
        light = (np.exp(-d2 / (2 * 26.0 ** 2)) * 1.6 + np.exp(-d2 / (2 * 95.0 ** 2)) * 0.9 * beams
                 + np.exp(-d2 / (2 * 210.0 ** 2)) * 0.35 * beams)
        occ = occl_small if dt > 0 else np.zeros_like(occl_small)
        shafts = zoom_blur((light * (1.0 - occ * min(1.0, dt / 0.15 if dt > 0 else 0.0)))[..., None]
                           * np.array([1.0, 0.82, 0.55], np.float32), sx / 4, sy / 4)
        rays_amt = (0.45 + 0.75 * min(1.0, max(0.0, dt) / 0.6)) * power if vis else 0.0
        shafts_big = np.asarray(Image.fromarray(np.clip(shafts * 255, 0, 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)).astype(np.float32) / 255.0
        out = 1.0 - (1.0 - frame) * (1.0 - np.clip(shafts_big * rays_amt, 0, 1))          # screen blend
        # Lens streak through the sun.
        if dt > 0 and vis:
            ys = np.exp(-((np.arange(H) - sy) ** 2) / (2 * 3.5 ** 2))[:, None]
            xs = np.exp(-((np.arange(W) - sx) ** 2) / (2 * 520.0 ** 2))[None, :]
            streak = (ys * xs)[..., None] * np.array([1.0, 0.85, 0.6], np.float32) * 0.55 * min(1.0, dt / 0.3)
            out = 1.0 - (1.0 - out) * (1.0 - np.clip(streak, 0, 1))
        if dt >= 0:
            # Title: slams in from 112 % over 0.5 s, rim-lit.
            p = min(1.0, dt / 0.5)
            sc = 1.12 - 0.12 * (1 - (1 - p) ** 3)
            alpha_in = min(1.0, dt / 0.12)
            if abs(sc - 1.0) > 1e-3:
                ti = Image.fromarray((title_np * 255).astype(np.uint8)).resize((int(W * sc), int(H * sc)), Image.BICUBIC)
                ox, oy = int(title_c[0] * sc - title_c[0]), int(title_c[1] * sc - title_c[1])
                t_np = np.asarray(ti.crop((ox, oy, ox + W, oy + H))).astype(np.float32) / 255.0
            else:
                t_np = title_np
            glow = rim[..., None] * np.array([1.0, 0.78, 0.4], np.float32) * 0.6 * alpha_in
            out = 1.0 - (1.0 - out) * (1.0 - np.clip(glow, 0, 1))
            ta = t_np[..., 3:4] * alpha_in
            out = out * (1 - ta) + t_np[..., :3] * ta
            # Embers rising from around the title.
            for _ in range(3 if dt < 3.0 else 1):
                embers.append([rng.uniform(300, W - 300), rng.uniform(330, 560), rng.uniform(-0.4, 0.4),
                               rng.uniform(-2.6, -1.2), rng.uniform(1.2, 2.6), 0.0, rng.uniform(1.6, 3.2)])
            ember_layer = Image.new("L", (W, H), 0)
            ed = ImageDraw.Draw(ember_layer)
            alive = []
            for e in embers:
                e[0] += e[2] + 0.6 * math.sin(e[5] * 3.0)
                e[1] += e[3]
                e[5] += 1.0 / FPS
                if e[5] < e[6]:
                    life = 1.0 - e[5] / e[6]
                    r = e[4]
                    ed.ellipse((e[0] - r, e[1] - r, e[0] + r, e[1] + r), fill=int(255 * life))
                    alive.append(e)
            embers[:] = alive
            el = np.asarray(ember_layer.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32)[..., None] / 255.0
            out = 1.0 - (1.0 - out) * (1.0 - np.clip(el * np.array([1.0, 0.75, 0.35], np.float32) * 1.3, 0, 1))
            # Flash on impact.
            flash = max(0.0, 1.0 - dt / 0.35) * 0.85
            out = out + (1.0 - out) * flash
            # Tagline and subline.
            for k, tg in enumerate(tags):
                ta2 = min(1.0, max(0.0, (dt - 1.0 - 0.5 * k) / 0.4))
                if ta2 > 0:
                    aa = tg[..., 3:4] * ta2
                    out = out * (1 - aa) + tg[..., :3] * aa
        writer.stdin.write((np.clip(out, 0, 1) * 255).astype(np.uint8).tobytes())
        fi += 1
    writer.stdin.close()
    writer.wait()
    print("wrote", a.out, fi, "frames")


if __name__ == "__main__":
    main()
