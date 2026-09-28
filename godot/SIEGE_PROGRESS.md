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
| R3 | Fate offerings (the cake): altar spawns offerings; feeding the captive enemy Oracle makes her heavier/slower to carry; visibly fatter | done |
| R4 | Catapult towers (workshop upgrade): auto-fire at enemies near your walls | done |
| R5 | Siege ladders: workers build a ladder on an enemy wall; a private passage for their team; enemies can break it | done |
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

## R3 notes
- Altar per courtyard at (-3.5, 17) (blue space); an offering every 30 s. Carrying one: no
  attacks, 0.9x speed, lost on death. Feed within 1.9 m of the captive in your dungeon.
- Weight 0-5; carrier speed x(1 - 0.08*weight). Weight survives drops/recaptures, resets on
  rescue. Oracle widens 16 % per level. Defender bots feed when there's no alarm/carrier.
- 6-match smoke: 77 feedings, max weight 5 reached; 0 clips; half the matches now run to the
  9-minute cap (heavier carries).

## R4/R5 notes
- The sim code for both was found uncommitted after an interrupted session, failing its own
  test (0 catapult shots, 1 ladder in 6 matches). Finished and tuned:
  catapult 15 wood/25 stone; quartermaster now saves toward a planned upgrade; repairs cost
  1 material per 3 ticks; ladder builder condition relaxed.
- Fixed a clip the interrupted cell move introduced (bars 0.4 m from the field edge) and clamp
  to the field before wall push-out.
- 6-match smoke: 0 clips, catapults bought in 2/6 matches (47 shots), 3 ladders (1 knocked
  down), 67 feedings. Bots rarely use these; players can buy/build them directly.
- View: turret turns to the target, arm throws, stone flies in an arc, impact ring; ladders
  lean on the outside of the enemy wall and splinter when knocked down. HUD: LADDER action,
  Catapults in the workshop, ladder toasts. Verified by Vulkan screenshots.
- Known: red won 4 of 6 bot matches in recent runs; watch for side bias.

# Round 3 (Kevin, 2026-09-28): much larger land, 16v16, princess mechanics from his screenshots
| Step | Scope | Status |
|---|---|---|
| A | Field 26x58 -> 52x104; castles keep their layout (castle-local coords via Sim._c), gain side walls; nav grid built by stamping bboxes; resources spread over the land; 16 per team | done (cake trees moved to B) |
| B | Oracle: cake -> size stages (1..6 lifters needed); multi-player lift; captors carry a dropped Oracle back (no instant recapture); tantrum knockback+stun when left on the ground; healing aura for her team while captive | done |
| C | Tests, perf (32 units), APK | todo |

## Step A notes
- Sim cost at 16v16 was 2.36 ms/tick, 1.73 of it in _separate (every unit vs every wall).
  6 m spatial buckets for walls/obstacles: 0.99 ms/tick (profile: tests/siege_profile.gd).
- Stalemate at 16v16 (0 gates broken in 12 min): 5 workers/team out-repaired the assault.
  Repairs now pause while a gate was hit in the last 3 s; role mix 7 raid/3 escort/3 defend/3 work.
- After that: 23 gate breaks, 37 pickups, but 0 rescues in 2 matches (carriers die on the ~90 m
  run). To be tuned after step B's mechanics (captor carry-back, tantrum, healing aura).

## Step B notes
- 6 cake trees (3 mirrored pairs) replace the courtyard altars; a cake every 40 s; 2 cakes per
  size stage; stages 0..5 need 1..6 lifters. Rescue resets her; drops/returns keep her size.
- Lift: first lifter leads (a human who joins takes the lead); followers ride a ring around the
  lead and are wall-resolved after placement (344 clips before that fix). Too few hands -> she
  won't move. Captors lift a dropped Oracle and carry her back to their cell.
- Dropped: tantrum after 6 s (then every 6 s): 4 m knockback + 1.6 s stun within 5 m; back to
  her cell after 25 s. Captive: heals her own team within 3.2 m at 12 hp/s.
- 2-match smoke: 0 clips; fed 37 (max size reached), lift groups up to 4, 6 carry-backs,
  1 tantrum, 2 rescues (both while skinny). Verified by Vulkan screenshots.
