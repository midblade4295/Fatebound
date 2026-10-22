#!/usr/bin/env python3
"""Fatebound's social kit for Muse, Kevin's posting bot (Kevin: "Make a social media pack for my other bot" / "Just give
me a zip file with everything like graphic art, what the game is about ect that I can give to it so it posts on
socials").

Builds <out>/Fatebound-Social-Kit/ and <out>/Fatebound-Social-Kit.zip:
  START_HERE.md, links.md, game/ (overview.md, champions.md, facts.json), brand/ (voice.md, rules.md, profiles.md),
  posts/ (post_ideas.md, posts.json), assets.json (every picture and video: what it shows, its alt text, where it fits),
  art/ (logo, icon, banners, key art, post-sized key art, the 18 champions and their 18 outfits, the roster, the
  Herald's posts and his blank scrolls, screenshots, gameplay stills) and video/ (trailer 8 and five clips of it,
  16:9 and 9:16).

From: the kit's text (store-listing/muse_kit/), the champions (tools/social_champions.gd: DUMP=<json> for the facts,
its renders for the pictures), the social kit (store-listing/social/), the store images (store-listing/graphics/), the
Herald's scroll art (assets/ui/tutorial/), the key art (art_sources/social/key_art.png, via build_social_kit.py), and
trailer 8 (its master for the video, its recordings for the stills, via trailer8_edit.py).

    cd godot && python3 tools/build_muse_kit.py --out <dir> --champs <renders> --champ-json <dump.json> \
        --trailer <Fatebound-Trailer-8.mp4> --rec <trailer 8 recordings> [--no-video]
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
ROOT = os.path.dirname(GODOT)
sys.path.insert(0, HERE)
import build_social_kit as K        # noqa: E402

LISTING = os.path.join(GODOT, "store-listing")
SRC = os.path.join(LISTING, "muse_kit")
SOCIAL = os.path.join(LISTING, "social")
GRAPHICS = os.path.join(LISTING, "graphics")
LILITA = os.path.join(GODOT, "assets", "fonts", "LilitaOne-Regular.ttf")
CINZEL = os.path.join(LISTING, "tools", "fonts", "Cinzel-Black.ttf")
NUNITO = os.path.join(LISTING, "tools", "fonts", "Nunito-ExtraBold.ttf")
ROLES_ART = os.path.join(GODOT, "assets", "ui", "roles")
HERALD_ART = os.path.join(GODOT, "assets", "ui", "tutorial")
NAME = "Fatebound-Social-Kit"
INK = (8, 14, 30)
SCROLL_INK = (62, 38, 16)            # the scroll's writing (tutorial.gd INK_TEXT)
WHITE = (255, 255, 255)
CREAM = (255, 244, 214)
ROLE_NAMES = {"tank": "Tank", "fighter": "Fighter", "assassin": "Assassin", "mage": "Mage", "marksman": "Marksman",
              "support": "Support"}
ROLE_ORDER = ["tank", "fighter", "assassin", "mage", "marksman", "support"]

# Each pose of the Herald with his scroll (tutorial_poses.gd POSES: the clear part of the parchment, in its pixels)
POSES = {
    "hold": (1100, 624, (206.9, 325.6, 728.4, 239.1)),
    "lying": (989, 673, (89.0, 363.0, 734.0, 250.0)),
    "leaning": (1100, 652, (311.3, 293.7, 631.7, 266.0)),
    "sitting": (1062, 698, (78.0, 392.0, 574.0, 242.0)),
    "peeking": (1086, 678, (89.0, 299.0, 806.0, 308.0)),
    "napping": (1073, 627, (88.0, 328.0, 806.0, 238.0)),
    "pointing": (1034, 697, (69.0, 468.0, 816.0, 178.0)),
    "hanging": (1100, 579, (72.7, 230.1, 650.1, 285.0)),
}
# The Herald's posts: (file, pose, what his scroll says; the posts' text says the same, signed by him: the account may
# speak as him). Lines of his from the game (herald_intro.gd, tutorial.gd),
# word for word, except "chests" (shortened from "Win, and you'll earn chests. They wait down here, unlocking slower
# than a royal tax refund.") and "smug" (from "Ours is behind us. Theirs is at the far end, looking smug. Knock him off
# it and we win. Simple.").
HERALD_POSTS = [
    ("herald_hello", "peeking", "Oh! Hello. Didn't see you there. I'm the Royal Herald. I announce people."),
    ("herald_five", "hold", "Five heroes versus five. Three lanes. Two castles. Each with a King sitting on a very "
                            "comfortable chair."),
    ("herald_play", "pointing", "PLAY. It throws you straight into a battle. It is the most important button in the "
                                "kingdom. Please don't sit on it."),
    ("herald_chests", "sitting", "Win, and you'll earn chests. Unlocking slower than a royal tax refund."),
    ("herald_alliance", "leaning", "Five of you on one side. The enemy hates it. I adore it."),
    ("herald_smug", "lying", "Their King sits at the far end, looking smug. Knock him off his chair and we win. "
                             "Simple."),
    ("herald_dress", "hanging", "Dress to impress. Or at least to intimidate."),
    ("herald_nap", "napping", "I'll be right here. Napping. Heroically."),
]

# Gameplay stills: (file, trailer 8 time, what it shows). Full 16:9 frames of its recordings, graded like the trailer.
STILLS = [
    ("01_the_rift", 3.0, "The Rift at golden hour, seen from above our castle: green fields, rocky ridges and towers "
                         "along the lanes, the enemy castle far away on the horizon."),
    ("02_their_king", 7.0, "Their King, round and red-cheeked with a gold crown and a sceptre, sits on his red throne "
                           "in front of his castle wall, between two royal banners."),
    ("03_the_charge", 11.5, "Five heroes charge down the lane toward the camera: the Stormcaller, the Dragoon, the "
                            "Knight, the Archmage and the stone Golem, with their castle behind them."),
    ("04_the_clash", 16.0, "Both teams clash in the river ford, a glowing golden circle on the ground and spells "
                           "flying."),
    ("05_meteors", 17.6, "Over the Archmage's shoulder: a meteor bursts in the lane in a ball of fire and enemy heroes "
                         "are thrown into the air."),
    ("06_dragon_dive", 19.0, "The Dragoon leaps high into the evening sky, his lance raised, before his Dragon Dive "
                             "comes crashing down; an enemy Barbarian waits below."),
    ("07_landslide", 21.0, "The stone Golem rolls through the enemy team with his Landslide, heroes flying into the "
                           "air around him."),
    ("08_the_duel", 22.0, "The Knight and the Barbarian face off up close, sword against a bear-hide giant."),
    ("09_the_breach", 26.5, "Our heroes pour through the broken gate of the enemy castle; a wizard in a starry hat in "
                            "the foreground."),
    ("10_grave_wyrm", 35.5, "At dusk the Grave Wyrm, a huge glowing skeletal dragon, rises out of its pit with its "
                            "wings spread."),
]

# Trailer 8's clips: (file, from, to, what it shows, the Herald's lines in it)
CLIPS = [
    ("clip_01_opening", 0.0, 15.2, "Over our castle and down the lane; their King on his throne; our five heroes "
                                   "charging at the camera in slow motion.",
     "Two kingdoms. One crown. Rally your team."),
    ("clip_02_battle", 15.2, 25.2, "The drums hit: both teams clash at the ford, then the Archmage's meteors, the "
                                   "Dragoon's dive, the Golem's landslide, the Knight against the Barbarian, and a tower "
                                   "coming down.", "Eighteen champions. Break their towers."),
    ("clip_03_breach", 25.2, 30.6, "Their gate smashed in, our heroes pouring through it toward their King on his "
                                   "throne.", "Topple their King."),
    ("clip_04_grave_wyrm", 30.6, 40.19, "Dusk at the pit: the ground shakes, the Grave Wyrm rises, rears up and roars, "
                                        "pouring soul-fire at the camera.",
     "But deep in its pit... the Grave Wyrm wakes."),
    ("clip_05_title", 40.19, 47.2, "Lightning splits the dark and the FATEBOUND logo slams in with its crown and "
                                   "flags, then 5V5 HERO BATTLES.", "Fatebound. Five-on-five hero battles."),
]

# One line about each champion, from his story (champions.gd) -- the hook for his spotlight
HOOKS = {
    "knight": "Held a bridge alone for a night and a day. Borrowed sword. Shield cracked in three places.",
    "barbarian": "Wrestled the great bear of Frostfang Pass with his bare hands, and wore it home.",
    "rogue": "Nobody in Thornwood knows Wren's face. Only the green hood, and the purse that went missing just after.",
    "ranger": "Splits apples off fence posts at a hundred paces.",
    "mage": "Set her first spellbook on fire by accident. And her second on purpose.",
    "priest": "The abbey's bell-ringer. When the shadow plague came, he kept ringing, and the light came with him.",
    "crusader": "The only one to come back from the Dawn Order's last charge, carrying its hammer and its banner both.",
    "berserker": "Left for dead on four battlefields. Walked off every one of them.",
    "assassin": "Raised by the Veiled Court to be sold like a blade. Chose not to be.",
    "sniper": "Once shot the rope off a hanging bell from across Wolfden Valley.",
    "archmage": "Three hundred years counting falling stars. Now they fall where he points.",
    "necromancer": "The gravekeeper of Morrow Hill. One night the dead began to whisper to him. He listens to them still.",
    "golem": "Slept in the side of Mount Kharum for a thousand years, until a war woke him with its noise.",
    "dragoon": "The last dragon rider of Skyreach. When he comes down out of the sky, he comes down like a dragon.",
    "duelist": "Four hundred duels in the courts of Montclair. Never lost. Never took off the mask.",
    "stormcaller": "Climbed the Thunder Peaks to ask the storm a question. It answered by striking him nine times.",
    "musketeer": "Kept his hat, his musket and his manners. Never fires a shot without tipping his hat first.",
    "druid": "Found as a child asleep in the roots of the oldest tree in the Old Grove. The forest raised her.",
}

# Each champion's painted place (his window's backdrop, art_sources/champions/prompts.json), for the alt text
PLACES = {
    "knight": "front of a castle gate at dawn, blue banners on its towers",
    "barbarian": "a snowy mountain camp at night, a roaring bonfire and a timber longhouse",
    "rogue": "a deep forest at dusk, mossy roots, rope bridges and a hanging lantern",
    "ranger": "a forest archery range in golden afternoon light",
    "mage": "a library of tall bookshelves, a starry round window, floating candles and a blazing fireplace",
    "priest": "a sunlit cathedral of white and gold with stained-glass windows",
    "crusader": "a white stone sanctuary at sunrise, golden sun banners and a stairway to a chapel",
    "berserker": "a scorched battlefield under a blood-red sunset, broken shields and spears in the ground",
    "assassin": "a city rooftop at night under a crescent moon, red paper lanterns strung across",
    "sniper": "an autumn valley in the early morning, a log lodge and a lookout platform",
    "archmage": "an observatory under a sky full of stars and comets, a great brass telescope",
    "necromancer": "a moonlit graveyard by an open crypt glowing green, candles on the tombstones",
    "golem": "ancient ruins of stone pillars carved with glowing ice-blue runes, a waterfall beyond",
    "dragoon": "ruined towers above the clouds at sunset, wind-torn red banners and an abandoned giant nest",
    "duelist": "a palace duelling hall, a marble floor, red curtains, a chandelier and rose petals",
    "stormcaller": "a ring of standing stones with glowing blue runes under a thunderstorm",
    "musketeer": "a sea fort's wall with bronze cannons, sailing ships in the bay",
    "druid": "an enchanted grove, a giant glowing tree, mossy standing stones and fireflies",
}

assets = []                                   # assets.json


def asset(path, kind, shows, alt, best_for, **kw):
    full = os.path.join(KIT, path)
    e = {"file": path, "kind": kind, "shows": shows, "alt": alt, "best_for": best_for}
    if path.endswith((".png", ".jpg")):
        w, h = Image.open(full).size
        e["size"] = "%dx%d" % (w, h)
    e["bytes"] = os.path.getsize(full)
    e.update(kw)
    assets.append(e)


def cap(s):
    # "HUNTER'S MARK" -> "Hunter's Mark"
    return " ".join(w[:1].upper() + w[1:].lower() for w in s.split())


def tidy(s):
    # the game's text writes a dash as " -- "
    return s.replace(" -- ", " \u2014 ")


def font(path, px):
    return ImageFont.truetype(path, int(px))


def save_jpg(im, path, q=92):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.convert("RGB").save(path, quality=q, subsampling=0, optimize=True)


def wrap(d, text, f, width):
    lines, cur = [], ""
    for w in text.split():
        t = (cur + " " + w).strip()
        if d.textlength(t, font=f) <= width or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def fit(d, text, path, box_w, box_h, hi, lo=14, spacing=1.18):
    for px in range(int(hi), int(lo) - 1, -1):
        f = font(path, px)
        ls = wrap(d, text, f, box_w)
        if len(ls) * px * spacing <= box_h and all(d.textlength(s, font=f) <= box_w for s in ls):
            return f, ls, px
    f = font(path, lo)
    return f, wrap(d, text, f, box_w), lo


def text_c(d, cx, y, s, f, fill, stroke=0, stroke_fill=INK):
    w = d.textlength(s, font=f)
    d.text((cx - w / 2, y), s, font=f, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)


def logo_img(h):
    lg = K.logo()
    return lg.resize((int(round(h * lg.width / lg.height)), int(h)), Image.LANCZOS)


# ---------------- the champions ----------------
def champion_card(raw, top, name, sub, quote, badge):
    """a 1080 x 1350 card: his render (his place, him in 3D), the logo over the top, and under him a small line (the
    class and role, with the role's badge), his name, his title and his line"""
    c = Image.open(raw).convert("RGBA")
    W, H = c.size
    # a darker foot for the text (the window's own shade already darkens it)
    g = Image.new("L", (1, H), 0)
    for y in range(H):
        t = max(0.0, (y / H - 0.60) / 0.25)
        g.putpixel((0, y), int(255 * min(1.0, t) * 0.55))
    c.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (W, H), INK).split(), g.resize((W, H)))))
    lg = logo_img(118)
    c.alpha_composite(lg, ((W - lg.width) // 2, 26))
    d = ImageDraw.Draw(c)
    y = int(H * 0.705)
    f = font(LILITA, 34)
    tw = d.textlength(top, font=f)
    bx = (W - tw) / 2
    if badge is not None:
        b = Image.open(badge).convert("RGBA")
        b = b.resize((44, int(round(44 * b.height / b.width))), Image.LANCZOS)
        bx = (W - tw - 54) / 2
        c.alpha_composite(b, (int(bx), y - 4))
        bx += 54
    d.text((bx, y), top, font=f, fill=WHITE, stroke_width=3, stroke_fill=INK)
    y += 46
    fn, ls, px = fit(d, name, LILITA, W - 90, 100, 92, 40)
    for s in ls:
        text_c(d, W / 2, y, s, fn, WHITE, stroke=max(3, px // 14))
        y += int(px * 1.06)
    y += 6
    fs, ls, px = fit(d, sub, CINZEL, W - 120, 56, 40, 22)
    for s in ls:
        text_c(d, W / 2, y, s, fs, CREAM, stroke=3)
        y += int(px * 1.2)
    if quote:
        y += 14
        fq, ls, px = fit(d, "“" + quote + "”", NUNITO, W - 160, H - 40 - y, 36, 22)
        for s in ls:
            text_c(d, W / 2, y, s, fq, (220, 228, 245), stroke=2)
            y += int(px * 1.2)
    bar = K.fire_ice_bar(360, 6)
    c.alpha_composite(bar, ((W - 360) // 2, H - 30))
    return c.convert("RGB")


def champions(data, renders):
    out = []
    for ch in data["champions"]:
        hid = ch["id"]
        raw = os.path.join(renders, hid + ".png")
        role = ch["role"]
        badge = os.path.join(ROLES_ART, role + ".png")
        top = "%s  ·  %s" % (ch["class"].upper(), ROLE_NAMES[role].upper())
        card = champion_card(raw, top, ch["name"].upper(), ch["title"], ch["quote"], badge)
        p = "art/champions/%s.jpg" % hid
        save_jpg(card, os.path.join(KIT, p))
        alt = "%s, %s: the %s (%s) standing in 3D in %s. Text: %s, %s, “%s”" % (
            ch["name"], ch["title"], ch["class"], ROLE_NAMES[role].lower(), ch["place"], ch["name"], ch["title"],
            ch["quote"])
        asset(p, "champion card (the game's own champion window, its buttons hidden; text added)",
              "%s, %s: the %s, %s %s" % (ch["name"], ch["title"], ch["class"], "an" if role == "assassin" else "a",
                                          ROLE_NAMES[role].lower()), alt,
              ["instagram (4:5)", "facebook", "x", "threads", "bluesky"], champion=hid)
        pc = "art/champions/clean/%s.jpg" % hid
        save_jpg(Image.open(raw), os.path.join(KIT, pc))
        asset(pc, "champion picture, no text (the game's own champion window, its buttons hidden)",
              "%s, the %s, in the default look" % (ch["name"], ch["class"]),
              "The %s standing in 3D in %s." % (ch["class"], ch["place"]),
              ["instagram (4:5)", "your own layouts"], champion=hid)
        if ch.get("outfit_id"):
            raw2 = os.path.join(renders, ch["outfit_id"] + ".png")
            oname = ("%s %s" % (ch["outfit"], ch["class"])).upper()
            card = champion_card(raw2, "EPIC OUTFIT", oname, ch["name"], "", None)
            p2 = "art/outfits/%s.jpg" % ch["outfit_id"]
            save_jpg(card, os.path.join(KIT, p2))
            asset(p2, "outfit card (the game's own champion window, its buttons hidden; text added)",
                  "The %s outfit for the %s (%s): an epic outfit with a weapon of its own" % (
                      ch["outfit"], ch["class"], ch["name"]),
                  "The %s in the %s outfit, standing in 3D in %s. Text: Epic outfit, %s %s, %s." % (
                      ch["class"], ch["outfit"], ch["place"], ch["outfit"], ch["class"], ch["name"]),
                  ["instagram (4:5)", "facebook", "x"], champion=hid, outfit=ch["outfit"])
        out.append(ch)
    roster(data, renders)


def roster(data, renders):
    """all 18 on one 1080 x 1350 picture, a column a role (tank, fighter, assassin, mage, marksman, support)"""
    W, H = 1080, 1350
    c = Image.new("RGBA", (W, H), INK + (255,))
    art = Image.open(K.KEY_ART).convert("RGB")
    bg = art.resize((int(H * art.width / art.height), H), Image.LANCZOS)
    bg = bg.crop(((bg.width - W) // 2, 0, (bg.width - W) // 2 + W, H))
    bg = Image.fromarray((np.asarray(bg.filter(ImageFilter.GaussianBlur(30))).astype(np.float32) * 0.32).astype(np.uint8))
    c.paste(bg)
    lg = logo_img(150)
    c.alpha_composite(lg, ((W - lg.width) // 2, 24))
    d = ImageDraw.Draw(c)
    text_c(d, W / 2, 190, "18 CHAMPIONS", font(LILITA, 64), WHITE, stroke=5)
    text_c(d, W / 2, 268, "Six roles. Pick yours.", font(NUNITO, 30), (220, 228, 245), stroke=2)
    cw, gap = 170, 6
    x0 = (W - (6 * cw + 5 * gap)) // 2
    by = {r: [] for r in ROLE_ORDER}
    for ch in data["champions"]:
        by[ch["role"]].append(ch)
    ch_h = 290
    for i, r in enumerate(ROLE_ORDER):
        x = x0 + i * (cw + gap)
        y = 330
        b = Image.open(os.path.join(ROLES_ART, r + ".png")).convert("RGBA")
        b = b.resize((40, int(round(40 * b.height / b.width))), Image.LANCZOS)
        c.alpha_composite(b, (x + (cw - 40) // 2, y))
        text_c(d, x + cw / 2, y + 44, ROLE_NAMES[r].upper(), font(LILITA, 26), WHITE, stroke=3)
        y += 84
        for ch in by[r]:
            im = Image.open(os.path.join(renders, ch["id"] + ".png")).convert("RGB")
            # him: the middle of the stage (the render's x 250..830, y 140..1048: the cell's 170 x 266)
            crop = im.crop((250, 140, 830, 1048)).resize((cw, ch_h - 34), Image.LANCZOS)
            m = Image.new("L", crop.size, 0)
            ImageDraw.Draw(m).rounded_rectangle((0, 0, crop.width - 1, crop.height - 1), 14, fill=255)
            c.paste(crop, (x, y), m)
            ImageDraw.Draw(c).rounded_rectangle((x, y, x + cw - 1, y + crop.height - 1), 14, outline=(255, 255, 255, 70),
                                                width=2)
            d = ImageDraw.Draw(c)
            fn, ls, px = fit(d, ch["class"].upper(), LILITA, cw - 8, 30, 25, 14)
            text_c(d, x + cw / 2, y + crop.height + 4, ls[0], fn, WHITE, stroke=2)
            y += ch_h
    bar = K.fire_ice_bar(420, 7)
    c.alpha_composite(bar, ((W - 420) // 2, H - 36))
    p = "art/champions/roster_18_champions.jpg"
    save_jpg(c, os.path.join(KIT, p))
    asset(p, "roster (the champions' renders, arranged)", "All 18 champions, in six columns by role",
          "The Fatebound logo over '18 CHAMPIONS - Six roles. Pick yours.' and all 18 champions in six columns: tanks "
          "(Knight, Crusader, Golem), fighters (Barbarian, Berserker, Dragoon), assassins (Rogue, Assassin, Duelist), "
          "mages (Mage, Archmage, Stormcaller), marksmen (Archer, Ranger, Musketeer) and supports (Priest, Necromancer, "
          "Druid).", ["instagram (4:5)", "facebook", "x"])


# ---------------- the Herald ----------------
def herald():
    for pose in POSES:
        src = os.path.join(HERALD_ART, "scroll_%s.png" % pose)
        p = "art/herald/herald_scroll_%s.png" % pose
        os.makedirs(os.path.join(KIT, "art/herald"), exist_ok=True)
        shutil.copy(src, os.path.join(KIT, p))
        w, h, tr = POSES[pose]
        asset(p, "template (see-through PNG, the game's own tutorial art)",
              "The Royal Herald (%s) with his blank scroll, to write on" % pose,
              "The Royal Herald, a moustached royal announcer in a blue and gold tunic and a feathered cap, with a "
              "blank parchment scroll.", ["your own layouts"],
              write_here="x %d, y %d, %d x %d px (the clear part of the parchment; dark brown text #3E2610)" % (
                  round(tr[0]), round(tr[1]), round(tr[2]), round(tr[3])))
    art = Image.open(K.KEY_ART).convert("RGB")
    for (name, pose, line) in HERALD_POSTS:
        W = H = 1080
        bg = art.resize((int(H * art.width / art.height), H), Image.LANCZOS)
        bg = bg.crop(((bg.width - W) // 2, 0, (bg.width - W) // 2 + W, H)).filter(ImageFilter.GaussianBlur(26))
        bg = Image.fromarray((np.asarray(bg).astype(np.float32) * 0.42).astype(np.uint8)).convert("RGBA")
        sc = Image.open(os.path.join(HERALD_ART, "scroll_%s.png" % pose)).convert("RGBA")
        w, h, (tx, ty, tw, th) = POSES[pose]
        k = 1000.0 / w
        sc = sc.resize((1000, int(round(h * k))), Image.LANCZOS)
        ox, oy = (W - sc.width) // 2, max(30, (H - 150 - sc.height) // 2)
        sh = Image.new("RGBA", bg.size, (0, 0, 0, 0))
        a = sc.split()[3].point(lambda v: int(v * 0.6))
        sh.paste(Image.merge("RGBA", (*Image.new("RGB", sc.size, (0, 0, 0)).split(), a)), (ox, oy + 12))
        bg.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))
        bg.alpha_composite(sc, (ox, oy))
        d = ImageDraw.Draw(bg)
        bw, bh = tw * k, th * k
        f, ls, px = fit(d, line, NUNITO, bw * 0.88, bh * 0.92, 64, 22, 1.2)       # (clear of the wax seal)
        y = oy + ty * k + (bh - len(ls) * px * 1.2) / 2
        for s in ls:
            text_c(d, ox + (tx + tw / 2) * k, y, s, f, SCROLL_INK)
            y += px * 1.2
        lg = logo_img(118)
        bg.alpha_composite(lg, ((W - lg.width) // 2, H - lg.height - 28))
        p = "art/posts/%s.jpg" % name
        save_jpg(bg, os.path.join(KIT, p))
        asset(p, "post (the game's own Herald art; text added)", "The Royal Herald: “%s”" % line,
              "The Royal Herald, a moustached royal announcer in a blue and gold tunic and a feathered cap, with his "
              "parchment scroll reading: %s The Fatebound logo below." % line,
              ["instagram (1:1)", "x", "threads", "bluesky", "facebook"], says=line)


# ---------------- key art in post sizes ----------------
POST_SIZES = {
    "key_art_square_1080x1080": dict(size=(1080, 1080), view=("band", 0.0, 1.0, (0, 330, 1080, 938)), logo=(0.27, 0.035),
                                     line=True),
    "key_art_portrait_1080x1350": dict(size=(1080, 1350), view=("band", 0.0, 1.0, (-170, 380, 1250, 1180)),
                                       logo=(0.215, 0.05), line=True),
    "key_art_story_1080x1920": dict(size=(1080, 1920), view=("band", 0.0, 1.0, (-400, 600, 1480, 1660)),
                                    logo=(0.17, 0.12), line=True),
}


def key_art():
    art = Image.open(K.KEY_ART).convert("RGB")
    bare = K.uncrown(art)
    lg = K.logo()
    for name, spec in POST_SIZES.items():
        im = K.banner(art, bare, lg, spec)
        p = "art/posts/%s.jpg" % name
        save_jpg(im, os.path.join(KIT, p))
        asset(p, "key art (illustrated)", "The key art with the logo and 5V5 HERO BATTLES",
              "The Fatebound logo over illustrated key art: a blue-armoured Knight and a fur-clad Barbarian clash in the "
              "middle over a crackling rift of ice and fire, their armies and castles on either side. Text: 5V5 HERO "
              "BATTLES.", {"key_art_square_1080x1080": ["instagram (1:1)", "facebook", "x"],
                           "key_art_portrait_1080x1350": ["instagram (4:5)", "facebook"],
                           "key_art_story_1080x1920": ["instagram story", "tiktok photo", "facebook story"]}[name])


# ---------------- copies: logo, icon, banners, key art, screenshots ----------------
def copies(listing):
    def cp(src, dst):
        os.makedirs(os.path.dirname(os.path.join(KIT, dst)), exist_ok=True)
        shutil.copy(src, os.path.join(KIT, dst))
    for w in (1400, 700):
        p = "art/logo/logo_transparent_%d.png" % w
        cp(os.path.join(SOCIAL, "icons", "logo_transparent_%d.png" % w), p)
        asset(p, "logo (see-through PNG)", "The FATEBOUND logo", "The Fatebound logo: FATE in icy blue and BOUND in "
              "fiery orange, split by a crackling rift, a gold crown on top and a blue and a red flag either side.",
              ["over your own pictures and video"])
    for n in (1080, 800, 512, 400, 256):
        p = "art/icon/avatar_%d.png" % n
        cp(os.path.join(SOCIAL, "icons", "avatar_%d.png" % n), p)
        asset(p, "icon (the app icon)", "The game's icon, for profile pictures",
              "The Fatebound icon: a Knight and a Barbarian clashing over a rift of ice and fire under a gold crown.",
              {1080: ["instagram", "tiktok", "facebook", "threads", "bluesky"], 800: ["youtube"],
               512: ["discord"], 400: ["x"], 256: ["twitch", "reddit"]}[n])
    cp(os.path.join(SOCIAL, "icons", "icon_square_1024.png"), "art/icon/icon_square_1024.png")
    asset("art/icon/icon_square_1024.png", "icon (the app icon)", "The game's icon at full size",
          "The Fatebound icon: a Knight and a Barbarian clashing over a rift of ice and fire under a gold crown.",
          ["anywhere the icon is wanted"])
    where = {"x_header_1500x500": ["x header", "bluesky header", "reddit banner"],
             "youtube_banner_2560x1440": ["youtube banner"], "facebook_cover_1640x624": ["facebook cover"],
             "twitch_banner_1200x480": ["twitch banner"], "discord_server_banner_960x540": ["discord server banner"],
             "discord_profile_banner_680x240": ["discord profile banner"],
             "share_card_1200x630": ["link previews (og:image)", "press"]}
    for name, best in where.items():
        p = "art/banners/%s.png" % name
        cp(os.path.join(SOCIAL, "banners", name + ".png"), p)
        asset(p, "banner (illustrated key art)", "The key art with the logo, cut for a profile banner",
              "The Fatebound logo over illustrated key art: a Knight and a Barbarian clashing over a rift of ice and fire, "
              "their armies and castles on either side.", best)
    for name in ("key_art_1920x1080", "key_art_clean_1920x1080"):
        p = "art/key_art/%s.png" % name
        cp(os.path.join(SOCIAL, "banners", name + ".png"), p)
        clean = "clean" in name
        asset(p, "key art (illustrated)", "The key art" + (" as drawn, with its crown, no logo" if clean else
                                                       " with the logo and 5V5 HERO BATTLES"),
              "Illustrated key art: a blue-armoured Knight and a fur-clad Barbarian clash over a crackling rift of ice and "
              "fire%s, their armies and castles on either side%s." % (
                  " under a gold crown" if clean else "", "" if clean else ", the Fatebound logo above and 5V5 HERO "
                                                                          "BATTLES below"),
              ["x", "facebook", "youtube thumbnail", "press"] if not clean else ["your own layouts"])
    p = "art/key_art/feature_graphic_1024x500.png"
    cp(os.path.join(GRAPHICS, "feature_graphic_1024x500.png"), p)
    asset(p, "store feature graphic (the game's engine, no controls)", "The FATEBOUND title over a 5v5 fight",
          "The Fatebound logo over a 5v5 fight on the Rift.", ["x", "facebook", "link previews"])
    shots = json.load(open(os.path.join(LISTING, "listing", "listing.json")))["phone_screenshots"]
    for s in shots:
        s["shows"] = tidy(s["shows"])
        src = os.path.join(LISTING, s["file"])
        base = os.path.splitext(os.path.basename(s["file"]))[0]
        key = base.split("_", 1)[1]
        ingame = key not in ("king", "wyrm")         # (those two: the game's engine, a camera of its own, no HUD)
        p = "art/screenshots/%s.jpg" % base
        save_jpg(Image.open(src), os.path.join(KIT, p))
        asset(p, "store screenshot (the game as it plays%s; caption added)" % (
            "" if ingame else ": in-engine, no controls"),
              "%s: %s" % (s["headline"], s["subline"]),
              "Caption: %s. %s. The picture: %s." % (s["headline"], s["subline"], s["shows"]),
              ["instagram story", "tiktok photo", "facebook story", "x"], caption=s["headline"])
        raw = os.path.join(GRAPHICS, "raw_renders", "%s_play.webp" % key)
        if os.path.exists(raw):
            p2 = "art/screenshots/clean/%s.jpg" % base
            save_jpg(Image.open(raw), os.path.join(KIT, p2))
            asset(p2, "screenshot, no caption (the game as it plays%s)" % ("" if ingame else
                                                                            ": in-engine, no controls"),
                  s["shows"], "The picture: %s." % s["shows"], ["instagram story", "tiktok photo", "your own layouts"])


# ---------------- gameplay stills (from trailer 8's recordings) ----------------
def stills(rec):
    import trailer8_edit as T
    vig = T.vignette()
    for (name, t, shows) in STILLS:
        for (a, b, run, rin) in T.CUTS:
            if a <= t < b:
                fr = next(T.frames_of(os.path.join(rec, run + ".avi"),
                                      T.avi_frame(rec, run, rin) + int(round((t - a) * T.FPS)), 1))
                f = T.grade(fr.astype(np.float32) / 255.0, vig)
                p = "art/gameplay_stills/%s.jpg" % name
                save_jpg(Image.fromarray((f * 255 + 0.5).astype(np.uint8)), os.path.join(KIT, p), 93)
                asset(p, "gameplay still (staged in the game's engine, a cinematic camera, no controls; from trailer 8)",
                      shows, shows, ["x", "facebook", "reddit", "youtube community", "instagram (crop to 4:5)"])
                break


# ---------------- video ----------------
TITLE_AT = 40.19                    # trailer 8's title: the lightning, then the logo (trailer8_edit.py B_AT)


def overlay_png(path):
    """the vertical videos' frame: the logo up top, the tagline over its fire-and-ice bar at the foot"""
    W, H = 1080, 1920
    c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    lg = logo_img(300)
    c.alpha_composite(lg, ((W - lg.width) // 2, 250))
    d = ImageDraw.Draw(c)
    f = font(LILITA, 84)
    tw = d.textlength(K.LINE, font=f)
    d.text(((W - tw) / 2, 1450), K.LINE, font=f, fill=WHITE, stroke_width=7, stroke_fill=INK)
    bar = K.fire_ice_bar(int(tw * 0.8), 10)
    c.alpha_composite(bar, (int((W - bar.width) / 2), 1556))
    c.save(path)


def ffmpeg(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + args, check=True)


def video(trailer, work, encode=True):
    os.makedirs(os.path.join(KIT, "video", "landscape"), exist_ok=True)
    os.makedirs(os.path.join(KIT, "video", "vertical"), exist_ok=True)
    ov = os.path.join(work, "vertical_overlay.png")
    overlay_png(ov)
    enc = ["-c:v", "libx264", "-preset", "slow", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
           "-movflags", "+faststart"]
    # (bitrates kept to what the sites recommend for 1080p -- they re-encode anyway -- so the zip stays small enough to
    # hand over: 8 Mbps the trailer, 6 the clips, 4 the vertical ones, whose middle is a 1080 x 603 strip)
    # the trailer is 2.39:1 inside 16:9 (138 px bars); the vertical one shows the middle 1440 x 804 of it, 1080 wide,
    # over a blurred, darker copy of itself, the logo above and the tagline below
    vf_v = ("[0:v]crop=1920:804:0:138,split[a][b];"
            "[a]scale=-2:1920,crop=1080:1920,boxblur=24:2,eq=brightness=-0.22:saturation=0.8[bg];"
            "[b]crop=1440:804:240:0,scale=1080:603[fg];"
            "[bg][fg]overlay=0:658[m];[m][1:v]overlay=0:0:enable='lt(t,%.3f)',format=yuv420p[v]")
    items = [("Fatebound-Trailer", 0.0, 47.2, "Trailer 8: the full 47-second trailer, narrated by the Royal Herald.",
              "Two kingdoms. One crown. Rally your team. Eighteen champions. Break their towers. Topple their King. But "
              "deep in its pit... the Grave Wyrm wakes. Fatebound. Five-on-five hero battles.")] + CLIPS
    for (name, a, b, shows, says) in items:
        dur = b - a
        full = name == "Fatebound-Trailer"
        af = "afade=t=in:d=0.08,afade=t=out:st=%.3f:d=0.45" % max(0.0, dur - 0.45) if not full else "anull"
        vfade = "" if full else ",fade=t=out:st=%.3f:d=0.3" % max(0.0, dur - 0.3)
        lp = "video/landscape/%s.mp4" % name
        if encode:
            ffmpeg(["-ss", "%.3f" % a, "-t", "%.3f" % dur, "-i", trailer, "-vf", "format=yuv420p" + vfade, "-af", af,
                    "-crf", "21", "-maxrate", "8M" if full else "6M", "-bufsize", "16M"] + enc + [os.path.join(KIT, lp)])
        asset(lp, "video (trailer 8: staged in the game's engine, cinematic cameras, no controls)", shows,
              shows + " The Herald says: “%s”" % says,
              ["youtube", "x", "facebook", "reddit", "discord"] if full else ["x", "facebook", "reddit", "discord"],
              seconds=round(dur, 2), size="1920x1080 (2.39:1 letterboxed)", herald_says=says)
        vp = "video/vertical/%s-vertical.mp4" % name
        # (the logo and tagline over it until the title comes in: the trailer's own then)
        ov_end = max(0.0, min(dur, TITLE_AT - a))
        if encode:
            ffmpeg(["-ss", "%.3f" % a, "-t", "%.3f" % dur, "-i", trailer, "-loop", "1", "-t", "%.3f" % dur, "-i", ov,
                    "-filter_complex", vf_v % ov_end + ("" if full else ";[v]fade=t=out:st=%.3f:d=0.3[v2]" % max(0.0, dur - 0.3)),
                    "-map", "[v]" if full else "[v2]", "-map", "0:a", "-af", af, "-crf", "23", "-maxrate", "4M",
                    "-bufsize", "8M", "-r", "30"] + enc + [os.path.join(KIT, vp)])
        asset(vp, "video, vertical 9:16 (trailer 8, its middle, over a blurred copy, logo and tagline added)", shows,
              shows + " The Fatebound logo above, 5V5 HERO BATTLES below. The Herald says: “%s”" % says,
              ["tiktok", "instagram reels", "youtube shorts", "facebook reels"], seconds=round(dur, 2),
              size="1080x1920", herald_says=says)


# ---------------- the text ----------------
def champions_md(data):
    L = ["# The 18 champions", "",
         "Every name, title, story, line and ability here is the game's own (version %s). Quote them exactly. "
         "Pictures: `art/champions/<id>.jpg` (with text), `art/champions/clean/<id>.jpg` (without), "
         "`art/outfits/<outfit>.jpg` (each one's epic outfit), `art/champions/roster_18_champions.jpg` (all of them)."
         % data["version"], "",
         "## The six roles", ""]
    for r in ROLE_ORDER:
        names = ", ".join(c["class"] for c in data["champions"] if c["role"] == r)
        L.append("- **%s** (%s): %s" % (ROLE_NAMES[r], names, data["roles"][r]))
    L += ["", "**12 are yours from the start:** %s. **6 are unlocked in the game:** %s. Each week two of those six are in a rotation "
          "everyone can play." % (", ".join(c["class"] for c in data["champions"] if c["starter"]),
                          ", ".join(c["class"] for c in data["champions"] if not c["starter"])), "",
          "Note: the **Archer** and the **Ranger** are two different champions (the Archer is Kestrel Finn, the "
          "Ranger is Hollis Thorne).", "",
          "| Champion | Name | Title | Role | Line |", "|---|---|---|---|---|"]
    for c in data["champions"]:
        L.append("| %s | %s | %s | %s | “%s” |" % (c["class"], c["name"], c["title"], ROLE_NAMES[c["role"]],
                                                         c["quote"]))
    for c in data["champions"]:
        k = c["abilities"]
        L += ["", "## %s, %s" % (c["name"], c["title"]),
              "**The %s** · %s · %s · id `%s`" % (
                  c["class"], ROLE_NAMES[c["role"]], "yours from the start" if c["starter"] else "unlocked in the game",
                  c["id"]), "",
              c["lore"], "", "> “%s”" % c["quote"], "",
              "- **Q %s** (level 1): %s" % (cap(k["q"]["name"]), k["q"]["text"]),
              "- **W %s** (level 2): %s" % (cap(k["w"]["name"]), k["w"]["text"]),
              "- **E %s** (level 3): %s" % (cap(k["e"]["name"]), k["e"]["text"]),
              "- **R %s** (the ultimate, level 6): %s" % (cap(k["r"]["name"]), k["r"]["text"]),
              "- **Epic outfit:** %s %s (a new look and a weapon of its own). Also a Frostbound outfit." % (
                  c["outfit"], c["class"]),
              "- **Pictures:** `art/champions/%s.jpg`, `art/champions/clean/%s.jpg`, `art/outfits/%s.jpg`" % (
                  c["id"], c["id"], c["outfit_id"])]
    open(os.path.join(KIT, "game", "champions.md"), "w").write("\n".join(L) + "\n")


def facts_json(data):
    listing = json.load(open(os.path.join(LISTING, "listing", "listing.json")))
    f = {"game": "Fatebound", "store_name": listing["app_name"], "tagline": "5V5 HERO BATTLES",
         "one_line": "Fatebound is a fast 5v5 hero battle game (a MOBA) made for phones: pick a champion, push down the "
                     "lanes and knock their King off his throne.",
         "short_description": listing["short_description"], "full_description": listing["full_description"],
         "status": "Not released yet. Coming to Android (Google Play) and iPhone and iPad (App Store). No release date "
                   "announced: never guess one.",
         "version": data["version"], "developer": "A solo indie developer (Kevin).", "engine": "Godot",
         "facts": listing["game_facts"], "roles": data["roles"], "champions": data["champions"],
         "never_say": ["a release date or 'soon'", "a link not in links.md", "prices, 'free', 'free-to-play', "
                       "'no pay-to-win', anything about ads or purchases", "download, player or review numbers",
                       "other games' or companies' names", "platforms besides Android and iPhone/iPad",
                       "modes besides 5v5 (online, or against bots)", "the old tagline 'Steal their King. Save yours.'",
                       "that the art, music or voices are hand-made"]}
    json.dump(f, open(os.path.join(KIT, "game", "facts.json"), "w"), indent=2, ensure_ascii=False)


def posts(data):
    P = []
    tags = "#Fatebound"

    def add(pid, pillar, media, short, long, video=None, extra_tags=(), notes=""):
        e = {"id": pid, "pillar": pillar, "media": media, "short": short, "long": long,
             "hashtags": [tags] + list(extra_tags)}
        if video:
            e["video_caption"] = video
        if notes:
            e["notes"] = notes
        P.append(e)

    tr = "video/landscape/Fatebound-Trailer.mp4"
    trv = "video/vertical/Fatebound-Trailer-vertical.mp4"
    add("trailer", "the trailer", [tr, trv],
        "Two kingdoms. One crown. The Fatebound trailer, narrated by the Royal Herald. ⚔️\U0001f451",
        "Two kingdoms. One crown. Eighteen champions.\n\nThe Fatebound trailer, narrated by our very own Royal Herald, "
        "who would like it known he did this between naps.\n\nFast 5v5 hero battles, made for your phone.",
        "Two kingdoms. One crown. \U0001f451 #Fatebound", ["#MOBA", "#IndieGame"],
        "Pin it. Landscape for YouTube, X, Facebook; vertical for TikTok, Reels, Shorts.")
    add("key_art", "the game", ["art/posts/key_art_square_1080x1080.jpg", "art/key_art/key_art_1920x1080.png"],
        "Their King sits on a very comfortable chair. Knock him off it. \U0001f451 Fatebound: 5v5 hero battles.",
        "Their King sits on a very comfortable chair. Knock him off it.\n\nFatebound is a fast 5v5 hero battle game made "
        "for your phone. Pick a champion, team up with four others, push down three lanes past the enemy towers and "
        "topple their King before they topple yours.", None, ["#MOBA", "#5v5", "#MobileGame"])
    add("the_rift", "the Rift", ["art/gameplay_stills/01_the_rift.jpg"],
        "Three lanes. Three towers in each. Two more by the King. And at the very end, one very comfortable chair.",
        "This is the Rift.\n\nThree lanes, three towers in each, and two more guarding the King. Minion waves march down "
        "every lane, jungle camps hide between them, and two epic monsters sleep in their pits.\n\nEvery match is a "
        "fresh fight of up to 20 minutes.", None, ["#MOBA", "#IndieGame"])
    add("their_king", "the King", ["art/gameplay_stills/02_their_king.jpg"],
        "Meet their King. Large. Grumpy. Hits back. Mostly eating. \U0001f451",
        "Meet their King.\n\nHe's large, he's grumpy, and he hits back. He can only be hurt once both of his King towers "
        "have fallen.\n\nYour King is counting on you. He's also eating. Mostly eating.", None, ["#IndieGame"])
    add("charge", "gameplay", ["art/gameplay_stills/03_the_charge.jpg"],
        "Rally your team. Five of you, one lane, their towers at the end of it. ⚔️",
        "Rally your team.\n\nParty up with friends and clanmates, up to five together, or let the bots fill the empty "
        "seats. Then pick a lane.", None, ["#5v5", "#MobileGame"])
    add("clash", "gameplay", ["art/gameplay_stills/04_the_clash.jpg"],
        "Every knockout pays. Every death feeds the other team. Choose wisely.",
        "Every knockout pays, and every death feeds the other team.\n\nFirst Blood, multi-kills, shutdowns, Aces and "
        "bounties: the river ford is where it all goes wrong for someone.", None, ["#MOBA"])
    add("meteors", "champion moment", ["art/gameplay_stills/05_meteors.jpg"],
        "Theron Starweave spent three hundred years counting falling stars. Now they fall where he points. ☄️",
        "The Archmage's ultimate, METEORS: six meteors rain down round your target.\n\nTheron Starweave, Keeper of the "
        "Falling Stars. Kind, forgetful, very old, and the sky still listens to him.", None, ["#MOBA", "#FantasyGame"])
    add("dragon_dive", "champion moment", ["art/gameplay_stills/06_dragon_dive.jpg"],
        "“Look up.” — Kael Wyrmlance, the Dragoon \U0001f409",
        "“Look up.”\n\nThe Dragoon's ultimate, DRAGON DIVE: leap high onto an enemy hero up to 11 m away and "
        "crash down, with heavy damage and a 1 s stun round you.\n\nKael Wyrmlance, Last Rider of Skyreach.", None,
        ["#MOBA"])
    add("landslide", "champion moment", ["art/gameplay_stills/07_landslide.jpg"],
        "Gorrak Stoneheart slept in a mountain for a thousand years, until a war woke him with its noise. \U0001faa8",
        "The Golem's ultimate, LANDSLIDE: roll 9 m like an avalanche, flattening everyone in the way; where you stop the "
        "ground breaks and enemies near are stunned.\n\nGorrak Stoneheart, The Living Mountain. “... I ... "
        "remain.”", None, ["#MOBA"], "Use the emoji only if the platform shows it (rock); otherwise drop it.")
    add("duel", "champion moment", ["art/gameplay_stills/08_the_duel.jpg"],
        "Sword meets bear. ⚔️ The Knight and the Barbarian, up close.",
        "Sir Aldric Vane, The Oathbound Wall: “Not one step back.”\nHroth Bearcloak, Son of the Frostfang "
        "Clans: “Ha! Is that all the north wind has?”\n\nSomeone's taking a step back.", None, ["#IndieGame"])
    add("breach", "gameplay", ["art/gameplay_stills/09_the_breach.jpg", "video/landscape/clip_03_breach.mp4",
                               "video/vertical/clip_03_breach-vertical.mp4"],
        "Outer tower. Inner tower. Gate tower. The gate. The King's two towers. Then the King. \U0001f3f0",
        "To win, push down a lane: outer tower, inner tower, gate tower, then the gate. Then the two towers by their "
        "King, then the King himself.\n\nHe's large, grumpy, and hits back.", "Then the King. \U0001f451 #Fatebound",
        ["#MOBA", "#5v5"], "The words are the Herald's, from the tutorial.")
    add("grave_wyrm", "the Rift", ["art/gameplay_stills/10_grave_wyrm.jpg", "video/landscape/clip_04_grave_wyrm.mp4",
                                   "video/vertical/clip_04_grave_wyrm-vertical.mp4"],
        "But deep in its pit... the Grave Wyrm wakes. \U0001f409\U0001f480",
        "But deep in its pit... the Grave Wyrm wakes.\n\nA huge skeletal dragon sleeps in the Rift's east pit. It "
        "wakes at 3:00 and breathes soul-fire. Slay it, and every hero on your side gets tougher for the rest of the "
        "match.", "It wakes at 3:00. \U0001f409 #Fatebound", ["#MOBA", "#FantasyGame"])
    add("battle_clip", "gameplay", ["video/landscape/clip_02_battle.mp4", "video/vertical/clip_02_battle-vertical.mp4"],
        "When the drums hit. ⚔️",
        "Eighteen champions. Break their towers.\n\nTen seconds of Fatebound: the ford, the Archmage's meteors, the "
        "Dragoon's dive, the Golem's landslide, and a tower that had it coming.", "Eighteen champions. ⚔️ "
        "#Fatebound", ["#MOBA", "#5v5"])
    add("opening_clip", "the trailer", ["video/landscape/clip_01_opening.mp4",
                                        "video/vertical/clip_01_opening-vertical.mp4"],
        "Two kingdoms. One crown. Rally your team.",
        "Two kingdoms. One crown. Rally your team.\n\nFive heroes, one lane, and a King at the end of it.",
        "Two kingdoms. One crown. \U0001f451 #Fatebound", ["#IndieGame"])
    add("title_clip", "the trailer", ["video/landscape/clip_05_title.mp4", "video/vertical/clip_05_title-vertical.mp4"],
        "Fatebound. Five-on-five hero battles. ⚡",
        "Hear ye, hear ye! Fatebound. Five-on-five hero battles.", "Hear ye. ⚡ #Fatebound", ["#MOBA", "#IndieDev"])
    add("roster", "champions", ["art/champions/roster_18_champions.jpg"],
        "18 champions. Six roles. Tanks, fighters, assassins, mages, marksmen and supports. Who's yours?",
        "18 champions in six roles:\n\U0001f6e1️ Tanks take the hits and hold the line.\n⚔️ Fighters "
        "fight up close and keep going.\n\U0001f5e1️ Assassins get in, take out a hero, get out.\n\U0001fa84 Mages "
        "cast from range: big damage, control.\n\U0001f3f9 Marksmen deal steady damage from range and carry late.\n"
        "✨ Supports heal, shield and set up the team.\n\nEvery champion has three abilities and an ultimate that "
        "unlocks at level 6. Who's yours?", None, ["#MOBA", "#5v5"],
        "On Instagram/Facebook the six role lines may use emoji; on X keep the short text.")
    add("outfits", "collecting", ["art/screenshots/05_outfit.jpg"] + ["art/outfits/%s.jpg" % c["outfit_id"]
                                                                       for c in data["champions"][:4]],
        "36 outfits: a set made for every champion, each with its own weapon, plus the Frostbound line. ❄️",
        "36 outfits: a set made for every champion, each with a weapon of its own, plus the Frostbound line.\n\nOutfits "
        "are cosmetic only. They change how a champion looks, never how a champion plays.", None, ["#IndieGame"],
        "A carousel on Instagram/Facebook (up to 10 pictures from art/outfits/).")
    add("clans", "clans", ["art/screenshots/06_clan.jpg"],
        "Build your clan's camp from a single tent to a great hall. \U0001f3d5️\U0001f3f0",
        "Join a clan:\n• Choose your crest and grow your camp from a single tent to a great hall\n• Earn clan "
        "points in every match for the weekly Clan Chest\n• Climb the Clan League\n• Ask your clan for hero "
        "shards, and give yours\n• Looking For Group to jump straight into a party", None, ["#MobileGame"])
    add("squad", "clans", ["art/screenshots/07_home.jpg", "art/posts/herald_alliance.jpg"],
        "Parties of five with friends and clanmates. The enemy hates it. The Herald adores it.",
        "Squad up: parties of up to five with friends and clanmates, and chat with your clan, your party and everyone "
        "online.\n\n“Five of you on one side. The enemy hates it. I adore it.” — the Royal Herald", None,
        ["#MobileGame"])
    add("tutorial", "the Herald", ["art/screenshots/08_tutorial.jpg"],
        "Learn the ropes from the Royal Herald. Fully voiced. Mostly painless.",
        "New to hero battles? The Royal Herald teaches you the basics in a funny, fully voiced tutorial.\n\n“It's "
        "quick, it's mostly painless, and there's gold at the end.”", None, ["#IndieGame"])
    add("teamfight", "gameplay", ["art/screenshots/01_teamfight.jpg"],
        "This is what it looks like in your hands. DOUBLE KILL. ⚡",
        "This is what it looks like in your hands: a 5v5 fight in the river, the Stormcaller's storm finishing two of "
        "theirs. DOUBLE KILL.\n\nOnline 5v5 matches with bots filling any empty seats, or a match against bots whenever "
        "you like.", None, ["#MOBA", "#MobileGame"])
    add("jungle", "the Rift", ["art/gameplay_stills/04_the_clash.jpg"],
        "Clear the jungle: the Arcane Wraith makes your abilities recharge faster, the Ember Brute makes you hit harder.",
        "Between the lanes, the jungle. Clear its camps for gold, experience and buffs:\n• the Arcane Wraith: your "
        "abilities and ultimate recharge faster\n• the Ember Brute: you hit harder\n\nAnd at 5:00 the Bone Lord "
        "rises in the west pit. Bring him down and he marches for your side.", None, ["#MOBA"],
        "The picture is a river fight, not the jungle: don't say it shows the camps or the Bone Lord.")
    add("godot", "behind the scenes", ["art/gameplay_stills/01_the_rift.jpg"],
        "Fatebound is made with the Godot engine by a solo indie developer. \U0001f6e0️",
        "Fatebound is made with the Godot engine by a solo indie developer: 18 champions, a Rift with three lanes, two "
        "epic monsters and one very comfortable chair.", None, ["#MadeWithGodot", "#GodotEngine", "#IndieDev",
                                                                  "#GameDev"])
    for (name, pose, line) in HERALD_POSTS:
        add(name, "the Herald", ["art/posts/%s.jpg" % name], line + " — the Royal Herald",
            "%s\n\n— the Royal Herald" % line, None, ["#IndieGame"])
    for c in data["champions"]:
        k = c["abilities"]
        add("champion_" + c["id"], "champion spotlight", ["art/champions/%s.jpg" % c["id"]],
            "%s %s, %s. “%s”" % (HOOKS[c["id"]], c["name"], c["title"], c["quote"]),
            "Meet %s, %s: the %s (%s).\n\n%s\n\n“%s”\n\nUltimate: %s. %s" % (
                c["name"], c["title"], c["class"], ROLE_NAMES[c["role"]].lower(), c["lore"], c["quote"],
                k["r"]["name"], k["r"]["text"]), None, ["#MOBA", "#FantasyGame"],
            "One a week makes an 18-week series. Check the short text's length for X (240).")
        add("outfit_" + c["id"], "outfit spotlight", ["art/outfits/%s.jpg" % c["outfit_id"]],
            "The %s %s: %s's epic outfit, with a weapon of its own." % (c["outfit"], c["class"], c["name"]),
            "The %s %s: an epic outfit for %s, %s, with a weapon of its own.\n\nOutfits are cosmetic only." % (
                c["outfit"], c["class"], c["name"], c["title"]), None, ["#IndieGame"])
    json.dump({"note": "Ready posts. 'short' is for X, Threads and Bluesky; 'long' for Instagram, Facebook and "
                       "LinkedIn; 'video_caption' for TikTok, Reels and Shorts. Add the hashtags as voice.md says. "
                       "Each media file's alt text is in assets.json.", "posts": P},
              open(os.path.join(KIT, "posts", "posts.json"), "w"), indent=2, ensure_ascii=False)
    for p in P:
        if len(p["short"]) + len(" #Fatebound") > 280:
            print("LONG for X:", p["id"], len(p["short"]))
    L = ["# Post ideas", "",
         "%d ready posts (all of them in `posts.json`, with the files to attach). Mix the pillars; don't post more "
         "than one a day on a platform. Everything in them is checked against the game; if you change a post, keep to "
         "`brand/rules.md`." % len(P), "",
         "## The pillars", "",
         "| Pillar | What | Posts |", "|---|---|---|"]
    pillars = {}
    for p in P:
        pillars.setdefault(p["pillar"], []).append(p["id"])
    about = {"the trailer": "the trailer and its clips", "the game": "what Fatebound is", "the Rift": "the map, its "
             "monsters and jungle", "the King": "the King, the running joke", "gameplay": "moments on the Rift",
             "champion moment": "a champion's ultimate in action", "champions": "the roster and roles",
             "collecting": "outfits", "clans": "clans and parties", "the Herald": "the Royal Herald's humour",
             "behind the scenes": "how it's made", "champion spotlight": "one champion: story, line, ultimate",
             "outfit spotlight": "one champion's epic outfit"}
    for k, v in pillars.items():
        L.append("| %s | %s | %d |" % (k, about.get(k, ""), len(v)))
    L += ["", "## Suggested first two weeks", "",
          "1. `trailer` (pin it)", "2. `herald_hello`", "3. `roster`", "4. `the_rift`", "5. `champion_knight`",
          "6. `their_king`", "7. `battle_clip`", "8. `herald_five`", "9. `grave_wyrm`", "10. `champion_stormcaller`",
          "11. `clans`", "12. `meteors`", "13. `herald_play`", "14. `outfits`", "",
          "Then a champion spotlight a week (in the order of `game/champions.md`), the outfit spotlights in between, "
          "and the rest mixed in.", ""]
    for p in P:
        L += ["## %s (%s)" % (p["id"], p["pillar"]), "", "Attach: " + ", ".join("`%s`" % m for m in p["media"]), "",
              "**Short (X, Threads, Bluesky):** " + p["short"], "", "**Long (Instagram, Facebook):**", ""]
        L += ["> " + s if s else ">" for s in p["long"].split("\n")]
        if p.get("video_caption"):
            L += ["", "**Video caption (TikTok, Reels, Shorts):** " + p["video_caption"]]
        L += ["", "Hashtags: " + " ".join(p["hashtags"])]
        if p.get("notes"):
            L += ["", "_Note: %s_" % p["notes"]]
        L.append("")
    open(os.path.join(KIT, "posts", "post_ideas.md"), "w").write("\n".join(L))


def main():
    global KIT
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--champs", required=True, help="tools/social_champions.gd's renders")
    ap.add_argument("--champ-json", required=True, help="tools/social_champions.gd DUMP=<this>")
    ap.add_argument("--trailer", default="", help="trailer 8's master (trailer8_edit.py)")
    ap.add_argument("--rec", default="", help="trailer 8's recordings (for the stills)")
    ap.add_argument("--no-video", action="store_true")
    ap.add_argument("--video-from", default="", help="a kit built before: take its video/ as it is (no encoding)")
    a = ap.parse_args()
    KIT = os.path.join(a.out, NAME)
    if os.path.exists(KIT):
        shutil.rmtree(KIT)
    for sub in ("game", "brand", "posts"):
        os.makedirs(os.path.join(KIT, sub), exist_ok=True)
    for f in ("START_HERE.md", "links.md", "game/overview.md", "brand/voice.md", "brand/rules.md",
              "brand/profiles.md"):
        shutil.copy(os.path.join(SRC, f), os.path.join(KIT, f))
    data = json.load(open(a.champ_json))
    for c in data["champions"]:
        c["lore"], c["quote"] = tidy(c["lore"]), tidy(c["quote"])
        for sl in c["abilities"].values():
            sl["text"] = tidy(sl["text"])
    import re
    vs = re.findall(r'version/name="(\d+)\.(\d+)\.(\d+)-fatebound"', open(os.path.join(GODOT, "export_presets.cfg")).read())
    data["version"] = "%s.%s.%s" % max(tuple(int(x) for x in v) for v in vs)
    for c in data["champions"]:
        c["outfit_id"] = c.get("outfit_id", "")
        c["place"] = PLACES[c["id"]]
    champions_md(data)
    facts_json(data)
    copies(LISTING)
    key_art()
    herald()
    champions(data, a.champs)
    if a.rec:
        stills(a.rec)
    if a.video_from:
        shutil.copytree(os.path.join(a.video_from, "video"), os.path.join(KIT, "video"))
        video(a.trailer, a.out, encode=False)
    elif a.trailer and not a.no_video:
        video(a.trailer, a.out)
    posts(data)
    for p in json.load(open(os.path.join(KIT, "posts", "posts.json")))["posts"]:
        for m in p["media"]:
            if m.endswith(".mp4") and (a.no_video or not (a.trailer or a.video_from)):
                continue
            assert os.path.exists(os.path.join(KIT, m)), (p["id"], m)
    json.dump({"note": "Every picture and video in the kit: what it shows, its alt text, where it fits best. 'kind' "
                       "says how it was made: the store screenshots show the game as it plays; the gameplay stills and "
                       "the trailer are staged in the game's own engine and filmed with cinematic cameras, without the "
                       "on-screen controls; the champion and outfit cards are the game's own champion window with its "
                       "buttons hidden.", "assets": assets},
              open(os.path.join(KIT, "assets.json"), "w"), indent=2, ensure_ascii=False)
    z = os.path.join(a.out, NAME + ".zip")
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
        for dp, _, fs in os.walk(KIT):
            for f in sorted(fs):
                full = os.path.join(dp, f)
                arc = os.path.relpath(full, a.out)
                comp = zipfile.ZIP_STORED if f.endswith((".mp4", ".jpg", ".png")) else zipfile.ZIP_DEFLATED
                zf.write(full, arc, compress_type=comp)
    print("kit", KIT, len(assets), "assets", "zip", z, os.path.getsize(z) // (1024 * 1024), "MB")


if __name__ == "__main__":
    main()
