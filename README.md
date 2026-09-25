# Fatebound v109 — Adventure / matchmaking preview

This feature branch continues the exact approved v108 main. It contains the complete game, raid/modal fixes, two-spell loadouts, pinned goals, cosmetic mastery, supply objective, detailed results, offline daily challenges/practice, and a separate authoritative 20-player arena with asynchronous guild expeditions.

**Live activation is pending.** The authorized host's Remote Desktop Commander connection was offline. No SSH deployment, public matchmaking activation, Play publication, or Legionary change was performed. `main` remains the approved v108 baseline until the preview is reviewed and deployed.

- Start with `multiplayer/docs/FEATURES.md` for the exact implemented scope and limitations.
- Read `multiplayer/docs/TEST_REPORT.md` for actual tests and environments.
- Use `multiplayer/docs/DEPLOYMENT.md` for the isolated loopback-8081 service and Caddy route.
- `fatebound.html` is the full game, not a stripped test page; verify `fatebound-source.sha256`.
- `multiplayer/src` mirrors the named embedded engine/client/CSS; use `multiplayer/tools/sync-inline.py --root .` to check consistency. Do not rebuild from an old v108 transport payload to make future changes.

## Matchmaking contract

A lobby waits the full **20 seconds** from its first arrival, including when full. It creates **20 total combatants: 10 vs 10**. Empty slots become explicitly labelled bots only at the deadline. A 21st human goes to another lobby. A disconnected human keeps the same slot with a labelled bot substitute and can reconnect. Cancellation is allowed in the queue, not in the live match.

Online uses equalized level-10 common-power combat and persistent anonymous guest identity. It is not yet Google-account binding, cross-device account recovery, ranked MMR or party matchmaking. Solo progression and existing saves remain intact. No new save reset is introduced.

## Reproduce the checks

```sh
node --test multiplayer/tests/server.test.js
python3 multiplayer/tools/sync-inline.py --root .
sha256sum -c fatebound-source.sha256
```

The optional browser regression fixture needs Python Playwright, requests and Chromium at `/usr/bin/chromium`. Run `multiplayer/tests/harness-server.js` only on a development machine, then `python3 multiplayer/tests/browser_tests.py`. Ports 8851/8852 are **local test fixtures**, including clock/resource controls; they are not production endpoints. The production unit runs `arena-server.js` on loopback 8081 only. See the test report for simulated save/network/time conditions.

HTML v109 is not Android versionCode 109. Keep the existing upload key and check consumed Play codes before any requested release. Do not alter Legionary, its service, or port 3000.
