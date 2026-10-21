#!/usr/bin/env python3
"""The game's icon from one square painting (art_sources/app_icon/icon.png, 1024 x 1024) -- 0.31.200 (Kevin: "make new
game icon"): the launcher icons the Android exports use, the window's, the Play listing's and the App Store's.

  assets/branding/icon.png        192   the legacy launcher icon and the window's (config/icon): the whole painting
  assets/branding/background.png  432   the adaptive icon's back layer: the painting over the 108dp layer's middle
                                        80 dp (so a launcher's 72 dp window, round or square, shows nearly all of it),
                                        its edges mirrored out into the margin the launchers' parallax moves through
  assets/branding/foreground.png  432   the adaptive icon's front layer: clear (everything is in the back layer)
  assets/branding/monochrome.png  432   (themed icons: the crown silhouette, unchanged -- the new icon has the crown too)
  store-listing/graphics/app_icon_512x512.png and fastlane's images/icon.png   Google Play, 512, 32-bit PNG
  store-listing/ios/app_icon_1024.png                                         the App Store's (and the iOS export's), RGB

    python3 tools/build_app_icon.py
"""
import os

from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
SRC = os.path.join(os.path.dirname(GODOT), "art_sources", "app_icon", "icon.png")
BR = os.path.join(GODOT, "assets", "branding")
SL = os.path.join(GODOT, "store-listing")
LAYER = 432                       # 108 dp
ART_DP = 80.0                     # the painting's width in the layer, of its 108 dp (the launchers show the middle 72)


def main():
    art = Image.open(SRC).convert("RGB")
    assert art.size[0] == art.size[1], art.size
    art.resize((192, 192), Image.LANCZOS).save(os.path.join(BR, "icon.png"), optimize=True)
    # the back layer: the painting at ART_DP over the middle, mirrored into the margin
    a = int(round(LAYER * ART_DP / 108.0))
    m = (LAYER - a) // 2
    core = art.resize((a, a), Image.LANCZOS)
    big = Image.new("RGB", (a * 3, a * 3))
    for i in range(3):
        for j in range(3):
            t = core
            if i != 1:
                t = ImageOps.mirror(t)
            if j != 1:
                t = ImageOps.flip(t)
            big.paste(t, (i * a, j * a))
    big.crop((a - m, a - m, a - m + LAYER, a - m + LAYER)).save(os.path.join(BR, "background.png"), optimize=True)
    Image.new("RGBA", (LAYER, LAYER), (0, 0, 0, 0)).save(os.path.join(BR, "foreground.png"), optimize=True)
    play = art.resize((512, 512), Image.LANCZOS).convert("RGBA")
    play.save(os.path.join(SL, "graphics", "app_icon_512x512.png"), optimize=True)
    play.save(os.path.join(SL, "fastlane", "metadata", "android", "en-US", "images", "icon.png"), optimize=True)
    art.resize((1024, 1024), Image.LANCZOS).save(os.path.join(SL, "ios", "app_icon_1024.png"), optimize=True)
    print("icon built from", SRC)


if __name__ == "__main__":
    main()
