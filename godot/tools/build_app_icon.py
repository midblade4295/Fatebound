#!/usr/bin/env python3
"""The game's icon -- 0.31.210 (Kevin: "I want a new game icon that is a 3d design that doesn't look like 'ai slop' that I
got feedback with" -> picked "1 King, blue"): the King, rendered in 3D from his own model (tools/render_app_icon.gd, his
textures cleaned up by tools/clean_king_texture.py) over a plain studio backdrop in the blue side's colour. The render is
see-through and MARGIN (1.5) times wider than the icon -- the launchers' adaptive icon shows the middle 72 dp of its
108 dp layers -- so the King is the adaptive icon's front layer and the backdrop its back one, and they move apart in
the launchers' parallax as Android means them to. (0.31.200's icon, a gpt-image-2 painting, is in git history and
art_sources/app_icon/concepts.)

  art_sources/app_icon/render/king_wide.png   the render (RGBA, square, MARGIN x the icon; render_app_icon.gd's
                                              <id>_wide.png: OUT_DIR=art_sources/app_icon/render ONLY=king)
  art_sources/app_icon/icon.png               1024, the icon flat (the backdrop and the King): the record, and what
                                              tools/build_social_kit.py makes the avatars from

  assets/branding/icon.png        192   the legacy launcher icon and the window's (config/icon)
  assets/branding/background.png  432   the adaptive icon's back layer: the backdrop over the whole 108 dp
  assets/branding/foreground.png  432   the adaptive icon's front layer: the King, see-through around him
  assets/branding/monochrome.png  432   (themed icons: the crown silhouette, unchanged -- it is his crown)
  store-listing/graphics/app_icon_512x512.png and fastlane's images/icon.png   Google Play, 512, 32-bit PNG
  store-listing/ios/app_icon_1024.png                                         the App Store's (and the iOS export's), RGB

    python3 tools/build_app_icon.py
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
ART = os.path.join(os.path.dirname(GODOT), "art_sources", "app_icon")
RENDER = os.path.join(ART, "render", "king_wide.png")
BR = os.path.join(GODOT, "assets", "branding")
SL = os.path.join(GODOT, "store-listing")
LAYER = 432                       # 108 dp
MARGIN = 1.5                      # the render (and the layers) cover 108 dp, the icon the middle 72 dp
# the backdrop: lit from behind his head (CENTER, a fraction of the icon), darkening to EDGE by RADIUS
CENTER_COLOR = (0x3f, 0x86, 0xde)
EDGE_COLOR = (0x0c, 0x1f, 0x4a)
CENTER = (0.5, 0.4)
RADIUS = 0.78


def backdrop(n, scale):
    """n x n pixels covering `scale` icon widths, centred: the radial light, a touch of grain against banding."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float32) / n
    x = (x - 0.5) * scale + 0.5
    y = (y - 0.5) * scale + 0.5
    d = np.sqrt((x - CENTER[0]) ** 2 + (y - CENTER[1]) ** 2) / RADIUS
    t = np.clip(d, 0.0, 1.0) ** 1.3
    a = np.array(CENTER_COLOR, np.float32)
    b = np.array(EDGE_COLOR, np.float32)
    img = a * (1.0 - t[..., None]) + b * t[..., None]
    img += np.random.default_rng(1).normal(0.0, 1.0, img.shape)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def main():
    wide = Image.open(RENDER).convert("RGBA")
    assert wide.size[0] == wide.size[1], wide.size
    n = wide.size[0]
    core = int(round(n / MARGIN))
    o = (n - core) // 2
    # the icon: the backdrop with the middle of the render over it
    flat = backdrop(core, 1.0).convert("RGBA")
    flat.alpha_composite(wide.crop((o, o, o + core, o + core)))
    flat = flat.convert("RGB")
    art = flat.resize((1024, 1024), Image.LANCZOS)
    art.save(os.path.join(ART, "icon.png"), optimize=True)
    art.resize((192, 192), Image.LANCZOS).save(os.path.join(BR, "icon.png"), optimize=True)
    # the adaptive layers: the backdrop behind, the King in front, both over the whole 108 dp
    backdrop(LAYER * 2, MARGIN).resize((LAYER, LAYER), Image.LANCZOS).save(os.path.join(BR, "background.png"), optimize=True)
    wide.resize((LAYER, LAYER), Image.LANCZOS).save(os.path.join(BR, "foreground.png"), optimize=True)
    play = art.resize((512, 512), Image.LANCZOS).convert("RGBA")
    play.save(os.path.join(SL, "graphics", "app_icon_512x512.png"), optimize=True)
    play.save(os.path.join(SL, "fastlane", "metadata", "android", "en-US", "images", "icon.png"), optimize=True)
    art.save(os.path.join(SL, "ios", "app_icon_1024.png"), optimize=True)
    print("icon built from", RENDER)


if __name__ == "__main__":
    main()
