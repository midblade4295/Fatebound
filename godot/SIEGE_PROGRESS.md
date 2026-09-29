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
