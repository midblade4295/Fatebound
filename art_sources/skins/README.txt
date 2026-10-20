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

0.31.188 (Kevin: "Remove the forge and the individual weapon skins. I only want the cosmetics to be an entire outfit.
Each outfit has its own specific looking weapon" ... "Make all new sets for every hero and make each one unique to their
class and lore along with the weapons to go along with each skin"): every cosmetic is a whole outfit -- the body's paint
and the weapon in his hands. economy.gd OUTFITS / SKINS.

outfits/      each hero's own set (18, epic, 750 gems): <hero>.jpg (2048) and <hero>_meshy_preview.png, made like the
              Frostbound line with the set's look in the prompt (tasks.json: task ids, credits, prompts). Lionguard
              Knight, Mammoth Hunter Barbarian, Velvet Thief Rogue, Orchard Warden Archer, Phoenix Mage, Bellringer
              Priest, Ashen Templar Crusader, Blood Moon Berserker, Red Ribbon Assassin, Wolfstalker Ranger, Stargazer
              Archmage, Gravekeeper Necromancer, Geode Golem, Dragonscale Dragoon, Golden Rose Duelist, Stormforged
              Stormcaller, Privateer Musketeer, Cherry Blossom Druid. take1/ holds the first takes that were set aside:
              the Archmage, Necromancer, Duelist and Stormcaller came back with other faces (a brown beard, a normal
              face, a beard, brown hair), the Barbarian's bear hood didn't change, and the Rogue's mask read as a grey
              beard -- each made again with his face named in the prompt (the Barbarian's set is called Mammoth Hunter:
              Meshy repaints, it can't reshape the bear hood). 18 + 6 retextures, 240 credits.
outfits/weapon_sheets/
              the sets' own weapons (23 pieces: a sword and shield for the Knight, twin daggers for the Rogue, a staff
              and a star-chart tome for the Archmage...). sheet_A_* / sheet_B_* are the concept sheets (two takes
              each, 12 pieces a sheet; the pieces were cut from them with godot/tools/meshy_weapon.py crop), pick/ the
              take chosen for each, meshy/ Meshy's image-to-3D tasks (<piece>.task: its id and model -- meshy-7.1 at
              4,000 polys or meshy-6-lite at 3,000 -- and a thumbnail; the raw downloads aren't kept, as with the
              0.31.93 weapons: the fitted pieces in godot/assets/meshy/weapons are the models). Each was fitted into the space of the KayKit
              piece it is held like (meshy_weapon.py fit; siege_view.gd MESHY_WEAPON_LIKE) and lives in
              godot/assets/meshy/weapons/<piece>.glb; weapon_fx.gd SIGNATURE gives each its glow and particles.
frostbound/weapons/
              Frostbound keeps the hero's own weapon, repainted in frost: each of the 23 heroes' own pieces through
              Meshy's retexture (meshy_retexture.py mw/<piece>; 23 x 10 credits) -> godot/assets/skins/weapons/
              <piece>_frost.jpg (512, build_skins.py), painted on at run time (siege_view.gd apply_weapon_skin).
              Frostbound became the cheaper line (rare, 390 gems).
