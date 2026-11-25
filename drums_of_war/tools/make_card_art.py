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
    "line_infantry": ("u_line", (112, 0, 912, 831)),
    "skirmishers": ("u_skirm", (112, 0, 912, 831)),
    "militia": ("u_militia", (112, 0, 912, 831)),
    "scouts": ("u_cav", (52, 30, 972, 986)),
    "heavy_cavalry": ("u_cav", (200, 0, 860, 686)),
    "field_gun": ("cannon", (30, 10, 994, 1012)),
}
SIZE = (208, 216)        # the game draws from the top down, as much as a card has room for
TOP = (120, 180, 232)
BOTTOM = (214, 234, 246)


def backdrop(top, bottom, scenery=True):
    """A painted outdoor scene: sky, soft clouds, far hills, a sunlit field."""
    from PIL import ImageFilter
    w, h = SIZE
    back = Image.new("RGBA", SIZE)
    draw = ImageDraw.Draw(back)
    for y in range(h):
        t = y / (h - 1)
        draw.line([(0, y), (w, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    if not scenery:
        return back
    clouds = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    cd = ImageDraw.Draw(clouds)
    for cx, cy, rx, ry in [(40, 34, 46, 14), (78, 26, 34, 12), (160, 50, 52, 15), (190, 40, 30, 11), (110, 70, 40, 10)]:
        cd.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(255, 255, 255, 215))
    back.alpha_composite(clouds.filter(ImageFilter.GaussianBlur(5)))
    land = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    ld = ImageDraw.Draw(land)
    ld.ellipse([-80, int(h * 0.50), 150, int(h * 1.2)], fill=(150, 178, 120, 255))      # far hills, hazy
    ld.ellipse([70, int(h * 0.54), 320, int(h * 1.3)], fill=(128, 164, 100, 255))
    ld.ellipse([-120, int(h * 0.66), 260, int(h * 1.6)], fill=(156, 176, 84, 255))      # the near field
    ld.ellipse([60, int(h * 0.74), 380, int(h * 1.7)], fill=(176, 186, 92, 255))
    back.alpha_composite(land.filter(ImageFilter.GaussianBlur(2.2)))
    glow = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([w - 110, -70, w + 50, 90], fill=(255, 236, 170, 120))  # low sun, top right
    back.alpha_composite(glow.filter(ImageFilter.GaussianBlur(22)))
    return back


def order_art():
    """The two orders have no model, so their pictures are drawn here."""
    import math
    # Fire!: a muzzle flash bursting out of a bank of smoke.
    img = backdrop((70, 52, 120), (150, 120, 190), scenery=False)
    d = ImageDraw.Draw(img)
    cx, cy = 104, 92
    for r, col in [(74, (255, 255, 255, 235)), (52, (255, 248, 236, 255))]:
        for k in range(7):
            a = k * 0.9
            d.ellipse([cx - 78 + 26 * k - r * 0.5, cy + 34 * math.sin(a) + 20 - r * 0.5,
                       cx - 78 + 26 * k + r * 0.5, cy + 34 * math.sin(a) + 20 + r * 0.5], fill=col)
    for radius, col in [(70, (255, 138, 31, 255)), (46, (255, 214, 64, 255)), (22, (255, 252, 230, 255))]:
        pts = []
        for k in range(20):
            a = math.pi * 2 * k / 20
            rr = radius * (1.0 if k % 2 == 0 else 0.52)
            pts.append((cx + rr * math.cos(a), cy - 8 + rr * math.sin(a)))
        d.polygon(pts, fill=col)
    img.convert("RGB").save("assets/cards/fire.png", optimize=True)
    print("wrote assets/cards/fire.png")
    # Rally: a drum under a pennant, the two things a broken regiment forms up on.
    img = backdrop((70, 52, 120), (150, 120, 190), scenery=False)
    d = ImageDraw.Draw(img)
    d.rectangle([58, 18, 64, 150], fill=(96, 62, 32, 255))
    d.polygon([(64, 20), (160, 40), (64, 64)], fill=(36, 86, 201, 255))
    d.polygon([(64, 20), (160, 40), (64, 64)], outline=(21, 35, 58, 255))
    d.ellipse([84, 150, 172, 186], fill=(120, 30, 40, 255))
    d.rectangle([84, 118, 172, 168], fill=(200, 30, 58, 255))
    for k in range(5):
        x0 = 84 + k * 22
        d.line([(x0, 120), (x0 + 11, 166)], fill=(246, 242, 230, 255), width=3)
        d.line([(x0 + 11, 166), (x0 + 22, 120)], fill=(246, 242, 230, 255), width=3)
    d.ellipse([84, 100, 172, 136], fill=(246, 242, 230, 255), outline=(242, 182, 50, 255), width=5)
    d.line([(108, 70), (140, 112)], fill=(96, 62, 32, 255), width=6)
    d.line([(156, 66), (120, 112)], fill=(96, 62, 32, 255), width=6)
    img.convert("RGB").save("assets/cards/rally.png", optimize=True)
    print("wrote assets/cards/rally.png")


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
        back = backdrop(TOP, BOTTOM)
        back.alpha_composite(crop)
        out = f"assets/cards/{card}.png"
        back.convert("RGB").save(out, optimize=True)
        print("wrote", out)
    order_art()

if __name__ == "__main__":
    main()
