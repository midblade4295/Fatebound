#!/usr/bin/env python3
"""Makes the card pictures in assets/cards/ from the illustrations in assets/cards/src/.

Each source is a 4:5 painted action scene (see assets/cards/SOURCES.md). The game picture is the
same scene at 320 x 400; the card face then shows a window of it that fits the card's shape,
centred a little above the middle where the subject is (ui_kit.gd card_face).

Usage: make_card_art.py            (run from the drums_of_war folder; needs Pillow)
"""
import os
from PIL import Image

CARDS = ["line_infantry", "skirmishers", "militia", "scouts", "heavy_cavalry", "field_gun", "fire", "rally"]
SIZE = (320, 400)


def main():
    for card in CARDS:
        src = f"assets/cards/src/{card}.jpg"
        if not os.path.exists(src):
            print(f"skip {card}: no {src}")
            continue
        img = Image.open(src).convert("RGB").resize(SIZE, Image.LANCZOS)
        out = f"assets/cards/{card}.png"
        img.save(out, optimize=True)
        print(f"{out}: {os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main()
