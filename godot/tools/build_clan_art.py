#!/usr/bin/env python3
"""The clans' art (0.31.196, Kevin: "Do clan chest, clan camp, crest, shard requests, 5 - stack, lfg button, league").

Sources (ElevenLabs, flow "Fatebound clans 0.31.196", gpt-image-2), in art_sources/clans/:
  emblems_a.png     a 4 x 4 grid of white heraldic emblems on black (Eco.CLAN_EMBLEMS' order: lion, stag, raven, wolf /
                    dragon, bear, eagle, boar / skull, crown, swords, tower / tree, flame, moon, bolt) -- the one used
  emblems_c.png     another take of the same grid: its eagle (wings raised: a's raven and eagle were one bird twice)
  raven.png         four side-view ravens (a 2 x 2 grid): the one on a branch (top right) is the raven
  shield_green.png  a gold-rimmed shield with a blank grey field on flat green (the first of four takes)
  camp_stages.png   the clan camp at its four stages (a 2 x 2 grid: a tent and a banner; two tents, two banners; a
                    palisade, three banners, a cauldron; a hall, a watchtower, five banners) -- 0.31.196's
  stage_<1-4>_square.png  each stage cut out of it (0.31.197: the references for the tall ones)
  camp_tall_<1-4>.png     each stage carried up into the night sky and down over more ground, 1024 x 2048
                    (gpt-image-2.5-sunburst from stage_<n>_square.png; the second of four takes each)

Writes assets/ui/clans/ (the "ui" content pack):
  emblem_<name>.png             each emblem, white on clear, EMBLEM px square (tinted the crest's colour in the app)
  shield_field.png              the shield's field: its soft shading in grey-white on clear, reaching a little under the
                                rim (tinted the crest's field colour)
  shield_rim_<metal>.png        the rim with the field cut out: iron (every clan), gold / silver / bronze (last week's
                                League podium, Eco.CLAN_LEAGUE_PRIZES "frame")
  camp_<1-4>.webp               the camp's stages, tall (CAMP_W x CAMP_H): the whole CLAN screen behind its buttons
                                (scripts/app/clan_camp.gd; 0.31.197, Kevin: "make the camp screen fill the entire
                                screen")
and prints the shield's field and, per stage, the banners' cloth and the fire (clan_camp.gd's consts).

  python3 tools/build_clan_art.py
"""
import os

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as nd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(ROOT), "art_sources", "clans")
OUT = os.path.join(ROOT, "assets", "ui", "clans")
NAMES = ["lion", "stag", "raven", "wolf", "dragon", "bear", "eagle", "boar", "skull", "crown", "swords", "tower",
         "tree", "flame", "moon", "bolt"]
EMBLEM = 160                      # px square; the emblem fills EMBLEM_FILL of it
EMBLEM_FILL = 148
SHIELD_W = 256
CAMP_W, CAMP_H = 1024, 2048       # a stage's tall painting


def components(gray, n, merge=14):
    """the n biggest white shapes (parts closer than `merge` px are one), as (box, mask) in reading order"""
    m = gray > 100
    lab, k = nd.label(nd.binary_dilation(m, iterations=merge))
    sizes = nd.sum(m, lab, range(1, k + 1))
    keep = np.argsort(sizes)[::-1][:n] + 1
    out = []
    for i in keep:
        sl = nd.find_objects((lab == i).astype(np.int32))[0]
        out.append(((sl[0].start, sl[0].stop, sl[1].start, sl[1].stop), lab == i))
    out.sort(key=lambda b: (b[0][0] + b[0][1]) / 2)
    rows = int(round(n ** 0.5))
    per = n // rows
    ordered = []
    for r in range(rows):
        ordered += sorted(out[r * per:(r + 1) * per], key=lambda b: b[0][2])
    return ordered


def emblem_image(gray, box, mask, only_largest=False):
    y0, y1, x0, x1 = box
    g = np.where(mask, gray, 0.0)[y0:y1, x0:x1]
    if only_largest:                                   # (the moon: its crescent, not the star beside it)
        lab, k = nd.label(g > 100)
        sizes = nd.sum(g > 100, lab, range(1, k + 1))
        big = nd.binary_dilation(lab == (int(np.argmax(sizes)) + 1), iterations=3)
        g = np.where(big, g, 0.0)
    ys, xs = np.where(g > 30)
    g = g[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    a = np.clip((g - 30.0) / 170.0, 0.0, 1.0)
    h, w = a.shape
    s = EMBLEM_FILL / max(h, w)
    im = Image.fromarray((a * 255).astype(np.uint8)).resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    canvas = Image.new("L", (EMBLEM, EMBLEM), 0)
    canvas.paste(im, ((EMBLEM - im.size[0]) // 2, (EMBLEM - im.size[1]) // 2))
    white = Image.new("L", (EMBLEM, EMBLEM), 255)
    return Image.merge("RGBA", (white, white, white, canvas))


def emblems():
    ga = np.asarray(Image.open(os.path.join(SRC, "emblems_a.png")).convert("L")).astype(float)
    gc = np.asarray(Image.open(os.path.join(SRC, "emblems_c.png")).convert("L")).astype(float)
    gr = np.asarray(Image.open(os.path.join(SRC, "raven.png")).convert("L")).astype(float)
    a = components(ga, 16)
    c = components(gc, 16)
    ravens = components(gr, 4, merge=10)
    sheet = Image.new("RGBA", (EMBLEM * 8, EMBLEM * 2), (40, 50, 80, 255))
    for i, name in enumerate(NAMES):
        if name == "raven":
            box, mask = ravens[1]                      # (the top right one: on a branch)
            im = emblem_image(gr, box, mask)
        elif name == "eagle":
            box, mask = c[i]
            im = emblem_image(gc, box, mask)
        else:
            box, mask = a[i]
            im = emblem_image(ga, box, mask, only_largest=(name == "moon"))
        im.save(os.path.join(OUT, "emblem_%s.png" % name), optimize=True)
        sheet.alpha_composite(im, ((i % 8) * EMBLEM, (i // 8) * EMBLEM))
    sheet.save("/tmp/clan_emblems_sheet.png")
    print("emblems: %d written (sheet /tmp/clan_emblems_sheet.png)" % len(NAMES))


def shield():
    im = Image.open(os.path.join(SRC, "shield_green.png")).convert("RGB")
    a = np.array(im).astype(float)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    spill = G - np.maximum(R, B)
    alpha = 1.0 - np.clip((spill - 40.0) / 90.0, 0.0, 1.0)
    a[..., 1] = np.where((alpha < 1.0) | (spill > 10), np.minimum(G, np.maximum(R, B) * 1.02), G)
    alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))) / 255.0
    # the field: the flat grey inside the rim (low saturation, light), one piece, holes filled
    mx = a.max(2)
    mn = a.min(2)
    grey = (mx - mn < 22) & (mx > 140) & (alpha > 0.9)
    lab, k = nd.label(grey)
    sizes = nd.sum(grey, lab, range(1, k + 1))
    field = nd.binary_fill_holes(lab == (int(np.argmax(sizes)) + 1))
    field = nd.binary_opening(field, iterations=2)
    soft = np.asarray(Image.fromarray((field * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))) / 255.0
    under = nd.binary_dilation(field, iterations=4)    # (the field layer reaches under the rim: no seam)
    under_soft = np.asarray(Image.fromarray((under * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))) / 255.0
    lum = a.mean(2)
    ref = np.percentile(lum[field], 90)
    shade = np.clip(lum / ref, 0.55, 1.0)
    shade = np.where(field, shade, 0.9)                # (under the rim: a plain light value)
    ys, xs = np.where(alpha > 0.05)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    sw = box[2] - box[0]
    sh = box[3] - box[1]
    S = SHIELD_W / sw
    size = (SHIELD_W, round(sh * S))

    def out(rgb, al, name):
        img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), (np.clip(al, 0, 1) * 255).astype(np.uint8)]), "RGBA")
        img = img.crop(box).resize(size, Image.LANCZOS)
        img.save(os.path.join(OUT, name), optimize=True)
        return img

    v = (shade * 255.0)[..., None].repeat(3, 2)
    out(v, under_soft * alpha, "shield_field.png")
    rim_al = alpha * (1.0 - soft)
    gold = a.copy()
    out(gold, rim_al, "shield_rim_gold.png")
    L = (0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]) / 255.0
    metals = {"silver": (np.array([0.93, 0.96, 1.02]) * 1.18, 0.0), "bronze": (np.array([1.05, 0.66, 0.40]) * 1.12, 0.0),
              "iron": (np.array([0.70, 0.75, 0.84]) * 0.92, 0.0)}
    for name, (tint, _) in metals.items():
        rgb = (L[..., None] * tint[None, None, :]) * 255.0
        out(rgb, rim_al, "shield_rim_%s.png" % name)
    fy, fx = np.where(field)
    fb = ((fx.min() - box[0]) / sw, (fy.min() - box[1]) / sh, (fx.max() - fx.min()) / sw, (fy.max() - fy.min()) / sh)
    cy = (fy.mean() - box[1]) / sh
    print("shield: %dx%d, aspect %.4f; field Rect2(%.3f, %.3f, %.3f, %.3f), its centroid at y %.3f" % (size[0], size[1], size[1] / size[0],
          fb[0], fb[1], fb[2], fb[3], cy))


def camp():
    """the four stages (0.31.197): the tall paintings as they are; each one's banners (the blue cloth, above its
    swallowtails) and fire found for clan_camp.gd"""
    banners_all = []
    fires = []
    for k in range(1, 5):
        im = Image.open(os.path.join(SRC, "camp_tall_%d.png" % k)).convert("RGB")
        assert im.size == (CAMP_W, CAMP_H), im.size
        im.save(os.path.join(OUT, "camp_%d.webp" % k), "WEBP", quality=90, method=6)
        a = np.asarray(im).astype(int)
        r, g, b = a[..., 0], a[..., 1], a[..., 2]
        blue = (b > 65) & (b < 170) & (b > r * 2.4) & (b > g * 2.1)   # (the cloth's deep blue -- not the purple sky)
        blue[:int(CAMP_H * 0.27)] = False
        blue[int(CAMP_H * 0.51):] = False
        lab, n = nd.label(nd.binary_opening(blue, iterations=2))
        found = []
        for i, sl in enumerate(nd.find_objects(lab)):
            area = int((lab[sl] == i + 1).sum())
            w = sl[1].stop - sl[1].start
            h = sl[0].stop - sl[0].start
            if area < 800 or w < 24 or h < w * 1.1 or area < 0.55 * w * h or sl[0].start < CAMP_H * 0.31 \
                    or sl[1].start < 4 or sl[1].stop > CAMP_W - 8:
                continue
            # the cloth: the longest run of columns that are cloth through its middle rows (a lake behind one: not it)
            ya, yb = sl[0].start, sl[0].stop
            mid = blue[ya + (yb - ya) // 5: ya + (yb - ya) * 3 // 5, sl[1].start:sl[1].stop].mean(0)
            best, run, start = (0, 0), 0, 0
            for x, v in enumerate(list(mid) + [0]):
                if v > 0.8:
                    if run == 0:
                        start = x
                    run += 1
                else:
                    if run > best[1]:
                        best = (start, run)
                    run = 0
            bx0 = sl[1].start + best[0]
            bx1 = bx0 + best[1]
            rows = blue[:, bx0:bx1].mean(1)
            ys = [y for y in range(ya, yb) if rows[y] > 0.6]
            if best[1] >= 20 and ys:
                found.append((bx0, min(ys), bx1 - bx0, max(ys) - min(ys)))
        found.sort()
        banners_all.append(found)
        fire = (r > 240) & (g > 150) & (b < 150)
        fire[:int(CAMP_H * 0.35)] = False
        lab2, n2 = nd.label(nd.binary_dilation(fire, iterations=4))
        sizes = nd.sum(fire, lab2, range(1, n2 + 1))
        ys, xs = np.where(lab2 == int(np.argmax(sizes)) + 1)
        fires.append((int(xs.mean()), int(ys.mean()), int(xs.max() - xs.min())))
    print("camp: 4 stages, %dx%d" % (CAMP_W, CAMP_H))
    print("const BANNERS := [")
    for f in banners_all:
        print("\t[%s]," % ", ".join("Rect2(%d, %d, %d, %d)" % bb for bb in f))
    print("]")
    print("const FIRES := [%s]" % ", ".join("Vector2(%d, %d)" % (f[0], f[1]) for f in fires))
    print("(the fires' widths: %s)" % ", ".join(str(f[2]) for f in fires))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    emblems()
    shield()
    camp()
