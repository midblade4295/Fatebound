#!/usr/bin/env python3
"""The game's icon -- 0.31.210 (Kevin: "I want a new game icon that is a 3d design that doesn't look like 'ai slop' that I
got feedback with" -> picked "1 King, blue"), 0.31.211 ("Seems a bit plain with the solid blue background. Also maybe if
you can make the king higher triangle count so it's more detail"): the King in front of his throne, rendered in 3D
(tools/render_app_icon.gd, shot "king_hd") -- the King himself rebuilt in far more detail for it by Meshy from views of
his own model (tools/meshy_king.py: 824k triangles and 4k textures against the game's 10.4k and 512 px), and behind him
his corner of the keep as the game lays it out (the throne, the Royal kit's canopy and banners, the statues, the wall,
the sky), blurred here as a camera lens would and darkened toward the corners so he stands out. Both renders are
MARGIN (1.5) times wider than the icon -- the launchers' adaptive icon shows the middle 72 dp of its 108 dp layers -- so
the King is the adaptive icon's front layer and the throne room its back one, and they move apart in the launchers'
parallax with real depth. (0.31.200's icon, a gpt-image-2 painting, is in git history and art_sources/app_icon/concepts.)

  art_sources/app_icon/render/king_hd_wide.png     the King (RGBA, square, MARGIN x the icon)
  art_sources/app_icon/render/king_hd_bg_wide.png  the throne room behind him (RGB, the same camera, sharp)
      (render_app_icon.gd: OUT_DIR=art_sources/app_icon/render ONLY=king_hd)
  art_sources/app_icon/icon.png               1024, the icon flat: the record, and what tools/build_social_kit.py makes
                                              the avatars from

  assets/branding/icon.png        192   the legacy launcher icon and the window's (config/icon)
  assets/branding/background.png  432   the adaptive icon's back layer: the throne room over the whole 108 dp
  assets/branding/foreground.png  432   the adaptive icon's front layer: the King, see-through around him
  assets/branding/monochrome.png  432   (themed icons: the crown silhouette, unchanged -- it is his crown)
  store-listing/graphics/app_icon_512x512.png and fastlane's images/icon.png   Google Play, 512, 32-bit PNG
  store-listing/ios/app_icon_1024.png                                         the App Store's (and the iOS export's), RGB

    python3 tools/build_app_icon.py
"""
import os

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
ART = os.path.join(os.path.dirname(GODOT), "art_sources", "app_icon")
RENDER = os.path.join(ART, "render", "king_hd_wide.png")
SET = os.path.join(ART, "render", "king_hd_bg_wide.png")
BR = os.path.join(GODOT, "assets", "branding")
SL = os.path.join(GODOT, "store-listing")
LAYER = 432                       # 108 dp
MARGIN = 1.5                      # the renders (and the layers) cover 108 dp, the icon the middle 72 dp
BLUR = 1.0 / 110.0                # the lens blur on the throne room, a share of the render's width
SATURATION = 1.1
VIGNETTE = 0.5                    # how much darker the icon's corners get (centred a little above the middle)


def backdrop(set_img):
    """The throne room blurred, a touch richer, darkening toward the icon's corners; a little grain against banding."""
    n = set_img.size[0]
    b = ImageEnhance.Color(set_img.convert("RGB").filter(ImageFilter.GaussianBlur(n * BLUR))).enhance(SATURATION)
    a = np.asarray(b, np.float32)
    y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
    d = np.sqrt(((x - 0.5) * MARGIN) ** 2 + ((y - 0.45) * MARGIN) ** 2) / 0.72
    a *= (1.0 - VIGNETTE * np.clip(d, 0.0, 1.4) ** 2)[..., None]
    a += np.random.default_rng(1).normal(0.0, 1.0, a.shape)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def main():
    wide = Image.open(RENDER).convert("RGBA")
    room = backdrop(Image.open(SET))
    assert wide.size[0] == wide.size[1] == room.size[0] == room.size[1], (wide.size, room.size)
    n = wide.size[0]
    core = int(round(n / MARGIN))
    o = (n - core) // 2
    # the icon: the middle of the throne room with the middle of the King over it
    flat = room.convert("RGBA")
    flat.alpha_composite(wide)
    flat = flat.crop((o, o, o + core, o + core)).convert("RGB")
    art = flat.resize((1024, 1024), Image.LANCZOS)
    art.save(os.path.join(ART, "icon.png"), optimize=True)
    art.resize((192, 192), Image.LANCZOS).save(os.path.join(BR, "icon.png"), optimize=True)
    # the adaptive layers: the throne room behind, the King in front, both over the whole 108 dp
    room.resize((LAYER, LAYER), Image.LANCZOS).save(os.path.join(BR, "background.png"), optimize=True)
    wide.resize((LAYER, LAYER), Image.LANCZOS).save(os.path.join(BR, "foreground.png"), optimize=True)
    play = art.resize((512, 512), Image.LANCZOS).convert("RGBA")
    play.save(os.path.join(SL, "graphics", "app_icon_512x512.png"), optimize=True)
    play.save(os.path.join(SL, "fastlane", "metadata", "android", "en-US", "images", "icon.png"), optimize=True)
    art.save(os.path.join(SL, "ios", "app_icon_1024.png"), optimize=True)
    print("icon built from", RENDER, "and", SET)


if __name__ == "__main__":
    main()
