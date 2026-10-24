The game's icon (0.31.210, Kevin: "I want a new game icon that is a 3d design that doesn't look like 'ai slop' that I
got feedback with" -> "1 King, blue"). 0.31.200's icon was a gpt-image-2 painting (concepts/, below); this one is a 3D
render of the game's own King.

render/king_wide.png   the King (assets/kings/king_blue_fat.glb), rendered by godot/tools/render_app_icon.gd: smooth
                       shading, the desktop renderer's ambient occlusion, a warm key light with soft shadows, a cool fill
                       and a blue rim, on a clear background, 1.5x wider than the icon (the adaptive icon's 108 dp layer
                       around its 72 dp window). Re-render it with:
                         Xvfb :98 -screen 0 1080x1920x24 &
                         cd godot && DISPLAY=:98 SIZE=2048 ONLY=king OUT_DIR=../art_sources/app_icon/render \
                           godot --rendering-method forward_plus --path . -s res://tools/render_app_icon.gd
                       (it also writes render/king.png, the icon's square; the build only needs king_wide.png)
king_clean/            the King's textures for the render (godot/tools/clean_king_texture.py): his 512 px Meshy texture
                       redrawn as clean flat paint at 2048 in his own palette, his face and hands kept as painted, and a
                       roughness/metal map (the crown, scepter and chain are gold metal, the gems glassy)
icon.png               the icon flat, 1024 (the backdrop and the King) -- written by godot/tools/build_app_icon.py, which
                       also makes the launcher icons (assets/branding: the King in front, the backdrop behind), the Play
                       icon and the App Store's

concepts/  0.31.200's: gpt-image-2 (1K, medium), two takes each, the title logo and Home's camp painting as references;
           4,784 ElevenLabs credits. On the flow "Fatebound app icon (5v5)" (sNGLKqkKPx0Jv89JIHVM).
  A1, A2   two chibi champions clash -- a Knight and a Barbarian -- sword on axe over the logo's lightning rift (A1 was the
           icon from 0.31.200 to 0.31.209)
  B1, B2   a heraldic shield split by the rift, ice and fire, the crown on it, a sword and an axe crossed behind
  C1, C2   one chibi Knight charging at you, sword up, the crown on his helmet, the rift behind him
