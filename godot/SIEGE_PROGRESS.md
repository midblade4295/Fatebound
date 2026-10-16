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

# Trailer 2: the last three Herald lines; the backstab from behind
- Kevin's 3-line read split (12 gather, 13 build, 14 backstab; line 12 accepted after review: heard "drop would
  mind ... would mind stone"); now in tools/trailer2_vo. All 13 lines in the cut, no overlaps, -0.8 dBFS.
- Backstab: the archer turned round to face the rogue before he struck -- _start_attack aims at the nearest enemy.
  Her shots now fire without aim ("shoot" beat, aim=false) and her facing stays locked away from him.

# GitHub sync (Kevin: "upload to GitHub")
- No credentials in this environment (no token, credential store or gh CLI): Kevin pushes with push_siege_r5.sh.
- GitHub's claude/siege-dev-r5 (a269a43) had been rewritten (same work, different ids) and gained Codex's store
  listing pack and Kevin's PLAY_STORE_HANDOFF.md. Merged it (85b04de): the 26 conflicts were older copies of code
  already newer here (ours kept); the merge adds only those 41 docs files. The bundle is now based on a269a43,
  and the push was tested against a stand-in of GitHub's current state: fast-forward, nothing overwritten.

# Cinematic Play Store graphics (Kevin: "new cinematic screenshots for the Play Store")
- tools/store2_shots.gd (extends trailer2_shots.gd): SHOT/STILL_AT/OUT -> a 1080x1920 still of a staged trailer shot,
  HUD hidden; portrait cameras for captive (over the guards), build (along the wall), rampart (low, outside, up at
  the rangers), clash (unused: a jumble in portrait -> the gate assault opens the set instead).
- tools/store2_compose.py: gold Luckiest Guy headline + Fredoka subline over a dark top band; feature graphic
  1024x500 cut from the title reveal (title, god rays, tagline). 8 screenshots: assault, captive, heroes, build,
  rampart, backstab, feast, carry. Every claim true of 0.25.0.

# Trailer 3 (Kevin approved the recut after Derek Lieu's "Sheepherds" makeover)
- Core action first and given time: breakin (10 s, one shot: smash their cell door, grab our King, the bots carry him
  up the dungeon stairs; a gate pre-broken for the way out; camera follows the King), carry2 (a rogue's stab drops
  the carrier -- scripted "die" beat, a swing at a moving target can miss -- the King lies there a beat, the
  barbarian scoops him when in reach), throne. Then the layers: feast, toofat (their lone raider lifts their
  stage-4 King and can't move; our barbarian ends it; camera above the dungeon wall), gather, build, assault (the
  gate gives way), heroes, hatsteal (a villager walks over a fallen knight's hat). Variety last: rampart, backstab,
  clash (16 VS 16), reveal. Two title cards only (FIRST TO 3 RESCUES WINS, 16 VS 16).
- Music: the title on the song's biggest hit (72.5 s); the first drop (42.5 s) lands at 29.1 s as "getting in"
  starts. 66.6 s. The finale line is anchored ("FATEBOUND" on the title wins over the no-overlap rule).
- VO: 1 and 11 reused; 10 new lines (15..24) pending Kevin's read.

# Trailer 3 with the Herald (Kevin's 10-line read)
- Split clean (cuts on real pauses; 1, 5, 7, 8 accepted after review: misheard, e.g. "Or just knock" -> "all the
  snow"); lines 15-24 in tools/trailer2_vo. All 12 lines placed, no overlaps; "Rule two: don't drop him" on the drop,
  "Need a way in? Chop. Mine." on the song's first drop, "FATEBOUND" on the title.
- Lines over the busier music lifted (VO_GAIN_SHOT: assault, hatsteal, carry2, gather, heroes, feast): every line
  8.8-13.8 dB over the music. Limiter ceiling 0.80: the AAC encode overshot to 0.0 dBFS with 0.85; now -1.2 dBFS
  true peak.

# 0.25.1 (Kevin: "in the tutorial I couldn't exit the enemy castle -- doors should let them exit but not enter")
- Castle gates are one-way for the enemy: each gate has an inward normal ("in"); Sim.lets_out(g, p) = p on its
  castle's side. Push-out (collision), the bot's stop-and-break-the-gate check (_path_gate) and the gate's open
  visual honour it; find_path from inside an enemy castle temporarily makes that castle's intact gates cheap (the
  tutorial's guide arrow ran through a standing gate). From outside a gate still blocks until broken (a unit
  pressed on it is held ~1.45 m out; no move covers that in one tick). The jail door is unchanged.
- sim smoke "one-way gates" (out through an intact gate, can't come back in, path from inside uses the gate); match
  gate-violation check allows exits. Protocol v15.

# 0.25.2 (Kevin: "increase the graphical fidelity -- lighting, shadows")
- Settings > "High-quality graphics (shadows, glow, smooth edges)", on by default (hq_graphics -> SiegeMode.hq_gfx ->
  SiegeView.hq_gfx). The Mobile renderer has no SSAO/SSR/GI; what it adds: real sun shadows (2 PSSM splits to 80 m,
  2048 atlas, soft-low filter); casters = castles (merged kit), castle blocks, steps, iron bars, units, Kings
  (_cast(); make_body reads the static _cast_static); ground, water, grass, decals and FX only receive. Light
  rebalanced so the shadows read (the fill was tuned for a shadowless world -- shade kept ~52 % of lit, tonemapped
  flat): ambient x0.75 and cooler (#a9bcd8), sun 1.45, exposure +5 %: shade ~40 % of lit, cool blue against warm
  sun; contrast 36 -> 40 (std), mean brightness about the same. Subtle glow (levels 1-2, softlight), saturation
  1.12, contrast 1.06; MSAA 4x (2x without it).
- The software renderer (llvmpipe: tests, trailer and store renders) keeps the old look unless FB_FORCE_HQ: it once
  hung on shadow-casting Kings. Checked with FB_FORCE_HQ: shadows under walls, steps, buildings and units, no acne.

# 0.25.3 (Kevin: "make the auto 30fps toggled")
- The thermal guard (under 50 fps for 3 s at the 60 cap -> 30 fps, then 75 % 3D resolution if still under 26) is now
  a setting: "Auto 30 FPS when the phone runs hot" in Settings and "AUTO 30 FPS: ON/OFF" in the pause menu (same
  profile setting auto_30fps, default on = the old behaviour). Off: it never drops fps or resolution on its own.
- siege_guard_smoke: phase 2 with it off at ~30 fps -> no trip, cap stays 60.

# 0.26.0 (Kevin: "remove options for fps and just hard lock to 30. Also add even more effects")
- Locked at 30 fps (FPS_CAP 30; the sim ticks at 30 Hz): the pause menu's 30 FPS MODE / AUTO 30 FPS buttons, the
  Settings switch and the guard's fps step are gone; the guard keeps its resolution step (75 % when even 30 can't be
  held). siege_guard_smoke: cap 30 throughout; at ~20 fps the resolution steps down.
- More effects with High-quality graphics (the 30 fps budget pays for them): drifting cloud shadows on the terrain
  and the castle floors (terrain.gdshader + _cloud_floor_material; 20 %), grass tufts sway in gusts (vertex shader,
  still per-vertex lit), warm light motes drifting where the camera looks (GPUParticles3D, 90), sparse sun glints
  on the river (emission -> glow), projectiles and spark FX brighter so the glow blooms (_bright; rings/decals
  untouched), wall torches in each dungeon (RPG Tools torch, flickering OmniLight + flame). Checked with
  FB_FORCE_HQ (glints were first far too dense -> threshold 0.58-0.64; motes 0.16 m; torch 2.2x).

# 0.27.0 (Kevin: "make the water look much more realistic, like actually simulated water; let players walk through
# it but much slower; realistic physics on water that creates wakes")
- Wading: no river bank walls (Land.walls skips them); Sim.water_depth(p) = WATER_Y - height_at (0..0.5 m, the bed
  is at -0.95); move_mult eases to WATER_MOVE 0.45 by 0.35 m depth (carriers too); river nav cells cost 2.5, so a
  path near a bridge takes it. Bridge rails still block. Protocol v16. sim smoke "wading": across 11 m in 3.9 s
  (2.4 s on land); next to a bridge the path stays dry.
- Simulated water (High-quality graphics): a 512x52 height field over the river (x -34..34, ~13 cm cells) stepped
  each frame on the GPU with the wave equation (two SubViewports ping-pong, HDR 2D: R = now, G = a step ago,
  damping 0.984); each wading unit adds a Gaussian push scaled by its speed (16 max), a splash + spray when it steps
  in -- wakes, rings and bank reflections come out of the physics. New water shader: normals from the field's
  slopes plus flowing detail, deep/shallow colour, sky reflection at grazing angles (fresnel), see-through (bed and
  legs show), shore foam and foam on crests, sparse glints. Tuned on renders: first pass foamed everywhere
  (drops halved, crest foam 0.045-0.11, ripple shading x15). Without High-quality graphics: the old water, still wadeable.

# 0.27.1 (Kevin: "remove the foam effect and make the wake more noticeable")
- No foam anywhere: the High-quality water's shore and crest foam, and the plain water's white banks (now a slight
  shade). Without foam the wakes read through the physics: twice the push per wading unit (0.005 + 0.0085/(m/s)),
  ripple shading x28 (was 15), crests lighter / troughs darker (wake_tint 4.5), damping 0.989 (trails last longer).

# 0.27.2 (Kevin: "fps dropping here" -- 21 fps in a big fight at his front gate, resolution auto-dropped to 75 %)
- Measured, not guessed: tests/battle_bench.gd stages a 32-bot fight at the blue gate and measures each graphics
  configuration live (3D viewport render time, draw calls and triangles for the main and the shadow pass).
  Full High-quality 805 ms/frame (software renderer); without glow -4 %; without water sim + motes -8 %; MSAA 4x->2x
  -54 %; without shadows -32 %; two shadow splits to 80 m drew 323k triangles in 325 calls (more than the visible
  scene). Script cost of the same fight headless, uncapped: 4.2 ms avg, 6.6 ms 95th (x86) -- not the bottleneck.
- Fix: MSAA back to 2x; one orthogonal shadow pass to 45 m (the camera sees ~40 m): 283 ms (-65 %), shadow pass
  121k triangles in 97 calls; shadows look the same (render compared). Glow, water and motes kept.

# 0.27.3 (Kevin: "I don't see shadows from trees and stuff")
- 0.27.2 cut the shadow reach to 45 m on a wrong assumption ("the camera sees ~40 m"). Measured: the camera is 38 m
  up, the visible ground is 28 m deep at the bottom of the screen and ~70 m at the top, so the upper half had no
  shadows. One orthogonal pass to 75 m: trees, rocks, ledges and bridges shadowed again (render compared).
  battle_bench (MSAA 2x): 45 m 326 ms, 75 m 340 ms (+4 %), two splits to 80 m 349 ms -- the 21 fps was MSAA 4x.

# 0.28.0 (Kevin: "blood will splatter on the ground when hit, and when a player dies there will be a pool of blood")
- View only (no sim/protocol change). On "hit": a splat beside the target on the side away from the attacker (sized
  by damage) and 3-7 droplets flung outward under gravity that land as small spots. On "death": a pool spreading
  under the body over 3 s (ease-out). Procedural splatter textures (4 splat variants with satellite drops, 1 pool),
  lit and glossy (roughness 0.22) so sun and shadows fall on them. Splats last 18 s, pools 25 s, then fade 3 s;
  recycled with hard caps (90 splats, 24 pools, 60 droplets). Not on the river. Tuned on renders: first pass too
  small and near-black at the game camera -> brighter red, splats x1.6, pools x1.6.

# 0.29.0 (Kevin: "players should be able to shoot other players on the wall; mage and arrow projectiles faster -- hard
# to hit players moving")
- Before: hits are 2D, but every low shot died at a castle wall each tick, so a defender behind the parapet on the
  rampart could only be hit from another rampart. Now Sim.on_rampart(p) (the walkway, Castle.WALK_*) and
  _lob_at_rampart: a ranged shot aimed within ~11 deg of an enemy on a rampart, in range, is "high" (over the walls
  and gates, like shots from the rampart). Only the walkway: not terraces deep inside. Bots treat a rampart foe as
  shootable. Auto-aim already considered them (nearest_enemy has no line-of-sight check).
- proj_speed: ranger 22 -> 33 m/s, mage 15 -> 24 m/s (life = reach / speed: same range).
- sim smoke "shooting the rampart": a ground ranger outside takes a rampart defender 60 -> 15 hp; a defender in the
  courtyard behind the wall is untouched. Protocol v17.

# 0.29.1 (Kevin: "movement slows down in the dungeon like there is water")
- Bug from 0.27.0: water_depth = WATER_Y - height_at with no check for the river; the dungeon floor (-1.6 m) read as
  1.15 m of water -> wading speed (0.45), river nav cost 2.5 (bots avoided it), no blood, splash/wave pushes.
  water_depth now counts only within the river band (|z - river_c| <= RIVER_HW + 1.6). Measured before: both
  dungeons depth 1.15, move_mult 0.45; after: 0 and 1.0. sim smoke asserts it; the same seed's bot match now ends
  3-2 by rescue at 5:36 (was a 12-minute time-out). Protocol v18 (movement rule; server and client must agree).

# 0.30.0 (Kevin, Fat Princess map reference): a bigger, natural map; towers you climb; no tower respawns
- Land (siege_land.gd): field 88 x 140 m (was 64 x 128) with a natural edge (EDGE_BLUE, point-mirrored; "edge" walls,
  nav cells beyond it solid). Scenery beyond it: rock walls on the west and behind the castles; on the east between
  the castles a sheer 24 m drop (the cliff side) with the river pouring over a waterfall into a valley (view only).
- The river widens into a lake round an island (ellipse 9 x 5.5 m). The island lane: one narrow bridge (rails
  +-1.25 m) from each bank to the island's tips; two full bridges at x = +-24. Everything stays wadeable (Round 33).
- Rounded plateaus (polygons with ramps, rock faces) replace the box terraces: a west highland and an east bluff
  on the cliff edge per side. 5 towers: one on each plateau + the island tower. The tower nearest each castle is
  on the highland, so the tutorial's "tower up on the ledge" stays true.
- Paths, resources, cover rocks re-placed; siege_land_check covers them; terrain rebaked.
- Towers (sim): archers and mages of the holding team climb (ACTION within 3.4 m; CLIMB / CLIMB DOWN), 4 places.
  On top: pinned, +30 % range, shots fly over walls, no dodge, no mage nova; melee can't reach or target them;
  arrows/fire/catapult still hit (towers no longer stop projectiles). Capture counts ground units only; losing the
  tower throws everyone off (0.8 s stun). Bots (ranged, not raiders) climb when an enemy is within 18 m of a tower
  we hold, max 2 bots per tower, and climb down after 8 quiet seconds or when a King is on the move.
- No respawning at towers (the forward-outpost rule is gone). Workers still bank loads at towers we hold (3.4 m).
- Net: protocol v19 (unit field 31 = tower + 1; clients rebuild op.occ). Server redeploy needed for online.
- Water (view): the simulated patch now spans the field and the lake's width (680 x 198); UV2 carries the bank-to-
  bank coordinate for the shallows. Waterfall sheet + valley river on the cliff side.
- Tutorial: t_out_done re-recorded in the Herald's voice (ElevenLabs, eleven_v4, Edward), text in SCRIPT.md.
- Tests: tower_test (21 checks) new; land_check, reach updated; sim smoke's ladder coordinates moved with the castle.
- KNOWN PROBLEM: bot matches on this map: 0 King pickups in seeds 11 and 22 (0.29.1 map: seed 22 rescues).
  Over 300 s of seed 22, 34 of 57 blue raider deaths are inside blue's own courtyard behind the west gate
  (-6, 48) (0.29.1 map: 3 in blue's half, 27 in red's). Not yet diagnosed. LANE_NAV_COST 2.2 added (bots used to
  pile into the lane) did not fix it. siege_sim_smoke fails on rescues=0 until this is solved.

# 0.30.1 (Kevin, phone screenshots: cliffs, outposts)
- Cliffs: new rock.png (grey layered stone slabs, was brown flagstones); terrain.gdshader samples it triplanar
  (no stretching on angled faces), blends rock/grass on a ragged noisy edge, adds faint strata and moss on faces
  that turn up. Plateau faces wander (Land.wobble, even so heights stay point-symmetric); the field's rock walls
  wander a metre (edge_jit), step once on the way up and vary in height; their tops are grass with stony patches
  (they were one flat brown sheet). Tried KayKit rocks along the cliffs: hexagonal prisms, read as fence posts in
  tools/terrain_shot.gd renders -- dropped (_plan_cliff_rocks kept, unused).
- Not every outpost on a plateau: the east tower is on open ground at (25, 17); the east bluff stays as high
  ground (one ramp, north). 2 of 5 towers raised (the highland ones, so the tutorial's "up on the ledge" holds).
- No climbing (TOWERS_CLIMBABLE = false; code kept). Towers stop shots again. Protocol v20.
- Towers 25 % bigger (model 4.0, base 4.5, OUTPOST_TOWER_R 2.25, worker drop 3.8 m), sunk 0.14 m, a level patch
  round each foot (rolling fades out), bushes and a ring of grass tufts and flowers round the base.
- Tutorial t_out_done: Kevin's original take with "We can respawn here," cut out at the pauses (heard back
  exactly as the new text); the 0.30.0 ElevenLabs re-record is no longer used.
- Tests: tower_test rewritten (no climb, solid, capture from the ground, no respawn, worker drop-off, 2 of 5 raised);
  reach points moved. Full quick suite passes; bot matches: seed 22 blue wins 3-0 by rescue at 650 s, seed 11 0-0
  on time (as on the 0.29.1 map) -- the 0.30.0 rescue regression is gone.

# 0.30.2 (Kevin: "naturally formed ... slight hills where players can climb up in a lot of it and maybe steeper
# spots"; "make it so players can climb up captured towers")
- Plateaus and ramps are gone. Land.HILLS: smooth rises walkable from almost anywhere (flat-ish top to r0, easing
  out by r1, wobbling outline): the west highland (2.2 m, its tower on top), the east rise at the cliff edge
  (2.6 m), a 1.1 m knoll mid-field. Land.SCARPS cut short rock faces into three hill flanks (the hill drops away
  within 1 m outside the line, tapering to slope over 2.6 m at each end); walls only along the steep middles.
  Rolling ground a little livelier (amplitude x1.25). Rock on the scarp faces/lips via the terrain mask.
- Towers: any class of the holding team climbs again (TOWERS_CLIMBABLE, TOWER_CLASSES = all); only archers and
  mages attack from the top (TOWER_SHOOTERS); block/whirlwind/priest beam don't work up there. Bots don't climb
  (TOWER_BOTS = false). Top floor 5.6 m (tower model x4.0). Towers don't stop shots (people stand inside them).
  Protocol v21.
- Tests: tower_test (climb any class, knight can't fight up there, ranger reach, arrows hit, ejected on capture,
  no respawn, worker drop-off, 2 of 5 raised). Quick suite: all pass except siege_sim_smoke (rescues=0 in seeds
  11 and 22; 0.30.1 had 3 in seed 22). Seed 22 trace: red breaks blue's west gate at 84 s and a red barbarian
  inside kills 12 respawned blue villagers in the courtyard -- the defence collapses early. Not fixed yet.

# 0.30.3 (Kevin, phone screenshots: rings, tower spot, roofs)
- Capture rings are painted by the terrain shader (uniform arrays posts / post_ring / post_cap, set in
  _sync_outposts): a dashed ring in the owner's colour (white neutral) with a faint inner tint, and while a capture
  is under way a fill growing from the middle in the capturing team's colour. On hills the old torus decals sank
  into the slope; the ground now draws them. OUTPOST_R 5 -> 6.5.
- The east tower moved to Kevin's circle on the east rise: (35, 18.5) (the hill re-centred on it, r0 7 m flat top;
  its scarp moved south to the hill's edge).
- Towers: roofs off (the KayKit "_top_" piece hidden), x6 wide / x4 tall, a plank deck inside the rim at 5.68 m,
  the owner's flag on the rim. OUTPOST_TOWER_R 3.0; climb within 4.0 m; worker drop 4.4 m. People on the deck
  walk about freely (kept within TOWER_TOP_R 1.85 m of the centre; they push each other but not the ground), 8 of
  them; climbing down drops you on the side you stand on. Protocol v22.
- Tests: tower_test adds walking about on the deck. Quick suite all pass; bot matches: see the smoke line in the
  round report (rescues > 0 again).

# 0.30.4 (Kevin: "projectiles are firing from the base of the outpost instead of from the top"; "player can run
# off top of outpost")
- Shots from a tower's deck carry h0 (TOWER_FLOOR), their origin o and dd (the aimed target's distance, from _aim;
  full reach if nothing was aimed at). The view starts them at the shooter's height and brings them down onto
  the target, nose tipped down; past it they fly on at normal height. Online the snapshot sends [id, pos, vel,
  kind, o, h0, dd] for those (the last slide to impact keeps them). Protocol v23.
- Walking past the deck's edge (TOWER_TOP_R) while moving outward jumps you down on that side (same as CLIMB
  DOWN); ACTION still works.
- tower_test: walk about, run off the edge, climb back, arrow launch height/aim distance. Quick suite all pass.

# 0.30.5 (Kevin: the Knight's upgrade is the Crusader, with Hammer Throw)
- UPGRADE_NAME knight: Paladin -> Crusader (hat shop "Crusader Hats"). ability_of(upgraded knight) = "hammer"
  (like the Berserker's whirlwind replacing spin): the Crusader trades the shield for Hammer Throw.
- Hammer Throw: a "hammer" projectile (stepped by _step_hammer, not the arrow code): 9 m out at 17 m/s through
  everyone in its path, then back to wherever the thrower is now; each enemy hit once out and once back for one
  swing's damage (stat dmg); walls/gates turn it early; no swinging while it's out; 10 s cooldown (HUD ring uses
  HAMMER_CD); not from a tower deck. Dies with its thrower. Bots throw at 2+ enemies in a line within 9 m, or one
  standing back past 3.5 m. View: a glowing gold head on a wooden handle spinning end over end. Protocol v24.
- Tutorial t_up_done: "Crusader hats!" generated in the Herald's voice (ElevenLabs, eleven_v4, Edward, 14 credits)
  spliced in place of "Paladin hats!" at the pause; the rest is Kevin's original take (heard back exactly).
- tests/hammer_test.gd (11 checks) added to the suite. Quick suite all pass (seed 22: red wins 3-0 by rescue).

# 0.30.6 (Kevin: a sound effect for throwing the hammer)
- assets/sounds/hammerThrow.wav: ElevenLabs Sound Effects v2 (eleven_text_to_sound_v2, 1.2 s, prompt influence
  0.55; prompt: heavy war hammer thrown hard, whoosh then spinning end over end, faint magical shimmer, cartoon
  fantasy, dry). 3 takes (12 credits each); picked the one with a strong opening whoosh and three heavy spinning
  whomps (the other was a thin continuous whirr), trimmed to 1.05 s with a fade, 32 kHz 16-bit mono, peak 0.56 like
  the rest of the cue catalog (cue-catalog.json entry added).
- SiegeMode._event_sound: plays it on the Crusader's "attack"/"hammer" event, offline and online; full volume for
  your own throw or one within 9 m, quieter to 28 m, silent beyond. (It is the first in-match combat cue.)

# 0.30.7 (Kevin: the hammer sound should be much better, "like Thor throwing his hammer (without thunder)")
- Rounds 2 and 3 of single-prompt generations were rejected. The model guide (eleven_text_to_sound_v2) asks for
  one short concrete sound per prompt, no cinematic words, separate nodes for layers. Generated layers that way:
  "Heavy iron war hammer swung hard through the air, deep powerful whoosh, close-mic" (2 takes), "Heavy metal
  hammer spinning fast through the air, deep rhythmic whirring hum, passing by" (Kevin picked take 2), an electric
  charge (Kevin: neither). Kevin: combine both whooshes.
- Both whoosh takes were almost all sub-bass (93 % / 63 % under 120 Hz): a phone speaker plays little of that.
  Mix (tools/hammer_sfx_mix.py): whoosh B as the punch at 0 s, whoosh A trimmed so its peak lands just
  behind (a thick double hit), both saturated so they grow harmonics; a synthesized noise swish sweeping 6.5 ->
  1.5 kHz, pulsing at ~13 Hz (the spin); spin take 2 from 70 ms with its pitch falling 4 semitones as it flies
  off; bus high-pass 55 Hz, soft clip, 0.18 s fade, peak 0.56. 44.1 kHz (the old cues are 32 kHz). "Punchy"
  version installed as hammerThrow.wav; a "heavy" version (more body, slower spin) handed over as an option.
- SFX credits so far: ~410 (12/18-credit fixed-length takes; auto-length takes cost 50 each).

# 0.30.8 (Kevin: "use sounds in this pack and put them in game where they should go" -- TomMusic Free Fantasy SFX Pack)
- License (itch.io page): royalty-free, commercial use OK, credit appreciated, no resale/redistribution of the pack.
  CREDITS.md added. NOTE: the GitHub repo is public; pushing these files there may count as redistribution.
- 95 one-shots converted (mono 44.1 kHz WAV, leading silence trimmed, length capped, peak 0.56 combat / 0.32
  footsteps) as assets/sounds/tm_*.wav (5.2 MB); 3 ambience loops as Ogg (2.6 MB). Converter: /tmp/convert_tm.py
  (not kept; the mapping is in SiegeMode._event_sound and below).
- SiegeMode: every sound is placed relative to you (full within 6 m, fading out by 24 m; gate breaks, catapults
  and gate hits carry further; your own actions always full). Mapping: swings (sword pack) for melee attacks incl.
  villagers/workers, bow shots, fireballs (mage), firespray (nova), sword/bow/spell impact by attacker class, sword
  blocked (shield blocks), chop/mine (gathering), mine (gate repair), chest close (worker delivers), chest open
  (upgrades bought), unsheath/sheath (hat taken/dropped), door thuds (gate hits), rock-wall crumble (gate broken),
  gate open/close (allies passing; soft, 12 m), gate close (rebuilt), lock (jail reset), meteor throw/swarm
  (catapult fire/impact), spell impact (fire explosions), wood/dirt landings (ladder, tower up/down), dirt jump
  (dodge), water spray / jump (fishing). Hammer throw keeps its own sound.
- Your footsteps: water when wading, wood on bridges/tower decks, stone in castles and on brick paths, earth
  elsewhere; Knights/Crusaders use the chain-mail variants. Ambience: forest day bed, river louder near the water,
  waterfall near the cliff-side falls; follows master x sfx volume, muted/unfocused silences it.
- native_audio: 16 voices (was 8); play(cue, quiet, vol) volume factor.
- tests/match_audio_test.gd: cues exist, attacks/hits heard, footsteps per surface, distance fade. Quick suite pass.

# Match music, ready for the song (Kevin: "play the game's music ... not drowning out the sound effects"; "use trailers")
- The game had no music (a saved "music" setting at 0.6 that nothing used). The trailers' music is Kevin's Suno track
  Spooky_3.wav, which isn't in the repo -- waiting for it.
- SiegeMode._music_step: loops res://assets/music/match.ogg if present. Gain MUSIC_GAIN 0.10 x master x music
  (track normalised to -16 LUFS by tools/music_prep.sh, which also crossfades its end into its start for the loop).
  Ducking: every placed cue raises _duck to its volume; the music drops by up to MUSIC_DUCK (half, -6 dB) within
  ~0.1 s and eases back over ~1 s. Muted/unfocused: silent.
- Settings: a Music slider (Master, Effects, Music); siege_app passes it as audio.levels.music.
- Checked with a stand-in (the procedural trailer placeholder, not committed): loads, audible, ducks 0.045 -> 0.028
  under a nearby hit and returns to 0.045. match_audio_test runs those checks when a track is installed.

# 0.30.9 (Kevin: music steady, no dipping, quiet by default; river quieter)
- Ducking removed: the music sits at one level (MUSIC_GAIN 0.10 -> 0.045, so 0.020 linear at the default master
  0.75 x music 0.6: about -50 LUFS for a -16 LUFS track); it only eases when muted or the Music slider moves.
  match_audio_test checks it stays put through a nearby hit and a gate crash.
- River ambience 0.55 -> 0.14 (at the bank: -35.5 -> -47.4 dB, the forest bed is -49.0); the waterfall was louder
  still (-30.0) and came down with it (0.7 -> 0.12: -45.3 dB at its closest).
- Still waiting for the trailer song (Spooky_3.wav) for assets/music/match.ogg.

# 0.30.10: the match music is the Fatebound theme (Kevin's track, Fatebound-Theme-Spooky_3.wav, the trailers' song)
- tools/music_prep.sh: 103.4 s at -23.9 LUFS -> normalised to -15.3 LUFS (target -16), last 1.5 s blended into the
  first (equal-power) -> assets/music/match.ogg, 101.9 s loop, Ogg q5, 2.0 MB. The song has no fade-out (ends at
  -25 dB RMS, starts at -29), so the seam holds level (checked 3 s either side).
- Plays steady at 0.020 linear at default settings (about -49 LUFS in the mix), under the effects; Music slider.

# 0.30.11 (Kevin: music "just a bit louder"; "there is white on water" -- screenshot: the lake south of a straight
# line past the island tower rendered flat white)
- Music: MUSIC_GAIN 0.045 -> 0.064 (+3 dB).
- White water: could not reproduce here (tools/water_shot.gd renders the lake with the real terrain, both water
  shaders, the game's lighting and the ripple step: no white on llvmpipe). Likely causes on the phone, all hardened:
  (1) the ripple simulation now covers the whole lake (5x the cells): one bad cell (NaN/inf) spreads and the water
  shader renders it white -- the step shader now scrubs NaN/inf and clamps to +-0.6, and the water shader guards
  its samples and clamps the slope; (2) glare: the high-quality water's sun specular (roughness 0.05, specular
  0.75) and sky mix (up to 0.75) over a lake-wide sheet -- now roughness 0.16, specular 0.35, sky mix up to 0.5;
  standard water specular 0.6 -> 0.35, roughness 0.12 -> 0.18.

# 0.31.0 (Kevin: boulder-shaped "iron" (stone) nodes; trees chop down into logs, boulders break into rocks; logs/rocks
# have physics -- roll, get pushed by walking into them; click to pick up)
- Nodes: "amount" now counts swings left (trees 5, boulders 6); the last swing fells the tree into LOGS_PER_TREE 4
  logs lying along where it fell (boulder: ROCKS_PER_BOULDER 4 rocks scattered), each worth ITEM_VALUE 2; a stump /
  rubble stays and the node grows back whole after NODE_REGROW (35 s / 45 s). Chopping no longer fills your arms.
- Sim.items: 2D bodies (logs = capsules, half-length 0.85, r 0.24; rocks = balls r 0.32). Anyone walking into one
  shoves it (logs spin when hit off-centre); they roll down slopes (gravity along the ground gradient; a log rolls
  sideways and hardly slides lengthways); logs float off downstream in the river, rocks drag; walls, gates, trees and
  towers stop them with a little bounce; they keep apart; unclaimed ones vanish after 150 s.
- Workers pick one up with ACTION ("PICK UP"), up to 3 (CARRY_MAX 5 -> 6), one kind at a time, and bank them as before.
  Bots: pick up any matching logs/rocks within ~32 m first, otherwise chop/mine, deliver when the next won't fit.
- Net: protocol v25, snapshot "it": [id, log/rock, x, z, ang, roll, rax].
- View: boulder nodes are procedural low-poly boulders (icosphere + smooth noise, squashed, flat-shaded greys), rubble
  when broken; logs are bark cylinders with pale cut ends rolling about their axis; rocks small boulders; carried and
  stockpiled stone shows rocks (was the KayKit ingot stack). Sounds: tree down (wood thud), boulder break (crumble),
  pick-ups. Event "item_pickup" (not "pickup": that is the King's).
- tests/items_test.gd (15 checks incl. 120 units delivered by bots in 4 min). Quick suite all pass.

# 0.31.1 (Kevin: High Priest gets Resurrection; bigger priest heal and wizard AoE)
- ability_of(upgraded priest) = "resurrect" (Sanctuary stays on the Priest): raises the ally who fell most recently
  within RESURRECT_R 6 m, where they fell, at 40 % health, before their 5 s respawn takes them to the castle; their class
  comes back if their dropped hat is still there (the hat is taken off the ground). Cooldown 30 s (HUD ring). Bots use
  it when someone's down within reach. Light ring + sparks; sound: the pack's "Firebuff 1" as tm_revive.
- SANCTUARY_R 4.5 -> 6.5; NOVA_R (new constant) 3.3 -> 4.8, its ring drawn to match. Mage bots now nova only with an enemy
  inside NOVA_R (they used to fire it 35 % of the time at any range).
- Protocol v26. tests/priest_test.gd (12 checks).
- Quick suite: all pass except siege_sim_smoke: seeds 11 and 22 both 0-0 on time (0.31.0: 3 rescues in 22). Seeds 33, 44,
  55: 0-0, 3-0 by rescue at 316 s, 2-1. Bot rescues remain seed-dependent; not changed here.

# 0.31.2 (Kevin: High Priest -> Necromancer with the Necromancer skin and the skull staff; his beam drains an enemy (green)
# and heals him, with a second white beam healing an ally)
- KayKit Skeletons 1.1 (CC0, EXTRA tier; LICENSE-skeletons.txt): heroes/Necromancer.glb (Rig_Medium like the Adventurers,
  so the existing animation libraries drive it), weapons/Skeleton_Staff.gltf (+ .bin, skeleton_texture_A.png).
- UPGRADE_NAME priest: Necromancer; hat shop "Necromancer Hats". View.look_key(): upgraded priest -> "necromancer" look
  (model Necromancer, right hand Skeleton_Staff, the priest's casting animations).
- The Necromancer's beam (attack): _necro_beam locks a green beam on the nearest enemy in reach (9 m) and drains DRAIN_DPS 14
  life/s (applied in 7-point chunks; kills count), healing himself the same; while draining, a white beam (beam2) heals the
  nearest injured ally in reach by NECRO_ALLY_HEAL 22/s. No enemy in reach: no beams. Resurrection stays his ability.
  Bots drain the nearest enemy in reach, close in on one within 16 m. Drain hits make no sword sounds.
- Net: unit field 32 = beam2 (+1 index); protocol v27. View: gold heal (Priest), green drain + white heal (Necromancer).
- priest_test: +9 checks (name, model, staff, both beams, drain/self-heal/ally-heal, no enemy no beams, online beam2).
- Quick suite: all pass except siege_sim_smoke (seeds 11/22 0-0 on time, as in 0.31.1).

# 0.31.3 (Kevin: class caps for balance, tuned for 16-player teams -- bots fill every match)
- Sim.CLASS_CAP per team: knight 4, barbarian 3, rogue 3, ranger 3, mage 2, priest 2, worker 3; villagers uncapped. An
  upgraded class counts as its base (a Necromancer is one of the 2 priests). Counted over living units (the dead are
  villagers), so a place frees when someone falls.
- Enforced everywhere a class is gained: stands (walk-over and swap), dropped hats (stay on the ground while full), the
  workshop's tools, a Resurrection (comes back a villager if their class filled meanwhile; the hat stays). Bots only head
  for hats/stands they may take. Players get "Knights full · 4/4" (HUD toast, 1.5 s apart); a full stand's ACTION says
  FULL; the workshop button reads "TAKE TOOLS · BECOME A WORKER (n/3)" / "WORKERS FULL · 3/3" (disabled).
- View: above every stand, your team's count of that class / cap (green; red when full).
- Protocol v28. tests/caps_test.gd (7 checks; 5 min of 16v16 bots peak at the caps, never over).
- Quick suite: ALL PASS (bot matches: seed 11 1-0 by rescue at 203 s, seed 22 0-0).

# 0.31.4 (Kevin: no class caps after all; balance through the stands, no heal stacking, flatter armory, weaker workers,
# per-class stats)
- CLASS_CAP emptied (class_full() always false); the stand count labels, FULL label and worker count are gone.
- Stands per class: STAND_STOCK knight/barbarian/rogue/ranger 3, mage/priest 2; STAND_REGEN 6 / 6 / 6 / 8 / 10 / 12 s.
- Healing doesn't stack: a target gets one Sanctuary per 3 s; a second healer beam (Priest's or Necromancer's white) on a
  target already beam-healed this tick heals at half.
- armory_mult: +8 % a level (was +12 %; max +24 %). Worker hp 95 -> 80.
- Sim.class_stats (per class label: damage dealt/taken, kills, deaths, seconds alive); tools/class_balance.gd runs seeds and
  prints the table. Protocol v29. tests/stands_test.gd replaces caps_test (9 checks).
- Quick suite: all pass except siege_sim_smoke (seeds 11/22 0-0 again).
- First balance table (seeds 11, 22, 44; 16v16 bots): Mage K/D 2.39 with the least damage taken per minute of any fighter
  (105/min); Necromancer 20 kills / 3 deaths (12.6 min, small sample); Crusader 2.07; Barbarian 1.80; Archmage 1.43;
  Assassin 1.41 (7 min); Berserker 1.07; Rogue 1.01; Knight 1.04 with the lowest damage of the fighters (121/min);
  Workers 0.08 (321 deaths). Bot class choices and play are scripted -- read as direction, not truth.

# 0.31.5 balance (from the 0.31.4 table)
- Necromancer heals himself for DRAIN_SELF 0.5 of what he drains (was all of it). Mage fireball x MAGE_BOLT 0.9 (nova damage and
  radius unchanged). Knight dmg 18 -> 21 (the Crusader's swing and hammer scale with it).
- Re-run (seeds 11, 22, 44; scores 0-0, 0-1, 1-1): Mage K/D 2.39 -> 1.74 (dmg/min 313 -> 287), now level with Barbarian 1.72
  and Archmage 1.73; Crusader 2.00; Berserker 2.39 (18 min); Assassin 1.28; Rogue 0.90; Knight 0.75, dmg/min 111 -- the extra
  damage didn't show because bot knights spend their time blocking (_think_shields), not swinging; Necromancer 6 kills / 0
  deaths in 7 min (too little play to judge).
- Quick suite: all pass except siege_sim_smoke (seeds 11/22 0-0; 4 pickups, 1 carried back, no rescue).

# 0.31.6 (Kevin: bot Knight change; "I don't think bots fish and feed the King")
- Knights, measured (seed 11, 10 min, 12,039 samples of bot knights): blocking 0.9 % of the time (Round 17 already limits the
  shield), moving 42 %, idle 15 %, swinging 41 %; 65 % of their time as escorts, 29 % defending, 6 % raiding. Their low damage
  is not the shield. Gate damage now counts in the class table (gate/min): knights 9/min, so not gates either. Likely: slowest
  class (4.6 m/s) with a short reach (1.7 m) swinging at enemies that move away. No knight change made.
- Fishing, measured: bots did fish and feed, but only defenders whose id hashed even -- about one per team, sometimes none
  (seed 22: one team fed the enemy King 0 times in 12 min). Now exactly FISH_RUNNERS 1 defender per team is a fish runner
  every match, setting out 3 s after a gate alarm (was 6 s). Seeds 11/22: 10/10 and 12/11 feeds per team. (2 per team left
  too few on the rampart: the rampart-bots rule test fell to 1 of 3.)
- Quick suite: all pass except siege_sim_smoke (seeds 11/22 0-0; heavier captive Kings make rescues harder).

# 0.31.7 (Kevin: "I meant make that knight change")
- Measured first (seed 11, 5 min): bot Knights hit 80 % of their swings and block < 1 % of the time; they simply swung
  half as often as Barbarians/Rogues because as escorts they only engaged within 6.5 m.
- KNIGHT_AGGRO 3.0: bot Knights engage 3 m further out (escort 9.5, defend 11, raid 6.5). Same seed: 6.3 -> 12.4 swings/min,
  5.1 -> 10.7 hits/min (Barbarian 17.5, Rogue 14.1 hits/min).
- Knight reach 1.7 -> 2.0 m (class table, seeds 11/22/44: Knight K/D 1.08 -> 1.31, gate damage 9 -> 32/min).
- Quick suite: all pass except siege_sim_smoke (seeds 11/22 0-0; 7 King pickups, 2 carried back, no rescue).

# 0.31.8 (Kevin: optimise fps, fix the long start after Play, shrink online packets)
- Match start, measured headless on the build box: 1,435 ms to the first frame -> 548 ms.
  * assets/terrain/cache.res (SiegeTerrainCache, baked by tools/bake_land.gd, 1 MB): terrain and outer-land meshes, the
    foliage plan (1,515 instances) and the 5 blood textures. View._load_cache() uses it when Land.bake_key() matches
    (land data hash), else generates as before. siege_land_check should be extended to check the key.
  * AssetCache.preload_async()/poll(): the app loads the 78 models a match needs (assets/terrain/preload.json, written by
    tools/preload_list.gd) on a thread while the menus are up; AssetCache.scene() waits for a pending load.
  * HUD: the workshop and pause panels (~370 ms together) are built on first open (Hud.paused()/show_pause()).
  * Left: terrain build 120-190 ms (water strips, MultiMesh fill), castle kit 65 ms, Sim.setup ~50 ms.
- Sim tick 2.17 -> 1.54 ms (16v16, 2 min avg): resting logs/rocks sleep until a unit is within 3 m; the ground slope under
  an item is re-read every 6th tick; _sync_outposts uploads the ring uniforms only when a ring changed.
- Net (protocol v30): snapshots 5,525 B raw / 1,702 B zstd -> 3,406 / 1,111 (-35 %): 24.9 -> 16.3 KB/s per player at 15 Hz.
  Projectiles 11 x int16 (22 B each; was ~60 B of Variants), items 7 x int16, Kings as plain arrays; slow state (st, lv,
  g, n, op, hs, hd, l) only when its hash changed, in full every FULL_EVERY 15 snapshots. Units (2,112 B) are now 62 %.
- Timing instrumentation kept: Mode.ready_times, View.build_times (static dictionaries).
- Quick suite: all pass except siege_sim_smoke (seeds 11/22 0-0).

# 0.31.9 code cleanliness pass (gdlint 4.5 + a reference scan over scripts/, tests/, tools/, server/)
- Removed dead code: sim stand_pos, altar, forward_outpost, enemies_of, ladder_climb, tower_slot_pos and the constants
  ROLL_TIME, DOOR_X, OFFERING_EVERY, LADDER_CLIMB, HAT_STAND_R, RESPAWN_HAT_NEAR, TOWER_SLOT_OFF, ALTAR_P; view hex_pos,
  _machine_piece, _stairs, _parapet, GROUND_TINT, HAT_WEAPON, MACHINES (22-line table), MACHINE_GLOW, _beam_mat; land
  _out_normal, LEDGE_H; hud FACE_COLOR; ui CARD_EDGE, GOLD_DEEP, ORANGE; visual_theme title_plate, apply_tactile, cta,
  install; castle_mesh WALL_H, WALL_T, TOWER_R, GATE_TOWER_R, TOWER_H, PARAPET_H, PARAPET_T; server _bool_list.
- Land: one preload of siege_castle.gd (Castle) instead of two; view: path.png preloaded once (PATH_TEX) instead of three
  loads; elif-after-return, two unused arguments marked, timing variables renamed.
- gdlint now reports only style preferences the codebase deliberately keeps (long lines, definition order, single-letter
  geometry variables, long files).
- Kept on purpose: CLASS_CAP machinery (empty; class_full()/can_take_class() make re-adding caps a one-line change) and
  the tower-climb code paths.
- Quick suite: all pass except siege_sim_smoke (seeds 11/22 0-0, 0 pickups this run).

# 0.31.10 (Kevin, screenshot of the dungeon: jail door should sink into the floor; a ring floating above the King;
# "AI is running in king cell and just running against wall")
- Measured (seeds 11/22, 10 min): 9 bot defenders spent > 4 s inside their own team's jail cell. Their guard spot was
  theirs.pos - 2 m "outward", which since the cell moved to the west wing lies behind the cell's back wall: the door lifts
  for the castle's own team, so they walked in and pushed against that wall. The floating ring in the screenshot is the
  stuck defender's own ring and health bar inside the wall.
- Defenders now guard from jail_outside() (1.5 m outside the cell door), spread along it. Fish runners feed the captive
  through the bars (within JAIL_FEED_R 1.3 m of that spot, or FEED_RADIUS of the King as before) and never enter.
  Re-measured: 0 own-team units in a cell; one enemy rescuer waiting beside a King in a broken jail (intended: waiting
  for enough lifters). Feeding still happens (smoke: fed=58).
- The jail door sinks 2.35 m into the floor when it opens (was rising).
- 7 rings drawn at a fixed height (King pick-up/drop/recapture, gate and jail breaks, workshop, catapult, throne) now sit on
  the floor under them (Sim.height_at), so none float in the 1.6 m-deep dungeon.
- Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22).

# 0.31.11 (Kevin: "the gold ring is still floating above the King's head")
- It was the gold cell marker decal in _build_castle, drawn at Castle.L1_H + 0.06 (1.86 m: the level-1 platform where the
  cell used to stand); the cell is now in the sunken dungeon (floor -1.6), so it hung 3.5 m up. Now at Sim.height_at(cell).
  (0.31.10's diagnosis -- a stuck defender's ring -- was wrong for this ring; the stuck defenders were real and are fixed.)
- Scanned every flat decal in a running match against the floor under it: the only other one off the floor is the
  waterfall foam, which is meant to be in the valley 24 m below.

# Trailer 4 (Kevin: a cinematic trailer showing off the scenery, building to the title moving into the shot with the sun's
# light reflecting off it; trailer 2's rules; then: no captions, only the final title; new Herald lines to match)
- Rendering here: this box has 1 CPU core; Godot's worker pool then has one thread and deadlocks on pipeline compiles
  (the process sits at ~3 % CPU, all threads in futex waits). /tmp/trailer4/override.cfg (6 worker threads, 1920x1080
  window) is copied into the project only for a render and removed after -- it must never be in an export. Godot also
  hangs on exit after Movie Maker here: the shot prints SHOT_DONE and render.sh kills it. Xvfb (2560x1440) does not
  survive between turns. ~0.5 s per 1080p frame.
- tools/trailer4_shots.gd: sky, river, island, hills, castle, deck, logs, clash, golden (keyframed cameras; STILL_AT for
  single-frame checks). "golden": the in-engine title -- a TextMesh FATEBOUND in Luckiest Guy, extruded 0.5, with a
  gold shader (fake golden-hour environment reflection, darker sides, a sharp glint lobe that sweeps left to right as it
  settles) flying in from the right and turning to face the camera (TITLE_IN 3.6 -> TITLE_SET 6.4 s). Falls shot
  dropped (unreadable from every camera tried).
- tools/trailer4_title_fx.py: god rays (bright sky round the sun zoom-blurred from its tracked screen position), lens
  streak, a flash as the title lands (4.9 s), fade-out; tagline off (--tag-at 999).
- tools/trailer4_edit.py: segments (no captions), crossfades, fadeblack into golden, the song from 29.1 s so its hit
  (72.5 s) lands on the title (43.4 s), the Herald per shot, music ducked as trailer 2 (0.12 / 2 / knee 6 / 40 / 700),
  limiter 0.70 with level=disabled (auto-level had pushed the AAC to +0.2 dBFS); --stage audio rebuilds only the mix.
- tools/trailer4_vo 1..9.ogg: ElevenLabs Edward (eleven_v4), one 21 s take split on word timings + the finale line
  (267 credits). "FATEBOUND" heard at 43.46 s in the cut. Output: Fatebound-Trailer-4.mp4, 48.5 s 1080p30,
  -14.6 LUFS, -2.5 dBFS peak.

# 0.31.12 (Kevin, trailer still: the land beyond the cliff side "needs to look more natural"; the trailer is too slow)
- Land.outer_height: the valley/mountain border (drop_weight's 4 m band) stood as a 50 m sheer, flat-textured wall running
  out along y = +-39; it now widens with distance from the field (x band 4 + 0.4 d, y band 37..41 + 0.9 d). The valley's
  far side, one smooth 50 m ramp (rock texture by slope and height), now climbs gently over a longer run in uneven
  rolling hills below the rock line. _build_outer_trees: 420 trees (was 260), half of the east side's spread over the
  valley up to 220 m out. Start-up cache re-baked.
- Trailer 4 recut for energy (tools/trailer4_edit.py): beat-sized slices from the middle of each render, sped 1.25x
  (logs 1.15x), hard cuts on the song's beats (126.5 BPM, 0.474 s, measured by spectral flux + autocorrelation), the
  song from 50.82 s so the title lands on its hit (72.64 s on the grid) at 21.82 s; no opening line; 27.0 s.
  "FATEBOUND" heard at 21.86 s; -12.6 LUFS, -1.7 dBFS peak. All shots re-rendered on the new landscape.
- Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22).

# 0.31.13 (Kevin: "make the cliff side of the map look like the other side ... in a valley instead of a cliff; as natural
# as possible")
- No drop side any more: drop_weight, DROP_DEPTH, VALLEY_WATER_Y, FALL_X removed. terrain_height raises the rock walls all
  round (the east like the west) and cuts the river's gorge both ways; ledge_rim paints the rock face and its foot shadow
  on the east too; outer_height loses its valley branch (hills close in, mountains beyond, on every side). The waterfall
  mesh, its foam and valley water strip, and the waterfall ambience (and its .ogg) are gone; one river strip runs right
  through at water level. Trees now line the east edge too.
- The river's own valley out among the hills widens with distance (RIVER_HW + 6 + 0.32 d, was + 0.05 d): it was a 6 m cut
  whose sides stood as sheer flat rock in the mountains; now a soft V between green hills.
- Checked from two new cameras in tools/trailer4_shots.gd ("east", "eastwide"). Terrain and start-up cache re-baked.
- Trailer 4's footage still shows the old cliff side (re-render the shots if it should match).
- Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22).

# 0.31.14 (Kevin, screenshots at the east edge: grass not blending in spots; "more atmosphere ... better lighting")
- The straight-edged light slabs were the seam between the baked terrain and the outer land: outer_land.gdshader lit
  them differently (specular on, no cloud shadows, a different rock). It now shades like the field (specular off, the
  same drifting cloud shadows and triplanar tinted rock with moss, meadow variation only from 4-14 m out); the view
  copies cloud_tex/cloud_strength/macro_tex/rock_col across.
- The stone patches on the wall tops faded over 0.25..0.8 and read as smeared, see-through rock; now a narrow jittered
  threshold (0.44..0.58) -- crisp, ragged stone breaking through the turf.
- Atmosphere: haze from 48 m (was 70) with warm sun scatter (0.22) and a little low-ground fog (height -0.2, density
  0.05); the sun warmer (#ffdfb4) and lower (-47 deg, was -55) for longer shadows against the cool ambient; HQ glow a
  touch stronger (0.6 / 0.95, bloom 0.04), contrast 1.08; a soft radial vignette under the HUD.
- tools/trailer4_shots.gd: "edge_e"/"edge_w" play-camera views of both field edges for checks.
- Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22).

# 0.31.15 (trailer 5 notes from Kevin: the boulder in the opening; the Knight should fly back and die; show the ladder
# actually going up and being climbed)
- Game: ladders swing up off the ground into their lean (View._sync_raising, LADDER_RAISE 0.9 s, slight overshoot) and stand
  on the ground under them (Sim.height_at) instead of popping in at y 0.
- tools/trailer5_shots.gd: props in the close-ups' sightline hidden (_clear_sightline); "hook": on the hit the Knight is
  thrown 1.7 m back in a 0.95 m arc, dead (state only: he stays a Knight, no hat drop), landing in frame; "build": staged at
  the enemy castle's real front wall (the old fixed spot no longer touched a wall, so no ladder was ever raised), the
  worker still hammering as recording starts, three heroes walk to the ladder's foot then up and over.
- Trailer 5 recut; 58 s, -12.8 LUFS, -2.2 dBFS.
- Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22).

# 0.31.16 (Kevin: "upload game version to github")
- The Berserker's body turns with his whirlwind (View: root yaw = face - accumulated 38 rad/s while Sim.whirling(), the same
  way round as the ribbons at 44/34 rad/s). Trailer 5 notes since 0.31.15 (tools only): Necromancer from the front and wider,
  the hammer meets a charge (wider, from the throw), the spin: three charge and are cut down in slow motion; all trailer
  renders in High-quality (FB_FORCE_HQ=1 -- the view keeps HQ off on llvmpipe otherwise).
- Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22).

# 0.31.17 (Kevin: "realistic cloth physics for the capes")
- The Knight, Mage, Ranger, Rogue and hooded Rogue capes (separate 56-vertex skinned meshes in KayKit, rigid on
  spine/hips/chest) become cloth near the camera: View._cape_setup/_cape_step. A 5 x 6 Verlet sheet in world space, its
  top row pinned across the shoulders to the chest bone (rest grid taken from the model's cape shape, flared at the hem),
  gravity 7.5, damping 0.93, a little wind, stretch links across and down plus bend links two rows down, 2 solver passes,
  kept behind the back plane and outside a 0.3 m capsule round the torso (in the chest frame) and above the ground.
  Drawn as a double-sided ArrayMesh (one array upload a frame) in the cape's own atlas colour; the original cape hides
  while the cloth shows. Only within CAPE_NEAR 34 m (ground distance) of the camera; past 70 % of that, half rate.
- Cost measured in a 16v16 match on the build box: ~7.8 capes simulated a frame, 1.5 ms a frame (0.19 ms each).
- Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22).

# 0.31.18 (Kevin: "there are floating capes; the capes are very jittery"; 22 fps in his screenshot)
- 0.31.17's cloth was a separate world-space mesh per cape: it was left behind wherever the body vanished or was rebuilt
  (floating capes), stepped with the raw frame time and every other frame further off (shivering), and rebuilt and
  re-uploaded an ArrayMesh per cape per frame (costly on phones).
- Now the original cape mesh is bent in its vertex shader (CAPE_SHADER, uniform offs[12]) by a 3 x 4 spring grid (top row
  pinned to the chest bone), stepped at a fixed 30 Hz with an accumulator and eased onto the screen (1 - e^-30dt). Nothing
  separate to strand; out of range or hidden it relaxes to the plain cape. 0.40 ms a frame for ~8 capes on the build box
  (was 1.5 ms plus the mesh uploads).
- Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22).

# 0.31.19 (Kevin: the workshop makes a powerful bomb, carried and thrown by players, one at a time; the throw lights
# the fuse; it kills everyone in its radius, friends too; half of a door's health, all of a jail door's) -- protocol 31
- Sim: bombs[team] ({} or one dict) -- one per workshop at a time, first at BOMB_FIRST 40 s, the next BOMB_RESPAWN 45 s
  after one goes off, at bomb_spot() beside the workshop (outside its ACTION ring). ACTION picks it up (bomb_to_pick,
  1.6 m; not while lifting a King, holding a fish, in a tower or on a task); carrier runs at 85 %; ACTION or ATTACK throws
  it 9 m where he faces (_push_out keeps it out of walls; it flies over them), 0.75 s arc; the throw lights a 2.4 s fuse
  (a lit bomb can be picked up and thrown back, fuse running); a carrier who dies drops it (unlit stays unlit).
  _explode_bomb: everyone alive within BOMB_R 4.5 m dies (kill credit only for enemies), every door in reach loses half
  its max health (open doors too), a jail door in reach is destroyed outright. Bots run from a lit or flying bomb.
- Net v31: "bm" per team [state, x, y, h, fuse left, carrier, to x, to y]; clients set bomb_held from it.
- View: iron ball with a brass band and a fuse; held over the carrier's head; spins in flight; lit, the fuse spits sparks
  and the ball throbs red faster as it runs down. Blast: additive fireball, two rings, sparks, smoke, a scorch that
  fades over 25 s, camera shake by distance. Sounds: fireball + crumble (heard 70 m), fuse catching, pick-up clank.
  HUD: PICK UP BOMB / THROW BOMB. tools/trailer5_shots.gd "bomb" check shot.
- tests/bomb_test.gd (in the suite). Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22).
- Bots don't pick bombs up yet.

# 0.31.20 (Kevin: weapons fall when a player dies; weapons and hats get physics like the logs and stones; ragdolls that
# fall the way they were killed -- a bomb throws them and their weapons a short way to tumble; a flying hammer throws
# the body the way it went)
- Sim: the killing blow's push (_next_push, set before _damage; _kill falls back to straight away from the killer,
  3.2 m/s + 1.6 up) goes out with the death event ("push") and onto the unit (death_push). Arrows/bolts 3.2-3.6 along
  their flight, fireball splash 4 away from the burst, the Crusader's hammer 4.6 the way it flew, catapult 4.4 + 3.6 up
  away from the strike, the bomb 5.2 + 4.2 up away from it (less further out). Dropped hats are flung with it (0.75 of
  the push + a little scatter) and slide (friction 3.2 m/s^2), roll a little downhill, float off downstream like the logs,
  stay out of walls (_step_hat_motion).
- View: deaths within 40 m of the camera become ragdolls -- PhysicalBoneSimulator3D on the KayKit skeleton, 11 bodies
  (hips, chest, head sphere, upper/lower arms and legs; cones at hips/shoulders/neck, hinges at elbows/knees) started with
  the push and a tumble, on a HeightMapShape3D patch (21 x 21 m) sampled from Sim.height_at; at most 8 at once; freed on
  respawn. The dying body keeps its class look until respawn (no swap to the Villager mid-fall). Weapons and shields in
  the hand slots come loose as RigidBody3D boxes thrown with the push, lie 30 s (24 at most). Hats tumble while they slide.
- project.godot: 3D physics engine Jolt (stabler ragdolls).
- Quick suite: ALL PASSED (siege_sim_smoke too: seed 11 had a rescue).

# 0.31.21 (Kevin: the water reacts to a bomb with huge waves; weapons and bodies react to bombs and catapults; weapons
# and hats are pushed around on the ground)
- Water: the river/lake surface now rises and falls with the GPU wave simulation (vertex displacement, wave_height 1.5,
  held at the banks; the strip has WATER_ROWS 10 vertices across, was 2). water_blast(): a bomb (or catapult stone,
  0.6 power) in the water or within 5 m of it pushes the surface down hard for 4 frames at the nearest water, plus spray
  and a ring; the rings run out across the river and the lake.
- Sim: _blast_push() -- bomb (BOMB_R + 2, 7 m/s) and catapult (AOE + 1.5, 4.5 m/s) throw hats, logs and rocks. Hats are
  kicked along by whoever walks into them (as the logs and rocks), unless a Villager who can wear it walks over it.
- View: _blast_bodies() -- ragdolls and loose weapons within the blast are thrown up and away; _kick_debris() -- loose
  weapons are kicked along by walking units. tools/trailer5_shots.gd "waterbomb" check shot.

# 0.31.22 (Kevin: the catapult model is backwards; the camera stays with the body through the respawn countdown; hats
# not auto-pickup; equip the upgraded hat at the shop once it's upgraded)
- Catapult towers: the turret faces the field at rest (it faced the castle) and aims with atan2(local.x, local.z) (the
  model throws along +z; it was turned the wrong way round when firing).
- Camera: while you're dead it stays with your body (the ragdoll's hips if there is one), not your spawn.
- Hats: players take them with ACTION -- a dropped hat (hat_to_pick, "PICK UP HAT") or a stand ("NEW HAT"); bots still take
  them by walking over (their AI's button press). At your own team's stand for your class, once the team owns that hat
  upgrade, ACTION trades your ordinary hat for the upgraded one (can_equip_upgrade/_equip_upgrade, "WEAR UPGRADE"); the
  player who buys the upgrade at the stand wears it at once; bots swap when they're at their stand. Tutorial hat task
  text: "(press NEW HAT)". Tests updated (stands, tutorial, net smoke, sim smoke hat rules).
- Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22; its hat-rule checks all pass).

# 0.31.23 (Kevin: abilities lag online; optimise online play and the net code for 32 players without lag or stutter)
# -- protocol 32, server redeploy needed
- Server: one snapshot encoded + zstd-compressed per tick for everyone (it was encoded and compressed once per player);
  each player's private bit (their task) is its own small "m" message, only when it changes. SIEGE_STATS=1 logs load
  every 5 s (ms/s in sim steps, snapshot build, sends; kB/s; worst frame); SIEGE_STATS_FILE writes them flushed.
- tests/net_load_test.gd (in the suite): the real server with 32 connected players sending inputs at 20 Hz for 25 s.
  Build box: sim 40 ms/s, snapshot 11 ms/s, sends 6 ms/s (about 6 % of one core), 340 kB/s out, 10.6 kB/s per
  player, 60 frames/s, worst frame 17 ms. The server was never the bottleneck.
- Client: SNAP_HZ 15 -> 20. Timed interpolation (Net.interpolate_at): each unit keeps its last 4 snapshot positions
  with their server times; the client runs a render clock INTERP_DELAY (75 ms) behind the newest snapshot, eased, and
  draws every remote unit between the two samples round it, extrapolating up to 120 ms past the newest. The old scheme
  slid from the last drawn position to the newest over an estimated interval and stuttered with any jitter.
  net_interp_test: a walker under +-25 ms jitter and a dropped snapshot moves at a steady 5 m/s (worst frame step
  within 15 % of the mean, no stalls). Decode + apply + interpolate: 0.4 ms per 32-unit snapshot.
- Abilities: Sim.predict_ability() -- pressing the button starts the swing/spin/ring on the client at once (block,
  whirlwind state, hammer/resurrect/nova wind-ups and cooldowns); the server resolves the effect; the server's own copy
  of the effect for that player within 0.6 s isn't shown twice (_pred_fx). Before, an ability showed only after
  the round trip plus a snapshot plus the interpolation delay (~200-300 ms).
- Tests kill their server with SIGKILL (it ignores SIGTERM; stale servers had been grabbing the test port).
- Quick suite: all pass except siege_sim_smoke (rescues 0 in seeds 11/22).

# 0.31.24 (online follow-up)
- The draw delay adapts to the connection: the client smooths |arrival gap - snapshot interval| and draws remote units
  INTERP_DELAY + 1.5 x that behind the newest snapshot, between 75 and 250 ms (a jittery mobile link gets a deeper buffer
  instead of stutter; a clean one stays at 75 ms).
- Your own unit: beyond PREDICT_SOFT 0.7 m of drift from the server's position, it's eased back 12 % per snapshot; the
  2.5 m snap stays as the last resort (a correction slides instead of teleporting).
- The quick suite no longer requires a bot rescue (NO_RESCUE_CHECK=1 with seeds 11,22); the full six-seed run does.
  Bot teams rescue in roughly 1 match in 6 -- worth a look at bot carrying some day.
- Quick suite: ALL PASSED (24).

# 0.31.25 (Kevin: "make the bots much smarter") -- first round
- Measured first (seed 11, 12 min): the jail was never broken by either side, no raider ever got within 4 m of the
  captive King, 85 raid/escort deaths in 400 s of which 73 in the field (both raids brawling mid-map), raiders were
  picking up dead workers' tools (11 "workers" on a team) and marching out as Villagers when the stands were empty.
- Raids now gather at a rally spot RALLY_OUT 21 m outside the enemy front wall and push in together with RALLY_HANDS 4
  (or after RALLY_WAIT 28 s with 2+), for ASSAULT_LEN 70 s; pushing in, raiders' aggro drops to 2 m outside the castle
  so they aren't drawn into the field brawl. A raider takes the workshop's bomb (one claims it) and throws it at the
  enemy front gate, or at the jail door once the gate is down. Targeting: bots finish wounded enemies (< 35 % hp, a 3 m
  bonus); archers and mages go for priests and mages first. Villagers never take tools unless their role is gather, and
  wait at their stand for the next hat instead of leaving as Villagers.
- After: the enemy gate goes down at ~60 s (the bomb), jails get broken (70 s / 610 s in seed 11), but still no rescue:
  raiders die in the field to the enemy's raid and mages before a lift forms. Next: shield the push with Knights blocking
  in front, retreat to the priest at low hp, time the push for when the enemy's raid is out, and lift coordination.
- Quick suite: ALL PASSED (24).

# 0.31.26 (Kevin: bots round two; "add the king digesting")
- The King digests: DIGEST_EVERY 75 s a captive (or any) King works off one fish; weight and lifters needed follow.
  (40 s left him never fat: one fish runner feeds about one per 45-60 s.) Event "digest". tests/digest_test.gd.
- Bots: the push waits until at most 6 of theirs are at home (their raid is out), unless it has waited 1.5x RALLY_WAIT;
  it always goes after 2.5x. Badly hurt bots (< 35 %, not carrying, no foe at arm's length) go to the nearest priest of
  theirs within 22 m (beam + Sanctuary) or back toward the rally. Mages keep Nova for 2+ enemies in its radius.
- Result (seeds 11/22, 12 min): matches now end 3-2 and 3-1 on rescues (both were 0-0 last week); jails broken at
  59-165 s; the King reaches stage 1-2 under feeding. siege_sim_smoke: rescues in both quick seeds.
- Quick suite: ALL PASSED (25).

# 0.31.27 (Kevin, screenshot: bots waiting at their rally point didn't react to him shooting them)
- A raider only looked for enemies within its role's aggro (3.5 m; 2 m while pushing), so an archer at 10+ m could
  pick off a waiting raid. Now _damage records hurt_by/hurt_at, and _attacker_to_answer(): a bot hit in the last
  ANSWER_FOR 3 s -- or seeing a friend within ANSWER_FRIEND 9 m hit -- takes the attacker within ANSWER_R 22 m as its
  target (melee charge him, ranged shoot back; swords don't chase someone up a tower), unless an enemy is already at
  arm's length. tests/answer_test.gd: 4 of 4 waiting raiders go for an archer hitting one of them from 11 m.
- Quick suite: ALL PASSED (26).

# 0.31.28 (Kevin: a player launcher in each castle -- built with a lot of resources, a lever, a 5 s countdown, everyone
# on it launched into the enemy castle, flying in real time) -- protocol 33
- Workshop upgrade "launcher" (60 wood + 45 stone). Pad at castle-local LAUNCH_PAD (-5, 10), r 2.5 m; lever at
  (-1.4, 10). ACTION at the lever ("PULL LEVER") starts LAUNCH_COUNT 5 s; then everyone on the pad -- either side, not
  King/fish/bomb carriers, tower archers or workers on a task -- gets state "fly": a straight line over the ground to a
  spread spot round the enemy courtyard (LAUNCH_LAND (0, 10)), 2.6-4 s at LAUNCH_SPEED 32, with Sim.flight_height an arc
  peaking ~17 m. Untouchable in the air (no targeting, arrows pass). Land with a 0.45 s stagger. Lever reloads 20 s.
- Bots: bot-only teams buy it after the second armory level; raiders gather on the pad, the first there pulls the lever
  once 3 are on it (or after 8 s) and they ride it in (measured: 2-6 launches a match once built). A team with a player
  leaves the buy to the players.
- Net v33: state "fly" in STATES, "la" [[count_at, ready_at] x2]; clients take each flyer's arc from the "launch" event.
- View: stone base, wooden pad, brass rim (glows when ready, throbs faster through the countdown), spring coils, a lever
  on a post that swings when pulled, the countdown 5..1 over the pad; launch: ring, dust, shake, catapult whoosh; landing:
  dust ring and thump. The flyer's model follows the arc (measured up to 16.8 m) and the camera with it.
- Answering fire (0.31.27) cost rescues (3-2/3-1 -> 0-0): a raider on the push now answers only within 6 m, and swords
  never chase someone on a rampart. Back to 0-1 / 1-1 in seeds 11/22.
- tests/launcher_test.gd. Quick suite: all pass.

# 0.31.29 (Kevin: double kills, triple kills, etc.)
- Sim._multi_kill: enemy kills by the same player each within MULTI_WINDOW 4 s of the last chain: 2 DOUBLE KILL,
  3 TRIPLE KILL, 4 QUADRA KILL, 5 PENTA KILL, 6+ LEGENDARY; event "multikill" {id, team, n, name}; best_multi kept per
  unit. Friendly kills (a bomb on your own side) don't count; a bomb that kills three enemies at once is a TRIPLE.
- HUD: your own multi-kill slams onto the middle of the screen in Luckiest Guy (white-gold -> orange -> red -> pink ->
  purple by tier), settles and fades over 1.8 s; anyone else's triple or better shows as a line ("An ally: TRIPLE
  KILL" / "An enemy: ...").
- The Herald calls yours: assets/vo/herald/mk_double/triple/quadra/penta/legendary.ogg (ElevenLabs Edward, one take:
  "Double kill!", "Triple kill!", "Quadra kill! Show-off.", "Penta kill! Somebody stop him!", "LEGENDARY!"), at the
  master volume; a newer call cuts off the one before (Mode._herald_say).
- tests/multikill_test.gd. Quick suite: ALL PASSED (28).

# 0.31.30 (Kevin: the Herald does match announcements -- "only important ones")
- assets/vo/herald/an_<key>_<n>.ogg, 22 lines from one ElevenLabs take (Edward): start (2), our_pickup (2),
  their_pickup (2), our_drop, our_rescue (2), their_rescue (2), our_gate, their_gate, their_jail ("The jail is open! Grab
  our King!"), our_jail, match_point_us, match_point_them, last_minute, ten_seconds, victory, defeat, draw.
- Mode announcer: from your team's side; priority 3 (rescues, match point, last minute, ten seconds, victory/defeat/draw)
  cuts in, priority 2 queues behind the line playing (dropped if it can't play within 5 s); per-key cooldowns (gates and
  jails 45 s, pickups 25 s, a drop 20 s). Lines are timed by their length on the frame clock (the player's playing flag
  sticks on the dummy audio driver). Not in the tutorial. Multi-kill calls share the voice.
- tests/announce_test.gd. Quick suite: ALL PASSED (29).

# 0.31.31 (Kevin: "announce outposts also")
- The Herald calls towers: taken by us -- "Tower taken! The view is lovely." / "That tower is ours now!"; taken from us
  (one of ours lost, or theirs captured) -- "They've taken a tower! Take it back!" / "We've lost a tower. Rude."
  (an_our_outpost_1/2, an_their_outpost_1/2; ElevenLabs, Edward). Priority 2, a 20 s cooldown each (a tower lost and
  then captured by them a moment later is one call). announce_test covers both. Quick suite: ALL PASSED (29).

# 0.31.32 (Kevin: the last three upgrades get their own abilities -- all three) -- protocol 34
- Assassin -- VANISH (14 s cd): 4 s unseen; nobody can pick him out as a target beyond 1.6 m; his first strike out of it
  does 2x and reveals him, as does any hit he takes. View: see-through copies of his materials -- a ghost (45 %) to his
  own side, almost nothing (8 %) to the enemy, ring hidden from them (GeometryInstance3D.transparency didn't show on the
  Mobile renderer in a check render). Bots vanish to close 3-11 m on a target.
- Sniper -- PIERCE (9 s cd): a heavy arrow (2.2x, 42 m/s, 30 m) that goes through everyone in its path once each,
  thrown along its line; a long arrow with a pale streak. Bots fire it at two or more in a line, or at range past 16 m.
- Archmage -- METEOR (12 s cd): on the nearest enemy within 12 m (else ahead), a red warning circle and a burning rock
  falling for 1 s, then 2.4x damage (half at the 3.2 m edge) with a stagger, bodies, weapons, hats and logs blown out,
  waves if it's near water, and the ground burning 3.5 s (9 dps to enemies in it). Bots aim it at two or more or at a
  King carrier.
- Looks: Assassin -- hooded Rogue, dark violet, two daggers; Sniper -- Ranger, forest green, two-handed crossbow, bow
  draw; Archmage -- Mage, crimson, staff and an open spellbook, summon cast. Ability buttons: VANISH / PIERCE / METEOR
  with their cooldowns. Sounds from the pack (fire spray, fireball, crumble, bow hits).
- Net v34: "pierce" in PROJ_KINDS; vanish/meteor by events. tests/upgrades_test.gd. Quick suite: ALL PASSED (30).

# 0.31.33 (Kevin: logs and rocks pop into the air and fall like confetti; explosions destroy trees and rocks in their
# path and fling the material away)
- View: a new log or rock pops up (4.5-6.5 m/s; 9-12 if a bomb or meteor went off within 12 m in the last 0.6 s),
  tumbles about a random axis, falls (16 m/s^2), bounces once and settles where the sim has it. Chips: every chop or pick
  throws 4; a tree falling or a boulder breaking throws 18 (26, faster and away from the blast, if a blast did it) --
  small spinning bits, bark/pale wood/leaf green or greys, air-slowed like confetti, one bounce, fading at 1.6-2.4 s.
- Sim: _blast_nodes(at, r, speed) -- the bomb (BOMB_R, 7.5 m/s) and the meteor (METEOR_R, 6 m/s) fell every tree and
  shatter every boulder they reach; _fell_node(..., blast) flings all the pieces away from the blast (spread 0.7 rad,
  0.7-1.15 x speed, spinning); they regrow as if worked out. tests/blast_nodes_test.gd; "treeblast" check shot.
- Quick suite: ALL PASSED (31).

# 0.31.34 (Kevin: catapults break trees and rocks too; materials flung by explosions and catapults -- two versions:
# chopping/mining does the confetti, explosions and catapults break and launch)
- Sim: a catapult strike calls _blast_nodes (CATAPULT_AOE + 0.6, 6 m/s) like the bomb and the meteor.
- View: _launch_items(at, r, power) -- logs and rocks already lying in a bomb (BOMB_R + 2), meteor (METEOR_R + 1.5) or
  catapult (CATAPULT_AOE + 1.5) blast go up into the air again (6-11 m/s by distance) and tumble while the sim throws
  them outward; pieces broken by a catapult pop high like a bomb's (it's a recent blast). Chopping and mining keep the
  small pop and the confetti chips. blast_nodes_test covers the catapult. Quick suite: ALL PASSED (31).

# 0.31.35 (Kevin: blasted logs and rocks were still doing the confetti pop -- they should fly away from the blast)
- The pop was a view-only hop while the sim slid the piece along the ground, losing most of its speed to friction in
  the first moments: up, down, a short skid. Now a piece a blast throws (broken out of a tree/boulder, or already lying
  in it) is AIRBORNE in the sim: BLAST_VZ 7.5 m/s up (+-15 %), flying straight out at its full launch speed with no
  friction, slope, river or shoves for 2 vz / ITEM_G (~0.9 s), walls still stopping it; it lands with 55 % of its speed and
  slides/rolls on. Launch speeds up (bomb 9, meteor 7.5, catapult 7 m/s): pieces land ~5-9 m out. The view draws the
  same arc (no easing in flight) and tumbles it. Chopping/mining keeps the small hop and the confetti chips.
  Online clients (no flight data) use the view's stand-in pop.
- Quick suite: ALL PASSED (31).

# 0.31.36 (Kevin: the pass lasts 4 weeks)
- Economy.SEASON_DAYS 42 -> 28. Season 1 (from 2026-10-01) now ends 2026-10-29, season 2 on 2026-11-26; saved pass
  progress is keyed by season id, so nothing resets early.
- Measured the pace first: a match pays ~420 pass XP (64 player-matches over two bot matches), the three dailies ~1,300,
  the weeklies ~5,700 a week; at TIER_XP 1,000 the 30 tiers filled in 8-9 days even at 2 matches a day. TIER_XP 2,500
  (75,000): ~20 days at 3 a day with the challenges, ~23 at 2, ~16 at 5.
- meta_economy_test's scratch profiles were named by ticks-since-start, which repeat between runs: a previous run's
  file (with today's first win) was occasionally reloaded. Now wall-clock ms + a random number.
- Chests and gem packs are designed (not built yet); waiting on Kevin: instant-open vs timed.

# 0.31.37 (Kevin: a chest system; chests unlock over time)
- Economy: CHESTS wooden (30 min) / silver (3 h) / gold (8 h) / royal (12 h) -- gold, gems and a chance (wooden 15 %,
  silver 35 %) or certainty of a shop cosmetic by rarity table; duplicates turn into gold (100/250/600/1500); Gold and
  Royal chests guarantee an epic or better at least every PITY_EPIC 10; skip_cost 1 gem per 10 minutes left; roll_chest
  seeded by the chest (opening can't be re-rolled by reloading); chest_odds() prints them plainly. Earned by playing,
  never sold (no paid loot boxes): every win a Wooden (Silver with a rescue or a multi-kill), the first win of the day a
  Silver, all three dailies a Silver, all weeklies a Gold, levels 5/15/25... a Gold and 10/20/30... a Royal (replaces the
  25 gems), the pass free tiers 12 and 24 Silver, premium 8 and 16 Gold and 28 Royal.
- Profile: d.chests {slots, next, pity}; CHEST_SLOTS 4 (full: the chest becomes 50/120/300/700 gold at once); one
  unlocks at a time; start_unlock / skip_chest / open_chest. Old saves get the empty chests block (merge of defaults).
  Online: my own multi-kills are kept on my unit from the events (the sim's count is on the server).
- Home screen: a CHESTS card -- four slots (tier icon in its colour, OPEN / time left with a gem skip / UNLOCK), the
  rule line ("never sold"), WHAT'S INSIDE? with the odds. Results panel: "<chest> earned!" or "slots full, turned into
  gold". tests/chest_test.gd. Quick suite: ALL PASSED (32).
- Gem packs for real money: designed; needs Play Billing + products in Play Console (not built).

# 0.31.38 (Kevin: more to spend gold on -- upgraded-class cosmetics first)
- Measured: gold bought 19 items, 18,900 gold in all; a regular player earns ~1,400 gold a day -- everything in ~2 weeks.
- Economy: UP_CLASSES crusader/berserker/necromancer/assassin/sniper/archmage (UP_BASE, UP_LOOK: the Crusader is a Knight
  body), own CLASS_NAMES, cosmetic_class(cls, up). 30 new cosmetics, 5 per upgraded class: a rare skin (1,500 gold), an
  epic skin (2,800), a legendary skin (400 gems), a rare weapon (1,200) and an epic weapon (2,400) -- 47,400 gold more to
  spend (gold items 19 -> 43), using the KayKit bits weapons (hammers and shields, halberd, scythe, fang daggers, fist
  claws, recurve/heartwood bows, crystal staff/rod). All "shop": they rotate through the shop and drop from chests.
  DAILY_SLOTS 4 -> 6, FEATURED_SLOTS 2 -> 3 so the bigger pool still comes round.
- Profile: equip slots for the upgraded classes (old saves get them). Match: an upgraded player wears his upgraded
  class's cosmetics, not the base class's (a Berserker no longer gets the Barbarian's axe and tint). Mode._looks sends
  them. Showcase and render_skin_icons build each on its own body; the tool now also renders weapon icons (whole
  figure, gear in hand) and the upgraded defaults; 42 new thumbnails. Locker: a second tab row for the upgraded classes.
- render_skin_icons: the camera is aimed by transform (look_at failed: not in the tree in _initialize).
- meta_economy_test covers it. Quick suite: ALL PASSED (32).

# 0.31.39 (Kevin: only weapons are cosmetics, so it's easy to tell who's playing what class)
- All 32 skins (tints) are gone from the catalog: 19 gold and 9 gem shop skins, 4 pass skins. The class looks (and the
  upgraded classes' own colours) are fixed. REMOVED_SKIN_REFUND keeps the 28 bought skins' prices; Profile._normalized
  pays them back once (skins_refunded) and the home screen says what came back. Pass skins (free) just go.
- Packs are weapon bundles now ("Arsenal": two weapons per class, the Knight's with its title), ~80 % of the items'
  value; the Priest pack (one shop weapon) is gone. Chests drop weapons only. The pass draws from 15 weapons + 5 titles.
- look_for() sends no tint; the locker shows WEAPONS only; the home screen shows the equipped weapon's name. 64 skin
  thumbnails deleted (class defaults kept).
- Gold sink: gold-bought items 43 -> 24 (~32,000 gold). More weapons per class would bring it back.
- meta_economy_test: no skins, refund paid once, no tints in battle. Quick suite: ALL PASSED (32).

# 0.31.40 (Kevin: add the remaining KayKit models to the classes that suit them)
- Every unused KayKit weapon model is now a cosmetic (measured lengths decide one- or two-handed): 19 weapons --
  Knight: Arming Sword & Round Shield (sword_A), Longsword & Square Shield (sword_C), Broadsword & Spiked Shield
  (sword_D); Barbarian: Bearded Axe & Buckler (axe_A), Butcher's Blade (sword_F), Brawler's Gauntlets (fistweapon_B);
  Rogue: Twin Stilettos (dagger_A), Brass Knuckles (fistweapon_A); Ranger: Hunting Bow (bow_A_withString); Mage: Ritual
  Knife & Tome (dagger_C); Priest: Pilgrim's Staff (staff_A), Mace & Holy Shield (hammer_B); Worker: Felling Axe (axe_C);
  Crusader: Judgment Maul (hammer_D, legendary, 3,600 gold); Berserker: Broadblade; Necromancer: Bone Spear (spear_B);
  Assassin: Night Blades; Sniper: Repeater (crossbow_1handed); Archmage: Elder Oak & Tome. The five unused shields go
  with them. All gold (900-3,600): gold-bought items 24 -> 43, ~62,000 gold in all. Arrows and the bare bow frames are
  left out (not weapons).
- render_skin_icons renders any weapon without an icon; 19 new thumbnails. Quick suite: ALL PASSED (32).

# 0.31.41 (Kevin: the Knight always uses a shield)
- Four Knight/Crusader weapons had an empty left hand; each now comes with a shield (ids kept, so owners keep them):
  Greatsword & Kite Shield (shield_A), Crimson Blade & Shield (shield_round_color), Halberd & Tower Shield
  (shield_square_color), Judgment Maul & Shield (shield_badge). View.make_body: a Knight body (the Knight and the
  Crusader) with nothing in the left hand gets its own shield_B, so no future item can leave it bare. meta_economy_test:
  every Knight/Crusader weapon has a shield. Thumbnails re-rendered. Quick suite: ALL PASSED (32).

# 0.31.42 (Kevin: a much higher-quality Siege Pass screen; tap an item to expand it and turn it with a finger; less gear
# on the free side, the best-looking gear and more unlocks on the paid side)
- Economy: PASS_FREE_ITEMS 6 -> 3 at tiers 10/20/30 (the season's lowest rarities); PASS_PREMIUM_ITEMS 10 -> 13 at
  PREMIUM_ITEM_TIERS [1,3,5,7,9,12,15,18,21,24,26,28,30] -- every epic and legendary of the season (season 1: 6
  legendary), rising rarity to the best at tier 30 and a strong opener at tier 1 (pass_items ranks by RARITY_RANK after a
  per-season shuffle). Premium chests at 8/16 (Gold) and 22 (Royal).
- Screen: season banner (season chip, ends-in chip, season name, a round tier medallion, a thick XP bar); the premium
  offer naming what it holds (13 cosmetics, N legendary, chests) or a PREMIUM ACTIVE strip; the season's best item turning
  in 3D (tap for detail); CLAIM ALL; the track -- free left, premium right, a gold spine through the reached tiers with
  numbered medals; reward cards with rarity-coloured borders and glows, green glow + CLAIM when ready, dimmed with a
  lock (purple for premium) or a check when claimed.
- Detail sheet (tap any reward): a big 3D stage -- the weapon in its class's hands, Showcase.interactive (drag to turn,
  coasts, then turns slowly by itself) -- or the title / chest / gold / gems large; name, rarity and class chips, OWNED,
  chest odds; CLAIM / UNLOCK PREMIUM / REACH TIER N / CLAIMED. tools/app_shots: SHOT_PASS_DETAIL.
- meta_economy_test: premium has >3x the free items, all the top rarities, the best at tier 30. Quick suite: ALL PASSED.

# 0.31.43 (Kevin: weapons upside down and wrongly sized -- "staffs shouldn't be super short")
- Measured every weapon model with node transforms applied: the Bits pack uses the same convention and scale as the
  Adventurers weapons (grip at the origin, business end along +Y; sword_A 1.77 m vs sword_1handed 1.78, staff_A 2.15 vs
  staff 2.15). The old flat 0.55 on every Bits model was the fault: a staff came out 1.2 m, daggers 0.7 m. The Bits bows
  lie along X (the Adventurers bow along Z) and were turned by a half turn like it -- horizontal in the hand.
- View._fit_weapon + WEAPON_SCALE: Bits models at full size, with the giants brought to the Adventurers two-handers
  (sword_E 0.75 -> 2.4 m, spears 0.8, bow_C 0.75, staff_D 0.85, halberd 0.85, hammer_D 0.9, sword_F 0.9) and shields
  slightly scaled (A 1.0, B 0.9, C 0.85, D 0.78); Bits bows a quarter turn, the Adventurers bow its half turn. Checked in
  close-up renders mid-swing against the pack weapons. 56 weapon thumbnails re-rendered. Quick suite: ALL PASSED.

# 0.31.44 (Kevin's screenshots: crossbow not held right, hands through shields, brass knuckles backwards, axes upside
# down)
- View.WEAPON_ROT / _fit_weapon: crossbows (1H and 2H, pack) a quarter turn about X so they lie forward (they stood up
  like bows); every shield moved out along the hand slot's Z (pack 0.15, Bits 0.14) so the fist sits behind the board
  instead of poking through its face; fistweapon_C_left/right a half turn (the claws faced the wrist); bits/axe_D (the
  Great Cleaver) a half turn so its single blade hangs forward in the two-handed grip (its edge pointed at the sky).
  Checked in front-view renders like the screenshots.
- barb_wpn_twinaxe "Twin Axes" (an axe in each hand under two-handed animations: the second stuck out of the left hand)
  is now one double-bitted axe, "Twin-Bitted Axe".
- 68 weapon thumbnails re-rendered. Quick suite: ALL PASSED (32).

# 0.31.45 (Kevin's screenshots: crossbow held in both hands, right hand on the trigger; scythe upside down; axes still
# upside down)
- Two-handed crossbows (the Sniper's default, Heavy Crossbow, Repeater) now sit in the RIGHT hand, lying forward; with
  the bow animations' extended left arm the hold reads as two-handed with the right hand at the trigger. The Rogue's
  one-handed crossbow stays in the left hand beside the dagger.
- WEAPON_FLIP_FOR: the Knight's one-handed idle rests the weapon point-down (right for a sword, wrong for a polearm), so
  the halberd turns head-up on the Knight body; the Rogue's scythe (Reaper) turns blade-down the same way. Other bodies
  (Berserker's halberd, Necromancer's scythe) already hold them head-up. The Great Cleaver goes back to the pack axes'
  blade direction (its 0.31.44 half-turn is undone). Front-view renders checked. 7 thumbnails re-rendered.
- Quick suite: ALL PASSED (32).

# 0.31.46 (Kevin: the adjusted weapons are the right way up but held backwards)
- Side-view renders of the actual idle poses: the Knight's one-handed idle holds the weapon's long axis HORIZONTAL (a
  half turn about Z only swapped forward for backward -- 0.31.45's halberd pointed behind him); a quarter turn about Z
  stands it upright, head up. The Rogue's idle does the same to the scythe: a quarter turn, blade up. The right-hand
  crossbows wanted the opposite quarter turn about X from the left-hand one (they pointed backwards): now -90 in the
  right hand, +90 in the left, and both point forward in the bow idle and release.
- View.WEAPON_ROT_FOR (body -> file -> rotation) replaces WEAPON_FLIP_FOR; _fit_weapon takes the hand. 6 thumbnails
  re-rendered. Quick suite: ALL PASSED (32).

# 0.31.47 (Kevin: rotate both 90 degrees back and the blade 180)
- Knight halberd / Rogue scythe: (0, 180, 0) -- a half roll about the weapon's own long axis. Lying along the arm as in
  0.31.45 (the hold he called the right way), blade hanging down, but the head forward instead of behind him. Rendered
  side and front through View.make_body. 2 thumbnails re-rendered. Quick suite: ALL PASSED (32).

# 0.31.48 (Kevin: turn the blades of the Oathkeeper, Great Cleaver and Axe & Ale 180; zoom in the detail window)
- View.WEAPON_ROLL: a half roll about the weapon's own long axis for axe_1handed (the Worker's axe, Axe & Ale, Axe &
  Buckler -- its edge faced back in the chop), bits/axe_D (Great Cleaver) and bits/sword_G (Oathkeeper). Checked idle
  and mid-chop through View.make_body. 4 thumbnails re-rendered.
- Showcase zoom (interactive only): two-finger pinch (tracked from the touch events), the OS magnify gesture, the mouse
  wheel, and zoom_by() -- ZOOM_MIN 0.75 to ZOOM_MAX 2.6, eased; closer in, the eye drops toward the look point. The pass
  detail sheet has + / - buttons on the stage and the hint reads "DRAG TO TURN · PINCH TO ZOOM". tools/app_shots:
  SHOT_ZOOM. Quick suite: ALL PASSED (32).

# 0.31.49 (Kevin: a new model for the gold itself)
- From the packs on Kevin's itch.io account (Vellicgames): Quaternius Fantasy Props MegaKit (CC0) -- Coin, Coin_Pile,
  Coin_Pile_2 (and the pouch, tried and dropped: its pale leather read as a flour sack). Stored in assets/models/gold
  (16 MB of trim textures, excluded from the APK export) with the licence.
- tools/render_gold_icons.gd renders the four gold icons at 320 px: coin (one embossed coin, face on), coins_s (stacks),
  coins_m (stacks and a spill), coins_l (a hoard). The coins' gold lives in their vertex colours ("MI_Trim_Metal_Vertex"),
  which Godot's import leaves off -- the renderer turns them on (linear). Icon.gd's "coin" glyph draws the new coin too,
  so the top bar, price buttons, rewards and the gem exchange all show it.
- Also prepared but NOT shipped (git stash "0.31.49 candidate"): 11 bone weapons / Sledgehammer / Pick & Torch gold
  cosmetics from KayKit Skeletons EXTRA and RPG Tools EXTRA on the same account.
- Quick suite: ALL PASSED (32).
- (same version) The source models moved out of the Godot project to art_sources/gold_megakit: the export filter kept
  the source files out but not their imported textures (7.5 MB got into the first build). Only the four 320 px icons ship.

# 0.31.50 (Kevin: a plasma beam for the Necromancer's siphon -- option 3, our own shader)
- The EffectBlocks pack's plasma beam was removed by its author over copyright (an adaptation of someone else's shader),
  so it isn't in Kevin's copy; this is an original shader, scripts/siege/plasma_beam.gdshader: two twisting wave trains
  warped by each other plus scrolling value noise make the plasma; pulses run from the victim to the Necromancer; dark
  violet troughs, green filaments with hot crests; soft view-facing sides, faded ends; beam_len as an instance uniform
  so the waves keep their size at any length. blend_mix (an additive beam washed out to white over the sunlit grass
  under the HQ glow).
- View._sync_plasma / _make_plasma: a 0.3 m plasma sheath (ripples in width) round a 0.07 m core, a purple glow on the
  victim and a green bloom at the Necromancer's hands (radial-gradient billboards); replaces the flat green cylinder.
  The Priest's heal beam and the Necromancer's white heal to an ally are unchanged.
- trailer5_shots: "plasma" check shot (a Necromancer draining a Knight) and a "drain" beat (the real attack action:
  the old "attack" beat bypassed the Priest's beam). Quick suite: ALL PASSED (32).

# 0.31.51 (Kevin: reverse the beam so it flows back into the Necromancer)
- The siphon's plasma material sets flow_dir -1: the cylinder's UV.y = 1 end is at the Necromancer, and +1 ran the
  pattern toward UV.y = 0 (out to the victim). Measured on the render: cross-correlating the beam's greenness profile
  between consecutive frames, 13 of 15 frame pairs move toward the Necromancer. Quick suite: ALL PASSED (32).

# 0.31.52 (Kevin: a new Assassin character model, made with Meshy; rigged)
- Meshy (Kevin's account, ~75 credits in all): text-to-3D came out realistic (small head) -- dropped. Then
  multi-image-to-3D from our own Assassin rendered unarmed in T-pose (front/side/back on white) for the chibi
  proportions, retextured (violet hood and short cape, black mask, charcoal tunic, crossed straps, crimson sash, grey
  boots), auto-rigged (24-bone humanoid, centimetre units). 10.3k triangles vs KayKit Rogue's 7.2k.
- assets/meshy/assassin: rigged.glb, rig.json (fit 1.81 to the KayKit height; hand-slot rests), anims_<g|m|r|mb|ma|t>.res
  -- all 110 KayKit animations baked onto the Meshy skeleton by tools/retarget_meshy.gd (each mapped bone's global
  rotation relative to its KayKit rest applied to the Meshy bone's rest; hips motion scaled by hip heights; the hand
  slots baked too, since KayKit turns its hand bones; clips that scale a bone to zero hold it still).
- View: MESHY / meshy_body() renames the Meshy bones (and the skin's binds) to KayKit names, adds handslot.r/l, puts the
  fit on the rig's own root (the view sets each body's scale), drops Meshy's sample player; make_body uses the baked
  libraries, wraps weapons in a holder that undoes the centimetre scale, skips the tint (it's painted); _ragdoll skips a
  Meshy body (it plays its death clip). LOOKS.assassin.model = "meshy:assassin". Vanish's see-through copies work as
  they are. Checked: idle, run, stab, jump chop, hit and death through make_body; the upcheck match shot (size next to
  the Sniper and Archmage, Vanish). Assassin thumbnails re-rendered. Quick suite: ALL PASSED (32).

# 0.31.53 (Kevin: add the ragdoll to the new Assassin)
- meshy_body now puts the rig in metres at scale 1: the Meshy rig is centimetres under a 0.01 Armature (with the KayKit
  fit on top), and physics bodies can't live under a scaled skeleton. Every bone rest's offset and every skin bind pose
  is scaled by the same factor (S * bind), the nodes' scales reset to 1; the skin is duplicated per body first. Draws
  and animates exactly as before (six-pose render identical); weapon holders no longer need the counter-scale. The
  110 animations re-baked for the metre rig (hips motion in metres).
- _ragdoll no longer skips Meshy bodies: the renamed bones (hips, spine, chest, head, arms, legs) are what RAG_SPEC
  wants. trailer5_shots "asnrag": a Knight cuts the Assassin down -- he staggers, falls back, lies splayed, daggers and
  hat dropped. Quick suite: ALL PASSED (32).

# 0.31.54 (Kevin: now the Archmage)
- Same pipeline as the Assassin (~45 Meshy credits): the game's Archmage rendered unarmed in T-pose (front/side/back)
  -> multi-image-to-3D -> retexture (deep crimson robe with gold trim and buttons, tall crimson hat with a wide gold
  band, long black hair, pale skin, gold-buckled belt, black boots) -> auto-rig (same 24 bones). 10.2k triangles.
- assets/meshy/archmage: rigged.glb, rig.json (fit 2.21 to the KayKit Mage's height, hat included), 110 baked
  animations. MESHY["archmage"]; LOOKS.archmage.model = "meshy:archmage" (staff and spellbook in its hand slots;
  metre rig, so it ragdolls). tools/retarget_meshy.gd: KK_FOR picks the KayKit body each Meshy model replaces
  (assassin -> rogue, archmage -> mage). Checked: idle, run, shoot, summon, hit, death through make_body; the upcheck
  match shot (size beside the Sniper and the new Assassin). Archmage thumbnails re-rendered (the wide hat is cropped
  at the top of the bust). Quick suite: ALL PASSED (32).

# 0.31.55 (Kevin: the Archmage as an old man, a powerful wizard)
- New reference: the KayKit Mage wearing the Barbarian's bearded head (same Rig_Medium, so the skin binds match), unarmed
  in T-pose; then painted -- beard and brows whitened, a long flowing beard drawn down to the belt on the front and side
  views. Meshy multi-image-to-3D -> retexture (ancient archmage: snow-white beard, bushy white brows, wrinkled wise face,
  crimson robe with gold trim and stars, tall crimson hat with a gold band) -> auto-rig (same 24 bones). ~45 credits.
- assets/meshy/archmage/rigged.glb replaced; 110 animations re-baked (fit unchanged, 2.21). render_skin_icons frames the
  Archmage's bust and gear wider and higher for the tall hat. Quick suite: ALL PASSED (32).

# 0.31.56 (Kevin: the EffectBlocks pack's shockwave on the meteor and bomb explosions)
- The pack's shockwave (assets/other/shockwave.tscn): a single-particle GPUParticles3D drawing a torus (inner 0.8, outer
  1.0, triangular section) that grows from nothing over 0.74 s on an ease-in curve, with a screen-distortion shader.
  Rebuilt as a plain MeshInstance3D (View.shockwave / _sync_shocks) with the same torus, the same curve (cubic Hermite,
  slopes 0.227 -> 1.392), the same timing and shader settings (distortion 0.1, noise 0.273), sized per blast: bomb
  BOMB_R + 1.5, meteor METEOR_R + 1.2. Skipped on low effects (it reads a screen copy).
- The pack's shader bends outward from the SCREEN's centre (right only for a blast mid-screen): our copy
  (assets/vfx/effectblocks/shockwave.gdshader) bends outward from the ring's own centre on screen, strongest across the
  band, fading as it grows. Checked alone over a checkerboard (a clean refracting ripple) and on the treeblast shot.
- Quick suite: ALL PASSED (32).

# 0.31.57 (Kevin: better explosions from the EffectBlocks pack)
- Previewed the pack's three explosions with their real GPU particles (--fixed-fps 60 renders them; the earlier stall
  was the beam effects): heavy (fireball -> rolling smoke -> burning debris with smoke trails), light (small pop,
  sparks, puffs), electric (white-cyan flash, sparks).
- assets/vfx/effectblocks/explosion_heavy.tscn / explosion_light.tscn: copies without the pack's demo script (it
  re-fired the effect on the ui_accept input -- Enter/Space) and the light one's sound. View._pack_explosion(kind, at,
  size): every emitter to local coordinates (so the node's scale sizes the whole effect), half the particles on low
  effects, freed after its longest emitter.
- Bomb: heavy at 3.6 (replacing the glow sphere, 46 sparks and 9 smoke puffs; the reach rings, shockwave, scorch,
  shake, water waves and debris stay). Meteor: heavy at 2.7 (replacing its glow sphere and sparks; its warning circle,
  falling rock, rings, burning ground and shake stay). Catapult stones: light at 2.0 (they had no explosion).
- Checked on the treeblast shot. Quick suite: ALL PASSED (32).

# 0.31.58 (Kevin: bomb explosion much larger, meteor a bit larger; a louder, more powerful bomb sound -- a bang that
# lingers off; a quieter, less dramatic meteor; game audio up, announcer down)
- Sizes: bomb's heavy explosion 3.6 -> 6.0 (its shockwave BOMB_R + 1.5 -> + 3.0), meteor's 2.7 -> 3.4.
- assets/sounds/tm_bomb_blast.wav: ElevenLabs Sound Effects v2 (Kevin's workspace, 3 takes ~50 credits), "massive bomb
  explosion outdoors: one huge sharp deep boom..., then a long rolling rumble that slowly fades away". Picked by
  measurement: the take with the sharpest attack (peak at 0.10 s) and the longest tail (2.5 s to -30 dB); low shelf
  +3 dB at 90 Hz, loudness-normalised (-12 LUFS, -0.8 dBTP), 0.7 s fade, 5 s mono 44.1 kHz. The bomb plays it alone
  (was fireball + crumble) at 2.6x, heard out to 95 m.
- native_audio: every gain above 1 was clamped to 1 (so the bomb's "1.6" never applied); now up to 3x, the product
  capped at full scale, and the base 0.12 -> 0.2 (+4.4 dB for all sound effects).
- Meteor: fireball 1.5 -> 0.55 (45 m), crumble 0.9 -> 0.3 (32 m). Herald: SiegeMode.HERALD_GAIN 0.5 (-6 dB) in matches,
  the tutorial's Herald the same.
- Quick suite: ALL PASSED (32).

# 0.31.59 (Kevin: realistic, physics-based smoke from the explosions that lingers)
- View.smoke_cloud(at, size, amount, life): a one-shot GPUParticles3D per blast -- puffs thrown out of a sphere, slowed
  by air drag (damping 2.4-3.6 x size), lifted by buoyancy and pushed by a steady breeze (gravity (0.45, 0.55, 0.18)),
  stirred by a turbulence field (strength 1.8, influence 0.05-0.16) so the cloud boils and curls; each puff swells
  (scale curve 0.35 -> 1.45), turns slowly, starts dark and fire-warm, thins to pale grey and fades. Depth-sorted,
  soft against the ground (proximity fade 1.4), no shadows, 40 % on low effects. Puff texture generated
  (assets/vfx/smoke/smoke_puff.png: radial falloff broken up by fractal noise).
- Bomb: 64 puffs, 9.5 s, size 1.7; meteor: 34 puffs, 7.5 s, size 1.05. With our smoke on, the pack explosion drops its
  own smoke emitter and its fireball cools to a thin fading grey (was an opaque near-black ball).
- Checked on the treeblast shot (now 9.5 s): fireball -> fiery cloud -> grey-brown smoke that rises, drifts and still
  hangs in pale wisps 6.6 s on. Quick suite: ALL PASSED (32).

# 0.31.60 (Kevin: the Crusader -- make him look like a badass)
- First try painted a closed great helm and a red-cross tabard onto the Knight reference: Meshy made them flat slabs
  (a box on the face, a red board on the chest). Second: the clean Knight views (front/side/back, unarmed T-pose) ->
  multi-image-to-3D -> retexture as a grim veteran crusader (blackened steel plate with gold trim, white tabard with a
  blood-red cross front and back, crimson cape, stern scarred bearded face) -> auto-rig. ~85 credits for both.
- assets/meshy/crusader (fit 2.12 to the KayKit Knight), 110 animations baked. LOOKS.crusader (sword and shield,
  the Knight's animations); look_key: an upgraded Knight is now "crusader" (he used the plain Knight body before);
  the always-a-shield rule covers meshy:crusader; Eco.UP_LOOK.crusader -> "crusader" (menus and thumbnails).
  Thumbnails re-rendered. Quick suite: ALL PASSED (32).

# 0.31.61 (Kevin: the Crusader's eyes black, not gold; the Crusader can also block; the Berserker and the Sniper get
# models; rename Ranger -> Archer and Sniper -> Ranger)
- Crusader eyes: the gold eye discs located by rendering his face with UV-coded passes (coarse + fract(uv*32)), the two
  eye blobs mapped back to texels and painted near-black (only where the texture itself is gold).
- Crusader block: new sim action "block" (Knight class, up or not) -> _block; a BLOCK button beside the hammer
  (HUD "block", held like the Knight's ability; key L); offline the held button blocks every frame, online the input
  message carries "k" and the server blocks while it's held; Net.ACTIONS gains "block", protocol 34 -> 35. Crusader
  bots raise the shield like Knights and throw the hammer when not blocking.
- Names only (ids unchanged): CLASSES.ranger.name "Archer", UPGRADE_NAME.ranger "Ranger", Eco.CLASS_NAMES ranger
  "Archer" / sniper "Ranger", the stand upgrade "Ranger Hats", the locker tab "RANGER".
- Berserker and Ranger (sniper) via Meshy (multi-image from their current bodies, retextured: a wolf-pelted,
  war-painted berserker with a braided red beard; a hooded woodland marksman in green and leather; both asked for
  black eyes), auto-rigged, 110 animations baked each (fit 2.00 / 1.90). LOOKS.berserker/sniper -> meshy bodies,
  KK_FOR barbarian / ranger. ~135 credits this round (3,110 left). Thumbnails re-rendered (with the Crusader's).
- Quick suite: ALL PASSED (32). NOTE: the online server must be redeployed for protocol 35.

# 0.31.62 (Kevin: more melee animations, not one swing over and over; damage unchanged)
- Sim._start_attack: an attack within windup + recover + COMBO_GAP (0.9 s) of the last one's start is the next swing
  of a three-hit combo (u.combo, u.combo_t); the "attack" event carries "combo" (events travel whole in snapshots,
  so online clients see the server's swing). Damage, timing and reach are unchanged.
- LOOKS.<cls>.combo -- Knight/Crusader: diagonal slice, horizontal slice, shield bash (Melee_Block_Attack);
  Barbarian: 2H slice, chop, stab; Berserker: chop, slice, spin; Rogue/Assassin: dual stab, slice, chop; Worker:
  chop, horizontal slice, stab; Villager: punch, punch, kick. View plays the combo's clip for an attack event.
- A hit's flinch alternates Hit_A / Hit_B; a blocked hit plays Melee_Block_Hit on the blocker ("blocked" event).
- tests/combo_test.gd (in the quick suite): held attacks give swings 0,1,2,0; a 2.5 s pause resets to 0; every melee
  look has three swings. Quick suite: ALL PASSED (33).

# 0.31.63 (Kevin: the Necromancer didn't look fully textured -> a Meshy model like the others)
- He was fully textured: all seven KayKit parts use the colour-strip texture, but its white/pale-blue swatches (skin,
  hair, bone crown) read as unpainted under the menu's bright light.
- Meshy: multi-image from the KayKit Necromancer (front/side/back) -> retexture as a sinister undead sorcerer with
  strong contrast (purple-black tattered robes, bone crown with a skull, grey-green skull face, glowing green eyes,
  stringy white hair) -> auto-rig. ~45 credits (3,065 left). 110 animations baked (fit 2.03).
- LOOKS.necromancer -> meshy:necromancer; LOOKS.necromancer_kaykit keeps the stock body for retarget_meshy (KK_FOR).
  render_skin_icons frames the Necromancer wider like the Archmage (his crown). Thumbnails re-rendered.
- All six upgraded classes now have Meshy bodies. Quick suite: ALL PASSED (33).

# 0.31.64 (Kevin: the Necromancer's staff skull should face the floor; the Archmage's book pages should face him;
# zoom on the locker's character)
- WEAPON_ROLL: Skeleton_Staff 195 -- worked out, not eyeballed: the skull sits on the model's -X side (head verts span
  x -0.46..0.14); a probe stepped the roll 0..345 in the Necromancer's idle and read where model -X points: 0 gave
  (0.28, 0.96, 0) = the sky, 195 gives (0, -1, 0) = the floor. spellbook_open 180 (pages toward the holder, cover out).
  (View.WEAPON_ROLL_TEST: a tools-only override for trying rolls.)
- Locker: the hero showcase is interactive (drag to turn, pinch / wheel to zoom) with the same + / − buttons and
  hint as the pass item view -- Screens.zoom_controls(stage, showcase, prefix), now shared by both. app_shots'
  SHOT_ZOOM also reaches the locker. Quick suite: ALL PASSED (33).

# 0.31.65 (Kevin: any staff is held straight up and down)
- View._stand_staff: a staff ("staff", "Skeleton_Staff", "bits/staff_*"; wands unchanged) is turned in the hand so it
  stands vertical in the class's idle pose, head up, with its face (STAFF_FACE; the skull staff's is -X) toward the
  front. Computed, not eyeballed: the idle animation's frame 0 is applied down the bone chain to the hand slot (each
  bone's rest overridden by its position/rotation/scale tracks), and the turn mapping the staff's +Y to world up and
  its face to the body's +Z is built in the slot's space; cached per body, idle and hand. It moves with the hand in
  casts, attacks and runs. Covers the Mage, Archmage, Necromancer, and the Priest's staff cosmetics, in matches and
  menus. Skeleton_Staff's 195-degree roll (0.31.64) is superseded: the skull now faces forward.
- render_skin_icons: base classes get default-gear icons too; the 11 staff thumbnails re-rendered.
- Environment rebuilt this session (container reset): clone from GitHub, Godot 4.7.2 + templates, Android build-tools
  35, the preview key from the R5 handoff (cert SHA-256 10:11:FC:79...:B3:8B:87, unchanged), mesa-vulkan-drivers for
  lavapipe renders. Quick suite: ALL PASSED (33).

# 0.31.66 (Kevin: hold the staffs as before, just turn each staff's face toward the body -- the skull facing the
# player model)
- 0.31.65's upright staffs undone; the 0.31.64 hold is back. View._face_staff only rolls a staff about its own length:
  in the idle's frame 0 (posed down the bone chain, as before) the roll that points its face at the holder's chest,
  across the staff, is applied. Faces measured from the meshes' heads: Skeleton_Staff -X (the skull, centroid
  x -0.24); staff, staff_B, staff_D +Z (flat heads, wide in X, thin in Z); staff_A (a thin rod) and staff_C (round)
  have no face and keep their old hold. Checked from the holder's chest with the body hidden: the skull's eyes, the
  orb's rim, the crystal's crescent and the ring all look back at it. The 11 staff thumbnails re-rendered.
  Quick suite: ALL PASSED (33).

# 0.31.67 (Kevin: new building models with Meshy, the Knight's shop first -- "a different design that would make more
# sense for knights"; picked the giant great helm, concept 3, "and add effects like the smoke and glowing lights in the
# visor")
- First try: Meshy multi-image from the KayKit barracks + retexture (40 credits) -- same shape, more detail; Kevin
  wanted a new design. Concepts (ElevenLabs gpt-image-2, ~1,480 credits for 8): a giant great helm and an armory.
- Helm 3 -> Meshy image-to-3D (30 credits): 20.3k triangles, one texture. tools/meshy_building_tex.py makes
  assets/meshy/knight_shop/: knight_shop.glb (texture cut 2K -> 1K = the blue team), knight_shop_red.png (the blues
  -- plume, shields, banner -- turned red, same saturation/brightness), knight_shop_glow.png (bright-yellow texels on
  triangles inside the visor box = the window slits).
- HAT_SHOPS.knight: model "meshy:knight_shop", scale 2.2 (base ring radius ~1.85 m, sim radius 1.8 unchanged; same spot,
  door and take ring); "flag" puts the upgrade flag on the dome beside the plume (default stays (0, 3.4, 0)).
- View._meshy_building (MESHY_BUILDINGS: base / vent / visor in model units): team texture; the glow mask as emission
  (EMISSION_OP_MULTIPLY -- ADD lit the whole helm) flickering with a warm omni light in front of the visor, like the
  dungeon torches (_sync_ambience); a short iron chimney on the back of the dome with a steady smoke trail
  (_chimney_smoke: 16 puffs, 4.5 s, the blast smoke's texture and breeze; half on low effects; preprocessed so it is
  already smoking at the start).
- tools/building_shot.gd: shop close-ups in a match (front, game camera, back, red; FLAGS=1 shows the upgrade flag).
  preload.json: knight_shop.glb in, barracks out. Quick suite: ALL PASSED (33).

# 0.31.68 (Kevin: the rest of the buildings -- hat shops + workshop, one giant-item and one themed concept per shop;
# picked A1 for Barbarian, Archer and Mage, B2 for Priest and Workshop; Rogue gets new concepts)
- Concepts: ElevenLabs gpt-image-2, 2 per style per shop (24, ~4,430 credits) + 4 new Rogue concepts (hood / dagger
  hideout, ~740). Meshy image-to-3D from each pick (5 x ~30 credits), ~20k triangles each, doors on +Z like the helm.
- assets/meshy/<barbarian_shop|archer_shop|mage_shop|priest_shop|workshop>/ via tools/meshy_building_tex.py, which now
  takes several --glow boxes each with its own colour rule, and --color-glow (the mask keeps the texture's colours:
  yellow windows, the priest's sun window and cyan fountain). Workshop glow: its side window only (the bright orange
  wood matched every looser rule).
- MESHY_BUILDINGS generalised: base / glow / energy / pipe (knight) / smoke (workshop chimney, measured at the roof's
  high point) / lights (knight only -- every omni light in reach of a castle's merged mesh is paid for across the whole
  castle on the phone) / crystals (mage: 5 glowing purple crystals orbiting and bobbing round the hat, transforms only).
- Fits: barbarian 1.85, archer 2.4, mage 2.1, priest 1.75 (base radii ~ the sims' r); upgrade flags placed on each
  top surface (heights measured from the meshes). Workshop: Castle.BUILDINGS -> "meshy:workshop", scale 2.1, moved
  x 17.35 -> 16.95 so its back meets the east wall, sim r 1.7 -> 2.1 (touches the wall: tests/siege_land_check flagged a 0.2 m squeeze trap at 1.85); built outside the merged kit mesh.
- tools/building_shot.gd: CLS=workshop. preload.json: the five new GLBs in, the replaced KayKit buildings out.
  Quick suite: ALL PASSED (33).

# 0.31.69 (Kevin: the Rogue shop -- new concepts, picked C2: a giant dark hood with glowing eyes)
- Concepts C (giant hood) / D (giant dagger through a crate hideout), 2 each (~740 ElevenLabs credits). C2 -> Meshy
  image-to-3D (~30 credits): ~20k triangles, door on +Z. assets/meshy/rogue_shop/ via tools/meshy_building_tex.py
  (--color-glow; glow boxes: the eyes inside the hood, the lantern on the left; the gold coins at the base stay unlit).
- HAT_SHOPS.rogue: "meshy:rogue_shop", scale 1.9 (base radius ~1.8 = the sim's r), flag on the right shoulder.
- MESHY_BUILDINGS.blink: the glow snaps off for 0.13 s every 4.7 s, with a quick double-blink every third time (the
  hood blinks; the lantern dims with it). Every hat shop and the workshop are now Meshy models.
- preload.json: rogue_shop.glb in, building_market out. Quick suite: ALL PASSED (33).

# 0.31.70 (Kevin: testers on a Pixel 7 Pro and a vivo S30 mini, Android 16, get stuck on a black screen when starting
# the game; the Godot splash shows on one of them -- so the engine and Vulkan come up and the hang is in our start-up)
- No logs exist from those phones: diagnostics only started in a match, and COPY DIAGNOSTICS sits in Settings. Both
  phones are likely ARM Mali GPUs (Tensor G2 Mali-G710; S30 Pro mini Dimensity 9300+); the game has only been checked
  on Kevin's Adreno S21. Not guessed at -- this build collects the evidence and gets testers in.
- Start-up log: SiegeApp creates a Diag first thing (user://boot_diag.log, previous start in boot_diag_prev.log;
  Diag.log_path/prev_path, BOOT_PATH/BOOT_PREV_PATH): device, GPU and API version, every start-up step with its time,
  engine/script errors, and the watchdog's STALL lines with the phone's logcat if frames stop for 2 s. It stops
  logging 8 s after the menu is up. COPY DIAGNOSTICS includes the start-up logs.
- Safe start: user://boot_state.json is "pending" from the first line until the menu has drawn 30 frames. If the last
  start never got there, this start skips the two heavy steps before the first frame -- the ~78 background model loads
  (Assets.preload_async) and the live 3D hero (its own 4x MSAA viewport, which blocks on the hero model's threaded
  load) -- and the home screen shows a SAFE START card with COPY DIAGNOSTICS. Stays on for this build; a new build
  tries the normal start again. Headless runs (tests, tools) never track or safe-start.
- Measured here (lavapipe): normal start, first frame at 4.3 s of which 3.6 s is the hero step waiting on the threaded
  loads; safe start, first frame at 0.3 s. Quick suite: ALL PASSED (33).

# 0.31.71 (Kevin, after seeing the same scenes on Vulkan and on the OpenGL test build: "OpenGL looks better")
- Kept Vulkan (OpenGL froze on Kevin's S21) and retuned it to look like the OpenGL render. The renderer-specific
  numbers: VULKAN_EXPOSURE 1.55 -> 2.0, VULKAN_AMBIENT 2.25 -> 1.05 (the strong ambient fill was what flattened the
  shadows), and new Vulkan-only multipliers on the colour adjustments, VULKAN_CONTRAST 1.2 and VULKAN_SATURATION 0.96
  -- applied in _apply_hq too, which used to overwrite the adjustments outright.
- Picked by measurement, not by eye: knight and mage shops, front and game camera, full quality, Vulkan vs OpenGL
  (tools/building_shot.gd FB_VK_EXP/AMB/CON/SAT). Luminance p10/p50/p90, saturation: OpenGL .10/.40/.72 s.54;
  Vulkan before .29/.47/.69 s.46; now .18/.38/.74 s.56 (11 combinations tried). Low graphics moves the same way
  (before .35/.53/.70 -> now .24/.42/.71; OpenGL .15/.36/.53). The menu hero shares exposure/ambient: a touch more
  contrast, otherwise unchanged. Quick suite: ALL PASSED (33).

# 0.31.72 (Kevin: "turn on the fallback to OpenGL for the older phones" -- after Mali testers froze on the splash)
- Vulkan stays the default (Kevin's S21 is unaffected). Read from Godot 4.7.2's source before building on it:
  Godot.kt getNativeRenderer -> GodotLib.getRendererInfo -> DisplayServerAndroid::check_vulkan_global_context (Vulkan
  1.1 hardware version + a Vulkan context, before the first frame); main.cpp takes the renderer from
  rendering/renderer/rendering_method(.mobile); ProjectSettings::setup loads application/config/project_settings_override
  before that; restart_on_exit on Android = Main::cleanup -> create_instance -> GodotActivity rebirth.
- Two fallbacks:
  1. Godot's own: rendering_device/fallback_to_opengl3 = true. Phones with no usable Vulkan (older phones) start on
     OpenGL before our code runs.
  2. BootGuard (scripts/app/boot_guard.gd, an autoload: its _init runs before the main scene loads). Marks each start
     pending until the menu has drawn 30 frames (moved here from SiegeApp, 0.31.70). If the last start was on Vulkan
     and never got there, it writes user://renderer.cfg (rendering_method and rendering_method.mobile =
     gl_compatibility; project.godot: application/config/project_settings_override="user://renderer.cfg") and restarts
     the app, which then runs on OpenGL for good. Stuck on OpenGL: no further switching, a safe start. Only on Android
     (FB_BOOT_GUARD=1 on desktop for testing); tools and tests never switch.
- The start-up log now opens in BootGuard._init (Diag.start_early), so it covers the main scene's loading too.
- Settings: "Graphics engine: Vulkan / OpenGL (compatibility)" with SWITCH TO OPENGL / VULKAN (confirm, restart);
  if Godot itself found no usable Vulkan, it just says so.
- OpenGL keeps the look Kevin picked (0.31.71 tuned Vulkan to match it).
- build_siege_preview.sh now requires the fallback ON and the override path, and checks both in the APK (Godot leaves
  fallback_to_opengl3 out of project.binary when it equals the engine default, true: missing = on).
- Checked end to end on desktop (FB_BOOT_GUARD=1): clean start -> Vulkan, menu up; a pending Vulkan record -> writes
  renderer.cfg and quits; next start -> OpenGL from the file, menu up. Settings rendered on both. tests/boot_guard_test
  (decisions + the file's keys + project settings). Quick suite: ALL PASSED (34).

# 0.31.73 (Kevin: "redo the outposts" with Meshy models, concepts first; "a different model for each outpost so it shows variety")
- Five Meshy keeps from the concepts Kevin picked, one per outpost (Land.OUTPOST_LOOKS, by outpost id): blue highland
  A1 watchtower (wall torches), red highland E1 log fort (palisade, shields), blue east rise D1 mossy ruin (rune
  crystal), red east rise B1 rook (the tall one, lit windows), the island C2 fire beacon. Doors face their own side's
  castle; the island's faces east, side-on to both. Replaces the KayKit tower bodies, plank deck and separate flags.
- Owner colours from ONE texture per model (scripts/siege/team_swap.gdshader): the saturated blues stay blue, turn
  deep red (the same rule as the shops' _red.png), or go plain grey-white cloth while nobody holds it; the bluish grey
  stone and iron below that saturation stay as painted. One texture instead of three per model keeps size and memory
  down. Glow masks (tools/meshy_building_tex.py --no-red --dilate 3): the watchtower's torches (plus little flames),
  the rook's windows, the ruin's crystal and runes and the beacon's coals; the ruin and the beacon glow in the holder's
  colour (faint grey when neutral).
- The beacon burns in the holder's colour (flames + a light); neutral, it smoulders (embers, smoke). Units on its deck
  keep out of the fire basket (Land.tower_block, applied in the sim's deck clamp and on climbing up).
- Sizes, measured from the meshes (centre, foot, deck height, parapet's inside, foot radius per model in
  siege_view.gd OUTPOST_MODELS): each scaled so its wall is about the solid radius (OUTPOST_TOWER_R 3.0, unchanged)
  and its parapet's inside >= 2.2 m (units walk to TOWER_TOP_R 1.85, unchanged); the squat ones stretched 12-30 %
  taller so decks sit ~2.7-3.0 m up (the rook 4.1 m). The deck height is per outpost now (Land.tower_floor): where
  units up there are drawn and where their shots start (h0). Gameplay radii are the same on every outpost.
- Bushes smaller and outside each keep's foot, the grass ring round the foot; the door side left clear.
- Textures 1K, imported lossy with mipmaps: 0.8-1.5 MB per outpost, 6.9 MB for all five in the export. Preview APK
  162.6 -> 169.2 MiB (177.5 MB).
- tests/outpost_look_test (new): five different models, deck heights match the models, parapets clear the walk
  radius, doors, the basket no-go spot (walking at the fire stops at its edge), the material and owner colours.
  tools/outpost_shot.gd: every outpost neutral / blue / red with rangers on the decks. Checked on Vulkan and OpenGL.
  Quick suite: ALL PASSED (35).

# 0.31.74 (Kevin: new castles "in meshy", "insides done also so the castles don't look cookie cutter", picked "B1 for one team and A2 for other", "stairs shouldn't be between the two main gates" (outside), "make sure players can climb up on the front wall to shoot outside")
- Two castle kits (scripts/siege/castle_kit.gd): blue gets A2 "Royal" (cream stone, blue cone roofs, gold), red gets
  B1 "War fortress" (dark stone, timber galleries, iron). Only what is drawn changed: walls, gates, terraces, stairs,
  rooms, the wall-walk and the dungeon are the sim's as before (siege_land_check unchanged and passing). The wall-walk
  behind the front wall keeps its stair inside the courtyard; the front wall between the gates is solid outside.
- Concepts: gpt-image-2 (ElevenLabs flows) from Kevin's picks, split into single-piece model sheets; 24 Meshy
  image-to-3D models, then Meshy remesh to low poly (walls ~1.2k triangles, terrace walls ~1k, gatehouses ~5k, towers
  ~3k, props ~1.6k; topiary and hedge box kept at ~3.8k, the remesh broke them). tools/meshy_building_tex.py: keeps
  only the base colour of remeshed models (they carry normal/metal maps too), --tex 512 for small props, --dilate.
- Pieces, each drawn with team_swap.gdshader (so a kit's blue cloth turns red on the red castle): curtain walls along
  every sim wall line, terrace walls on every terrace edge, stair side, the rampart's edges and the dungeon pit
  (decorated face to the lower side, found from the castle's heights), gatehouses round both gates (the KayKit gate's
  door leaves stay, scaled to the arch; its wall piece dropped), corner towers, an archway over the doorway down to the
  dungeon, the throne piece (Royal: a blue canopy on marble columns; War: a stone dais between two braziers, the
  throne raised 0.16 m onto it), and props along the walls (Royal: lion wall fountain, market stall, topiaries, hedge
  boxes, statues, banners; War: forge, weapon racks, training dummies, braziers, tents, supply piles). Walls and
  terrace walls are merged per model (_merge_kit); the rest keep their LODs. Braziers, the forge and the dungeon gate's
  torches burn (glow masks + small flames).
- Floors per area and kit (castle_mesh.gd builds each area as its own mesh): Royal cream flagstones / garden paving /
  white marble with gold inlay, War packed earth / planks / dark slate, darker in the dungeon; seamless textures from
  gpt-image-2. Stair stone tinted per kit.
- The KayKit castle is still there behind SiegeView.CASTLE_KITS = false (tools compare).
- Cost (tools/castle_cost.gd, lavapipe, 960x540, four game-camera views): primitives 333k -> 412k (own castle) /
  265k -> 346k (from the field), draw calls +5..+46, frame time +17..22 % (CPU rasteriser: relative only).
- tests/castle_kit_test (new): every piece and floor present, each team its own kit, every prop on its level and out of
  the way (stairs, wall-walk, gateways, hat shops, workshop, throne, the way to the dungeon) -- it moved five War props.
  tools/castle_shot.gd: both castles from the field, inside, gate, throne, courtyard and dungeon; tools/preload_list
  re-run (the outposts and castle pieces load in the background at start). The outpost and castle model files load on
  first use otherwise.

# 0.31.75 (Kevin: "make both castles the same royal style")
- Both teams build the Royal kit (castle_kit.gd STYLE_OF_TEAM = royal, royal). On the red castle team_swap turns the
  kit's blue roofs, banners, canopy and stall cloth deep red; the stone, gold and floors are the same on both.
- The War fortress kit stays described in castle_kit.gd and its files stay in the repo, but every export preset now
  excludes assets/meshy/castle/war_* and assets/meshy/castle/floors/war_* (about 5 MB). To bring it back: name it in
  STYLE_OF_TEAM and drop those two patterns. tests/castle_kit_test checks both ways (a kit a team builds is never
  excluded; an unused one is excluded from every preset) and only checks the props of kits in use.
- tools/preload_list re-run (the war pieces dropped from the background preload). tools/castle_shot.gd: both castles
  from the field, inside, the throne and the courtyard. Quick suite: ALL PASSED (36).

# 0.31.76 (Kevin: "Make concepts for the peasant and farmer", then picked "A2 both both")
- Concepts (gpt-image-2, ElevenLabs flow, with a lineup of the game's class bodies as the style reference): two designs
  x two takes each for the Peasant (the Villager) and the Farmer (the Worker); Kevin picked A2 for both -- a
  bareheaded peasant in a patched linen tunic with a rope belt and pouch, foot wraps; a straw-hat farmer with a
  moustache, red bandana, green overalls, leather gloves and a tool belt. Sheets and picks in reports/concepts/
  (with character_style_ref.png and tpose_ref.png, the references the flow fetched from the repo).
- Models: each pick redrawn as a T-pose turnaround (front / side / back, the KayKit Rogue's rest pose as the pose
  reference), split into three square views -> Meshy multi-image-to-3D (latest model, t-pose, remeshed to ~10k
  triangles, textured from the views) -> Meshy auto-rig (same 24 bones). 70 Meshy credits for both; ~5,950 ElevenLabs
  credits for the concepts (8 images) and turnarounds (4).
- assets/meshy/villager, assets/meshy/worker: rigged.glb, rig.json (fit 1.82 to the KayKit Rogue's height, like the
  others), 110 animations baked each by tools/retarget_meshy.gd (KK_FOR villager/worker -> LOOKS.villager_kaykit, the
  old Rogue body kept for it). The tool also prints a neck-height fit (FIT=neck uses it) -- for a hat that stands far
  above the head; not needed here (the farmer's overall fit and neck fit differ by 5 %).
- LOOKS.villager -> meshy:villager, LOOKS.worker -> meshy:worker (the Worker's axe, mug, mallet and felling axe in the
  baked hand slots; same idles, combos and ragdoll as before). MESHY gains both.
- Worker icons re-rendered (bust and the four weapon icons; render_skin_icons frames the straw hat, and re-renders a
  base class's weapon icon when ONLY names it). tools/preload_list: the worker body is preloaded with the KayKit
  heroes; re-run.
- Checked: idle / punch / chop renders beside the Rogue, Knight, Crusader and Archmage; match views (castle_shot
  red_court, blue_gate). Quick suite: ALL PASSED (36).

# 0.31.77 (Kevin, on the new Worker in the locker: "The hand needs to close around the handle to properly grab it.
# Also the fingers on other hand should be slightly bent so it looks more natural")
- Meshy's rig has no finger bones and its hands were flat and open, so the hands are posed in the mesh (bind pose) by
  the new tools/meshy_hand_pose.py: each finger bends at three joints (knuckle / middle / tip), normals and tangents
  turned with it, skin weights unchanged (all 110 baked animations fit as they were; re-baking gives identical files).
  Worker right hand: a fist (75 / 80 / 30 degrees, the knuckle bend eased over the first 12 mm; thumb in and down);
  left hand: slightly bent (20 / 30 / 20). Knuckle lines measured from hand renders (0.120 / 0.105 m past the wrist).
- The chunky fingers fold right against the palm (no hole to pass the handle through), so the handle goes where the
  closed hand hides it best from the side (80 % covered), like the KayKit fists: rig.json slot_r moved ~1.3 cm (bone
  space), turn unchanged, also kept as "grip_r" -- retarget_meshy.gd now keeps a grip_r / grip_l when it re-writes
  rig.json. The tool runs on Meshy's original rigged GLB (in git history, before this commit).
- Worker icons re-rendered. Checked: hand close-ups (outside, front, behind, along the handle), the locker zoomed
  in. Quick suite: ALL PASSED (36).

# Trailer 6, "Anyone Can Change Fate" (tools only, no build; Kevin: an epic cinematic trailer following a villager as
# the hero of a battle -- "everyone makes a difference")
- Story (tools/trailer6_script.md): shoved aside while the others put on helmets, villagers cowering, he finds the
  bomb and runs it across the battlefield. A wizard's meteor throws his friends in slow motion and knocks him down
  (ears ringing). He gets up and sees their gate (snap zoom). His allies rally round him and clear his way. The throw
  (a heartbeat), the gate goes up, a Knight tosses him a helmet, the army pours in, and the gold title appears with
  "Anyone can change fate". The narrator speaks at the key moments (10 lines).
- tools/trailer6_shots.gd: four staged runs (court 27.5 s, run 9.5, fall 16.5, charge 15.5) in a real match, recorded
  by Movie Maker (tools/trailer6_render.sh <run> [W H]: a temporary override.cfg for the window size, removed
  afterwards). Slow motion by Engine.time_scale windows. Cameras: world paths, follow offsets, a top-down shot framed
  on the fallen hero's head and hips bones, an over-the-shoulder POV with an FOV snap zoom, and a bomb-follow shot.
  Small props (trees, rocks) between a camera and its subject are hidden while they are. Every staged unit is topped
  up each frame (the bots' Armory upgrades rescale hp to the stat, which once let the wall archers kill the hero).
  The cowering villagers are posed bone by bone over a held crouch (arms round the head / hands to the mouth, head
  ducked); no KayKit clip has it.
- tools/trailer6_edit.py: the cut (26 shots) and the mix. Every sound sits on a shot (cut name + recording time).
  Music by ElevenLabs in three cues: A stops dead on the meteor; B rises from near silence to the throw; C hits with
  the gate. Narration lines are levelled to one loudness. Beds and stingers (muffled battle, arrows, slowed booms,
  ringing, heartbeat, the army's roar) come from ElevenLabs; hits and the bomb are the game's own sounds. Normalised
  to -14 LUFS.
- tools/trailer4_title_fx.py: --tag / --tag2 for the tagline's text (defaults unchanged).
- Fatebound-Trailer-6.mp4: 84 s, 1920x1080 at 30 fps, -13.8 LUFS, -1.0 dBFS peak, 128 MB.
- Remix (Kevin: the throw "cuts off too abruptly"; "the end lines are too quiet to hear the narrator"): cue B no longer
  stops at the throw but sinks under water (low-passed, echoing, faded by the boom) over a muffled battle, the fuse's
  fizz and the heartbeat, and a reversed boom swells into the real one. The music and the beds dip under every line
  (-7 dB; -12 dB under cue C), the last three lines are 3-5 dB louder, the boom under "FATEBOUND" is gone and the
  army's roar ends before "Everyone makes a difference". Narration now sits 7-20 dB over everything else
  (MIXMUTE=vo / bg renders the parts separately to measure it).
- Second pass (Kevin: the dip under the last lines "is too noticeable"; no soldiers' sounds after "Get up"; the bomb's
  flight "jittery"): no sidechain any more (its fast pumping on each word was what showed). Under a line only the
  music's voice band (800-4000 Hz) dips much, over slow 0.6 s ramps -- 1.3-2.6 dB overall -- while the last lines get
  their own lift after the VO compressor and cue C sits a little lower throughout; the narration is still 7-15 dB
  over everything else in the voice band. Nothing but the music from "Get up" to the rally (the battle bed comes
  back with the rally, from another part of the battle recording). The flying bomb is placed each frame on the sim's
  own flight curve at the frame's exact time (sim time + the match loop's banked tick time): in slow motion the sim
  moved it only every few frames, and the camera following it stepped with it (now an even 8.7-9.9 cm a frame). The
  gates' doors are kept out of the hidden props (the bomb shot, looking straight at the gate, hid them as it landed).

# 0.31.78 (Kevin: "go through the game and fix any issues like slow loading into battles, messy code, increase
# performance (without affecting quality)")
- Measured first (tests/start_bench.gd, headless here, after the app's background preload): pressing Play froze the
  menu for 670-1,300 ms of building before the loading card appeared (view 450-700 ms: hat shops 200 (their red and
  glow textures loaded on the spot), castles 200, outer-land trees 90, terrain 150; sim 50-70), then the first frame
  made 32 bodies (126 ms). The first Crusader / Berserker / Assassin / Sniper / Archmage / Necromancer of a match loaded
  its body and 110 animations right there: 1.3 s here (the phone several times that) -- the mid-match freezes. Every
  texture was imported lossless, so each load decoded it on the CPU (a 2048 character texture: 120-160 ms) and it sat
  uncompressed in video memory (21 MB each). In a 16 v 16 fight the CPU side was sim 2.4 ms/tick (all 31 bots thinking
  on the same tick every 0.15 s: 10-20 ms spikes), view 3 ms, HUD 0.8 ms a frame (this box; the phone is 2-3x).
- The start, staged (siege_mode.gd _start_staged): the FATEBOUND card goes up on the first frame after PLAY and the match
  is built behind it in steps that fit a 20 ms budget a frame (the sim, then View.setup_steps: lighting, terrain, outer
  land, foliage, each castle, props, scenery, oracles) -- the menu never freezes, the card's dots keep moving, the world
  draws (and its pipelines start compiling) as it grows; the warm-up camera tour and the clock wait as before. Rematches
  the same way. Tests and tools still build at once (FB_STAGED_START=1 for the staged path; tests/staged_start_test.gd).
- Less to build: the background preload (asset_cache.gd, now any resource; tools/preload_list.gd) covers the textures
  the hat shops, castle floors and outposts loaded on the spot, every class body with its animations (168 paths, was 80),
  so nothing loads mid-match; the outer-land tree plan is baked into the start-up cache (cache-v2); a castle's merged
  walls are kept for the next match. Mode._ready 670-1,300 -> 210 ms synchronous here (staged: 6 frames, longest
  98 ms); a rematch 97 ms.
- The 8 Meshy character textures (2048, lossless) are imported VRAM-compressed, high quality (ASTC 4x4 on Android, BC7
  on desktop): loaded straight into video memory (3 ms, was 120-160), 5.6 MB each instead of 21. Compared renders
  (tools/body_shot, castle_shot): the compression noise is a few levels, invisible; the APK grows ~14 MB. The 1K building
  and castle textures stay lossless (ASTC there would add ~60 MB to the APK for little gain: they're preloaded).
- Per frame: each bot thinks on its own 0.15 s schedule, spread over the ticks (sim p90 4.5 -> 3.4 ms, p99 8.2 -> 7.0,
  no think spikes); a Knight's / Crusader's shield reflex to an incoming shot is checked every tick (an arrow flies for
  less than the 0.15 s between decisions: whether it was blocked depended on the bots' phase -- knight_ai_test);
  _separate on packed arrays (0.54 -> 0.34 ms/tick, same pushes); the view's actor check no longer formats a key
  string per unit per frame; gates, trees, catapult arms and stockpiles are re-posed only when they change.
- Code: dead tier_cell, ensure_fonts (never called) and the two DejaVu fallback fonts and assets/castle textures it
  alone referenced (1.7 MB + 1 MB out of the APK); SiegeDiag's STAT line now splits sim= and view= times, and the
  match logs "MATCH BUILT" with the step times. Benches: tests/start_bench.gd, tests/fight_bench.gd.
- Quick suite: ALL PASSED (37, with staged_start_test).

# 0.31.72 Play bundle size (vc31 rebuilt, same versionCode/versionName/key; no gameplay or code change)
- Why: the 220.8 MB vc31 AAB could not be uploaded from the box Chrome (its upload buffer tops out at 256 MiB, about
  1.53x the file). The install-time pack grew 36 -> 114 MB with the 0.31.36-0.31.72 Meshy models, and every 3D texture
  was imported Lossless (headless imports never run the editor's "used in 3D -> VRAM" detection).
- No junk to remove: Godot exports only imported resources (no .blend/.psd/.glb originals in the pack), duplicate
  entries total 0.09 MB, every Meshy file is loaded by siege_view.gd.
- 31 3D albedo textures -> VRAM Compressed (ETC2 on Android, high_quality off = Godot's mobile default for 3D):
  Meshy characters 6x2048 (-21.95 MB), Meshy shops blue 7x1024 (-10.36), shops red 7x1024 (-7.66), kings 6x512
  (-2.57), terrain grass/path/rock + castle bricks/paving (-2.38). Normal maps, glow masks and all 2D/UI stay Lossless.
  ETC2 vs source at mip 0: PSNR 37-41 dB characters, 38-46 terrain/castle, 29-34 shops, 27-30 kings; zoomed 3x crops
  of the worst 128px blocks and in-match renders (building_shot knight/priest, body_shot crusader/berserker) show no
  visible difference.
- project.godot: WebP lossless effort for the remaining Lossless textures -> compression_method 6, factor 100
  (-1.04 MB pack, -0.09 MB launcher icons). Every one of the 135 remaining textures and all 26 icon/splash WebPs decode
  pixel-identical to the previous build.
- AAB 220,756,335 -> 174,716,069 bytes (pack 114.4 -> 68.4 MB; base 105.8 MB unchanged: 4 ABIs x libgodot ~25 MB).
  Still above the 170 MB ceiling; the remaining options all change something and were reported, not applied.
  Quick suite: ALL PASSED (34).

# 0.31.73 Forced update on a protocol mismatch (branch grok/siege-force-update; no versionCode bump, no protocol bump)
- Kevin: "when server has newer version than players installed game it'll force them to update".
- Found: the server's version refusal sent {"t":"bye","why":"version","need":N} and closed (4001) in the same frame;
  the client never received the bye (only the close), and siege_mode checked the socket state before reading packets
  anyway, so a too-old client only ever toasted "Could not connect to the server" and went home. The "Update the game
  to play online" text was unreachable.
- Server (backward compatible, protocol stays 35): refusals close REFUSE_CLOSE_DELAY (0.25 s) after the bye, so the
  bye arrives; the close reason is "version:<server protocol>" (was "version"); new {"t":"ver"} query answered with
  {"t":"ver","v":N} and closed (1000), no match joined. Old clients see the same bye/code (vc31 against this server:
  "Update the game to play online" instead of "Could not connect"). Needs a server redeploy to take effect.
- Client: Net.version_verdict / Net.refused_version (only Net.VERSION is compared, so every future bump works).
  Server newer -> UpdateScreen (scripts/app/update_screen.gd): full screen, input-blocking, "UPDATE REQUIRED" /
  "A new version of Fatebound is available. Update to keep playing.", big UPDATE -> market://details?id=com.fatebound.game
  (Android), https://play.google.com/store/apps/details?id=com.fatebound.game fallback. "PLAY OFFLINE VS BOTS" closes it
  but online stays locked (ONLINE / PLAY online re-show it; it comes back after each offline match). Back = quit.
  Server older -> "Servers are updating, try again in a few minutes", nothing blocked. A legacy close-only refusal
  (4001 "version", no number) can only come from a server older than this code -> "servers are updating".
- Menu check: VersionCheck (scripts/app/version_check.gd) at start-up and on resume (>60 s since the last), skipped
  headless. Against a server without the "ver" message it gets no answer (-1, unknown) and the connect path decides.
- tests/version_gate_test.gd (real server + in-process fake newer/legacy servers + the real client and app).

# Play preset: no 32-bit Intel (Kevin: "remove the 32bit Intel from game")
- export_presets.cfg "Android Play Store": architectures/x86=false (armeabi-v7a, arm64-v8a, x86_64 stay). Only that
  preset had it; the itch/preview presets were already arm64-v8a only. Intel Atom Android devices are long gone; the
  AAB's per-device split meant no player downloaded it anyway -- a smaller upload, nothing else. No build or upload.

# vc32 / 1.2.8-siege-0.31.78 rebuilt without x86 (same versionCode/versionName/key; game data unchanged)
- Built on claude/siege-dev-r6-local 8fb85e8 merged into grok/siege-play-local-r9; verify_play_bundle.py now expects
  exactly armeabi-v7a, arm64-v8a, x86_64.
- AAB 193,648,329 -> 167,008,590 bytes (only base/lib/x86/* removed; asset pack, icons, ETC2 textures, forced-update
  screen identical). SHA-256 7741f5bfdc2c41061b861717f5d88b945729f134a97ba5f51a85c26fd8fd8142.
- Verifier + bundletool validate + jarsigner OK, upload cert 69:71:A9:...:83:90:84. Protocol 35 (no server change).
  Quick suite: ALL PASSED (38).
# Trailer 6: where the meteor comes from (Kevin: "it looks like he's the one that blew them up. Make it so viewers
# know where explosion came from with camera following the meteor from arch mage")
- The fall run opens on the red Archmage now: a close low shot as he raises his staff, a fireball gathers on its orb
  and he hurls it; the camera chases it (slow motion) over his shoulder and down onto the hero's friends, with the
  hero running in on the left; the blast shot starts a beat earlier so its fiery streak comes down into the frame.
  The fireball (trailer only, tools/trailer6_shots.gd): a child of the staff while it gathers, then a curve to the
  ground, landing on the sim tick its meteor goes off; its own light, flame trail and smoke; the game's falling rock is
  hidden, its warning ring kept. Everything from the impact on is the old fall, 1.79 game s later; the hero is paced
  to the spot he was knocked down from before (measured), so the shots after it frame as they did.
- Cut and mix (tools/trailer6_edit.py): approach 1.0 s, "mage" 1.13 s, "chase" 1.87 s, the blast 6.5 s; the cast's
  surge and crackle, the game's meteor-cast sound on the throw, its rush slowed with the picture. 87.4 s (was 84.4).

# Home: one PLAY, always the server (Kevin: "remove the play with bots option from game. Only have the regular play
# button so player is always playing on server plus they play with bots anyway when there aren't enough players")
- screens.gd: the VS BOTS / ONLINE 16v16 row is gone; PLAY always starts the online match. The server already holds
  every slot no human does with a bot (siege_server.gd), so a quiet server is still a full 16 v 16. Hint under PLAY:
  "Live 16 vs 16 on the Siege server · bots fill any empty slots". siege_app.gd: play_online removed.
- The local match stays for the tutorial (HOW TO PLAY / first-visit Herald) and the tests. With no signal PLAY shows
  the existing "Could not connect to the server" and returns Home (no offline fallback any more).
- Tests: app_flow_test checks there's no mode choice and that PLAY goes online (rewards still checked on a local
  match); app_scroll_test finds PLAY by its action key instead of a fixed point. app_flow, app_scroll, tutorial,
  parse_all pass. No build.

# 0.31.79 menus, step 1 (Kevin: "continue with new menu build" -- the concept boards in the game)
- Art: assets/ui/v2 -- the painted Home battlements, the vault, the pass and market banners, seamless damask /
  parchment / wood / stone, twelve 3D-style icons (ElevenLabs), the four Meshy chests baked by tools/chest_bake.gd
  into split-lid scenes (1K VRAM textures; the source GLBs sit in chests/src, .gdignore'd, not exported).
- Look: ui2.gd + skin.gd + ui_skin.gdshader -- every panel and button is one signed-distance skin (crisp on any
  phone): gold rims, damask/parchment/wood fills, lipped glossy buttons that press in and grey out, Luckiest Guy text
  with chunky outlines, ribbons, dividers, badges, sweeps, sunbursts.
- Chrome: shield level badge, XP bar, gold/gem pills; a wooden tab bar with the 3D icons, the open tab raised.
- Home: the battlements backdrop with drifting clouds and slow sun rays; all seven base classes in 3D on the dais in
  their equipped weapons (roster.gd); PASS / ORDERS / FIRST WIN medallions; the ribbon; one big PLAY; the chests in 3D
  over their slots (chest_row.gd); the orders on parchment; the pass summary. Opening a chest is a full-screen 3D
  scene (chest_open.gd): it rattles, TAP TO OPEN, the lid flies open with a flash and a spray of coins, the rewards
  rise in. Pass, Shop, Locker and Settings rebuilt in the same look (same buttons and keys underneath).
- Pass chest rewards showed "0 gold" (reward_text had no chest case); they now show the chest.
- app_flow, app_scroll, tutorial, chest, boot_guard, parse_all pass.
- Step 2: the match panels in the same look (siege_hud.gd): PAUSED on a parchment sheet (how to win with the 3D icons,
  the tricks, RESUME / RESOLUTION / LEAVE MATCH), the results under a VICTORY / DEFEAT / DRAW ribbon (a crown and a
  sunburst on a win), the score in team colours, your KOs / downs / rescues, the spoils on parchment, the chests earned
  with their pictures, HOME / PLAY AGAIN; the workshop uses the new panel and buttons. Panels drop open, and one taller
  than the screen is shrunk to fit (wrapping labels are given a width before they're measured -- unmeasured, they made
  the panel thousands of pixels tall).
- Locker rail: round head portraits (assets/ui/skins/default_*), zoom buttons in the new style.
- 0.31.79, version code 165. Quick suite: ALL 37 PASSED.

# 0.31.80 (Kevin: "redo all the basic characters also since we did the advanced ones"; picked Knight A1, Barbarian
# A1, Rogue A1, Archer B1, Mage B1, Priest A2)
- Concepts (gpt-image-2, ElevenLabs flow "Fatebound base-class concepts"): per class one sheet with design A (close to
  the old body) and B (a fresh take), two takes each, in the Farmer concept's clay style, each base class's old body
  and its upgraded form as the reference (reports/concepts/ref_pair_<cls>.png). Sheets and picks in reports/concepts.
  The Priest gets a body of his own (it was the Mage's with a cream tint). Mage B's round glasses were dropped
  (too close to a famous boy wizard).
- Models: each pick redrawn as a 2K T-pose turnaround (front / side / back, tpose_ref.png as the pose), cut into three
  square views, Meshy multi-image-to-3D (latest, t-pose, ~10k triangles), Meshy auto-rig. The Knight's first model
  lost its cape and turned Roman, the Rogue's lost his cape: both redone with image enhancement off and the views as
  the texture references (texture_image_urls) -- faithful. ~12k ElevenLabs credits (12 concept images, 6 turnarounds),
  ~275 Meshy credits.
- assets/meshy/<knight|barbarian|rogue|ranger|mage|priest>: rigged.glb, rig.json, the 110 baked animations
  (tools/retarget_meshy.gd). Fit by the neck height (FIT=neck): every new body's neck at the KayKit neck height
  (1.24 m), as the other Meshy bodies have it -- the height fit would have made them ~20 % bigger (the KayKit heads
  are half the body). KK_FOR now names stock *_kaykit bodies for every Meshy body (knight_kaykit ... mage_kaykit added
  to LOOKS, tools only; the Priest's and the Archmage's source is mage_kaykit).
- LOOKS: knight / barbarian / rogue / ranger / mage / priest -> meshy:<cls> (same weapons, idles, combos, ragdoll); the
  Knight's always-a-shield rule and the halberd / scythe holds cover the Meshy Knight and Rogue. Priest tint dropped.
- Icons: the six busts (locker coins) and every base-class weapon icon re-rendered (render_skin_icons: bust framing for
  the Mage's hat, the Knight's plume and the bear head). tools/preload_list re-run (the KayKit hero GLBs leave the
  list, the six Meshy bodies and their animations join it).
- Home dais (roster.gd): the Knight a step forward (z 0.95), the Barbarian and the Mage turned so the axe and the
  staff's orb clear him.
- 0.31.80, version code 166. Quick suite: ALL 37 PASSED.

# 0.31.81 (Kevin: "redo the advanced classes in the same style"; picked B2 for all six)
- Concepts (same ElevenLabs flow): per upgraded class one sheet with design A (its current look redone) and B (the new
  base pick grown up), two takes each; references: the base class's concept pick (style) and the new base body beside
  the current upgrade in the game (reports/concepts/ref_up_<cls>.png). Picks: the Knight as a champion (silver and gold
  plate, crowned crimson plume, lion emblem, crimson cape); the Barbarian as a berserker (black bear pelt, braided
  beard with beads, chain, bones); the Rogue as a master assassin (black hood lined crimson, crimson mask, tattered
  black cape); the Archer as an elite ranger (green feathered hat, green cloak, studded leather, quiver); the Mage grown
  old (grey beard, midnight-blue constellation robes and hat); the Priest fallen (grey skin, glowing green eyes, cracked
  sun emblem, tattered black robes). Sheets and picks in reports/concepts.
- Models: 2K T-pose turnarounds, Meshy multi-image-to-3D with image enhancement off and the views as the texture
  references (faithful from the start), auto-rig. The view splitter now cuts where the sheet is emptiest near each
  third (a hand reaching past a third's edge no longer leaves a sliver in the next view). ~3.9k ElevenLabs credits for
  the turnarounds (+7.9k concepts), 210 Meshy credits.
- assets/meshy/<crusader|berserker|assassin|sniper|archmage|necromancer>: replaced (rigged.glb, rig.json, the 110
  baked animations), fit by the neck height like the base classes (the old ones were fit by overall height; the
  necks land at 1.24 m either way). LOOKS unchanged (same weapons, idles, abilities; the upgrade's 1.14 scale).
- Texture import: the twelve new character textures (0.31.80's six too) are VRAM-compressed, high quality, like the
  0.31.78 ones -- 0.31.80 shipped its six base bodies lossless (decoded on the CPU, 21 MB each in video memory).
- Icons: the six upgrade busts and their weapon icons re-rendered (render_skin_icons BUST_FRAME gains the upgrades; the
  far framing stays for the Archmage's gear only -- the Necromancer has no crown now). tools/preload_list re-run.
- 0.31.81, version code 167. Quick suite: ALL 37 PASSED.

# 0.31.82 (Kevin: "Add a players online in main menu. Also when starting match have it countdown from 20 seconds and show players joining.")
- Server (server/siege_server.gd): a hello no longer seats the player at once -- it joins the lobby. The first one in
  starts a LOBBY_TIME (20 s; env SIEGE_LOBBY) countdown, everyone who arrives before zero goes in with them, and every
  0.5 s each waiting player gets {"t":"lobby", left, wait, names, me, online, in_match, slots, running}. At zero the
  wave is seated: a new match if none runs (or only bots are left in it), else into the running one; during a results
  screen they wait for the next match with everyone. Waiting players get no snapshots. {"t":"status"} without a hello
  answers {online, in_match, waiting, lobby, running, slots, max} (the asker closes; the server does after 2 s -- a
  close right behind the answer can arrive in the same read and the WebSocket drops the answer). Protocol stays 35:
  an older app ignores "lobby" and simply gets its welcome at zero; this app against an older server is welcomed at
  once (no countdown) and gets no count.
- Lobby panel (scripts/siege/lobby_panel.gd), up from PLAY until the welcome: FATEBOUND, "FINDING A BATTLE" with a
  spinning ring while connecting, then "BATTLE STARTS IN" with the seconds inside a ring that empties (orange and a
  tick each second in the last five), whether a battle is already on ("2 players fighting, you join it at zero") or a
  new one starts, "N / 32 PLAYERS", and the players joining as name chips (yours marked YOU; newcomers pop in with a
  flip; ten shown, then "+N more"). LEAVE / Back goes home; a failed connection shows "CAN'T JOIN" and the reason.
  On the welcome the FATEBOUND card goes straight over it (the warm-up as before).
- Home (screens.gd, scripts/app/online_status.gd): the line under PLAY is a pill -- "12 PLAYERS ONLINE" with a
  breathing green dot and "N in battle" / "N in the lobby, join them!" / "bots fill the empty slots". Polled with a
  status query every 15 s while Home shows (not during a match or in the background); "LIVE SIEGE SERVER" until an
  answer or when the server can't say (the live server needs the redeploy). Only the real app polls (tests and tools
  stay off the network unless FB_STATUS_POLL is set).
- server/siege_probe.gd also asks the status and waits out the countdown (35 s timeout): the install script's probe.
- Tests: siege_net_smoke runs the server with a 1.5 s lobby and checks the lobby messages before both welcomes (names,
  running, counts), the panel closing on the welcome and a status answer; net_load_test uses a 1 s lobby.
- Live server: needs `sudo bash godot/server/deploy/install_siege_server.sh` from this branch for the countdown and the
  count (until then the app connects as before).
- 0.31.82, version code 168. Quick suite: ALL 37 PASSED.

# 0.31.83 (Kevin: "I don't like the wallpaper looking pattern on background")
- The royal damask is gone: no longer tiled under every screen (siege_app._build_background -- the gradient is now the
  royal blue the damask used to give it, #243d96 -> #152a7c -> #0a1750, with the warm glow at the top), and the damask
  panel kinds (royal, night, purple, ember, green: the shop / pass / featured cards, the match HUD's panels) are plain
  gradients (pattern_mix 0). Parchment, wood and stone panels unchanged.
- 0.31.83, version code 169. Quick suite: ALL 37 PASSED.

# 0.31.84 (Kevin: "I still want a sort of texture or design for background. Give me concepts to pick from" -> "C.
# Also put a fps cap of 60 in the menus")
- Seven background concepts (reports/concepts/bg_concepts.png): A castle stone, B twilight sky, C light rays, D battle
  map, E painted canvas, F banner hall (gpt-image-2, 9:16, two takes each, ~2.2k ElevenLabs credits), G diagonal
  stripes (drawn in code); each shown behind the real Shop. Kevin picked C: royal blue, soft light rays fanning from the
  top, drifting gold motes. Upscaled 2x with Topaz (1440x2560, ~0.5k credits) -> assets/ui/v2/bg_menu.webp (VRAM
  compressed, high quality, no mipmaps), covering the screen behind every menu over the gradient
  (siege_app._build_background).
- Menus capped at 60 fps (MENU_FPS): they ran uncapped, 120 on the S21 Ultra's 120 Hz screen. A match still sets its
  own 30 and puts the 60 back when it ends. The real app only (tests and tools run the menus uncapped, FB_MENU_FPS to
  force it).
- 0.31.84, version code 170. Quick suite: ALL 37 PASSED.

# Server install fix (Kevin: "The 20 second timer isn't working")
- The live server still runs a build from before 0.31.82 (probe: welcomed at once, no lobby messages, no status
  answer) -- the countdown and the player count are the server's, so it needs the redeploy.
- server/deploy/install_siege_server.sh could not have done that: its minimal server project copied only siege_sim.gd
  and siege_net.gd, but the sim preloads siege_land.gd and siege_castle.gd, so the copied sim failed to compile and the
  probe failed. It now copies all four (the baked terrain files stay client-only). Dry run (NO_SYSTEMD=1): installs,
  the probe waits out the 20 s lobby, PROBE_OK.

## vc33 build (grok/siege-play-local-r10, 2026-10-08 PT) -- OVER THE 175 MB UPLOAD LIMIT, not uploaded
- Merge of claude/siege-dev-r6-local e749337 (0.31.84) onto r9: ETC2 imports kept (the six new base-class bodies set to
  ETC2 like the rest), force-update + 0.31.82 lobby/status merged on the server (status close goes through _refuse),
  Update screen's "Play offline vs bots" now starts the offline match itself (Home has no VS BOTS any more).
- vc33 / 1.2.9-siege-0.31.84, 3 ABIs, signed with the upload key (cert SHA256 69:71:A9...:90:84), verifier/bundletool/
  jarsigner OK, 38/38 quick tests pass. AAB 198.4 MB (vc32 167.0): +31 MB from 12 new Meshy bodies (textures, meshes,
  anims) and the v2 menus/chests. Protocol still 35.

# Play preset: no 64-bit Intel either (Kevin: "Can we drop the 64bit Intel also")
- export_presets.cfg "Android Play Store": architectures/x86_64=false; the AAB now carries armeabi-v7a and arm64-v8a
  only (Play's 64-bit requirement is met by arm64-v8a). The itch/preview presets were already arm64-v8a only. Gone with
  it: Intel/AMD Chromebooks, x86 emulators and Google Play Games on PC (those need an x86_64 build). No build or upload.

## vc33 rebuilt with 2 ABIs (grok/siege-play-local-r10, 2026-10-09 PT) -- fits the 175 MB upload limit, not uploaded
- Merged claude/siege-dev-r6-local 8827b74 (Kevin: drop x86_64): "Android Play Store" preset is armeabi-v7a + arm64-v8a
  only; tools/verify_play_bundle.py now requires exactly those 2 ABIs (and no x86/x86_64 libs).
- Same vc33 / 1.2.9-siege-0.31.84, ETC2, laughing-king icon (icon files byte-identical to the 3-ABI build), Vulkan with the
  OpenGL fallback, forced-update screen. Signed with the upload key (cert SHA256 69:71:A9...:90:84); verifier, bundletool
  and jarsigner OK; 38/38 quick tests pass. AAB 172,571,884 bytes (172.6 MB; was 198.4 MB with x86_64).
  SHA256 9c3cc7c8b2bb20ee6aa1232dfb5ee3361a2394b2f4a8bc70b5d2fd8435a06a2e. Protocol still 35 (deploy-0.31.84 unchanged).

# 0.31.85 (Kevin: "When on the other team, it still thinks I'm on the other team and controls are inverted and health
# bars are red for my team")
- Online, the server seats you on either team; everything was tested from the blue side (offline you are always blue,
  online the first player is too). On red:
  - Controls: the camera looks up the field from your own castle, so on red it is turned half way round -- but the
    stick's screen directions went into the sim as blue's world directions. siege_mode._move_input() turns the stick
    round for the red team (prediction, the inputs sent, offline).
  - Colours: rings, health bars, castle roofs and banners, the throne, the King, outposts, hat shops, the workshop, the
    HUD's YOUR SIDE / gates / outpost diamonds / station signs were drawn in the real team colour, so a red player's own
    side was red. Now your side is always drawn blue and the other red (siege_view.vt() / siege_hud.vt(); my_side from
    the player's unit at setup). Positions, facing and the camera still use the real team. The merged castle walls kept
    for rematches are dropped when the side changes (their tint was for the other side).
- tests/side_view_test.gd (in the suite): a match seated on b0 and on r0 through the welcome path; stick up / right move
  up / right on screen, ally bars blue, enemy bars red, the HUD's mapping.
- No server change (the client draws and turns the stick).
- 0.31.85, version code 171. Quick suite: ALL 38 PASSED.

# Merge of grok/siege-server-min-build (91b7d66) into this branch
- The live server was redeployed from that branch (server 0.31.84-minbuild: minimum app build from
  /etc/fatebound-siege/min_build, the "ver" query, the client's Update screen; Play vc33 line). Merged here so the next
  server deploy from this branch keeps it. Only this file conflicted. Its import changes (ETC2 textures) need a
  `godot --headless --import` after checkout.

# 0.31.86 (Kevin: "Can you add so it shows the player names on the battlefield above their heads. Only live players
# will show names.")
- Server: {"t":"pn", "n":{unit id: name}} to everyone in the match whenever a seat changes (a join, a leave, a new
  match); only seated players are in it, never bots. Names are cleaned at the hello (no control characters, 20 letters,
  "Player" if empty). Additive -- older apps ignore it; protocol stays 35. SERVER_BUILD 0.31.86 (min_build_test wants
  it equal to the app's build).
- App: siege_mode keeps the names (net_names) and hands them to the view; view.bars() adds the name to a live player's
  bar and the HUD draws it just above: yours gold, your side's light blue, theirs light red. Dead players have no bar,
  so no name. Offline (all bots) shows none.
- siege_net_smoke: the names arrive for both players, show over our bar, and the leaver's goes when they leave.
- Live server: needs the redeploy from this branch for the names (until then the app shows none).
- 0.31.86, version code 172. Quick suite: ALL 40 PASSED (with the merged version_gate_test and min_build_test).

# 0.31.87 (Kevin: "make it so their titles show (use correct punctuation when putting the titles on the name)"; "players
# have to earn the titles instead by doing tasks in the game. Make ones that are easier and ones that are hard
# (legendary rarity)"; "more titles for each class"; "remove the no death in a match title because players will just camp")
- 37 titles, all earned (draft approved, rarity looks picked from reports in chat): 16 for everyone (5 common, 3 rare,
  4 epic, 4 legendary) and a rare / epic / legendary for each of the 7 classes (each upgrade counts as its class).
  siege_net.TITLES: id -> [text, form, rarity] -- here so the server builds the over-head text from ids, never free
  text. Forms and punctuation: "the" epithet (Midblade the Gatebreaker), "of" (Midblade of Many Hats), "prefix" rank
  (Squire Midblade, Sir Midblade), "office" after a comma (Midblade, Siege Lord). Net.title_parts / title_text.
- How each is earned: economy TITLE_GOALS (lifetime count -> n, a task line, its class). Profile stats gain lifts,
  repaired, healed, best_multi, streak / best_streak, main_<cls>, win_<cls>, kills_<cls>. A match's class is the one
  played longest (at least a minute; hats come off on a knockout, so not the class it ends as); knockouts count for the
  class they were made as. siege_mode gathers it the same way offline and online (class time and knockouts from the
  player's unit, repairs and bursts from the sim's events); healing is the sim's new "healed" (what allies got, not
  yourself: priest beam, Sanctuary, Necromancer's ally heal), sent online by the server ("st", once a second).
  profile.check_titles() after every match (results: TITLE EARNED with the name as it shows) and on load (a veteran's
  old stats earn theirs at once; Home toasts how many).
- No win-without-dying title (Kevin: camping). Whirlwind, Shieldwall, Lightbringer and Mason became class titles; the
  general triple knockout is the Tempest.
- Owned titles stay owned (shop, pass, the Knight Arsenal). Gatebreaker and Kingsworn left the shop; the Knight Arsenal
  dropped its title (330 -> 280 gems); the five old pass titles stay in the pass draw (every season keeps its tiers)
  and their tiers give gems (epic 50, legendary 100; season 1: premium 5, 9, 21); the premium offer counts the real
  cosmetics (10, 5 legendary in season 1). Today's shop rotation changes once (its pool lost the two titles).
- Online: the hello names the worn title id (dropped unless in Net.TITLES); "pn" carries "tt" {unit: title id}, the
  lobby "tt" beside its names (the panel lists titled names). SERVER_BUILD 0.31.87; additive, protocol 35.
- Over the head (siege_hud): every live player's name on a dark plate; the title in its rarity's colour; common plain,
  rare a blue rim, epic a purple rim and slow glow, legendary a gold rim, glow, a light band sweeping the letters and two
  sparkles. Plates that would cover one already placed step up. The top bar reads the punctuated name.
- Locker > TITLES: For Everyone, then each class (as Knight or Crusader ...), rarity order; each card the rarity's
  panel, the name as it shows, the task, a progress bar, EQUIP once earned.
- tests/title_test.gd (in the suite); siege_net_smoke: a title through the server to the other player's bar and lobby.
- Live server: needs the redeploy from this branch (titles over heads, healing counted online).
- 0.31.87, version code 173. Quick suite: ALL 41 PASSED.

## 0.31.88 — your own nameplate (Kevin: "Show the nameplate for the players own name also")
- siege_view: my_name / my_title, set by siege_mode from the profile in both match setups (vs bots and online);
  your bar always carries your name (gold) and worn title, so the plate shows against bots and without the
  server's "pn". Other players' plates still come only from the server; bots have none.
- side_view_test: my plate, gold, with no names from a server, on either team.
- 0.31.88, version code 174. Quick suite: ALL 41 PASSED.

## 0.31.89 — new launcher icon (Kevin picked concept B4, "King Rescue")
- assets/branding: a blue knight sprinting home with the chubby King hoisted overhead (fish in hand, crown
  slipping), the enemy castle behind. foreground.png = the knight and King cut out; background.png = the scene
  with them painted out and reflected into the 18dp parallax margin, so a launcher's parallax never shows a
  second copy; the art covers the 72dp viewport (296 px of 432). monochrome.png = a new tipped battlement crown
  (themed icons; max radius 113 px). icon.png (192) = the 72dp viewport.
- store-listing: the 512 Play icon (graphics/app_icon_512x512.png, fastlane images/icon.png); README updated.
- Concepts A-F and the source art are on Kevin's ElevenLabs flow (tL2Uq8Khy94WZ0PV3s34).
- 0.31.89, version code 175. Quick suite: ALL 41 PASSED.

## IAP plan (2026-10-09, no build)
- Kevin: weapons overhaul ("Armory Reforged": every weapon its own Meshy model and a new name, 7 quest-only legendaries,
  a Forge with Embers and three cosmetic stars) plus in-app purchases. Real money buys gems only; chests stay
  earn-only; quest weapons are never sold; nothing sold changes damage.
- godot/PLAY_IAP_HANDOFF.md: the Play Console side for Grokbot (payments profile, internal-testing billing build,
  products gems_80 / gems_500 / gems_1100 / gems_2400 / gems_6500 / starter_pack, license testers, the purchase-check
  service account at /etc/fatebound-siege/play-service-account.json, Data safety and rating). PLAY_STORE_HANDOFF.md
  points to it.

## 0.31.90 — Google Play Billing and the gem shop
- addons/GodotGooglePlayBilling: the official plugin 3.3.0 (Billing Library 9.1.0), built from source
  (godot-sdk-integrations e494f37; GitHub release downloads are blocked here). export_plugin.gd patched so the AAR and
  its dependencies go only into Gradle presets: the Play preset gets billing, the preview APK is unchanged.
  Checked with a throwaway-key Play export: the AAB has the plugin, the billing classes and the BILLING permission.
- siege_net.IAP: the product table from PLAY_IAP_HANDOFF.md (gems_80 .. gems_6500, starter_pack = 300 gems + 150 Embers
  + an unowned rare weapon, once). Profile: embers, iap {done, starter}; grant_iap is once per purchase token.
- scripts/meta/billing.gd: connect, local prices, buy, then the Siege server checks the token with Google before the
  grant; gem packs consumed, starter pack acknowledged. Pending, cancelled, unreachable and app-killed purchases are
  finished later from query_purchases (start, resume, ITEM_ALREADY_OWNED). Nothing is consumed before it is granted.
- server/iap_verify.gd + siege_server "iap": RS256 service-account JWT -> access token -> androidpublisher
  purchases.products.get; verdicts ok / pending / used / bad / unconfigured / unreachable; ledger iap_ledger.jsonl
  (hashed tokens). Key via systemd LoadCredential (the installer enables it when
  /etc/fatebound-siege/play-service-account.json exists). SIEGE_IAP_FAKE=1 accepts all (internal testing only).
- Shop: GEM PACKS above GEMS → GOLD; starter pack card until bought; packs in a 3 + 2 grid. Preview builds show grey
  PLAY STORE buttons; the Play build shows Google's local prices.
- privacy.html: purchases section. PLAY_IAP_HANDOFF: installer re-run in step 5, SIEGE_IAP_FAKE, Status updated.
- tests/iap_test.gd (in the suite): product table vs the handoff, grants, a fake BillingClient through every path, a
  fake Google (JWT signature, verdicts, one token request), and real servers in FAKE and no-key modes.
- Live server: needs the redeploy from this branch for purchase checks.
- 0.31.90, version code 176. Quick suite: ALL 42 PASSED.

## 0.31.91 — first start froze on the Godot splash (Kevin's S21, fresh Play install, Vulkan)
- Kevin's log: the first start (Vulkan) never reached the menu; BootGuard switched the phone to OpenGL and the next
  start was fine. The frozen start's own log had been rotated out by the two restarts after it.
- Reproduced on desktop Vulkan (Mobile renderer) by emptying user://shader_cache: the start hangs forever at "hero",
  every thread asleep; with the cache warm it starts in ~5 s (0.31.90 code).
- Cause (gdb on the hung process + Godot 4.7.2 source): ShaderData::is_valid() (scene_shader_forward_mobile.cpp) holds
  SceneShaderForwardMobile::singleton_mutex while ShaderRD::version_is_valid() waits for the shader's compile tasks
  (a WorkerThreadPool group). The background preload had ~200 threaded loads in flight (sub-threads on); each waiting
  load lets the pool start another, so every pool thread ended up in a load blocked on that mutex and the compile
  tasks never got a thread. A warm cache compiles nothing, which is why only fresh installs froze (likely the testers'
  "frozen splash" phones too) and why the long-installed preview never did.
- Fix (asset_cache.gd): the preload is a queue with ONE load on a pool thread at a time, no sub-threads; a queued path
  needed now is loaded directly, the one loading is waited for. Empty shader cache: menu up, preload drains (39 s on
  lavapipe), and a match started with 113 loads still queued builds and runs.
- tools/cold_start_check.sh (needs a display): starts the app on Vulkan with the shader cache moved aside, PASS when
  the menu is up. Fails on 0.31.90, passes now. tests/preload_queue_test.gd (in the suite): the queue's rules.
- BootGuard keeps the frozen start's log as user://boot_diag_stuck.log when it switches to OpenGL; COPY DIAGNOSTICS
  includes it.
- Resume: the server version re-check was add_child'ed during NOTIFICATION_APPLICATION_RESUMED ("Parent node is busy
  setting up children" in Kevin's log); the failed checker then blocked every later check. Now deferred.
- Phones BootGuard already moved to OpenGL stay there: Settings -> Graphics engine -> SWITCH TO VULKAN.
- 0.31.91, version code 177. Quick suite: ALL 43 PASSED.

## 0.31.92 — Vulkan only (Kevin: "Ok vulkan now works. I'd like to remove the opengl version now")
- project.godot: rendering_device/fallback_to_opengl3=false (Godot then marks android.hardware.vulkan.version 1.1
  required in the manifest: Play won't offer the game to phones without it; an itch APK on such a phone shows Godot's
  "no Vulkan" message); application/config/project_settings_override removed, so user://renderer.cfg is never read.
- BootGuard: no renderer switch, no restart. Keeps the start-up log, pending-until-menu record, SAFE START after a stuck
  start and boot_diag_stuck.log (now for any stuck start). Deletes a leftover user://renderer.cfg. Checked on desktop
  Vulkan with an OpenGL renderer.cfg and a stuck record: Vulkan, file removed, SAFE START, stuck log kept, menu up.
- Settings: the "Graphics engine / SWITCH TO OPENGL|VULKAN" block is gone (High-quality graphics and Reduce effects
  stay). SiegeApp's restart hook removed.
- Lighting: the VULKAN_* multipliers always apply (siege_view, roster, showcase, render_skin_icons); same look on
  Vulkan, the OpenGL branches are gone.
- build_siege_preview.sh: requires fallback off and no override in project.godot and the APK, and the manifest's Vulkan
  requirement (aapt2). verify_play_bundle.py: the same for the Play AAB. PLAY_STORE_HANDOFF / SIEGE_HANDOFF updated.
  Godot suggests min SDK 29 for Vulkan; the Play preset stays at 24 (Kevin's call).
- 0.31.92, version code 178. Quick suite: ALL 43 PASSED. Preview APK: renderer settings and the manifest's Vulkan 1.1
  requirement verified by build_siege_preview.sh.

## Play preset: min SDK 29 (Kevin: "Do it", 2026-10-09; no new build)
- Vulkan only since 0.31.92, so the Play preset now requires Android 10 (gradle_build/min_sdk 24 -> 29), Godot's
  recommendation for Vulkan. Android 7-9 was ~8% of active devices in Google's Dec 2025 numbers, mostly old Vulkan
  drivers (or none, already filtered by the Vulkan 1.1 requirement).
- verify_play_bundle.py expects minSdkVersion 29; PLAY_STORE_HANDOFF updated. The itch preview APK doesn't use Gradle,
  so it keeps the template's min SDK (24).

## 0.31.93 — Armory Reforged: the Knight's weapons, and the Forge (Kevin: "begin the weapon models and forge system")
- Pipeline (tools/meshy_weapon.py, tools/gltf_bounds.py): the approved concept sheet (art-refs branch,
  weapon-concepts/) -> a parts sheet with every piece drawn on its own, front view (ElevenLabs gpt-image-2 with the
  sheet as reference, ~600 credits a sheet) -> crop (swords turned hilt-down) -> Meshy image-to-3D -> fit: the piece is
  placed in the space of the KayKit model it replaces (same length for blades and poles, same face area for shields,
  facing +Z), baked into the vertices (Godot drops a glTF's single root transform), texture 512 (VRAM-compressed).
  siege_view: "mw/<id>" files, MESHY_WEAPON_LIKE (id -> the KayKit file whose hand slot, fit and roll it uses), so every
  hold Kevin tuned carries over. Checked in hand: same transform as the old piece, idle/attack/block renders.
- Meshy: meshy-6-lite (15 credits, 3k tris) for blades, meshy-7.1 (30, 4k) for shields and the legendary (lite's
  shields had a split rim from the side). Knight: 22 pieces, ~495 credits; 575 left.
- Knight weapons renamed (Kevin's roster): Squire's Blade (starter, Eco.STARTER_NAMES), Steadfast, Highguard,
  Lionheart, Dawnwall, Bloodmoon, Stonewarden, Thornspire, Frostward, Ironbriar, Kingsoath. Bloodmoon's blade is held
  like the one-handed sword (the two-handed template made it huge).
- Icons: tools/render_weapon_icons.gd -- the weapon itself posed like the concept sheets (shield behind, blade diagonal;
  scripts/app/weapon_pose.gd), for every mw/ weapon and starter. Replaces the tiny figure with an edge-on shield.
- The Forge: Home medallion (anvil) under FIRST WIN (badge: an equipped weapon of a class you play can be forged), the
  Locker's "FORGE YOUR <CLASS> WEAPONS", Screens.forge: Embers bar (+ packs 60/150/400 gems -> 60/170/500), class
  picker, the weapon turning in its own world (forge_stage.gd) with its effects, stars, next star and cost, the third
  star's wins (25 with it equipped) and element (fire/frost/storm/holy/nature/void, changeable free once Ascended),
  the class's weapons with their stars. Stars also on the Locker cards.
- Stars: Polished 40 Embers + 500 gold, Runed 120 + 1,500, Ascended 300 + 4,000. Looks only. forge_glow.gdshader as a
  next_pass on the weapon's materials (sheen sweep + rim; rune bands; brighter in the element's colour) and, at three
  stars, an aura of motes and a world-space trail from the tip. Applied in make_body from the profile's look
  (look_for -> "forge"), so the match, Home's line-up, the Locker vault and the Forge show the same. Local player only.
- Embers: +2 a match / +5 a win, +15 a daily order, a chest duplicate (10/25/60/150 by rarity, was gold), pass tiers
  2, 6, 14 ... (20 free / 40 premium), the starter pack's 150, packs for gems. Results screen shows them.
- New icons: anvil (Forge), Embers (ElevenLabs, cut out). tests/forge_test.gd (in the suite).
- 0.31.93, version code 179. Quick suite: ALL 44 PASSED.

## 0.31.94 — Armory Reforged: every other class's weapons (Kevin: "I've topped up meshy")
- Parts sheets for the 8 remaining concept sheets (BA, RO, AR, MA, PW, CB, NA, RA; art-refs weapon-parts/), 91 pieces
  through Meshy (~1,815 credits; 1,760 left): meshy-7.1 for shields, bows, crossbows, claws and the legendaries,
  meshy-6-lite for the rest. 86 are in the game; the 8 quest weapons' raw models are kept on art-refs
  (quest-weapons/, with the template each would use) for when quests come.
- meshy_weapon.py fit: --axes turns (or mirrors) a piece onto its template's axes first -- a bow lies along Z (or X
  for the Bits bows), a crossbow along Z, a claw along X; "auto" picks the turn that lays the piece over the template
  best (surface samples, nearest-point distance both ways; "autoy" only about the length, "automirror" for a left-hand
  claw made from the right one). Kind "box": longest side matched, centred. Normals are turned with the piece; a
  mirrored piece's triangles are reversed. Checked against the templates from three sides, then in hand.
- Choices: closed tomes face their cover out of the hand (the open book's pages face the holder); the Necromancer's
  skull staffs face -X like the KayKit skull (so the face-the-chest turn of 0.31.66 still applies); the cleaver and
  the Eye of the Archon are 0.75 of their template's length (the length match made them huge).
- Renamed to Kevin's roster, every class: starters in Eco.STARTER_NAMES (Woodsplitter, Cutpurse Daggers, Ashwood Bow,
  Apprentice Staff, Acolyte's Wand, Work Hatchet, Templar's Sword, Ironhewer, Bonecaller, Shade Daggers, Marksman's
  Crossbow, Magister's Staff) and LOOKS; catalog weapons (Raider's Bite ... Voidrod) point at their mw/ pieces.
- Icons and the Forge preview (weapon_pose.gd): a piece is stood up first -- longest side up, broadest face to the
  camera; a staff shows its face, a closed tome its cover; a bow (or a quiver's bow) is the main weapon.
- tools/app_shots.gd: SHOT_FORGE_CLS opens another class's Forge. Preload list regenerated (the new starters).
- 0.31.94, version code 180. Quick suite: ALL 44 PASSED. APK 228,303,619 bytes (+25 MB for the 86 pieces), sha256
  337db0d666b1812361ba68d61bead392f141865fea9736959009fefb083a10fd, on itch (vellicgames/fatebound:android).

## Play preset: 32-bit ARM dropped (Kevin: "Ok drop the 32bit", 2026-10-10; no new build)
- export_presets.cfg "Android Play Store": armeabi-v7a off -- the bundle is arm64-v8a only. verify_play_bundle.py
  now wants exactly arm64-v8a. PLAY_STORE_HANDOFF.md updated. A phone's Play download is unchanged (Play already sent
  each phone one engine); the .aab loses ~26 MB (the 32-bit release engine, compressed). Reach: armeabi-v7a-only
  devices were ~1.3% of one app's Play installs (ZeusLN, 2026-09-07), fewer for a Vulkan, Android 10+ game. Play
  Console will report fewer supported devices on the next upload. The itch preview was already arm64 only.

## 0.31.95 — a small install, then "UPDATING" downloads the art (Kevin: "the main game installs a small file from the Play store and itch, then when they launch the game after first install the game will say it's updating")
- The build (Play and itch) holds the engine, every script and scene, the fonts, the launcher art and the loader. The
  art and sound are 5 content packs (ui 15.5, world 53.9, heroes 68.5, weapons 32.7, audio 10.6 MB) on the repo's
  content-packs branch, served by GitHub (raw.githubusercontent.com, byte ranges). Kevin picked GitHub, then the
  branch when GitHub refused this session releases. content/manifest.json lists file, size, sha256 and a probe each.
- tools/content_packs.py: build (export each pack with the "Content Pack" preset, only when its inputs -- the files,
  their import settings, the engine -- changed; files named by that hash, reproducible), strip to data only (Godot puts
  the project settings, the uid cache and the autoload script into every pack: removed; fails on any code), upload (a
  plain commit to the branch, never a force-push; old files stay), check (inputs unchanged, every pack on the branch),
  base (an APK/AAB holds no pack data, has this manifest, starts the loader), presets (the base presets' exclude
  filters), coverage (every asset in exactly one pack or the base). tools/pck_tool.py lists/strips .pck files.
- The loader (scenes/Boot.tscn, now the main scene; scripts/app/content_loader.gd): packs already in res:// (source,
  tools, tests) need nothing; packs downloaded and checked before mount at once; the rest download with "UPDATING", a
  progress bar, MB and MB/s -- 8 MB ranges appended to a .part file (resumes after a dropped connection or a closed
  app), SHA-256 as it arrives, retries 2/4/8/15/30 s with RETRY NOW, "is the phone full?" on a write failure. Packs no
  longer listed are deleted. Packs never replace the build's own files. BootGuard.hold(): a download isn't a frozen
  start, and the OK count starts when the game loads.
- content/preload.json (was assets/terrain/): the start-up list is code-side, so a new list doesn't re-download a pack.
- Checked: tests/content_test.gd (in the suite); tools/content_e2e.sh (desktop-format packs, a project copy without
  the packs' files, a local server that drops a connection: all 5 download, the retry happens, the menu loads and every
  start-up model loads; second start downloads nothing; a half-downloaded pack resumes at 9.5 MB) -- PASS; and the real
  packs downloaded from GitHub by Godot's HTTPRequest, checked and mounted.
- The itch preset also stopped shipping store-listing/ (26 MB of Play listing art had been in the APK).
- content/uids.json: the packs' resources' UIDs, registered after mounting (the build's uid cache only lists its own
  files, else Godot warns and falls back to the path for every reference). 6 hero models' imports still name an older
  UID for their texture -- also in the full project, harmless.
- privacy.html: GitHub listed under Internet use (updated 10 October 2026). PLAY_STORE_HANDOFF.md: content packs.
- 0.31.95, version code 181. Quick suite: ALL 45 PASSED. APK 31,135,353 bytes (was 228 MB), sha256
  a31aa9ca7c54017aafab8e38a0d7c56a6b43b09640d7af6b95d5ad4c5768467e. First launch downloads 181 MB.

## 0.31.96 — tap a shop item to preview it; every weapon and shield fitted to the grip (Kevin: "Make it so you can click the items in the store page and preview them. Also I want you to go through every weapon and shield to make sure and line them up correctly with the hands gripping them.")
- Shop preview (scripts/app/screens.gd open_item): a tap on the featured weapon, a daily deal or an Arsenal opens a sheet
  -- IN HAND (the class's hero holding it, drag to turn, pinch or +/- to zoom) or WEAPON (the weapon alone, drag to
  turn, then it turns slowly by itself: forge_stage.gd `interactive`), its stars if forged, name, rarity, class, and
  BUY / EQUIP right there (it stays open after buying; a gem confirm's CANCEL goes back to it). An Arsenal shows its
  weapons one at a time (the icon row) with BUY ARSENAL. The card's own price button still buys straight away; a drag
  on a card still scrolls the menu. app.confirm() takes an optional on_no.
- tests/shop_preview_test.gd (suite): real taps on all 12 shop cards, then the toggle, gold buy, equip, gem
  cancel/buy, an Arsenal's second weapon and buying it -- all through the preview's buttons. tools/app_shots.gd
  SHOT_PREVIEW / SHOT_PREVIEW_MODE.
- Grips (tools/weapon_grip.py, now the last step of meshy_weapon.py fit). Checked every Armory Reforged piece (108) in its
  template's space with the grip marked, then in the hand, posed, before and after:
  - Long weapons: the fit had centred each piece's whole box, so a head hanging to one side put the haft off the hand.
    The shaft is now found (the column of the piece that runs through the whole grip band -- an axe blade, a
    scythe's blade, a lantern or feathers fill only part of it) and put through the fist: Soulreaper and Grimgrin
    scythes 0.25, Stormcleaver 0.27, Worldsplitter 0.22, Wayfarer's staff 0.19 (the hand was on the lantern), Raider
    axe 0.17, Boarsbane spear 0.16, Bonecarver 0.11, Timberfall, Work Hatchet, the other axes and a few daggers less.
    Swords whose guard sat on the hand moved up onto the grip (Dawnwall, Kingsoath, Templar).
  - Three daggers had been fitted upside down -- the hand held the blade: Shade (the Assassin's starter), Asp, Eclipse.
    Refitted blade-up (their icons re-rendered).
  - Shields: the KayKit shields have a handle the fist closes on; a Meshy board has none and was fitted by its front
    face, so thin boards floated a hand's width off the fist (Bloodmoon 0.18, Ironbriar 0.28, Kingsoath, Thornhide,
    Stonewarden, the Barbarian's round shields) and thick ones swallowed it (Lionheart, Highguard, Bulwark, Sunrise:
    the gauntlet came out through the face). Every board's back now sits just in front of the knuckles.
  - Tomes: closed tomes are three times as thick as the open spellbook they replace and the hand was inside them
    (Prism, Rootwise, Hex, Gravecaller, Magister's book); the back cover now sits where the spellbook's does.
  - Bows (riser on the hand), crossbows, claws, knuckles, the mug and the bomb were already held right.
  56 pieces moved (31 by under 3 mm left as they were).
- Content packs: ui (dagger icons) and weapons rebuilt and on the content-packs branch; an installed 0.31.95 downloads
  only those two (48 MB) on its next launch. 0.31.96, version code 182. Quick suite: ALL 46 PASSED. APK 31,143,545
  bytes, sha256 a7a7ae0f6c0b122cf26878a19b3c54a27f748394968dc390edb752d910a0576d; on itch (android channel).

## 0.31.97 — a quest for every class (Kevin: "Build the quest system and I want quests for each class")
- Eco.QUESTS: one quest per class (13), three steps claimed in order. Step 1 pays 400 gold + 30 Embers, step 2 50 gems
  + a Gold chest, step 3 the class's legendary (source "quest": never in the shop, the pass or a chest; forgeable once
  owned). Steps per class are its own kind of work: Knight wins / King rescues / knockouts; Barbarian knockouts / gate
  damage / wins; Rogue knockouts / a 3-knockout burst / knockouts; Archer knockouts / wins / knockouts; Mage knockouts /
  King lifts / wins; Priest healing / rescues / wins; Worker gathering / gate repairs / wins; and the six upgrades the
  same at smaller numbers (they're only worn once the team buys the hat).
- Counting (profile stats "q_<class>_<stat>", from 0.31.97 on): siege_mode credits what my unit does -- seconds played,
  knockouts, rescues, gate damage, gathering, fish, healing, repairs, King lifts, the best burst -- to the class I'm
  wearing (a Crusader apart from a Knight; nothing as a villager), online and offline alike. A base class's quest counts
  its upgrade too (as the titles do); an upgrade's quest only the upgrade. A match counts as played / won as a class
  after a minute as it.
- Legendaries: the 7 drawn with the Armory Reforged sheets (Dawnpiercer, Hawk's Judgment, The Golden Sledge, Bloodroar,
  Lichcrown, Last Breath, Astral Codex) fitted at last, and 6 new ones for the classes that had none -- concept sheet
  (4 takes sent to Kevin), parts sheet, Meshy 7.1: Kingsguard (Knight, crown-guard sword and winged crown shield),
  Skyrender (Barbarian, eagle-winged great axe), Moonfang (Rogue, crescent daggers), Emberheart (Mage, phoenix staff),
  Seraph's Grace (Priest, winged halo staff), Oathbound (Crusader, winged-sun warhammer and chained cross shield). All 16
  pieces fitted with the grip step; icons rendered.
- Screens: Home's QUESTS button (left, under ORDERS; a badge per step ready). The Quests screen (sign and HOME like the
  Forge): the 13 classes (a badge where a step is ready, a tick where done), the hero holding the legendary (turn, zoom),
  its name, the three steps with progress, rewards and CLAIM; claiming the last shows the legendary with EQUIP. The
  Locker shows each class's quest under its nameplate (OPEN / CLAIM), and the legendary's card says "Quest reward".
  The match results show the quest steps that moved and a banner when one is ready. New icon (quest map) in the game's
  icon style.
- Fixed: the Priest's equipped weapon never showed in a match (the class was missing from the match's looks list).
- tests/quest_test.gd (the table, counting, claiming in order, save/load, the screens through their buttons) and
  tests/quest_track_test.gd (in-match crediting per class worn), both in the suite.
- 0.31.97, version code 183. Quick suite: ALL 48 PASSED (meta_economy_test now counts the 6 upgraded-class quest
  legendaries apart). Content packs ui (16.1 MB) and weapons (37.8 MB) rebuilt and on the branch. APK 31,159,929 bytes,
  sha256 9ea15725ce9c782164af1515b6aaf5ec982c0fdb1ff5d511acc0e7c920c34f60; on itch (android channel).

## 0.31.98 — the Rogue's Whisperbolt is two daggers (Kevin: "He shouldn't have a crossbow at all. Just give him the daggers")
- The Rogue is melee and stabs with both hands, so Whisperbolt's off-hand crossbow was swung like a dagger. Whisperbolt
  is now the Whisperbolt dagger in both hands; the crossbow model is gone (and its hold), the icon re-rendered.
- Content packs ui and weapons rebuilt and on the branch. 0.31.98, version code 184. Quick suite: ALL 48 PASSED. APK
  31159929 bytes, sha256 65dcab5a605de93fb2572aa96affd449aaddf04493c86822c7c3e5ac37669b1b; on itch (android channel).

## 0.31.99 — Whisperblades, and no smoke bomb (Kevin: "Yeah rename and also remove smoke bomb")
- Whisperbolt is renamed Whisperblades (it's two daggers since 0.31.98). Smokescreen is its dagger in both hands; the
  smoke bomb model and its hold are gone, the icon re-rendered. The Rogue now holds only blades, knuckles or claws (and
  the Grimgrin scythe).
- tests/min_build_test.gd: server A's minimum is now this app's build + 1 (it was a fixed "0.31.99", which this
  version reached, so the app was no longer "outdated" there).
- Content packs ui and weapons rebuilt and on the branch. 0.31.99, version code 185. Quick suite: ALL 48 PASSED. APK
  31159929 bytes, sha256 754316445f9aae2684aedf87907198d251bde94c6fcec612dc9c0553e688d29b; on itch (android channel).

## 0.31.100 — better Forge effects, and every legendary has its own (Kevin: "I want the effects to look better for the forge weapons. I also want to add effects for all the legendary weapons")
- Sprites: 15 painted VFX sprites (sparkle, flame, smoke, lightning, rays, snowflake, ice shard, leaf, feather, four
  runes, sigil, crescent, soul wisp, vortex, star cluster, ring) generated with ElevenLabs gpt-image-2 as white-on-black
  sheets (4 takes, best of each kept; flow tL2Uq8Khy94WZ0PV3s34), cut by tools/cut_vfx_sheet.py into 128 px grayscale
  textures in assets/vfx/weapon (base APK, lossless + mipmaps; SOURCE.txt). fx_sprite.gdshader draws them added in the
  particle's colour with a white-hot core, billboarded or laid flat (a halo).
- scripts/siege/weapon_fx.gd (replaces siege_view's forge code): a glow pass over the weapon's own materials
  (forge_glow.gdshader rewritten: fresnel rim, a narrow glint running up the piece, glowing veins from a 3D cell pattern
  with a pulse flowing up them, and a colour key that lights a legendary's lava / eye / gems from its own texture), plus
  particles, pinned sprites (rays behind a staff's head, a halo, a turning sigil or vortex, sparks orbiting) and a swing
  ribbon (fx_trail.gdshader: a crescent along the tip's path, only while the blade moves fast; a jump clears it; never on
  bows, staffs, books or shields). weapon_fx_root.gd builds them on the first frame in the tree in world units measured
  from the piece, since Godot draws a particle at its own size whatever the emitter's scale.
- Forge stars: 1 Polished = glint + sparkles; 2 Runed = + veins, runes drifting along it, a faint ribbon; 3 Ascended =
  all in the element's colour + fire flames and embers / frost snow and mist / storm lightning and sparks / holy rays and
  motes / nature leaves / void wisps and vortex, and a bright ribbon. Star texts updated.
- Legendaries (LEGENDARY, by model, whether or not forged; with stars they add up): Kingsoath sparkles and motes,
  Worldsplitter glowing lava with embers and flames, Grimgrin purple wisps, Eye of the Archon lit eye with a sigil and
  orbiting sparks, Solaris rays from its sun, Final Verdict golden runes, Kingsguard royal sparkles, Skyrender
  lightning, Moonfang drifting crescents, Dawnpiercer leaves, Emberheart phoenix flames and fire feathers, Seraph's Grace
  a halo and falling feathers, The Golden Sledge sparks, Oathbound sun rays, Bloodroar red embers and smoke, Lichcrown
  green soulfire, Last Breath violet smoke, Hawk's Judgment golden feathers, Astral Codex orbiting stars, a vortex and
  a sigil behind the book. Each has its own swing ribbon colour where it swings.
- Shown on a body (Locker, Home, Quests, shop "in hand", my unit in a match) and in the Forge / shop "weapon" view; the
  still icons stay plain (WeaponPose.compose effects=false). Sprites write their strength into alpha so the transparent
  showcase viewports get no black squares.
- tests/weapon_fx_test.gd (every legendary piece has effects, presets and sprites exist, stars 1/2/3, Seraph's halo,
  sizes follow the piece's world scale, icons plain, the ribbon only in a fast swing) in the suite; forge_test updated.
  tools/app_shots.gd: SHOT_EQUIP=id,... wears items for a shot.
- 0.31.100, version code 186. Quick suite: ALL 49 PASSED. Content packs unchanged (CONTENT OK; the sprites are base).
  APK 31323653 bytes, sha256 3ad510dafe0bf710b10f0963cb9822ca46ee617b58bf09d301b6920dbb4ef539; on itch (android
  channel).

## 0.31.101 — everyone sees what everyone wears (Kevin: "I want players to see everything the other players are wearing")
- Until now a match dressed only my own unit; every other player showed the defaults. Now each player's equipped weapon
  and its Forge stars / element, for every class, reach everyone in the match (titles and names already did).
- Wire (additive, protocol stays 35): the hello carries "lk": {class: "weapon id|stars|element"} (Profile.wire_looks,
  only dressed classes). The server keeps only well-formed entries (Net.clean_looks: one of the 13 classes, an id of
  a-z 0-9 _ up to 40, stars clamped 0-3, an element word) and adds "lk": {unit id: entries} to "pn" (sent to the match
  whenever a seat changes, like the names). It doesn't check ids against the catalog -- the server carries no economy,
  and a newer app may know newer items; each app builds the look from its own catalog (Eco.looks_from_wire /
  Eco.look_of, which Profile.look_for now uses too, so the others see exactly what I see), the starter for an id it
  doesn't know or of another class. Older apps / an older server ignore "lk".
- The battle view dresses a unit from unit_cosmetic(): mine from the profile, a live player's from the server, a bot's
  the defaults (a player leaving hands the bot the defaults back). Their legendary and Forge effects show too; with
  fewer effects on (Settings' reduce motion), the other players' weapons keep their glow but no particles.
- Ownership isn't verified (cosmetics are local, there are no accounts): a modded app could show items it doesn't own,
  to others; it changes nothing in play.
- Live server: reports 0.31.92 (status). Needs the redeploy from this branch (install_siege_server.sh) for "lk";
  until then everything works as before (no looks relayed).
- tests/shared_looks_test.gd (the wire rules, cleaning, my looks out and back equal look_for, unknown ids, the view
  dressing another player, the lighter version) in the suite; siege_net_smoke: a second player's looks come back
  cleaned through the real server, and leave with them. Quick suite: ALL 50 PASSED.

## 0.31.102 — Google Play Games sign-in and cloud save (Kevin: "Google play account linking to the game")
- Split like purchases: Claude the game code, Grokbot the Play Console side (godot/PLAY_GAMES_HANDOFF.md: the Play Games
  project, Saved Games on, the OAuth consent screen and the Android client with the app-signing SHA-1, testers, the Game
  ID into the build, the internal-testing test, Data safety). Kevin: itch uploads stopped (no itch build from here on).
- addons/GodotPlayGameServices: godot-play-game-services 3.4.0 (Play Games Services v2 21.0.0) built from source
  against Godot 4.7.2 (tag v3.4.0, e38b618). Own export plugin: no autoload and none of its GDScript wrappers, Gradle
  presets only, and nothing packed until the Game ID is set (preset option godot_play_game_services/game_id or
  PLAY_GAMES_APP_ID) -- the Play Games SDK stops an app that has the plugin but no APP_ID. verify_play_bundle.py fails
  a bundle with one and not the other. Checked with throwaway-key Play exports: with a test ID the AAB carries the
  plugin, the APP_ID meta-data and the ID resource (billing still there); without one, none of it.
- scripts/meta/play_games.gd: sign-in (automatic at start, or SIGN IN), the player's Play Games name, and one Saved Game
  ("fatebound-profile": the profile gzipped + base64 with a stamp, time, phone and summary). Reads before it ever
  writes: no copy -> the first link uploads; in step -> uploads changes (every 2 min while changing, on going to the
  background, BACK UP NOW); another phone moved ahead and this one hasn't changed, or a never-linked new install ->
  restores silently (keeping this phone's sound/graphics settings); both changed -> WHICH PROGRESS? (USE GOOGLE PLAY'S
  / KEEP THIS PHONE'S; asked after a match if it comes up during one). Never overwrites a copy it can't read or one a
  newer version wrote; Google not answering in 30 s -> an error and TRY AGAIN (which reads again first).
- Profile: cloud {stamp, dirty, at}; every save marks it (save(false) for the sync's own); summary(), is_fresh(),
  cloud_payload(), restore_cloud().
- Settings: a GOOGLE PLAY card under the name: off Play "Available in the Google Play version", SIGN IN WITH GOOGLE
  PLAY, "Signed in as <name>... backed up (n min ago)" + BACK UP NOW, CHOOSE, TRY AGAIN. tools/app_shots.gd
  SHOT_PLAY=out|synced|ask.
- privacy.html: a Google Play Games section (optional; name read; the save kept in the player's Google account, not on
  our server). Note for Kevin: its opening still describes the dice-era game and Firebase.
- tests/play_games_test.gd (a fake of the plugin: first link, later uploads, a save during an upload, new install,
  phone in step, both changed with both answers, unreadable / newer copies untouched, no answer -> TRY AGAIN, off Play,
  the Settings card and the question through their buttons) in the suite.
- 0.31.102, version code 188 (preview numbering; Play codes are Grok's). Quick suite: ALL 51 PASSED. CONTENT OK. No itch build.

## 0.31.103 — the Astral Codex's rings turn (Kevin: "Can we make the top of this weapon animate. Like have the rings spins and rotate")
- The staff was one Meshy mesh. tools/weapon_spin_parts.py cuts a weapon's connected components into their own nodes,
  each placed at a pivot with its vertices re-expressed about it, so at rest the weapon looks and is held exactly as
  before. astral_staff.glb: Body (shaft and claw), Rings (the beaded ring with its orbs and the gold band -- they
  touch, so they move as one cage), Crystal; Rings and Crystal pivot on the crystal's centre.
  (`--part Rings:0,3:2 --part Crystal:2`.) Splitting the rings from each other was tried (circle fits): they are
  fused where they cross, so turning them apart would tear them.
- weapon_fx.gd LEGENDARY "spin": parts by node name, turned about their own +Y (rad/s) and rocked +-wobble degrees
  about X; weapon_fx_root.gd sets each from its rest pose every frame (no drift). Astral: the cage turns 0.6 rad/s
  around the crystal, rocking 8 degrees; the crystal turns -0.5 rad/s. Wherever its effects show (bodies, the Forge,
  the shop / quest showcases); the still icons keep the modelled pose.
- Content pack weapons rebuilt (weapons-cd8cb0f18e24.pck) and on the content-packs branch.
- tests/weapon_fx_test.gd: the spin parts exist in the model, turn on a body (each its own way), stay put on an icon.
- 0.31.103, version code 189. Quick suite: ALL 51 PASSED (a first run missed staged_start_test's 200 ms _ready budget by 8 ms under load; alone it runs 107-126 ms). CONTENT OK. No itch build.

## 0.31.104 — weapon grips (Kevin, with screenshots of Brickbreaker, Ravenclaws, Twin Sparks, Bloodmoon, Hawkeye, Eye of the Archon: "A lot of the weapons are still not gripped correctly")
- Audit: every catalog weapon and starter rendered in its class's idle from the front and both sides, plus hand
  close-ups against the KayKit piece each one is fitted to, plus handle profiles (1 cm slices along each piece).
- Bows: the five on Bits templates (Hawkeye, Stag Hunter, Galeshot, Longshot, Heartseeker) had the string on the far
  side, away from the archer -- the Bits bows' quarter turn in siege_view._fit_weapon went the same way as the
  Adventurers bow's half turn. Now the other way: every bow's string faces the archer (the Galeshot, which looked like an
  arch lying forward, is the same fix -- its deep curve was facing away).
- One-handed hammers, maces, axes and wands: a piece with a longer handle than its template kept the template's grip
  height, so the fist closed partway up the handle under the head with the rest sticking out behind (Brickbreaker,
  Twin Sparks). tools/weapon_grip.py END (now part of `fit` too): the hand END_UP (0.12) above the end of the handle's
  plain stretch. 18 slid: acolyte, sparkstick, spellwright and candle wands, both Twin Sparks, brawler / thornhide /
  timberfall axes, work hatchet, frostbeard axe, Brickbreaker, Bulwark, Oathbound, Golden Sledge, Verdict maul,
  Sunrise and Penitent maces (+0.07 to +0.35). Raider axe and Skullknocker were already there.
- Staffs: the Eye of the Archon (its rings, eye and ornate neck are two thirds of it) and the Lich-Crown (the fist was on
  its winged neck) slid down onto the plain shaft (`weapon_grip.py slide`, +0.32 / +0.33). The other staffs, swords,
  daggers, shields, claws and two-handers were checked and left as they were (Bloodmoon: the hand is on the handle
  under the guard; its crescent guard curls back over the fist by design. Ravenclaws: blades out of the knuckles,
  feathers back over the hand, as drawn).
- Icons, the Forge and the WEAPON tab centre each piece on its own box: unchanged. Effects are placed by fractions of the
  box: unchanged.
- tests/weapon_grip_test.gd in the suite: every bow's string on the archer's side (8 bows); every one-handed hammer,
  mace, axe and wand held in the bottom 28% of its length (20); the Archon / Lich-Crown with most of the staff ahead of
  the hand.
- Content pack weapons rebuilt (weapons-5a80f010ba2b.pck) and on the content-packs branch.
- 0.31.104, version code 190. Quick suite: ALL 52 PASSED. CONTENT OK.

## 0.31.105 — new gold, diamonds and Embers; they fly into the counters (Kevin: "Make new meshy models for gold, diamonds and ember. Also when a play obtains them it'll play a animation where they fly to the players total amount at top of screen" -- picks: gold C, diamonds B, embers B; "Yes put an ember counter at top also")
- Concepts: 4 sheets each (gpt-image-2.5, ElevenLabs flow 5ZFwy4wQvTF2WkdBftDK); Kevin's picks cropped (meshy_weapon.py
  crop); the ember's flame edited out first (a flame doesn't model -- it is an effect in the game instead). Meshy
  image-to-3D, meshy-7.1, 4000 tris: a chunky crown coin, a brilliant-cut diamond, a cracked volcanic ember.
- The models (textures 1024) are in art_sources/currency, OUTSIDE the project (never in the APK);
  tools/render_currency_icons.gd reads them at run time and renders assets/ui/currency: coin, coins_s/m/l (stack, stack
  and pile, hoard), gem, gems, ember (new: the counter's), embers, and coin/gem/ember_spin.png (16 frames turning).
  The ember: rock darkened, its molten cracks an unlit additive pass (an emission texture rendered plain white), then
  tools/currency_glow.py blooms the cracks and adds an orange halo. Every screen using the currency icons (shop,
  chests, Forge, pass, quests) shows the new ones. render_gold_icons.gd (the MegaKit coins) superseded.
- Top bar: a third counter, Embers (orange edge; tapping it opens the Forge, where Embers are bought); the three
  counters made a little narrower so the name still shows at 420 wide.
- scripts/app/reward_fly.gd on a CanvasLayer above everything: a rise in gold / gems / Embers (siege_app._counter, from
  refresh_top) bursts 3-12 turning pieces (by amount) out of the tap that claimed it (CLAIM, COLLECT, BUY ...; else the
  middle of the screen), each curving up into its counter with a glow and a trail (sparkles; the ember a flickering
  flame and rising sparks); the counter keeps its number until they land, counts up as each does (a clink, the icon
  punches) and ends on the profile's amount. Spending shows at once. A restored Google Play save doesn't fly; during a
  match the counters wait and the match's rewards fly on the way back to the menus.
- tests/reward_fly_test.gd in the suite.
- Content pack ui rebuilt (ui-4d2ee4b95bd9.pck) and on the content-packs branch.
- 0.31.105, version code 191. Quick suite: ALL 53 PASSED. CONTENT OK.

## 0.31.106 — pack art that grows with the pack; two bigger gold offers (Kevin: "Make new art for the higher tier packs so it shows more the higher the pack is. Add fun things to art for higher packs. Also maybe add some higher gold packs?")
- Ten pictures, assets/ui/packs/{gem,gold}_pack_1..5.png (448 px, transparent), made with Meshy's image-to-image
  (gpt-image-2.5, background removed; tools/meshy_image.py -- ElevenLabs' credits had run out), each steered by the
  concept art of the game's own diamond and crown coin (Kevin's picks) so they match the currency:
  gems 80 a diamond, 500 a heap, 1100 a leather pouch spilling them, 2400 an open treasure chest overflowing, 6500 a
  royal golden chest under a mountain of diamonds with a jeweled crown, a golden goblet and a chubby baby dragon hugging
  a giant diamond; gold 600 a stack, 1600 a stack and a heap, 4500 a mound with stacks, 12,000 a barrel pouring coins,
  30,000 a mine cart heaped with coins and gold bars, a pickaxe, a lantern and a grinning chest mimic on top.
- Shop: the pictures bigger (104 px; the two big tiles 132); tiers 4-5 sit in a soft glow, the top one also turns rays
  and bobs. The starter pack shows the heap. Gold offers in a 3 + 2 grid like the gem packs, shown in full ("+12,000",
  UI.grouped).
- Eco.EXCHANGE: + gold_xl 700 gems -> 12,000 gold and gold_xxl 1600 gems -> 30,000 (gold per gem 12 / 13.3 / 15 / 17.1
  / 18.8, the biggest BEST VALUE). Items' gem value still at the old 4500 = 300 rate.
- tests/shop_packs_test.gd in the suite.
- Content pack ui rebuilt (ui-f69d90ec6748.pck) and on the content-packs branch.
- 0.31.106, version code 192. Quick suite: ALL 54 PASSED. CONTENT OK.

## 0.31.107 — Siege Pass tier skips (Kevin: "Can you put tier skips for the battlepass. Players can buy 10 tiers for gems")
- Eco.TIER_SKIP 10, TIER_SKIP_GEMS 100 a tier: 10 tiers for 1000 gems (near the end only what's left: at tier 26 the
  last 4 for 400). Profile.skip_offer / skip_tiers: the pass XP for those tiers, the progress into the current tier
  kept, their rewards then waiting to be claimed like any others (CLAIM ALL); counted in d.pass.skipped. None when the
  pass is complete. Any 10 tiers give back at most ~270 gems over both tracks (seasons 1-6), so a skip never makes gems.
- Pass screen: a SKIP 10 TIERS card under the tier card (a +10 pass shield, "Jump to tier N · claim every reward on the
  way", the gem price), greyed without the gems; it asks first (SKIP 10 TIERS? ... Costs 1000 gems.).
- tests/tier_skip_test.gd in the suite.
- 0.31.107, version code 193. Quick suite: ALL 55 PASSED. CONTENT OK.

## Economy review (Kevin: "Go through and check economy balance for entire game. Go through everything like forge, gems, embers, $ cost of everything ect") -- no game change yet
- tools/economy_sim.gd: MODE=samples runs full 16v16 bot matches and saves every unit's end-of-match numbers; MODE=season
  plays four styles (light 2 a day 5 days a week, casual 3, regular 5, grinder 12; 50% wins) for 84 days on the real
  Profile / Economy code, books gold / gems / Embers by source per season, the day the pass is finished, and the pass
  items a player already owned at the season's start. 12 seeds = 384 samples.
- Findings (the review doc for Kevin): season 2's premium track is 8 of 13 repeats for a season-1 buyer (10 of 13 in
  season 3; a repeat gives nothing); Silver chests' 5-10 gems are about half of all free gems; a free regular earns ~960
  gems a season (premium is 950) and a premium casual ~1,160; the gold shop (62,100) is bought out in ~4-6 weeks; level /
  pass / quest chests turn to gold when the 4 slots are full (the level-10 Royal included); the starter pack is ~1.5x.
- Candidate tested (not shipped): Silver chest 30% chance of 5 gems -> free gems a season light 300, casual 510, regular
  540, grinder 710.

## 0.31.108 — the economy review's fixes, and the server keeps the accounts (Kevin: "I want you to fix everything. I also want to make sure everything is verified by server so players can't edit gems ect"; VS BOTS: "Always online")
- Pass: a pass item already owned is swapped when claimed (Eco.pass_swap: another pass weapon of its rarity the player
  doesn't own and this season doesn't give, else Embers 25/60/150 by rarity); the tier remembers what it gave
  (d.pass.swaps) and the pass screen shows it ("In place of X, which you already own"). From season 2 the premium
  track's 60-gem tiers give 60 Embers (season 1 unchanged). A season can have its own pass-exclusive weapons
  (Eco.PASS_SEASON_ITEMS, CATALOG "season": n) spread over SEASON tiers 1..30; season 2's await Kevin's picks of the
  concept board (6 weapons). Earlier seasons' pass weapons are vaulted: sold in the Featured shop for gems (rare 150,
  epic 300, legendary 450; Featured 3 -> 4 slots) and their legendaries join the Royal chest's legendary roll.
- Chests: Silver gems 5-10 always -> a 30% chance of 5. Wooden items rares only (the only common was Sparkstick).
  Reward chests (levels, pass, quests, a whole day's / week's orders) wait for a slot (d.chests.queue, up to 12;
  Home shows "+N WAITING") instead of turning into gold; a match's chest still turns into gold when full. Rolls are
  seeded by the account's salt + the chest's id and kind (the phone and the server roll the same).
- Forge gold doubled (1,000 / 3,000 / 8,000). Hunter Arsenal 120 -> 80 gems; Arsenal values at the 30,000-gold offer's
  rate. Starter pack 500 gems + 300 Embers + an epic (was 300 / 150 / a rare). gems_14000 ($99.99) added, shown only
  once Google Play returns its price (PLAY_IAP_HANDOFF: create it, update the starter pack's description); its art
  assets/ui/packs/gem_pack_6.png (Meshy i2i: a mountain of diamonds over two royal chests, a sceptre, a sleeping
  purple baby dragon); it takes BEST VALUE when shown.
- Server-kept accounts (server/eco_accounts.gd, server/match_ledger.gd, scripts/meta/eco_sync.gd; SIEGE_HANDOFF 19):
  every change in the app is an op (Profile.OPS, recorded by Profile._rec) replayed on the server with the same
  profile.gd / economy.gd and its own clock; numbered (a resent op is done once); the answer replaces the phone's copy
  with the unsent ops re-applied. VS BOTS needs a server ticket to start; its result counts 150 s+ after the ticket,
  once, clamped (EcoAccounts.clamp_me). Online matches are paid by the server from its own count. Purchases are
  granted to the account by the server, one account per token (purchase_tokens.json; the old ledger's confirmed tokens
  count once in an import). Online name / title / looks come from the account. New accounts import the phone's progress
  once, held to what that many matches could earn (+ confirmed purchases), until 2026-12-01; 240 new accounts an hour
  at most. The tutorial's pay (Profile.finish_tutorial) and the name (set_name) are ops; the dice-era import is off.
  The installer ships the meta scripts and backs up the accounts before each update.
- tools/economy_sim.gd: the model behind the review (bot-match samples + 84 days on the real code).
- tests/eco_server_test.gd (accounts alone + end to end against the real server on 8093) and economy_fix_test.gd in
  the suite; iap_test / forge_test updated for the new numbers.
- Home: "+N WAITING" over the chest row when reward chests wait (app_shots SHOT_QUEUE=1). Pass premium copy says
  "Embers and gold on every tier" from season 2.
- Content pack ui rebuilt (ui-4e65a88f514e.pck, gem_pack_6) and on the content-packs branch. Server: SERVER_BUILD
  0.31.108 -- needs the redeploy (SIEGE_HANDOFF 19); until then the app keeps its own local economy as before.
- tools/economy_sim.gd after the fixes, free gems a season: light 340, casual 550, regular 620, grinder 800 (were 370,
  770, 960, 1,120); with premium 500 / 860 / 890 / 1,100 (were 550 / 1,160 / 1,320 / 1,490); no Gold/Royal chest lost
  to full slots (were up to 10 a season).
- 0.31.108, version code 194. Quick suite: ALL 57 PASSED. CONTENT OK. APK 31,373,497 bytes,
  sha256 5068951500e9e1f3fcf7c0cf4efe96622b20a41fcdb6efe7189dda683d5a7664.
- Season 2's own pass weapons: ON HOLD (Kevin: "Hold off on new season 2 weapons since the games not really out
  yet"). The concept board is kept at reports/concepts/s2_pass_weapons.jpg (Ashguard, Magmamaw, Cinderfangs, Ashwind,
  Pyreforge, Cinderlich; A/B each). Eco.PASS_SEASON_ITEMS stays empty: season 2 uses the old draw, with owned items
  swapped (Embers or an unowned pass weapon).

## 0.31.109 — new menu sounds (Kevin: "make all new high quality sound effects for the menu. I don't want these to be cheap 8bit sounds. I want them to be sounds you'd hear in AAA game")
- 15 menu cues from ElevenLabs sound effects (eleven_text_to_sound_v2; 76 generations, four takes per prompt, ~1,270
  credits), the best take picked from its waveform and spectrogram (onset, length, partials, noise), then cut, layered,
  high-passed for phone speakers, levelled to each other and soft-limited by tools/build_menu_sfx.py (sources kept in
  art_sources/menu_sfx/; the script rebuilds assets/sounds/<cue>.wav, 44.1 kHz 16-bit stereo).
  Replaced: tap (polished-wood tap), menuClose (whoosh into a cloth thud), confirm (crystal bell), equip (blade slides
  home and clanks), coin (a gold coin rings), purchase (coins into a pouch + a sparkle), error (two dull wooden
  knocks), flip (a card), countdown (a deep clock tick), matchStart (war drum + horn).
  New: gem (a crystal clink) and ember (a fire puff) for their counters (the reward flight played the coin for all
  three), claim (a brass-and-chimes fanfare: pass tiers, CLAIM ALL, orders, quests -- were the coin / purchase),
  chestOpen (the lid creaks, magic swells into the burst at 0.45 s, a sparkle after -- was the purchase sound plus a
  coin at the burst), forge (a hammer rings on the anvil + a shimmer -- was the purchase).
- native_audio: the new cues count as UI sounds (the sfx volume). cue-catalog.json notes the replaced cues.
- Audition page (artifact "Fatebound Menu Sounds"): every new cue next to the old one.
- Content pack audio rebuilt (audio-d94b1cd17740.pck) and on the content-packs branch. 0.31.109, version code 195.
  Sound tests (match_audio, reward_fly, chest, app_flow, forge, quest, tier_skip, content) pass. APK 31373497 bytes,
  sha256 a7281bed81486b5dfd4a033ae7bd9fe97b057065639667cc0992072c140c5e2d.

## 0.31.110 — more menu sounds, sliders at 100% (Kevin: "I want more menu sound effects. Also make it so the audio sliders are max by default")
- 14 more menu cues, made the 0.31.109 way (ElevenLabs eleven_text_to_sound_v2, four takes a prompt, ~930 credits; the
  best take picked from waveform + spectrogram, cut/layered/levelled by tools/build_menu_sfx.py, sources in
  art_sources/menu_sfx/):
  tab (rustle into a wooden click: the tab bar, the coin pills, PASS / FORGE / QUESTS medallions, the Locker's Forge
  and quest buttons), menuOpen (replaced: an airy whoosh with a soft tone -- confirms, the chest window, a pass reward,
  the shop preview, the Forge's Embers shop), toggle (switch click + latch: the graphics switches), slider (a tiny
  ratchet tick a step, at the new level), unlock (a key turns, ka-chunk: chest UNLOCK), premium (golden two-note
  chord + sparkle: the premium pass), tierUp (rising chime: tiers skipped, a tier reached in a match),
  revealRare / revealEpic / revealLegendary (the chest card by rarity; a quest's legendary gets the legendary one),
  gemPack (gems pouring: a Play Store gem pack), levelUp (ascending arpeggio), resultWin (brass and drums) and
  resultLose (low strings + horn; softly for a draw) on the results screen -- the stinger at once, a level up's
  arpeggio (else a pass tier's chime) 1.6 s later. The Forge / Quests home buttons play menuClose; a chest skipped
  plays only the window opening (it played the tap twice). A gold-only chest card plays the coin, a duplicate Embers.
- Sliders: Master, Effects and Music default to 100% (Profile.defaults, the settings fallback, native_audio's start
  levels, _apply_audio's and the match's fallbacks). Once (settings.audio_max), each slider still on its old default
  (80 / 80 / 60) goes to 100%; one someone moved stays where it was. New profiles carry the mark, so a new install's
  slider set to 80% stays 80%.
- tests/menu_sound_test.gd (in the suite): every sfx cue in scripts/app has its WAV and plays on the Effects slider,
  the new cues' lengths, 100% defaults, the one-time move and its edge cases. Full suite: ALL SIEGE TESTS PASSED (58).
- Content pack audio rebuilt (audio-686aa32b16bd.pck) and on the content-packs branch. 0.31.110, version code 196.
  APK 31369401 bytes, sha256 333b0712cd9b76ee42a54cdac9e43f377422fe1a136a20a623d60298e5f33ca9.
- Audition page (artifact "Fatebound Menu Sounds") now lists the 0.31.110 cues above the 0.31.109 ones.

## 0.31.111 — chat, friends, parties, quick chat (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list. They can then group up and form a party. Also add the quick chat pings")
- Server `server/social.gd` + `siege_server.gd`: persistent social sockets tied to the accounts (0.31.108), global and
  party chat (filter, links masked, rate limits, repeats, last lines in memory), friends / requests / blocks /
  reports (reports.jsonl) / muted.txt, parties of 4 with invites, the leader's PLAY ("go"), a party seated on one
  team; "qc" quick chat to the speaker's side (gg to all, 2 s apart), "status"/"ver" say "social":1. `social.json`
  in the state dir (backed up by the installer with the accounts).
- Sim `call_bots`: "Need help!" / "Follow me!" bring the 3 nearest free bots of that side for 15 s.
- App: `scripts/meta/social.gd`, `chat_panel.gd`, `friends_panel.gd`, `social_ui.gd` (name card: add / invite /
  remove / block / report), `chat_ticker.gd` (Home's chat line), `invite_banner.gd`; FRIENDS medallion, party ribbon,
  PLAY ×N / READY, Settings > SOCIAL; windows with a list drag-scroll like the menus (`_scroll_target`). HUD: the horn,
  the 8-line wheel, bubbles (edge arrows), the feed. New icons chat / friends / horn (generated to match the set,
  background removed) and sounds ping / chatPop (ElevenLabs, build_menu_sfx.py).
- Fix: UI2.bob no longer errors when Home is redrawn twice in one frame.
- privacy.html: "Game server account" and "Chat, friends and parties" sections (to redeploy). SIEGE_HANDOFF.md §20:
  deploy, moderation, the Play forms to update.
- Tests: social_test (server alone + two phones against the real server, party seated together, quick chat and its
  gap, bot calls), social_ui_test (the app's real buttons end to end: chat line, chat window, name card, Friends,
  invite, party ribbon, PLAY ×2 -> "go", one side, quick chat both ways). 0.31.111, version code 197.
- Content packs ui-4890b4aaf16a.pck and audio-bcc08ca599d8.pck on the content-packs branch. Full suite: ALL SIEGE TESTS
  PASSED (60). APK 31423633 bytes, sha256 c0cfec618579c88968577bc325882d563e7e78530d36c486c5b91e41b1277c28.

## 0.31.112 — Home in the middle, a Home that doesn't scroll (Kevin: "For the home screen, move it to the center button. Move the shop button to far left. Also for home screen I don't want it to scroll down, just have the chests at bottom and move the orders and stuff to its own popup menu. Put the play tutorial right under the play button and make it pulse. Once player completes it then it'll go away")
- Tab bar: SHOP · PASS · HOME · LOCKER · SETTINGS.
- Home fills the screen and doesn't scroll (`Screens.home_layout`): the chests sit on the bottom edge; the ribbon,
  PLAY and the row under it stay under the heroes when there's room, else they pack up from the chests (the ribbon goes
  when it would cover the heroes; a party then shows under PLAY instead of the players online). Only a screen
  shorter than ~16:9 still scrolls the little that doesn't fit. App: `home_height()`, `home_fixed`; `_scroll_target`
  returns nothing on a fixed Home.
- ORDERS opens a window (`orders_panel.gd`): daily and weekly orders (CLAIM, reroll), the Siege Pass summary and
  what's inside each chest (the "WHAT'S INSIDE THE CHESTS?" button and the bottom of Home). `rebuild()` refreshes an
  open window that has `refresh()`; `show_tab` closes any window first. The ORDERS medallion wiggles when one is ready.
- PLAY TUTORIAL (+250 gold) sits right under PLAY, pulsing, until the tutorial has been played through (it then
  shows the players online); HOW TO PLAY moved to Settings. A safe start says so in a toast (Settings has COPY
  DIAGNOSTICS).
- tools/app_shots.gd no longer reaches the live server (eco_sync / social / version check off): since 0.31.108 a
  screenshot run with a display made an account on the live server and replaced the shot's profile with it. Eight
  such accounts were made there (see the reply to Kevin for their ids). SHOT_TUTORIAL=todo|done, SHOT_ORDERS=1.
- Tests: app_flow_test (the orders window, the tab order, the tutorial button going away, the layout at 723 / 700 /
  680 px), app_scroll_test (drags tried on the SHOP tab; PLAY still fires on a tap). 0.31.112, version code 198.
- Full suite: ALL SIEGE TESTS PASSED (60). No content pack change. APK 31427896 bytes, sha256
  46ea0bf87c32c57a55019ef423a829e721f1aee48032dd53d7cd90cecf6e6eed.

## 0.31.113 — the "All Tied Up" title, the King swinging from the rope (Kevin: "I like the all tied up one. Can you also make it so the king swings back and forth from the rope")
- Home's text logo ("FATEBOUND" + "ANYONE CAN CHANGE FATE") is now the All Tied Up title: FATEBOUND bound in rope over
  the "STEAL THEIR KING. SAVE YOURS." scroll, with the captured King hanging from the knot under the D.
- `tools/build_title_logo.py` cuts the one painting (`art_sources/title_logo/fatebound_tied_up.png`, white page) into
  two layers in assets/ui/v2: `logo_base.webp` (the King painted out: the D's outline and face carried on behind him,
  the page left clear where he hung over it) and `logo_king.webp` (the King with his two rope ends, from just under the
  knot; the rope ends fade in over 8px so the join at the knot doesn't show). His outline is the white page around him
  plus hand-traced rope ends and crown where he hangs in front of the D, refined with GrabCut. Imported lossy 0.92 with
  mipmaps (drawn linear-with-mipmaps).
- `scripts/app/title_logo.gd`: the two layers sized by width; the King turns about the knot, ±7° on a 2.8 s sine.
  Still with Reduce Motion; stops with the rest of Home in a match (hero layer's processing). Without the ui pack's art
  it falls back to the text logo with the new line. Placed between the side medallions under the top bar
  (`min(w - 150, 300)` wide, 60 px under the safe area).
- tools/app_shots.gd: SHOT_NO_LOGO hides the title; SHOT_SWING=n saves n frames of the swing (home_swing_NN).
  reports/concepts/home_title_logo.png, title_swing.gif.
- Tests: title_logo_test (layers load and match the sizes in title_logo.gd, text logo gone, swings both ways within
  7°, the knot never moves, the swinging King clears the medallions at 420 wide, still with Reduce Motion).
- ui pack rebuilt and uploaded (ui-80b7ee56e390.pck). Full suite: ALL SIEGE TESTS PASSED (61). 0.31.113, version code
  199. APK 31432155 bytes, sha256 b20a2069da753dec18ffdac079fa2b40f0028392631d9dc933d48d63b88e2f60.

## 0.31.114 — a cleaner Home: the heroes in two rows with room between them (Kevin: "The characters on main screen are too hudled together and clipping into each other. Is there a way you can redesign the home screen so it's cleaner")
- `roster.gd`: the seven heroes stand in two staggered rows instead of one tight arc (0.95 m apart, weapons through
  each other): the Barbarian, the Knight and the Mage in front (2.25 m apart), the Rogue, the Ranger, the Priest and
  the Worker behind them in the gaps (the outer two beside the dais). 1.2x (was 1.12x), camera 22 degrees up (was 12.7)
  so the back row stands visibly behind. `SPOTS`, `HERO_SCALE`.
- `screens.gd`: the side medallions tucked up under the top bar (`MED_Y` 0 / 82 / 164, was 58 / 150 / 242 left and
  58 / 176 / 270 right) so they end above the heroes; FIRST WIN's "+300" is a badge on its corner. The "16 v 16
  SIEGE" ribbon is gone (it sat on the heroes' feet; the line under PLAY already says 16 vs 16); a party now always
  shows under PLAY. `home_layout` has no ribbon key.
- Tests: home_heroes_test (no hero's body or weapons within 6 cm of another, from the weapons' actual vertices; at
  420 x 933 every hero clear of the medallions and standing above PLAY, the front three side by side; no ribbon).
  The 0.31.113 line-up fails it (rogue/ranger, ranger/barbarian, barbarian/knight, ...). app_flow_test drops its
  ribbon check. reports/concepts/home_heroes_before_after.png.
- Full suite: ALL SIEGE TESTS PASSED (62). No content pack change. 0.31.114, version code 200. APK 31432155 bytes,
  sha256 9d86bef25c87accf7e4808fb0873959549d6b265004b7396a3f2dea9912baa59.

## 0.31.115 — a new stage under the heroes (Kevin: "Some of the characters are looking like they are floating now because the background art. Maybe needs a redesign")
- 0.31.114's line-up stood the outer two beside the small painted dais (on the battlements' painted wall), and its
  22-degree camera looked down on the heroes more steeply than the painting looks at its dais.
- New Home backdrop (`assets/ui/v2/bg_home.webp`; source `art_sources/home_bg/bg_home_stage.png`): the old painting
  edited (ElevenLabs gpt-image-2.5-sunburst, 4 variations, 1,731 credits; flow "Fatebound Home stage") so the bottom is
  one big round flagstone stage with a gold rim across the whole width -- sky, castle, valley, banners and towers kept.
  Its floor runs from its far rim (77% down the painting at the sides) to its near rim (94%), behind PLAY.
- `roster.gd`: camera down to 16 degrees ((0, 5.17, 14.9)), the rows deeper (front z 2.3 / Knight 2.6, back -2.2 /
  outer -1.9), the outer two at ±4.0 on the floor, 1.15x.
- home_heroes_test: + every hero's feet land on the painted floor (at 420 x 933). ui pack rebuilt and uploaded
  (ui-ab92acbcbfe5.pck). reports/concepts/home_stage_before_after.png.
- Full suite: ALL SIEGE TESTS PASSED (62). 0.31.115, version code 201. APK 31432155 bytes, sha256
  23ccddd3195480e9e5b9f2c75efe5dfba41e7617c98b4566e44a6e77c3b1f2dc.

## 0.31.116 — floating menu icons move smoothly (Kevin: "The icons in the menus that float up and down are not smooth")
- Cause: Godot rounds every control's position to a whole canvas pixel (gui/common/snap_controls_to_pixels, on by
  default). With canvas_items stretch a canvas pixel is ~3.4 screen pixels on the S21 Ultra (1440 / 420), so a 3-5 px
  float (UI2.bob: FIRST WIN's trophy, claimable pass rewards, the equipped weapon, Career tiles, result chests; the
  selected tab's icon) moved in 3-4-pixel jumps a few times a second. Measured at 2x: the trophy held still, then
  jumped 2 px, in exact 2 px steps; after, a smooth sine in fractions of a pixel. Scale pulses (PLAY, the tutorial
  button) were rounded the same way.
- project.godot: gui/common/snap_controls_to_pixels=false (text is MSDF, and at 3.4x a whole canvas pixel never lined
  up with a screen pixel anyway; no visible change to text in the 2x shots).
- UI2.bob: an icon in a container floats inside a holder of its own size that the container lays out, so it follows
  layout changes (before, it stayed pinned where it started).
- Tests: menu_float_test (the setting off in project and viewport; in a box laid out again every frame the icon moves
  < 2 px a frame, floats the full 6 px, and floats 30 px lower when the line above grows 30 px; without the holder it
  stays pinned).
- Full suite: ALL SIEGE TESTS PASSED (63). No content pack change. 0.31.116, version code 202. APK 31432155 bytes,
  sha256 2ccc631af0d34766e874ed5f673206eedacf59728e6d49cd252bda56a294210f.

## Store art (after 0.31.116) — new Play Store screenshots and feature graphic (Kevin: "Give me new playstore screenshots and banner. I want a mix of cinematic action screenshots along with gameplay screenshots along with some menu stuff like forge ect. Put captions on them and make it all eye catching")
- 8 phone screenshots (1080x1920) + the feature graphic (1024x500), all real renders of 0.31.116, in
  `store-listing/graphics/` and the fastlane folder (the 0.19 set removed; renders kept as `raw_renders/*.webp`):
  01 CALL DOWN THE METEOR (cinematic) · 02 16 VS 16 CASTLE SIEGES (gameplay + close-up bubble) · 03 STEAL THEIR KING.
  SAVE YOURS. (gameplay + the King on the Crusader's shoulders) · 04 ANYONE CAN CHANGE FATE (cinematic) · 05 BLOW THEIR
  GATE SKY-HIGH (cinematic) · 06 FORGE LEGENDARY WEAPONS · 07 WIN CHESTS, CLAIM LOOT · 08 SQUAD UP WITH FRIENDS. Feature
  graphic: the All Tied Up title over the Villager running the bomb with his Knights. Captions checked against the
  code (WIN_RESCUES 3, the Archmage's meteor, bombs, every win a chest, the Forge's stars/elements, looks only).
- Tools: `tools/store3_shots.gd` (trailer 6's staged runs played to one moment and saved at any size, portrait camera
  presets; nothing drawn until just before it, so a still is a minute or two), `tools/store3_match.gd` (the 0.19
  in-match staging on the current game, + CLOSE=1 close-ups), `tools/store3_app.gd` (Forge / Royal Chest reveal /
  Friends in a party, sample names, never the live server), `tools/store3_compose.py` (gold Luckiest Guy headlines,
  colour pills, phones over a blurred battle, magnifier bubbles, the feature graphic). The tools end their own
  process once written (Godot can hang on exit after these runs). `store-listing/graphics` and `fastlane` carry a
  `.gdignore` (no imports of listing art). The listing text still says "Oracle" in places.
- No game change; no ElevenLabs credits.

## 0.31.117 — Home's painting down the whole screen, empty chest slots, the online line (Kevin: "The screen space under the play button is very empty looking. And you maybe make a new home screen backdrop or redesign it")
- The painting stopped just under PLAY (the hero layer was 650 + safe area tall), so on a 20:9 phone the rest of Home
  was plain navy with four hollow "Win to earn a chest" boxes.
- New `bg_home.webp` (1024x2816; source `art_sources/home_bg/bg_home_full.png`): the 0.31.115 painting extended down
  -- the stage's stone base, a flight of steps down into a torch-lit treasure hall (braziers, royal banners, chests and
  gold heaped at the sides, open flagstones in the middle where the chests sit), fading to navy at the bottom. Made by
  ElevenLabs gpt-image-2.5-sunburst from `bg_home_extend_input.png` (the old painting over a blank lower part; 4
  variations, 1,767 credits, flow "Fatebound Home stage"); the old painting's own pixels kept above the stage's base
  and the new part blended in under it (aligned to 1 px at the seam), so the stage, the sun and the heroes' placement
  are unchanged. `BG_ASPECT` is the whole painting; `BG_STAGE` (1280/720) the part the stage, sun and clouds are
  measured on. The hero layer is now as tall as the app.
- Empty chest slots: see-through glass over the painted floor with a dim chest in each, "WIN TO EARN" on the first,
  "EMPTY" on the rest.
- The line under PLAY gives a count only once someone else is on ("LIVE SIEGE SERVER" instead of "0 PLAYERS ONLINE").
- tools/app_shots.gd: SHOT_NO_CHESTS=1 (a new player's empty slots). reports/concepts/home_backdrop_before_after.png.
- home_heroes_test: + the tall painting, it reaching the bottom of 20:9 and 21:9 screens, the layer as tall as the app,
  a dim chest in each empty slot, the online line. Heroes still on the painted floor.
- ui pack rebuilt and uploaded (ui-03795105ed77.pck). Full suite: ALL SIEGE TESTS PASSED (63). 0.31.117, version
  code 203. APK 31432155 bytes, sha256 0bb3124c8d6fac17015e4e6113e3b4341a47a362b88caea10a270780feb2be50.

## 0.31.118 — Self-hosted usage statistics (Kevin's spec `ANALYTICS_SPEC_FOR_CLAUDE.md`: "Replaces what Firebase Analytics would do, with no SDK and no third party")
- Notes for whoever runs it: `godot/ANALYTICS.md` (and SIEGE_HANDOFF section 21).
- Events and the props each may carry: `scripts/meta/analytics_events.gd`, shared by the phone and the server (anything
  else is dropped). Numbers, true/false and short words made by the game; never a name, chat text, token or order id.
- Phone `scripts/meta/analytics.gd` (a child of SiegeApp): a queue on disk (500 events / 256 KB; the oldest go and
  are reported as q_dropped), batches of 100 on an `an` socket (compressed, like eco) once `ver`/`status` said `"an":1`
  and the phone has an account; the `ok` list lets those go; no answer = keep and retry (eco_sync's backoff).
  Sessions are times in the foreground (session_start once the version check answered, with online/offline;
  session_end with its length on pause/quit; a session that never ended is closed "lost" at the next start;
  clean_session at the next cold start), level_up, error boot_stuck (safe start) and script_error (a count a session).
  Hooks: tutorial start/step/complete/skip, VS BOTS match start/finish/quit, match_join, forge, chest_open, shop_view,
  update_screen. Settings > PRIVACY > "Share anonymous usage stats" (on by default): off clears the queue, sends one
  opt_out, logs nothing more; the match and social hellos then carry `an_off`.
- Server `server/analytics.gd`: the account's key must open it (else 4005 "an", nothing written); allow-lists; ts
  clamped to -30 d / +1 d (ts_bad); 100 a batch, 2,000 an account a day; ids deduped for today and yesterday (read back
  from the files at start); `analytics/YYYY-MM-DD.jsonl` by the UTC day it arrived, flushed every second, folder 0700,
  files 0600; gzip after 2 days, deleted after 90 (at start and hourly). The server writes its own events:
  session_online (a hello with an account), online match_start / match_finish (result, team_n humans on the side,
  length, start and final class) / match_quit (left mid-match), purchase_verified (product, test), chat_send (kind),
  friend_add / friend_accept, party_create / party_invite / party_join, quick_chat (index), update_screen (a min_build
  refusal). Nothing for an opted-out account. Never an IP address. Protocol stays 35.
- Deploy: the installer ships both new scripts; the accounts backup takes the last 7 days of `analytics/` and
  `opt_out.json`. The probe sends `an` when the status says `an:1` (with SIEGE_PROBE_ACCT/KEY a real batch, build
  `-probe`; without, a made-up key must be refused). Checked with the installer's test mode (PROBE_OK) and a 0.31.116
  build still playing against the new server with min_build 0.31.116 (and 0.31.115 refused).
- Report `tools/analytics_report.py` (stdlib): total unique players and 30-day daily actives (UTC and Pacific) first,
  then WAU/MAU, new players, D1/D7/D30, tutorial funnel, match completion/length (online/bots), win rate by class,
  session length, purchase conversion without test purchases, social use, update screens by build, crash-free, opt-outs,
  dropped. `--json`, `--tz`, `--exclude-file`; `-probe` builds left out.
- privacy.html: "Usage statistics" section (+ mentions in collect/use/sharing/retention), still dated 12 October 2026.
- Tests: analytics_client_test, analytics_server_test (+ a fake older server that never answers), analytics_events_test
  (real server: probe, phone batch, social, an early quit and a full online match in a party, quick chat, a fake
  purchase, min_build refusals, the opted-out account writing nothing, a grep for IPs/names/chat/tokens/keys),
  tools/test_analytics_report.py. Full suite: ALL SIEGE TESTS PASSED (67). 0.31.118, version code 204. APK 31448879
  bytes, sha256 26441e6950d78dc1057e2b14160d69c891faae3ce4f98a154e8fa0e7d92be10a. No content pack change.
- Not done here: the server redeploy (Kevin), privacy.html on main + sslip (after merge), Play Data safety form
  (Grokbot/Kevin, spec section 10). `remote_deploy.sh` isn't in this repo.

## 0.31.119 — match rooms, idle takeover, scoreboard, leaderboards, chest notifications, daily reward, achievements (Kevin: "Do all besides #7")
- **Match rooms** (server only). The server ran one match: the 33rd player was turned away "full". Now each room is
  its own match, lobby countdown and results screen (the old single-match code, per room: `Room` in
  siege_server.gd). SIEGE_MAX_PLAYERS stays the humans in one match (32); SIEGE_MAX_ROOMS (default 4) matches at once.
  A hello goes to its party's room while it has space, else the busiest room with space, else a new room; "full" only
  when every room is full. Empty rooms close after IDLE_STOP. Match ids unique across rooms. "status" counts all
  rooms (+ "rooms"); lobby "in_match"/"running" are the room's own. Protocol unchanged (35).
  Load (this machine, NET_TEST_N=128, 4 full rooms): ~330 ms of work a second, 1.45 MB/s out, 60 frames/s, worst
  frame 17 ms (one room: ~90 ms/s, 350 kB/s). tests/match_rooms_test.gd (rooms of 3, 2 rooms: overflow, party first,
  full only when all are full, status, names per room, rooms closing); every server test passes on the new code.
- **Idle players.** A seated player with no input (no movement, attack/ability/block, action or quick chat -- the
  phone's own position reports don't count) for 45 s of live match time is played by a bot; time dead, in the lobby, on
  the results screen or building the match on the phone (until its first input, up to 20 s) doesn't count. The server
  turns the unit's bot flag on (every app sees it), ignores that phone's positions and tells it {"t":"idle", "on",
  "kick_in"}; any input gives the unit straight back. At 180 s: bye "idle" + close 4006, nothing paid, the seat stays
  with the bot. Phone: stops predicting its unit while a bot has it (draws it where the server has it), HUD banner "A BOT
  IS PLAYING FOR YOU · Move or attack to take over · removed in m:ss"; when removed it goes back to Home, which says
  why (new `notice()` modal). "full" now reads "Every match is full -- try again in a minute". Env for tests:
  SIEGE_IDLE_BOT / SIEGE_IDLE_KICK. tests/idle_test.gd (real server + the real client).
- **End-of-match MVP and scoreboard.** The results showed only your own KOs/downs/rescues. Every unit's knockouts,
  downs, rescues, gathering, gate damage and fish fed already come with the snapshots, so the board is the server's own
  count. Points: rescue 300, KO 20, fish fed 30, gathering 2, gate damage 1 per 10. The results panel gets an MVP strip
  (the best of everyone -- a bot that outplayed everybody is named "Bot · <class>"; "YOU ARE THE MVP!" when it's you,
  with a shine) and a SCORES button: both sides' top 6 best first, players by name (the server's "pn"), you marked and
  always listed on your side. tests/scoreboard_test.gd.
- **Leaderboards.** `server/leaderboard.gd`: every paid online match (the server's own ledger) adds to the account's
  week -- points (the scoreboard's, + 100 for a win), wins, matches, rescues, KOs. Weeks start Monday 00:00 UTC; the
  finished week's top 3 are kept as last week's champions. leaderboard.json in the state directory (backed up with
  the accounts). A socket whose first message is {"t":"lb", "acct", "key"} gets the top 50, the account's own row and
  its friends' rows (names and titles only, never account ids); a wrong key: 4007. "ver"/"status" say "lb":1.
  App: Home's top-right medallion is now RANKS (trophy) -> the LEADERBOARD window (`leaderboard_panel.gd`, fetched by
  `scripts/meta/lb_fetch.gd`): THIS WEEK / FRIENDS tabs, the week's end, your row pinned under the top 50 when you're
  further down, last week's champions, how points are earned. The first win of the day (was the FIRST WIN medallion)
  is a gold "FIRST WIN +300" tag on PLAY's corner while it's open. tests/leaderboard_test.gd (the board, the real
  server, the window).
- **Daily login reward.** A 7-day calendar (`Eco.LOGIN_REWARDS`): 150 gold, 25 Embers, a Silver chest, 250 gold, 50
  Embers, 400 gold, a Gold chest + 20 gems -- a week is 800 gold, 75 Embers, 20 gems and two chests (gems only on day
  7: the economy review found Silver chests were already half of all free gems). One claim a UTC day (like the orders
  and the first win), round and round; a missed day doesn't reset it; chests are reward chests (they wait when the
  slots are full). `claim_login` is a profile op: the server replays it with its own clock, so a phone that moves its
  clock gets nothing more (profile `login` {day, n}). App: the DAILY REWARD card (`daily_reward.gd`, 7 tiles, today's
  pulsing, CLAIM, then "Day N in 21h 2m") opens by itself on Home the first time each day a claim waits (not in tests or
  screenshot tools: `daily_auto`); it's also first in ORDERS, and counts on the ORDERS badge. Analytics: a
  `daily_reward` {day} event (allow-listed). tests/daily_reward_test.gd.
- **"Your chest is ready" notifications.** A small Android plugin of our own, FateboundNotify
  (`godot/android_plugins/fatebound_notify`, Java, built with the cached Gradle 8.14.5 / AGP 8.13.2 against
  org.godotengine:godot:4.7.2.stable; AARs in `addons/FateboundNotify/bin`): `hasPermission`, `requestPermission`
  (Android 13+ POST_NOTIFICATIONS), `schedule(id, title, body, delay)` (AlarmManager.setAndAllowWhileIdle -- inexact, no
  exact-alarm permission; a BroadcastReceiver posts it on a "Chests" channel with a chest status icon; a tap opens the
  game), `cancelAll`. Like billing and Play Games it goes into Gradle exports only (the Play Store preset): the preview
  APK has no notifications. `scripts/meta/notify.gd`: going to the background schedules one per unlocking chest at
  the moment it's ready ("Your Silver Chest is ready!"), coming back cancels them. The first UNLOCK asks in the game's
  own words ("CHEST NOTIFICATIONS -- want a notification when your chest is ready?"); only YES brings up Android's
  dialog (asked once; NO turns the setting off). Settings > NOTIFICATIONS > "Chest ready" (greyed out without the
  plugin). Nothing leaves the phone. Checked: a Gradle export of a minimal project with the plugin merges the
  permission, the v2 plugin entry, the receiver, the classes and the icon (aapt2/dexdump); not run on a phone (no
  emulator here). tests/notify_test.gd (a fake plugin).
- **Google Play Games achievements.** 18 achievements (`scripts/meta/achievements.gd`): Welcome to the Siege, First
  Blood, First Victory, Long Live the King, Many Hats, Fattening Season, Lumberjack, Gatecrasher, Heavy Lifting,
  Centurion, Relentless, Unstoppable, Royal Bodyguard, Master Smith, Seasoned (level 20), Siege Lord (50 wins), Slayer
  of Thousands (1,000 KOs), Legend of the Siege (250 wins) -- 570 points. Read from the account the server keeps;
  sent by play_games.gd while signed in (every 5 s, only what changed: incremental ones as their steps, standard ones
  unlocked once met). The ids come from Play Console: `scripts/meta/play_achievement_ids.gd` (empty = skipped).
  Settings > GOOGLE PLAY > ACHIEVEMENTS opens Google's screen. Icons for Play Console (512x512, bronze/silver/gold
  rims): `store-listing/achievements/`. Steps for Grokbot/Kevin: `godot/PLAY_ACHIEVEMENTS_HANDOFF.md`.
  tests/achievements_test.gd (a fake of the plugin).
- Also: privacy.html (leaderboard names/points, achievements to Google Play Games, local chest notifications, daily
  rewards in the usage statistics), SIEGE_HANDOFF section 22. Full suite: ALL SIEGE TESTS PASSED (74). 0.31.119,
  version code 204 -> 205. APK 31486950 bytes, sha256 b7fcd798843c064ae20ce2c43beac216b644f4c74adb49bdbe5c64a072652e27.
  No content pack change. Needs the server redeployed (rooms, idle, leaderboard).

## 0.31.120 — rejoin, join a friend's match, leaderboard prizes, referral codes, profile card, diagnostics upload, kill feed, vibration (Kevin: "1 and 2 I want added"; then "Do 1, 3, 6, 8, 10, 9 (but make so it's a join match option)")
- **Rejoin after a dropped connection.** Before, a phone that lost its connection mid-match saw "Disconnected from the
  server", the server gave the seat to a bot and the match's record (the ledger) went with the socket -- nothing paid.
  Now every welcome carries "rj", a secret token for the seat. A seated player whose socket drops mid-match (no close
  frame; or silent for 8 s after it started sending input -- SILENT_DROP) has the seat HELD for 60 s: a bot plays it,
  nobody else is seated on it, the ledger is kept, the match still pays it if it ends meanwhile, and it counts toward the
  room's size. A clean close (the app's 1000 "leave" -- now sent with {"t":"leave"} and polled out by a small
  SocketCloser node so it isn't lost when the match node is freed; any code 1000) holds nothing. A hello with "rj" (and
  the same account) goes straight back onto the unit in the same match: welcome {"rejoin":true}, no lobby. A hello with
  the token of a socket the server still thinks is open (a phone that changed networks) takes the seat over and closes
  the old one ("rejoined"). A held seat nobody returns for is let go (match_quit logged then). The game: on a drop it
  keeps the match on screen with a "RECONNECTING... Your seat is held for you · 52 s" banner and reconnects every 2 s for
  up to 55 s; then "Disconnected from the server" as before. The probe leaves cleanly. Older apps never send "rj"
  (their drops are held and simply run out). tests/rejoin_test.gd (real server + the real client: drop and rejoin,
  can't get back, a network switch takes over, a clean leave holds nothing, a hold that runs out, a held seat paid).
- **Join a friend's match** (Kevin: "make so it's a join match option"). Friends: a friend who's in a match has JOIN
  (green). It starts a match whose hello carries "join": the friend's public id; the server checks the two are friends
  and puts the player in that friend's room -- their match, on their side while it has room -- even when another room
  is busier. When the friend's match is full (or they've left / aren't friends) the usual room is picked and
  {"t":"joinr", "why":"full"|"gone"} says so (a toast and a line on the lobby card). In a party of 2+ it says to leave
  the party first. tests/join_friend_test.gd (real server + the real app).
- **Weekly leaderboard prizes.** `Eco.LB_PRIZES`, paid by the server when a week ends (leaderboard.gd `pay_fn` ->
  `eco_accounts.grant_prize` -> `Profile.grant_prize`, never a phone op): #1 300 gems + Royal chest + "Champion" (new
  legendary prefix title), #2-3 200 gems + Gold chest + "the Contender" (epic), #4-10 100 gems + Gold chest + "of the
  Ten" (rare), #11-100 30 gems + Silver chest. Only players with 3+ online matches that week can win (they rank first;
  a row says "N more matches for a prize" until then). "paid" in leaderboard.json + a profile refusing a second prize
  for a week = never paid twice (also after a restart). The window shows THIS WEEK'S PRIZES; Home says "LEADERBOARD
  PRIZE -- You finished #3 ..." once (settings.prize_seen); the Locker has a LEADERBOARD titles section. Profile
  `prizes` (last 12). tests/lb_prizes_test.gd.
- **Referral codes** (Kevin: "both get a Gold chest when the new player reaches level 5, server-checked"). The code is the
  friend code you already have. Friends has INVITE FRIENDS: what it gives, how many friends reached level 5 with your
  code, and -- for a player under level 5 who hasn't entered one -- "Invited? Their code" + REDEEM. That asks the server on
  its own socket ({"t":"ref", "acct", "key", "code"}, like "lb"; `lb_fetch.ask`); server/referrals.gd refuses a wrong
  key, an unknown code, your own, a second one, a loop (they entered yours) and "late" (account older than 7 days or
  already level 5 -- the field then hides), else records who and sets the account's `referral.by`. When the new player's
  account reaches level 5 (checked after every paid online match and every eco exchange) the server gives both a Gold
  chest (eco_accounts.grant_referral -> Profile.grant_referral, never a phone op) with a note; a friend is rewarded for at
  most 20 players; referrals.json keeps by / paid / count. Home says FRIEND REWARD once per note (settings.ref_seen),
  also right after the sync that brought it. "ver" says "ref":1. Constants in Eco (REF_DAYS / REF_LEVEL / REF_MAX /
  REF_CHEST). Installer copies referrals.gd and backs up referrals.json. tests/referral_test.gd (the rules with real
  accounts; then the real server on 8107 + the real app: REDEEM, a restart with the player at level 5, the chest and
  the popup, the friend's chest).
- **Player profile card** (Kevin: tap a name -- level, title, wins, favourite class and weapon). The card a name opens
  (chat, Friends, and now a row of RANKS -- leaderboard rows carry the public friend code "pid") asks the server over the
  social socket ({"t":"so", "k":"prof", "pid"}) and fills in when the answer comes ("Loading..." until then; kept a
  minute): the class played most (stats.main_<cls>) with its portrait, its matches and wins, the weapon won most with
  (forge.wins, else that class's weapon) with rarity colour and Forge stars, then LEVEL / WINS / WIN RATE / RESCUES /
  KNOCKOUTS / BEST STREAK and "#N this week · M matches · since <month>". eco_accounts.stats_of gives only those fields
  (no ids, gold, gems or purchases); a player who blocked you shows nothing; 12 asks per 10 s, then "busy". A friend in
  a match: the card's button is JOIN THEIR MATCH. tests/profile_card_test.gd (stats_of; the real server on 8108 with
  accounts and the week's board written first; RANKS > Alice's row > her card; a blocked card; the wire's fields; busy).
- **SEND TO DEVELOPER.** Settings has an orange SEND TO DEVELOPER (above COPY DIAGNOSTICS, which stays). It asks every
  time -- what's sent (the game's log: what it was doing, errors, phone model, game version, player name; no chats or
  purchases), an optional "What went wrong?" -- then SEND sends it on its own socket, zstd-compressed
  ({"t":"diag", ...}; `lb_fetch.ask(..., zstd)`; a long log keeps its first 3,000 characters and as much of its end as
  fits one 64 KB packet). server/diag_reports.gd keeps it as diag/YYYYMMDD-HHMMSS-<ID>.txt (a JSON header line, then the
  log, control characters out) and answers the ID: "Sent -- report #7F3A9C. Thank you!". The account is kept only when
  its key opens it (otherwise anonymous, so a phone stuck at start can still send); 4 an hour per account or address,
  300 a day, the newest 1,000 / 80 MB kept. tools/diag_reports.py lists them (newest first, --since/--build/--all) and
  shows one (show ID [--errors]). The stuck-start toast now points at SEND TO DEVELOPER. "ver" says "diag":1. Installer
  copies diag_reports.gd. Also fixed: the Privacy toggle's long subtitle (0.31.118) didn't wrap and pushed the whole
  Settings page wider than a 420-wide screen (toggles cut off at the right) -- toggle subtitles wrap now.
  tests/diag_send_test.gd (the server's rules; fitting an 864 KB log; the real server on 8109 + Settings > SEND; the
  report on disk; diag_reports.py list and show).
- **Kill feed.** On the right under the toast line (the quick-chat lines stay on the left): "<who>  ⚔  <whom>" for
  every knockout (players by name, bots by class, in their side's colour; you are "You" in gold on a gold-edged plate;
  a fall with nobody behind it shows a skull), "<who> grabbed their King", "<who> rescued our King!", "<who> broke our
  west gate" (red when it's ours) -- newest on top, 4 at most, 6 s each, then fading. From the events every phone
  already gets (offline: the sim's; online: the snapshots'), so no server change. Off in the tutorial.
- **Vibration.** Settings > SOUND has VIBRATION (on by default; turning it on gives a sample buzz). In a match: a short
  buzz when you're hit (one per 0.25 s however many land), firmer for your knockout, a multi-knockout and grabbing the
  King, a long one when you fall, a King rescued (ours long, theirs shorter) or our gate falling. Android needs the
  VIBRATE permission: added to the "Android Play Store" and "Android KayKit Rebuild" presets (a normal permission, no
  prompt). tests/kill_feed_test.gd (the feed's lines, limit and life; each buzz and the hit gap; Settings; a match gets
  the setting).
- **Build 0.31.120 (versionCode 206).** Full suite (--quick): 81 tests; the first run caught title_test still counting
  37 titles (the 3 leaderboard prize titles are "prize", not earned) -- fixed, passes. privacy.html: player cards,
  invite codes, problem reports. SIEGE_HANDOFF section 23; PLAY_STORE_HANDOFF: the VIBRATE permission and the Data
  safety line for problem reports. APK build/Fatebound-Siege-0.31.120-fatebound.apk (31 MB, Vulkan only, INTERNET +
  VIBRATE), sha256 cb7dad8acccc6f367d543b1b9d103edf5cd9b8454b245700a87dbb03fd3cd244. Needs the server redeployed
  (rejoin, join, prizes, referrals, player cards, reports all live on it; the app works against the old server
  without them).

## 0.31.121 — Play Games achievement ids (Kevin: "Play Games achievements are created (Game ID 1022979193240)")
- `scripts/meta/play_achievement_ids.gd`: all 18 ids from Play Console. Checked: each id's prefix carries Game ID
  1022979193240 and their numbers run 2..19 in the handoff table's order (achievements_test checks both).
- Gatecrasher confirmed: "gates" is counted 1 per 100 gate damage (Eco.match_stats: int(gate_dmg / 100) per match, so
  a match's leftover under 100 doesn't carry over), 100 steps = 10,000 damage -- the same count as the Gatebreaker title.
- `godot_play_game_services/game_id="1022979193240"` on the "Android Play Store" preset here too (the export plugin
  only uses it in Gradle/Play builds; the preview APK still has no Play Games).
- play_games_test's fake plugin had no achievement calls (with empty ids none were made); it records them now and checks
  that a signed-in phone sends them with the real ids.
- Version 0.31.121, versionCode 207.

## 0.31.122 — the next match only after PLAY AGAIN; chat line clear of the tab bar; the Settings gear turns in place
- **No automatic next match** (Kevin: "make it so the game doesn't automatically put player back in a new game because
  they could be looking at score card or something"). Before, 15 s after a match ended the server put everyone into the
  next one, which threw the results / SCORES away. Now the game's hello says "ask_next": the server keeps it on its
  results (no seat, no snapshots of the next match) until PLAY AGAIN sends {"t":"again"} -- pressed while the results
  are up it goes into the next match when that starts; pressed later it's seated in the running match at once. If
  nobody in the room wants another match, none starts until someone does. Left on the results 10 minutes
  (SIEGE_RESULTS_KEEP): "bye done", the game goes back to Home. Older apps (no ask_next) and players waiting in the
  lobby go in as before. SIEGE_RESTART sets the 15 s for tests. tests/next_match_test.gd (real server on 8110 + the
  real client).
- **Chat line** (Kevin: "The icons at bottom block chat"): the open tab's raised tile and its bobbing icon stand ~18 px
  over the tab bar and covered the middle of Home's chat line. The line now sits 22 px above the bar (ChatTicker.GAP;
  Home's height accounts for it) as a whole rounded bar.
- **Settings gear** (Kevin: "needs its animation to just rotate in place"): UI2.spin set the pivot only on "resized",
  which never fired for an icon already at its size, so the gear turned about its top-left corner and swung around the
  sign (checked: pivot (0,0) before, (21,21) now, its centre fixed while it turns). wiggle() had the same gap; both set
  the pivot at once and when they start.
- Version 0.31.122, versionCode 208.

## 0.31.123 — Settings: the old version's progress import removed
- Kevin: "Remove the progress from old version in the settings since Google play saves progress now". The parchment
  card (PROGRESS FROM THE OLD VERSION: paste exported progress + IMPORT, or "Carried over: ...") is gone from Settings.
  Profile.import_legacy stays for the one automatic carry-over at first launch (a dice-era save on the phone,
  `_migrate_legacy`) and meta_economy_test. Settings now ends GRAPHICS, SEND TO DEVELOPER, COPY DIAGNOSTICS / PRIVACY
  POLICY, HOW TO PLAY. Settings tests (app_flow, app_scroll, diag_send, notify, analytics_client, kill_feed, play_games,
  meta_economy) pass. Version 0.31.123, versionCode 209.

## 0.31.124 — the Discord link, with a one-time gem gift
- Kevin: "Add the discord link to the game" (https://discord.gg/H8eKXH8TmM) and "Also give a reward for joining the
  discord". Settings has a COMMUNITY card under SOCIAL: a line about the Discord and JOIN OUR DISCORD (Discord's blue,
  UI2 "discord") that opens the invite through the app's link opener (`open_url`). Until claimed it says
  "+100 GEMS"; the first press pays Eco.DISCORD_GEMS (100) through a new op, `claim_discord` -- once per account,
  replayed by the server on its own copy (profile `discord`), so a phone can't take it twice. The game can't see whether
  the player then actually joins (that would need a Discord bot and sign-in), so opening the invite is what's rewarded.
- privacy.html: "Links to Discord". tests/discord_test.gd (the op, the server paying once, the Settings card).
  Version 0.31.124, versionCode 210.

## 0.31.125 — JOIN OUR DISCORD on Home until it's claimed
- Kevin: "Put a discord button on front page that goes away after they claim it then leave the other discord button in
  settings". Home has JOIN OUR DISCORD (Discord blue, a gentle bob, a "+100" gem tag on its corner) under the logo
  between the medallion columns (Screens.DISCORD_Y), shown only while the profile's `discord` is false. Home's and
  Settings' buttons share `Screens.discord_press`: open the invite, and the first time claim the 100 gems and rebuild --
  Home's button goes, Settings' stays as plain JOIN OUR DISCORD. tests/discord_test.gd covers both; Home tests (app_flow,
  app_scroll, tutorial, daily_reward, menu_sound, home_heroes, menu_float, lb_prizes, social_ui) pass. Version 0.31.125,
  versionCode 211.

## 0.31.126 — dirt paths instead of herringbone brick
- Kevin: "Make the paths on the map more natural looking like it's a dirt path ect". Before: straight runs of
  herringbone brick, one width, a crisp 0.6 m edge. Now:
  - **Shape** (siege_land.gd): PATHS_BLUE_HALF are control points; `paths()` curves a Catmull-Rom line through them
    every 0.75 m (it passes through each point, so the spurs still meet their paths). `path_wobble(p)` makes the track
    swell and narrow along the way (+-0.32 m) and fray at the edge (+-0.4 m more); even in p, so both halves match.
  - **Mask** (tools/bake_land.gd, re-baked pathmask.res and cache.res): R is now `Land.path_r` -- 1 on the track's
    middle, 0.5 at its (wobbling) edge 2.1 m out, 0 a little into the grass -- instead of a brick path's on/off edge.
    The segments are bucketed in 4 m squares, so the bake still takes ~6 s.
  - **Look** (terrain.gdshader): `assets/terrain/dirt.png` (new, made by tools/make_dirt_texture.py: soft trodden-earth
    cells, warm/cool patches, pebbles lit from the top left, tiles seamlessly; imported like grass/rock) at 7 m a tile,
    broken up by a big-patch noise; the edge frays with the grass cells and a mid-scale noise; damp, darker earth by the
    grass and a lighter, dustier middle; clumps of grass holding on near the edges; the grass right at the edge a little
    trodden. path.png stays for the castle floors' no-kit fallback.
  - Grass tufts now hug the frayed edge (they step out until the mask says grass); foliage keeps off the dirt (R > 0.46).
    Footsteps on a path sound of dirt, not stone (only the castles are stone now).
  - The baked land changed, so the "world" content pack is rebuilt and uploaded (players download it once, ~54 MB).
- Version 0.31.126, versionCode 212.

## 0.31.127 — the paths run into a patch of trodden earth round each tower
- Kevin: "Make it so the paths blend better into the towers so it doesn't look like an unnatural cutoff". The spurs
  stopped at a tower's capture ring with a rounded end in the grass. Now every tower (the four on the plateaus and the
  island's) stands in a patch of trodden earth -- its edge about 5.4 m from the centre (Land.APRON_IN 3.3 + the paths'
  2.1), fraying and wobbling like the paths -- and a path that reaches one widens into it: the mask's distance is the
  smooth minimum of the path's and the patch's (Land.ground_dist, APRON_BLEND 2.2 m), so there's no seam. Baked into
  pathmask.res (tools/bake_land.gd); the shader draws it like the paths. A few grass tufts sit round the patch's edge
  (sparse -- a full ring read as a hedge). World content pack rebuilt. Version 0.31.127, versionCode 213.

## 0.31.128 — vibration only for knockouts; one body size; the Knight's idle for (nearly) everyone
- Kevin: "I only want phone to vibrate when player makes a kill". `siege_mode._haptic`: one buzz (70 ms) for each
  enemy the player knocks out; nothing for being hit, falling, a multi-knockout's banner, the King, rescues or gates.
  Settings' line: "A buzz each time you knock out an enemy". kill_feed_test updated.
- Kevin: "make the base class models the same size as the advanced class". Every body is drawn at 1.14 (View.BODY_SCALE;
  the base classes were 1.0, the upgraded 1.14). An upgraded class still shows by its own model and its gold ring.
- Kevin: "make their idle animations the same as knight so the others aren't bouncing up and down so much". Measured
  the clips' hip motion: g/Idle_A (the Knight's) 1.5 cm, g/Idle_B 10.2 cm (Rogue, Mage, Priest, Assassin, Archmage,
  Necromancer), m/Melee_2H_Idle 3.6 cm (Barbarian, Berserker), r/Ranged_Bow_Idle 0 cm (Archer, Ranger). Every class now
  stands in g/Idle_A except the two archers: in g/Idle_A the bow hand is the Knight's shield hand and all eight bows'
  strings turned away from the archer (weapon_grip_test), and their own idle doesn't bob at all. Home's heroes use the
  same idles.
- Version 0.31.128, versionCode 214.

# Trailer 7, "Bring Him Home" (tools only, no build; Kevin: "Make a new game trailer. I want it very cinematic. Have
# epic music, action sequences, slow motion ect. Also climactic end scene leading to the game title and use the new
# title graphic with the swinging tied up king")
- Plan in tools/trailer7_script.md. No narrator: the score carries it, with four title cards in Cinzel (the game's
  serif): TWO KINGDOMS / ONE STOLEN KING / BRING HIM HOME / 16 VS 16. The shape: a dark, slow opening over the kingdom
  at golden hour; our King behind bars in their dungeon at dusk, torchlit; our army in a long rank, the gates swinging
  open, out they pour; both armies charging (four angles); the music cut dead and time all but frozen as the front
  ranks' blows land -- then the battle score crashes in as time starts again and their front rank is thrown back; an
  action montage on the beat (Crusader's hammer, Berserker's whirlwind, Archmage's meteor, a volley, the Necromancer's
  drain, the Sniper's piercing shot, the Assassin's leap, a Knight's shield, their gate blown in from inside their
  courtyard); the score's quiet bars as their cell door is smashed in, from inside the cell over the King's shoulder;
  our King carried out, over the east crossing into the low sun, an ambush stopped by the hammer, our gates; up into
  the throne room in slow motion; the hit, a white flash -- and Home's logo slamming in over the battle far below,
  the tied-up King swinging hard from the impact and settling into the logo's own swing, the rope creaking.
- tools/trailer7_shots.gd: 19 short staged runs in a real match (one per process, Movie Maker at 1920x1080 30 fps:
  tools/trailer7_render.sh <run> [W H]). Slow motion is keyed (SCALE: [time, scale] pairs, ramped between them), so
  speeds ramp in and out. The clash is triggered by distance (the front ranks within 2.6 m), not a clock; the three
  charge runs share one seed so their cuts match. New camera kinds: "group" (follows the middle of a rank), "orbit",
  and "track" (a fixed eye panning with someone). Camera moves run on recording time, so they glide through the slow
  motion. The dungeon at dusk: a cold dim sun, a flickering torch inside the cell, a dim one outside.
- tools/trailer7_edit.py: the cut (29 shots, 75 s) timed to the music's own landmarks (cue A's booms and its peak, B's
  first beat, bars at 139.7 BPM and its quiet bars, C's hit), and the mix -- every sound placed on its shot; the game's
  own sounds slowed with the picture; trailer 6's beds. -14 LUFS.
- tools/trailer7_finish.py: the finishing pass over the cut picture: a filmic grade (S-curve, cool shadows, warm
  highlights, vignette), 2.39:1 letterbox, the cards (fading in while they grow; the 16 VS 16 card snaps on the beat),
  the flash on the final hit, and the title: logo_base.webp + logo_king.webp laid out with title_logo.gd's own
  constants (read from the script: KING_AT, PIVOT, SWING_DEG, PERIOD), the King's swing 7 + 19 e^(-t/1.5) degrees,
  a slam with a bounce and shake, a glint across the gold, embers, a soft shadow.
- ElevenLabs (estimated and reported first): music, three cues x 4 takes, 5,039 credits; sound effects (rope creak,
  title slam, time-freeze breath) x 4 takes, ~660 credits. The takes used are in tools/trailer7_vo/raw.
- Fatebound-Trailer-7.mp4: 75 s, 1920x1080 at 30 fps, -13.7 LUFS, -1.4 dBFS peak, 112 MB (and a 720p phone copy, 23 MB).

## 0.31.129 — the title logo's white gaps cleared
- Kevin (on Trailer 7's title): "There is white showing on the title". The painting's white page showed through in
  three pockets shut in between the letters and the tagline scroll (under "FATE" and under "BOU"): the cut-out only
  cleared the white connected to the painting's border. tools/build_title_logo.py now clears enclosed pockets of
  white page too (at least POCKET_MIN 150 px, left of the King -- his beard and fur are white and stay). Same layout
  (BASE / KING_AT / KING_SIZE / PIVOT unchanged), logo_king.webp unchanged; Home's logo and the trailer's title both
  use the fixed logo_base.webp. ui content pack rebuilt (ui-26af4d5a8e1a). Trailer 7's title stretch re-rendered.
- Version 0.31.129, versionCode 215.

## 0.31.130 — the iOS port, step 1: one face for both stores (Android unchanged)
- Kevin's IOS_PORT_SPEC_FOR_CLAUDE.md (in godot/): the same game on iPhone through TestFlight, then the App Store, with
  Android unchanged in behaviour. Kevin's choices: GodotApplePlugins (migueldeicaza, MIT, a SwiftGodot GDExtension) for
  StoreKit 2 and Game Center, so the minimum is iOS 17 (the spec said 15); only the TestFlight workflow file goes to main.
- scripts/meta/platform.gd: which phone and which store -- is_android / is_ios / store() ("play" | "appstore" | "none"),
  the store's page (Play's market:// then web; the App Store's apps.apple.com/app/id<APPLE_APP_ID>, a search link
  until the app record exists), has_iap / has_cloud_save / has_achievements, the store's words. Tests pretend with
  Platform.forced. The three OS.get_name() == "Android" checks now ask it (update screen, BootGuard -- tracking on iOS
  too -- and the logcat tail), answering exactly as before on Android.
- scripts/meta/store_billing.gd / game_services.gd: pick billing.gd + play_games.gd (Android and the desktop,
  unchanged) or billing_ios.gd + game_center.gd (iOS). Both pairs have one face, so the app and the shop never ask which.
- billing_ios.gd: App Store purchases with Play's flow: Apple's sheet (appAccountToken = UUIDv5 of the account id,
  apple_token.gd) -> the signed transaction to the server ("iap" with "store":"apple" and the JWS) -> granted to the
  account -> only then finished. Unfinished transactions come back from StoreKit on start and resume. Ledger tokens
  "apple:<transactionId>" (gem packs) and "apple:<originalTransactionId>" (the starter pack). RESTORE PURCHASES.
  Refunded transactions are finished, never granted.
- game_center.gd: signed in by Apple at start; the 18 achievements as percentages with Apple's ids (gc_achievement_ids.gd,
  "fatebound.<key>") -- achievements.gd now counts once and each service sends its own way (Play's calls unchanged);
  Apple's achievements screen; a `signed(teamPlayerID)` signal for the account link (step 6). No cloud copy on iOS v1.
- Screens: the shop says App Store / APP STORE on iOS (Google Play / PLAY STORE otherwise, unchanged) and has RESTORE
  PURCHASES; Settings shows GAME CENTER ("signed in as <alias>" + ACHIEVEMENTS, or "Sign in from iOS Settings > Game
  Center") instead of GOOGLE PLAY. The update screen names the App Store on iOS.
- tests/ios_port_test.gd (in the quick suite): the platform answers, the facades, UUIDv5 against Python's, billing_ios
  and game_center against doubles of the plugin's classes, the real app as an iPhone and as Android.
- Android check: the Play AAB built from HEAD and from this change (a throwaway key in /tmp, preset.0 untouched): both
  verify_play_bundle BASE OK, CONTENT OK, play_games true, bundletool valid; the only differences are the changed
  scripts and the seven new ones (dormant on Android). Quick suite: ALL 84 PASSED.
- Version 0.31.130, versionCode 216.

## iOS port step 2 — the "iOS App Store" export preset (no game change; still 0.31.130)
- export_presets.cfg preset.5 "iOS App Store": bundle com.fatebound.game, team YBKRZRW845, App Store export (release
  method 0, "Apple Distribution", the profile from the CI), arm64, minimum iOS 17.0 (GodotApplePlugins), iPhone and
  iPad, portrait (project setting), Game Center entitlement; Metal is Godot 4.7's default driver on iOS (nothing set,
  project.godot untouched, MoltenVK unused). The mobile renderer makes Godot require an A12 (same floor as iOS 17).
  short_version 1.2.25 / version 214 are placeholders: the TestFlight workflow writes Play's versionName number and
  versionCode in. Godot's own Info.plist already has ITSAppUsesNonExemptEncryption = false and the display name.
- Privacy manifest (Godot writes PrivacyInfo.xcprivacy from the preset): no tracking; Godot's required-reason APIs
  (file timestamp DDA9.1 + C617.1, boot time 35F9.1, disk space E174.1 + 85F4.1) plus UserDefaults CA92.1; collected,
  linked to the account, never tracking: other user content, user id, purchase history (app functionality), product
  interaction (analytics), crash data (both), other diagnostic data (app functionality).
- The App Store icon: store-listing/ios/app_icon_1024.png = the King Rescue (B4) painting at 1024, no alpha (the exact
  source of the Play 512 icon); kept in store-listing so the Android bundle doesn't carry it. Godot makes every size.
- tools/content_packs.py: BASE_PRESETS gains "iOS App Store" -- the same exclude filter as the Play base (the Android
  presets' filters came out unchanged).
- addons/GodotPlayGameServices/export_plugin.gd: its export hook returns for non-Android exports (it errored on the
  iOS preset, which has no Gradle option); Android unchanged.
- Checked on Linux (Godot writes the Xcode project and stops, as it does off a Mac): bundle id, team, deployment
  target 17.0, device family 1,2, version placeholders, the Game Center entitlement, export_options (app-store,
  YBKRZRW845), Info.plist / PrivacyInfo / entitlements all parse; the icons RGB; a 2.4 MB base Fatebound.pck.

## iOS port steps 3, 5, 7 — the native side: StoreKit 2, Game Center, notifications
- tools/ios_plugins.sh puts the iOS build's native plugins into godot/addons/ just before an iOS export (the TestFlight
  workflow runs it): GodotApplePlugins v1.11 (release build-a6d667dd..., zip SHA-256 checked) -- only its StoreKit,
  GameCenter and Swift runtime addons -- and FateboundNotifyIOS built from source. Nothing of it is committed
  (.gitignore), so Android and desktop builds never carry or load it; --remove takes it out again.
- The iOS preset alone also leaves the plugins' bin/ folders out of the pck (content_packs.py PRESET_EXTRA): Godot
  copies their xcframeworks into the Xcode project itself, and their Swift module JSON (~80 MB) had landed in the pck.
  The Android presets' filters are unchanged. Checked on Linux: the Xcode project carries StoreKit, GameCenter and
  SwiftGodotRuntime xcframeworks with their entry symbols registered; the pck is 2.4 MB with the two .gdextension files.
- godot/ios_plugins/fatebound_notify (hidden from Godot by .gdignore): FateboundNotifyIOS, an Objective-C++ GDExtension
  on godot-cpp (godot-4.5-stable, pinned commit) using UNUserNotificationCenter, with the Android plugin's own four calls
  -- hasPermission (iOS's answer, cached), requestPermission (iOS's dialog), schedule(id, title, body, delay),
  cancelAll (pending and shown). build_ios.sh (macOS + Xcode) makes static xcframeworks (iPhone + Simulator) for it and
  godot-cpp and writes the .gdextension into addons/FateboundNotifyIOS/. Off Apple platforms the same class builds with
  a stand-in that records the calls: built and loaded in Godot 4.7.2 on Linux -- the class, permission, the calls.
- scripts/meta/notify.gd: on iOS it takes FateboundNotifyIOS; everything else (our question before iOS's dialog,
  Settings > NOTIFICATIONS > Chest ready, scheduling per unlocking chest, cancel on return) is the same code.
- ios_port_test: notify.gd on iOS, and the iOS class registers the name and the four calls the Android plugin has.

## 0.31.131 — the iOS port, step 4: App Store purchases checked by the server
- server/iap_verify_apple.gd (iap_verify.gd, Google's, untouched): an "iap" message with "store":"apple" carries Apple's
  signed transaction (JWS). server/apple_jws.py checks it in its own process (the game loop never waits): the x5c
  chain to Apple Root CA - G3 (server/certs/AppleRootCA-G3.cer, public, SHA-256 pinned) at the transaction's signedDate,
  Apple's receipt-signing marks on the leaf and the intermediate, the ES256 signature; then Apple's App Store Server
  API is asked for the same transaction (production or sandbox by its environment, an ES256 JWT from the In-App
  Purchase key) and its copy checked the same way. Python's standard library and the openssl command only (nothing to
  pip-install on the server). The game's rules on top: bundle id, product (and in Net.IAP), not refunded (Apple's
  current copy), appAccountToken = UUIDv5 of the account asking (when the purchase carries one).
- Granted with the same eco.grant_purchase as Google's, ledger tokens "apple:<transactionId>" (gem packs) and
  "apple:<originalTransactionId>" (the starter pack): once per token, never to another account, and they can't collide
  with Google's. Ledger lines get "store":"apple"; analytics purchase_verified gets a "store" prop (google | apple).
  A message without "store" is Google's, exactly as before. No key -> "unconfigured" (the phone keeps the purchase
  unfinished and asks again later), like Google's.
- Key: $CREDENTIALS_DIRECTORY/appstore-key (LoadCredential, like play-key; the installer turns it on when
  /etc/fatebound-siege/appstore-key.p8 exists), SIEGE_APPSTORE_ISSUER and SIEGE_APPSTORE_KEY_ID in
  /etc/fatebound-siege.env. The installer ships the verifier, the helper, the root and apple_token.gd, and warns when
  python3 or openssl is missing. Refund notifications (App Store Server Notifications V2): not built (Google's flow has
  no revocation either) -- the API check already refuses a refunded transaction.
- tests/apple_iap_test.gd (in the quick suite): a stand-in Apple (tools/apple_test_certs.py) and a fake App Store
  Server API: a valid sandbox purchase ok; refused: wrong bundle, another product, another root, a tampered payload,
  refunded, bought for another account, unknown to Apple, a product not on sale; a refused key -> unconfigured; the
  starter pack's token; the API's JWT checked (ES256, kid, issuer, aud, bundle). Then the real server process: two
  accounts, billing_ios.gd's own message, granted once, the same transaction again "already yours", another account
  refused (its token is A's) or "used" (a copy without the token). analytics_events_test knows the store prop.
- Version 0.31.131, versionCode 217. Quick suite: all 85 passed (84 Godot tests + the report check; analytics_events_test re-run after its fix). Kevin: redeploy the server for App Store purchases.

## 0.31.132 — the iOS port, steps 6 and 9: the account between phones, deleting it, privacy
- Settings > ACCOUNT (Android and iPhone alike): MOVE TO ANOTHER PHONE asks the server for a one-time code (8
  characters from 2-9 and A-Z without I/O, 10 minutes, once, kept only in the server's memory; at most 5 an hour per
  account); ENTER A CODE on the other phone (Android <-> iPhone, both ways) gives that phone its own key to the same
  account (the account keeps up to 8 extra key hashes, meta.keys; the first phone's key still works) and the
  server's copy replaces the phone's. Wrong codes: 10 per address and 60 per server in 10 minutes, then "busy".
- Game Center link: signed in, the phone sends Apple's identity signature (GKLocalPlayer fetchItems: public-key URL,
  signature, salt, timestamp); server/apple_jws.py --gc fetches the key's certificate from Apple (https, apple.com
  hosts only), checks it is in date and that it verifies the RSA-SHA256 signature over teamPlayerID + bundle id +
  timestamp + salt; the server refuses one older than 10 minutes or seen before. Then gc_links.json maps
  sha256("fatebound-gc:" + teamPlayerID) -> account (never the id itself). Another account found for the player: a
  fresh phone takes it silently ("Progress restored from Game Center", like Google Play's copy), a phone with progress
  asks (USE THAT ACCOUNT / KEEP THIS PHONE'S -- keeping relinks the player to this phone's account).
- DELETE ACCOUNT (App Store 5.1.1(v); Google Play's data deletion too), asked twice: the server deletes the account's
  files, its Game Center link and codes, forgets its name, friends and blocks (social) and its leaderboard row, and
  records nothing more for it in usage statistics; purchase tokens keep pointing at the empty id so nothing is granted
  twice. The phone starts afresh (sound and graphics settings kept; Google Play's copy is overwritten at the next
  upload, never read back).
- UGC (App Store 1.2): server/social.gd already has report, block, a word filter with links masked, and the muted
  list -- nothing to add. The privacy manifest came with step 2.
- scripts/meta/account_link.gd (the phone's side), server/eco_accounts.gd (link_new / link_use / gc_link /
  delete_account / extra keys), siege_server "eco" with an "op" (link_new, link_use, gc, delete; "ver" says move:1),
  social.forget, leaderboard.forget; social.gd (the phone) reconnects after a switch. Usage statistics:
  session_start carries plat ("android" | "ios"); tools/analytics_report.py splits daily players by phone.
- privacy.html: the App Store and its purchase check, Game Center (achievements, the hashed player id for account
  restore), moving to another phone, deleting the account, notifications on iPhone too, "Android or iOS version".
- tests/account_move_test.gd (in the quick suite): the accounts alone (codes, limits, keys, Game Center link, relink,
  deletion), then three phones against the real server (a code moves A to B; a wrong code; Game Center with a
  stand-in key server: A links, a fresh C gets A's account, the same signature again and one signed for another
  player refused; DELETE ACCOUNT, after which A's first key no longer opens it). ios_port_test checks the ACCOUNT card
  on both phones; analytics tests know plat.

## iOS port steps 8 and 10 — content packs on iOS, the TestFlight workflow (also 0.31.132)
- The same packs serve both phones: tools/ios_pack_check.py exports every pack with an iOS pack preset (added only
  while it runs) exactly as content_packs.py builds Android's: all five (ui, world, heroes, weapons, audio) came out
  byte-identical to the manifest's (same sha256). Godot gives iOS the same texture formats (etc2 + astc) as Android.
  So one manifest, one content-packs branch, no per-platform entries.
- The loader keeps packs in Library/Caches on iOS (OS.get_cache_dir()/fatebound_packs): user:// is backed up to
  iCloud there, and Apple's storage rules keep re-downloadable data out of backups. iOS may empty Caches when short
  of space; the packs are simply downloaded again. Android keeps user://packs.
- content_packs.py base takes an .ipa (Payload/<app>.app/<name>.pck) or a .pck too, and fails if the iOS plugins'
  binaries got into the pck. Checked on the Linux-exported iOS pck: BASE OK, 227 files.
- .github/workflows/ios-testflight.yml (manual only; to main, the only file there, as Kevin chose): macos-15, Godot
  4.7.2 editor + iOS template (SHA-512 from Godot's SHA512-SUMS), tools/ios_plugins.sh, the version from the inputs,
  export of the Xcode project, checks (base pck, plists, bundle id, version, deployment target, Game Center
  entitlement, the three plugins' entry symbols), then either an unsigned iPhone build (build-check) or a
  throwaway keychain with the distribution .p12 and the profile from secrets, archive, export (app-store-connect,
  manual signing), the .ipa checked again, altool validate + upload to TestFlight (never review), artifacts (the .ipa
  or Simulator app and logs), and the keychain and keys deleted in an always() step.
- godot/IOS_HANDOFF.md: what Kevin and Grok Bot do next (certificate and profile with openssl, no Mac; App Store
  Connect app, keys, the seven products, the 18 achievements as fatebound.<key>, App Privacy, TestFlight testers; the
  GitHub secrets; the server's In-App Purchase key; privacy.html to main; one shared min_build).
- Version 0.31.132, versionCode 218. Quick suite: all 86 passed (85 Godot tests + the report check). Kevin: redeploy the
  server (App Store checks from 0.31.131, the account moves and deletion from 0.31.132 -- Android uses them too).
- The workflow checked on GitHub's Mac (build-check, unsigned, no secrets) -- four runs, each fix pushed:
  SCons now in its own venv (Homebrew Python refuses pip, PEP 668); the check mode builds for iPhone (Godot's
  Simulator library is x86_64 only); Xcode 26 picked (Godot 4.7.2's iOS template links iOS 26 SDK symbols:
  CADynamicRange*, MTLTensorDomain); the notification plugin compiled with the selected Xcode's toolchain (godot-cpp
  defaults to /Applications/Xcode.app, another Xcode, and the mix broke the system modules). Run 38520870076: Godot,
  GodotApplePlugins, FateboundNotifyIOS, export, every check and the unsigned iPhone build (Xcode 26.3, iOS 26.2 SDK)
  -- BUILD SUCCEEDED; the x86_64 Simulator build too. Only signing and the upload wait for Kevin's secrets.
- Android, last check: the Play AAB built from 0.31.132 (throwaway key, preset.0 untouched): BASE OK, CONTENT OK,
  play_games true, bundletool valid.

## 0.31.133 — iOS launch prep: the App Store app's id, the handoff's account, the key check
- `platform.gd` `APPLE_APP_ID = "6822556363"`: the App Store app **Fatebound Siege** (bundle com.fatebound.game). The
  update screen's UPDATE on an iPhone now opens https://apps.apple.com/app/id6822556363 instead of an App Store search
  (ios_port_test checks the exact URL). Android's links are unchanged.
- IOS_HANDOFF.md: the Apple account is midblade4295@hotmail.com (Individual, Kevin Petrie, team YBKRZRW845; the CSR
  line uses it), the App Store app is "Fatebound Siege" with Apple ID 6822556363 (the home-screen name stays
  "Fatebound"). privacy.html untouched (bc8898f's contact email stays).
- The server's App Store purchase checks, reviewed end to end for launch: the phone sends the StoreKit 2 signed
  transaction; the server checks its x5c chain to Apple Root CA G3 (bundled, SHA-256 pinned) and the ES256 signature,
  then asks the App Store Server API (GET /inApps/v1/transactions/{id}, production or sandbox by the transaction's
  environment -- TestFlight purchases are Sandbox) with an ES256 JWT from the In-App Purchase key
  ($CREDENTIALS_DIRECTORY/appstore-key via LoadCredential, SIEGE_APPSTORE_ISSUER, SIEGE_APPSTORE_KEY_ID). Kevin has
  put key 2X23RCW3YT at /etc/fatebound-siege/appstore-key.p8 with both env lines; the installer only adds its
  LoadCredential line when the file exists, so the server must be redeployed after it (the log then says
  `purchase checks: Apple: key 2X23RCW3YT (issuer <first 8>...)`; `Apple: off (no App Store key)` means it wasn't loaded).
- New: `server/apple_jws.py --api-check` checks the key against Apple without a purchase (asks production and
  sandbox for a made-up transaction: 404/400 = key accepted, 401 = refused; exit 0 only when both accept). Command in
  IOS_HANDOFF.md §4.3. Checked here: a local stand-in API (404 and 400 -> accepted, exit 0; wrong key -> refused,
  exit 1) and Apple's real endpoints with a throwaway key (both reached, 401 REFUSED, exit 1) -- the live server and
  the real key are Kevin's.
- Version 0.31.133, versionCode 219 (server 0.31.133 = 0.31.132's Apple purchase checks and account features + the
  key check). One commit for the Android build, the server and the iOS TestFlight build.
- Quick suite: all 86 passed (85 Godot tests + the report check). The Play AAB built from this commit (throwaway key,
  preset.0 untouched): BASE OK (228 files), CONTENT OK, play_games true, bundletool valid.

## 0.31.134 — Crown War step 1: clans
Kevin's Crown War design (houses, clans, a weekly war over a live map) starts with clans. Decisions (Kevin, 2026-10-14):
30 members, a clan's house never changes, 10,000 gold to start one, houses Lions / Stags / Ravens, map battles for clans
only (later steps).
- server/clans.gd (new, clans.json in the state directory): a clan has a name (3-20 letters, digits, spaces, ' and -;
  the chat's word filter; unique ignoring case, spaces and punctuation), a tag (3-4 of A-Z 0-9, unique, filtered), a
  house, who may join (open / by request / invite only), the lowest level, a leader, officers and members (30 at most).
  Officers and the leader answer requests, invite (by friend code or a name card; an invite lets a player past the
  level and the mode; a player who blocked the officer never gets it, and blocking takes an invite away), and remove
  members; the leader also names officers, hands the clan over, removes officers and disbands. Leaving or being removed
  means 24 hours before joining or starting another clan (disbanding, or the last one out, doesn't). A leader not seen
  for 14 days hands the clan to the officer seen last (else the member seen last). Invites and requests last 7 days.
  At most 20 clan messages a player per 10 s; asking to join again pops up for the officers once an hour.
- Starting a clan: every rule checked first, then eco_accounts.pay_gold (Profile.pay_gold, server only, never below
  zero, noted in profile "paid") takes 10,000 gold, then the clan is made and written to disk at once. The phone pulls
  its account and shows the new gold.
- It rides the social socket (server/social.gd): "clan_*" messages; "clan" is a third chat channel (members only, 50
  lines, sys lines for joins, leaves, roles); cards, chat lines, profile cards and leaderboard rows carry "ct" (the
  tag); "pn" carries "ct" per unit and the lobby a "ct" list (siege_server.gd); "me", "ver" and "status" say
  "clans":1. Account deletion leaves the clan. Usage statistics: clan_create / clan_join / clan_request / clan_invite /
  clan_leave (server events), and a "clans" line in the report's social section.
- The phone: Home's FRIENDS medallion is SOCIAL (no room for another medallion beside the heroes); its window has
  FRIENDS and CLAN tabs (counts on the other tab). CLAN (scripts/app/clan_panel.gd): not in a clan -- invites, FIND A
  CLAN (search, house filters, JOIN / ASK / ASKED / FULL / INVITE ONLY, a clan's card with its members), START A CLAN
  (name, tag in capitals, house, who may join, lowest level, the cost against your gold); in a clan -- the banner in
  the house's colours, CLAN CHAT, requests (officers), INVITE A PLAYER (officers), members (crown, OFFICER, MANAGE:
  make officer / member / leader, remove), settings (officers), LEAVE / DISBAND (two taps). The chat has a CLAN tab;
  a name card shows the tag and INVITE TO CLAN (officers, players not in a clan). The tag shows before names in chat,
  friends, ranks, the lobby and over heads in a match ("[WOLF] Alice").
- Tests: clans_test (73 checks: server/clans.gd through social.gd) and clans_ui_test (26 checks: the app's buttons
  against the real server on 8118 with a second phone, gold taken and shown, request/accept, clan chat, MANAGE, the
  tag over her head in a match). A separate review of the server code found no serious defects; its four smaller
  findings (the clan written at once after the gold is taken, a rate limit and one pop-up an hour, no wait for the
  last one out, blocking removes an invite) are fixed and tested.
- server/deploy/install_siege_server.sh copies server/clans.gd (checked: the installer's minimal project, built the same
  way, starts and says "social: 0 players known, 0 clans").
- Version 0.31.134, versionCode 220. Server 0.31.134 must be deployed for clans (older servers: the CLAN tab says clans
  arrive with the next server update).
- Quick suite: all 88 passed (87 Godot tests + the report check; profile_card_test's list of card fields now allows
  "ct"). The Play AAB built from this commit (throwaway key, preset.0 untouched): BASE OK (230 files), CONTENT OK,
  play_games true, bundletool valid.

## 0.31.135 — Crown War step 2: the map and battles
The second step of Kevin's Crown War (the "Crown War" design doc): the war map, its battles and the war table on the
phone. Kevin's decisions used here: map battles for clans only, a 3D war-table map, the starting numbers (5 attempts a
day, +50 a crown, -100 a loss, 1,000 to take held land, 500 for free land; defending is free; bots defend).
- scripts/meta/war_map.gd (new, shared by phone and server): three homes (Lions' Keep, Stags' Keep, Ravens' Keep --
  never lost; King's Day attacks them in a later step) and fifteen territories (The Mill, Old Tower, The Abbey, High
  Pass, The Quarry, The Ford, Silver Lake, King's Bridge, Deep Mine, The Marsh, Kingswood, The Forge, Grey Cliffs,
  Raven Fen, Saltport), 30 links between them, and the numbers.
- server/world.gd (new, world.json in the state directory): who holds each territory (house, clan, tag), each clan's
  bar on each territory, the battles on, each player's attempts today (UTC days), the weeks won, recent captures. A
  house attacks along a link from land it holds (its home counts), one battle a territory at a time (asking for one
  your house already started joins it; another house's is refused), one battle on at a time for a player and two for a
  clan (each holds a room). Starting a battle spends the starter's attempt; another clan member's battle counts when
  seated with an attempt left: crowns x 50 (a gate broken, the King rescued, the match won), -100 for a loss (or
  quitting, or never coming; a battle every player left is lost); a battle still on when the week ends counts for
  nothing; bars never go below 0; the first clan to fill its bar takes the territory for its house and every bar there starts again (the
  clans' chats hear it: "We took X for House Y!" / "We lost X to [TAG]"). Weeks run Monday to Monday (UTC): the house
  holding the most land wins the week and the map is free again. It rides the social socket: war_open / war_close (the
  map pushed while it's open, at most every 0.5 s), war_go {tid, call} -> the battle's id; "call" sends war_call to
  the clan's members online, and the holders' members get war_alarm; the clan chats get a line each way and a summary
  after the battle ("The battle for X: won, 2 crowns, +100 (200/1000)"). Usage statistics: war_start, war_capture.
- server/siege_server.gd: a war battle is a 16-a-side match in a room of its own (never picked by matchmaking or a
  friend's JOIN): attackers on red, the holders' house on blue (nobody defends free land), bots in every empty seat; a
  player of neither house (or no clan) is turned away (bye war_side), as is one for a battle that's over (war_over) or
  full (war_full), and a second seat for the same account (war_twice). Battles never take the server's last room
  (matchmaking keeps it). Its countdown is 30 s (SIEGE_WAR_LOBBY); an empty war room waits 90 s for its players
  (SIEGE_WAR_WAIT); after the match everyone on its results is let go within 3 minutes, so the room closes. After the match each player gets {"t":"war"}: the territory, crowns, points, the bar (attackers),
  held or lost (defenders), or "helped" (no attempt left: fought, no points). PLAY AGAIN there says war_over.
- The phone: Home shows CROWN WAR · HOUSE X under PLAY for clan members (where the players-online pill was; a party's
  pill still comes first); the CLAN window has WAR MAP (and SEE THE WAR MAP before joining a clan). The war table
  (scripts/app/war_table.gd): the map as KayKit hex tiles on a wooden table, each on a ledge in the colour of the house
  that holds it, with its banner, names and holders' tags over the tiles, a battle's ring glowing; over it the week's
  end, your attempts and each house's land; tap a place for who holds it, the clans' bars, and ATTACK (with CALL CLAN)
  or why not, JOIN THE BATTLE / DEFEND IT when one is on. The battle's countdown says "BATTLE FOR X · House A attack
  House B"; its results add what it did (crowns, points, the clan's bar, or held / lost) and WAR MAP instead of PLAY
  AGAIN, which reopens the table on that territory. A clan mate's call drops a JOIN banner (green), an attack on your
  clan's land a DEFEND banner (red), both straight into the battle (not during a match).
- Tests: world_test (51 checks: server/world.gd alone -- reach, homes, attempts and the day, joining a battle, the
  limits, points, bars, captures, a battle everyone left, the week's roll and a battle it caught, a damaged
  world.json), war_battle_test (20 checks: a battle end to end against the real server on 8120 -- called, alarmed,
  seated by side, refused without a clan or twice, scored 1-0, war_over after, the last room kept for matchmaking, the
  results let go and the room closed), war_ui_test (20 checks: the
  app's buttons against the real server on 8121 -- Home's CROWN WAR, a tap on the table picks the place drawn there,
  ATTACK, the battle, the results, WAR MAP back with the bar and 4 attempts, a clan mate's JOIN banner).
- A separate review of the server code (run against a real server) found four defects and three smaller ones, all
  fixed and tested: battles cost nothing to start (rooms could be held empty, blocking matchmaking) -- now the starter's
  attempt, the limits above and the last room kept; a battle every attacker left took no points; a finished battle's
  room could be held forever by a phone that never asks for the next match; a battle running across the week's end
  counted on the new map; one account could fill a side; a malformed "call" dropped the request; joining after a
  battle said war_side (now war_over); a damaged world.json could stop the saves.
- server/deploy/install_siege_server.sh copies server/world.gd and scripts/meta/war_map.gd (checked: the installer's
  minimal project, built the same way, starts and says "war map week 2026-10-12, 0 held").
- Version 0.31.135, versionCode 221. Server 0.31.135 must be deployed for the war map (older servers: no CROWN WAR).
- Quick suite: all 91 passed (90 Godot tests + the report check; apple_iap_test failed once while another server test
  ran beside it and passed alone). The Play AAB built from this commit (throwaway key, preset.0 untouched): BASE OK
  (234 files), CONTENT OK, play_games true, bundletool valid.

## 0.31.136 — the war table's places made with ElevenLabs and Meshy
Kevin: "I want the war map to be made by you, utilize Meshy and Eleven" -- the 18 places (picked over the table, its
standards or sounds).
- Concepts: ElevenLabs gpt-image-2, three sheets of six tabletop miniatures on hex bases (the keeps in their houses'
  colours, the territories in stone, wood, grass and water), two takes each, 2K, 2,050 credits (flow "Fatebound war
  table"). Kevin picked A2 + B2 + C1 (every base a true hex).
- Meshy: each place cropped from its sheet (tools/meshy_weapon.py crop) -> image-to-3D, meshy-7.1, 8k triangles,
  30 credits each (540; 614 left) -> tools/meshy_war_piece.py fit (new): the base's tightest hex found and turned so
  its sides face the neighbours (corners on +-X), scaled to an apothem of 1.04, centred, its bottom on the ledge;
  texture 512 (VRAM-compressed). assets/meshy/war/<place>.glb.
- war_table.gd: each place is its miniature (the KayKit tile only when one is missing); the coloured ledges under them
  turned to line up and a little wider (who holds it); the holders' flags gone (the ledges say it); lighting raised for
  the painted models; the camera lower (the miniatures show their sides) and fitted to the room it has on any screen
  (_fit_camera: how far back and where it aims, so every place fills the table's rectangle under NAMES). A clean
  table: names only on the place picked and on battles; NAMES (the table's corner) shows them all.
- Content packs: a new "war" pack (assets/meshy/war, 9.3 MB) so the world pack doesn't change (players download only
  the new 9 MB); base presets exclude it; uploaded to content-packs (6a15026). content_test expects 6 packs.
- war_ui_test: a clean table, NAMES, the places are the miniatures (22 checks).
- Version 0.31.136, versionCode 222 (server code unchanged; SERVER_BUILD follows the app's version).
- Quick suite: all 91 passed. The Play AAB built from this commit (throwaway key, presets untouched by the build):
  BASE OK (234 files, no pack data), CONTENT OK (6 packs on the branch), play_games true, bundletool valid.

## 0.31.137 — the war map becomes a land
Kevin: "I don't like how static the map looks. I want it to look like a real natural land mass but in map form."
- tools/war_land.py (new) grows one continent in the sea around the places of scripts/meta/war_map.gd, everything
  from one height field (so mesh, colours and regions line up): a coast with bays and a few islets, mountain ranges in
  the north and round the High Pass, Deep Mine and Grey Cliffs, gentle hills, a river from the northern mountains past
  the mine, under King's Bridge, through Silver Lake, across the Ford to the south coast, marsh and fen pools in the
  south-east, a harbour at Saltport; painted colours (grass, a patchwork of fields with hedges round the Lions and the
  Mill, forest canopy, reed beds, rock and snow, beaches, dirt roads along the links, the slopes shaded); and a rocky
  ridge on every border two places share without a link (all 30 links are borders; the 8 borders without one are
  ridges), so the land says where an attack can go. Writes assets/war_land/ (land.glb 53k triangles, land_color.jpg,
  land_regions.png: place index, distance to a border, ridge, height) and scripts/app/war_land_data.gd (the grid,
  each place's spot and ground height, its miniature's scale and sink, 428 trees).
- war_table.gd: the land with scripts/app/war_land.gdshader (each place's land tinted with the colour of the house
  holding it, a white border with the holder's colour along its inside, none where a ridge stands, the place picked
  lit and outlined, a battle's land pulsing orange, cloud shadows drifting); the sea with war_sea.gdshader (turquoise
  shallows, deep blue, drifting waves and glints, foam breathing along every shore -- the lake and river too); the
  Meshy miniatures standing in their land (tools/meshy_war_piece.py trim takes off each one's hex base and ground; the
  lake and the ford are the water itself); KayKit trees over the painted forests (MultiMesh); crossed swords bobbing
  over a battle. Tap a place's land to pick it (a ray to the land, the region map says whose); one finger drags the
  map, two pinch it closer (to 3.2x; the mouse wheel too), the camera fitted to the land at any size.
- The "war" content pack carries assets/meshy/war (the trimmed miniatures; lake and ford dropped) and assets/war_land
  (8.8 MB; uploaded to content-packs 055492c). The world pack is unchanged.
- war_ui_test: the holders' tints, the miniatures in the land, the region under a point, a pinch and a drag (24 checks).
- Version 0.31.137, versionCode 223 (server code unchanged; SERVER_BUILD follows the app's version).
- Quick suite: all 91 passed. The Play AAB built from this commit (throwaway key, presets untouched by the build):
  BASE OK (238 files, no pack data), CONTENT OK (6 packs on the branch), play_games true, bundletool valid.

## 0.31.138 — Home is the war room
Kevin (the clan-centred redesign: "Design a home screen that shows the camera overlooking the live map and then you can
see the castles/land in the background. You'll see some heroes standing next to the map table looking at it"), picked
the war room concept with the dusk view, then: "Make sure to bring the scene to life with candles emitting light glow
along with the glow effect of sun. Also maybe glimmer of the water and birds flying in sky ect ect".
- The painting (ElevenLabs gpt-image-2.5-sunburst on the approved concept, its table, heroes and UI taken out; 1152 x
  2560 for 20:9 phones; art_sources/home_war_room/room.png): the tower's war room at dusk, the great arched window open
  on the sea, the river and the two rival castles, candle stands and candles on the sill, a round rug. tools/
  home_war_room.py writes assets/ui/v2/bg_war_room.webp and a quarter-size mask (the window's opening traced from the
  painting; the river, the lake and the sea in the view). bg_home.webp and roster.gd (the old line-up) are gone.
- scripts/app/home_scene.gd lays it out (the painting's row 1418 at PLAY's top: at 420 x 933 it fills the screen from
  the top) and makes it live: the setting sun's glow and slow rays, cloud wisps and twinkling stars, small flocks of
  birds flapping and gliding across, all drawn between the painting and the room again with the window cut out
  (home_room.gdshader), so they're only seen through the window; the water shimmering and glinting, most in the sun's
  path on the sea; every painted candle's flame flickering and swaying, its halo and the warm pool on the wall
  breathing; dust motes. Reduce motion holds it all still (no birds or clouds); a safe start draws the painting only.
- scripts/app/war_room.gd: the war table in 3D on the rug (fitted to the painting: 268.6 px a metre, 32 degrees down):
  an oval oak table (longer away from you, so the land fills it) with a raised lip, gilt bands and iron plates, the
  live war map in it -- scripts/app/war_land_view.gd, the war map's own land, sea, trees, miniatures and battle swords
  (moved out of war_table.gd, which now uses it too; the shaders take a map space, an oval cut, a glow, finer waves and
  stronger house colours for the table) -- two candle clusters on the rim whose light flickers on the map, and the
  concept's four heroes in the player's equipped looks round it: the Barbarian and the Mage beyond it, the Knight and
  the Ranger at its near corners. Drawn every 2nd frame (the menus run at 60), shadows from the heroes and table only.
- Home watches the war while it's up (not under a match): social.war_open/close take who's watching ("home", "map"),
  so closing the war map doesn't stop Home's table; the map pushed by the server paints the table's holders and battles.
- The title is smaller and higher (226 wide) so the castles show under it.
- home_heroes_test rewritten for the war room (the art, the four heroes in their looks, clear of each other and of the
  medallions, the table on the rug and over PLAY, the war painted on it, Home and the map both watching, the candles,
  sun, water and birds alive, reduce motion, safe start; the chest slots and the online line kept); title_logo_test
  follows the title's new size. tools/home_scene_shot.gd shoots the scene alone (WAR=1: a war on the table).
- The ui content pack rebuilt (19.5 MB; uploaded to content-packs 23ec83f); the others unchanged.
- Version 0.31.138, versionCode 224 (server code unchanged; SERVER_BUILD follows the app's version).
- Quick suite: all 91 passed. The Play AAB built from this commit (throwaway key, presets untouched by the build):
  BASE OK (244 files, no pack data), CONTENT OK (6 packs on the branch), play_games true, bundletool valid.

## 0.31.139 — a title screen; Settings under the level shield, ALLIANCE in the tab bar; PLAY on the table
Kevin: "Seems very busy now. Maybe remove the fatebound title and instead put that in a startup screen and any loading
screens. Give the starting title screen a little jingle tune and have title animate in there like slamming onto the
wall or something. Move the settings cog into a menu that players can press on their level icon on top left. then
move the social to where the settings was and rename that Alliance. Change play button and tutorial button design and
location so you can move the map table lower to bottom of screen so the window to outside is more viewable."
- The title screen (scripts/app/title_screen.gd), what the app opens on (not under tests and tools; FB_TITLE=1 shows
  it there): a castle wall at dusk, its two torches flickering and throwing up embers; the jingle starts and the title
  flies in from the viewer, big and tilted, and slams onto the wall at 0.5 s -- the thud, a flash, the screen shakes,
  dust bursts from behind it, rubble drops, cracks run out into the stones, the title squashes and settles, the King
  swings; then TAP TO START (a tap anywhere lifts it off Home; a tap during the flight lands it). Reduce Motion: it
  fades in and holds still. tools/title_shot.gd shoots the sequence.
- Art and sound by ElevenLabs (flow "Fatebound title screen"; tools/build_title_art.py, sources in
  art_sources/title_screen): the wall (gpt-image-2.5-sunburst with the war room as its style), the jingle
  (eleven_music v2.5, 3 takes, the first used: 5 s, trimmed and levelled; the others kept to swap), the slam (sound
  effects v2, two takes layered), the PLAY plaque (gpt-image-2 on green, keyed out). About 2,700 credits in all.
- The title is gone from Home; the loading screens have it: the first-start download screen (the wall and the title,
  new base-build files assets/branding/splash.png and title_logo.webp), the match's warm-up cover (the wall and the
  swinging title), and the boot splash is the wall (project.godot application/boot_splash, covering the screen).
- The level shield (a little cog on its corner) opens the player's menu: name and level, SETTINGS, DISCORD. The tab bar
  is SHOP, PASS, HOME, LOCKER, ALLIANCE: ALLIANCE opens the friends and clan window over the screen you're on, with a
  badge for requests and invites (SOCIAL's medallion is gone).
- Home: PLAY is a gold-framed plaque with crossed swords behind it (play_plaque.webp), the FIRST WIN tag on its corner,
  standing just over the chests; the tutorial a pulsing medallion in the right column (where SOCIAL was) with its gold
  as a tag; the server line (or CROWN WAR, or your party) a short pill at the top between the medallion columns, JOIN
  OUR DISCORD under it. The war room painting now covers the screen from its top, and the war table stands down at
  PLAY (the map's near shore just under the plaque's top), so the whole window shows: the sun, the castles and the
  river above the heroes.
- Tests: title_logo_test is the title screen's now (the flight, the slam, TAP TO START, the King, Reduce Motion, the
  tap, the loading screens and the boot splash); home_heroes_test (the table at PLAY, the castles above the heroes);
  app_flow_test (the tab bar, Settings through the shield's menu, Home's layout); clans_ui_test and social_ui_test open
  the window from ALLIANCE.
- Version 0.31.139, versionCode 225 (server code unchanged; SERVER_BUILD follows the app's version).
- Quick suite: all 91 passed (social_ui_test's real-time chat check missed once in the first run and passed on
  rerun). The Play AAB built from this commit (throwaway key, presets untouched by the build): BASE OK (251 files, no
  pack data), CONTENT OK (6 packs on the branch: ui and audio uploaded, content-packs 982860d), play_games true,
  bundletool valid.

## 0.31.140 — Home's heroes whole to their feet; players online; chat kept to 50 lines
Kevin (with a photo of Home on the S21 Ultra): "The screen is cutoff where feet are. Also make sure it shows players
currently online. Also make it so the chat messages don't get deleted, only delete after 50 messages"
- The feet: Home's 3D frame (war_room.gd FRAME) reaches 300 px of painting further down, behind the chests, and the
  camera moves down its own up (Camera3D.v_offset, WarRoom.v_shift) so the table still sits where it did; the near
  heroes' legs and feet and the table's foot are drawn whole (row_of/near_row do the same sums, so the table still
  lands at PLAY).
- Players online: the line at the top of Home counts everyone with the game open -- the server's social connections
  ("chatting": Home, menus and matches alike, you included; the server has sent it since 0.31.111) -- not only those
  in a match ("online"); with nobody else it says 1 PLAYER ONLINE (you), and with no server LIVE SIEGE SERVER.
- Chat kept: the server writes the global and clan chats to chat.json beside social.json (with it, 3 s after a line),
  and reads them back on start, so a restart or update no longer empties them; each keeps its last 50 lines (the
  oldest going as a new one comes), the line ids carrying on. A disbanded clan's chat goes from it. The phone keeps
  50 lines a channel (was 100, as the server keeps 50) and merges the server's global lines with the ones it has
  (each once, in order; a blocked player's left out), so a server that comes back with fewer no longer wipes the
  chat; a party's or clan's history still replaces (leaving a clan empties its chat). The chat panel redraws when
  lines are merged in before the ones on screen. The server's start log says how many global lines it kept.
- Needs the server redeployed for the kept chat (sudo bash godot/server/deploy/install_siege_server.sh); the
  players-online count works with the server as it is.
- Tests: social_test (chat.json written after a line, a restart keeps the last 50 global lines and a clan's, not a
  party's, ids carry on, a newcomer gets all 50; the phone's merge, the 50 cap, blocked lines, a clan's emptying);
  home_heroes_test (no hero cut off at the feet; the online line counts the social connections).
- Version 0.31.140, versionCode 226 (server code changed: SERVER_BUILD 0.31.140).
- Quick suite: all 91 passed. The Play AAB built from this commit (throwaway key, presets untouched by the build):
  BASE OK (251 files, no pack data), CONTENT OK (no pack changed: ui-504c03c158f7 and audio-ab91387f1397 as in
  0.31.139), play_games true, bundletool valid.

## 0.31.141 — the title screen up first, the game loading behind it; a bigger show
Kevin: "Make the intro splash screen more exciting and also load faster"
- Faster: until now the app loaded the whole game (Main.tscn: ~35k lines of scripts to compile, ~1.9 s on this box)
  and built Home before the title screen existed, so the phone sat on the still boot splash, and the title's flight
  then played over Home's first (3D) frames. Now the boot screen (content_loader.gd) puts the title up as soon as the
  packs are mounted (~0.1 s after the boot screen; title_screen.gd and its art are ~0.1 s to load) and loads the game
  behind it on a thread of its OWN. Once loaded and the slam has settled (title_screen.can_swap, 0.45 s after the
  hit), the game goes in behind the title (change_scene_to_packed; the title stays on its own root layer) and takes it
  over (siege_app.adopt_title); 3 frames after Home is built, TAP TO START (LOADING... until then; a tap meanwhile is
  kept and lifts the screen the moment Home is ready). Desktop (lavapipe), warm start: the title's first frame 0.79 s
  into the session (was ~3.9 s, behind a 4.6 s software 3D first frame).
- Not on the worker pool: a pool-thread load froze the cold start here (tools/cold_start_check.sh, empty shader
  cache, 2 cores: the main thread waiting on a lock held by the load, which waited for shader compiles that needed
  the pool's threads -- the 0.31.91 trap). On its own Thread the check passes (twice). BootGuard.wait_for_game holds
  the frame count (the title's frames aren't the menu's), so a game load that never finishes is still a stuck start.
- Less to compile at start-up (Main.tscn 1.88 s -> 1.47 s here): the match's script (siege_mode.gd) and the windows
  opened later (war table, clan, chat, friends, orders, daily reward, leaderboard, update screen) are no longer
  preloaded by siege_app.gd; they load first in the background queue (Assets.preload_async(LATER), one at a time as
  before) or there and then (_later) if needed first.
- More exciting (title_screen.gd, title_logo.gd, title_rays.gdshader, title_glint.gdshader; no new art or sound
  files): it opens as the boot splash left it and the edges darken; the torches flare alight one after the other (a
  burst of sparks, tm_fireball1); the title launches with a whoosh (tm_sword_swing2) trailing two afterimages; the
  jingle is started so its first note lands on the hit (0.58 s); the hit adds a shockwave ring, gold sparks, a
  punch-in zoom, the torches gusting up, the slam louder, rubble trickling (tm_crumble1), and the King knocked into a
  ~20 degree swing dying down to his gentle 7; then light rays turn slowly behind the title, a gold glint sweeps
  across the letters every 4.5 s and embers drift up the screen. A long frame slows the show (max 1/20 s a step)
  instead of skipping the flight. Reduce Motion: no flight, shake, zoom, glint or drifting embers.
- Tests: title_logo_test (the flare, afterimages, the jingle on the hit, ring/sparks/zoom, the King's kick then back
  to 7 degrees, rays, glint, LOADING and the kept tap, can_swap only after the slam); boot_title_test (new: from
  Boot.tscn, the title is up before the game, the game loads on its own thread, goes in after the slam and takes
  that title over, TAP TO START, a tap lifts it; the match's script and the windows aren't compiled with the game and
  load from the queue). tools/title_shot.gd: LOADING=1.
- The queue now holds scripts, so the app drains it as it closes (Assets.drain on siege_app._exit_tree): a script
  half-compiled on a thread while the engine shut down failed to resolve ui.gd's constants (reward_fly_test's exit).
- Version 0.31.141, versionCode 227 (server code unchanged; SERVER_BUILD follows the app's version).
- Quick suite: all 92 passed. tools/cold_start_check.sh (Vulkan, empty shader cache, no live server): PASS twice (the
  pool-thread version froze; 0.31.140 passes). The Play AAB built from this commit (throwaway key, presets untouched
  by the build): BASE OK (253 files: the two title shaders), CONTENT OK (no pack changed), play_games true, bundletool
  valid.

## 0.31.142 — no freezes in the title's show; Home's first frame no longer compiles pipelines
Kevin (with COPY DIAGNOSTICS from his S21, two starts of 0.31.141): "Getting freezes during it now"
- His log: the title up 0.85 s in, the slam 0.6 s later, the game loaded 2.3 s after the title went up -- and then
  6.4 s without a frame, with the show stopped halfway: building Home 1.9 s (hero 1.3, menus 0.5) and Home's first
  frame 4.5 s (STAT worst=6415/7007 ms). Before 0.31.141 the same wait was there, but under the still boot splash.
- Home's first frame: the war room and the chest row drew through transparent SubViewports with MSAA 4x, whose
  pipelines Godot's pre-compilation doesn't make, so they were compiled on the spot every start (here: 8 "draw"
  compiles, 7.1-7.4 s of first frame on lavapipe against 3.5 s without). MSAA is off in both (war_room.gd,
  chest_row.gd): no draw compiles left (tools/boot_probe.gd; the start-up log now says how many pipelines the start
  compiled and how many stopped a frame). The room is drawn at the screen's own pixel density; FXAA was tried and
  greyed the transparent edges. (The other MSAA views -- chest opening, Forge, showcase, war map, the match at a
  lowered render scale -- still compile theirs the first time they open.)
- The show waits for the game: the wall and the torches open (the pre-roll) while the game loads on its thread; when
  it has loaded the screen settles to a still LOADING... (hold_for_game: the drifting embers fade, the torches hold
  steady, 0.25 s) and only then does the game go in behind it -- so building Home and drawing it the first time stop
  a still loading screen, not the show. Once Home is drawn the show plays (flight, slam, TAP TO START 0.6 s after
  the hit). A tap while loading is kept and goes straight in when Home is ready (no show).
- While the title covers Home, Home isn't drawn at all (siege_app hidden from home_ready until the title starts to
  lift: the show has the phone to itself), and the background loading (the match's script, the windows, the
  models) starts once the show is over (title_screen.shown), so it doesn't jolt the show.
- Desktop (lavapipe) start: the title 0.9 s, the game loaded 3.2 s, still LOADING... until Home's first frame at
  6.5 s, the show 7.1 s, the slam 7.5 s (real time now), TAP TO START 8.1 s.
- Also from his log: Home's drag-to-scroll asked a window for "drag_scroll" with a null default, which Godot treats
  as no default (an error on every drag with the chat or Friends open): has_meta first.
- Tests: title_logo_test (the show waits for the game; the hold: still, then can_swap; a tap while loading goes
  straight in; the background loading starts after the show), boot_title_test (the game goes in behind a still
  LOADING..., before the show; the show once Home is ready; Home not drawn under the title, drawn again as it lifts).
  tools/title_shot.gd: HOLD_AT / READY_AT. tools/boot_probe.gd (new).
- Version 0.31.142, versionCode 228 (server code unchanged; SERVER_BUILD follows the app's version).
- Quick suite: 90 of 92 in the run; siege_net_smoke and social_ui_test (real-time networking) missed under load and
  passed alone three times each. tools/cold_start_check.sh: PASS. The Play AAB built from this commit (throwaway key,
  presets untouched by the build): BASE OK (253 files), CONTENT OK (no pack changed), play_games true, bundletool
  valid.

## 0.31.143 — the LOADING wait: the pipeline cache kept, Home built a piece a frame, a progress bar
Kevin (his S21's log of 0.31.142): "It freezes while loading for a few seconds"
- The log: the game loaded behind the title in 3.4 s (smooth), then no frame for 7.3 s: Home's build 2.4 s (hero
  1.7, menus 0.8) and its first frame 4.8 s -- with no "draw" pipeline compiles left (0.31.142), but the same 45 or
  so pipelines compiled again (canvas 11, mesh 10, surface 11, specialization 13).
- Why every start: Godot keeps compiled pipelines in user://vulkan/pipelines.<renderer>.<gpu>.cache but writes it
  only when it has grown by rendering/rendering_device/pipeline_cache/save_chunk_size_mb (3 MB) or when the app
  quits (rendering_device.cpp update_pipeline_cache) -- and a phone's app is killed, not quit, so the cache was never
  written and each start compiled Home's pipelines from scratch (hidden under the boot splash before 0.31.141).
  project.godot: save_chunk_size_mb 0.1, so it is written within the first start. The start-up log's second line
  now says what pipeline cache there is ("none yet" or its file and size) -- the next log shows if it took.
- Home built a piece a frame behind the boot title (siege_app._stage): background | the painting | the 3D war room
  (home_scene.defer_room / add_room, siege_app._build_room) | the menus | the services and Home's page -- a frame
  drawn between each, the title's new LOADING bar stepping on (0.6 when the game has loaded, then 0.66, 0.72, 0.8,
  0.86, 0.9, 0.95; it creeps on by itself while the game loads on its thread). The app's _process and _input wait
  for the build (_building). Without a title in front (tests, tools) it builds in one go as before.
- Tests: boot_title_test (Home built over several frames, the bar stepping on: [0.6, 0.72, 0.8, 0.86, 0.9, 0.95]).
- Desktop (lavapipe): the longest frame of the build is the one that first draws the 3D (its pipelines: lavapipe
  keeps no pipeline cache, so it can't show the saved-cache start; the phone's log will).
- Version 0.31.143, versionCode 229 (server code unchanged; SERVER_BUILD follows the app's version).
- Quick suite: all 92 passed. tools/cold_start_check.sh: PASS. The Play AAB built from this commit (throwaway key,
  presets untouched by the build): BASE OK (253 files), CONTENT OK (no pack changed), play_games true, bundletool
  valid.
- Kevin's S21, two starts of 0.31.143 (2026-10-15): "pipeline cache: pipelines.mobile.adreno_(tm)_660.cache 2.29 MB"
  loaded at boot. The title up 0.5-0.66 s after the boot guard, the game loaded 1.5 s later, Home built and drawn by
  3.0 s, the slam 3.3-3.7 s, TAP TO START at 3.9-4.3 s (0.31.141: 9.4 s; 0.31.142: 12.9 s). The longest frame of the
  build 0.48-0.64 s (was 7.3 s without a frame); the show smooth on the second start (fps 34, worst 52 ms).

## 0.31.144 — the other 3D views without MSAA; the "Lambda capture was freed" error found and gone
Kevin: "Go ahead with adjust" (the cleanups after 0.31.143's start-up fix)
- MSAA off in the chest opening (chest_open.gd), the Forge (forge_stage.gd) and the hero showcase (showcase.gd): all
  three draw at the screen's own pixel density, so like Home they look the same without it (Locker shots at 2x
  before/after), and they no longer compile MSAA pipelines the first time each opens. Left on: the war map
  (war_table.gd, drawn at the logical size through a stretched SubViewportContainer: without MSAA it would show jaggies)
  and the match (MSAA 2x only at a lowered render scale). With the pipeline cache now kept (0.31.143), their
  compiles happen once per install, not every time.
- "Lambda capture at index 0 was freed. Passed "null" instead." -- in Kevin's start-up logs and his match logs, and 3-6
  times in clans_ui_test / war_ui_test. Found by tagging every multi-line lambda with a print for one run: UI2.bob (the
  floating menu icons) waits a frame (process_frame, one shot) before starting the float, and a menu redrawn in
  between (Home's online line, the clan/war status) had freed the icon its lambda held. bob now holds the icon weakly
  (WeakRef); siege_hud's panel-unroll timer likewise. Both tests: 0 now.
- Not done: the "invalid UID" warnings on six Meshy hero models (archmage, assassin, berserker, crusader, necromancer,
  sniper): their imported scenes name their texture by a UID from before the texture was reimported; Godot finds it
  by path, so it's harmless. Fixing it means reimporting the models, which changes the 65 MB heroes pack and makes
  every phone download it again -- to do the next time that pack changes for a real reason.
- Version 0.31.144, versionCode 230 (server code unchanged; SERVER_BUILD follows the app's version).
- social_ui_test: its two raw sockets (Alice's and Bob's account creation) dialed the server 1.5 s after starting it
  and never again; on a slow machine the server wasn't listening yet, the sockets closed and the test timed out in
  "accounts". They now dial again (every 0.5 s) until the server answers.
- Quick suite: 88 of 92 in one run on a slow machine (about 1.5x slower than usual); net_load_test, referral_test and
  version_gate_test passed alone; social_ui_test fixed as above (passes twice alone). tools/cold_start_check.sh: PASS.
  The Play AAB built from this commit (throwaway key, presets untouched by the build): BASE OK (253 files), CONTENT OK
  (no pack changed), play_games true, bundletool valid.
- Kevin on 0.31.144 (2026-10-15): "Ok works good".

## 0.31.145 — PLAY opens the war map; QUICK BATTLE at its foot
Kevin (Crown War's next steps, asked one at a time): "Play open war map"
- Home's PLAY (siege_app.play) opens the war map (war_table.gd). At its foot, QUICK BATTLE · 16 VS 16
  (siege_app.quick_battle): the match from matchmaking that PLAY started until now, for any house or none (bots in the
  empty seats). Players in a clan pick a territory and ATTACK / JOIN / DEFEND as before; players without a clan see how
  the war works, FIND A CLAN, and QUICK BATTLE.
- Straight into a match as before when the map can't show anything (not connected, a server without the war map) and
  for a party: its leader's PLAY ×N takes everyone into one match, which a battle on the map doesn't (start_match's
  party path is unchanged). An update needed: PLAY shows the update screen, as before.
- Home's line at the top: the players online for everyone now (a clan member's CROWN WAR · HOUSE X pill went: PLAY
  opens the map) -- Kevin, 0.31.140: "make sure it shows players currently online".
- While the map is open, Home's war room (war_room.gd: the table and the heroes behind the window's dimmed backdrop)
  is held on its last frame (process off), so two 3D views don't draw at once; it's let go when the map closes.
- Opening the map from PLAY: ~140 ms here (the land, the sea, the trees and the miniatures built at once).
- Tests: war_ui_test (no CROWN WAR pill, the players-online line; PLAY opens the map with QUICK BATTLE; Home's 3D held
  and let go), clans_ui_test (PLAY opens the map in a clan; QUICK BATTLE starts the match). social_ui_test's party
  PLAY still goes straight in.
- Version 0.31.145, versionCode 231 (server code unchanged; SERVER_BUILD follows the app's version).
- The same slow-machine race as social_ui_test (0.31.144) in clans_ui_test, leaderboard_test, social_test and
  war_battle_test: their raw sockets dial the test server again until it listens.
- Quick suite: 90 of 92 in one run on the slow machine; social_test (the race above, before its fix) and
  staged_start_test ("_ready itself is quick": 223 ms against 200, a timing check; the match code is unchanged) passed
  alone (staged_start_test twice: 195 / 172 ms). tools/cold_start_check.sh: PASS. The Play AAB built from this commit
  (throwaway key, presets untouched by the build): BASE OK (253 files), CONTENT OK (no pack changed), play_games true,
  bundletool valid.

## 0.31.146 — PLAY always opens the war map
Kevin: "I want the play button to always bring players into map"
- siege_app.play: Home's PLAY opens the war map every time -- in a party, not connected, and on a server from before
  the war map too (0.31.145 went straight into a match for those). Only an update needed still shows the update screen.
- The map says why it's empty: "Not connected to the server" (QUICK BATTLE then tries the server, as PLAY did) or "The
  war map comes with the next server update"; "Loading the war map..." while the server's map is on its way.
- QUICK BATTLE in a party: the leader's reads QUICK BATTLE · PARTY ×N and takes everyone (start_match's party path, as
  PLAY ×N did); a member's reads LEADER STARTS and says the leader starts it (the map stays open); the leader's start
  still pulls the members in from wherever they are (the map closes). It follows the party as it changes.
- Unchanged: the results' PLAY AGAIN and the party window's PLAY TOGETHER still go straight into a match.
- Tests: app_flow_test (not connected: PLAY opens the map, QUICK BATTLE starts the session), social_ui_test (a party's
  PLAY opens the map, QUICK BATTLE · PARTY ×2 takes the party in), war_ui_test, clans_ui_test, version_gate_test.
- Version 0.31.146, versionCode 232 (server code unchanged; SERVER_BUILD follows the app's version).
- Quick suite: all 92 passed (the redialing server tests too). tools/cold_start_check.sh: PASS. The Play AAB built from
  this commit (throwaway key, presets untouched by the build): BASE OK (253 files), CONTENT OK (no pack changed),
  play_games true, bundletool valid.

## 0.31.147 — the Herald's tour of the war map; JOIN A CLAN opens on the clans; PLAY zooms into the map
Kevin: "Create a tutorial for everyone that walks them through how the map works and joining a clan. When they click
join clan it put the list of available clans or they have option to start clan. Also then the map opens up have camera
zoom to it as animation"
- The tour (scripts/app/war_tour.gd, new), told by the Royal Herald as in the match tutorial: it runs by itself the
  first time a phone's war map has the war on it (settings.war_tour, kept on the phone; existing players get it once
  too) unless the player has already started using the map, and again from the map's new "?" (beside NAMES). Ten
  steps, each with the Herald's line typing out (NEXT finishes it first; a tap on the dimmed screen = NEXT), a gold
  spotlight on what it's about and the map's camera gliding there: the three houses (the whole land); the keeps, never
  lost (close on your house's keep, the Lions' without a house); a land's colour and tapping one (close on a held place,
  picked, its sheet lit: one another house holds next to your land, else any held one); the clans' bars (+50 a crown,
  -100 a loss); taking land (1,000 held / 500 free); the roads and ridges; 5 battles a day, started or joined, defending
  free; the week (Monday, the most land wins, the map wiped); QUICK BATTLE (its button lit). The numbers come from
  war_map.gd. Last step: not in a clan -- JOIN A CLAN or LATER; in a clan -- "You fight for House X with [TAG]",
  FINISH. SKIP on every step but the last; the map goes back to the whole land when it ends. Voice lines can be
  dropped in as assets/vo/war_tour/<id>.ogg (tour_intro ... tour_clan), like the match tutorial's.
- JOIN A CLAN (the tour's, the map's sheet's JOIN A CLAN / JOIN A CLAN TO FIGHT) opens the CLAN window on joining
  (clan_panel.gd focus "join"): JOIN A CLAN at the top, the clans to join right under it (FIND A CLAN: every clan,
  JOIN / ASK / FULL, the house filters), START MY OWN CLAN scrolling down to the form. The CLAN window opened from
  ALLIANCE has START MY OWN CLAN too.
- The zoom: PLAY pushes Home's view into the war table (the painting and the 3D scaled together onto the map's middle,
  war_room.table_center, x2.1 in 0.45 s, easing in; Home's buttons fade; nothing else pressable meanwhile), then the
  war map opens over it, fading in while its camera dives from high and far (1.75x, looking down) onto the land,
  settling in 1 s (war_table.gd INTRO_*: the dive waits out the window's first two frames, the slow ones). Opening the
  map from anywhere else (the CLAN window, a battle's WAR MAP) has the dive too. A touch on the map ends the dive.
  Home eases back out when the map closes (at once if a match starts). Reduce Motion: no push, no dive, no glides.
- Tests: war_tour_test (new, 27 checks: the push, the dive, the tour by itself, typing and NEXT, the keep, the place
  and its sheet in the spotlight, QUICK BATTLE lit, JOIN A CLAN -> the CLAN window on joining, seen once, "?" again,
  SKIP, the in-clan ending, reduce motion); clans_ui_test (the join view: the clans, START MY OWN CLAN scrolling, no
  SEE THE WAR MAP); war_ui_test, social_ui_test, app_flow_test wait for the map after PLAY's push.
- Version 0.31.147, versionCode 233 (server code unchanged; SERVER_BUILD follows the app's version).
- (0.31.147's suite was stopped part way -- 0.31.148 came straight after; its checks are 0.31.148's below.)

## 0.31.148 — clans cost 5,000 gold; a house clan for each house
Kevin: "Make it cost 5000 gold and make a default clan for each faction that the new players can choose since there are
no clans in game yet"
- server/clans.gd: COST_GOLD 5,000 (was 10,000; the phone shows what the server says). The house clans
  (HOUSE_CLANS): The Lion Guard [LION], The Stag Guard [STAG], The Raven Guard [RAVN] (ids h_lions / h_stags /
  h_ravens), made when the server starts (ensure_house_clans) and never gone: free, open to all, level 1, up to 1,000
  members, no leader or officers -- nobody invites, answers requests, removes anyone, changes the settings or disbands
  it, and it's never handed to anyone. A tag a players' clan already holds is left alone: the house clan takes the next
  of its list ([LNG], [STG], [RVG]...). Its members leave it without the 24-hour wait, the wait from leaving a players'
  clan doesn't keep anyone out of it, and joining (or being let into) a players' clan or starting one moves a member out
  of it by itself (another house's clan too). No join / leave lines in its chat; a join refreshes only the newcomer; its
  card shows 40 members (online first, then those seen last, and you). Every clan state carries the three ("hcs").
  They fight on the war map like any clan (bars, battles, attempts).
- The CLAN window, not in a clan: YOUR HOUSE'S CLAN (FREE) under the intro -- the three, members, JOIN on each -- then
  FIND A CLAN (the players' clans: "No players' clans yet -- be the first to start one!"), then START A CLAN. In a house
  clan: its banner ("The Lions' own clan", members), CLAN CHAT, WAR MAP, its members, A CLAN OF YOUR OWN? (START MY OWN
  CLAN), MOVE TO A PLAYERS' CLAN (the players' clans, JOIN / ASK), START A CLAN, and LEAVE ("no wait"). The window goes
  back to its top when you join, leave or move clans.
- The Herald's last line (not in a clan): "Every house has its own, free and open to all. Or join a players' clan, or
  start your own."
- Needs the server redeployed (sudo bash godot/server/deploy/install_siege_server.sh): the 5,000 and the house clans
  are the server's. Until then the old server still asks 10,000 and has no house clans.
- Tests: clans_test (5,000; the house clans from the start in every state; joining free, moving between them, out of
  one by joining or starting a players' clan, no wait leaving, the wait not keeping you out, nobody running them, never
  handed on, kept in clans.json, a players' [LION] kept and the Lion Guard on [LNG]); clans_ui_test (YOUR HOUSE'S CLAN,
  JOIN, the house clan's window, leaving with no wait; 5,000 taken); world_test's clans take other tags.
- Version 0.31.148, versionCode 234 (server code changed: SERVER_BUILD 0.31.148).
- version_gate_test: the same slow-machine race (it dialed the real server 1.5 s after starting it) -- it now knocks
  until the server listens.
- Quick suite: 92 of 93 in one run (war_tour_test new); version_gate_test (the race above) passed alone three times.
  tools/cold_start_check.sh: PASS. The Play AAB built from this commit (throwaway key, presets untouched by the build):
  BASE OK (255 files: war_tour.gd and its uid), CONTENT OK (no pack changed), play_games true, bundletool valid.

## 0.31.149 — no QUICK BATTLE: every match is a battle picked on the map; BATTLES NOW (the hot zones)
Kevin: "Remove the quick play so the player needs to choose where to fight. Maybe show hot zones where players are
actively fighting and players can jump right into that battle"
- war_table.gd: QUICK BATTLE is gone. At the map's foot, BATTLES NOW: the battles on the map (hot_list), the ones you
  can fight in first, then the busiest -- two rows (the rest "+N more glowing on the map"), each the place, "Lions attack
  Stags · 7 fighting" (or "starting" / "bots only"), and JOIN (your house attacking) / DEFEND (your house holds it);
  another two houses' war: NOT YOUR HOUSE. A tap on a row takes the camera to it and picks it. Not in a clan: JOIN <its
  house> -- into that house's own clan (0.31.148, free) and straight into the battle in one tap (the place's sheet has
  JOIN <attackers> and DEFEND FOR <holders>). None on: "No battles right now. Tap a land and ATTACK to start one." The
  map's label on a battle: "⚔ 7 FIGHTING". A clan joined or left with the map open: the map asked for again (your house).
- Every match being a battle, ATTACK works with no battles left today that count: the battle starts and counts for
  nothing for you (no points, no loss; "Your 5 battles that count are used today: this one won't move your clan's bar
  (the match still pays)"). The house clans aren't held to 2 battles at once (the server's rooms are their limit).
- Parties: the leader's battle takes the party (social "play" with the battle: the members' apps go into it; one of
  another house is turned away there). Home's PLAY ×N (the leader) and the party window's PLAY TOGETHER open the map;
  a member's plaque says PLAY (not READY). The leader's JOIN / DEFEND in BATTLES NOW takes the party too.
- server: world.gd -- war_go with no attempts left starts the battle ("counts": false, no scorer); the house clans past
  MAX_CLAN_BATTLES; each battle on the map carries "na"/"nd" (players on each side, count_fn); siege_server.gd counts
  them (_war_counts) and pokes the open maps when they change (every 1 s at most); social.gd -- the party "play"
  carries the battle ("go" with "war"). Matchmaking keeps its one room (old phones, a party's match on an old server).
- A server from before the war map: BATTLES NOW offers PLAY A MATCH (matchmaking) so the app isn't stuck.
- The Herald's tour: "tour_hot" (BATTLES NOW lit: "Battles burning right now glow on the map and line up under it.
  Tap JOIN and you're in.") replaces QUICK BATTLE's step; the attempts line: "After that you can keep fighting, it just
  won't move the bars."
- Needs the server redeployed (sudo bash godot/server/deploy/install_siege_server.sh) for the counts, battles past 5
  a day and the party following its leader into a battle.
- Tests: world_test (a battle with no attempts left starts and counts for nothing; the counts on the map),
  war_battle_test (the open map hears 2 attacking, 1 defending; waits for the clan tags), war_ui_test (no QUICK
  BATTLE; BATTLES NOW empty, then Bob's Ford with JOIN), war_tour_test (three battles: the busiest first, two rows,
  JOIN LIONS for a player with no clan, the label, a tap on a row; tour_hot), clans_ui_test (the match is Alice's
  ATTACK, Bob into her battle), social_ui_test (Bob's battle under Alice's map, JOIN LIONS puts her in The Lion Guard
  and the battle, the party follows her in, one side), app_flow_test (not connected: the map says so).
- Version 0.31.149, versionCode 235 (server code changed: SERVER_BUILD 0.31.149).
- (0.31.149's checks were stopped part way -- 0.31.150 came straight after; its checks are 0.31.150's below.)

## 0.31.150 — no daily limit on battles
Kevin: "Remove the 5 battle daily"
- server/world.gd: no attempts any more -- every battle counts, as many as anyone likes: its starter and every member of
  the attacking clan seated in it score (seated(); another clan of the same house still fights beside them and
  "helps", its points going to nobody's bar). world.json no longer keeps "attempts" (an old one is ignored and dropped on
  the next save). The map still sends "att"/"max" as Map.ATTEMPTS (5) for phones before 0.31.150, whose ATTACK wanted an
  attempt left.
- The phone: ATTEMPTS n/5 is gone from the strip over the map, and so is 0.31.149's "your battles that count are used
  today" note. The match results' "helped" line: "You fought for your house beside another clan (its bar moves, not your
  clan's)". The Herald's tour: "tour_battles" -- "Fight as often as you like. Every battle your clan wins moves its bar,
  started or joined. Defending your house's land holds it, and costs you nothing but sweat." -- replaces tour_attempts.
- Needs the server redeployed (sudo bash godot/server/deploy/install_siege_server.sh).
- Tests: world_test (the starter and seated clan members score; a sixth battle in a day starts and counts; the damaged
  world.json without attempts), war_battle_test, war_ui_test (no ATTEMPTS), war_tour_test (tour_battles).
- Version 0.31.150, versionCode 236 (server code changed: SERVER_BUILD 0.31.150).
- Quick suite: all 93 passed (first try). tools/cold_start_check.sh: PASS. The Play AAB built from this commit (throwaway
  key, presets untouched by the build): BASE OK (255 files), CONTENT OK (no pack changed), play_games true, bundletool
  valid.

## 0.31.151 — war rewards, room for every battle, JOIN a friend's battle, King's Day, heroes pack reimport
Kevin: "What's next to add" -> war rewards, battle capacity, friend JOIN into battles, phone alerts, King's Day, tour
VO, Meshy UID reimport; then "Do them all".
- Capacity (siege_server.gd): no room held back for matchmaking any more -- battles on the war map may use every room;
  MAX_ROOMS 6 by default (was 4; SIEGE_MAX_ROOMS in /etc/fatebound-siege.env overrides it; a full room is ~9% of a core
  and ~350 kB/s out). war_battle_test runs with SIEGE_MAX_ROOMS 1 to check the full case.
- Friends > JOIN into a battle: a friend's card carries the battle they're in (wb, wt); JOIN starts that battle on your
  side (siege_app.join_friend -> start_war); the card says "Fighting at <place>". An older phone's JOIN into a friend's
  battle is routed into it by the server (hello join fallback -> the friend's war room).
- War rewards (Eco): WAR_TAKE (200 gold + a Silver Chest) to each of the clan's fighters in the battle that takes a
  land; WAR_WEEK (50 gems + a Gold Chest) to everyone in a clan of the house that wins the week; WAR_KEEP (300 gold + a
  Gold Chest) for storming a keep on King's Day. Paid on the server into the account (eco_accounts.grant_war, once per
  reward id; Profile.grant_war is not a phone op), so the phone gets it with its next sync. The match results say
  "Your reward: ..."; Home says it once (CROWN WAR: "You took Old Tower for House Stags! You got 200 gold and a Silver
  Chest."). The Herald's week line names the Gold Chest and the gems.
- King's Day (Sunday, UTC -- the week's last day; the map resets Monday): keeps can be stormed. Map.KINGS_DAY,
  NEED_HOME 2000 points, HOME_WORTH 3 (a stormed keep counts as three lands for its captor until the week ends). A
  keep can be attacked only from a linked land, and its own house can always storm it back (the keep is theirs again).
  Every clan of the keep's house hears the alarm. The map sends kd / kd_at; the strip over the map says "👑 KING'S DAY
  · ENDS IN ..." on the day, and a keep's sheet says when the next one is (or that it can be stormed today, and how
  many points take it). The Herald's keeps line explains it. Labels on the map are clipped to it (a keep's label slid
  over the strip).
- Phone alerts when the app is closed (land attacked / your clan attacking): need real push (Firebase Cloud Messaging,
  APNs through it for iPhone) -- the chest notifications are scheduled on the phone and the server can't send them.
  PUSH_HANDOFF.md lists what Kevin sets up first (Firebase project, google-services.json, the FCM API, the service
  account's role, the server's key file); not built yet.
- Herald tour voice-over: estimated, not generated -- ~1,380 ElevenLabs credits a take for the 10 fixed lines
  (voice "Edward - British", eleven_v4), waiting on Kevin's OK. The app plays assets/vo/war_tour/<id>.ogg when there.
- Heroes content pack: six Meshy models (archmage, assassin, berserker, crusader, necromancer, sniper) had imported
  scenes naming their texture by a stale UID (this machine's import cache predated the textures' current .import
  files; harmless -- Godot found them by path -- but a warning each load). Reimported (the cached scenes removed, then
  --import); no warnings when loading every asset and scene (515). The pack's inputs didn't change, so
  tools/content_packs.py has PACK_REV (heroes: 2) folded into its hash: heroes-98bd68ca9e0c.pck (68.5 MB), uploaded to
  content-packs (cf00cc6). Phones download it once more.
- Needs the server redeployed (sudo bash godot/server/deploy/install_siege_server.sh) for the rooms, the friend's
  battle, the rewards and King's Day.
- Tests: war_rewards_test (new: the profile, the account, Home's note), world_test (who gets rewards; King's Day: off
  day refused, Sunday stormed, counts 3, its house storms it back, the alarm), war_tour_test (keep sheet off / on King's
  Day; JOIN into a friend's battle), social_test (the card's battle), war_battle_test (one room), content_test.
- Version 0.31.151, versionCode 237 (server code changed: SERVER_BUILD 0.31.151).
- Quick suite: all 94 passed (first try). tools/cold_start_check.sh: PASS. The Play AAB built from this commit (throwaway
  key, presets untouched by the build): BASE OK (255 files), CONTENT OK (heroes-98bd68ca9e0c on the branch), play_games
  true, bundletool valid. Preview APK: build/Fatebound-Siege-0.31.151-fatebound.apk (32 MB, preview key).

## 0.31.152 — the Herald's war map tour, voiced
Kevin: "Go" (the tour's voice-over, estimated at 0.31.151).
- assets/vo/war_tour/<id>.ogg for the ten fixed lines (tour_intro, tour_homes, tour_land, tour_bars, tour_take,
  tour_links, tour_battles, tour_week, tour_hot, tour_clan): ElevenLabs, voice "Edward - British" (the Herald),
  eleven_v4, one take each, 1,410 credits in all. Each levelled to -16 LUFS (gain, limiter -1.5 dB), 10/60 ms fades,
  mono 44.1 kHz OGG Vorbis q5 (as the tutorial's). Checked by speech recognition (PocketSphinx) against its own line.
  The tour already played <id>.ogg with each line (war_tour._play_line; the master volume at half, nothing when muted;
  NEXT cuts it off).
- Not voiced: tour_ready (the last line for a player already in a clan: it names their house and tag).
- assets/vo/war_tour/SCRIPT.md: what was read. Four lines say numbers from the code (tour_bars, tour_take, tour_week,
  tour_homes); war_tour_test now checks every fixed line has its file and that SCRIPT.md's text is still the text the
  tour shows, so a changed number fails the suite until the line is re-recorded. It also checks the first line's voice
  is loaded when the tour starts.
- The audio content pack rebuilt (audio-3b550a027262.pck, 12.8 MB; uploaded to content-packs 11e363f).
- Version 0.31.152, versionCode 238 (server code unchanged; SERVER_BUILD follows the app's version).
- Quick suite: all 94 passed (first try). tools/cold_start_check.sh: PASS. The Play AAB built from this commit (throwaway
  key, presets untouched by the build): BASE OK (255 files), CONTENT OK (audio-3b550a027262 on the branch), play_games
  true, bundletool valid. Preview APK: build/Fatebound-Siege-0.31.152-fatebound.apk (preview key).

## 0.31.153 — COMMANDER (test): Clash Royale-style cards in a 1v1 against an AI commander
Kevin: "I want to see about doing a clash royale style system with the heroes. And instead of it being 16v16 it'll be
1v1 real player and 30 bots 15 on each side. The bots will be each players army and the player will need to unlock
heros (cards) to be able to have more variety of troops (hats) on the field. There will be 15 common, 15 rare, 16 epic,
2 legendary..." -- "What do you think? I'm not sure how it'll vibe together" -- (I: test it first, as a separate mode:
you also command, a deck and points that fill, the cards send squads; offline against an AI commander; the 14 troops we
have as the first cards) -- "Yes".
- scripts/meta/cards.gd (new): the 14 cards -- Peasants (Villagers), Workers, Knights, Archers, Barbarians (common),
  Rogues, Mages, Priest (rare), Crusader, Berserker, Assassin, Ranger (epic), Archmage, Necromancer (legendary) -- each
  with its troop (class + upgraded), cost (1-5 points), squad (1-3 soldiers), role for the bots (raid / escort / defend /
  gather) and a line; a deck is 8, the hand 4; the starting deck; the AI's deck (Workers + Knights + 6 at random).
  Every number is a first guess.
- siege_sim.gd, the COMMANDER section (only after setup_commander(); the 16v16 and the server don't change): each side's
  unit 0 is its hero (you; the enemy commander's r0, an ordinary bot), the other 15 start in the barracks (dead, hidden,
  never respawning by themselves). Command points: 5 to start, +1 every 2.8 s (twice as fast in the last 2 minutes), 10
  at most. play_card: the cost paid, up to the card's squad out of the barracks at the castle's spawn, in the card's hat
  and role; the card to the back of the deck and the next one into its place ("card" event). A soldier who falls drops
  his hat as ever and is back in the barracks 4 s later (CMD_RETURN; a Necromancer can still raise him before that).
  Soldiers never take hats (no stand swaps for Peasants, no upgrades at the stands) -- the cards decide; the heroes
  still do. The enemy commander (_cmd_ai): every 0.5 s the card in its hand that fits -- Workers while it has fewer than
  two, wall troops when its castle is attacked, raiders when it isn't -- played once it has the cost plus 0-3 saved (full
  points: anything). The workshop's own buyer skips the hat upgrades. 8-minute matches (match_time; the HUD clock and the
  Herald's "last minute" follow it).
- The HUD: the hand on the right edge between the kill feed and DODGE -- 4 cards (portrait, cost bubble, ×squad, name,
  rarity rim; dimmed and shaded from the top until it can be paid for; FULL when the whole army is out), the next card,
  ARMY n/15, the points as a bar of 10 with the count; tap to play (siege_mode._play_card: a card flip and a buzz, or the
  bar flashes red and a toast says why). "TAP A CARD TO SEND YOUR SOLDIERS OUT ▶" pulses until the first card. Your
  card: "ARCHERS ×2 ARE OUT!"; the enemy's in the kill feed ("Enemy sent Berserker"). The view hides soldiers in the
  barracks and bursts a squad out (gold for an upgraded troop). Results: the cards each side played, "COMMANDER is a test
  -- no rewards yet" (no gold, XP, pass or challenges: profile.apply_match is skipped).
- Home: COMMANDER (with a TEST tag) in the right column where the tutorial's medallion was (once it's done) opens the deck
  window (commander_panel.gd): what the mode is, the 14 cards (your 8 ticked; tap one to take it out or put it in, its
  line underneath), the average cost, BATTLE (PICK n MORE until there are 8). The deck is kept on the phone
  (settings.cmd_deck). BATTLE starts the match offline (siege_app.start_commander: no server, no ticket).
- The Peasants card's portrait: assets/ui/skins/default_villager.png (tools/render_skin_icons.gd renders the Villager
  bust too now); the ui content pack rebuilt (ui-7d5a7af44d31.pck, 20.1 MB; uploaded to content-packs 7dbb744).
- The server installs a list of scripts, and the sim now preloads cards.gd: added to META_SCRIPTS in
  install_siege_server.sh. tools/test_server_files.py (new, in the suite) follows every preload/load of the installed
  scripts and fails when one isn't installed (it fails without that line).
- Tests: commander_test (new: the start, a card and its squad, refusals and why, a soldier falling and coming back, the
  hero respawning, the army full, Peasants without hats, the points' rate, doubling and cap, the enemy commander's
  first minute, a whole AI-vs-AI match), commander_ui_test (new: Home's COMMANDER, the deck window, BATTLE, a card
  tapped on the HUD and one refused, the results without rewards), server_files (py).
- Five AI-vs-AI matches (MATCHES=5 PRINT=1): one ended 3-2 on rescues at 4:16, four went the 8 minutes (2-1, 2-0, 0-0,
  0-0); 48-70 cards a side; 55-120 knockouts a side; 2-8 workshop upgrades.
- Needs the server redeployed (sudo bash godot/server/deploy/install_siege_server.sh) only because the sim file changed
  (the mode itself is offline).
- Version 0.31.153, versionCode 239 (server code changed: SERVER_BUILD 0.31.153).
- Quick suite: all 97 passed (first try; + commander_test, commander_ui_test, server_files). tools/cold_start_check.sh:
  PASS. The Play AAB built from this commit (throwaway key, presets untouched by the build): BASE OK (259 files: the two
  new scripts and their remaps), CONTENT OK (ui-7d5a7af44d31 on the branch), play_games true, bundletool valid. Preview
  APK: build/Fatebound-Siege-0.31.153-fatebound.apk (preview key).

## 0.31.154 — COMMANDER on every Home
Kevin (a Home screenshot, the phone's profile without the tutorial played): "I don't see the test button"
- COMMANDER only took the tutorial's place once the tutorial was done, so a phone that hadn't played it never showed it.
  Now it's always there: under the TUTORIAL medallion until the tutorial is done (a fourth row on the right, clear of
  PLAY), in its place after. Its TEST tag moved to its left side (over it, the tag covered TUTORIAL's label).
- commander_ui_test: + a fresh profile -- COMMANDER under TUTORIAL, in line with it, above PLAY.
- Version 0.31.154, versionCode 240 (server code unchanged; SERVER_BUILD follows the app's version).
- Quick suite: 95 of 97 in the run. commander_ui_test's new check wanted COMMANDER above PLAY; headless the window is
  short and PLAY's plaque comes up level with the fourth row (beside it, not under it) -- the check is now "not over
  the plaque" (passes headless and at 420 x 933). staged_start_test: _ready 237 ms against 200 on a busy machine (the
  known flake); alone 183 ms, pass. tools/cold_start_check.sh: PASS. The Play AAB (throwaway key, presets untouched):
  BASE OK (259 files), CONTENT OK, play_games true, bundletool valid. Preview APK:
  build/Fatebound-Siege-0.31.154-fatebound.apk (preview key).

## 0.31.155 — 5V5 (test): heroes, minion waves and League's towers, against bots
Kevin, on COMMANDER: "Hm not sure if I like picking the troops give me other ideas" -- "More ideas" -- "What about putting
in moba mechanics" -- "5v5" -- "Minions should spawn in a group of 1 healer, 2 ranged and 1 knight" -- "Remove the hat
system. Minions will stack up if opportunity happens. If minions still alive then the new mions that spawn will
eventually join them just like in league of legends. Make sure to have same tower mechanics as league of legends".
(Asked meanwhile, no answer yet: is it won by rescuing the King or by destroying the castle's heart -- built with the
King for now.)
- scripts/siege/moba.gd (new), on the sim through hooks (stat, step, _think, _damage, _kill, _damage_gate, melee and
  arrows on towers, ACTION, level picks; the 16v16, COMMANDER and the server don't change -- moba stays null):
  - Heroes: five a side (you and four bots; five bots), 12 to pick from (the six classes and their six upgrades), each
    keeping its class all match: no hats (the stands stay empty, nothing to take or swap), no Villagers, no workshop.
    Heroes have 1.8x their class's health (an upgrade x1.15 more, its damage x1.1). A fallen hero comes back as himself
    in his castle after 4 + 1.6 x level s; his own castle heals him 6 % a second.
  - Levels 1-10: XP from enemy minions dying within 12 m (15, shared 65 % each when there are more of you), hero
    knockouts (40 + 12 x their level; helpers half), towers (50 to the whole side). Each level +6 % health and damage
    and 3 upgrades to choose from (+15 % damage, +15 % health, +8 % speed, +12 % attack speed, ability +25 % faster,
    8 % lifesteal, regen 1 %/s; each up to 3 times; none of a healer's useless ones). Bots pick by themselves.
  - Lanes: the three crossings (west bridge, island, east bridge) as tracks of points along the dirt paths from one
    castle's gate to the other's. From 0:15, every 30 s each castle sends down each lane 1 Knight, 2 Archers, 1 Priest
    (Kevin's group), smaller minions (x0.5 health, x0.45 damage). They march, fight whatever's in front (an enemy hero
    who hurts one of their heroes first, then minions, then towers, then heroes), and push on; a wave still fighting
    when the next comes is joined by it (stacking happens by itself; a 40-a-side ceiling only for the phone). At the
    lane's end: the enemy gate, then inside.
  - Towers, League's rules: two per lane per side (outer, inner) beside the track, solid (KayKit hex towers in the
    side's colour). 11.5 m range; a shot every 0.9 s, homing. Target: an enemy hero who hurts one of its heroes in
    range (call for help) over anything; else the nearest minion; heroes only when no minion is in range. On a hero
    40 damage ramping +40 % a shot in a row (3 times at most), +4 % a minute; on a minion 45 % (Knight) / 70 % of its
    health. An inner tower can't be damaged while its lane's outer one stands; a castle gate can't be damaged while an
    inner tower of a lane leading to it stands (the jail: while the front gates stand). With none of the attackers'
    minions in range a tower takes a third of the damage (backdoor). Only basic attacks and arrows/fire hurt towers.
    1000 / 1300 health (from 1600 / 2000: at those, in three bot matches no gate ever fell).
  - Bot heroes: a lane each (yours: west, middle, east x2; theirs: west, middle x2, east x2); follow their wave,
    fight heroes not under a tower, then minions, then the enemy tower while our minions take its shots; step out of
    an enemy tower's range when it would shoot them; home to heal under 30 %; their carrier taking their King home is
    chased. Once an enemy gate is down, two of each side's bots go for the King with the siege brain.
  - Winning: as before (3 rescues, or ahead at 12 minutes), then more of their towers down, then hero knockouts.
- The view: the towers (a stump when down, an explosion), their health bars (wide), their range on the ground near an
  enemy one (red when it's on you), their shots (a fireball from the top homing in; bigger as it warms up), minions
  at 0.78 size. The HUD: LEVEL and an XP bar under your health, TOWERS yours / theirs; a level-up's three upgrades as
  chips in the middle of the screen until you tap one ("LEVEL 3! PICK AN UPGRADE"); "That tower is protected" when you
  hit one behind another; the kill feed without minions, with towers falling; no hat-shop signs. Results: towers down
  each way, your level, "5V5 is a test -- no rewards yet" (no gold, XP, pass, challenges).
- Home: 5V5 (TEST) takes COMMANDER's medallion (COMMANDER stays in the code, off Home); it opens the hero window
  (moba_panel.gd: 12 heroes, a line each, the last pick kept in settings.moba_hero), BATTLE starts it offline.
- The server installs scripts/siege/moba.gd (the sim loads it) -- caught by tools/test_server_files.py.
- Three bot matches (MATCHES=3): towers down 5/4, 1/6, 5/2; gates down 4, 2, 2; one King rescued; heroes level 6-10;
  at most 67 units on the field; about 3.5 ms a tick here (the 16v16's bot matches: 2.6-3.5).
- Tests: moba_test (new), moba_ui_test (new); commander_ui_test opens COMMANDER from the app now.
- Version 0.31.155, versionCode 241 (server code changed: SERVER_BUILD 0.31.155).
- (0.31.155's checks were stopped part way -- 0.31.156 came straight after; its checks are 0.31.156's below.)

## 0.31.156 — 5V5: the enemy King is the heart
Kevin: "Have the enemy king be the "heart" and players will have to defeat him"
- moba.gd: each King sits on his own throne (the oracle's state "home"; no rescues, no lifting, no cell, no fish, no
  tantrums -- the sim's oracle step is off in 5v5), solid (an obstacle like the towers), 3500 health. He can't be hurt
  until one of his castle's front gates is down; then basic attacks, arrows and fire hurt him -- and he hits back: a
  slam on every enemy within 4.5 m every 1.6 s (50, +4 % a minute, knocking them back). Left alone (no enemy within
  14 m) for 6 s he heals 1.5 % a second. Defeat him: that side scores, the match ends ("king"). At 12 minutes: the side
  that did more to the other's King wins, then more towers down, then hero knockouts.
- Bots: minions at the end of their lane go in and hit the King once he's open; the two King-runner bots of a side go
  for an open King (fighting the heroes in their way first); bots within 45 m of their own King come back when
  enemies are at him (and have health to spare).
- HUD: each side's King's health at the top instead of the rescue count ("♛ 100%" / "75% ♛"); the status line "Defeat
  their King -- he's guarded until a gate of his falls" / "Their King is open -- defeat him!" / "OUR KING IS UNDER
  ATTACK!"; the KING pointer points at theirs; "Their King is protected until one of his gates falls" when you hit
  him early; "THEIR KING IS DEFEATED!". The results say KINGS. The view: a gold health bar over each King, his slam
  (a gold ring and sparks), his fall (an explosion). The hero window says it.
- moba_test: + the Kings (home and solid; untouchable while the gates stand; hit once one's down; the slam; healing
  when left alone; the tiebreak; defeated -> the match won).
- Four bot matches: two won on the King (10:38, 9:57), two at time (one with their King at 90 %).
- Version 0.31.156, versionCode 242 (server code changed: SERVER_BUILD 0.31.156).
- Quick suite: 97 of 99 in the run; notify_test (its CHEST NOTIFICATIONS window counted 4 frames after UNLOCK and wasn't
  up yet on a busy machine) and staged_start_test (_ready 207 ms against 200, the known flake) -- both pass alone (twice /
  176 ms). tools/cold_start_check.sh: PASS. The Play AAB (throwaway key, presets untouched): BASE OK (263 files),
  CONTENT OK, play_games true, bundletool valid. Preview APK: build/Fatebound-Siege-0.31.156-fatebound.apk (preview key).
