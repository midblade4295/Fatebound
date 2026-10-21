#!/usr/bin/env python3
"""0.31.200 (Kevin: "Need all new pics for app stores"): the store images, from real renders of the game.

Raw renders (tools/store4_match.gd, tools/store4_app.gd) in --raw:
  <key>_play.png    1080 x 1920 portrait (a 16:9 phone: the Play screenshots' own shape)
  <key>_phone.png   1080 x 2340 portrait (a 19.5:9 phone, an iPhone's)
  <key>_ipad.png    1536 x 2048 portrait (the iPad's 3:4)
  feature.png       2048 x 1000 (a wide battle, no HUD)
Out (--out):
  play/NN_<key>.png      Google Play phone screenshots, 1080 x 1920
  iphone/NN_<key>.png    App Store iPhone 6.9", 1320 x 2868
  ipad/NN_<key>.png      App Store iPad 13", 2048 x 2732
  feature_graphic_1024x500.png   Google Play feature graphic
Each screenshot: the render on a phone (or tablet) over a blurred, darkened copy of itself, a headline and a line
over it. Headlines in Lilita One (the game's titles), lines in Nunito ExtraBold; white and pale blue -- no yellow
text (Kevin, 0.31.195). The fire-and-ice bar under each headline and the feature graphic's title are the game's logo
(assets/ui/v2/title_rift_base.webp and its flags).

    python3 tools/store4_compose.py --raw RAW --out OUT [--only key,key]
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
TITLE_FONT = os.path.join(GODOT, "assets", "fonts", "LilitaOne-Regular.ttf")
BODY_FONT = os.path.join(GODOT, "store-listing", "tools", "fonts", "Nunito-ExtraBold.ttf")
LOGO = os.path.join(GODOT, "assets", "ui", "v2")

# (key, headline, line) in store order -- every claim checked against the game's code (0.31.199):
#  fight: 5v5 online (siege_server) or offline against bots; champions: moba.gd HERO_ORDER (18) and moba_kits ROLE_OF's
#  six roles; wyrm: the Grave Wyrm and the Bone Lord (moba.gd camps), buff camps; king: the King falls -> the match is
#  won (moba.gd hit_king); outfit: economy.gd OUTFITS (18) + SKIN_LINES Frostbound (18) = 36; clan: clans (economy.gd
#  clans: camp stages, Clan Chest, Clan League); home: social.gd PARTY_MAX 5; tutorial: tutorial.gd, voiced; chest:
#  a chest's gold, gems and a chance of a hero shard (economy.gd CHESTS).
SHOTS = [
    ("teamfight", "5V5 HERO BATTLES", "Team up and take the Rift, online or against bots"),
    ("champion", "18 CHAMPIONS", "Tanks, fighters, assassins, mages, marksmen and supports"),
    ("king", "TOPPLE THEIR KING", "Push the lanes, break the towers, take the throne"),
    ("wyrm", "SLAY THE GRAVE WYRM", "Epic monsters, jungle camps and buffs that turn the fight"),
    ("outfit", "36 OUTFITS", "A set made for every champion, plus the Frostbound line"),
    ("clan", "BUILD YOUR CLAN", "A camp that grows, a weekly Clan Chest and the Clan League"),
    ("home", "SQUAD UP", "Parties of five with friends and clanmates"),
    ("tutorial", "LEARN FROM THE HERALD", "A funny, fully voiced tutorial gets you battle-ready"),
    # (Google Play takes 8; the App Store 10 -- the chest only there)
    ("chest", "OPEN CHESTS", "Gold, gems and hero shards", ("iphone", "ipad")),
]

TARGETS = {
    # canvas, raw suffix, headline px, line px, top margin, device area (x0, y0, x1, y1), bezel, corner radius
    "play": {"size": (1080, 1920), "raw": "play", "h": 92, "l": 40, "top": 70, "area": (0, 390, 1080, 1890), "bezel": 14, "r": 44},
    "iphone": {"size": (1320, 2868), "raw": "phone", "h": 120, "l": 54, "top": 124, "area": (0, 575, 1320, 2810), "bezel": 18, "r": 60},
    "ipad": {"size": (2048, 2732), "raw": "ipad", "h": 150, "l": 64, "top": 110, "area": (0, 560, 2048, 2680), "bezel": 24, "r": 56},
}

ICE = (90, 170, 255)
FIRE = (255, 120, 40)
INK = (8, 14, 30)
LINE = (205, 228, 255)


def font(path, px):
    return ImageFont.truetype(path, px)


def cover(im, size):
    w, h = size
    k = max(w / im.width, h / im.height)
    r = im.resize((int(im.width * k + 0.5), int(im.height * k + 0.5)), Image.LANCZOS)
    x = (r.width - w) // 2
    y = (r.height - h) // 2
    return r.crop((x, y, x + w, y + h))


def backdrop(raw, size):
    bg = cover(raw, size).filter(ImageFilter.GaussianBlur(max(size) // 40))
    dark = Image.new("RGB", size, INK)
    bg = Image.blend(bg, dark, 0.62)
    # a deeper shade at the top, under the words
    shade = Image.new("L", size, 0)
    d = ImageDraw.Draw(shade)
    for y in range(size[1] // 3):
        d.line([(0, y), (size[0], y)], fill=int(150 * (1 - y / (size[1] / 3))))
    return Image.composite(dark, bg, shade)


def rounded_mask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), r, fill=255)
    return m


def wrap(text, f, width, draw):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=f) <= width or cur == "":
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def fire_ice_bar(w, h):
    bar = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(bar)
    for x in range(w):
        t = x / max(1, w - 1)
        c = tuple(int(ICE[i] + (FIRE[i] - ICE[i]) * t) for i in range(3))
        d.line([(x, 0), (x, h)], fill=c)
    m = rounded_mask((w, h), h // 2)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(bar, (0, 0), m)
    return out


def compose(raw, target, headline, line):
    t = TARGETS[target]
    W, H = t["size"]
    canvas = backdrop(raw, (W, H)).convert("RGBA")
    d = ImageDraw.Draw(canvas)
    # the headline, the bar, the line
    hf = font(TITLE_FONT, t["h"])
    lf = font(BODY_FONT, t["l"])
    y = t["top"]
    for ln in wrap(headline, hf, W * 0.9, d):
        tw = d.textlength(ln, font=hf)
        sh = Image.new("RGBA", (W, int(t["h"] * 1.4)), (0, 0, 0, 0))
        ImageDraw.Draw(sh).text(((W - tw) / 2, 6), ln, font=hf, fill=(0, 0, 0, 170))
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(t["h"] // 12)), (0, y + t["h"] // 16))
        d.text(((W - tw) / 2, y), ln, font=hf, fill=(255, 255, 255), stroke_width=max(3, t["h"] // 22), stroke_fill=INK)
        y += int(t["h"] * 1.05)
    bw = int(min(W * 0.34, t["h"] * 4.2))
    bh = max(6, t["h"] // 12)
    canvas.alpha_composite(fire_ice_bar(bw, bh), ((W - bw) // 2, y + bh))
    y += bh * 3 + t["l"] // 3
    for ln in wrap(line, lf, W * 0.86, d):
        tw = d.textlength(ln, font=lf)
        d.text(((W - tw) / 2, y), ln, font=lf, fill=LINE, stroke_width=2, stroke_fill=INK)
        y += int(t["l"] * 1.25)
    # the device: the render with rounded corners in a dark bezel, a soft glow behind
    ax0, ay0, ax1, ay1 = t["area"]
    ay0 = max(ay0, y + t["l"] // 2)
    bz = t["bezel"]
    aw, ah = ax1 - ax0, ay1 - ay0
    k = min((aw * 0.92 - 2 * bz) / raw.width, (ah - 2 * bz) / raw.height)
    sw, sh2 = int(raw.width * k), int(raw.height * k)
    shot = raw.resize((sw, sh2), Image.LANCZOS).convert("RGBA")
    dw, dh = sw + 2 * bz, sh2 + 2 * bz
    dx, dy = (W - dw) // 2, ay0 + (ah - dh) // 2
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle((dx - 6, dy - 6, dx + dw + 6, dy + dh + 6), t["r"] + 8, fill=(120, 170, 255, 120))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(28)))
    body = Image.new("RGBA", (dw, dh), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, dw - 1, dh - 1), t["r"], fill=(10, 12, 20, 255), outline=(70, 80, 105, 255), width=3)
    canvas.alpha_composite(body, (dx, dy))
    inner_r = max(8, t["r"] - bz)
    canvas.paste(shot, (dx + bz, dy + bz), rounded_mask((sw, sh2), inner_r))
    return canvas.convert("RGB")


def logo():
    base = Image.open(os.path.join(LOGO, "title_rift_base.webp")).convert("RGBA")
    out = Image.new("RGBA", base.size, (0, 0, 0, 0))
    out.alpha_composite(Image.open(os.path.join(LOGO, "title_flag_l.webp")).convert("RGBA"), (0, 153))
    out.alpha_composite(Image.open(os.path.join(LOGO, "title_flag_r.webp")).convert("RGBA"), (1233, 153))
    out.alpha_composite(base)
    return out


def feature(raw):
    W, H = 1024, 500
    bg = cover(raw, (W, H)).convert("RGBA")
    # darker round the title, the battle bright at the sides
    shade = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shade).ellipse((W * 0.12, -H * 0.15, W * 0.88, H * 0.95), fill=165)
    shade = shade.filter(ImageFilter.GaussianBlur(70))
    bg = Image.composite(Image.new("RGBA", (W, H), INK + (255,)), bg, shade)
    lg = logo()
    lw = 640
    lg = lg.resize((lw, int(lg.height * lw / lg.width)), Image.LANCZOS)
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", lg.size, (0, 0, 0)).split(), lg.split()[3].point(lambda a: a * 0.7))),
                       ((W - lw) // 2, 54))
    bg.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)))
    bg.alpha_composite(lg, ((W - lw) // 2, 40))
    d = ImageDraw.Draw(bg)
    f = font(TITLE_FONT, 40)
    txt = "5V5 HERO BATTLES"
    tw = d.textlength(txt, font=f)
    y = 40 + lg.height + 10
    d.text(((W - tw) / 2, y), txt, font=f, fill=(255, 255, 255), stroke_width=3, stroke_fill=INK)
    return bg.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s]
    n = 0
    for shot in SHOTS:
        key, head, line = shot[0], shot[1], shot[2]
        targets = shot[3] if len(shot) > 3 else tuple(TARGETS)
        n += 1
        if only and key not in only:
            continue
        for target in targets:
            src = os.path.join(a.raw, "%s_%s.png" % (key, TARGETS[target]["raw"]))
            if not os.path.exists(src):
                print("missing", src)
                continue
            os.makedirs(os.path.join(a.out, target), exist_ok=True)
            im = compose(Image.open(src).convert("RGB"), target, head, line)
            assert im.size == TARGETS[target]["size"]
            dst = os.path.join(a.out, target, "%02d_%s.png" % (n, key))
            im.save(dst, optimize=True)
            print(dst, im.size)
    fr = os.path.join(a.raw, "feature.png")
    if os.path.exists(fr) and (not only or "feature" in only):
        im = feature(Image.open(fr).convert("RGB"))
        im.save(os.path.join(a.out, "feature_graphic_1024x500.png"), optimize=True)
        print("feature", im.size)


if __name__ == "__main__":
    main()
