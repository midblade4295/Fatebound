#!/usr/bin/env python3
"""0.31.212 (Kevin: "Now I want new higher quality app store screenshots. Here is the app store page for clash Royale for
reference"): landscape store screenshots in Clash Royale's manner -- a hero big on the left, in 3D (the HD models,
tools/meshy_hd.py, rendered by tools/render_app_icon.gd), a two-line headline in the corner below him, and on the right
the real game on a phone-shaped card (the raw renders of tools/store4_match.gd / store4_app.gd, as they are: the HUD
and screens untouched), over the game's own world blurred (landscape renders of store4_match.gd, CINE=1) and tinted,
with a light behind the hero (the team colours' confetti: off, Kevin asked). The first is the key art: the heroes together and the
title, no phone.

In (--art): store_<hero>_wide.png or .webp (render_app_icon.gd's store_* shots, square, RGBA) for each SHOTS hero;
--raw: <key>_play.webp (1080 x 1920, store-listing/graphics/raw_renders); --bg: <scene>.png or .webp (2868 x 1320
landscape, store4_match.gd CINE=1). The ones used are kept in store-listing/graphics/raw_renders/store5 (art and bg).
Out (--out):
  play/NN_<key>.jpg     Google Play phone screenshots, 2560 x 1440 (16:9)
  iphone/NN_<key>.jpg   App Store iPhone 6.9", 2868 x 1320 landscape
  ipad/NN_<key>.jpg     App Store iPad 13", 2732 x 2048 landscape
Headlines in Lilita One (the game's titles), white with a dark outline and drop shadow -- no yellow text (Kevin,
0.31.195).

    python3 tools/store5_compose.py --art ART --raw RAW --bg BG --out OUT [--only key,key]
"""
import argparse
import math
import os
import random

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
TITLE_FONT = os.path.join(GODOT, "assets", "fonts", "LilitaOne-Regular.ttf")
LOGO = os.path.join(GODOT, "assets", "ui", "v2")

TARGETS = {"play": (2560, 1440), "iphone": (2868, 1320), "ipad": (2732, 2048)}

# key, the raw render on the phone ("" none), the backdrop scene, its tint, the glow behind the hero, the confetti,
# the headline's two lines (Kevin, 0.31.212: "Can you remove the confetti" -- off on every shot; confetti() kept), and
# the heroes: [render, x, y, height] -- the render's middle at (x, y), its full square
# `height` tall, all in units of the canvas height (x from the left edge; on wider canvases the hero keeps to the left
# and the phone to the right). Every claim checked against the game's code (0.31.211):
#  teamfight: 5v5 online (siege_server) or offline against bots; champions: Champions.ORDER (18); king: the King falls
#  -> the match is won (moba.gd hit_king); wyrm: the Grave Wyrm (moba.gd camps); outfits: economy.gd OUTFITS (18) +
#  SKIN_LINES Frostbound (18) = 36; clan: clans (camp, Clan Chest, Clan League); squad: social.gd PARTY_MAX 5.
SHOTS = [
    {"key": "keyart", "raw": "", "bg": "feature", "tint": (40, 90, 200), "glow": (120, 190, 255), "confetti": False,
     "lines": ("", ""), "logo": True,
     "heroes": [["king", 1.085, 0.47, 1.08], ["dragoon", 1.47, 0.36, 0.95], ["knight", 0.74, 0.55, 1.05],
                ["barbarian", 0.36, 0.57, 1.1], ["stormcaller", 1.8, 0.56, 1.12]]},
    {"key": "teamfight", "raw": "teamfight", "bg": "feature", "tint": (30, 90, 220), "glow": (130, 200, 255),
     "confetti": False, "lines": ("TEAM UP FOR", "5V5 HERO BATTLES"),
     "heroes": [["stormcaller", 0.56, 0.57, 1.55]]},
    {"key": "champions", "raw": "champion", "bg": "tower", "tint": (230, 150, 40), "glow": (255, 220, 140),
     "confetti": False, "lines": ("PICK FROM", "18 CHAMPIONS"),
     "heroes": [["barbarian", 0.33, 0.55, 1.28], ["mage", 1.08, 0.53, 1.28], ["knight", 0.67, 0.59, 1.32]]},
    {"key": "king", "raw": "king", "bg": "king", "tint": (120, 60, 200), "glow": (255, 220, 150), "confetti": False,
     "lines": ("PUSH THE LANES AND", "TOPPLE THEIR KING"),
     "heroes": [["king", 0.55, 0.52, 1.5]]},
    {"key": "wyrm", "raw": "wyrm", "bg": "wyrm", "tint": (20, 160, 140), "glow": (150, 255, 220), "confetti": False,
     "lines": ("SLAY THE", "GRAVE WYRM"),
     "heroes": [["dragoon", 0.66, 0.5, 1.8]]},
    {"key": "outfit", "raw": "outfit", "bg": "tower", "tint": (200, 60, 120), "glow": (255, 170, 210), "confetti": False,
     "lines": ("DRESS UP IN", "36 OUTFITS"),
     "heroes": [["mage", 0.55, 0.5, 1.45]]},
    {"key": "clan", "raw": "clan", "bg": "king", "tint": (200, 110, 40), "glow": (255, 200, 130), "confetti": False,
     "lines": ("BUILD", "YOUR CLAN"),
     "heroes": [["barbarian", 0.55, 0.5, 1.45]]},
    {"key": "squad", "raw": "home", "bg": "feature", "tint": (40, 140, 90), "glow": (170, 255, 190), "confetti": False,
     "lines": ("SQUAD UP", "WITH FRIENDS"),
     "heroes": [["knight", 0.55, 0.52, 1.45]]},
]

INK = (10, 16, 34)
# the heroes rendered from their left (render_app_icon.gd store_dragoon: his halberd in view), mirrored here so they
# too look across to the phone
MIRRORED = {"dragoon"}
CONFETTI = [(235, 70, 60), (60, 140, 235), (245, 195, 70), (255, 255, 255)]


def font(px):
    return ImageFont.truetype(TITLE_FONT, px)


def cover(im, size):
    w, h = size
    k = max(w / im.width, h / im.height)
    r = im.resize((int(im.width * k + 0.5), int(im.height * k + 0.5)), Image.LANCZOS)
    x = (r.width - w) // 2
    y = (r.height - h) // 2
    return r.crop((x, y, x + w, y + h))


def backdrop(scene, size, tint, glow, glow_at):
    """The game's world, blurred out of focus, tinted toward the shot's colour, a light behind the hero, darker
    corners."""
    w, h = size
    b = cover(scene.convert("RGB"), size).filter(ImageFilter.GaussianBlur(h / 55))
    b = ImageEnhance.Color(b).enhance(1.25)
    a = np.asarray(b, np.float32)
    t = np.array(tint, np.float32)
    a = a * 0.42 + t * 0.58 * (a.mean(-1, keepdims=True) / 130.0)          # (tinted, keeping the light and dark)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    gx, gy = glow_at
    d = np.sqrt(((x - gx) / h) ** 2 + ((y - gy) / h) ** 2)
    a += np.array(glow, np.float32) * (np.clip(1.0 - d / 0.75, 0, 1) ** 2 * 0.55)[..., None]
    v = np.sqrt(((x - w / 2) / (w * 0.75)) ** 2 + ((y - h * 0.45) / (h * 0.85)) ** 2)
    a *= (1.0 - 0.45 * np.clip(v, 0, 1.3) ** 2)[..., None]
    a += np.random.default_rng(3).normal(0, 1.2, a.shape)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def confetti(size, seed, n, avoid, near_band=None):
    """Paper confetti in the team colours and gold: small twisted rectangles, some near and out of focus."""
    w, h = size
    rnd = random.Random(seed)
    far = Image.new("RGBA", size, (0, 0, 0, 0))
    near = Image.new("RGBA", size, (0, 0, 0, 0))
    for i in range(n):
        x = rnd.uniform(0, w)
        y = rnd.uniform(0, h * 0.8)
        if avoid[0] <= x <= avoid[2] and avoid[1] <= y <= avoid[3]:
            continue
        s = h * rnd.uniform(0.012, 0.03)
        # (the near, out-of-focus ones only in near_band, the strip between the hero and the phone: never on a face)
        big = rnd.random() < 0.3 and near_band is not None and near_band[0] <= x <= near_band[1]
        if big:
            s *= 2.2
        c = rnd.choice(CONFETTI)
        pw, ph = s * rnd.uniform(1.2, 2.2), s * rnd.uniform(0.45, 0.8) * abs(math.cos(rnd.uniform(0, 3.14))) + s * 0.15
        piece = Image.new("RGBA", (int(pw * 1.6) + 4, int(pw * 1.6) + 4), (0, 0, 0, 0))
        d = ImageDraw.Draw(piece)
        cx, cy = piece.width / 2, piece.height / 2
        shade = tuple(int(v * rnd.uniform(0.75, 1.0)) for v in c)
        d.rounded_rectangle((cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2), radius=ph * 0.25, fill=shade + (255,))
        piece = piece.rotate(rnd.uniform(0, 360), resample=Image.BICUBIC, expand=False)
        layer = near if big else far
        layer.alpha_composite(piece, (int(x - piece.width / 2), int(y - piece.height / 2)))
    near = near.filter(ImageFilter.GaussianBlur(h / 260))
    return far, near


def rounded_mask(size, r, scale=4):
    m = Image.new("L", (size[0] * scale, size[1] * scale), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] * scale - 1, size[1] * scale - 1), radius=r * scale, fill=255)
    return m.resize(size, Image.LANCZOS)


def phone(raw, h, glow):
    """The game's screen on a phone-shaped card: rounded, a light rim, glowing in the shot's colour, a soft shadow."""
    ph = int(h)
    pw = int(round(ph * raw.width / raw.height))
    r = int(ph * 0.045)
    rim = max(4, int(ph * 0.008))
    pad = int(ph * 0.08)
    out = Image.new("RGBA", (pw + 2 * pad, ph + 2 * pad), (0, 0, 0, 0))
    # glow and shadow
    m = Image.new("L", out.size, 0)
    m.paste(rounded_mask((pw + 2 * rim, ph + 2 * rim), r + rim), (pad - rim, pad - rim))
    g = Image.new("RGBA", out.size, glow + (0,))
    g.putalpha(m.filter(ImageFilter.GaussianBlur(ph * 0.03)).point(lambda v: int(v * 0.95)))
    sh = Image.new("RGBA", out.size, (0, 0, 0, 0))
    sm = Image.new("L", out.size, 0)
    sm.paste(rounded_mask((pw, ph), r), (pad + int(ph * 0.012), pad + int(ph * 0.02)))
    sh.putalpha(sm.filter(ImageFilter.GaussianBlur(ph * 0.02)).point(lambda v: int(v * 0.55)))
    out.alpha_composite(sh)
    out.alpha_composite(g)
    # the rim (light, a touch of the glow), then the screen
    rimc = tuple(int(255 * 0.75 + c * 0.25) for c in glow) + (255,)
    rim_img = Image.new("RGBA", (pw + 2 * rim, ph + 2 * rim), rimc)
    rim_img.putalpha(rounded_mask(rim_img.size, r + rim))
    out.alpha_composite(rim_img, (pad - rim, pad - rim))
    scr = raw.convert("RGB").resize((pw, ph), Image.LANCZOS).convert("RGBA")
    scr.putalpha(rounded_mask((pw, ph), r))
    out.alpha_composite(scr, (pad, pad))
    return out, pad


def text_layer(size, lines, x0, y_bottom, h, max_w):
    """The headline: a smaller first line, a big second, white, a dark outline and a hard drop shadow -- both smaller
    together when the big line wouldn't fit in max_w (the room left of the phone)."""
    w, _ = size
    small, big = lines
    fs, fb = h * 0.085, h * 0.14
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ds = ImageDraw.Draw(shadow)
    widest = max(d.textlength(big, font=font(int(fb))), d.textlength(small, font=font(int(fs))) if small else 0)
    k = min(1.0, max_w / max(1.0, widest * 1.04))
    fs, fb = int(fs * k), int(fb * k)
    yb = y_bottom
    rows = []
    if big:
        f = font(fb)
        bb = d.textbbox((0, 0), big, font=f)
        yb_top = yb - (bb[3] - bb[1])
        rows.append((big, f, yb_top - bb[1]))
        yb = yb_top - h * 0.012
    if small:
        f = font(fs)
        bb = d.textbbox((0, 0), small, font=f)
        rows.append((small, f, yb - (bb[3] - bb[1]) - bb[1]))
    for text, f, y in rows:
        stroke = max(3, int(f.size * 0.085))
        off = max(3, int(f.size * 0.07))
        ds.text((x0, y + off), text, font=f, fill=INK + (255,), stroke_width=stroke, stroke_fill=INK + (255,))
        d.text((x0, y), text, font=f, fill=(255, 255, 255, 255), stroke_width=stroke, stroke_fill=INK + (255,))
    shadow = shadow.filter(ImageFilter.GaussianBlur(h * 0.002))
    shadow.alpha_composite(layer)
    return shadow


def logo_img():
    base = Image.open(os.path.join(LOGO, "title_rift_base.webp")).convert("RGBA")
    out = Image.new("RGBA", base.size, (0, 0, 0, 0))
    out.alpha_composite(Image.open(os.path.join(LOGO, "title_flag_l.webp")).convert("RGBA"), (0, 153))
    out.alpha_composite(Image.open(os.path.join(LOGO, "title_flag_r.webp")).convert("RGBA"), (1233, 153))
    out.alpha_composite(base)
    return out


def hero_scale(size, heroes, centred, px0):
    """How much smaller than on the iPhone the heroes are drawn on this canvas: the key art's group by the canvas'
    width (a little cut at the sides is fine); with a phone less than in proportion, and never so wide that the last
    one's middle is under the phone."""
    w, h = size
    if centred:
        return min(1.0, (w / h) / 2.17 * 1.38)
    k = min(1.0, ((w / h) / 2.17) ** 0.5)
    reach = max(x + 0.12 * ht for _, x, _, ht in heroes)
    return min(k, (px0 / h) / reach)


def hero_layer(size, art, heroes, centred, k):
    """The heroes (the list's order is back to front). Their places are in units of the canvas height on the iPhone's
    2.17:1; with a phone they keep to the left edge as they are, the key art's group is centred and, on a narrower
    canvas, drawn smaller, standing on the same bottom line."""
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    for name, x, y, ht in heroes:
        im = art[name]
        side = int(ht * h * k)
        r = im.resize((side, side), Image.LANCZOS)
        cx = (w / 2 + (x - 2.17 / 2) * h * k) if centred else x * h * k
        cy = h - (1.0 - y) * h * k
        layer.alpha_composite(r, (int(cx - side / 2), int(cy - side / 2)))
    return layer


def compose(shot, target, art, raw_dir, bg_dir):
    size = TARGETS[target]
    w, h = size
    # the phone: the right side, most of the height
    has_phone = shot["raw"] != ""
    ph_h = h * 0.84
    raw = Image.open(os.path.join(raw_dir, shot["raw"] + "_play.webp")) if has_phone else None
    ph_w = ph_h * 1080 / 1920
    margin = h * 0.045
    px1 = w - margin
    px0 = px1 - ph_w
    k = hero_scale(size, shot["heroes"], not has_phone, px0)
    hero_cx = shot["heroes"][0][1] * h * k if has_phone else w / 2
    bg = backdrop(Image.open(found(bg_dir, shot["bg"])), size, shot["tint"], shot["glow"],
                  (hero_cx, h * 0.42))
    img = bg
    if shot["confetti"]:
        right = max(x for _, x, _, _ in shot["heroes"]) * h * k        # (past the last hero's middle)
        band = (right + h * 0.42 * k, px0 - h * 0.06) if has_phone else None
        far, near = confetti(size, sum(map(ord, shot["key"])), 60, (px0 - h * 0.05, 0, w, h) if has_phone else (0, 0, 0, 0),
                             band)
        img.alpha_composite(far)
    else:
        near = None
    img.alpha_composite(hero_layer(size, art, shot["heroes"], not has_phone, k))
    if has_phone:
        card, pad = phone(raw, ph_h, shot["glow"])
        img.alpha_composite(card, (int(px0 - pad), int((h - ph_h) / 2 - pad)))
    if near is not None:
        img.alpha_composite(near)
    if shot.get("logo"):
        lg = logo_img()
        lw = int(min(w * 0.56, h * 1.2, lg.width * 1.15))
        lg = lg.resize((lw, int(lg.height * lw / lg.width)), Image.LANCZOS)
        at = (int((w - lw) / 2), int(h - lg.height - h * 0.025))
        sh = Image.new("RGBA", size, (0, 0, 0, 0))                     # (a soft shadow under it, off the heroes' colours)
        sh.paste((0, 0, 0, 255), at, lg.getchannel("A").point(lambda v: int(v * 0.7)))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(h * 0.02)))
        img.alpha_composite(lg, at)
    if any(shot["lines"]):
        img.alpha_composite(text_layer(size, shot["lines"], int(h * 0.06), int(h * 0.93), h,
                                       (px0 - h * 0.03 if has_phone else w) - h * 0.06))
    return img.convert("RGB")


def found(d, stem):
    for ext in (".png", ".webp"):
        if os.path.exists(os.path.join(d, stem + ext)):
            return os.path.join(d, stem + ext)
    raise SystemExit("missing %s/%s.png (or .webp)" % (d, stem))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--art", required=True)
    ap.add_argument("--raw", required=True)
    ap.add_argument("--bg", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--targets", default="play,iphone,ipad")
    a = ap.parse_args()
    only = [k for k in a.only.split(",") if k]
    names = {n for s in SHOTS for n, *_ in s["heroes"]}
    art = {}
    for n in names:
        im = Image.open(found(a.art, "store_%s_wide" % n)).convert("RGBA")
        art[n] = im.transpose(Image.FLIP_LEFT_RIGHT) if n in MIRRORED else im
    for t in a.targets.split(","):
        os.makedirs(os.path.join(a.out, t), exist_ok=True)
    for i, shot in enumerate(SHOTS):
        if only and shot["key"] not in only:
            continue
        for t in a.targets.split(","):
            im = compose(shot, t, art, a.raw, a.bg)
            p = os.path.join(a.out, t, "%02d_%s.jpg" % (i + 1, shot["key"]))
            im.save(p, quality=94, subsampling=0, optimize=True)
            print(p, im.size)


if __name__ == "__main__":
    main()
