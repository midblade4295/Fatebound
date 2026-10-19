#!/usr/bin/env python3
"""Herald dialog concepts A-F as 900x2000 phone mockups over a real tutorial frame."""
import os
import numpy as np
import scipy.ndimage as nd
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = "/home/claude/midblade4295/fatebound"
CON = os.path.join(REPO, "art_sources", "tutorial", "concepts")
PORTRAIT_NOW = os.path.join(REPO, "godot", "assets", "ui", "tutorial", "herald.png")
PORTRAIT = os.path.join(CON, "herald_nohorn.png")
NUNITO = os.path.join(HERE, "Nunito-ExtraBold.ttf")
LG = os.path.join(REPO, "godot", "assets", "fonts", "LuckiestGuy-Regular.ttf")
W, H = 900, 2000
LINE = "That gold buys them swords. Swords they then use on you. You see the problem. Dying isn't just embarrassing. It's a donation."
NAVY = (10, 15, 38, 244)
GOLD = (242, 209, 141, 255)
GOLD_D = (173, 134, 81, 255)
TEXT = (243, 239, 225, 255)


def cutout(path):
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float64) / 255.0
    mn = rgb.min(2)
    lab, n = nd.label(mn >= 0.975)
    sizes = nd.sum(np.ones_like(mn), lab, range(1, n + 1))
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    pockets = {i + 1 for i, sz in enumerate(sizes) if sz > 600} - edge
    fg = ~np.isin(lab, list(edge | pockets))
    fg = nd.binary_erosion(fg, iterations=2)
    fg = nd.binary_fill_holes(fg) & ~np.isin(lab, list(pockets))
    a = nd.gaussian_filter(fg.astype(np.float64), 1.0)
    a[a < 0.03] = 0.0
    return Image.fromarray((np.dstack([rgb, a]) * 255 + 0.5).astype(np.uint8), "RGBA")


def base():
    bg = Image.open(os.path.join(HERE, "bg.png")).convert("RGBA").resize((W, H))
    dim = Image.new("RGBA", (W, H), (0, 3, 10, int(255 * 0.42)))
    return Image.alpha_composite(bg, dim)


def font(path, px):
    return ImageFont.truetype(path, px)


def wrap(d, text, f, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textlength(t, font=f) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return lines


def body(im, box, text=LINE, px=36, col=TEXT, hint=True, hint_col=GOLD, gap=1.28, lesson_col=(255, 255, 255, 120)):
    d = ImageDraw.Draw(im)
    f = font(NUNITO, px)
    x0, y0, x1, y1 = box
    for i, l in enumerate(wrap(d, text, f, x1 - x0)):
        d.text((x0, y0 + i * px * gap), l, font=f, fill=col)
    if hint:
        hf = font(NUNITO, 24)
        t = "TAP TO CONTINUE  >"
        d.text((x1 - d.textlength(t, font=hf), y1 - 28), t, font=hf, fill=hint_col)
        if lesson_col[3] > 0:
            d.text((x0, y1 - 28), "LESSON 10 OF 12", font=hf, fill=lesson_col)


def plate(im, xy, text="THE ROYAL HERALD", px=34, anchor="la"):
    d = ImageDraw.Draw(im)
    f = font(LG, px)
    d.text(xy, text, font=f, fill=GOLD, stroke_width=6, stroke_fill=(20, 12, 4, 255), anchor=anchor)


def lesson(im, xy, anchor="ra"):
    d = ImageDraw.Draw(im)
    d.text(xy, "LESSON 10 OF 12", font=font(LG, 24), fill=(255, 255, 255, 170), stroke_width=5, stroke_fill=(20, 12, 4, 255), anchor=anchor)


def panel(im, rect, radius=34, border=5, fill=NAVY, double=False):
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    x0, y0, x1, y1 = rect
    d.rounded_rectangle((x0 + 4, y0 + 10, x1 + 4, y1 + 12), radius, fill=(0, 0, 0, 110))
    lay = lay.filter(ImageFilter.GaussianBlur(8))
    d = ImageDraw.Draw(lay)
    d.rounded_rectangle(rect, radius, fill=fill, outline=GOLD, width=border)
    if double:
        d.rounded_rectangle((x0 + 12, y0 + 12, x1 - 12, y1 - 12), radius - 10, outline=GOLD_D, width=2)
    return Image.alpha_composite(im, lay)


def paste(im, art, xy, size=None):
    if size:
        art = art.resize(size, Image.LANCZOS)
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    lay.paste(art, xy, art)
    return Image.alpha_composite(im, lay)


def label(im, tag, name):
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((18, 1460 - 0, 18 + 0, 1460), 0)
    f = font(LG, 44)
    t = "%s  %s" % (tag, name)
    d.rounded_rectangle((24, 1130, 24 + d.textlength(t, font=f) + 40, 1202), 18, fill=(0, 0, 0, 190), outline=GOLD, width=3)
    d.text((44, 1142), t, font=f, fill=GOLD)


PANEL = (21, 1640, 879, 1952)


def concept_now():
    im = base()
    p = Image.open(PORTRAIT_NOW).convert("RGBA")
    im = paste(im, p, (30, 1640 - 312 + 46), (282, 312))
    im = panel(im, PANEL)
    plate(im, (330, 1576))
    lesson(im, (850, 1590))
    body(im, (58, 1676, 842, 1930), lesson_col=(0, 0, 0, 0))
    label(im, "NOW", "as in 0.31.181")
    return im


def concept_a():
    # A: he rises out of the box -- drawn behind it, the box's top edge across his chest
    im = base()
    p = cut_crop(PORTRAIT)
    w, h = 360, 399
    im = paste(im, p, (24, PANEL[1] - h + 120), (w, h))
    im = panel(im, PANEL, border=6, double=True)
    plate(im, (392, PANEL[1] - 52))
    body(im, (58, PANEL[1] + 40, 842, PANEL[3] - 22))
    label(im, "A", "rises out of the box")
    return im


def concept_b():
    # B: his bust in a gold medallion on the box's corner
    im = base()
    im = panel(im, PANEL, border=6, double=True)
    p = cut_crop(PORTRAIT)
    c, r = (150, PANEL[1] + 4), 122
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.ellipse((c[0] - r - 6, c[1] - r + 2, c[0] + r + 6, c[1] + r + 14), fill=(0, 0, 0, 120))
    lay = lay.filter(ImageFilter.GaussianBlur(6))
    d = ImageDraw.Draw(lay)
    d.ellipse((c[0] - r - 12, c[1] - r - 12, c[0] + r + 12, c[1] + r + 12), fill=(120, 86, 34, 255))
    d.ellipse((c[0] - r - 8, c[1] - r - 8, c[0] + r + 8, c[1] + r + 8), fill=GOLD)
    d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=(28, 44, 104, 255))
    im = Image.alpha_composite(im, lay)
    face = p.resize((330, 365), Image.LANCZOS)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=255)
    lay2 = Image.new("RGBA", im.size, (0, 0, 0, 0))
    lay2.paste(face, (c[0] - 190, c[1] - 150), face)
    lay2.putalpha(Image.fromarray(np.minimum(np.asarray(lay2.split()[3]), np.asarray(mask))))
    im = Image.alpha_composite(im, lay2)
    d = ImageDraw.Draw(im)
    d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), outline=(120, 86, 34, 255), width=3)
    # ribbon name plate along the top edge
    d.rounded_rectangle((260, PANEL[1] - 34, 640, PANEL[1] + 20), 14, fill=(150, 30, 34, 255), outline=GOLD, width=3)
    plate(im, (450, PANEL[1] - 7), px=30, anchor="mm")
    body(im, (300, PANEL[1] + 44, 846, PANEL[3] - 22), px=34)
    label(im, "B", "medallion on the corner")
    return im


def concept_c():
    # C: leaning on the box's top edge, forearms on it
    im = base()
    art = cutout(os.path.join(CON, "C_ledge.png"))
    s = 470 / 1024.0
    art = art.resize((470, 470), Image.LANCZOS)
    top = PANEL[1]
    im = paste(im, art, (8, int(top - 957 * s + 18)))
    im = panel(im, PANEL, border=6, double=True)
    # the forearms over the frame: paste the bottom strip of the art again on top of the border
    strip = art.crop((0, int(930 * s), 470, int(962 * s)))
    im = paste(im, strip, (8, int(top - 957 * s + 18 + 930 * s)))
    plate(im, (500, top - 60))
    body(im, (58, top + 48, 842, PANEL[3] - 22))
    label(im, "C", "leaning on the box")
    return im


def cut_crop(path, margin=6):
    art = cutout(path)
    a = np.asarray(art.split()[3])
    ys, xs = np.nonzero(a > 15)
    return art.crop((max(0, xs.min() - margin), max(0, ys.min() - margin), min(art.width, xs.max() + margin), min(art.height, ys.max() + margin)))


def concept_d():
    # D: the proclamation -- he holds the scroll and the scroll is the text box
    im = base()
    art = cutout(os.path.join(CON, "D_scroll_nohorn.png"))
    s = 930 / 1280.0
    art = art.resize((930, int(720 * s)), Image.LANCZOS)
    ox, y = -20, H - int(720 * s) + 30
    im = paste(im, art, (ox, y))
    x0, x1 = int(ox + 290 * s), int(ox + 1135 * s)
    y0, y1 = int(y + 362 * s), int(y + 640 * s)
    body(im, (x0 + 8, y0 + 4, x1 - 12, y1), px=30, col=(74, 44, 16, 255), hint_col=(140, 36, 30, 255), gap=1.22,
         lesson_col=(74, 44, 16, 150))
    plate(im, (int(ox + 700 * s), y + int(305 * s)), anchor="mm")
    label(im, "D", "the proclamation scroll")
    return im


def concept_e():
    # E: leaning in from the screen's edge, presenting the box
    im = base()
    art = cut_crop(os.path.join(CON, "E_side_nohorn.png"))
    h = 500
    art = art.resize((int(art.width * h / art.height), h), Image.LANCZOS)
    im = paste(im, art, (0, PANEL[1] - h + 46))
    im = panel(im, PANEL, border=6, double=True)
    plate(im, (862, PANEL[1] - 52), anchor="ra")
    body(im, (58, PANEL[1] + 40, 842, PANEL[3] - 22))
    label(im, "E", "leans in from the edge")
    return im


def concept_f():
    # F: the box and the Herald painted as one piece
    im = base()
    art = cutout(os.path.join(CON, "F_panel_nohorn.png"))
    s = 900 / 1280.0
    art = art.resize((900, int(720 * s)), Image.LANCZOS)
    y = H - int(720 * s) + 40
    im = paste(im, art, (0, y))
    x0, x1 = int(515 * s), int(1205 * s)
    y0, y1 = int(y + 333 * s), int(y + 553 * s)
    body(im, (x0 - 14, y0 + 2, x1, y1 + 4), px=27, gap=1.18)
    plate(im, (int(870 * s), y + int(285 * s)), anchor="mm", px=30)
    label(im, "F", "painted as one piece")
    return im


def main():
    out = os.path.join(HERE, "mock")
    os.makedirs(out, exist_ok=True)
    shots = [("0_now", concept_now()), ("A", concept_a()), ("B", concept_b()), ("C", concept_c()),
             ("D", concept_d()), ("E", concept_e()), ("F", concept_f())]
    for n, im in shots:
        im.convert("RGB").save(os.path.join(out, n + ".png"))
    # the sheet: the bottom halves, side by side
    crop = [im.crop((0, 1100, W, H)).convert("RGB") for _, im in shots]
    sw = 450
    sh = int(900 * sw / W)
    sheet = Image.new("RGB", (sw * 4 + 30, sh * 2 + 10), (12, 14, 22))
    for i, c in enumerate(crop):
        sheet.paste(c.resize((sw, sh), Image.LANCZOS), ((i % 4) * (sw + 10), (i // 4) * (sh + 10)))
    sheet.save(os.path.join(HERE, "sheet.jpg"), quality=90)
    print("ok")


if __name__ == "__main__":
    main()
