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

## Step C: balance (16v16 had 0 rescues in 4 matches)
- Found after an interrupted session: uncommitted sim changes + tests/_trace.gd (kept as
  tests/siege_trace.gd). Reviewed and tested before committing:
  rubble (broken gate can't be rebuilt for 20 s or with an enemy within 6 m); cake every 60 s,
  3 cakes per stage; carry 0.65x (rogue 0.72x), +10 % per extra lifter; bots wait for enough
  hands before lifting; tantrum knockback moves in steps and stops at walls.
- Blessing (NOT in Kevin's screenshots, added for balance): while her own team carries her she
  heals them within 4.2 m. Same 4 seeds: 7 rescues with it, 2 without. One constant (BLESS_R).
- 6-match smoke: 0 clips, 10 rescues (was 2), 49 gate breaks, 56 feedings; 1 match won 3-2 on
  rescues, the rest went to time. Bots rarely raise ladders at 16v16; the smoke test now reports
  catapults/ladders instead of asserting them, and asserts at least one rescue.

# Round 4 (Kevin, 2026-09-28): online multiplayer on his server ("ssh")
| Step | Scope | Status |
|---|---|---|
| N1 | Protocol (scripts/siege/siege_net.gd), headless authoritative server (server/siege_server.gd), online client in siege_mode | done |
| N2 | Home "PLAY ONLINE", Vulkan screenshot of an online match | done |
| N3 | Deploy kit for 136.113.125.3 (systemd, Caddy fragment, install script), docs, APK | done (not deployed: needs Kevin/his agent on the server) |

## N1 notes
- Server = the real SiegeSim, headless Godot, WebSocket on 127.0.0.1:8082 (8080 web/saves,
  8081 old arena, 3000 Legionary are taken). Bots fill every slot; a joining player takes a bot
  on the team with fewer humans; a leaver's unit goes back to a bot. New match 15 s after one
  ends; stops simulating after 30 s with nobody connected.
- Client = mirror SiegeSim (same map from setup) overwritten by 10 Hz snapshots, positions
  interpolated between snapshots; inputs at 20 Hz + actions immediately. View/HUD unchanged.
- Snapshot: unit values as int16 (1 cm, 0.001 rad), zstd. 32 clients: 845 B/snapshot,
  8.3 KB/s per phone, 267 KB/s server upload, 9.9 % of one core, 118 MB RSS.
- tests/siege_net_smoke.gd (REAL time, no --fixed-fps): server process + game client + raw
  client: seating, snapshots, touch movement, forge through the server, leave -> bot. PASS.

## N2/N3 notes
- Home SIEGE card: PLAY ONLINE (16 vs 16) under ENTER BATTLE; card text fixed (was "6 vs 6").
  Verified on Vulkan: real app -> PLAY ONLINE -> local server -> match renders from snapshots.
- server/deploy: fatebound-siege.service (DynamicUser, read-only, loopback :8082),
  caddy-route.fragment (printed, not applied), install_siege_server.sh (Godot 4.7.2 SHA-512
  verified download, 176 KB server-only project, service, PROBE_OK). Tested in NO_SYSTEMD mode
  with a real download, and as user nobody from a read-only folder.
- Test runner now includes siege_net_smoke (12 suites, all pass).

# Round 5 (Codex, 2026-09-28): fail-closed Vulkan Android export
- The 0.11.0 server/client source and all 12 suites passed, but the rebuilt APK packed
  `renderer/rendering_method=gl_compatibility`. The old build check depended on the optional
  `strings` command; when it was absent, the pipeline printed an error and still reported OK.
- Set the base and mobile renderer settings to `mobile`, disabled the OpenGL fallback, replaced
  the APK check with a Python verifier that fails closed, and routed CI through the same checked
  build script. Bumped the preview to 0.11.1 / version code 20.
- Made the real-time network smoke deterministic: the original fixed northward touch could hit
  a wall from randomized spawns. It now drives the real touch stick along the mirror nav path,
  requires authoritative movement over 3 m, and retains an 8 s hard failure bound. The raw test
  client also sends its hello once the socket opens instead of relying on a narrow timing window.
- Verification: all 12 suites pass in the quick runner; the final network smoke also passed five
  consecutive standalone server/client runs.

# Round 5 (Kevin, 2026-09-28): Siege-only app, new home, battle pass, shop, economy, UI fidelity
Branch `claude/siege-dev-r5` from live `447b97a`. "Remove everything that had to do with the old
version, everything will be the siege now."
| Step | Scope | Status |
|---|---|---|
| E1 | New economy + profile (scripts/meta): currencies, levels, Siege Pass, challenges, shop catalog/rotation, match rewards, one-time migration from the old save (old file untouched) | done |
| E2 | Siege uses the profile: rewards breakdown, challenge progress, equipped cosmetics shown in battle | done |
| E3 | New app shell + screens: Home (3D hero showcase, PLAY offline/online), Pass, Shop, Locker, Settings | done |
| E4 | Remove the old dice-era app (pages, full_client, battle/raid/training/guild/arena code, old tests) | done |
| E5 | UI fidelity: new theme, icons, transitions; screenshots | done |
| E6 | Tests, APK | todo |

Design (all cosmetic; no pay-to-win; no real-money purchases until Play Billing exists):
- Gold (soft, matches), Gems (premium, earned: pass, challenges, level-ups). Old gold -> gold 1:1,
  old tokens -> gems 1:1, old owned weapons/chests -> gold, old level kept, old Fate dropped.
- Siege Pass: 42-day seasons, 30 tiers x 1000 pass XP, free + premium (gems) tracks.
- Challenges: 3 daily + 3 weekly from Siege stats. First win of the day bonus.
- Shop: daily rotation (gold), weekly featured (gems), gems -> gold exchange.
- Cosmetics: per-class color variants (tinted KayKit models) and weapon/off-hand variants from
  the KayKit weapons pack; titles.

## E1 notes
- scripts/meta/economy.gd (pure tables/functions), scripts/meta/profile.gd (state, atomic save to
  user://siege_profile.json, migration, all operations). Season 1 starts 2026-10-01 UTC.
- 29 cosmetics (per-class tints + KayKit weapon/off-hand variants + titles); 17 weapon models
  added from the Adventurers pack. Shop: 4 daily gold items, 2 weekly gem items, gem->gold.
- Bug caught by the tests: JSON loads numbers as floats and the normaliser treated that as a
  type mismatch, resetting gold/gems/level to defaults on every load. Fixed; claimed tiers and
  challenge progress are re-cast to ints on load.
- tests/meta_economy_test.gd: 45 checks (migration, rewards, levels, pass/premium, shop, equip,
  challenges, rollover, persistence, corrupt file, catalog integrity). PASS.

## E2 notes
- siege_mode: rewards via profile.apply_match (offline + online); Oracle lifts counted from the
  player's own lift_join events (no protocol change). The old shell gets a profile until E3/E4.
- siege_view: player_looks (tint + weapon/off-hand per class) for the LOCAL player only. The tint
  is a cached duplicate of the model's StandardMaterial3D with albedo multiplied, set once when
  the body is built (never per frame). NOTE for any future freeze: this is a static material
  override on a skinned mesh (the 0.7.8 removal list included animated emission overrides).
  Other players online still show default looks (would need a protocol change).
- Results panel: itemised lines (+gold/+pass), totals, level-ups, pass tier reached, challenge
  progress; fixed rows overflowing the screen (label helper forces 290 px min width).
- Test runner now also runs meta_economy_test (13 suites).

## E3 notes
- scenes/Main.tscn now runs scripts/app/siege_app.gd (the dice-era full_client is no longer the
  entry; its code is removed in E4).
- scripts/app: ui.gd (palette, tactile buttons, cards, bars), icon.gd (procedural icons),
  showcase.gd (3D hero on a stone dais, physical-pixel SubViewport, transforms only per frame),
  screens.gd (Home, Pass, Shop, Locker, Settings), siege_app.gd (chrome, tabs, toasts, confirm
  dialogs, match launch, back button, safe-area top inset).
- Found while testing: overlay labels created before their parent had a width wrapped one
  letter per line (title drawn mid-card); the name box limit applied before trimming spaces.
- tests/app_flow_test.gd (21 checks, real time): buy with gold and with gems (confirm), equip,
  pass claim/premium/claim-all, challenge claim + reroll, rename, offline match -> rewards ->
  home, unreachable online server -> home, back button, persistence. PASS.
- Settings links PRIVACY_URL https://136-113-125-3.sslip.io/fatebound/privacy.html (unverified
  from here).

## E4 notes
- Removal driven by a reachability scan from the new app, Siege, server and their tests (not by
  guesswork). The only link left to old code was siege_view -> kaykit_stage for a 4-line scene
  cache, now scripts/siege/asset_cache.gd.
- Removed: full_client, main, pages, battlefield, dice_strip, kaykit_stage, spell_fx, arena
  api/wire, scripts/game/* (progression, content, raids, training, campaign, arena...),
  old UI helpers, 19 old tests, data/v114-content.json, reports/, old tools and docs, and the
  unreferenced asset folders art/dice/portraits/premium (assets 53 MB -> 19 MB).
  Kept: assets/branding (app + adaptive icons), visual_theme/brass/tactile (used by the HUD).
- The repo-root web game and servers (fatebound.html, arena, save host) are untouched: they
  still serve existing web players on the VM.
- tools/verify_play_bundle.py: adopted the Play branch version; its dice-era checks now require
  the Siege app scripts and fail if dice-era scripts ship. The Play workflow on this branch is
  still the older vc22 one (the Play branch owns release builds) — merge carefully.
- godot-visual-review.yml runs run_siege_tests.sh --quick. New tests/parse_all.gd.
- Verified from a deleted .godot cache (fresh import): all 11 suites pass.

## E5 notes
- In-match panels (forge, workshop, pause, results) now use the app's card and tactile button
  styles (UI.style_button / UI.card_style), so battle and menus look like one game.
- UI.tighten(): narrow padding + clipping for tight rows. Fixed the 4-die forge overflowing its
  panel (style reset the dice font to 16 px; 16 px side padding x4); TAKE gets 1.3x of the row so
  "TAKE BERSERKER" (longest label) fits (193 px available, 149 needed). Verified on Vulkan.

# Round 6 (Kevin, 2026-09-28): "make the home screen menus look better; use headless Blender if you have to"
- Baseline problems found from screenshots at 420x933: boxed hero viewport with a flat grey
  castle and a washed-out tint; every shop item the same tiny glyph (a skin and a weapon showed
  the identical wand); one coin icon for 600 and 4,500 gold; flat PLAY button.
- Done: Blender backdrop + 19 gear icons + coin/gem art; 18 skin busts from Godot; full-bleed
  animated hero; icon chips; PLAY button animation; tab pill; fade transitions; real art in
  Shop/Locker/Pass. See SIEGE_HANDOFF section 12. All 11 test suites pass.
- Bugs met on the way: material cache dying across Blender scene resets; a background Blender
  run that hung (foreground works, 3 s/icon); Nishita sky too pale for a sunset (painted dome);
  sky gradient stops placed outside the ~-12..+30 deg the camera sees; home camera framed for a
  shorter box (character filled the screen).
- Not done: per-challenge icons, animated number count-ups, a rendered logo.

## 0.13.1 fix
- Found while packaging 0.13.0: the home hero layer (a sibling of chrome) stayed visible and
  processing during matches. Proved with two failing asserts in app_flow_test first, then fixed by
  `_set_menu_active`. All 11 suites pass. (Not measured on a device; the GPU cost is inferred from
  the viewport settings, not profiled.)

# Round 7 (Kevin, 2026-09-28): Fat Princess-style land, slopes, bigger map, capturable outposts, bridges ("use Blender")
| Step | Scope | Status |
|---|---|---|
| T1 | Blender art: seamless grass (voronoi patches), herringbone brick path, rock ledge texture, wooden bridge model | done |
| T2 | Sim: bigger field, river with 3 bridges (walls + nav), raised ledges with ramps, rolling slopes (height_at), outposts (capture, respawn, trickle), protocol sync | done |
| T3 | View: single terrain mesh (heights from sim) with grass/path/rock shader + path mask, water, bridges, ledge faces, outpost towers | done |
| T4 | Bots (outposts), HUD markers, tests, screenshots, APK | done (0.14.0, code 24) |

## T1 notes
- tools/blender/terrain_art.py -> assets/terrain/{grass,path,rock}.png (1024, seamless) + bridge.glb.
- Seamless by construction: 4D noise sampled on a torus (grass, rock); the herringbone rendered
  over exactly one period. The 2x1 herringbone lattice (H bricks on (1,1)/(2,-2), V bricks at
  offset (-1,0), period 4x4) was verified by rasterising before modelling.
- Bugs found and fixed: brick colours overexposed (Blender colours are linear); per-brick random
  colour/tilt broke tiling (halves of a wrapped brick differed) -> variation keyed to the brick's
  position within the period (wrap diff 7.9 -> 1.6, flat control 0.3).

## T2 notes
- scripts/siege/siege_land.gd: field 64x128 (was 52x104); river c(x)=1.5 sin(0.16x) (odd, so it
  is its own point mirror), 6 m wide, bridges at x=-20/0/20 (rails, deck arch); 4 raised ledges
  (1.5 m) with ramps; rolling slopes (sin*sin + cos*cos, even under the mirror); 4 outposts on
  the ledges; brick path routes gate -> ramps -> bridges.
- Sim: walls from the land ("river" and "rail" don't block arrows), outposts (lone team captures,
  ~9.5 s alone / 4.8 s with 4; contested freezes; crossing 0 neutralises; +1 wood +1 stone per
  15 s; raiders/escorts respawn at the forward outpost), escorts capture. Old plateau + ruin gone.
- tests/siege_land_check.gd (placement clear of walls/paths/rings, flat rings, point symmetry,
  nav reaches bridges/outposts, river only crossed on bridges) caught 6 bad hand placements.
- 2 matches: both ended 3-2 on rescues (~7 min; before, most went to time); outposts captured 35 /
  lost 27; 0 clips. Red won both: watch side balance.
- Protocol v2 (snapshot "op" = owner, prog per outpost). Old clients get "update the game".
  **The server must be redeployed with this branch before online play works again.**
- The view still draws the old hex terrain/plateau until T3.

## T3 notes
- Terrain = baked height map (tools/bake_land.gd -> assets/terrain/height.res, 157x285 @ 0.5 m)
  meshed in 32 m bands (cached per session) + scripts/siege/terrain.gdshader: grass, herringbone
  bricks via the baked mask (R), rock on steep faces, rock rim from above (G) and cliff-foot
  shadow (B). Baking because computing 43k heights at match start took 387 ms on the dev box.
  tests/siege_land_check.gd fails if the bake is stale: **re-run bake_land.gd after editing
  siege_land.gd**.
- Found by screenshots: the bridge deck was hidden because the terrain was baked at deck height
  (terrain now excludes decks; units still walk on them); ledges were invisible from the game
  camera (faces point away) -> 1.2 m rock band + rim/shadow in the mask; the Vulkan exposure
  washed the textures out (shader tint 0.74).
- Water: animated shader on a strip following the river (TIME only; no per-frame buffers).
- Outposts: bare stone tower when neutral, team tower + flag when owned, capture ring + an inner
  ring that grows with progress in the capturing team's colour.

## T4 notes
- HUD: POSTS pips (owner colour, arc = capture in progress in the capturing team's colour),
  toasts on capture/loss, "enemies are taking one of our outposts" alert (throttled 10 s).
  Verified by a staged screenshot (owned / enemy / capturing / neutral).
- Preview 0.14.0-siege-land, version code 24. Protocol v2: the online server must be
  redeployed from this branch (install_siege_server.sh) before this build can play online.

# Round 7b (Kevin): "more colourful like the sample pics, the grass needs to look more like grass"
- Measured (HSV, green pixels, in-match camera vs Kevin's references): before hue 79 deg /
  sat 131 / val 209 (yellow, washed); refs 110-112 deg / 138 / ~190; after 103 deg / 135-138 /
  192-195.
- Grass texture rebuilt in Blender: true green, soft lighter/darker patches, faint wavy lines
  (the polygon rim network read as tiles), blade grain; seamless.
- Terrain shader: large-scale sunlit/shaded variation (noise), grass-only saturation control,
  cooler tint (was yellowish). Scene: saturation x1.08, contrast x1.04.
- Foliage (view, MultiMesh per 32 m band, planned once per session): ~1,480 KayKit grass tufts
  lining path edges and ledge tops + field clumps; ~400 Blender flowers (red/blue/yellow/white,
  172 tris each) in clusters. Kept off paths, bridges, water, castle grounds, cliff bands and
  obstacles.
- Preview 0.14.1-siege-land, version code 25 (same protocol v2 as 0.14.0).

# 0.14.2 (Kevin): "optimize it, the fps are dropping now"
Measured with tests/perf_bench.gd (3D SubViewport render time, software Vulkan at 540x960,
same busy midfield spot; CPU rasterisation is fill-rate bound like a phone GPU, so the ratios
are what count, not the milliseconds). Each config measured twice; the first pass of a run
includes shader compile and is ignored.
| Build / config | 3D ms |
|---|---|
| 0.13.1 (smooth on Kevin's phone) | ~119 |
| 0.14.1 full | ~190 |
| 0.14.1, terrain shader swapped for a plain texture | 108 |
| 0.14.1, foliage hidden | 173 |
| 0.14.1, water hidden / colour adjust off | 186 / 191 (no measurable cost) |
| **0.14.2** | **~88** (-54% vs 0.14.1, -26% vs 0.13.1) |
- Terrain shader (was ~43% of the frame): a plain grass pixel reads 2 textures (was 7); brick
  and rock textures only where the mask/slope needs them (branches); macro variation is
  arithmetic in the vertex shader; no anisotropic filtering; no second rotated grass sample;
  specular off. Per-vertex lighting would save only ~3.5% more: not taken (look).
- Foliage (~9%): 44-tri tufts only (dropped the 132-tri variant), per-vertex lighting, flowers
  back-face culled (exported double-sided), visibility range 70 m, "Reduce effects" halves it.
- Look unchanged: grass hue 105 / sat 136 / val 189 vs 103 / 135 / 192 in 0.14.1.
- Not measured on the phone. Kevin: COPY DIAGNOSTICS after a match gives real fps.

# 0.14.3 (Kevin): "a bit more optimization to get that 60 fps lock" -- no automatic resolution
- Kevin explicitly does NOT want automatic/dynamic resolution (it was built and removed
  unshipped). Don't add it.
- Measured (tests/perf_bench.gd, frozen scene, software Vulkan 540x960, interleaved runs; the
  single-core sandbox is noisy, so only repeated A/B pairs were trusted):
  flowers ~1 % of the frame, tufts <1 %, characters ~24 % (~95 of ~125 draw calls), glow ~7 %.
  Game CPU per frame ~2 ms on the dev box (sim 0.6, view 1.1; the rest of a headless frame is
  the engine's idle wait), so the phone is GPU-bound.
- Changes: glow off in battle; terrain baked at 1 m (was 0.5 m: -45k triangles, no visible
  difference at the game camera); off-screen characters' AnimationPlayers paused (no skeleton
  update / skinning upload; resume on screen, 1.8 m margin); fewer flowers (150 clusters, was
  230) and tufts (sparser path edges, 340 field clumps, was 520), as Kevin suggested.
- End to end, 0.14.2 vs 0.14.3 alternated 3x: 90-93 ms -> 70-73 ms (-21 %), 145k -> 90k tris.
  Look unchanged (grass hue/sat/val 105/136/189 both).

# 0.14.4 (Kevin): "make the grass painted instead and have patterns like in the Fat Princess pics"
- Zoomed the references: two layers, both flat/painted: (1) polygon cells ~1.5-2 m, each one flat
  green a little lighter/darker than its neighbours, thin darker lines; (2) broad sweeping arcs of
  lighter/darker green several metres wide. No noise grain.
- Grass texture (Blender): flat Voronoi cells, 4-tone constant palette, thin dark line + faint light
  lip. Bugs met: Voronoi Scale left at Blender's default 5 (tiny shards); small torus radius curved
  cell edges into arcs (radius 1.7 + grass_scale 16 m).
- Colour from data: sampled the references' grass (mean sRGB 94,197,90, hue 117); first palette
  measured 121,207,69 in game -> each linear channel rescaled by the ratio -> 89-91,197-199,86-88.
  (Done in the grass palette, not the shared tint, so paths/rock keep their colour.)
- Sweeping bands: Land.grass_band baked into the terrain mask's alpha (RGBA8; no extra texture
  read). Concentric 5 m rings from 4 centres (mirrored) at/beyond the field edges so the play area
  sees arcs, not bullseyes (the first 16-centre layout read as targets). Shader band_strength 1.6
  (1x was faint, 3x bold). Vertex macro sine removed.
- perf_bench vs 0.14.3, alternated 2x: 58.8/60.3 ms -> 54.6/53.5 ms (no regression).

# Round 8 (Kevin): "not feeling the dice class system" -> Fat Princess hats (Kevin chose)
- Removed: the dice forge (roll/keep/pair/triple/FATE), its building, panel, the Fourth Die
  upgrade, the per-unit forge state, net actions forge_roll/take/leave.
- Hats (siege_sim.gd): 5 stands per courtyard (west corner, where the forge was): Villagers
  walking in take the hat (stock 3, +1 per 6 s); classed units swap with ACTION ("NEW HAT"; the
  old hat drops). Dying drops your hat where you fall and you respawn as a Villager; anyone
  (ally or enemy) walking over it as a Villager takes it; it vanishes after 30 s. One workshop
  upgrade per class makes that stand's hats the upgraded form (Paladin, Berserker, ...).
  Workers' tools are a hat too (they drop on death).
- Found by the match smoke: with hats only at the castle, attackers respawning at forward
  outposts as Villagers walked all the way back: 0 rescues in 2 matches (was 10). Fix: owned
  outposts carry a small rack (west = Knight, east = Rogue; 3 hats, +1 per 6 s); stand refill
  10 s -> 6 s. Now 6 rescues / 7 gates in 2 matches, 1,126 hats dropped and 440 picked back up.
- Bots: villager bots go for a dropped hat within 14 m, else an owned outpost rack if much nearer
  than the castle, else a stand of their role's classes; they fight as villagers if all are empty.
- Protocol v3 (stand stock "hs", dropped hats "hd", outpost rack stock). **Redeploy the server.**
- Tests: sim smoke checks the hat rules (take, drop on death, enemy pickup, swap, upgrade,
  refill, expiry) and counts hat events; net smoke takes a hat through the real server.
- Not verified: how a dropped hat looks in play (rendered, but not seen in a screenshot).

# 0.15.1 (Kevin, with a Fat Princess wiki screenshot): "make like this"
Rules from the screenshot: hat machines only inside each castle; dropped hats (friend or foe) can
be picked up anywhere; you can use the ENEMY's hat machines if you get inside their castle;
outposts have NO hat dispensers (respawn point + a closer drop-off for Workers).
- Removed the 0.15.0 outpost hat racks. Stands work for any team (tier = the stand owner's
  upgrade). Workers deliver at outposts their team holds (`drop_point`, `OUTPOST_DROP_R`).
- Respawn: humans respawn at the forward outpost only if a dropped hat is within 28 m of it (else
  the castle); bot attackers always respawn forward and scavenge dropped hats within 32 m, and use
  enemy stands once inside the enemy castle.
- Balance trail (2 matches each): racks removed, 14 m scavenging -> 0 rescues, 0 pickups (most
  hats expired unused); 32 m scavenging -> 1 rescue, 0 gates broken (repairs 60 HP/s per worker
  beat smaller waves); gate HP 1500 -> 1100 and repair 30 -> 20 per tick -> 3 gates, 0 rescues;
  bots always respawn forward -> 5 rescues, 12 Oracle pickups, 4 gates, 522/681 hats recycled.
  One of the two seeds still ends 0-0 on time.
- Class roster unchanged (Knight, Barbarian, Rogue, Ranger, Mage, Worker); Fat Princess's is
  Worker, Warrior, Mage, Ranger, Priest -- not changed without Kevin asking.
- Protocol still v3 (outpost stock is simply 0). The server must run this build's sim.

# Round 9 (Kevin): "there needs to be a healer class; hold the heal -> magic beam to the nearest ally"
- Priest (siege_sim.gd CLASSES "priest"): holding ATTACK channels a beam to the nearest injured ally
  within 9 m (else the nearest ally), 18 HP/s (High Priest x1.4), 70 % walk speed while channelling,
  no damage. Ability Sanctuary: +35 HP to allies within 4.5 m, 9 s cooldown. 6th hat stand +
  "High Priest Hats" workshop upgrade. Bots: escorts/defenders may pick Priest; priest bots beam
  the most hurt ally within 16 m and cast Sanctuary when 2+ are hurt nearby.
- View: Mage model tinted white-gold (LOOKS "tint", cached static material), wand, casting loop
  while beaming, beam = unit cylinder moved per frame (transform only), Sanctuary ring.
- Protocol v4: beam target in unit slot 26; "priest" added to the protocol class list (without it
  a Priest would have shown as the wrong class online).
- Balance: at 24 HP/s kills fell ~735 -> ~300 per 2 matches (healers undo fights) -> 18 HP/s.
  Gates break less (priests keep defenders/repairing workers alive); attackers use ladders. The
  smoke test now requires a breach (gate or ladder) + rescues, and exits on failure (a failed
  assert() in _init kept Godot running until the runner's 10-minute timeout).
- 6th stand placement: next to the others it sealed the corner / the west stairs (reach test);
  placed at (2.6, 17.0) in the east courtyard until the castle rebuild.
- Sim cost measured (tests/siege_profile.gd): 2.27 ms/tick (projectiles 1.20) since Round 7 +
  longer fights -> 1.93 (projectiles 0.89): projectile-only wall buckets, packed enemy positions,
  gate check only near castle fronts.

# Round 10 (Kevin): "castles much larger and more 3D like the pictures" -- step K1: geometry
| Step | Scope | Status |
|---|---|---|
| K1 | scripts/siege/siege_castle.gd layout; sim walls/ledges/stairs/heights/positions; basic view; land paths; tests | done |
| K2 | Blender castle textures (sandstone bricks, paving) | done |
| K3 | Generated castle geometry (castle_mesh.gd): 5.5 m crenellated walls, round towers, gatehouse lintels, terrace faces + parapets, walled stairs, paved floors | first pass done |
| K4 | Tuning (match pace), screenshots, perf, APK | todo |

K1 notes
- Castle 40 x 26 m (was 26 x 14): front wall z=3 local (world 38, was 50), gates x=+-7; L0 courtyard
  (spawn, 6 hat stands in 2 rows 3 m apart, workshop east); L1 terrace 1.8 m (dungeon west wing,
  grand stairs 8 m + two side stairs); L2 terrace 3.6 m (throne, 6 m grand stairs). Stair sides
  are ledges. Castle-to-castle gap 76 m (was 100).
- Land: path starts moved to the new gates, flat castle zone 44 -> 36, rebaked; 7 placements moved
  (land check).
- Bug found by a per-team stuck/death trace (blue won 4/4 seeds, kills 3-5x): each team's own gates
  cleared nav cells with a CAPSULE around the doorway whose rounded ends reached 1.35 m into the
  wall's end cap, so paths led units into solid wall (red workers/priests stuck ~865 ticks at their
  east gate). Doorways now clear a rectangle (_cells_across_segment). Afterwards: red 3 / blue 1 of
  4 seeds -- no longer one-sided (small sample). The old castle had the same flaw (smaller effect).
- Pace: matches now end ~260 s on 3 rescues, first rescue ~100 s (was mostly 7-12 min). Tune in K4.
- Protocol v5 (map geometry changed).

K2/K3 notes (0.17.0)
- tools/blender/castle_art.py -> assets/castle/{bricks,paving}.png (1024, one 2 m period, seamless
  by construction like the herringbone path).
- scripts/siege/castle_mesh.gd builds each team's castle from sim.walls + siege_castle.gd into two
  meshes (bricks, paving) with world-scaled UVs; cached per session. ~2k triangles, 4 draw calls.
  Replaces the KayKit wall runs, parapets, gate-flank and back towers (catapults now sit on the
  5.5 m wall; gate doors, bars, flags, props kept).
- Found in screenshots: every face was inside-out (Godot front faces are CLOCKWISE; floors
  vanished from above) -> triangles emitted reversed; walls and floors the same tan -> warmer
  brick, paler paving. Gate towers slimmer (1.35 m) so they never overhang the 2.3 m doorway.
- perf_bench vs 0.16.0 at (4,30) (now in front of the castle): ~70 -> ~84 ms, but mostly units and
  props now in view; hiding the castle meshes saves ~9 % (noisy). Hat stands are ~60 draw calls
  (pedestal + weapon + 3 hats each): merge them if the phone needs it.
- Next polish: darker stair risers, thicker parapets, throne dais/balustrades, maybe Blender towers.

# 0.17.1 (Kevin): "that castle looks horrible; utilize the KayKit assets for the walls, give the
# castles some character, not just basic"
- Dropped the generated sandstone walls/towers/parapets (castle_mesh.gd now only makes the
  herringbone floors and grey stone steps). Castle = KayKit: wall_straight runs (outer walls and,
  re-scaled so the walkway sits at the terrace height, every terrace edge and stair side), stone
  tower_base on the 4 corners, tower_A beside each gate, catapult towers, keep behind the throne.
- Character: blacksmith (the workshop), archery range (L1 east), church + tavern + two tower_B
  around the throne (L2), barrels/crates/sacks/targets/weapon rack/wheelbarrow, banners on the
  corner towers, trees in the courtyard corners. Buildings are solid in the sim
  (Castle.BUILDINGS -> obstacles "castle_building"); props are visual only (Castle.PROPS).
- Side stairs 2.5 -> 3.5 m and castle ledge radius 0.35 -> 0.55 (the KayKit edge walls are ~1.1 m
  thick); reach + land checks pass.
- Perf: all static KayKit pieces share one atlas material -> merged into one mesh per castle
  (_merge_kit; per castle so the far one is culled). perf_bench at (4,30): ~141-150k tris,
  179 draws (0.17.0: ~102-118k, ~165): the detailed buildings cost ~35-40k tris in view.
- Watch: seed 11 lopsided (red 3-0, kills 18-148); seed 22 even. Check for a side bias.

# Round 11 (Kevin): stairs, hat machines, Weapons Bits cosmetics, knight block, berserker whirlwind
- Stairs: terrace floors had no openings (covered the steps, climbers under the floor); box lids
  faced down after the winding fix; height = ramp + one riser. Treads pale, risers dark.
- Knight BLOCK / Berserker WHIRLWIND (see handoff 17). Protocol v6.
- Squeeze traps: a blocking knight got wedged into a 0.55 m slot (cell bars vs L2 face); the
  push-out resolves walls one at a time. siege_land_check now finds any castle slot narrower than
  a unit: 7 per castle, all fixed (cell on the L2 face, buildings touching walls, stands 1 m off).
- Hat machines spread (knight/rogue/barbarian courtyard, ranger L1, mage/priest L2), each a themed
  KayKit structure with an upgraded look. An UNSHADED orb + the mage/priest pieces hung the
  software-Vulkan renderer before the first frame (bisected per class, per piece; each alone
  fine) -> lit emissive orbs.
- Cosmetics: KayKit Fantasy Weapons Bits (assets/kaykit/bits): 18 weapon cosmetics + 2 priest
  skins + 3 titles; Priest in the Locker; 6 class packs (gems, pay only for what you don't own);
  pass 6 free + 10 premium cosmetics per season (was 3 + 5; the pool was exactly 8 before, so
  every season was the same). Icons: tools/blender/icons.py (bits/ models), priest busts.
- Open: the Priest is the Mage model tinted white-gold and reads almost like a Mage (a tint can
  only darken the purple robes); needs its own model or re-texture.

# 0.18.1 (Kevin): faster whirlwind with WoW-style spin FX, station titles, hat upgrades at the
# hat shops (not the workshop), bigger knight shield
- Whirlwind: sim spin 14 -> 26 rad/s (~4 turns/s), spinning anim x1.8, two translucent blade-trail
  ribbons (partial rings fading along the arc, additive) circling at 7 and 5.5 turns/s, tilted
  opposite ways; built once per unit, transform-only per frame.
- Titles: HUD-projected plates over every hat shop (class name, ★ + upgraded name when upgraded,
  stock) and workshop in view within 24 m. No 3D text nodes.
- Hat upgrades: ACTION at your own team's shop for your current class = UPGRADE (gold button, cost
  under it, dim when unaffordable); the workshop's hat grid is gone and "buy hat_*" through the
  workshop is refused. Bots still buy hat upgrades through the team planner.
- Knight shield: Weapons Bits shields attach at 0.9 (was 0.55).
- Protocol unchanged (v6): the server runs this build's sim, so still redeploy with it.

# 0.18.2 (Kevin): "stairs still don't look like stairs; arrows/bolts sometimes fly through enemies"
- PROJECTILES HIT NO UNITS from 0.16.0 to 0.18.1: the per-team position arrays (my 0.16.0
  optimisation) were appended through `tpos[t] as PackedVector2Array` -- packed arrays are VALUES in
  Godot 4, so the appends went to a copy and the arrays stayed empty. Arrows/bolts still hit walls
  and gates, and melee/catapults kept kills going, so no test noticed. Now: local arrays, a swept
  path-vs-circle test (the whole move since last tick, from the shooter on the first tick), the
  nearest hit wins, the projectile explodes at the impact point and the struck unit always takes
  the full hit. Measured: 0/300 -> 300/300 arrows and bolts on paths through a target. The sim
  smoke now fires 60 of each and requires every one to hit.
- With ranged damage back, two collision cases surfaced in bot matches:
  * a unit squeezed between a terrace wall end and the field edge (1,057 violation ticks): landscape
    walls ending within 1.5 m of an edge now run 1 m past it; siege_land_check checks wall ends vs
    the field edge; generic _fill_squeeze_slots() bridges any wall pair closer than a unit
    (2 fillers on the current map); the land check ignores gaps already covered by a third wall.
  * a dodging knight stayed inside a concave river-bank corner for 8 ticks: _push_out repeats its
    wall pass (max 3) while a pass still moves the unit.
- Stairs from the overhead camera: 6 steps per flight (0.5 m deep, was 9 x 0.33 m), each tread a
  bright nosing + mid stone + dark shadow band (vertex colours read as sRGB: as linear the dark
  bands came out pale grey).
- Bot match results shifted with ranged damage working (seed 11: red 3-0, kills 46-150).

# 0.18.3 (Kevin): "fix the main menu not being able to scroll up and down"
- Reproduced: the home content was 1377 px on a 648 px page, but touch drags never scrolled. Every
  screen is cards/buttons (and the hero spacer), which STOP input, so Godot's ScrollContainer
  touch-drag (mouse events emulated from touch) never received the drag. Switching controls to
  PASS isn't enough on a phone: buttons still claim the press.
- Fix (siege_app.gd `_input`): the app scrolls the menu itself. A press inside the menu that moves
  > 14 px vertically becomes a scroll (content follows the finger, flick glides and eases out); the
  pressed control gets a cancelled press (pointer moved off-screen, then released there -- buttons
  only update "pressing inside" on motion, so without the move PLAY still fired after a scroll);
  the emulated finger-lift release after a scroll is swallowed; short taps pass through. The
  built-in drag is off (scroll_deadzone 1e6). Skipped during a match and while a dialog is open.
- tests/app_scroll_test.gd (in the runner): drag from PLAY scrolls and doesn't press PLAY, a tap
  still presses it, a drag from the hero area scrolls, a flick glides. Harness note: push events
  with root.push_input(e, true) (viewport coords) and pair each touch with its emulated mouse
  event (device -1) the way a phone delivers them.

# 0.18.4 (Kevin): "optimize the network play; on the server the controls lag a bit"
- Cause (read in the code): no client-side prediction. The local unit was drawn from 10 Hz
  snapshots and interpolated like everyone else (+100 ms), so input -> screen was RTT + server
  tick + snapshot wait + 100 ms (~200-260 ms at a 60 ms RTT).
- Client-side prediction: the phone moves its own unit every frame with the sim's movement code
  (Sim.predict_step / move_mult; dodges and swings too, animation only) and sends position + facing
  with its inputs. Server (siege_server.gd): units of predicting clients are `net_driven` -- the
  sim doesn't move them; Sim.accept_client_pos takes the reported position if it's within speed x
  time x 1.35 + 0.6 m and pushes it out of walls, else keeps its own (the phone snaps back). Falls
  back to server movement if positions stop arriving for 0.3 s. Server-driven states (dead,
  stunned, carrying, lunge, tasks) and > 2.5 m disagreements follow the server (Net.PREDICT_SNAP).
- Snapshots 10 -> 15 Hz (measured ~1.3 KB compressed, p95 1.7 KB: ~19 KB/s per player).
- Protocol v7 (hello "pred", input "p"/"f").
- siege_net_smoke, against the real server: local move within 3 frames (0.41 m), server 0.21 m
  behind after 7.2 m, a forged position 20 m away rejected, a swing starts on the press.

# 0.19.0 (Kevin): "a tutorial walkthrough; a narrator talking to the player with humor; I'll add the
# voiceover later"
- scripts/siege/tutorial.gd: the Royal Herald. 13 steps, 30 lines (each [voice id, text]); 9 tasks
  the player must DO, checked from the sim each frame: walk, take the Knight hat at its shop, hit a
  training dummy 3x (an enemy posted in the courtyard with 9999 HP, sent home afterwards), dodge,
  hold ABILITY to block 1 s, reach the workshop, upgrade Knight hats at the hat shop (materials
  topped up), capture the home outpost, head for the river. Talk-only steps: dropped hats, the goal
  (gates, ladders, carrying the Oracle, 3 rescues), cake. Typewriter panel under the HUD status
  lines with NEXT on the right (the joystick owns the left side), crown badge, bouncing arrow over
  the target or an edge arrow when it's off-screen, pulsing ring on the button to press.
- Match: SiegeMode.tutorial -> 2 v 2, everyone else frozen; no match rewards/challenges; finish sets
  profile tutorial_done and pays 250 gold once, then returns to the menu.
- Home: "New here?" card with PLAY TUTORIAL until done; HOW TO PLAY under PLAY always.
- Voiceover: res://assets/vo/tutorial/<id>.ogg|wav|mp3 plays with its line if present (verified
  with a temporary tone, then removed); assets/vo/tutorial/SCRIPT.md is generated from STEPS.
- tests/tutorial_test.gd (runner): plays it end to end (16 s) and checks the script (unique ids).
- siege_net_smoke: the prediction check now compares the local move with speed x elapsed time (a
  fixed 0.1 m in 3 frames failed when uncapped frames were ~5 ms).

# 0.19.1 (Kevin): tutorial says "Fatebound"; clearer arrows; dummy somewhere better; end with carrying
# the Oracle home; walk through feeding her
- Script: "Fatebound" in the intro, goal, feed and end lines; 36 lines now (VO script regenerated).
- New ending: cake (take a slice, ACTION) -> feed their Oracle in OUR dungeon (ACTION) -> the Herald's
  "shortcut" (recruit placed outside the enemy gate on their dungeon's side, that gate broken;
  camera snaps) -> lift our Oracle (ACTION) -> carry her home to our throne (scores a rescue) -> end.
  The old "walk to the river" task is gone (the goal step is talk-only).
- Dummy: open courtyard floor (castle-local (4, 6.6)), with its own TRAINING DUMMY marker (next to
  the knight armory it blended in).
- Guidance: marching dotted line along the nav route (through gates, up stairs), pulsing ground
  ring + big outlined arrow over the target with a "NAME · N m" plate (walking distance), flipped
  below the target when it would sit under the Herald's panel; off-screen: big labelled edge arrow
  pointing along the route (projecting the far target flipped it when it was behind the camera);
  TAP / HOLD plates on button rings.
- tutorial_test: 12 tasks incl. cake, feed, grab, carry; the rescue must score.
- net smoke: the stick points toward the open courtyard (pushing "right" sometimes walked into a
  stand -> the prediction check failed on collision, not prediction).

# 0.19.2 (Kevin): "the projectiles skip across the screen in online mode"
- Cause (siege_net.gd apply): every snapshot replaced the mirror's projectile list and the view drew
  each at its snapshot position, so at 15 Hz an arrow (22 m/s) sat still 66 ms then jumped 1.47 m.
  Units were interpolated (net_from -> net_to); projectiles never were.
- Fix: projectiles persist across snapshots with net_from/net_to and Net.interpolate slides them on
  the same one-interval-behind timeline as the units; a new one starts at its spawn point; one that
  ended gets one last slide to the impact point (proj_end events now carry "pos") before vanishing.
  Offline, the view draws projectiles ahead by vel x the time since the last 30 Hz tick
  (view.proj_lead = mode._accum).
- tests/net_interp_test.gd (runner): real snapshot/encode/decode/apply, 5 samples per interval:
  largest step 0.29 m (old drawing 1.47 m), no stalls, ends 0.40 m from the target it hit.
- Protocol unchanged (v7; the extra event field is ignored by older builds). Redeploy the server
  so it sends impact points.

# Trailer (Kevin: "make a cinematic trailer")
- Fatebound-Siege-Trailer.mp4: 34.4 s, 1920x1080 @ 30, H.264 + AAC. Cut: aerial -> captive ("THEY TOOK OUR
  ORACLE.") -> hats ("GRAB A HAT.") -> gate assault ("STORM THE CASTLE.") -> whirlwind ("SPIN. SHIELD.
  SMASH.") -> cake ("FIGHT DIRTY.") -> carry ("BRING HER HOME.") -> title card on the score's hit.
- tools/trailer_shots.gd: staged shots + eased cinematic cameras, recorded by Godot's Movie Maker
  (game SFX included). 1080p needs a TEMPORARY godot/override.cfg with window size 1920x1080 (the
  project's 420x780 window override beats --resolution in Movie Maker) -- delete it afterwards, never
  commit it. Render in the foreground (a backgrounded Xvfb gets reaped when the command returns).
- tools/trailer_music.py: procedural placeholder score (90 BPM D minor; drums, pad, ostinato, riser,
  title hit). tools/trailer_edit.py: crossfades, captions (Cinzel), title card, score + SFX mix; it
  places the hit on the title (29.7 s; verified: the loudest 0.1 s of the mix is at 29.7 s).

# 0.19.3 (Kevin): the Herald's voiceover
- Kevin's ElevenLabs read ("Edward - British, Dark, Low"): all 36 lines in one 319 s file. The break
  tags weren't rendered as pauses (longest pause 0.93 s; ~a dozen >= 0.8 s), so silence alone couldn't
  separate lines from the Herald's dramatic pauses. tools/vo_split.py: cuts chosen among all 144
  pauses so each piece's length fits its line's text length (DP, prefers longer pauses; pieces 0.87-1.20
  of expected), then blind PocketSphinx recognition per piece: own-line word recall 0.36-1.00,
  neighbour leak <= 0.14, starts/ends match (e.g. #13 "oh cool with legs" = "A wall with legs!").
  Whole-file forced alignment returned nothing (too long for PocketSphinx), hence this two-step way.
- Export: one gain for the whole read (+1.62 dB to -16 LUFS), limiter -1.5 dB, fades, mono OGG
  Vorbis q5; 36 files, 3.3 MB, in assets/vo/tutorial/<id>.ogg.
- tutorial.gd: the voice follows the Settings master volume and the mute switch (native_audio.gd
  levels); it sits above the effects (those play at 0.12 x master x effects).
- tutorial_test: every line has a loadable recording >= 1.5 s; the first line plays.

# 0.19.4 (Kevin): "land on the edges of the map instead of nothing; a sky (mainly for the trailer)"
- Outer land (view only, no sim change): Land.outer_height starts at the terrain's own edge height
  (blends over 20 m), rolls into meadows and hills, rises to snow-capped mountains beyond ~110 m, and
  carves the river's valley on out of the map (river_c holds for any x). Four ring meshes (one per
  side, 15 rings to 260 m; the first tucked 1 m under the terrain edge so no crack shows), shader
  scripts/siege/outer_land.gdshader = the terrain's grass/tint/saturation + its sweeping bands faded
  out over 12 m, rock on steep/high ground, snow on peaks. ~260 kit trees in groves (MultiMesh per
  side x type, off-screen sides culled). The water now spans the outer land too (ripple density kept).
- Sky: ProceduralSkyMaterial as background only (ambient stays a colour, reflections off: the field's
  lighting is unchanged, no radiance map). Fog = the sky's horizon colour, 70 -> 285 m (the land ends
  ~300 m out: fully fogged there, so its rim never shows), fog_sky_affect 0.
- perf_bench (mid-field): 146-154k tris / 186 draws (was ~141-150k / 179); timings within noise.
- Trailer re-rendered: the opening starts on the sky and tilts down onto our castle; the finale pulls
  back and tilts up so the title sits over castle, mountains and sky; title dim 0.45 -> 0.25.

# Trailer with Kevin's music (his Suno track, Spooky_3.wav, 103 s)
- Scored with the song: its drop at 42.5 s (loudness x1.46 after a quieter stretch) lands on the title
  card (29.7 s): python3 tools/trailer_edit.py --song Spooky_3.wav --song-hit 42.5 (the song plays from
  12.8 s, 0.6 s fade in, 1.4 s fade out). The WAV came in quiet (-23.8 LUFS, peaks -9.9 dB): one steady
  gain to -15 LUFS (+9.5 dB); final mix -15.6 LUFS, true peak -1.5 dB. Measured: x1.37 louder in the
  second after the title than before it.
- "BRING HER HOME.": an ally carries her (the match writes the joystick into the player's move every
  frame, so "you" stood still) across the centre bridge toward our castle, escorts beside, enemies
  closing in behind.
- "FIGHT DIRTY.": a rogue creeps up behind a guard looking away and strikes three times (replaces the
  cake shot).
- The song isn't in the repo (Kevin's track, large); keep it with the trailer sources.

# 0.19.5 (Kevin): "the edge of the map still has grey spots -- mountains or something"; "better text above the buildings"
- The grey was the sky's ground colour showing through: 0.19.4 special-cased the triangle winding per
  side and got sides 1 (east) and 2 (behind the blue castle) backwards, so they were culled. All four
  sides run the same way round the rect with rings going outward, so one winding ([a, b, a+1, a+1, b,
  b+1]) is right for every side. My 0.19.4 test views only looked at sides 0 and 3.
- The sky's below-horizon colours = the fog colour: any gap now reads as distant haze.
- Outer land: hills close in within ~30 m, mountains from 40 m (was 110 m), blend from the field edge
  over 14 m: from the play camera the field sits in a valley between rocky slopes.
- Station plates restyled (HUD): rounded signboard (StyleBoxFlat, anti-aliased), gold rim (brighter +
  ★ when upgraded), team-coloured top stripe, soft shadow, pointer to the building; name in Cinzel
  (the logo font), subtitle in Nunito, hat stock as pips; fade in over 6 m; clamped on screen.
- Trailer re-rendered (all 8 shots) with the fixed land; same song/drop.

# 0.20.0 (Kevin): the Oracle becomes each castle's KING
- Every visible string: HUD rules/status/toasts/marker, stats screen ("King rescues"), economy (season
  "The King's Keep", challenges, reward line; the cosmetic title shows "Kingsworn" but keeps its id
  title_oracle_sworn so owned copies survive), tutorial lines/tasks/labels. Scan of every quoted string
  in scripts/: no visible "Oracle" left. Internal names (sim.oracles, oracle_nodes, protocol keys) are
  unchanged -- players never see them.
- The King: the Knight body, helmet and visor hidden, weapons stripped, team cape (royal blue / crimson),
  a gold five-point crown with a ruby on the head bone (placed at the head mesh's measured top); the halo
  and its spin are gone; the healing aura stays.
- Tutorial VO: 13 lines rewritten (him/his/King); their Oracle-era recordings pulled from the game until
  Kevin re-records (kept in staging), so the voice never contradicts the text. tutorial_test has the
  explicit pending list (13) and fails if it goes stale. Re-record sheet: Fatebound-Tutorial-VO-Rerecord.txt.
- Trailer captions/tagline and store captions/listing text now say King; the store images, the
  feature graphic and the trailer footage still show the Oracle until they're re-rendered (planned with
  the new trailer VO). The AI store package zip is stale until then.

# 0.20.1 (Kevin): Luckiest Guy for titles; the game is just "Fatebound" (no "Siege")
- Fonts added: assets/fonts/LuckiestGuy-Regular.ttf (Apache 2.0) and Fredoka-Variable.ttf (OFL), licences
  alongside. Home logo: "FATEBOUND" in Luckiest Guy (gold, dark outline, shadow), the "S I E G E" line
  removed. Pause heading "FATEBOUND", settings version "Fatebound <build>", migration toast "Welcome to
  Fatebound!". Feature names (Siege Pass, Siege server, "Frost Siege" season, "Siege Lord" title) kept.
- Trailer: text art pre-rendered as transparent PNGs (gold gradient Luckiest Guy, Fredoka tagline) and
  overlaid with fades (tools/trailer_edit.py make_overlays; ffmpeg drawtext can't do gradients); the
  title card is just FATEBOUND. Captive/carry/finale re-rendered with the King. Output renamed
  Fatebound-Trailer.mp4.
- Store: tools/store_compose.py headlines in gold Luckiest Guy, text in Fredoka, feature graphic without
  "SIEGE"; listing name "Fatebound"; all store screenshots re-rendered (King, new signs, new logo); the
  AI store package rebuilt.

# 0.20.2 (Kevin): his King models -- kingT1/kingT2 x fat/fatter/fattest
- Kevin's 6 GLBs: static meshes (no rig/animations), one "BakedMaterial" each (4K-ish baseColor, normal,
  metallicRoughness PNGs: ~21 MB per file), ~10.4k tris, 1.9 tall, origin at the centre. T1 = red robes,
  T2 = purple robes -> matched by colour: T1 leads red, T2 leads blue (Kevin numbered them team 1/2).
- Optimised in Blender (/tmp/kings/optimize.py pattern): origin at the feet, baseColor 1024 JPEG, normal
  512 -> then halved (APK: 1024/512 textures cost 17 MB for six kings): baseColor 512 JPEG, normal
  256, metallicRoughness dropped (matte 0.78), geometry untouched -> assets/kings/king_{blue,red}_{fat,
  fatter,fattest}.glb, ~1.1 MB each, 6.6 MB imported; side-by-side at gameplay/close-up size: no visible
  difference.
- View: each King root holds all three; sim weight 0-5 -> stage weight/2 (0-1 fat, 2-3 fatter, 4-5
  fattest), +5 % on odd weights, a puff when a stage goes up; breathing + sway at rest, a wobble while
  carried (the models aren't rigged). Scaled to 2.6 tall (the Knight hero is 2.54). The Knight-body
  King and the procedural crown are gone.
- Their shadows are OFF: a shadow-casting King + the full scene hung llvmpipe before the first frame
  (bisected: model alone fine, with its normal map, back-face culling, a shadow light -- all fine; full
  scene with King shadows off fine). Other characters don't cast real shadows either.
- The trailer and store screenshots still show the 0.20.0 Knight King until re-rendered.

# 0.21.0 (Kevin): the dungeon moved down into a walled wing off the west wall, with real jail bars
- Kevin circled the grass strip outside the west wall; option A: a walled, sunken wing (castle-local
  x -31..-20, z 8..24, floor -1.6 m). Doorway in the west wall off the L1 west wing (z 17..20); 11 stairs
  down along x (Castle.DSTAIR) with walls both sides; the old L1 cell is gone.
- Jail cell in the wing's front-west corner (two sides are the wing's walls): iron bars on the east side
  and a barred DOOR on the north side = a gate of kind "jail" (500 hp, r 0.35): it lifts for the castle's
  team (the existing gate "open" mechanic drives the view), blocks the enemy, has to be smashed (bots path
  through it at the enemy-gate cost and attack it), and _reset_jail() locks it again whenever the King is
  back in his cell (rescue or return). Excluded from the Reinforced Gates upgrade and the bots' "gates
  damaged" check; per-gate radius used everywhere gates collide/stamp nav/stop projectiles.
- Terrain: Land.in_dungeon_pit -> terrain dips to the dungeon floor (rebaked). Three resource nodes per
  half moved out of the wing's footprint (land check: no squeeze traps, all clear).
- View: iron-bar grilles (procedural, lit) replace the wooden-fence cell bars; the jail door slides up
  2.25 m when open; stone sides for the pit; the dungeon floor and striped stairs in castle_mesh.
- HUD: jail alerts ("THEY SMASHED OUR JAIL" / "THEIR JAIL IS OPEN"), "Our jail is locked again"; the
  jail isn't in the W/E gate bars. Tutorial shortcut also breaks the enemy jail. Protocol v8.
- sim smoke: jail rules (ally through, enemy blocked, enemy smashes it, re-locks) + matches: rescues still
  happen (first at ~100-220 s), 0 violations.

# 0.21.1 (Kevin): grass in the dungeon, keep blocking the throne, a throne, back walls, no inner towers, bigger outposts
- Grass tufts on the dungeon floor: foliage excluded only the main castle rect -> also Land.in_dungeon_pit(p, 1.5).
- The keep (building_castle, behind the throne) and the two tower_B flanking it removed.
- Back wall along the L2 back edge: kind "backwall" (ladders only use "wall"), line z=30.2 so its face (29.2)
  is just past the field edge -- 1.6 m clear of the church/tavern (29.6 made squeeze traps); drawn at L2 height,
  unclipped (clipped to the field edge it ran through the throne).
- Throne: Blender model (assets/props/throne.glb, 2.4k tris, 169 KB: stone dais, gold frame, velvet seat/back,
  crown); velvet recoloured per castle; at THRONE_SEAT (0, 28.3) flush with the wall, obstacle r 0.9; the
  rescue point THRONE (26.8) stays 1.5 m in front (0.95 m at 27.6 swallowed it: reach test).
- Outpost towers 40 % bigger (base 3.6, tower 3.2), collision 1.3 -> 1.8.
- Dungeon wing's outer wall moved to x=-33 (wholly outside the field): at -31 its rounded end sat on the field
  edge and a unit walking the edge got squeezed into it (215 wall violations). Cell keeps 3.4 m (bars -28.6).
  Rebaked. Protocol v9 (map changed).

# 0.21.2 (Kevin): walls backwards, the cage clipping into the wall, the cage opening near enemies
- The kit wall's stone face is its local +Z (the other side has the walkway lip; model centred, AABB z
  -0.4..0.4). _wall_run turned pieces by the segment's direction, which put +Z on the segment's left: the
  castle interior for both castles' front walls (the red castle's walls are point-mirrored, so they run the
  other way). Now _wall_run(..., inside) turns each piece stone-side away from a point inside what the
  wall encloses (castle centre, or the dungeon wing's centre for its walls); gate pieces face + PI.
- The cage clipped into the wing's outer wall: that wall (line x=-33) was drawn clipped to the field edge,
  1 m inside its real line; the wing's walls are drawn unclipped now, the cage meets the wall face.
- The jail door stays shut while any enemy is within JAIL_SHUT_R (3.5 m), defenders or not (sim; the
  door never let enemies through anyway). sim smoke checks both.
- Note: seed 11 has had 0 rescues since the dungeon wing (seed 22: 5); rescues are harder now.

# 0.22.0 (Kevin): stairs up onto the wall so players can walk on it and shoot arrows from it
- Rampart behind the front wall's middle section (between the gatehouses, |x| <= 4.4): walkway from the
  wall's inner face to z=6 at WALK_H=1.8 (L1 height; wall top 2.86 -> waist-high parapet). Stairs down at
  its centre (x +-1.6, z 6..9, descending along +z -- Castle.STAIRS/height_local/castle_mesh now handle
  descending flights). Ledges: its inner edge (gap at the stairs) and both ends above the gate passages.
  SPAWN (0, 8.5) -> (0, 10.5): in front of the stairs instead of on them.
- Arrows/fire shot from >= 1.5 m ("high": the rampart, and the terraces) fly over castle walls ("wall",
  "backwall") and gates; from the courtyard floor the wall still stops them. sim smoke: rampart rules.
- Jail re-lock waits (g.relock -> _try_relock each tick) until no enemy is in the doorway or within 3 m of
  the cell: snapping shut on a rescuer put him inside the door (gate violation) and would have locked
  anyone in the cell in with the King. sim smoke checks the wait.
- net smoke: the moved spawn sent the player east, to the ranger stand, whose goal cell is solid; steering
  at the path's end (the unit's own cell) stalled it 1.8 m short. Now it walks straight at the stand when
  the path runs out (3/3 at 14 s).
- Protocol v10.

# 0.22.1 (Kevin): bots man the rampart; black 3D world for a few seconds at match start
- Rampart bots: enemies within RAMPART_THREAT_R (26 m) of a castle's front (refreshed each AI tick) send
  its ranged "defend" bots to Castle.RAMPART_POSTS (4, handed out first come; released RAMPART_HOLD = 8 s
  after the front clears). On a post they hold and shoot (no kiting); ranged units >= 1.5 m up skip the
  wall line-of-sight check (their shots fly over). Three bugs on the way: posts at x +-3.4 were in solid
  nav cells (partial paths: bots wandered into the dungeon) -> posts on the walkable row z 4.6, |x| <= 2.5;
  bots heading up got pulled out through the gates by enemies seen through them -> ignore foes > 3 m
  until on the post; defenders' cake runs came first -> skipped while holding a post. sim smoke: 3/3 up,
  96 high shots; matches 3-0 / 3-0, 0 violations.
- Black world at match start: not reproducible here (llvmpipe compiles pipelines synchronously); the phone
  compiles the scene's new materials in the background and draws nothing until they're ready. Warm-up
  cover in siege_mode.gd: a FATEBOUND card ("Preparing the battlefield...") while the camera visits both
  castles, dungeons, thrones, the field and the outposts (2 frames each) so their pipelines compile behind
  it; it lifts when RenderingServer's pipeline-compilation counters have been still 0.5 s (min 0.6 s,
  max 10 s), fading over 0.3 s. Offline the match clock waits (verified: sim time 0.2 s when it lifted).
  Skipped under scripted main loops (tests, render tools) unless FB_FORCE_WARMUP is set. Diag logs
  "warm-up X s, N pipeline compiles" -- check a field log for the real phone timing.

# 0.22.2 (Kevin): "the knight AI needs to be better -- all they do is hold block when enemies are near"
- Cause (_think_shields): any enemy archer/mage/priest within 12 m (or anyone within 4 m when below half hp)
  kept the shield up; blocking refuses attacks and slows to 40 %. Measured: 98 % blocking, 0 swings, 0
  damage, even standing 2 m from an archer.
- _think_knight_shield: the shield goes up only when an enemy shot will pass within 1.3 m in the next 0.7 s
  (predicted from its velocity; the shield covers allies behind too) -- not while an enemy is at arm's
  length unless below half hp -- or, below 35 % hp with an enemy at arm's length, in 1 s guard bursts at
  most every 2.6 s. Knights also hunt archers/mages within 9 m unless someone is already in their face.
- tests/knight_ai_test.gd (runner): melee 0 % blocking / 15 swings / 216 dmg; vs a lone archer 9 %
  blocking, 5 shots blocked, 10 swings. Matches: kills 126/189 and 213/245 (were 59/147 and 137/53).

# 0.22.3 (Kevin): the shop name plates are bulky and cover the ground; the barbarian shop is cramped
- Plates: one slim line -- the name (Cinzel 13, was 17) and, for hat shops, the stock as inline dots; the
  "HAT SHOP" / "UPGRADES - TOOLS" subtitle dropped; 22 px tall (was 44); thin rim, smaller pointer and
  shadow; shown within 16 m (was 24), fading over the last 4.
- Barbarian hat shop (14.5, 12) -> (-7.5, 9.5): it was 3.2 m from the workshop's ring, its machine on top
  of the workshop area; now on the west courtyard's open floor by the knight and rogue shops (3.6 m from
  the archery targets). Land check / reach pass. Protocol v11 (stand positions are map data).

# 0.23.0 (Kevin): KayKit RPG Tools Bits (CC0) for tools; fishing replaces the cake mechanic
- assets/kaykit/tools: axe, pickaxe, hammer, fishing_rod, fishing_floater, fishing_tacklebox, lantern, torch
  (+ texture, licence). assets/props/fish.glb: Blender low-poly fish (338 tris).
- Workers hold the tool for the job (view _sync_hand): pickaxe on stone, axe on trees, hammer for repairs and
  ladders, the axe otherwise (scales measured: axe 1.15, pickaxe 0.9, hammer 1.2, rod 0.6).
- Fishing (sim): cake trees gone (and their ripening, obstacles, net sync). ACTION within 0.2..2.4 m of the
  river's edge (at_river_bank) starts a "fish" task (FISH_TIME 2.5 s, facing the water); done -> u.offering (a
  fish); a hit clears the task ("fish_lost"). Feeding unchanged (oracle "cakes" count kept as the fed count).
  Bots' fish runners use a cached clear spot on their own bank (_fish_spot). View: rod in hand, float in the
  water with a line (plus the rod's own bobber), Fishing_Cast/Idle/Reeling (KayKit tools rig), splash on
  catch; the carried item is the fish overhead. HUD: FISH button, catch/lost toasts, rules text.
- Tutorial: the cake step is "fish" (guide to our bank, "RIVER"); t_cake_1 rewritten (and t_cake_took,
  t_feed_1, t_grab_done now say fish) -> 14 lines pending re-record. Economy: "Feed 3 fish", "The Fish Wars",
  "Fish Baron" (id kept), stats "Fish fed"; store caption "FEED THEIR KING FISH".
- sim smoke: fishing rules (bank only, 2.5 s, a hit loses it, it feeds their King); bots fed 4 in a match.
- Protocol v12 (state "fish", no cake trees).
- Next: hat shops as the buildings themselves (Kevin, same message).

# 0.23.1 (Kevin): "the axe is held upside down"; "the fishing pole doesn't have string attached"
- Measured the tool models: all grip at the origin, head up +Y, like the weapon axe -- the axe's blade faced
  edge-up when held forward (both old and new axes; the new one is bigger). Axe turned 180 deg about the
  handle (edge down). Pickaxe/hammer symmetric.
- fishing_rod has its own line + bobber hanging from the grip (y -2.38..2.37): that was the bobber by the hand.
  Now fishing_rod_base (bare rod, y -0.24..2.37), turned 180 deg about X (the fishing animation held it
  pointing backward), and our line runs from its real tip (ROD_TIP, highest vertex, through the rod's live
  global transform) to the float in the water.
- Fixed: a freed cached rod (body rebuilt on a class change) assigned to a typed var -> script error (mode smoke).

# 0.24.0 (Kevin): "make it so the hat shops are the buildings themselves and not some items right next to building"
- Castle.HAT_SHOPS: one KayKit building per class, solid (obstacle r at the building), take the hat at its door
  (HAT_STANDS = the doors): knight barracks + rogue market against the west courtyard wall (doors face the
  courtyard), ranger = the archery range (L1 east), barbarian lumbermill (replaces the L2 tavern) and mage tower
  (L2 west), priest = the church (L2 east). The themed machines and hat stacks are gone (the plate's dots show
  stock); an upgraded shop flies a team flag on its roof (plus the plate's star). Plates sit over the roofs
  (stand "b"/"top"). The west-front barrels went (the barracks is there).
- Land check: the dungeon wing's front/back walls now end 1 m inside the west wall (their rounded ends made a
  squeeze slot with the barracks); the market touches the L1 face (was 0.45 m off).
- Bots: bots fed 0 fish -- both teams' fish runners had become priests and held rampart posts (and kept the post
  after respawning as other classes). Fish runners are exempt from rampart duty; a post is dropped when the unit
  stops being a ranged defender. Match: fed 2, 8 rescues, 0 violations; rampart test picks non-runners.
- Protocol v13.

# 0.24.1 (Kevin): tutorial updated for the recent changes; only the VO text we need
- Lines: t_hat_2 / hat task (the Barracks door), t_up_1 / upgrade task (the Barracks), t_goal_1 (dungeon down
  stairs, King behind bars), t_goal_2 (smash his cell open), t_feed_1 (our dungeon down the stairs, the cell door
  opens for friends), t_grab_1 (their gate and his cell door broken, dungeon downstairs); new talk-only step
  "rampart" (t_rampart_1). 37 lines; 17 await recording (t_hat_2 and t_up_1 pulled: their old audio said "hat
  shop"). Kevin's sheet: Fatebound-Tutorial-VO-Needed.txt, numbered 1..17 in tutorial order; the number -> id
  map is in /home/claude/vo_staging/needed_map.json (1 t_intro_2, 2 t_hat_2, 3 t_up_1, 4 t_rampart_1,
  5 t_goal_1, 6 t_goal_2, 7 t_goal_3, 8 t_cake_1, 9 t_cake_took, 10 t_feed_1, 11 t_feed_done, 12 t_rescue_1,
  13 t_grab_1, 14 t_grab_done, 15 t_carry_1, 16 t_carry_done, 17 t_end_2).

# 0.24.2 (Kevin): the 17-line re-record -- the tutorial is fully voiced again (37/37)
- Kevin's read (167 s; ElevenLabs ignored the break tags again: longest pause 0.69 s). tools/vo_split.py --ids
  takes a subset in order. The length-fit + word check passed it, but the new head/tail transcripts showed three
  cuts in a row one sentence off (t_goal_2 ended "...and we win", t_goal_3 "...a dirty trick", t_cake_1
  "...magnificent"). New refine_cuts: per boundary, force-align the two lines' text over their two pieces and cut
  in the pause between the aligned last/first words (timings from the forced hypothesis's seg(): get_alignment()
  is empty without a second pass). It moved exactly those 3; every piece now starts and ends on its own line.
- Exported (+1.96 dB to -16 LUFS), 37 recordings, tutorial_test pending list empty.

# Trailer 2 (Kevin: cinematic trailer, the Herald hyping it up, a spectacular title reveal with VFX, the whole kingdom
# behind it and the sun god-raying through the title)
- tools/trailer2_shots.gd: dawn captive heroes assault rampart whirl feast carry reveal (Movie Maker, one shot per
  run, SHOT=...). "reveal" is golden hour (sun low beyond the enemy castle: light + sky + fog retinted for that shot)
  and writes the sun's screen position per frame (reveal_sun.json).
- tools/trailer2_reveal_fx.py: over the reveal -- sun glow broken into slowly turning beams, occluded by the title's
  letters and zoom-blurred from the sun (quarter res), a flash, FATEBOUND slamming in from 112 % (sun behind the
  letters' upper half), rim glow, a lens streak, rising embers, tagline + subline.
- tools/trailer2_edit.py: --stage segments (each shot trimmed + its gold caption; resumable) then --stage final
  (crossfades, a dip to black into the reveal, fade-out, Kevin's Spooky_3 from 11.1 s so its drop at 42.5 s hits the
  title at 31.4 s; --vo DIR with 1..9.mp3 drops the Herald into each shot and sidechain-ducks the music).
  (Split in two: a single pass with full-length caption loops ran past the 5-minute tool limit; a background
  process doesn't survive the end of a tool call.)
- Output: Fatebound-Trailer-2.mp4, 38.9 s 1080p30. Herald trailer lines: waiting for Kevin's recording.

# 0.24.3 + trailer 2 v2 (Kevin: the King faces the wall; the trailer doesn't convey what you do -- what hats are;
# pump the thrilling 16 v 16 multiplayer; a better caption under the title)
- View: the King in his cell faces his cell door (out through the bars); within 1.5 m of his throne he faces out
  over his castle; dropped, he keeps his last facing (rotation was only ever set while carried).
- Trailer: 11 shots, 42.9 s -- clash (16 v 16 armies charge, then fight as bots) "16 VS 16 CASTLE SIEGE", captive
  "THEY STOLE OUR KING!", heroes (a villager walks into the Barracks door, comes out a Knight) "GRAB A HAT...",
  lineup (the 7 classes) "...BECOME A HERO", assault, rampart, whirl, feast "STUFF THEIR KING WITH FISH", carry
  "CARRY YOUR KING HOME", throne (the rescue; the King is stood at his throne after it scores) "FIRST TO 3
  RESCUES WINS", reveal. Tagline: "THE ULTIMATE 16 VS 16 CASTLE SIEGE" / "Grab a hat. Storm the castle. Bring
  your King home." Song from 7.2 s: its drop lands on the title at 35.3 s (measured -20 -> -13 dB).
- Shot scripts must not walk the player's unit: the match loop overwrites its move with the idle joystick.
- Herald trailer VO: 11 lines, waiting for Kevin's recording (tools/trailer2_edit.py --vo DIR, 1..11.mp3).

# 0.24.4 (Kevin): "fix the arrows flying sideways instead of straight (this happens in game also)"
- The arrow model (weapons/arrow_bow.gltf) lies along +Z, head forward (measured z -0.64..0.62, narrow end +Z);
  the projectile root already turns +Z onto the flight path. _make_projectile's extra rotation.x = PI/2 stood
  every arrow on its tip. Removed; checked from the game camera and the side (head leading, fletching trailing).
- Trailer 2: clash, assault and rampart re-rendered and their segments rebuilt; final re-cut (42.9 s, title 35.3 s).

# Trailer 2 with the Herald (Kevin's 11-line trailer read, 24 s)
- tools/vo_split.py: --lines-file (plain text, pieces named 1..N) and --accept (reviewed flags). Forced alignment
  moved 8 of 10 cuts; 4 short lines were flagged only because the recogniser mishears them ("They stole our King"
  -> "restore locked in"); neighbours 0.00 everywhere, lengths as expected -> accepted. Lines in
  tools/trailer2_vo (1..11.ogg + lines.txt; .gdignore keeps them out of the game).
- tools/trailer2_edit.py --vo: lines scheduled so none starts before the previous ends (+0.12 s); the music ducks
  under the Herald (sidechain threshold 0.012, ratio 12); the finale line +3 dB over the drop (it was masked:
  heard as "they see these free trial"); limiter at -1 dBFS (the sum peaked at +4 dBFS). Measured: lines 6-9 dB
  over the music; max -0.8 dBFS.
- Outputs: Fatebound-Trailer-2.mp4 (with the Herald), Fatebound-Trailer-2-NoVO.mp4.

# Trailer 2 mix (Kevin: "the music volume drops too much when voice happens, it needs to blend better")
- Measured the ducked music alone (--duck-out): it was dipping 6-10 dB under every line (threshold 0.012 / ratio 12;
  0.06 / 2.5 still 6-10). Now threshold 0.12, ratio 2, knee 6, attack 40 ms, release 700 ms: 2.7-5.1 dB dips
  (~4 avg), the Herald 7-15 dB over the music; VO gain 1.7 (finale 2.6: 7.2 dB over the drop); limiter, -0.8 dBFS.
- New --stage audio: rebuilds just the mix onto an existing cut (video stream copied) in ~7 s.

# Trailer 2: the title pops in on "FATEBOUND" (Kevin: "right when he says 'fatebound' the title pops in")
- trailer2_edit.py finds the word's onset in the last line by forced alignment (word_onset; "fatebound" at 1.11 s
  in Kevin's read) and places the line so the word starts at the title (35.30 s, also the song's drop): line at
  34.19 s. Checked in the final mix: "fatebound" aligns at 35.29 s; the flash is on the 35.27 s frame, the title
  solid by 35.45 s.

# Trailer 2: the economy (Kevin: "the trailer should also include mechanics about gathering resources")
- Two shots after the heroes: "gather" (workers chopping a tree and mining a rock -- the nearest wood/stone pair on
  our side -- one hauling lumber) "CHOP WOOD. MINE STONE."; "build" (a worker raises a ladder against their wall,
  3 s, steps aside; a knight heads up it) "BUILD LADDERS. UPGRADE YOUR CASTLE." (captions shrink to fit).
  The ladder was there but hidden: the worker and the knight stood at its foot, in line with the camera -> the
  builder steps aside and the camera comes from the front-right.
- 50.0 s; title at 42.5 s = the song's drop, so the song now plays from its start (lead pad if ever negative).
- VO by shot name (VO_FILE): 1..11 = Kevin's read, 12 gather / 13 build pending: "Chop wood! Mine stone!",
  "Build ladders and upgrade your castle!".

# Trailer 2 (Kevin: ladders must clearly be for getting INTO their castle; the hat villager ran into the wall --
# show him equipping the hat and becoming the hero; replace the spin with a rogue's backstab)
- build: the ladder's 3 s build mostly happens before recording (it goes up 0.5 s in), the builder steps aside,
  a knight, a barbarian and a ranger climb over one after another, and the camera cranes up over the wall as they
  drop into the enemy courtyard. "BUILD LADDERS. CLIMB INTO THEIR CASTLE."
- heroes: when the villager becomes a Knight at the Barracks door he stops, turns to the camera in a gold ring and
  sparkle burst, then swings (closer, frontal camera).
- backstab replaces whirl: their ranger shoots the other way; our rogue creeps up behind (move 0.3) and the first
  stab finishes her (hp 12). "STAB THEM IN THE BACK". Shots trimmed (USE) so the title (41.7 s) stays on the drop.
- VO pending: 12 gather "Chop wood! Mine stone!", 13 build "Build ladders and climb into their castle!",
  14 backstab "Sneak up... and stab them in the back!". Line 7 (the spin) is unused now.

# 0.25.0 (Kevin): "when players use a ladder they climb up it and over the wall"
- Before: a ladder only let its team walk through the wall at ground level at half speed.
- Sim: ladder_depth(p, team) = how far across one of the team's ladders (+ on its side, - beyond, INF off it);
  ladder_lift(d, ground): up the rungs from the foot (1.35 m out) to the top (LADDER_TOP 2.9 m), a 0.15 m arc over,
  then an accelerating drop to the ground beyond (the courtyard, or the rampart walkway). Speeds by zone: 0.3 on
  the rungs, 0.45 over the top, 0.7 dropping. Visual height only (not "high ground" for arrows).
- View: units on a ladder are lifted by ladder_lift and play the arms-up Jump_Idle pose (the rigs have no climb).
- sim smoke "ladder climb": a knight peaks at 3.05 m, takes 2.1 s across, ends inside their courtyard.
- Protocol v14 (movement rule: server and client prediction must agree).
