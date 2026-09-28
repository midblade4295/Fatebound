# Siege conversion — progress log

Goal (Kevin, 2026-09-28): Siege becomes the whole game. Add gathering + crafting, a proper
castle per team (walls, rooms, cell), gates that open for allies and must be broken by enemies.
Renderer stays Vulkan.

Each step is committed separately; this file is updated in the same commit.

| Step | Scope | Status |
|---|---|---|
| 1 | Sim: castle walls/rooms, gates (HP, ally-open, break, repair), wall collision, nav grid pathing | done |
| 2 | Sim: Worker class, trees/rocks, carry + stockpile, workshop upgrades, team commander | done |
| 3 | View: castle from KayKit kit, animated gates, cell, stockpile, worker visuals | done |
| 4 | HUD: resources, gate health, workshop panel, worker actions | done |
| 5 | Siege is the game: home entry, rewards into progression, hide dice-only modes | done |
| 6 | Tests, screenshots, perf check, APK | done (0.8.0, version code 16) |

## Layout (blue = team 0 at +z; red is the point mirror (x,z) -> (-x,-z))
- Field x -13..13, z -29..29. Walls use wall_straight x2.6 (5.2 long).
- Front wall z=15 (5 segments), gates at x=-5.2 and x=+5.2.
- Courtyard z 15..21: spawn (0,18.5), forge (-8,18), workshop/stockpile (8,18).
- Inner wall z=21 with doorways at x=-7.8 (dungeon) and x=+7.8 (throne room).
- Keep (castle model) blocks centre back x -2.6..2.6, z 22..29.
- Dungeon (west back room): cell holding the ENEMY Oracle at (-8,25.5).
- Throne room (east back room): own Oracle is delivered to (8,25.5).

## Step 1+2 results (6 bot-vs-bot matches, seeds 11..66)
- 0 wall clips, 0 gate clips (checked every 3 ticks for every unit).
- Gates broken 28x, rebuilt 21x; 1,585 resources delivered; 21 upgrades bought.
- Match length 255-540 s (win at 3 rescues, 9 min cap); first rescue 64-295 s.
- Tuning: gate 1500 HP; repair 30 HP/tick, 1 wood per 2 ticks; Oracle carry ~0.5x speed;
  2 workers per 6-player team (one wood-first, one stone-first); repair below 40 % only.
- Known: red won 4 of 6 (small sample; watch for side bias).

## Step 3 notes
- Gate segment narrowed to the model's doorway (+/-1.3 m); neighbouring wall ends cover the
  pillars, so allies can't walk through stone. Re-verified 0 clips.
- Cell bars are real sim walls on three sides (open front), not decoration.
- Door pivots are on their outer edges in wall_straight_gate, so doors rotate on their hinges.
- Verified by Vulkan screenshots: overview, gate (doors open for allies), dungeon cell, courtyard.

## Step 4 notes
- Workshop panel (TAKE TOOLS + 3 upgrades with costs/levels), forge shows 3 or 4 dice,
  WOOD/STONE + load readout, our two gates as HUD bars, world bars over damaged gates,
  action labels CHOP/MINE/REPAIR/WORKSHOP, toasts for gate breaks/rebuilds/upgrades.
- Verified by Vulkan screenshots; all test suites pass.

## Step 5 notes
- Home: SIEGE card with ENTER BATTLE (+ how-to line, diagnostics). Removed from home: Daily
  Raid link, Hero Academy (dice training), daily quests card (dice goals Siege can't progress),
  Siege alpha card. Dice-mode code is kept but unreachable from the UI (tests still reach it).
- Rewards via progression.grant(): win 120g/60xp/12pts/+chest, draw 70/40/8, loss 40/25/5;
  +40g +15xp per personal rescue, +4g per KO, +1g per resource delivered, +1g per 50 gate dmg.
  Granted once per match (PLAY AGAIN does not re-grant). Shown on the result panel.
- tests/siege_home_flow.gd: home -> ENTER BATTLE -> win -> gold/xp/pts/chest saved -> replay -> home.

## Step 6 notes
- Vulkan perf (software renderer, relative): own courtyard 269 draws / 181k tris, midfield
  254 / 176k, enemy gate 157 / 115k. 0.7.8-0.7.10 ran clean on the S21 Ultra at ~240-300 draws.
- 0.8.0 APK: Vulkan renderer, castle assets and new scripts verified inside the package.

## Not done yet / next candidates
- Online: the real-time server (M3) is still to do; Siege is offline vs bots.
- Hero page, shop weapons and dice-era power stats still exist from the dice game and don't
  affect Siege classes yet. Daily quests hidden (their goals were dice actions).
- Fate offerings (the "cake" mechanic), catapults, ladders are not in yet.

# Round 2 (Kevin, 2026-09-28): castle layers + stairs, 100 % resolution, "the rest of stuff"
| Step | Scope | Status |
|---|---|---|
| R1 | 3D at 100 % of PHYSICAL pixels (old code used the canvas scale = 1.0, so it rendered at the logical 336x746 on a 1440x3200 screen); pause-menu Resolution 100/75/50; MSAA off at 100 %; thermal guard step 2 drops to 75 % | done |
| R2 | Castle layers: raised throne room + dungeon platforms with stairs, midfield plateau with stairs; heights in sim (ledges = walls), view builds platforms/steps | done |
| R3 | Fate offerings (the cake): altar spawns offerings; feeding the captive enemy Oracle makes her heavier/slower to carry; visibly fatter | todo |
| R4 | Catapult towers (workshop upgrade): auto-fire at enemies near your walls | todo |
| R5 | Siege ladders: workers build a ladder on an enemy wall; a private passage for their team; enemies can break it | todo |
| R6 | Tests, screenshots, perf at 100 %, APK | todo |

## R2 notes
- The inner wall hid the platforms from every useful angle, so it was replaced by the terrace
  itself: a 1.6 m retaining edge (ledge) with a stone parapet, cut by two 8-step staircases.
  Keep still separates dungeon from throne room. Midfield plateau 1.2 m with 6-step stairs N/S.
- Cell moved to (-9, 27) (blue space): at (-8, 25.5) the stair ledge end and bar end left a
  0.35 m gap on the 1 m nav grid, so the cell was unreachable.
- Arrows/fire pass over ledges and through cell bars.
- tests/siege_reach.gd: every objective reachable for both teams (enemy cell, own throne,
  forge, workshop, plateau). 6-match smoke: 0 clips, wins 3-3.
