# Quest weapons (Armory Reforged) -- raw Meshy models, not in the game yet

Made 2026-10-10 with the rest of the class weapons (0.31.94) so the quest line can use them later. Each is the raw
Meshy image-to-3D output (`<id>.glb`) and the cropped parts-sheet image it was made from (`<id>.png`). To put one in
the game, fit it like the others (`godot/tools/meshy_weapon.py fit RAW TEMPLATE OUT KIND --axes ...`) and add it to
`MESHY_WEAPON_LIKE` in `godot/scripts/siege/siege_view.gd`.

| Piece | Class | Suggested template, kind, axes |
|---|---|---|
| dawnpiercer_bow | Archer | bow_withString, box, auto |
| goldensledge_hammer | Worker | bits/hammer_D, pole, X,Y,Z |
| bloodroar_demon | Berserker | bits/sword_E, pole, X,Y,Z |
| lichcrown_staff | Necromancer | Skeleton_Staff, pole, -Z,Y,X (skull to the template's face, -X) |
| lastbreath_dagger | Assassin | bits/dagger_C, pole, autoy |
| hawksjudgment_crossbow | Ranger | crossbow_2handed, box, auto |
| astral_staff + astral_book | Archmage | bits/staff_D, pole, X,Y,Z + spellbook_open, handheld, X,Y,Z |
