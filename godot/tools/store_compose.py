#!/usr/bin/env python3
"""Fatebound: Siege - compose the Google Play images from raw game renders.

Input : raw renders store_<name>.png (1080x1920 portrait; store_feature.png 1600x782 landscape),
        made by tools/store_shots_match.gd and tools/store_shots_app.gd.
Output: 01_battle.png ... 08_home.png (1080x1920, caption + framed screenshot) and
        feature_graphic_1024x500.png.

    python3 tools/store_compose.py --raw /tmp --out store_out [--fonts DIR]

Fonts: the game's Cinzel Black (titles) and Nunito ExtraBold (text). They ship as .woff2 in
assets/fonts; this converts them to .ttf with fontTools (pip install fonttools brotli) unless
Cinzel-Black.ttf / Nunito-ExtraBold.ttf already exist in --fonts. Both are SIL OFL licensed.
Needs Pillow.
"""
import argparse
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1080, 1920
GOLD = (255, 210, 87)
# (raw render name, headline, subline) in store order. Every claim is true of build 0.19.1.
SHOTS = [
    ("battle",    "STORM THE CASTLE",        "16 vs 16 sieges, online or offline with bots"),
    ("rescue",    "RESCUE YOUR KING",        "Carry him home from the enemy dungeon. Three rescues wins."),
    ("hats",      "THE HAT MAKES THE HERO",  "Walk into a hat shop and become a Knight, Mage, Priest and more"),
    ("abilities", "SPIN. SHIELD. SMASH.",    "Every class has its own ability"),
    ("feed",      "FEED THEIR KING CAKE",    "Heavier captives are harder to carry home. Delicious sabotage."),
    ("tutorial",  "LEARN FROM THE HERALD",   "A funny, hands-on walkthrough gets you battle-ready"),
    ("shop",      "SKINS, WEAPONS & PACKS",  "Cosmetics only. No pay-to-win."),
    ("home",      "SEVEN CLASSES",           "Knight, Barbarian, Rogue, Ranger, Mage, Priest and Worker"),
]


def fonts(font_dir: str) -> tuple:
    # Kevin's pick: Luckiest Guy for headlines (gold gradient), Fredoka for text. Both ship in
    # assets/fonts as .ttf (licences alongside), so no conversion is needed.
    here = os.path.dirname(os.path.abspath(__file__))
    a = os.path.join(here, "..", "assets", "fonts")
    return os.path.join(a, "LuckiestGuy-Regular.ttf"), os.path.join(a, "Fredoka-Variable.ttf")


def body_font(path, size):
    f = ImageFont.truetype(path, size)
    try:
        f.set_variation_by_name("SemiBold")
    except Exception:
        pass
    return f


def gold(img, text, font, cx, y, stroke):
    # Gold gradient fill, dark outline, soft shadow (the trailer's title treatment).
    W, H = img.size
    bb = font.getbbox(text, stroke_width=stroke)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    x, yy = cx - w // 2 - bb[0], y - bb[1]
    sh = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh).text((x + stroke // 2, yy + stroke), text, font=font, fill=190, stroke_width=stroke, stroke_fill=190)
    img.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), sh.filter(ImageFilter.GaussianBlur(max(3, stroke))))
    ImageDraw.Draw(img).text((x, yy), text, font=font, fill=(46, 25, 8), stroke_width=stroke, stroke_fill=(46, 25, 8))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).text((x, yy), text, font=font, fill=255)
    grad = Image.new("RGB", (W, H))
    gd = ImageDraw.Draw(grad)
    for y2 in range(H):
        t = min(1.0, max(0.0, (y2 - y) / max(1, h)))
        gd.line([(0, y2), (W, y2)], fill=(int(255 - 10 * t), int(236 - 80 * t), int(140 - 110 * t)))
    img.paste(grad, (0, 0), mask)
    return h


def background() -> Image.Image:
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=(int(11 + 18 * t), int(22 + 25 * t), int(48 + 44 * t)))
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-200, -260, W + 200, 520), fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    return Image.composite(Image.new("RGB", (W, H), (120, 88, 30)), im, glow)


def fit(path: str, text: str, max_w: int, start: int) -> ImageFont.FreeTypeFont:
    size = start
    while size > 30:
        f = ImageFont.truetype(path, size)
        if f.getlength(text) <= max_w:
            return f
        size -= 2
    return ImageFont.truetype(path, size)


def wrap(text: str, font: ImageFont.FreeTypeFont, max_w: int) -> list:
    lines, cur = [], ""
    for w in text.split():
        t = (cur + " " + w).strip()
        if font.getlength(t) <= max_w:
            cur = t
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return lines


def outlined(d: ImageDraw.ImageDraw, xy: tuple, text: str, font, fill, px: int) -> None:
    x, y = xy
    for dx in (-px, 0, px):
        for dy in (-px, 0, px):
            d.text((x + dx, y + dy), text, font=font, fill=(40, 24, 6))
    d.text((x, y), text, font=font, fill=fill)


def screenshot(raw: str, out: str, idx: int, name: str, head: str, sub: str, title_ttf: str, body_ttf: str) -> str:
    im = background()
    d = ImageDraw.Draw(im)
    hf = fit(title_ttf, head, W - 110, 96)
    y = 64
    hh = gold(im, head, hf, W // 2, y, 6)
    d = ImageDraw.Draw(im)
    sf = body_font(body_ttf, 42)
    ly = y + hh + 30
    for line in wrap(sub, sf, W - 140):
        d.text(((W - sf.getlength(line)) / 2, ly), line, font=sf, fill=(240, 236, 226))
        ly += 52
    top = max(ly + 34, 330)
    shot = Image.open(os.path.join(raw, f"store_{name}.png")).convert("RGB")
    scale = min((W - 150) / shot.width, (H - top - 60) / shot.height)
    sw, sh = int(shot.width * scale), int(shot.height * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    sx, sy = (W - sw) // 2, top
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((sx - 6, sy + 14, sx + sw + 6, sy + sh + 26), 44, fill=170)
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    im = Image.composite(Image.new("RGB", (W, H), (4, 6, 14)), im, shadow)
    ImageDraw.Draw(im).rounded_rectangle((sx - 8, sy - 8, sx + sw + 8, sy + sh + 8), 44, fill=GOLD)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw, sh), 38, fill=255)
    im.paste(shot, (sx, sy), mask)
    path = os.path.join(out, f"{idx:02d}_{name}.png")
    im.save(path, optimize=True)
    return path


def feature(raw: str, out: str, title_ttf: str, body_ttf: str) -> str:
    fw, fh = 1024, 500
    src = Image.open(os.path.join(raw, "store_feature.png")).convert("RGB")
    fg = src.resize((fw, int(src.height * fw / src.width)), Image.LANCZOS)
    top = (fg.height - fh) // 2
    fg = fg.crop((0, top, fw, top + fh))
    shade = Image.new("L", (fw, fh), 0)
    sd = ImageDraw.Draw(shade)
    for x in range(fw):
        sd.line([(x, 0), (x, fh)], fill=int(max(0, 225 - x * 0.46)))
    fg = Image.composite(Image.new("RGB", (fw, fh), (8, 12, 28)), fg, shade)
    d = ImageDraw.Draw(fg)
    x, y = 40, 120
    # The game is just "Fatebound" (no "Siege" line).
    th = gold(fg, "FATEBOUND", ImageFont.truetype(title_ttf, 96), 40 + ImageFont.truetype(title_ttf, 96).getbbox("FATEBOUND")[2] // 2, y + 10, 6)
    d = ImageDraw.Draw(fg)
    y = y + 10 + th - 132
    bf = body_font(body_ttf, 32)
    for k, line in enumerate(["Storm castles. Steal hats.", "Rescue the King."]):
        d.text((x + 6, y + 162 + k * 40), line, font=bf, fill=(0, 0, 0))
        d.text((x + 4, y + 160 + k * 40), line, font=bf, fill=(255, 255, 255))
    path = os.path.join(out, "feature_graphic_1024x500.png")
    fg.save(path, optimize=True)
    return path


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", default="/tmp", help="folder with store_<name>.png raw renders")
    ap.add_argument("--out", default="store_out", help="output folder")
    ap.add_argument("--fonts", default="/tmp", help="folder for (or with) the converted .ttf fonts")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    title_ttf, body_ttf = fonts(a.fonts)
    for i, (name, head, sub) in enumerate(SHOTS, 1):
        print(screenshot(a.raw, a.out, i, name, head, sub, title_ttf, body_ttf))
    print(feature(a.raw, a.out, title_ttf, body_ttf))


if __name__ == "__main__":
    main()
