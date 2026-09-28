# Fatebound Siege (Godot 4.7.2, Android, Vulkan)

A Fat Princess-style 16 vs 16 castle siege: roll your class at the forge, break the enemy gates,
carry your Oracle home. Offline against bots, or online on the Siege server.

- `scripts/app/` — the app shell and screens (Home, Siege Pass, Shop, Locker, Settings), UI
  toolkit, procedural icons and the 3D hero showcase. Entry: `scenes/Main.tscn`.
- `scripts/meta/` — economy (gold, gems, levels, Siege Pass, challenges, shop, cosmetics) and the
  player profile (`user://siege_profile.json`, one-time migration from the old dice-era save).
- `scripts/siege/` — the game: simulation, 3D view, HUD, online protocol, diagnostics.
- `server/` — the headless authoritative online server, probe and deployment kit.
- `tests/`, `tools/run_siege_tests.sh`, `tools/build_siege_preview.sh`.

Read `SIEGE_HANDOFF.md` and `SIEGE_PROGRESS.md` before changing anything.
The dice-era app (v114 port) was removed in Round 5; it remains in git history.
