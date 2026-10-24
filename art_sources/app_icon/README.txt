The game's icon. 0.31.210 (Kevin: "I want a new game icon that is a 3d design that doesn't look like 'ai slop' that I
got feedback with" -> "1 King, blue"), 0.31.211 ("Seems a bit plain with the solid blue background. Also maybe if you
can make the king higher triangle count so it's more detail"): a 3D render of the King in front of his throne.
0.31.200's icon was a gpt-image-2 painting (concepts/, below).

king_hd/        the King rebuilt in far more detail for the icon (godot/tools/meshy_king.py): Meshy 7.1 multi-image-to-3D
                from four views of the game's own King (king_input_<front|right|back|left>.png: godot/tools/
                render_app_icon.gd VIEWS=1, his textures cleaned up), 2k geometry, no remesh, 4k PBR textures.
                king_hd.glb: 824k triangles (the game's King: 10.4k), 38 MB; king_hd.json: the task and its settings
                (35 credits); king_hd.png: Meshy's preview. The game's King is unchanged -- this one is only rendered.
king_clean/     the game King's textures for the views above (godot/tools/clean_king_texture.py): his 512 px Meshy
                texture redrawn as clean flat paint at 2048 in his own palette, his face and hands kept as painted, and a
                roughness/metal map (gold metal, glassy gems)
render/         the icon's renders (render_app_icon.gd, shot "king_hd"), both 1.5x wider than the icon (the adaptive
                icon's 108 dp layer around its 72 dp window), the same camera:
                  king_hd_wide.png      the King, see-through around him (studio-lit: warm key, soft shadows, cool fill,
                                        blue rim, ambient occlusion)
                  king_hd_bg_wide.png   his corner of the keep as the game lays it out (the throne with the blue side's
                                        velvet, the Royal kit's canopy, banners and statues, the curtain wall, the sky)
                Re-render them with:
                  Xvfb :98 -screen 0 1080x1920x24 &
                  cd godot && DISPLAY=:98 SIZE=2048 ONLY=king_hd OUT_DIR=../art_sources/app_icon/render \
                    godot --rendering-method forward_plus --path . -s res://tools/render_app_icon.gd
                (it also writes render/king_hd.png, the King's square; the build only needs the two wide ones)
icon.png        the icon flat, 1024 -- written by godot/tools/build_app_icon.py (the throne room blurred like a lens and
                darkened toward the corners, the King over it), which also makes the launcher icons (assets/branding:
                the King in front, the throne room behind), the Play icon and the App Store's

concepts/  0.31.200's: gpt-image-2 (1K, medium), two takes each, the title logo and Home's camp painting as references;
           4,784 ElevenLabs credits. On the flow "Fatebound app icon (5v5)" (sNGLKqkKPx0Jv89JIHVM).
  A1, A2   two chibi champions clash -- a Knight and a Barbarian -- sword on axe over the logo's lightning rift (A1 was the
           icon from 0.31.200 to 0.31.209)
  B1, B2   a heraldic shield split by the rift, ice and fire, the crown on it, a sword and an axe crossed behind
  C1, C2   one chibi Knight charging at you, sword up, the crown on his helmet, the rift behind him
