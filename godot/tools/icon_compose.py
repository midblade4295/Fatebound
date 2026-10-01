#!/usr/bin/env python3
"""Fatebound game icon (Round 27): Kevin's King (an engine render, tools/icon_render.gd) as a sticker on a
royal-blue sunburst. Writes the Play Store icon (512), the legacy launcher icon (192) and the Android adaptive
layers (432: foreground = the King inside the safe zone, background = the sunburst, monochrome = his silhouette).

    python3 tools/icon_compose.py --king /tmp/icon/king_1024.png --out assets/branding --store /path/icon_512.png
"""
import argparse
import math
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024


def sunburst(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    c = size / 2.0
    for y in range(size):
        for x in range(size):
            dx, dy = x - c, y - c * 0.82
            r = math.hypot(dx, dy) / (size * 0.75)
            a = math.atan2(dy, dx)
            ray = 0.5 + 0.5 * math.cos(a * 16)                       # 16 rays
            t = min(1.0, r)
            base = (int(42 + (16 - 42) * t), int(111 + (44 - 111) * t), int(214 + (118 - 214) * t))
            lift = (0.10 * ray) * (1.0 - t * 0.5)
            glow = max(0.0, 1.0 - r * 2.2) ** 2 * 0.55
            px[x, y] = tuple(min(255, int(v + (255 - v) * (lift + glow))) for v in base)
    return img


def sticker(king, outline_px, color):
    a = king.split()[3]
    ring = a.filter(ImageFilter.MaxFilter(outline_px * 2 + 1)).filter(ImageFilter.GaussianBlur(1.2))
    out = Image.new("RGBA", king.size, color + (0,))
    out.putalpha(ring)
    shadow = Image.new("RGBA", king.size, (0, 0, 0, 0))
    shadow.putalpha(ring.filter(ImageFilter.GaussianBlur(10)).point(lambda v: int(v * 0.45)))
    canvas = Image.new("RGBA", king.size, (0, 0, 0, 0))
    canvas.alpha_composite(shadow, (0, 10))
    canvas.alpha_composite(out)
    canvas.alpha_composite(king)
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--king", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--store", required=True)
    a = ap.parse_args()
    king = Image.open(a.king).convert("RGBA").resize((S, S), Image.LANCZOS)
    st = sticker(king, 14, (11, 21, 48))
    bg = sunburst(S).convert("RGBA")
    full = bg.copy()
    full.alpha_composite(st)
    vign = Image.new("L", (S, S), 0)
    ImageDraw.Draw(vign).ellipse((-S * 0.25, -S * 0.25, S * 1.25, S * 1.25), fill=255)
    vign = vign.filter(ImageFilter.GaussianBlur(120))
    dark = Image.new("RGBA", (S, S), (6, 14, 40, 255))
    full = Image.composite(full, Image.alpha_composite(full, Image.new("RGBA", (S, S), (6, 14, 40, 90))), vign)
    os.makedirs(a.out, exist_ok=True)
    full.convert("RGB").resize((512, 512), Image.LANCZOS).save(a.store, optimize=True)
    full.convert("RGB").resize((192, 192), Image.LANCZOS).save(os.path.join(a.out, "icon.png"), optimize=True)
    # Adaptive: the foreground keeps head and crown inside the 288 px safe circle of the 432 layer.
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    small = st.resize((340, 340), Image.LANCZOS)
    fg.alpha_composite(small, (46, 92))
    fg.save(os.path.join(a.out, "foreground.png"), optimize=True)
    bg.convert("RGB").resize((432, 432), Image.LANCZOS).save(os.path.join(a.out, "background.png"), optimize=True)
    mono = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    sil = Image.new("RGBA", (340, 340), (255, 255, 255, 255))
    sil.putalpha(king.split()[3].resize((340, 340), Image.LANCZOS))
    mono.alpha_composite(sil, (46, 92))
    mono.save(os.path.join(a.out, "monochrome.png"), optimize=True)
    print("icons written")


if __name__ == "__main__":
    main()
