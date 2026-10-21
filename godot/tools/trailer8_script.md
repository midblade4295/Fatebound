# Fatebound trailer 8 -- the 5v5

Kevin's brief: "I want a trailer now. Very cinematic and showing gameplay. Also voice it. I want it to feature the dragon
roaring for climax along with music ramping up to climax then showing the title animating in". Then: "I want it to be
the herald voice. Also change the scene to not show king fight because king has no fight animations so it looks weird.
Also fix pacing because there's several spots where there is no music and nothing happening".

Narrated by the game's Royal Herald (ElevenLabs v4, Edward) over real gameplay: staged moments of an offline 5v5 on the
Rift, filmed by cameras of their own (no HUD, no fog of war, no team or tower rings), golden hour, then dusk for the
Grave Wyrm. The score builds from a dark opening through the battle to a climax on the Wyrm's roar, and never stops: its
silent stretches are cut out (the breath before the drums, most of the drop, the quiet between the title's two hits).
Then the game's own animated title (title_logo.gd: waving flags, the crackling rift, the gold glint) slams in.

Staged in `tools/trailer8_shots.gd` (one run a process: `tools/trailer8_render.sh <run> [W H]`, Movie Maker at 1920x1080
30 fps; SNAP=t1,t2 for stills; RUN=map for a top-down plan of the Rift), cut, graded (S-curve, cool shadows, warm
highlights, vignette), letterboxed (2.39:1) and mixed by `tools/trailer8_edit.py`. Sound in `tools/trailer8_vo/raw/`
(ElevenLabs, on the flow "Fatebound trailer 8 (5v5)": the Herald's narration, the two music cues, the roar, the rumble,
the lightning; the takes used), and the game's own sounds (assets/sounds) placed on their moments, slowed in slow motion.

The score as cut (trailer8_edit.py SCORE): cue A 0.4-15.45 (the opening), 16.38-33.1 (the battle; its drums at 15.2),
34.28-42.7 (a breath, then the climax at 32.02); cue B 0-1.1 (the lightning, 40.19), 3.0-9.5 (the swell into the slam,
42.19, and the chord).

| Time | Picture (run) | The Herald | Sound |
|---|---|---|---|
| 0:00 | fading up: a crane down over our castle at golden hour and down the middle lane (vista) | "Two kingdoms." | cue A: a deep drone, a lone taiko |
| 0:04.6 | their King on his throne, a slow push in, the low sun behind him (kingred) | "One crown." | |
| 0:09.4 | our five charge down the lane at the lens in slow motion: Stormcaller, Dragoon, Knight, Archmage, Golem (charge) | "Rally your team." | a war horn |
| 0:15.2 | the drums crash in (a flash): both lines meet on the ford, every hero casting, time slowing (clash) | | cue A's battle; blades |
| 0:17.2 | the Archmage's METEORS over her shoulder, four of theirs thrown (meteor) | "Eighteen champions." | blasts |
| 0:18.7 | the Dragoon's DRAGON DIVE against the sky (dive) | | his leap and landing |
| 0:20.2 | the Golem's LANDSLIDE through three of theirs, at the lens (slide) | | rocks, the quake |
| 0:21.7 | the Knight and the Barbarian -- the icon -- sword on axe, slow motion (duel) | | the block |
| 0:23.2 | their middle tower comes down in slow motion (tower) | "Break their towers." | the blast, crumbling |
| 0:25.2 | their middle gate smashed in, our five pouring through it, the camera after them, the King on his throne ahead (breach) | "Topple their King." | the gate, the blast |
| 0:31.2 | dusk: three of ours at the Wyrm's pit, the ground shaking (pit) | "But deep in its pit..." | cue A's drop, short; the rumble |
| 0:32.0 | the climax crashes in (a flash): the Grave Wyrm rises out of its pit, slowed (rise) | "...the Grave Wyrm wakes." | the ground breaking; cue A rising 3 dB |
| 0:36.1 | it rears up between our Dragoon and Knight (roar) and pours its soul-fire at the lens (roar2) | | THE ROAR (two takes, slowed) on the music's peak |
| 0:40.2 | the lightning rift splits the dark over the Wyrm's pit, crackling (title) | | cue B's first hit; the lightning |
| 0:42.2 | FATE and BOUND fly in from the viewer and slam home round it with the crown: flash, shake, flags whipping, rays | "Fatebound." | cue B's second hit; the game's title slam |
| 0:43.9 | 5V5 HERO BATTLES | "Five-on-five hero battles." | cue B's chord |
| 0:46.2 | fade to black (0:47.2) | | |

Not in the cut (staged, tried): the King fight (the King has no fight animations: Kevin), the Stormcaller's
THUNDERSTORM and the Mage's INFERNO (thin effects at this scale), the Archer's ARROW RAIN (sparse), the Necromancer's
LEGION. The first cut's narrator ("Don - Movie Trailers") was replaced by the Herald.
