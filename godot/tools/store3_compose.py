#!/usr/bin/env python3
"""Fatebound Play Store screenshots and feature graphic (0.31.116, Kevin: "Give me new playstore screenshots and banner.
I want a mix of cinematic action screenshots along with gameplay screenshots along with some menu stuff like forge ect.
Put captions on them and make it all eye catching").

    python3 tools/store3_compose.py --raw DIR --out DIR

Every picture is a real render of the game:
  cine_<name>.png    1080x1920 cinematic stills, no HUD (tools/store3_shots.gd: trailer 6's staged runs, portrait cameras)
  play_<name>.png    1080x2400 matches with the real HUD (tools/store3_match.gd)
  menu_<name>.png    1080x2400 menus (tools/app_shots.gd)
  feature.png        2048x1000 wide cinematic still for the feature graphic
Out: 01_*.png .. 08_*.png (1080x1920, RGB) and feature_graphic_1024x500.png (RGB). Cinematic shots are full-bleed under
a gold headline; gameplay and menus sit in a phone over a blurred battle. Every caption is checked against the game
(see SHOTS).
"""
import argparse
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
F_HEAD = os.path.join(GODOT, "assets", "fonts", "LuckiestGuy-Regular.ttf")
F_SUB = os.path.join(GODOT, "store-listing", "tools", "fonts", "Nunito-ExtraBold.ttf")
LOGO_SRC = os.path.join(os.path.dirname(GODOT), "art_sources", "logo_concepts", "tied_2.png")
W, H = 1080, 1920

# (file, kind, source, headline lines, subline, accent colour, backdrop for phone shots)
SHOTS = [
    ("01_meteor", "full", "cine_meteor", ["CALL DOWN", "THE METEOR"],
     "Upgrade your Mage into an Archmage", (226, 96, 22), None),
    ("02_siege", "phone", "play_battle", ["16 VS 16", "CASTLE SIEGES"],
     "Battle online. Bots fill every empty slot", (40, 112, 214), "cine_gate_blast"),
    ("03_king", "phone", "play_rescue", ["STEAL THEIR KING.", "SAVE YOURS."],
     "Carry your King home 3 times to win", (190, 128, 16), "cine_rally"),
    ("04_hero", "full", "cine_rally", ["ANYONE CAN", "CHANGE FATE"],
     "Start as a villager. Grab a hat. Become a hero.", (52, 150, 82), None),
    ("05_gate_blast", "full", "cine_gate_blast", ["BLOW THEIR", "GATE SKY-HIGH"],
     "Grab the bomb and storm their castle", (214, 62, 34), None),
    ("06_forge", "phone", "menu_forge", ["FORGE LEGENDARY", "WEAPONS"],
     "Stars, elements and auras. Looks only, never pay-to-win", (150, 70, 220), "cine_meteor"),
    ("07_chests", "phone", "menu_chest", ["WIN CHESTS,", "CLAIM LOOT"],
     "Every win earns a chest", (176, 84, 222), "cine_gate_blast"),
    ("08_friends", "phone", "menu_friends", ["SQUAD UP", "WITH FRIENDS"],
     "Chat, add friends and party up for the next siege", (40, 112, 214), "cine_rally"),
]


# CALLOUTS: a magnifier bubble beside the phone -- the same moment from close up (tools/store3_match.gd CLOSE=1):
# (close-up file, its centre and radius as fractions of its width/height/width, the bubble's centre on the canvas,
# its diameter)
CALLOUTS = {
    "02_siege": ("play_battle_close", 0.52, 0.42, 0.40, (812, 1260), 430),
    "03_king": ("play_rescue_close", 0.48, 0.38, 0.38, (812, 1190), 450),
}


def load(raw, name):
    # a render, as .png (fresh from the tools) or .webp (as kept in store-listing/graphics/raw_renders)
    for ext in (".png", ".webp"):
        if os.path.exists(os.path.join(raw, name + ext)):
            return Image.open(os.path.join(raw, name + ext)).convert("RGB")
    return None


def font(path, px):
    return ImageFont.truetype(path, px)


def fit(img, w, h):
    # cover-crop to w x h (centred)
    s = max(w / img.width, h / img.height)
    r = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    x = (r.width - w) // 2
    y = (r.height - h) // 2
    return r.crop((x, y, x + w, y + h))


def gold_text(img, text, f, cx, y, stroke=11, shadow=10):
    d = ImageDraw.Draw(img)
    bb = f.getbbox(text, stroke_width=stroke)
    x = cx - (bb[2] - bb[0]) // 2 - bb[0]
    sh = Image.new("L", img.size, 0)
    ImageDraw.Draw(sh).text((x + 4, y + shadow), text, font=f, fill=210, stroke_width=stroke + 2, stroke_fill=210)
    img.paste((10, 4, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(9)))
    d.text((x, y), text, font=f, fill=(58, 26, 6), stroke_width=stroke, stroke_fill=(58, 26, 6))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text((x, y), text, font=f, fill=255)
    grad = Image.new("RGB", img.size)
    gd = ImageDraw.Draw(grad)
    top, bot = y + bb[1], y + bb[3]
    for yy in range(max(0, top - 2), min(img.height, bot + 2)):
        t = (yy - top) / max(1, bot - top)
        if t < 0.5:   # bright cream to gold, then a deeper orange-gold at the foot
            k = t / 0.5
            c = (255, int(250 - 40 * k), int(200 - 120 * k))
        else:
            k = (t - 0.5) / 0.5
            c = (int(255 - 20 * k), int(210 - 70 * k), int(80 - 60 * k))
        gd.line([(0, yy), (img.width, yy)], fill=c)
    img.paste(grad, (0, 0), mask)
    return y + bb[3]


def pill_text(img, text, f, cx, y, accent):
    d = ImageDraw.Draw(img)
    bb = f.getbbox(text)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    pw, ph = tw + 64, th + 34
    x0 = cx - pw // 2
    sh = Image.new("L", img.size, 0)
    ImageDraw.Draw(sh).rounded_rectangle((x0 + 4, y + 10, x0 + pw + 4, y + ph + 10), radius=ph // 2, fill=170)
    img.paste((0, 0, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(10)))
    dark = tuple(int(c * 0.55) for c in accent)
    d.rounded_rectangle((x0, y, x0 + pw, y + ph), radius=ph // 2, fill=dark)
    d.rounded_rectangle((x0 + 4, y + 4, x0 + pw - 4, y + ph - 4), radius=ph // 2 - 4, fill=accent)
    d.rounded_rectangle((x0, y, x0 + pw, y + ph), radius=ph // 2, outline=(255, 226, 150), width=4)
    d.text((cx - tw // 2 - bb[0], y + 17 - bb[1]), text, font=f, fill=(255, 255, 255), stroke_width=3, stroke_fill=dark)
    return y + ph


def wrap_fit(text, f_path, px, max_w):
    # shrink the subline's font until it fits on one line (two if it must)
    while px > 30:
        f = font(f_path, px)
        bb = f.getbbox(text)
        if bb[2] - bb[0] <= max_w:
            return f, [text]
        px -= 2
    return font(f_path, 30), [text]


def caption(img, lines, sub, accent, top=70):
    fh = font(F_HEAD, 128)
    for ln in lines:      # headline lines share one size: the widest decides
        while fh.getbbox(ln, stroke_width=11)[2] - fh.getbbox(ln, stroke_width=11)[0] > W - 90:
            fh = font(F_HEAD, fh.size - 4)
    y = top
    for ln in lines:
        y = gold_text(img, ln, fh, W // 2, y) + 6
    fs, _ = wrap_fit(sub, F_SUB, 44, W - 170)
    return pill_text(img, sub, fs, W // 2, y + 22, accent)


def shade_top(img, h, a0=0.86):
    # a dark band down from the top edge, for the caption
    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)
    for yy in range(h):
        md.line([(0, yy), (W, yy)], fill=int(255 * a0 * (1 - yy / h) ** 1.6))
    img.paste((6, 6, 16), (0, 0), mask)


def vignette(img, strength=0.55):
    m = Image.new("L", (W // 8, H // 8), 0)
    md = ImageDraw.Draw(m)
    for i in range(40):
        k = i / 40
        md.ellipse((-W // 8 * 0.35 + i * 1.6, -H // 8 * 0.25 + i * 2.6, W // 8 * 1.35 - i * 1.6, H // 8 * 1.25 - i * 2.6), fill=int(255 * k))
    m = m.resize(img.size, Image.BILINEAR).filter(ImageFilter.GaussianBlur(30))
    dark = Image.new("RGB", img.size, (4, 4, 10))
    inv = m.point(lambda v: int((255 - v) * strength))
    img.paste(dark, (0, 0), inv)


def phone(img, screen, top, max_h, glow=(255, 190, 90)):
    sw = round(max_h * screen.width / screen.height)
    sh = max_h
    scr = screen.resize((sw, sh), Image.LANCZOS)
    bez = 22
    pw, ph = sw + bez * 2, sh + bez * 2
    x0 = (W - pw) // 2
    # glow and drop shadow behind the phone
    g = Image.new("L", img.size, 0)
    ImageDraw.Draw(g).rounded_rectangle((x0 - 30, top - 30, x0 + pw + 30, top + ph + 30), radius=90, fill=200)
    img.paste(glow, (0, 0), g.filter(ImageFilter.GaussianBlur(46)).point(lambda v: int(v * 0.55)))
    s2 = Image.new("L", img.size, 0)
    ImageDraw.Draw(s2).rounded_rectangle((x0 + 10, top + 24, x0 + pw + 10, top + ph + 24), radius=72, fill=220)
    img.paste((0, 0, 0), (0, 0), s2.filter(ImageFilter.GaussianBlur(20)))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((x0, top, x0 + pw, top + ph), radius=72, fill=(18, 20, 30))
    d.rounded_rectangle((x0 + 3, top + 3, x0 + pw - 3, top + ph - 3), radius=70, outline=(92, 98, 120), width=3)
    m = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=52, fill=255)
    img.paste(scr, (x0 + bez, top + bez), m)


def bubble(img, close, cx, cy, r, at, d, ring=(255, 214, 110)):
    # a round close-up, gold-ringed, with a soft shadow
    cw, ch = close.size
    box = (int(cx * cw - r * cw), int(cy * ch - r * cw), int(cx * cw + r * cw), int(cy * ch + r * cw))
    part = close.crop(box).resize((d, d), Image.LANCZOS)
    m = Image.new("L", (d, d), 0)
    ImageDraw.Draw(m).ellipse((0, 0, d - 1, d - 1), fill=255)
    x0, y0 = at[0] - d // 2, at[1] - d // 2
    sh = Image.new("L", img.size, 0)
    ImageDraw.Draw(sh).ellipse((x0 + 8, y0 + 20, x0 + d + 8, y0 + d + 20), fill=230)
    img.paste((0, 0, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(22)))
    gl = Image.new("L", img.size, 0)
    ImageDraw.Draw(gl).ellipse((x0 - 26, y0 - 26, x0 + d + 26, y0 + d + 26), fill=200)
    img.paste(ring, (0, 0), gl.filter(ImageFilter.GaussianBlur(26)).point(lambda v: int(v * 0.5)))
    img.paste(part, (x0, y0), m)
    dr = ImageDraw.Draw(img)
    dr.ellipse((x0 - 9, y0 - 9, x0 + d + 9, y0 + d + 9), outline=(58, 26, 6), width=6)
    dr.ellipse((x0 - 5, y0 - 5, x0 + d + 5, y0 + d + 5), outline=ring, width=10)
    dr.ellipse((x0 + 3, y0 + 3, x0 + d - 3, y0 + d - 3), outline=(255, 246, 210), width=3)


def backdrop(src):
    b = fit(src, W, H).filter(ImageFilter.GaussianBlur(22))
    dark = Image.new("RGB", (W, H), (8, 10, 28))
    return Image.blend(b, dark, 0.55)


def build_shot(raw, spec):
    name, kind, src, lines, sub, accent, bd = spec
    if kind == "full":
        img = fit(load(raw, src), W, H)
        vignette(img, 0.5)
        shade_top(img, 760)
        caption(img, lines, sub, accent)
    else:
        img = backdrop(load(raw, bd))
        shade_top(img, 600, 0.6)
        y = caption(img, lines, sub, accent)
        top = y + 46
        phone(img, load(raw, src), top, H - top - 70)
        co = CALLOUTS.get(name)
        if co and load(raw, co[0]) is not None:
            bubble(img, load(raw, co[0]), co[1], co[2], co[3], co[4], co[5])
    return img


def logo_image():
    # the All Tied Up title with its King, as Home shows it at rest
    lg = Image.open(LOGO_SRC).convert("RGBA")
    return lg


def build_feature(raw):
    fw, fh = 1024, 500
    img = fit(load(raw, "feature"), fw * 2, fh * 2)
    # darken the left for the logo
    m = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(m)
    for x in range(img.width):
        t = x / img.width
        md.line([(x, 0), (x, img.height)], fill=int(255 * max(0.0, 0.62 - t) / 0.62 * 0.8))
    img.paste((6, 6, 18), (0, 0), m)
    lg = logo_image()
    lw = int(img.width * 0.54)
    lg = lg.resize((lw, round(lg.height * lw / lg.width)), Image.LANCZOS)
    sh = Image.new("L", img.size, 0)
    lx, ly = 40, (img.height - lg.height) // 2 - 20
    sh.paste(lg.split()[3], (lx + 8, ly + 16))
    img.paste((0, 0, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.7)))
    img.paste(lg, (lx, ly), lg)
    return img.resize((fw, fh), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for spec in SHOTS:
        if a.only and a.only not in spec[0]:
            continue
        if load(a.raw, spec[2]) is None:
            print("skip", spec[0], "(no", spec[2] + ")")
            continue
        img = build_shot(a.raw, spec)
        img.save(os.path.join(a.out, spec[0] + ".png"), optimize=True)
        print("wrote", spec[0])
    if (not a.only or a.only == "feature") and load(a.raw, "feature") is not None:
        build_feature(a.raw).save(os.path.join(a.out, "feature_graphic_1024x500.png"), optimize=True)
        print("wrote feature graphic")


if __name__ == "__main__":
    main()
