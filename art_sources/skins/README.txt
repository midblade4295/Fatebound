Hero skins (0.31.186, Kevin: "Ok now I want the same IAP system as league of legends" -- the fourth part, hero skins).

A skin is the hero's own rigged model (godot/assets/meshy/<hero>/rigged.glb) repainted by Meshy's retexture API with his
own UV layout kept (enable_original_uv), so the new base colour fits the mesh the game already has: same mesh, rig and
silhouette (every hero still reads as himself -- the reason weapons were the only cosmetic since 0.31.39), only the
paint changes. godot/tools/meshy_retexture.py makes one (10 Meshy credits); godot/tools/build_skins.py turns the 2048
sources here into the game's 1024 textures (godot/assets/skins/<hero>_<line>.jpg, VRAM-compressed: the "skins" pack);
godot/tools/render_skin_icons.gd renders the shop's portraits (godot/assets/ui/skins/<id>.png). The catalog, names and
prices: godot/scripts/meta/economy.gd SKINS.

frostbound/   the first line, every hero (18): <hero>.jpg (the 2048 base colour), <hero>_meshy_preview.png (Meshy's own
              render), tasks.json (task ids, credits, the prompts), prompts.json (the per-hero part of each prompt:
              "Frostbound <hero> skin: the same <hero> character with <...>. Keep the same character, the same face and
              skin tone and the same shapes. Same chunky stylised clay-toy look, clean hand-painted colours, no text.").
              The Priest was made twice: the first take changed his face (darker skin, a goatee) -- the second prompt
              names his face (light peach skin, clean-shaven, short brown hair). 19 retextures, 190 credits.
