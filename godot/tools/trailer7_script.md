# Fatebound trailer 7 -- "Bring Him Home"

Kevin's brief: a new trailer, very cinematic -- epic music, action sequences, slow motion -- and a climactic end scene
leading to the game title, using the new title graphic with the swinging tied-up King (Home's logo,
`scripts/app/title_logo.gd`).

No narrator: the music carries it, with a few title cards (Cinzel, the game's serif) on the big hits, in the classic
trailer shape -- a dark, slow opening; a build to a dead stop; silence and time all but frozen as two armies meet; the
battle score crashing in on the impact; an action montage cut to the beat; a quiet slow-motion beat as their dungeon is
smashed open; the King carried home at full tilt; the rise into the throne room in slow motion -- and the hit, a white
flash, and the logo slamming in with the King swinging from the impact.

Staged in `tools/trailer7_shots.gd` (short runs, one per process: `tools/trailer7_render.sh <run>`), cut and mixed in
`tools/trailer7_edit.py`, finished (grade, letterbox, cards, flash, title) in `tools/trailer7_finish.py`. Music
(ElevenLabs Music v2.5, written for the trailer) in `tools/trailer7_vo/raw/`: A = musA_3 (prelude), B = musB_1 (battle,
139.7 BPM), C = musC_3 (riser and final hit, same tempo).

| Time | Picture (run) | Card | Music / sound |
|---|---|---|---|
| 0:00 | black | | A: silence, then the first boom |
| 0:01 | the kingdom at golden hour, over our castle to theirs (dawn) | TWO KINGDOMS | A: boom; wind |
| 0:05 | low over the river towards their walls (dawn) | | |
| 0:08 | our King behind bars in their dungeon, torchlit, a slow push in (captive) | ONE STOLEN KING | A: second boom |
| 0:14 | our army formed up behind the gates, a low dolly along the front rank (muster) | BRING HIM HOME | A: the ostinato starts; a war horn |
| 0:17 | the gates swing open, the army moves (muster) | | gates |
| 0:20 | out they pour (muster); both armies charging (charge) | | A: the build, the snare roll |
| 0:27 | the front ranks a step apart -- time all but stops | | A cut dead: silence, a blade drawn |
| 0:28 | the impact: their front rank thrown, in slow motion (charge) | | B crashes in |
| 0:31 | montage on the beat: hammer, whirlwind, meteor, volley, drain, the Sniper, the Assassin, the shield, their gate blown in | 16 VS 16 | B |
| 0:49 | their cell door smashed in, slow motion, from inside the cell (heist) | | B's quiet bars; a heartbeat |
| 0:52 | our King lifted high; out of the dungeon (heist) | | B back at full force |
| 0:55 | over the bridge into the low sun; an ambush, the hammer (slow motion); our gates (carry) | | |
| 1:01 | up into the throne room in slow motion (throne) | | C's rise |
| 1:02 | he's set on his throne: a gold burst, white flash | | C's hit |
| 1:02 | FATEBOUND, the tied-up King swinging from the impact and settling, over the battle far below (titlebg) | (the logo's own "STEAL THEIR KING. SAVE YOURS.") | C rings out; the rope creaks |
| 1:14 | fade to black | | |
