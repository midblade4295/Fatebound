# Fatebound Native 0.3 — full v114 game-system conversion

This parallel Godot client implements the persistent shell and original offline
modes as well as the existing authoritative multiplayer battle. It is not a
WebView and does not execute the original HTML to play the game.

The source basis is the complete approved v114 HTML:
`84697859827127e8c9285b0cf57578a8fc2bcedcb3cf8d3247772f0309f3b4e9`.
`data/v114-content.json` contains the extracted original characters, weapons,
quality tiers, relics, quest/reward tables, seasonal tracks, raid tables and all
33 training lessons. No new monetization, currencies or permanent combat bonus
was invented for the port.

## Available systems

- Home, day/streak/Fate regeneration, wallet, levels and pending level rewards.
- All five heroes and nine weapons, per-match weapon quests, equipment, four
  quality tiers, forging, shard types, relics and pinned upgrade goals.
- Season Pass: ten tiers, free/premium tracks, original 180-token premium cost,
  original rewards, same-season claim tracking and old-season receipt safety.
- Three daily quests, lifetime/best-match records, solo ranking, simulated ladder
  and cosmetic online mastery paths/ranks.
- Persistent roll chests, held KO chests, original ×3 solo-end opening, stored
  attacks, three-choice dice gifts, one daily free gift and timed return gifts.
- Solo Company: the original 40-fighter progression-enabled five-minute battle,
  your equipment/relics, Focus/multipliers/ALL-IN, critical timing, hot streaks,
  spells, ultimates, rallies, momentum, timed orders, supply objective, bounties,
  rival pursuit, KO/respawn, tower scoring, overtime, end rewards and local rank.
- Daily Raid: three 90-second attempts, simulated company support, daily bosses,
  armor/weak-face/stagger rules, parry wind-ups, class ultimates, personal reward
  tiers, shared damage milestones, qualifying kill rewards and daily Slayer.
- Hero Academy: all 33 original learn-by-playing lessons, using an isolated
  temporary save. Exit/resume and completion only change tutorial flags in the
  permanent profile. The purchase lesson uses practice resources.
- Standard practice, rotating Focus/Fixed Loadout/Guardian trials, and a saved
  last-tower 60-second practice challenge. Practice has no permanent rewards.
- Online 20-second matchmaking, 20 combatants, 10-versus-10, server-confirmed
  dice/actions/HP/respawn, unchanged gzip/delta synchronization, safe retries,
  match rewards and private account receipt recovery.
- Real online guild creation/join/leave, leader route selection, real members,
  weekly expeditions and once-only contribution rewards. The solo Company
  roster and War Room remain explicitly simulated/device-local, as in v114.
- Native audio, saved volume/mute preferences, reduced motion, private JSON
  import/export/clipboard backup and manual legacy-code cloud backup/restore.

## Deliberate native presentation changes

Menus use native Controls, scroll containers, fixed navigation and safe-area
handling. They are not pixel-for-pixel CSS replicas. The critical sequence has
three native timing windows and retains the source +35% per success / ×2.05
maximum; the timing animation itself was not copied from browser Canvas code.
The original random-sort target ordering in solo garrison attacks is represented
by a seeded Fisher–Yates shuffle; target allocation is randomized but is not
bit-for-bit identical to JavaScript's implementation-dependent random sort.

The game uses the original pre-rendered 2D artwork and animation frames, with
native effects. It is not a fully skinned 3D remodelling. Battle/home sprites have
1,170 verified animation frames; armory portraits are lossless crops from the
original 9×5 portrait atlas. Native sound uses the existing original PCM designs.

## Preserved disabled features

v114 paused Home purchases that did not deliver a usable benefit. Fate/cap sales
and temporary combat-consumable sales remain disabled outside the practice
purchase lesson. Fate is preserved, not erased or silently converted into Focus.
No Google payment service or Google-bound login was added; existing online
identities remain guest-device accounts.

## Saves and migration

Install the APK as an update over `Fatebound Godot Preview`; do not uninstall.
The preview uses the same package and debug certificate as 0.1/0.2 and retains
its online guest identity. Production Fatebound is a different Android package.

Settings & Saves accepts the original JSON or your own `FB-XXXX-XXXX` legacy
cloud code. Import first shows a summary and requires confirmation. It writes a
timestamped backup before replacing the native progression file. Compatible,
active session106/model2/matchVersion3 solo battles have a native conversion;
finished/incompatible historical snapshots are retained without new rewards.
The imported browser progression is not its separate online bearer identity.
A browser account's membership/reward history therefore does not automatically
move merely by importing the progression JSON.

Native writes are verified and replaced atomically with a previous backup.
Unfinished local sessions and pending claims survive restarts. Claimed server
receipts are applied only once per ID; a durable claim intent survives losing a
network response. An authenticated read-only `/receipts` route supports recovery
of rewards previously claimed by the same native preview guest. It does not let
one player read another player's receipts.

## Build and validation

Engine: the existing Godot 4.7.2 migration toolchain with matching templates.
Android preview package `com.fatebound.godotpreview`, code3, name0.3.0-full-game,
minimum24/target36. Use the existing dedicated debug key; never replace it or use
the production upload key for this preview. `project.godot` keeps the prior
application storage identity deliberately.

`tests/` and `tools/` are test/build-only and excluded from Android exports.
No forced faces, clock controls or harness ports may be deployed publicly.
Reports in `reports/full-port` distinguish original-rule comparisons, simulated
fixtures, real public matches, renderer checks and APK evidence. They are not a
claim of physical Android, speaker, thermal or production-scale load testing.

Do not replace the production v114 HTML or publish this separate preview to
Google Play without a separately approved native-client cutover.
