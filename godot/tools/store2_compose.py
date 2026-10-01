#!/usr/bin/env python3
"""Fatebound - cinematic Play Store screenshots (Round 26).

    python3 tools/store2_compose.py --raw /tmp/store2 --reveal /tmp/trailer2/reveal_fx.avi --out DIR

Input: full-bleed portrait engine renders raw_<shot>.png (1080x1920, tools/store2_shots.gd: the trailer's staged
shots frozen at their best moment, HUD hidden). Output: 01_*.png .. 08_*.png (1080x1920, gold headline + subline
over a dark top band) and feature_graphic.png (1024x500, from the golden-hour title reveal). Every claim below is
true of build 0.25.0.
"""
import argparse
import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, "..", "assets", "fonts")
W, H = 1080, 1920
SHOTS = [
    ("assault",  "16 VS 16 CASTLE SIEGE",       "Storm their gates online, or offline with bots"),
    ("captive",  "THEY STOLE YOUR KING",        "Break into their dungeon and carry him home"),
    ("heroes",   "THE HAT MAKES THE HERO",      "Step into a shop and become a Knight, Mage, Rogue and more"),
    ("build",    "CLIMB THEIR WALLS",           "Workers chop, mine and build ladders"),
    ("rampart",  "RAIN ARROWS FROM THE WALLS",  "Hold the rampart and shoot over the parapet"),
    ("backstab", "STAB THEM IN THE BACK",       "Rogues strike from behind"),
    ("feast",    "FATTEN THEIR KING",           "Catch fish and feed him. Heavy Kings are hard to carry home."),
    ("carry",    "BRING YOUR KING HOME",        "First to three rescues wins"),
]


def gold_text(img, text, font, cx, y, stroke):
    bb = font.getbbox(text, stroke_width=stroke)
    x = cx - (bb[2] - bb[0]) // 2 - bb[0]
    sh = Image.new("L", img.size, 0)
    ImageDraw.Draw(sh).text((x + 5, y + 9), text, font=font, fill=170, stroke_width=stroke, stroke_fill=170)
    img.paste((0, 0, 0, 255), (0, 0), sh.filter(ImageFilter.GaussianBlur(8)))
    ImageDraw.Draw(img).text((x, y), text, font=font, fill=(46, 25, 8, 255), stroke_width=stroke, stroke_fill=(46, 25, 8, 255))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text((x, y), text, font=font, fill=255)
    grad = Image.new("RGBA", img.size)
    gd = ImageDraw.Draw(grad)
    top, bot = y + bb[1], y + bb[3]
    for yy in range(top, bot + 1):
        t = (yy - top) / max(1, bot - top)
        gd.line([(0, yy), (img.size[0], yy)], fill=(255, int(244 - 80 * t), int(170 - 130 * t), 255))
    img.paste(grad, (0, 0), mask)
    return y + bb[3]


def wrap(text, font, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if font.getbbox(t)[2] - font.getbbox(t)[0] <= width:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def compose(raw_path, headline, subline, out_path):
    base = Image.open(raw_path).convert("RGBA").resize((W, H), Image.LANCZOS)
    # Dark band at the top (fades into the picture) and a soft bottom vignette.
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for y in range(0, 620):
        a = int(205 * (1.0 - y / 620.0) ** 1.6)
        sd.line([(0, y), (W, y)], fill=(8, 6, 4, a))
    for y in range(H - 260, H):
        a = int(110 * ((y - (H - 260)) / 260.0) ** 2)
        sd.line([(0, y), (W, y)], fill=(8, 6, 4, a))
    img = Image.alpha_composite(base, shade)
    size = 112
    f = ImageFont.truetype(os.path.join(FONTS, "LuckiestGuy-Regular.ttf"), size)
    while f.getbbox(headline, stroke_width=10)[2] - f.getbbox(headline, stroke_width=10)[0] > W - 90 and size > 60:
        size -= 4
        f = ImageFont.truetype(os.path.join(FONTS, "LuckiestGuy-Regular.ttf"), size)
    y = gold_text(img, headline, f, W // 2, 92, 10)
    fs = ImageFont.truetype(os.path.join(FONTS, "Fredoka-Variable.ttf"), 46)
    try:
        fs.set_variation_by_name("SemiBold")
    except Exception:
        pass
    yy = y + 34
    for line in wrap(subline, fs, W - 140)[:2]:
        bb = fs.getbbox(line, stroke_width=4)
        ImageDraw.Draw(img).text(((W - (bb[2] - bb[0])) // 2 - bb[0], yy - bb[1]), line, font=fs, fill=(255, 250, 238, 255),
                                 stroke_width=4, stroke_fill=(24, 14, 6, 255))
        yy += 62
    img.convert("RGB").save(out_path, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="/tmp/store2")
    ap.add_argument("--reveal", default="/tmp/trailer2/reveal_fx.avi")
    ap.add_argument("--reveal-at", type=float, default=5.5)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for k, (shot, head, sub) in enumerate(SHOTS):
        compose(os.path.join(a.raw, f"raw_{shot}.png"), head, sub, os.path.join(a.out, f"{k + 1:02d}_{shot}.png"))
        print("screenshot", k + 1, shot)
    # Feature graphic (1024x500): the title reveal -- FATEBOUND, its god rays and the tagline over the kingdom.
    frame = os.path.join(a.raw, "reveal_frame.png")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(a.reveal_at), "-i", a.reveal, "-frames:v", "1", frame], check=True)
    fr = Image.open(frame).convert("RGB")
    crop_h = int(1920 * 500 / 1024)
    fr.crop((0, 0, 1920, crop_h)).resize((1024, 500), Image.LANCZOS).save(os.path.join(a.out, "feature_graphic.png"), optimize=True)
    print("feature graphic")


if __name__ == "__main__":
    main()
