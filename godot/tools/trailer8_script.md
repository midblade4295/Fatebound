# Fatebound trailer 8 -- the 5v5

Kevin's brief: "I want a trailer now. Very cinematic and showing gameplay. Also voice it. I want it to feature the dragon
roaring for climax along with music ramping up to climax then showing the title animating in".

A narrated trailer (an epic movie-trailer voice, ElevenLabs "Don") over real gameplay: staged moments of an offline 5v5
on the Rift, filmed by cameras of their own (no HUD, no fog of war, no team rings), golden hour, then dusk for the Grave
Wyrm. The score builds from a dark opening through the battle to a climax on the Wyrm's roar; then the game's own
animated title (title_logo.gd: waving flags, the crackling rift, the gold glint) slams in.

Staged in `tools/trailer8_shots.gd` (one run a process: `tools/trailer8_render.sh <run> [W H]`, Movie Maker at 1920x1080
30 fps; SNAP=t1,t2 for stills; RUN=map for a top-down plan of the Rift), cut, graded (S-curve, cool shadows, warm
highlights, vignette), letterboxed (2.39:1) and mixed by `tools/trailer8_edit.py`. Sound in `tools/trailer8_vo/raw/`
(ElevenLabs, on the flow "Fatebound trailer 8 (5v5)": the narration, the two music cues, the roar, the rumble, the
lightning; the takes used), and the game's own sounds (assets/sounds) placed on their moments, slowed in slow motion.

Cue A's landmarks (musA_1): the first sound 0.5; the drums crash in 16.53 (120 BPM, bars on x.53); the drop 32.55; the
climax crashes in 34.53; it ends 42.6. Cue B (musB_1) at 43.6: a hit, a swell into a second hit at +3.9, a long chord.

| Time | Picture (run) | Narrator | Sound |
|---|---|---|---|
| 0:00 | black, fading up | | cue A: a deep drone, a lone taiko |
| 0:00.4 | over our castle at golden hour, down the middle lane to the haze; the waves meeting (vista) | "Two kingdoms." | |
| 0:05.6 | their King on his throne, a slow push in, the low sun behind him (kingred) | "One crown." | |
| 0:10.6 | our five charge down the lane at the lens in slow motion: Stormcaller, Dragoon, Knight, Archmage, Golem (charge) | "Rally your team." | a war horn |
| 0:16.0 | black | | the breath before the hit |
| 0:16.5 | the drums crash in (a flash): both lines meet on the ford, every hero casting, time slowing (clash) | | cue A's battle; blades |
| 0:18.5 | the Archmage's METEORS over her shoulder, four of theirs thrown (meteor) | "Eighteen champions." | blasts |
| 0:20.0 | the Dragoon's DRAGON DIVE against the sky (dive) | | his leap and landing |
| 0:21.5 | the Golem's LANDSLIDE through three of theirs, at the lens (slide) | | rocks, the quake |
| 0:23.0 | the Knight and the Barbarian -- the icon -- sword on axe, slow motion (duel) | | the block |
| 0:24.5 | their middle tower comes down in slow motion (tower) | "Break their towers." | the blast, crumbling |
| 0:27.0 | four of ours on their King, pushing in on him (kingfight, two stretches) | "Topple their King." | blows |
| 0:32.6 | the drop -- dusk: three of ours at the Wyrm's pit (pit) | "But deep in its pit..." | cue A's drop; the rumble |
| 0:34.5 | the climax crashes in (a flash): the Grave Wyrm rises out of its pit, slowed (rise) | "...the Grave Wyrm wakes." | the ground breaking; cue A rising 3 dB |
| 0:38.6 | it rears up between our Dragoon and Knight (roar) and pours its soul-fire at the lens, low in front of it (roar2) | | THE ROAR (two takes, slowed) on the music's peak |
| 0:42.6 | black | | cue A ends; the roar's tail |
| 0:43.6 | the lightning rift splits the dark over the Wyrm's pit; it crackles (title) | | cue B's first hit; the lightning |
| 0:47.5 | FATE and BOUND fly in from the viewer and slam home round it with the crown: flash, shake, flags whipping, rays | "Fatebound." | cue B's second hit; the game's title slam |
| 0:49.2 | 5V5 HERO BATTLES | "Five-on-five hero battles." | cue B rings out |
| 0:55.6 | fade to black (0:56.6) | | |

Not in the cut (staged, tried): the Stormcaller's THUNDERSTORM and the Mage's INFERNO (thin effects at this scale), the
Archer's ARROW RAIN (sparse), the Necromancer's LEGION.
