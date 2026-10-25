#!/usr/bin/env python3
"""X (Twitter) header and profile pictures from the game's 3D art (0.31.214, Kevin: "Make me a new X banner and pfp").
The old ones (tools/build_social_kit.py, 0.31.200) are the painted key art and the painted title -- the look the icon was
redone to get away from ("ai slop", 0.31.210). These are made only from renders of the game's own models: the HD heroes
(tools/meshy_hd.py -> render_app_icon.gd store_* shots, kept in store-listing/graphics/raw_renders/store5/art), the
game's world (store4_match.gd CINE=1 renders, .../store5/bg) and the icon's King and throne room
(art_sources/app_icon/render), with the title set in the game's own title font (Lilita One), white with a dark outline (no
yellow text, Kevin 0.31.195), and the fire-and-ice bar of the game's colours under the line.

  store-listing/social/x/x_header_1500x500.png  (and x_header_3000x1000.png: X shows 1500 x 500; the bigger one for
      a sharper upload) -- six heroes, the King in the middle, over the world out of focus, FATEBOUND and FAST 5V5
      MOBA BATTLES on the left, above where X puts the profile picture (its bottom-left corner) and inside what phones
      show of it
  store-listing/social/x/pfp_king_<n>.png (400, 800, 1080) -- the icon's King closer, his face and crown filling X's
      round crop, the throne room behind him as on the icon (so the account and the app look the same)
  store-listing/social/x/pfp_knight_<n>.png, pfp_stormcaller_<n>.png -- two other heroes the same way, over the world
  store-listing/social/x/preview.jpg -- the header with the King's picture where X puts it, and the three round

    cd godot && python3 tools/build_x_kit.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
ROOT = os.path.dirname(GODOT)
ART = os.path.join(GODOT, "store-listing", "graphics", "raw_renders", "store5", "art")
BG = os.path.join(GODOT, "store-listing", "graphics", "raw_renders", "store5", "bg")
ICON = os.path.join(ROOT, "art_sources", "app_icon", "render")
OUT = os.path.join(GODOT, "store-listing", "social", "x")
FONT = os.path.join(GODOT, "assets", "fonts", "LilitaOne-Regular.ttf")
INK = (10, 16, 34)
ICE = (90, 170, 255)
FIRE = (255, 120, 40)

# the header's heroes, back to front: the render, its middle (x, y) and its square's side, in units of the header's
# height (the header is 3 wide); five -- a team -- the King in the middle
HEROES = [["dragoon", 2.0, 0.40, 1.0], ["king", 2.24, 0.53, 1.24], ["knight", 1.72, 0.56, 1.14],
          ["barbarian", 1.42, 0.6, 1.16], ["stormcaller", 2.72, 0.58, 1.22]]
MIRRORED = {"dragoon"}          # (rendered from his left -- mirrored, he too looks the group's way)


def font(px):
    return ImageFont.truetype(FONT, int(px))


def cover(im, size):
    w, h = size
    k = max(w / im.width, h / im.height)
    r = im.resize((int(im.width * k + 0.5), int(im.height * k + 0.5)), Image.LANCZOS)
    x = (r.width - w) // 2
    y = (r.height - h) // 2
    return r.crop((x, y, x + w, y + h))


def world(name, size, tint, glow, glow_at, blur=55.0, keep=0.42):
    """The game's world out of focus, tinted toward `tint` (its light and dark kept), a light behind the heroes, darker
    toward the edges (tools/store5_compose.py's backdrop)."""
    w, h = size
    b = cover(Image.open(os.path.join(BG, name + ".webp")).convert("RGB"), size).filter(ImageFilter.GaussianBlur(h / blur))
    b = ImageEnhance.Color(b).enhance(1.25)
    a = np.asarray(b, np.float32)
    a = a * keep + np.array(tint, np.float32) * (1.0 - keep) * (a.mean(-1, keepdims=True) / 130.0)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    gx, gy = glow_at
    d = np.sqrt(((x - gx) / h) ** 2 + ((y - gy) / h) ** 2)
    a += np.array(glow, np.float32) * (np.clip(1.0 - d / 0.9, 0, 1) ** 2 * 0.6)[..., None]
    v = np.sqrt(((x - w / 2) / (w * 0.7)) ** 2 + ((y - h * 0.45) / (h * 0.9)) ** 2)
    a *= (1.0 - 0.42 * np.clip(v, 0, 1.3) ** 2)[..., None]
    a += np.random.default_rng(3).normal(0, 1.2, a.shape)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def hero(name):
    im = Image.open(os.path.join(ART, "store_%s_wide.webp" % name)).convert("RGBA")
    return im.transpose(Image.FLIP_LEFT_RIGHT) if name in MIRRORED else im


def shadowed_text(layer, xy, text, f, stroke, off, fill=(255, 255, 255, 255)):
    d = ImageDraw.Draw(layer)
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((xy[0], xy[1] + off), text, font=f, fill=INK + (255,), stroke_width=stroke, stroke_fill=INK + (255,))
    layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(max(1, off * 0.15))))
    d.text(xy, text, font=f, fill=fill, stroke_width=stroke, stroke_fill=INK + (255,))


def fire_ice_bar(layer, x0, y, w, h):
    """The game's two sides in one bar: ice blue into fire orange, a dark edge, a light along its top."""
    bar = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    a = np.zeros((h, w, 4), np.float32)
    t = np.linspace(0, 1, w, dtype=np.float32)[None, :, None]
    a[..., :3] = np.array(ICE, np.float32) * (1 - t) + np.array(FIRE, np.float32) * t
    a[..., 3] = 255
    a[: max(1, h // 4), :, :3] = a[: max(1, h // 4), :, :3] * 0.6 + 255 * 0.4
    bar = Image.fromarray(a.astype(np.uint8), "RGBA")
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), radius=h // 2, fill=255)
    edge = Image.new("RGBA", (w + 8, h + 8), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((0, 0, w + 7, h + 7), radius=(h + 8) // 2, fill=INK + (255,))
    layer.alpha_composite(edge, (x0 - 4, y - 4))
    layer.paste(bar, (x0, y), m)


def header(W=3000, H=1000):
    size = (W, H)
    img = world("feature", size, (36, 80, 190), (130, 190, 255), (2.15 * H, 0.42 * H))
    wash = Image.new("L", size, 0)                    # (a darker wash where the title goes, under the heroes)
    ImageDraw.Draw(wash).ellipse((-0.6 * H, -0.15 * H, 1.25 * H, 0.95 * H), fill=150)
    wash = wash.filter(ImageFilter.GaussianBlur(0.16 * H))
    dark = Image.new("RGBA", size, INK + (0,))
    dark.putalpha(wash)
    img.alpha_composite(dark)
    for name, cx, cy, side in HEROES:
        s = int(side * H)
        r = hero(name).resize((s, s), Image.LANCZOS)
        img.alpha_composite(r, (int(cx * H - s / 2), int(cy * H - s / 2)))
    # the title on the left: FATEBOUND over FAST 5V5 MOBA BATTLES, the bar between them
    tl = Image.new("RGBA", size, (0, 0, 0, 0))
    x0 = int(0.075 * H)
    big = font(0.235 * H)
    shadowed_text(tl, (x0, int(0.15 * H)), "FATEBOUND", big, int(0.017 * H), int(0.02 * H))
    bb = ImageDraw.Draw(tl).textbbox((x0, int(0.15 * H)), "FATEBOUND", font=big)
    fire_ice_bar(tl, x0 + int(0.006 * H), bb[3] + int(0.045 * H), bb[2] - bb[0] - int(0.012 * H), int(0.022 * H))
    small = font(0.104 * H)
    shadowed_text(tl, (x0 + int(0.004 * H), bb[3] + int(0.105 * H)), "FAST 5V5 MOBA BATTLES", small, int(0.009 * H), int(0.012 * H))
    img.alpha_composite(tl)
    return img.convert("RGB")


def round_check(im):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).ellipse((0, 0, im.width - 1, im.height - 1), fill=255)
    out = Image.new("RGB", im.size, (255, 255, 255))
    out.paste(im, (0, 0), m)
    return out


def pfp_king(n=1080):
    """The icon's King, closer: the throne room (blurred like the icon's) and him, cropped round his face and crown."""
    wide = Image.open(os.path.join(ICON, "king_hd_wide.png")).convert("RGBA")
    room = Image.open(os.path.join(ICON, "king_hd_bg_wide.png")).convert("RGB")
    N = wide.width
    b = ImageEnhance.Color(room.filter(ImageFilter.GaussianBlur(N / 110))).enhance(1.1).convert("RGBA")
    b.alpha_composite(wide)
    side = int(N * 0.5)                              # (the icon is the middle two thirds: this is closer)
    cx, cy = int(N * 0.465), int(N * 0.47)
    crop = b.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)).convert("RGB")
    return vignette(crop).resize((n, n), Image.LANCZOS)


def pfp_hero(name, tint, glow, face, side, n=1080):
    """A hero's head and shoulders (face: where his face is in the render, side: the crop's side, both as fractions of
    the render) over the world out of focus in the hero's colour."""
    im = hero(name)
    N = im.width
    s = int(N * side)
    cx, cy = int(N * face[0]), int(N * face[1])
    box = (cx - s // 2, cy - s // 2, cx + s // 2, cy + s // 2)
    bg = world("feature", (s, s), tint, glow, (s * 0.5, s * 0.42), blur=30.0, keep=0.35)
    bg.alpha_composite(im.crop(box))
    return vignette(bg.convert("RGB")).resize((n, n), Image.LANCZOS)


def vignette(im, amount=0.35):
    a = np.asarray(im, np.float32)
    h, w = a.shape[:2]
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((x - w / 2) / (w / 2)) ** 2 + ((y - h * 0.46) / (h / 2)) ** 2)
    a *= (1.0 - amount * np.clip(d, 0, 1.4) ** 2)[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def main():
    os.makedirs(OUT, exist_ok=True)
    big = header()
    big.save(os.path.join(OUT, "x_header_3000x1000.png"), optimize=True)
    small = big.resize((1500, 500), Image.LANCZOS)
    small.save(os.path.join(OUT, "x_header_1500x500.png"), optimize=True)
    pfps = {
        "king": pfp_king(),
        "knight": pfp_hero("knight", (40, 110, 70), (170, 255, 200), (0.5, 0.45), 0.36),
        "stormcaller": pfp_hero("stormcaller", (20, 120, 160), (140, 230, 255), (0.52, 0.31), 0.38),
    }
    for k, im in pfps.items():
        for n in (1080, 800, 400):
            im.resize((n, n), Image.LANCZOS).save(os.path.join(OUT, "pfp_%s_%d.png" % (k, n)), optimize=True)
    # the sheet: the header as X lays it out (the profile picture over its bottom-left), the three round
    sheet = Image.new("RGB", (1500, 500 + 60 + 300 + 40), (21, 24, 31))
    sheet.paste(small, (0, 0))
    av = round_check(pfps["king"].resize((134, 134), Image.LANCZOS))
    ring = Image.new("L", (142, 142), 0)
    ImageDraw.Draw(ring).ellipse((0, 0, 141, 141), fill=255)
    sheet.paste((21, 24, 31), (16, 500 - 72), ring)
    m = Image.new("L", (134, 134), 0)
    ImageDraw.Draw(m).ellipse((0, 0, 133, 133), fill=255)
    sheet.paste(av, (20, 500 - 68), m)
    for i, k in enumerate(pfps):
        r = pfps[k].resize((300, 300), Image.LANCZOS)
        m3 = Image.new("L", (300, 300), 0)
        ImageDraw.Draw(m3).ellipse((0, 0, 299, 299), fill=255)
        sheet.paste(r, (260 + i * 360, 580), m3)
    sheet.save(os.path.join(OUT, "preview.jpg"), quality=90)
    print("X kit written to", OUT)


if __name__ == "__main__":
    main()
