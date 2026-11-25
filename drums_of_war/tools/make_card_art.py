#!/usr/bin/env python3
"""Makes the card portraits in assets/cards/ from the models' reference images.

Each portrait is a 2:1 crop of assets/models/<model>/ref.png with the white studio background
replaced by a soft sky tint. Cards without a reference yet are skipped and keep their text face.

Usage: make_card_art.py            (run from the drums_of_war folder; needs Pillow)
"""
import os
from PIL import Image, ImageDraw

# card id -> (model whose ref.png to use, crop box on the 1024 px reference)
CARDS = {
    "line_infantry": ("u_line", (112, 0, 912, 400)),
    "skirmishers": ("u_skirm", (112, 0, 912, 400)),
    "militia": ("u_militia", (112, 0, 912, 400)),
    "scouts": ("u_cav", (72, 20, 952, 460)),
    "heavy_cavalry": ("u_cav", (232, 0, 792, 280)),
    "field_gun": ("cannon", (32, 250, 992, 730)),
}
SIZE = (208, 104)
TOP = (176, 214, 250)
BOTTOM = (232, 244, 255)


def main():
    os.makedirs("assets/cards", exist_ok=True)
    for card, (model, box) in CARDS.items():
        src = f"assets/models/{model}/ref.png"
        if not os.path.exists(src):
            print(f"skip {card}: no {src}")
            continue
        img = Image.open(src).convert("RGBA")
        if img.size != (1024, 1024):
            img = img.resize((1024, 1024), Image.LANCZOS)
        # Clear the white studio background, working in from the corners and edges.
        for seed in [(0, 0), (1023, 0), (0, 1023), (1023, 1023), (512, 0), (0, 512), (1023, 512)]:
            if img.getpixel(seed)[3] != 0:
                ImageDraw.floodfill(img, seed, (255, 255, 255, 0), thresh=40)
        crop = img.crop(box).resize(SIZE, Image.LANCZOS)
        back = Image.new("RGBA", SIZE)
        draw = ImageDraw.Draw(back)
        for y in range(SIZE[1]):
            t = y / (SIZE[1] - 1)
            draw.line([(0, y), (SIZE[0], y)], fill=tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,))
        back.alpha_composite(crop)
        out = f"assets/cards/{card}.png"
        back.convert("RGB").save(out, optimize=True)
        print("wrote", out)


if __name__ == "__main__":
    main()
