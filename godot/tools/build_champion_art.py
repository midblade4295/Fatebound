#!/usr/bin/env python3
"""The champions' paintings (0.31.187, Kevin: "When clicking on a champion, make a customized window for them that pops up
that is themed around them ... Use art and effects that match each characters lore").

Sources: art_sources/champions/<hid>.png -- ElevenLabs gpt-image-2, 9:16 at 1K (720 x 1280), medium quality, the Market
banner (assets/ui/v2/art_shop.webp) as the style reference, one take each; flow "Fatebound champions 0.31.187";
prompts.json has each prompt. Each is the champion's own place, empty, with open ground a third to two thirds of the
way down for him to stand on and a dark, quiet bottom third for the window's text.

Writes, for each of the 18:
  assets/ui/champions/<hid>.webp        the window's backdrop, 720 x 1280
  assets/ui/champions/cards/<hid>.webp  the Locker card's crop: the scene round the open ground, 3:4, 180 x 240

  python3 tools/build_champion_art.py      (pillow)
"""
import os

from PIL import Image

GODOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(GODOT), "art_sources", "champions")
OUT = os.path.join(GODOT, "assets", "ui", "champions")
HEROES = ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "crusader", "berserker", "assassin", "sniper",
          "archmage", "necromancer", "golem", "dragoon", "duelist", "stormcaller", "musketeer", "druid"]
CARD = (180, 240)


def main():
    os.makedirs(os.path.join(OUT, "cards"), exist_ok=True)
    for h in HEROES:
        im = Image.open(os.path.join(SRC, h + ".png")).convert("RGB")
        if im.size != (720, 1280):
            im = im.resize((720, 1280), Image.LANCZOS)
        im.save(os.path.join(OUT, h + ".webp"), "WEBP", quality=84, method=6)
        # the card: 600 x 800 round the open ground (centred across, from 9 % down)
        top = int(1280 * 0.09)
        crop = im.crop((60, top, 660, top + 800)).resize(CARD, Image.LANCZOS)
        crop.save(os.path.join(OUT, "cards", h + ".webp"), "WEBP", quality=86, method=6)
        print(h, os.path.getsize(os.path.join(OUT, h + ".webp")), os.path.getsize(os.path.join(OUT, "cards", h + ".webp")))


if __name__ == "__main__":
    main()
