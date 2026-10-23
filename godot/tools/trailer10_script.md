# Fatebound trailer 10 -- the vertical gameplay trailer, told by the Herald

Kevin: "Now make a gameplay trailer that shows the actual game off from a players perspective. Make the trailer vertical.
Make it voiced by herald and make very funny. Show how the game flow goes and also show some other things like guilds,
heros, how battles go ect. Do not put captions so players can focus on watching gameplay instead of reading."

A 9:16 trailer (1080 x 1920, 30 fps, -14 LUFS, 78.8 s) of the real game as a player sees it on a phone: the app's screens and
offline 5v5 matches against bots, with the HUD, the game's camera and fog of war, every button pressed through the
HUD's own touch path or the button's own press, and a fingertip drawn where the screen is touched (a phone's "show
taps"). The Royal Herald narrates (ElevenLabs v4, his voice "Edward - British", the same as his tutorial, match calls
and kill banners), dry and sarcastic as in the tutorial, his running joke the King's very comfortable chair. No
captions: the only words on screen are the game's own (its HUD, banners and menus). The game's own sound is in every
take (Movie Maker's track: the hits, the spells, the HUD, his in-game calls DOUBLE KILL / FIRST BLOOD / VICTORY), and
the game's theme (assets/music/match.ogg) runs under it all, dipping under him.

## The flow

| Time | Picture (take) | The Herald |
|---|---|---|
| 0:00 | a teamfight in the river: your Stormcaller's static field and storm -- a kill, then DOUBLE KILL (the game's own call) (hook) | "Ah! That's you. Being magnificent." |
| 0:05.3 | the fight played backwards, fast, like a tape; the theme stops like a tape | "Right. Let's back up a bit." |
| 0:06.0 | Home: the champions round the fire, a party of three, PLAY, the chests (home) | "This is Fatebound. Five heroes versus five." |
| 0:10.4 | the first seconds of a match: you step out toward our King on his throne (chair) | "Two Kings... on two very comfortable chairs." |
| 0:14.3 | the ARMORY tab tapped, the heroes dragged past: tanks, fighters, assassins, mages (armory) | "Eighteen heroes. Knights. Wizards." |
| 0:17.6 | the Golem's window: him in 3D on his stage, in his Geode outfit (golem) | "A large, angry rock. Pick whoever matches your personality." |
| 0:21.8 | the Stormcaller's window, his outfits tapped in turn: his own look, Frostbound, Stormforged (outfit) | "Then dress them up. You may still lose... but you'll lose fabulously." |
| 0:26.8 | the ALLIANCE tab: the Iron Wolves' camp, then its members (clan) | "Join a clan. Friends to fight beside. And to blame. Mostly to blame." |
| 0:31.8 | Home's PLAY -> the hero window, the Stormcaller tapped (play) | "Press PLAY, and your team assembles." |
| 0:33.7 | the loading screen as the players join, each hero dropping in in his outfit, the countdown (lobby) | "Roughly on time." |
| 0:37.2 | a minute in: up the middle lane behind our wave, theirs meeting it at the river; ATTACK (lane) | "Follow the minions. Brave little lads. Nobody writes them songs." |
| 0:41.8 | three minutes in: their Barbarian charges -- CHAIN LIGHTNING, STATIC FIELD, GUST, the storm -- FIRST BLOOD (fight) | "See an enemy? Press every button you have. Strategy can wait." |
| 0:47.1 | chasing their Golem under their tower, low on health: he turns round -- "Grimwald has slain Midblade", RESPAWNING IN (death) | "And when you die... I announce it. To everyone." |
| 0:51.5 | their middle tower, a wave of ours under it, you on it: it falls (tower) | "Knock down their towers. They had it coming." |
| 0:55.7 | the Grave Wyrm up in its pit, three of ours on it (wyrm) | "This is the Grave Wyrm. Never poke the Grave Wyrm." ... "They always poke the Grave Wyrm." |
| 1:02.3 | their keep open, the King on his chair: four of ours on him -- VICTORY (the game's own call), YOU ARE THE MVP (king) | "Then knock their King off his chair. He'll be furious." |
| 1:08.3 | Home: a Royal Chest -- OPEN -- a Dragoon shard, gold, gems (chest) | "Win, and there's loot. Lovely, shiny loot." |
| 1:12.7 | the app's own opening: the title flies in and slams onto the wall (its jingle), TAP TO START (title) | "Fatebound." ... "Go on, then. Their King won't fall off that chair by himself." |

## How it's made
- `tools/trailer10_shots.gd` stages each take (RUN=<run>): the app runs a mid-game profile (never the live server: the
  friends and the clan are sample data, tools/store4_app.gd's); the matches are offline 5v5s staged like
  tools/store4_match.gd's, in motion (who stands where, levels, the clock, sample player names and clan tags), you the
  Stormcaller in his Stormforged outfit. `tools/trailer10_render.sh <run>` records a take with Movie Maker at 1080 x
  1920 with the game's own 420 x 780 design size stretched to it, as on a phone (SNAP=t1,t2 for stills).
- `tools/trailer10_edit.py --rec <dir> --out <mp4>` cuts and mixes it (`--times` prints the plan). The Herald's lines
  are cut from his read by its word timings (tools/trailer10_vo/raw: two takes of the whole script and their
  ElevenLabs Scribe alignments), a touch brisker (x1.07, pitch kept), each levelled.
- The cut (trailer10_edit.py SHOTS): the hook 0-5.3 s of its take, then 1.0-5.3 backwards at 6x (the rewind: colour
  fringes and grain, its sound backwards and pitched up, the theme stopping like a tape and starting again from the top
  on Home); the Armory in three pieces (the tanks, a flick down the list at 2.5x, the mages) so "Knights" and "Wizards"
  land on them; the PLAY take ends on the hero picked (on a 9:16 screen the hero window's BATTLE is below the screen).
  The Herald's lines sit between the game's own calls (DOUBLE KILL at 1.4 s, FIRST BLOOD, VICTORY); his whispers +3 dB.
  The theme dips 12 dB in the voice band and 4 dB overall under him, the game's sound 9 dB in the voice band.
- Takes used: the Herald's take 2 for every line but "They always poke the Grave Wyrm." and "Fatebound." (take 1).
- ElevenLabs (flow "Fatebound trailer 10 (vertical gameplay, the Herald)", R7eUCVBIbKvO8oU4Aa1b): the read, two takes,
  2,042 credits (estimated first); the word timings, 0.
