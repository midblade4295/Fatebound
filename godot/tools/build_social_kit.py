#!/usr/bin/env python3
"""The social media kit (after 0.31.200, Kevin: "Give me social media package that has banner and icon").

From art_sources/social/key_art.png (16:9 painted key art, 2048 x 1152: the icon's Knight and Barbarian clashing in the
middle over the ice-and-fire rift, a gold crown over them, their teams and castles either side) and
art_sources/app_icon/icon.png (the game's icon), with the title logo (assets/ui/v2/title_rift_base.webp and its flags):

  banners/  x_header_1500x500, youtube_banner_2560x1440, facebook_cover_1640x624, twitch_banner_1200x480,
            discord_server_banner_960x540, discord_profile_banner_680x240, share_card_1200x630 (link previews),
            key_art_1920x1080 (with the title and the tagline), key_art_clean_1920x1080 (the art as painted)
  icons/    avatar_<n>.png (1080, 800, 512, 400, 256: the icon, square; every site's round crop keeps the crown, both
            faces and the clash), icon_square_1024.png, logo_transparent_1400.png and logo_transparent_700.png (the
            title, see-through)
  preview.jpg  all of them on one sheet

The banners with the title put it top centre, its rift on the art's rift, where the art's crown was: the title has its
own crown, so the art's is painted out first (uncrown(): the sky either side copied over it, the rift drawn back through).
Below the title the clash and both faces stay in what every device shows. On YouTube only the middle 1546 x 423 shows on
every device (computers show that strip's full width, TVs all 2560 x 1440), so there the art is drawn smaller in that
strip, over a blurred, darker copy of itself filling the rest. No yellow text (Kevin, 0.31.195): the tagline is white over the logo's fire-and-ice bar.

    cd godot && python3 tools/build_social_kit.py --out store-listing/social
"""
import argparse
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
ROOT = os.path.dirname(GODOT)
KEY_ART = os.path.join(ROOT, "art_sources", "social", "key_art.png")
ICON = os.path.join(ROOT, "art_sources", "app_icon", "icon.png")
V2 = os.path.join(GODOT, "assets", "ui", "v2")
TITLE_FONT = os.path.join(GODOT, "assets", "fonts", "LilitaOne-Regular.ttf")
INK = (8, 14, 30)
ICE = (90, 170, 255)
FIRE = (255, 120, 40)
LINE = "5V5 HERO BATTLES"

ART_RIFT = 0.522            # the art's rift (x, a fraction of its width) where the title goes
LOGO_RIFT = 0.479           # the title's own rift, between FATE and BOUND
LOGO_ASPECT = 1400 / 632

# The art's crown at 2048 x 1152 (a loose outline: the sky between its spikes goes too) and the rift behind it
CROWN = [(882, 170), (972, 175), (1057, 128), (1152, 175), (1232, 170), (1210, 300), (1190, 340), (1178, 380),
         (1057, 392), (932, 384), (920, 340), (900, 300)]
CROWN_RIFT = ((1086, 112), (1060, 392))
SKY_LEFT = (-380, -40)      # where each side's fill comes from (dx, dy): the ice sky up to its left, the fire sky up to
SKY_RIGHT = (330, -70)      # its right (clear of the Barbarian's ears)

# name: size, then
#   view: the art's top edge as a fraction of its height (wide banners show a band of it; 16:9 ones all of it), or
#         ("band", top, bottom, (x0, y0, x1, y1)): the art drawn so its rows top..bottom fill the box, over a blurred,
#         darker copy of itself filling the rest
#   logo: (height, top) as fractions of the banner's height, or None (the art as painted, crown and all)
#   line: the tagline at the bottom
LAYOUT = {
    # X: the avatar covers the bottom left
    "x_header_1500x500": dict(size=(1500, 500), view=0.03, logo=(0.46, 0.06), line=False),
    # YouTube: only x 507-2053, y 508-931 shows on every device
    "youtube_banner_2560x1440": dict(size=(2560, 1440), view=("band", 0.035, 0.60, (507, 508, 2053, 931)),
                                     logo=(0.152, 0.360), line=False),
    # Facebook: phones show the middle ~68% of the width, all of the height
    "facebook_cover_1640x624": dict(size=(1640, 624), view=0.03, logo=(0.42, 0.06), line=False),
    "twitch_banner_1200x480": dict(size=(1200, 480), view=0.03, logo=(0.40, 0.06), line=False),
    # Discord shows the server banner small: a big title
    "discord_server_banner_960x540": dict(size=(960, 540), view=0.0, logo=(0.36, 0.05), line=False),
    "discord_profile_banner_680x240": dict(size=(680, 240), view=0.03, logo=(0.46, 0.06), line=False),
    "share_card_1200x630": dict(size=(1200, 630), view=0.0, logo=(0.36, 0.05), line=False),
    "key_art_1920x1080": dict(size=(1920, 1080), view=0.0, logo=(0.31, 0.05), line=True),
    "key_art_clean_1920x1080": dict(size=(1920, 1080), view=0.0, logo=None, line=False),
}
AVATARS = [1080, 800, 512, 400, 256]


def logo():
    base = Image.open(os.path.join(V2, "title_rift_base.webp")).convert("RGBA")
    out = Image.new("RGBA", base.size, (0, 0, 0, 0))
    out.alpha_composite(Image.open(os.path.join(V2, "title_flag_l.webp")).convert("RGBA"), (0, 153))
    out.alpha_composite(Image.open(os.path.join(V2, "title_flag_r.webp")).convert("RGBA"), (1233, 153))
    out.alpha_composite(base)
    return out


def uncrown(art):
    # paint the crown out: the ice sky from its left over its left part, the fire sky from its right over the rest, the
    # rift drawn back through between them
    assert art.size == (2048, 1152), art.size
    a = np.asarray(art).astype(np.float32)
    left = np.roll(a, (-SKY_LEFT[1], -SKY_LEFT[0]), axis=(0, 1))      # (pixel (x, y) shows (x + dx, y + dy))
    right = np.roll(a, (-SKY_RIGHT[1], -SKY_RIGHT[0]), axis=(0, 1))
    (rx0, ry0), (rx1, ry1) = CROWN_RIFT
    ys = np.arange(a.shape[0], dtype=np.float32)[:, None]
    xs = np.arange(a.shape[1], dtype=np.float32)[None, :]
    rx = rx0 + (rx1 - rx0) * np.clip((ys - ry0) / (ry1 - ry0), 0, 1)
    side = np.clip((xs - rx) / 6.0 + 0.5, 0, 1)[..., None]
    fill = left * (1 - side) + right * side
    m = Image.new("L", art.size, 0)
    ImageDraw.Draw(m).polygon(CROWN, fill=255)
    m = m.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(9))
    mk = (np.asarray(m).astype(np.float32) / 255.0)[..., None]
    out = a * (1 - mk) + fill * mk
    # the rift: a jagged bright line with a warm glow, faded in and out where it meets the real one
    rnd = random.Random(7)
    pts = []
    n = 26
    for i in range(n + 1):
        t = i / n
        y = ry0 + (ry1 - ry0) * t
        x = rx0 + (rx1 - rx0) * t + (rnd.uniform(-7, 7) if 0 < i < n else 0)
        pts.append((x, y))
    glow = Image.new("L", art.size, 0)
    core = Image.new("L", art.size, 0)
    ImageDraw.Draw(glow).line(pts, fill=255, width=16)
    ImageDraw.Draw(core).line(pts, fill=255, width=4)
    glow = np.asarray(glow.filter(ImageFilter.GaussianBlur(10))).astype(np.float32)[..., None] / 255.0
    core = np.asarray(core.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32)[..., None] / 255.0
    warm = np.array([255, 200, 120], np.float32)
    white = np.array([255, 250, 235], np.float32)
    out = out + (warm - out) * glow * 0.55 * mk
    out = out + (white - out) * core * mk
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def backdrop(im, W, H, x, y):
    # im placed at (x, y) on a W x H canvas over itself scaled up to fill the canvas, blurred and darkened, the edges
    # between them feathered
    k = max(W / im.width, H / im.height) * 1.05
    big = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)
    rift = x + ART_RIFT * im.width                      # (the two rifts line up)
    bx = int(round(rift - ART_RIFT * big.width))
    bx = max(min(bx, 0), W - big.width)
    by = (H - big.height) // 2
    bg = Image.new("RGB", (W, H))
    bg.paste(big, (bx, by))
    bg = np.asarray(bg.filter(ImageFilter.GaussianBlur(36))).astype(np.float32) * 0.45
    fg = np.zeros((H, W, 3), np.float32)
    x0, y0 = max(x, 0), max(y, 0)
    x1, y1 = min(x + im.width, W), min(y + im.height, H)
    fg[y0:y1, x0:x1] = np.asarray(im).astype(np.float32)[y0 - y:y1 - y, x0 - x:x1 - x]
    feather = 48.0
    yy = np.arange(H, dtype=np.float32)[:, None]
    xx = np.arange(W, dtype=np.float32)[None, :]
    inx = np.minimum(xx - x, x + im.width - xx)
    iny = np.minimum(yy - y, y + im.height - yy)
    m = (np.clip(inx / feather, 0, 1) * np.clip(iny / feather, 0, 1))[..., None]
    m = m * m * (3 - 2 * m)
    out = fg * m + bg * (1 - m)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def place(art, size, view):
    # the art on the banner: returns the canvas, the art's scale and its top-left on the canvas
    W, H = size
    if isinstance(view, tuple):
        _, top, bottom, (bx0, by0, bx1, by1) = view
        k = (by1 - by0) / ((bottom - top) * art.height)
        aw, ah = int(round(art.width * k)), int(round(art.height * k))
        x = int(round((bx0 + bx1) / 2 - ART_RIFT * aw))
        y = int(round(by0 - top * ah))
        return backdrop(art.resize((aw, ah), Image.LANCZOS), W, H, x, y), k, x, y
    k = max(W / art.width, H / art.height)
    aw, ah = int(round(art.width * k)), int(round(art.height * k))
    x = (W - aw) // 2
    y = -int(round(view * ah))
    y = max(min(y, 0), H - ah)
    c = Image.new("RGB", size)
    c.paste(art.resize((aw, ah), Image.LANCZOS), (x, y))
    return c, k, x, y


def shade(c, box, alpha, spread):
    # a soft dark pool behind the title (or the tagline) so it reads over the bright sky
    x0, y0, x1, y1 = box
    m = Image.new("L", c.size, 0)
    ImageDraw.Draw(m).ellipse((x0, y0, x1, y1), fill=alpha)
    m = m.filter(ImageFilter.GaussianBlur(spread))
    return Image.composite(Image.new("RGBA", c.size, INK + (255,)), c, m)


def put_logo(c, lg, cx_rift, top, lh):
    lw = int(round(lh * LOGO_ASPECT))
    t = lg.resize((lw, int(round(lh))), Image.LANCZOS)
    x = int(round(cx_rift - LOGO_RIFT * lw))
    y = int(round(top))
    c = shade(c, (x + lw * 0.08, y + lh * 0.18, x + lw * 0.92, y + lh * 1.02), 120, max(4, lh * 0.22))
    sh = Image.new("RGBA", c.size, (0, 0, 0, 0))
    a = t.split()[3].point(lambda v: int(v * 0.8))
    sh.paste(Image.merge("RGBA", (*Image.new("RGB", t.size, (0, 0, 0)).split(), a)), (x, y + max(3, lw // 70)))
    c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(max(3, lw // 80))))
    c.alpha_composite(t, (x, y))
    return c


def fire_ice_bar(w, h):
    bar = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(bar)
    for x in range(w):
        t = x / max(1, w - 1)
        d.line([(x, 0), (x, h)], fill=tuple(int(ICE[i] + (FIRE[i] - ICE[i]) * t) for i in range(3)))
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), h // 2, fill=255)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(bar, (0, 0), m)
    return out


def put_line(c, cx, H):
    # the tagline at the bottom: white, ink-stroked, over the fire-and-ice bar
    px = int(H * 0.058)
    f = ImageFont.truetype(TITLE_FONT, px)
    d = ImageDraw.Draw(c)
    tw = d.textlength(LINE, font=f)
    ty = int(H * 0.885)
    c = shade(c, (cx - tw * 0.75, ty - px * 0.6, cx + tw * 0.75, ty + px * 1.9), 150, px * 0.6)
    d = ImageDraw.Draw(c)
    d.text((cx - tw / 2, ty), LINE, font=f, fill=(255, 255, 255), stroke_width=max(2, px // 12), stroke_fill=INK)
    bw, bh = int(tw * 0.8), max(4, px // 8)
    c.alpha_composite(fire_ice_bar(bw, bh), (int(cx - bw / 2), int(ty + px * 1.22)))
    return c


def banner(art, bare, lg, spec):
    W, H = spec["size"]
    if spec["logo"] is None:
        c, _, _, _ = place(art, spec["size"], spec["view"])
        return c
    c, k, x, _ = place(bare, spec["size"], spec["view"])
    c = c.convert("RGBA")
    rift = x + ART_RIFT * bare.width * k
    lh, top = spec["logo"]
    c = put_logo(c, lg, rift, top * H, lh * H)
    if spec["line"]:
        c = put_line(c, rift, H)
    return c.convert("RGB")


def avatar(icon, n):
    # the icon as it is: it was drawn for round masks (Android's), so a round crop keeps the crown, both faces and the
    # clash
    return icon.resize((n, n), Image.LANCZOS)


def preview(out):
    # preview.jpg: every banner and the round avatar on one sheet, each named
    W, pad, lab = 1600, 24, 34
    f = ImageFont.truetype(TITLE_FONT, 26)
    bd = os.path.join(out, "banners")

    def tile(name, w):
        im = Image.open(os.path.join(bd, name + ".png"))
        im = im.resize((w, int(round(im.height * w / im.width))), Image.LANCZOS)
        if name.startswith("youtube"):                  # (the strip every device shows)
            k = w / 2560
            ImageDraw.Draw(im).rectangle((507 * k, 508 * k, 2053 * k, 931 * k), outline=(255, 255, 255), width=2)
        return name, im

    half = (W - pad) // 2
    rows = [[tile("key_art_1920x1080", W)], [tile("x_header_1500x500", W)], [tile("facebook_cover_1640x624", W)],
            [tile("twitch_banner_1200x480", half), tile("discord_profile_banner_680x240", half)],
            [tile("discord_server_banner_960x540", half), tile("share_card_1200x630", half)],
            [tile("youtube_banner_2560x1440", half), tile("key_art_clean_1920x1080", half)]]
    ic = Image.open(os.path.join(out, "icons", "avatar_512.png")).resize((300, 300), Image.LANCZOS)
    m = Image.new("L", ic.size, 0)
    ImageDraw.Draw(m).ellipse((0, 0, 299, 299), fill=255)
    lg = Image.open(os.path.join(out, "icons", "logo_transparent_700.png"))
    H = pad + sum(lab + max(t[1].height for t in r) + pad for r in rows) + lab + 300 + pad
    sheet = Image.new("RGB", (W + 2 * pad, H), (18, 22, 34))
    d = ImageDraw.Draw(sheet)
    y = pad
    for r in rows:
        x = pad
        for name, im in r:
            d.text((x, y), name + ".png", font=f, fill=(255, 255, 255))
            sheet.paste(im, (x, y + lab))
            x += im.width + pad
        y += lab + max(t[1].height for t in r) + pad
    d.text((pad, y), "avatar (as sites crop it)  -  logo_transparent", font=f, fill=(255, 255, 255))
    sheet.paste(ic, (pad, y + lab), m)
    lgs = lg.resize((int(lg.width * 300 / lg.height), 300), Image.LANCZOS)
    sheet.paste(lgs, (pad + 340, y + lab), lgs)
    sheet.save(os.path.join(out, "preview.jpg"), quality=88)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="", help="comma-separated banner names")
    a = ap.parse_args()
    art = Image.open(KEY_ART).convert("RGB")
    bare = uncrown(art)
    icon = Image.open(ICON).convert("RGB")
    lg = logo()
    bd = os.path.join(a.out, "banners")
    idir = os.path.join(a.out, "icons")
    os.makedirs(bd, exist_ok=True)
    os.makedirs(idir, exist_ok=True)
    only = [s for s in a.only.split(",") if s]
    for name, spec in LAYOUT.items():
        if only and name not in only:
            continue
        im = banner(art, bare, lg, spec)
        assert im.size == spec["size"] and im.mode == "RGB"
        im.save(os.path.join(bd, name + ".png"), optimize=True)
        print(name, im.size)
    if only:
        return
    for n in AVATARS:
        avatar(icon, n).save(os.path.join(idir, "avatar_%d.png" % n), optimize=True)
    icon.resize((1024, 1024), Image.LANCZOS).save(os.path.join(idir, "icon_square_1024.png"), optimize=True)
    for w in (1400, 700):
        lg.resize((w, int(round(lg.height * w / lg.width))), Image.LANCZOS).save(
            os.path.join(idir, "logo_transparent_%d.png" % w), optimize=True)
    print("icons", AVATARS)
    preview(a.out)
    print("preview.jpg")


if __name__ == "__main__":
    main()
