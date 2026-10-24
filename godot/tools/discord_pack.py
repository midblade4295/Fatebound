#!/usr/bin/env python3
"""Fatebound's Discord emojis and stickers (Kevin: "Make me a set of discord emojis and stickers").

From the heroes rendered by tools/render_discord.gd (--raw) and the game's own art (its icons, currency, chests, kill
banners, the app icon) and font (Lilita One):
  emojis/<name>.png     128 x 128 PNG (Discord: 128 x 128, 256 KB at most)
  stickers/<name>.png   320 x 320 PNG; the animated ones APNG (Discord: exactly 320 x 320, 512 KB at most)
  preview_*.png, README.txt (names, each sticker's emoji tag and description)
    python3 tools/discord_pack.py --raw <render_discord.gd's OUT_DIR> --out <dir>
"""
import argparse
import io
import math
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
A = os.path.join(GODOT, "assets")
FONT = os.path.join(A, "fonts", "LilitaOne-Regular.ttf")
INK = (27, 16, 48, 255)          # the game's dark outline (UI2.INK's family)
GOLD = (255, 214, 90, 255)
EMOJI = 128
STICKER = 320
STICKER_MAX = 512 * 1024
EMOJI_MAX = 256 * 1024

HEROES = ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "crusader", "berserker", "assassin", "sniper",
          "archmage", "necromancer", "golem", "dragoon", "duelist", "stormcaller", "musketeer", "druid"]
# a hero's head on its bust: (zoom: the square's side as a share of the bust's height, nudge x, nudge y) -- hats,
# plumes and antlers kept in
HEAD = {"knight": (0.70, 0, 0), "barbarian": (0.66, 0, 0), "rogue": (0.66, 0, 0), "ranger": (0.74, 0, 0),
        "mage": (0.74, 0, 0), "priest": (0.66, 0, 0), "crusader": (0.70, 0, 0), "berserker": (0.66, 0, 0),
        "assassin": (0.66, 0, 0), "sniper": (0.74, 0, 0), "archmage": (0.70, 0, 0), "necromancer": (0.66, 0, 0),
        "golem": (0.62, 0, 0), "dragoon": (0.70, 0, 0), "duelist": (0.66, 0, 0), "stormcaller": (0.66, 0, 0),
        "musketeer": (0.78, 0, 0), "druid": (0.74, 0, 0)}

# emojis from the game's art: name -> file
ICON_EMOJIS = [
    ("gold", "ui/currency/coin.png"), ("gems", "ui/currency/gem.png"), ("loot", "ui/currency/coins_l.png"),
    ("crown", "ui/v2/icons/crown.png"), ("ko", "ui/v2/icons/skull.png"), ("battle", "ui/v2/icons/swords.png"),
    ("trophy", "ui/v2/icons/trophy.png"), ("castle", "ui/v2/icons/castle.png"), ("herald", "ui/v2/icons/horn.png"),
    ("royal_chest", "ui/v2/chests/royal_icon.png"), ("chest", "ui/v2/chests/wood_icon.png"),
    ("ace", "ui/banners/ace.png"), ("quadrakill", "ui/banners/quadra.png"), ("pentakill", "ui/banners/penta.png"),
]
TEXT_EMOJIS = [("gg", "GG"), ("gl", "GL"), ("wp", "WP")]

# stickers: name, render, caption, banner (game art over him), emoji tag, description, animated
STICKERS = [
    ("gg", "necromancer_raise", "GG", None, "🤝", "The Necromancer raises his staff: GG", False),
    ("lets_go", "dragoon_jump", "LET'S GO!", None, "🔥", "The Dragoon leaps: LET'S GO!", True),
    ("double_kill", "stormcaller_cast", None, "ui/banners/double.png", "⚡", "The Stormcaller's lightning: DOUBLE KILL", False),
    ("on_my_way", "musketeer_run", "ON MY WAY", None, "🏃", "The Musketeer running: ON MY WAY", True),
    ("rip", "crusader_down", "RIP", None, "💀", "The Crusader knocked out: RIP", False),
    ("first_blood", "barbarian_chop", None, "ui/banners/first_blood.png", "🩸", "The Barbarian's axe: FIRST BLOOD", False),
    ("angry_rock", "golem_smash", "ANGRY ROCK", None, "🪨", "The Golem smashes: ANGRY ROCK", True),
    ("every_button", "mage_spell", "PRESS EVERY\nBUTTON", None, "🪄", "The Mage casting everything: PRESS EVERY BUTTON", True),
    ("need_heals", "priest_raise", "NEED HEALS?", None, "🙏", "The Priest: NEED HEALS?", False),
    ("sneaky", "rogue_sneak", "SNEAKY", None, "🤫", "The Rogue sneaking: SNEAKY", False),
    ("blocked", "knight_block", "BLOCKED", None, "🛡️", "The Knight behind his shield: BLOCKED", False),
    ("touch_grass", "druid_grass", "TOUCH GRASS", None, "🌿", "The Druid: TOUCH GRASS", False),
    ("one_v_one", "duelist_stab", "1V1 ME", None, "⚔️", "The Duelist en garde: 1V1 ME", False),
    ("protect_king", "king", "PROTECT\nTHE KING", None, "👑", "The King: PROTECT THE KING", False),
    ("brave_lad", "minion", "BRAVE\nLITTLE LAD", None, "🫡", "A minion charging: BRAVE LITTLE LAD", False),
]
STARTER = ["gg", "lets_go", "double_kill", "on_my_way", "rip"]   # an unboosted server's five sticker slots


def font(px):
    return ImageFont.truetype(FONT, px)


def trim(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def despeck(im, min_share=0.004):
    """only the figure: stray specks (a spell's sparks, a glint) cut away -- every opaque island smaller than min_share
    of the biggest one goes, so the die-cut outline doesn't ring each of them"""
    a = np.array(im.getchannel("A"))
    lab, n = ndimage.label(a > 24)
    if n <= 1:
        return im
    sizes = ndimage.sum(np.ones_like(a), lab, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes >= sizes.max() * min_share
    keep[1:] |= sizes >= 2500                      # (a weapon held clear of the body, a staff's head)
    mask = keep[lab]
    # the soft edges round a kept island stay: grow the mask a little
    mask = ndimage.binary_dilation(mask, iterations=2)
    out = np.array(im)
    out[..., 3] = np.where(mask, out[..., 3], 0)
    return Image.fromarray(out, "RGBA")


def outline(im, px, color, soft=0.0):
    """im with a solid outline of px around its opaque shape (a die-cut sticker's border)."""
    a = im.getchannel("A")
    pad = px + 4
    big = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    big.alpha_composite(im, (pad, pad))
    a = big.getchannel("A").point(lambda v: 255 if v > 24 else 0)
    grown = a.filter(ImageFilter.MaxFilter(px * 2 + 1)) if px > 0 else a
    if soft > 0:
        grown = grown.filter(ImageFilter.GaussianBlur(soft))
    base = Image.new("RGBA", big.size, color)
    base.putalpha(grown)
    base.alpha_composite(big)
    return base


def shadow(im, off, blur, alpha):
    a = im.getchannel("A").point(lambda v: int(v * alpha))
    sh = Image.new("RGBA", (im.width + off * 2 + blur * 4, im.height + off * 2 + blur * 4), (0, 0, 0, 0))
    s = Image.new("RGBA", im.size, (8, 4, 20, 255))
    s.putalpha(a)
    sh.alpha_composite(s, (blur * 2 + off, blur * 2 + off))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    sh.alpha_composite(im, (blur * 2, blur * 2))
    return sh


def fit(im, w, h):
    s = min(w / im.width, h / im.height)
    return im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)


def text_img(text, px, fill=(255, 255, 255, 255), stroke=INK, stroke_px=None, gradient=None):
    """Lilita One, centred lines, a thick dark stroke (the game's titles); gradient: (top, bottom) fill colours"""
    f = font(px)
    sp = stroke_px if stroke_px is not None else max(2, px // 7)
    lines = text.split("\n")
    d0 = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    boxes = [d0.textbbox((0, 0), ln, font=f, stroke_width=sp) for ln in lines]
    lh = int(px * 0.98)
    w = max(b[2] - b[0] for b in boxes) + 8
    h = lh * (len(lines) - 1) + (boxes[-1][3] - boxes[-1][1]) + sp * 2 + 8
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, (ln, b) in enumerate(zip(lines, boxes)):
        x = (w - (b[2] - b[0])) // 2 - b[0]
        y = i * lh + sp + 4 - b[1] + sp
        d.text((x, y), ln, font=f, fill=fill, stroke_width=sp, stroke_fill=stroke)
    if gradient:
        # the fill alone recoloured top to bottom (the stroke stays): paint the letters' insides
        inner = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        di = ImageDraw.Draw(inner)
        for i, (ln, b) in enumerate(zip(lines, boxes)):
            x = (w - (b[2] - b[0])) // 2 - b[0]
            y = i * lh + sp + 4 - b[1] + sp
            di.text((x, y), ln, font=f, fill=(255, 255, 255, 255))
        grad = Image.new("RGBA", (w, h))
        for yy in range(h):
            t = yy / max(1, h - 1)
            grad.paste(tuple(int(gradient[0][k] + (gradient[1][k] - gradient[0][k]) * t) for k in range(4)), (0, yy, w, yy + 1))
        grad.putalpha(inner.getchannel("A"))
        im.alpha_composite(grad)
    return trim(im)


def rotate(im, deg):
    return im.rotate(deg, resample=Image.BICUBIC, expand=True)


def canvas(size):
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def paste_center(cv, im, cx, cy):
    cv.alpha_composite(im, (int(round(cx - im.width / 2)), int(round(cy - im.height / 2))))


# ---------------- emojis ----------------
def head_of(path, hero):
    im = Image.open(path).convert("RGBA")
    x0, y0, x1, y1 = im.getbbox()
    zoom, nx, ny = HEAD.get(hero, (0.7, 0, 0))
    side = int((im.height - y0) * zoom)
    top = max(0, y0 - int(side * 0.03)) + ny
    # centre on the opaque pixels of the head's rows
    a = im.getchannel("A").crop((0, top, im.width, min(im.height, top + side // 2)))
    cols = (np.array(a) > 40).sum(axis=0)
    tot = cols.sum() or 1
    cx = int((cols * np.arange(len(cols))).sum() / tot) + nx
    left = cx - side // 2
    head = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    head.alpha_composite(im.crop((max(0, left), top, min(im.width, left + side), min(im.height, top + side))),
                         (max(0, -left), 0))
    return head


def bottom_fade(cv, start=0.80):
    """the bust's cut at the bottom (and its outline): a soft fade so it doesn't end in a hard edge"""
    fade = Image.new("L", cv.size, 255)
    fd = ImageDraw.Draw(fade)
    f0 = int(cv.height * start)
    for yy in range(f0, cv.height):
        fd.line([(0, yy), (cv.width, yy)], fill=int(255 * (1 - (yy - f0) / (cv.height - f0)) ** 1.4))
    cv.putalpha(ImageChops.multiply(cv.getchannel("A"), fade))
    return cv


def emoji_from(im, pad=4, ring=2, fade=False):
    im = trim(im)
    inner = EMOJI - pad * 2 - ring * 2
    im = fit(im, inner, inner)
    im = outline(im, ring, INK)
    cv = canvas(EMOJI)
    paste_center(cv, im, EMOJI / 2, EMOJI / 2 + (pad + ring if fade else 0))
    return bottom_fade(cv) if fade else cv


def text_emoji(t):
    im = text_img(t, 120, gradient=((255, 240, 160, 255), (255, 170, 40, 255)), stroke_px=12)
    im = rotate(im, 8)
    return emoji_from(im, pad=2, ring=0)


# ---------------- stickers ----------------
def sticker_frame(hero_im, caption, banner, box=None):
    # box: an animated sticker's crop, the same for every frame (the frames' bounding boxes together), so he moves
    # in it rather than each frame being fitted on its own
    cv = canvas(STICKER)
    body = despeck(hero_im)
    body = body.crop(box) if box else trim(body)
    top_room = 0
    ban = None
    if banner:
        ban = fit(trim(Image.open(os.path.join(A, banner)).convert("RGBA")), 300, 110)
        top_room = ban.height - 18
    cap = None
    if caption:
        lines = caption.count("\n") + 1
        cap = text_img(caption, 62 if lines == 1 else 46, stroke_px=8)
        if cap.width > 304:
            cap = fit(cap, 304, 400)
        cap = rotate(cap, 4)
    bottom_room = (cap.height - 26) if cap is not None else 0
    avail_h = STICKER - 16 - top_room - bottom_room
    body = fit(body, 284, max(120, avail_h))
    body = outline(body, 5, (255, 255, 255, 255), soft=0.6)
    body = shadow(body, 3, 3, 0.45)
    cy = 8 + top_room + avail_h / 2 + 4
    paste_center(cv, body, STICKER / 2, cy)
    if ban is not None:
        b = shadow(ban, 2, 3, 0.5)
        paste_center(cv, b, STICKER / 2, 8 + b.height / 2)
    if cap is not None:
        c = shadow(cap, 3, 2, 0.6)
        paste_center(cv, c, STICKER / 2, STICKER - 6 - c.height / 2)
    return cv


def save_apng(frames, path, fps):
    """An 8-bit APNG within Discord's 512 KB: every frame on ONE shared 256-colour palette (alpha kept: the frames
    quantized together, side by side, then cut apart), Pillow writing only what changed from frame to frame; fewer
    colours, then every other frame, if it's still too big"""
    for colours, step in ((256, 1), (192, 1), (128, 1), (256, 2), (128, 2)):
        fr = frames[::step]
        strip = Image.new("RGBA", (STICKER, STICKER * len(fr)), (0, 0, 0, 0))
        for i, f in enumerate(fr):
            strip.paste(f, (0, i * STICKER))
        q = strip.quantize(colors=colours, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
        parts = [q.crop((0, i * STICKER, STICKER, (i + 1) * STICKER)) for i in range(len(fr))]
        buf = io.BytesIO()
        parts[0].save(buf, format="PNG", save_all=True, append_images=parts[1:], duration=int(1000 * step / fps),
                      loop=0, disposal=0, blend=0, optimize=True)
        if buf.tell() <= STICKER_MAX:
            open(path, "wb").write(buf.getvalue())
            return buf.tell(), colours, len(fr)
    open(path, "wb").write(buf.getvalue())
    return buf.tell(), colours, len(fr)


def sheet(paths, cell, cols, bg, out):
    ims = [Image.open(p).convert("RGBA") for p in paths]
    rows = math.ceil(len(ims) / cols)
    sh = Image.new("RGBA", (cols * (cell + 12) + 12, rows * (cell + 12) + 12), bg)
    for i, im in enumerate(ims):
        im = im.copy()
        im.thumbnail((cell, cell))
        sh.alpha_composite(im, (12 + (i % cols) * (cell + 12), 12 + (i // cols) * (cell + 12)))
    sh.save(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    ed = os.path.join(a.out, "emojis")
    sd = os.path.join(a.out, "stickers")
    os.makedirs(ed, exist_ok=True)
    os.makedirs(sd, exist_ok=True)
    readme = ["FATEBOUND -- DISCORD EMOJIS AND STICKERS", ""]
    # ---- emojis
    names = []
    for h in HEROES:
        e = emoji_from(head_of(os.path.join(a.raw, "bust_%s.png" % h), h), fade=True)
        e.save(os.path.join(ed, h + ".png"), optimize=True)
        names.append(h)
    king = Image.open(os.path.join(a.raw, "king.png")).convert("RGBA")
    kb = king.getbbox()
    kh = king.crop((kb[0], kb[1], kb[2], kb[1] + int((kb[3] - kb[1]) * 0.42)))
    emoji_from(kh, fade=True).save(os.path.join(ed, "king.png"), optimize=True)
    names.append("king")
    for n, f in ICON_EMOJIS:
        emoji_from(Image.open(os.path.join(A, f)).convert("RGBA"), ring=0).save(os.path.join(ed, n + ".png"), optimize=True)
        names.append(n)
    for n, t in TEXT_EMOJIS:
        text_emoji(t).save(os.path.join(ed, n + ".png"), optimize=True)
        names.append(n)
    readme.append("EMOJIS (%d) -- 128 x 128 PNG. Server Settings > Emoji > Upload Emoji (a server has 50 slots without"
                  " boosts); the file name becomes the emoji's name (:name:)" % len(names))
    for n in names:
        sz = os.path.getsize(os.path.join(ed, n + ".png"))
        assert sz <= EMOJI_MAX, n
        readme.append("  :%s:" % n)
    # ---- stickers
    readme += ["", "STICKERS (%d) -- 320 x 320 PNG; the four animated ones APNG (stickers/still/ has a still of each)."
               % len(STICKERS),
               "Server Settings > Stickers > Upload Sticker: pick the file, give it the name, the emoji tag (Discord's"
               " related emoji) and the description below. A server has 5 sticker slots without boosts (the starter",
               "five are marked *), more with each boost level. An animated sticker shows moving only once uploaded there"
               " -- sent through the chat bar it stays still.",
               "  name -- emoji tag -- description"]
    for (n, render, cap, banner, tag, desc, animated) in STICKERS:
        path = os.path.join(sd, n + ".png")
        src = os.path.join(a.raw, "king.png" if render == "king" else "pose_%s.png" % render)
        if animated:
            raws = []
            i = 0
            while os.path.exists(os.path.join(a.raw, "anim_%s_%02d.png" % (render, i))):
                raws.append(Image.open(os.path.join(a.raw, "anim_%s_%02d.png" % (render, i))).convert("RGBA"))
                i += 1
            bbs = [despeck(r).getbbox() for r in raws]
            box = (min(b[0] for b in bbs), min(b[1] for b in bbs), max(b[2] for b in bbs), max(b[3] for b in bbs))
            frames = [sticker_frame(r, cap, banner, box) for r in raws]
            size, colours, nf = save_apng(frames, path, 15)
            kind = "animated APNG, %d frames, %d colours" % (nf, colours)
            os.makedirs(os.path.join(sd, "still"), exist_ok=True)
            sticker_frame(Image.open(src).convert("RGBA"), cap, banner).save(os.path.join(sd, "still", n + ".png"), optimize=True)
        else:
            sticker_frame(Image.open(src).convert("RGBA"), cap, banner).save(path, optimize=True)
            size = os.path.getsize(path)
            kind = "PNG"
        im = Image.open(path)
        assert im.size == (STICKER, STICKER), n
        readme.append("  %s%s -- %s -- %s  (%s, %d KB)" % ("*" if n in STARTER else " ", n, tag, desc, kind, size // 1024))
        print("sticker", n, kind, size // 1024, "KB")
    open(os.path.join(a.out, "README.txt"), "w").write("\n".join(readme) + "\n")
    # ---- previews (Discord's dark and light themes)
    ep = [os.path.join(ed, n + ".png") for n in names]
    sp = [os.path.join(sd, ("still/" if s[6] else "") + s[0] + ".png") for s in STICKERS]
    sheet(ep, 128, 8, (49, 51, 56, 255), os.path.join(a.out, "preview_emojis_dark.png"))
    sheet(ep, 128, 8, (255, 255, 255, 255), os.path.join(a.out, "preview_emojis_light.png"))
    sheet(sp, 320, 5, (49, 51, 56, 255), os.path.join(a.out, "preview_stickers_dark.png"))
    sheet(sp, 320, 5, (255, 255, 255, 255), os.path.join(a.out, "preview_stickers_light.png"))
    print("emojis", len(names), "stickers", len(STICKERS))


if __name__ == "__main__":
    main()
