#!/usr/bin/env python3
"""The hero skins' textures (0.31.186, League's way: skins sold for gems, each with its hero): art_sources/skins/<line>/
<hero>.jpg (2048, Meshy's retexture of the hero's own model, its UVs kept -- tools/meshy_retexture.py) ->
assets/skins/<hero>_<line key>.jpg, 1024 (a hero is small on the screen; the pack stays ~0.7 MB a skin once VRAM-
compressed, the import below, as the heroes' own textures are). The catalog is economy.gd SKINS.

  python3 tools/build_skins.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
SRC = os.path.join(os.path.dirname(GODOT), "art_sources", "skins")
OUT = os.path.join(GODOT, "assets", "skins")
LINES = {"frostbound": "frost"}          # the line's folder -> the skin ids' suffix (economy.gd SKINS)
# 0.31.188: each hero's own set (art_sources/skins/outfits/<hero>.jpg -> <hero>_<key>.jpg, economy.gd OUTFITS) and the
# repainted weapons (art_sources/skins/<line>/weapons/<piece>.jpg -> assets/skins/weapons/<piece>_<key>.jpg, 512: a
# weapon is smaller still)
OUTFIT_KEYS = {"knight": "lion", "barbarian": "mammoth", "rogue": "velvet", "ranger": "orchard", "mage": "phoenix",
               "priest": "bell", "crusader": "ashen", "berserker": "bloodmoon", "assassin": "ribbon", "sniper": "wolf",
               "archmage": "stargazer", "necromancer": "gravekeeper", "golem": "geode", "dragoon": "dragonscale",
               "duelist": "rose", "stormcaller": "stormforged", "musketeer": "privateer", "druid": "blossom"}
WEAPON_SIZE = 512
SIZE = 1024
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
mipmaps/generate=true
mipmaps/limit=-1
detect_3d/compress_to=1
"""


def main():
    from PIL import Image
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for line, key in LINES.items():
        d = os.path.join(SRC, line)
        for f in sorted(os.listdir(d)):
            if not f.endswith(".jpg"):
                continue
            hero = f[:-4]
            out = os.path.join(OUT, "%s_%s.jpg" % (hero, key))
            Image.open(os.path.join(d, f)).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(out, "JPEG", quality=92)
            if not os.path.exists(out + ".import"):
                open(out + ".import", "w").write(IMPORT)       # (VRAM-compressed with mipmaps, like the heroes' own)
            n += 1
            print("%-24s %4d KB" % (os.path.basename(out), os.path.getsize(out) // 1024))
    d = os.path.join(SRC, "outfits")
    for hero, key in OUTFIT_KEYS.items():
        f = os.path.join(d, hero + ".jpg")
        if not os.path.exists(f):
            print("(no outfit yet for %s)" % hero)
            continue
        out = os.path.join(OUT, "%s_%s.jpg" % (hero, key))
        Image.open(f).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(out, "JPEG", quality=92)
        if not os.path.exists(out + ".import"):
            open(out + ".import", "w").write(IMPORT)
        n += 1
        print("%-24s %4d KB" % (os.path.basename(out), os.path.getsize(out) // 1024))
    wout = os.path.join(OUT, "weapons")
    os.makedirs(wout, exist_ok=True)
    for line, key in LINES.items():
        d = os.path.join(SRC, line, "weapons")
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".jpg"):
                continue
            out = os.path.join(wout, "%s_%s.jpg" % (f[:-4], key))
            Image.open(os.path.join(d, f)).convert("RGB").resize((WEAPON_SIZE, WEAPON_SIZE), Image.LANCZOS).save(out, "JPEG", quality=92)
            if not os.path.exists(out + ".import"):
                open(out + ".import", "w").write(IMPORT)
            n += 1
    print("%d skins" % n)


if __name__ == "__main__":
    sys.exit(main())
