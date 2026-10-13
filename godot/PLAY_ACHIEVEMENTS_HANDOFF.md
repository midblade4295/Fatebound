# Google Play Games achievements (0.31.119) -- for Grokbot / Kevin

The game sends 18 achievements to Google Play Games (scripts/meta/achievements.gd), read from the player's account on
the Siege server (so a changed save can't fake them). Nothing is sent until each one exists in Play Console and its id
is filled in. Needs Play Games Services already set up for the game (see PLAY_GAMES_HANDOFF.md: the Game ID on the
"Android Play Store" preset).

## Steps (Play Console, then one file)
1. Play Console > Fatebound > Grow users > Play Games Services > Setup and management > **Achievements** > Add
   achievement, once per row below: Name, Description, Icon (the 512x512 PNG listed), Incremental on/off (+ steps),
   Points. Initial state: **Revealed**. List order = the table's order.
2. Copy each achievement's **ID** (like `CgkI...EAIQAQ`) into `godot/scripts/meta/play_achievement_ids.gd` next to its
   key. An empty id is skipped, so they can be filled in a few at a time.
3. Publish the achievements (Play Games Services > Publishing) and build the AAB as usual (tools/build_play_release.sh).
   Testers on the testers list see them before publishing.

Points total 570 (Play allows up to 1,000 per game, so there's room for more later).

## The achievements
| # | Key (id slot) | Name | Description | Type | Steps | Points (XP) | Icon |
|---|---|---|---|---|---|---|---|
| 1 | `welcome` | Welcome to the Siege | Finish the tutorial. | Standard | - | 5 | `store-listing/achievements/welcome.png` |
| 2 | `first_blood` | First Blood | Knock out an enemy. | Standard | - | 5 | `store-listing/achievements/first_blood.png` |
| 3 | `first_victory` | First Victory | Win a match. | Standard | - | 10 | `store-listing/achievements/first_victory.png` |
| 4 | `kings_rescue` | Long Live the King | Carry your King home from the enemy dungeon. | Standard | - | 10 | `store-listing/achievements/kings_rescue.png` |
| 5 | `many_hats` | Many Hats | Play a match as each of the 7 classes. | Incremental | 7 | 20 | `store-listing/achievements/many_hats.png` |
| 6 | `fattening` | Fattening Season | Feed 25 fish to the enemy King. | Incremental | 25 | 15 | `store-listing/achievements/fattening.png` |
| 7 | `lumberjack` | Lumberjack | Gather 500 wood or stone. | Incremental | 500 | 15 | `store-listing/achievements/lumberjack.png` |
| 8 | `gatecrasher` | Gatecrasher | Deal 10,000 damage to enemy gates. | Incremental | 100 | 20 | `store-listing/achievements/gatecrasher.png` |
| 9 | `heavy_lifting` | Heavy Lifting | Help lift your King 50 times. | Incremental | 50 | 20 | `store-listing/achievements/heavy_lifting.png` |
| 10 | `centurion` | Centurion | Knock out 100 enemies. | Incremental | 100 | 20 | `store-listing/achievements/centurion.png` |
| 11 | `relentless` | Relentless | Win 5 matches in a row. | Standard | - | 30 | `store-listing/achievements/relentless.png` |
| 12 | `unstoppable` | Unstoppable | Knock out 5 enemies in one burst. | Standard | - | 40 | `store-listing/achievements/unstoppable.png` |
| 13 | `bodyguard` | Royal Bodyguard | Rescue your King 25 times. | Incremental | 25 | 40 | `store-listing/achievements/bodyguard.png` |
| 14 | `master_smith` | Master Smith | Forge a weapon to 3 stars. | Standard | - | 40 | `store-listing/achievements/master_smith.png` |
| 15 | `seasoned` | Seasoned | Reach level 20. | Incremental | 20 | 40 | `store-listing/achievements/seasoned.png` |
| 16 | `siege_lord` | Siege Lord | Win 50 matches. | Incremental | 50 | 60 | `store-listing/achievements/siege_lord.png` |
| 17 | `slayer` | Slayer of Thousands | Knock out 1,000 enemies. | Incremental | 1000 | 80 | `store-listing/achievements/slayer.png` |
| 18 | `legend` | Legend of the Siege | Win 250 matches. | Incremental | 250 | 100 | `store-listing/achievements/legend.png` |

Total points: 570 (Play allows up to 1,000).

All icons side by side: `store-listing/achievements/_all.png` (bronze rims = first steps, silver = mid, gold = hard).

## How the game sends them
- Only while signed in to Play Games (the Play build), every 5 s it compares the account's numbers with what it last
  sent this run: an incremental achievement gets `setAchievementSteps(id, total)` (Google never goes backwards, so
  sending the total again is harmless), a standard one `unlockAchievement(id)` once its goal is met.
- Settings > GOOGLE PLAY > ACHIEVEMENTS opens Google's own achievements screen.
- The preview APK has no Play Games plugin: nothing there.

## Status
- 2026-10-13 (0.31.121): all 18 created in Play Console (Game ID 1022979193240) and their ids filled in
  `scripts/meta/play_achievement_ids.gd`; tests/achievements_test.gd checks every id is there, different, of this game
  and in the table's order. Gatecrasher: the profile's `gates` stat is 1 per 100 gate damage (Eco.match_stats, whole
  hundreds per match), so its 100 steps = 10,000 damage. The Game ID is also set on the "Android Play Store" preset on
  this branch (as Grokbot did on grok/siege-play-local-r19). Left: publish the achievements, build the AAB, try them
  on a tester account.
