# KayKit assets used by the native 3D battlefield

All packs are by Kay Lousberg (www.kaylousberg.com) and released under CC0; the licence
texts are kept alongside as `LICENSE-*.txt`. Only the models the game uses are copied here.

| Folder | Pack | Source used for this import |
| --- | --- | --- |
| `hex/` | KayKit Medieval Hexagon Pack 1.0 | github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 (gltf) |
| `forest/` | KayKit Forest Nature Pack 1.0 (FREE) | owner-supplied zip, 2026-09-27 |
| `heroes/`, `weapons/` | KayKit Adventurers 2.0 (FREE) | owner-supplied zip (Dice Skirmish work) |
| `anim/` | KayKit Character Animations 1.1, Rig_Medium General/CombatMelee/CombatRanged | owner-supplied zip |

Hero order matches the v114 `CHARS` table (Knight, Rogue_Hooded, Barbarian, Mage, Ranger) and
weapon order matches `WEAPONS` (sword, dagger, axe_1handed, sword_2handed, axe_2handed, staff,
wand, bow_withString, crossbow_2handed). Weapons attach to the rig bones `handslot.r` / `handslot.l`;
the bow and crossbow need a π yaw so they are not held backwards.

The golden d12 face atlas in `../dice/die_faces.png` is generated for this project (not KayKit).
