# Fatebound Siege — handoff for the next agent

Owner: Kevin (GitHub `midblade4295`, repo `midblade4295/Fatebound`). Solo indie dev. Tests every
build on a **Samsung Galaxy S21 Ultra** (Adreno 660, 1440×3200).

**How Kevin works:** terse and directive. Read the actual code before answering; never guess.
He pushes back hard on claims not grounded in the files. Show evidence (test output, diffs,
screenshots), not assurances.

---

## 0. First steps (do these before anything else)

1. **Get the branch.** It is NOT on GitHub yet (35+ commits exist only in a git bundle).
   Kevin has `Fatebound_Siege_FULL.bundle` and `push_siege_branch.sh`. On a machine with
   push access:
   ```bash
   bash push_siege_branch.sh /path/to/Fatebound_Siege_FULL.bundle ~/Fatebound
   ```
   It clones if needed, verifies the bundle, creates local branch `claude/kaykit-3d-rebuild`,
   checks the expected tip hash and pushes **without force**. Manual equivalent:
   ```bash
   git clone git@github.com:midblade4295/Fatebound.git && cd Fatebound
   git bundle verify /path/to/Fatebound_Siege_FULL.bundle      # needs d43282a (on origin)
   git fetch /path/to/Fatebound_Siege_FULL.bundle claude/kaykit-3d-rebuild:claude/kaykit-3d-rebuild
   git checkout claude/kaykit-3d-rebuild
   git push -u origin claude/kaykit-3d-rebuild
   ```
   The bundle's base `d43282a` is on `origin/codex/fatebound-visual-rebuild`; a normal clone
   has it. (Older bundles named `..._0.x.bundle` need `4ab80fb`, which is NOT on GitHub — ignore them.)
2. **Check the state is clean:** `git status` and `git log --oneline -5`. Read
   `godot/SIEGE_PROGRESS.md` (the running log; newest rounds at the bottom).
3. **Run the tests** (section 5). Everything must pass before you change anything.
4. **Do work in small committed steps** and append to `godot/SIEGE_PROGRESS.md` in the same commit.
   Earlier sessions were cut off mid-task several times and left uncommitted, untested edits.
   If you find uncommitted changes you did not make, read and test them before building on them.

---

## 1. What the game is now

Fatebound was a dice-battle game. **Siege is now the whole game** (Kevin's decision): a Fat
Princess–style real-time capture game, offline vs bots. Dice survive only at the class forge.
Renderer **stays Vulkan** (Kevin's decision; see section 8).

- **Modes:** offline (ENTER BATTLE: you + 31 bots) and **online** (PLAY ONLINE: up to 32 humans
  on Kevin's server, bots fill the rest; section 10).
- **Match:** 16 v 16 (human + 15 bots vs 16 bots). Field 52 × 104 m. 12-minute cap. First to
  3 rescues wins; at time, more rescues wins, then more kills.
- **Each team's Oracle** (the "princess") starts captive in the ENEMY castle's dungeon cell.
  Carry yours from their dungeon to your own throne room.
- **Castle** (identical layout, red is the point mirror of blue): front wall with two gates,
  flanking towers and corner catapult towers, courtyard (spawn, forge, workshop/stockpile),
  inner ledge with stairs up to raised back rooms: **dungeon** (cell with bars on three sides,
  open front) and **throne room**, either side of the keep. Side walls. Midfield: a raised
  plateau with stairs, forests, quarries, cover rocks, six cake trees.
- **Gates:** 1500 HP. Open (doors swing on hinges) for allies, block enemy units and projectiles
  until broken. Class damage multipliers vs gates. A broken gate is rubble for 20 s and can't
  be rebuilt with an enemy within 6 m; workers repair it (solid again at 35 %). Repairs pause
  while the gate was hit in the last 3 s.
- **Classes** (forge dice: roll 3 d-faces, pair = class, triple = upgraded, FATE wild; Fourth Die
  upgrade adds a die): Villager (start), Worker (free at workshop), Knight/Paladin,
  Barbarian/Berserker, Rogue/Assassin, Ranger/Sniper, Mage/Archmage.
- **Gathering/crafting:** workers chop trees and mine stone (carry 5), deliver to the stockpile,
  repair gates, raise siege ladders on enemy walls (8 wood; private crossing for their team;
  enemies can knock it down). Workshop team upgrades: Reinforced Gates (2), Armory (3),
  Fourth Die (1), Catapults (1). Bot quartermaster saves toward a plan; on the human's team it
  only spends surplus (2× cost) so the player chooses first.
- **Oracle rules (from Kevin's Fat Princess screenshots):**
  - Cake trees (6, neutral) ripen a cake every 60 s. Feed cake to the ENEMY Oracle held in your
    dungeon. 3 cakes = one size stage; stages 0–5 need **1–6 lifters** to carry her. She is
    visibly wider each stage. A rescue resets her size.
  - Multi-player lift: first lifter leads (a human who joins takes the lead); followers hold a
    ring around the lead. Not enough hands → she won't move. Extra hands +10 % speed each.
  - Captors must carry a dropped Oracle back to their cell (no instant recapture).
  - **Tantrum:** on the ground 6 s → knockback 4 m + 1.6 s stun to everyone within 5 m, every 6 s.
    Back to her cell after 25 s untouched.
  - **Healing aura:** captive, she heals her own team within 3.2 m at 12 hp/s.
  - **Blessing (NOT in Kevin's screenshots, added for balance):** while her own team carries her
    she heals them within 4.2 m. Same 4 seeds: 7 rescues with it, 2 without. One constant,
    `BLESS_R` in `siege_sim.gd`. Kevin was told; he may want it removed.
- **Meta:** home screen's main card is SIEGE / ENTER BATTLE. Rewards via `progression.grant()`:
  win 120 gold / 60 XP / 12 season pts / +1 chest, draw 70/40/8, loss 40/25/5; plus 40 gold +
  15 XP per personal rescue, 4 gold per KO, 1 gold per resource delivered, 1 gold per 50 gate
  damage. Granted once per match. Daily Raid, Hero Academy and daily quests are hidden from home
  (dice code still exists, unreachable; tests still reach it by route).

---

## 2. Code map (all under `godot/`)

| File | Lines | Role |
|---|---|---|
| `scripts/siege/siege_sim.gd` | ~2000 | **All rules.** Pure simulation, no scene nodes, fixed 30 Hz `step()`. Map, walls, gates, nav (AStarGrid2D per team), spatial buckets, combat, projectiles, Oracles, cake, workers, upgrades, catapults, ladders, bot AI, commander, rewards. |
| `scripts/siege/siege_view.gd` | ~1200 | 3D presentation from KayKit models: terrain (MultiMesh hexes), castles built from `sim.walls`/`sim.gates`, actors (animated rigs), Oracles, cakes (primitive meshes), projectiles, effects, follow camera. Reads the sim; never changes rules. |
| `scripts/siege/siege_hud.gd` | ~700 | Hand-drawn multitouch HUD (stick + ATTACK/ABILITY/DODGE/ACTION), scoreboard, status lines, forge/workshop/pause/result panels, world-projected HP and gate bars, toasts. |
| `scripts/siege/siege_mode.gd` | ~230 | Owns SubViewport + sim + view + HUD. 60 fps cap, render scale, thermal guard, rewards grant. |
| `scripts/siege/siege_net.gd` | ~260 | Online protocol v1: snapshot encode (int16-packed units, zstd) and apply onto a mirror sim; interpolation. Shared by server and client. |
| `server/siege_server.gd`, `server/siege_probe.gd`, `server/deploy/` | | Headless authoritative server, health probe, systemd unit, Caddy fragment, install script (section 10). |
| `scripts/siege/siege_diag.gd` | ~260 | Field diagnostics: `user://siege_diag.log` (per-second STAT lines, stalls, engine errors, logcat on stall). Home card button "COPY SIEGE DIAGNOSTICS" puts it on the clipboard. |
| `scripts/app/` | | Round 5 app shell (entry via `scenes/Main.tscn`): `siege_app.gd` (chrome, tabs, match launch), `screens.gd` (Home, Pass, Shop, Locker, Settings), `ui.gd`, `icon.gd`, `showcase.gd`. |
| `scripts/meta/` | | `economy.gd` (tables + pure functions), `profile.gd` (user://siege_profile.json, migration from the old save). |
| `scripts/siege/asset_cache.gd` | | PackedScene cache for Siege models. |
| `assets/kaykit/` | | KayKit packs (CC0; licences included): `hex/` castle/props, `heroes/`, `anim/` rigs, `weapons/`, `forest/`. |
| `SIEGE_PROGRESS.md` | | Running log of every round/step, tuning results, known issues. |
| `tools/run_siege_tests.sh`, `tools/build_siege_preview.sh` | | One-command test and build (section 5). |

**Coordinates:** `Vector2(x, z)` on the ground. Blue = team 0 at +z, red = team 1 at −z; red is
the point mirror. Castle geometry is authored in castle-local blue space (x −13..13, z 15..29,
back at 29) and placed with `Sim._c(team, p)`; world-space things (resources, plateau) use
`Sim._m(team, p)`. `Sim.height_at(p)` gives visual floor height (the sim stays 2D; ledges are walls).

---

## 3. Invariants — do not break these

- **Sim/view split:** rules only in `siege_sim.gd`; the view and HUD only read sim state and
  events (`drain_events()`). Keep the sim deterministic for a seed (future online server).
- **Walls are segments with radius**; units slide along them. New walls/obstacles must be added
  in `_build_map()` (before `_build_buckets()` and `_build_nav()` in `setup`) or collision and
  pathfinding won't see them.
- **Clamp to the field before wall push-out** (`_separate`), and walls that meet the field edge
  run 1 m past it. Both fix real "unit pinned inside a wall" bugs.
- **Anything that moves units after the collision pass** (lift followers, tantrum knockback)
  must resolve walls itself (`_push_out`, `_knockback`). The smoke test checks every unit every
  3 ticks: `wall_violations=0 gate_violations=0` is required.
- **Gate segment = the doorway only** (±1.3 m); the neighbouring wall ends cover the pillars.
- **No per-frame GPU buffer churn** in Siege: no `Label3D` (damage numbers/HP bars are 2D HUD),
  no per-frame material/shader-param writes, shared cached materials. These were suspects in a
  field freeze (section 8).
- **Renderer:** Vulkan only (0.31.92). `project.godot` keeps both renderer methods on `mobile`,
  `rendering_device/fallback_to_opengl3=false` and no `project_settings_override`.
  `build_siege_preview.sh` refuses to finish otherwise, and checks the manifest requires Vulkan 1.1.
- **Brightness is measured, not eyeballed:** `VULKAN_*` constants in `siege_view.gd`
  (exposure 1.55, ambient 2.25) match Vulkan to Compatibility mean luminance; the home
  showcase reuses them (exposure x0.8).
  Backdrop shaders use `source_color` uniforms. Don't change without re-measuring.
- **Preview identity:** package `com.fatebound.kaykitrebuild`, preset "Android KayKit Rebuild",
  signed with Kevin's preview key (alias `fbpreview`, store/key password `fbpreview`,
  cert SHA-256 `1011fc79…3b38b87`). Bump `version/code` every build (next = **21**) and
  `BUILD` in `siege_diag.gd`. Never use the Play upload key for previews.
- **Repo rules (from the root `AGENTS.md`):** new task branches, no force-push, no merge to main,
  no save resets, no Play release, don't touch Legionary/Caddy or production signing.

---

## 4. Current tuning (from `siege_sim.gd`)

| Area | Values |
|---|---|
| Match | 30 Hz tick; 16 per team; 720 s; 3 rescues; respawn 5 s |
| Field | HALF_W 26, HALF_L 52; castle back at local z 29 (shift 23) |
| Gates | 1500 HP; solid again at 35 %; repair lock 3 s after a hit; rubble 20 s / no enemy within 6 m; repair 30 HP per 0.5 s tick, 1 material per 3 ticks |
| Workers | carry 5; 0.9 s per unit gathered; bots: 3 per team (one wood-first, one stone-first) |
| Upgrades (wood/stone) | Gates 15/10, 25/20 · Armory 10/15, 20/25, 30/35 · Fourth Die 10/20 · Catapults 15/25 |
| Catapults | every 4.5 s, range 5–22 m, 45 dmg, 2.6 m blast |
| Ladders | 8 wood, 3 s build, 250 HP, crossing at 0.5× speed |
| Oracle | cake 60 s/tree, 3 cakes/stage, lifters [1..6], weight slow −8 %/stage, carry ×0.65 (rogue 0.72), +10 % per extra lifter; tantrum after 6 s every 6 s, r 5, push 4, stun 1.6; heal r 3.2 @ 12/s; blessing r 4.2; drop return 25 s |
| Roles (16) | 7 raid (incl. human slot), 3 escort, 3 defend, 3 gather |

---

## 5. Build, test, install

**Toolchain:** Godot **4.7.2-stable** (`Godot_v4.7.2-stable_linux.x86_64`) + its Android export
templates in `~/.local/share/godot/export_templates/4.7.2.stable/`; JDK 17+; Android SDK
(`ANDROID_HOME`) with build-tools (zipalign, apksigner). Download:
`https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/`.

**Tests** (headless, ~3 min; `--quick` ≈ 2 min):
```bash
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 godot/tools/run_siege_tests.sh [--quick]
```
Runs and checks the pass marker of each: `siege_sim_smoke` (6 full 16v16 bot matches with the
wall/gate clip invariants, asserts ≥1 rescue; `SEEDS=11,22` to choose), `siege_reach` (every
objective reachable for both teams), `siege_mode_smoke`, `siege_human_soak` (synthetic touch
input; must report `stalls=0`), `siege_diag_smoke`, `siege_guard_smoke`, `siege_logcat_filter`,
`siege_net_smoke` (starts the real server as a separate process on port 8092 and plays through
it; must run in REAL time, never `--fixed-fps`), `parse_all` (every script loads),
`meta_economy_test` (economy + profile), `app_flow_test` (the app through its real buttons,
REAL time).
Diagnostics (not in the runner):
`tests/siege_profile.gd` (ms per tick by phase; last: 0.99 ms at 16v16) and
`SEED=33 … tests/siege_trace.gd` (match timeline: gates, pickups, drops, rescues, tantrums).

**Screenshots on Vulkan** (verify visuals; the software renderer is slow but correct):
```bash
xvfb-run -a $GODOT --rendering-method mobile --fixed-fps 30 --resolution 420x780 --path godot -s <script>
```
`siege_view.gd` has `cam_override = [eye, target]` for test shots. Brightness comparisons use
`--rendering-method gl_compatibility` vs `mobile`.

**APK** (signed with the preview key so it installs over earlier previews):
```bash
GODOT=… KEYSTORE=/path/to/fatebound-siege-preview.jks godot/tools/build_siege_preview.sh
```
The GitHub workflow `.github/workflows/build-kaykit-preview.yml` builds this APK on every push to
`claude/kaykit-3d-rebuild`, **but signs with a new throwaway key each run**, so those APKs can't
install over each other or over Kevin's current build. To fix: store the preview .jks as a
base64 repo secret and sign with it in the workflow (do not commit the .jks; the repo is public).

Kevin installs by downloading the APK on the phone. Latest delivered: **0.11.1-siege-online,
version code 20** (PLAY ONLINE needs the server deployed, section 10).

---

## 6. Known issues and next work (in priority order)

1. **Most matches end on time.** 6-match smoke: 10 rescues total, one match won 3–2 on rescues,
   the rest at the 12-minute cap (three 0–0). Levers: raider coordination/escort formation, carry
   route choice, respawn time at 16v16, defender count. Use `tests/siege_trace.gd` to see where
   carries die.
2. **Side bias:** blue won 5 of the last 6 bot matches (earlier rounds favoured red). Small
   samples — run more seeds before changing anything.
3. **Bots rarely raise ladders at 16v16**; catapults bought in only some matches (economy
   dependent). The smoke test reports these but doesn't assert them.
4. **Unverified on device:** 0.9.0 switched 3D to 100 % physical resolution (was ~25 %:
   336×746 on a 1440×3200 screen). 16v16 + big map in 0.10.0. Draw calls measured lower than
   0.9.0 (110–285 vs 315), but fill-rate/thermals on the S21 Ultra are unknown. Ask Kevin for
   "COPY SIEGE DIAGNOSTICS" output after a full match. Pause menu has Resolution 100/75/50 %;
   the thermal guard drops to 30 fps, then to 75 % resolution.
5. `siege_human_soak` stops at its own 400 s cap before the 720 s match ends — extend it.
6. Online is built and tested locally but **not deployed** (section 10). No client-side
   prediction yet: your own movement shows after one round trip (~100 ms + ping). No accounts,
   names are "Player", no lobby/matchmaking beyond "one match, join any time".
   Dice-era hero page / weapon shop don't affect Siege classes yet.
7. Kevin may want the Blessing removed (section 1).

---

## 7. Security issue in the repo (tell Kevin; don't fix silently)

The **Play Store upload keystore** is committed (`android/keystore/upload.jks.b64`) and its
password is in plain text in `.github/workflows/build-aab.yml`. The repo is publicly readable
(unauthenticated clone works). Anyone can sign an APK/AAB as Kevin's upload key. Recommended:
request an upload-key reset in Play Console, move signing material to GitHub Actions secrets,
remove the files, and consider making the repo private. Rewriting history requires a force-push
— only with Kevin's explicit authorization.

---

## 8. History you need (hard-won)

- **GPU freeze (S21 Ultra):** builds 0.7.3–0.7.7 froze the GL render thread after ~5,300–6,000
  frames regardless of load. 0.7.8 switched to Vulkan AND removed Siege-only GPU features at the
  same time → no freeze. An OpenGL A/B build was made; Kevin chose to stay on Vulkan, so the
  root cause (OpenGL driver vs removed features) was never isolated. Don't reintroduce
  per-frame GPU buffer churn, Label3D, or billboard-shader bars.
- **Vulkan brightness:** Vulkan lights in linear space; the same settings rendered ~half as bright
  as Compatibility. All compensation constants were tuned by measured mean luminance, and
  compensation uses light energy (not exposure) where unshaded backdrops exist.
- **Resolution:** until 0.9.0 the 3D viewport used logical size (blurry on the phone).
- **16v16 perf:** `_separate` tested every unit against every wall: 2.36 ms/tick → 0.99 ms with
  6 m spatial buckets. Nav grid built by stamping bounding boxes (setup ~3 ms).
- **Stalemates:** at 16v16 workers out-repaired assaults (repair lock + rubble fixed it);
  carriers died on the ~90 m run (carry speed, extra lifters, bots wait for enough hands,
  blessing).

---

## 9. Handoff package contents (what Kevin was given)

| File | What |
|---|---|
| `SIEGE_HANDOFF.md` | This document (also committed at `godot/SIEGE_HANDOFF.md`). |
| `Fatebound_Siege_FULL.bundle` | Git bundle: `d43282a..claude/kaykit-3d-rebuild` (all Siege work + these docs). |
| `push_siege_branch.sh` | Applies the bundle to a clone and pushes the branch (no force). |
| `fatebound-siege-preview.jks` | Preview signing key (alias/passwords `fbpreview`). Keep out of the repo. |
| `Fatebound-Siege-0.11.1.apk` | Latest build (version code 20): offline + PLAY ONLINE. |

---

## 10. Online multiplayer (Kevin's server)

**Server host:** `136.113.125.3` (`https://136-113-125-3.sslip.io`), user `midblade4295`, Caddy in
front. Existing services: Fatebound web/saves on 127.0.0.1:8080, the old dice arena on 8081
(`fatebound-arena.service`, Node), Legionary on 3000. **Siege uses 127.0.0.1:8082.**
Public URL the app uses: `wss://136-113-125-3.sslip.io/fatebound/siege/ws`
(`siege_net.gd` `DEFAULT_URL`; desktop override: env `SIEGE_URL`).

**Architecture:** the server is headless Godot running the same `SiegeSim` as offline play
(authoritative, 30 Hz). Bots hold every slot; a joining player takes a bot on the team with fewer
humans; a leaver's unit goes back to a bot. New match 15 s after one ends; stops simulating
after 30 s with nobody connected. Clients keep a mirror sim built by `setup()` (same map) and
overwrite its dynamic state from 10 Hz snapshots, interpolating positions; inputs go up at
20 Hz plus actions immediately. Server validates everything (action whitelist, clamped move,
size + rate limits). Protocol version `Net.VERSION` = 1; bump it on any wire change (old clients
get "Update the game to play online").

**Measured (32 clients, local):** 845 B per snapshot, 8.3 KB/s per phone (~30 MB/hour),
267 KB/s server upload, 9.9 % of one core, 118 MB RSS.

**Deploy (on the server, from a checkout of this branch):**
```bash
cd ~/Fatebound && git fetch && git checkout claude/kaykit-3d-rebuild && git pull
sudo bash godot/server/deploy/install_siege_server.sh
```
Installs Godot 4.7.2 (SHA-512 verified) to `/opt/godot-4.7.2`, a 176 KB server-only project to
`/srv/fatebound-siege`, the `fatebound-siege` systemd service (DynamicUser, read-only, loopback),
and ends with a probe that must print `PROBE_OK`. Re-run it to update. Tested here in its
`NO_SYSTEMD=1` mode and as an unprivileged user from a read-only folder.

**Caddy (one-time, Kevin's call — repo rules forbid unapproved Caddy changes):** back up the
Caddyfile, add `godot/server/deploy/caddy-route.fragment` inside the sslip.io site next to the
`/fatebound/arena/*` block, `caddy validate`, `systemctl reload caddy`, then the public probe:
`SIEGE_PROBE_URL=wss://136-113-125-3.sslip.io/fatebound/siege/ws /opt/godot-4.7.2/godot --headless --path /srv/fatebound-siege -s res://server/siege_probe.gd`.
Record the deployment like the arena did (`multiplayer/*/live-deployment.json` style).

**Operate:** `journalctl -u fatebound-siege -f` (joins, leaves, match starts/ends),
`systemctl restart fatebound-siege`, overrides in `/etc/fatebound-siege.env`
(`SIEGE_MAX_PLAYERS`, `SIEGE_LOG`). Previous install kept at `/srv/fatebound-siege.prev`.

---

## 11. Round 5: Siege-only app, Siege Pass, shop, economy (branch `claude/siege-dev-r5`)

Based on live `447b97a`. Preview **0.12.0-siege-app, version code 21** (APK 38 MB, was 76 MB).
- **Entry:** `scenes/Main.tscn` -> `scripts/app/siege_app.gd`. Tabs: Home (3D hero showcase,
  VS BOTS / ONLINE 16v16, PLAY, first-win banner, pass summary, daily + weekly challenges),
  Pass (30 tiers, free/premium, claim all, premium for 950 gems), Shop (weekly featured for gems,
  daily deals for gold, gems->gold), Locker (per-class skins/weapons, titles), Settings.
- **Economy/profile:** `scripts/meta/economy.gd` (all tables and formulas) and
  `scripts/meta/profile.gd` (`user://siege_profile.json`, atomic writes). Everything sold is
  cosmetic; no real-money purchases (Play Billing not integrated). Season 1 starts 2026-10-01 UTC.
- **Migration:** first launch converts the old save once (gold 1:1, tokens -> gems, old weapons
  250 gold each, chests 150 each, level kept); `user://fatebound-save.json` is never modified.
  Settings can import pasted old progress once if there was no local save.
- **Cosmetics in battle:** only the local player's look is applied (skin tint = cached static
  material; weapons swapped). Other players online see defaults (needs a protocol change).
- **Removed:** the whole dice-era app (reachability scan; see SIEGE_PROGRESS E4). The repo-root
  web game and its servers are untouched.
- **Play branch merge (codex/siege-play-vc24):** `tools/verify_play_bundle.py` on this branch is
  the Play branch's version with its dice-era checks replaced (requires Siege app scripts,
  rejects dice-era scripts; the old content JSON no longer exists). Keep the Play branch's own
  `build-native-play.yml` (vc24); this branch still carries the older vc22 workflow file.
- **Tests:** `tools/run_siege_tests.sh` = 11 suites incl. `app_flow_test` (the app through its
  real buttons, REAL time) and `meta_economy_test`. `godot-visual-review.yml` runs it on PRs.
- **Unverified:** Settings > Privacy Policy opens
  `https://136-113-125-3.sslip.io/fatebound/privacy.html` (not reachable from the dev sandbox).

---

## 12. Round 6: home screen and menu art (Blender pipeline)

Preview **0.13.1-siege-art, version code 23** (superseded: see section 13). Pre-rendered art lives in `godot/assets/ui/`
(3.4 MB); the scripts that make it are committed so it can be re-rendered.

| Art | Made by | Notes |
|---|---|---|
| `hero_backdrop.jpg` | `tools/blender/backdrop.py` | EEVEE render of the KayKit castle at dusk; sky is a painted gradient dome (Nishita washed out under Filmic), warm-violet world light, hills tinted for aerial perspective. ~55 s. |
| `icons/*.png` (19) | `tools/blender/icons.py` | Weapon/off-hand icons from the real KayKit models. Each model is auto-oriented: longest axis up, tip at the top (the end farther from the grip/origin), broad face to camera. Pairs = weapon behind, gear in front. |
| `currency/*.png` (6) | `tools/blender/icons.py` | Procedural gold coin, three coin piles (600/1600/4500 in the gem exchange) and cut gems: the kit has none. |
| `skins/*.png` (18) | `tools/render_skin_icons.gd` | Character busts rendered by the GAME (same builder, idle pose, tint), so icon == in-game look. Needs Xvfb + `--rendering-method mobile`. |

Re-render: `apt-get install blender` (4.0.2 works), then
`xvfb-run -a blender -b --python godot/tools/blender/icons.py` (`ONLY=name,name` for a subset;
~3 s each) and `... backdrop.py` (env `RESX RESY SAMPLES`). **Run Blender in the foreground**:
a `nohup` background run hung at the first render. **Never `pkill -f` a pattern that also appears
in your own command line** (it kills the shell). After adding a skin/weapon to `economy.gd`,
re-run the matching render and commit the PNG + `.import`.

Home screen (`scripts/app/siege_app.gd`, `screens.gd`, `showcase.gd`, `ui.gd`):
- Full-bleed hero layer *behind* the menu (backdrop + live 3D character + scrims + logo + gold
  motes), parallax/fade on scroll; `Screens.home` reserves its space with a spacer (322 px).
  Camera: `Showcase.cam_z/cam_y/look_y` (home 9.7/1.6/1.24, Locker default 7.4/1.45/0.88).
- Class picker = icon chips; animated PLAY button (`UI.play_button`: glow, pulse, light sweep);
  currency pills use the rendered coin/gem; selected tab has a highlight pill; screens fade in.
- Shop/Locker/Pass use the rendered icons via `Screens.swatch/item_swatch/reward_text`
  (`reward_text` returns `[glyph, text, colour, texture path]`).
- `tools/app_shots.gd` screenshots every screen with a realistic profile (see its header).

**Rule learned in Round 6 (0.13.0 -> 0.13.1):** anything that owns a SubViewport, particles or
looping tweens and lives *outside* `chrome` (the home hero layer sits behind it) must be switched
off when a match starts. 0.13.0 hid only `chrome`, so the hero's 4x-MSAA physical-resolution 3D
viewport and motes kept rendering behind the match. `SiegeApp._set_menu_active(on)` now hides the
menu AND disables processing for `chrome` and `hero_layer`; `tests/app_flow_test.gd` asserts it.
Any new full-screen layer must be added to that helper.

---

## 13. Round 7: Fat Princess land, bigger map, bridges, outposts (preview 0.14.0, code 24)

- **Landscape** (`scripts/siege/siege_land.gd`, all point-symmetric): field 64x128; river
  `c(x)=1.5 sin(0.16x)` (odd, so it mirrors onto itself), 6 m wide, bridges at x=-20/0/20;
  four raised ledges (1.5 m) with ramps and a 1.2 m rock band (walls sit mid-band so units stand
  on the flat top or at the foot); rolling slopes; brick path routes gate -> ramps -> bridges.
- **Outposts** (sim): 4 on the ledges. Lone team in the 5 m ring captures (1 unit ~9.5 s, 4+
  ~4.8 s), contested freezes, crossing 0 neutralises, owners get +1 wood +1 stone / 15 s,
  raiders/escorts respawn at the forward outpost, escort bots capture. HUD pips + toasts.
- **Art**: `tools/blender/terrain_art.py` (grass/path/rock textures, seamless; bridge.glb).
- **Terrain**: `tools/bake_land.gd` bakes `assets/terrain/height.res` + `pathmask.res`
  (R path, G ledge rim, B cliff-foot shadow); `scripts/siege/terrain.gdshader`. **After
  editing siege_land.gd, re-run the bake**: `tests/siege_land_check.gd` fails on a stale bake.
  The visual terrain excludes bridge decks (the deck model is drawn instead); units use decks.
- **Protocol v2** (outposts in snapshots; new map). **Redeploy the server from this branch
  before online play**; v1 phones are told to update.
- Tests: `siege_land_check` (placement, symmetry, nav across bridges only, stale bake) in the
  runner. Two 16v16 matches ended 3-2 on rescues in ~7 min (before: mostly time-outs); red won
  both -> watch side balance.
- Not verified on a device: frame rate with the terrain shader at full resolution, the water
  animation, capture rings filling.

**0.14.1 (Round 7b):** greener, more colourful terrain (new Blender grass, `tools/blender/flowers.py`,
grass tufts + flowers scattered by `SiegeView._plan_foliage`), shader `grass_sat` + macro
variation, scene saturation 1.08. Colour targets were measured against Kevin's references (see
SIEGE_PROGRESS Round 7b); re-measure if you change the tint.

**0.14.2 (performance):** `tests/perf_bench.gd` measures the 3D render time per config
(`BENCH=full,no_foliage,no_terrain_shader,no_water,no_adjust,nothing_new`; run under Xvfb with
`--rendering-method mobile --resolution 540x960`; compare the SECOND pass of a config, the first
includes shader compile). Terrain/water/foliage nodes carry `meta "perf"` for it. Keep the
terrain shader's common path at 2 texture reads; see SIEGE_PROGRESS 0.14.2 for the numbers.

**0.14.3:** glow off in battle, terrain baked at 1 m (`Land.BAKE_STEP`), off-screen character
animations paused (`SiegeView.anim_cull`), fewer flowers/tufts. **Kevin does not want automatic
resolution; don't add it.** `tests/perf_bench.gd` now restores each build's own settings, can
freeze the scene, and prints draw calls/triangles; compare builds by alternating runs.

**0.14.4 (painted grass):** flat Voronoi cell texture (`terrain_art.py grass()`, palette fitted to
the references' measured green) + sweeping bands baked into the mask alpha (`Land.grass_band`,
`BAND_W`, `BAND_CENTRES`; shader `band_strength`). Re-run `tools/bake_land.gd` after changing them.

---

## 14. Round 8: Fat Princess hats replace the dice forge (preview 0.15.0, code 29)

- Stands: `Sim.HAT_STANDS` (castle-local, west courtyard), stock `HAT_STOCK_MAX` 3, refill
  `HAT_REGEN` 6 s; villagers auto-take on walking in (`_step_hats`); `act("hat_swap")` / ACTION
  swaps for classed units. Dropped hats `sim.hats` ({id, cls, up, pos, t}), `HAT_LIFETIME` 30 s,
  picked up by any villager within `HAT_PICK_R`. `_kill` drops the hat and resets to villager.
- Outpost racks were removed in 0.15.1 (Fat Princess outposts have no hat dispensers).
- Upgrades `hat_<class>` (workshop grid) replace "Fourth Die". `Sim.forge()` now returns the hat
  stands' corner (kept for hints/tests).
- View: pedestal + class weapon + stacked hats per stand, dropped hats bob/spin (transforms only),
  rack hats beside outpost towers. HUD: dice panel gone, "NEW HAT" action, class toasts.
- Protocol v3: redeploy the server from this branch before online play.

**0.15.1 (Fat Princess hat rules, from Kevin's wiki screenshot):** no outpost hat racks; any team
can use a stand it reaches (enemy courtyard included; the stand owner's upgrade decides the tier);
Workers drop off at held outposts; humans respawn forward only when a dropped hat is near it, bot
attackers always respawn forward and scavenge (32 m). Gate HP 1100, repair 20/tick. See
SIEGE_PROGRESS 0.15.1 for the balance trail.

---

## 15. Round 9: Priest healer (preview 0.16.0, code 31, protocol v4)

`CLASSES.priest` + `_beam` / `_step_beam` / `_think_priest` / Sanctuary in `_resolve_attack`;
ATTACK for a priest = beam (held ATTACK already repeats the action, offline and on the server).
`BEAM_HOLD`, `BEAM_MOVE`, `SANCTUARY_*`, heal 18/s. View `_sync_beams`. Protocol v4 (slot 26 =
beam target index + 1; "priest" in the class list). **Redeploy the server.** Next: the castle
rebuild (Kevin: "much larger and more 3D", Fat Princess castle screenshots).

---

## 16. Round 10: big terraced castle (preview 0.17.0, code 32, protocol v5)

- Layout: `scripts/siege/siege_castle.gd` (40 x 26 m; courtyard, L1 1.8 m terrace with the dungeon,
  L2 3.6 m terrace with the throne, grand stairs). The sim builds walls/ledges/heights from it; the
  view's castle is generated by `scripts/siege/castle_mesh.gd` with `assets/castle` textures
  (`tools/blender/castle_art.py`). Change the layout in ONE place (siege_castle.gd), then run
  siege_reach + siege_land_check (placements, paths) and re-bake the land if paths moved.
- Gate nav fix: own-gate doorways clear a rectangle of nav cells (`_cells_across_segment`), not a
  capsule (the capsule's ends opened cells inside the wall: units stuck; blue won 4/4 seeds).
- Pace changed: castles 76 m apart; bot matches end ~260 s on rescues. Tune if Kevin wants longer.
- Protocol v5: redeploy the server.

**0.17.1 (KayKit castle):** the castle's walls, terrace edges, towers and buildings are KayKit
models (`SiegeView._build_castle_kit`, `_kit_run`), merged per castle into one mesh
(`_merge_kit`). Buildings: `Castle.BUILDINGS` (solid), props: `Castle.PROPS`. Only floors/steps are
generated (`castle_mesh.gd`). Kevin rejected the generated sandstone look: keep the KayKit style.

---

## 17. Round 11 (preview 0.18.0, code 34, protocol v6)

- Knight BLOCK: hold ABILITY (HUD `ability_held()`, K); `Sim.ability_of/blocking/shield_seg/
  shield_blocks`; hits whose path crosses the shield segment are stopped (the knight from the front,
  allies behind), projectiles crossing it are destroyed; 40 % speed. Online: input flag "b",
  server applies held block per tick.
- Berserker WHIRLWIND: `ability_of` = "whirlwind" for upgraded barbarians; 3 s, 2.4 m every 0.3 s,
  gates too, moving freely, 9 s cooldown; greatsword bits/sword_E.
- Snapshot unit slots 29 (blocking) and 30 (whirl remaining); F = 31.
- Hat machines: `Castle.HAT_STANDS` (spread), `SiegeView.MACHINES` (base/up pieces).
- Weapons Bits: "bits/<model>" in LOOKS and catalog weapons; `Eco.PACKS`, `Profile.buy_pack`,
  shop PACKS section; pass 6 + 10 items.
- siege_land_check: squeeze-trap rule. Keep new castle pieces >= 1 m apart or touching.

**0.18.4 (network):** client-side prediction for the local unit (Sim.predict_step, Net.apply(...,
predict=true), server `net_driven` + Sim.accept_client_pos validation, 0.3 s fallback), local
dodge/swing animation prediction, snapshots 15 Hz. Protocol v7: redeploy the server.

---

## 18. Tutorial (preview 0.19.0, code 39)

`scripts/siege/tutorial.gd` (STEPS = the Herald's script and tasks), `SiegeMode.tutorial`,
`SiegeApp.start_tutorial()`, Home card + HOW TO PLAY. Voiceover files go in `assets/vo/tutorial/`
as `<id>.ogg` (list: `assets/vo/tutorial/SCRIPT.md`; regenerate it after editing STEPS). Test:
`tests/tutorial_test.gd`. When a new mechanic ships, add a step (talk + task + task_done check).

**0.21.0 (dungeon wing):** Castle.ANNEX_*/DSTAIR/JAIL_*/CELL_C, Castle.in_annex/dungeon_ledges,
Land.in_dungeon_pit (re-run tools/bake_land.gd after changing the wing), jail = gate kind "jail"
(Sim._reset_jail). Protocol v8: redeploy the server.
