# Current continuation: v113 state/dice/network fix

Use branch `chatgpt/v113-sync-dice-compression`, based on v112 head
`b322d3b9bb30719a2b7de1e058773ce0473f8bb5`, not old main HTML.
Build `113-state-dice-network-fix`; 36,304,138 bytes; SHA-256
`56ad2d138c503d6a9b20bece12276252dd95bcf15e129a7030316383aa159a7f`.
Read `multiplayer/docs/SYNC_NETWORK_V113.md` and `multiplayer/sync-audit/`.
Deploy the matching arena-server.js WITH arena-wire.js and http-compression.js.
Python web-host changes provide gzip and private ETag revalidation. Do not expose
working directories. New optional transport2 is NOT gameplay protocol2:
protocol/store1, balance110, session106, 20-second/20-total-slot matchmaking and
existing v112 audio remain. All103 large embedded assets are unchanged.
Preserve authoritative HP/respawn, monotonic snapshots, roll-index receipt checks,
single-owner HUD labels, all-three-dice winning feedback, bounded wire histories,
Brotli/gzip negotiation and full-snapshot fallback. Never deploy harness controls.
No save reset, Legionary/Caddy route, main merge, Android or signing changes.
Deployment evidence will be recorded separately after live verification.

---
## Earlier instructions retained as historical context

# Fatebound v111 — UI and sound continuation

Current task branch: `chatgpt/v111-ui-audio`, based on v110 head
`8a04f85e0739a4606266c6ec32f99c8bce8b042e`. HTML build
`111-ui-sound-workshop`, 36,286,487 bytes, SHA-256
`8cb7cc7f5c04898183bc298c4f23fb96ce203cf2794df043534cdc36912dad84`.
Read `multiplayer/docs/UI_AUDIO_V111.md`, the manifest and
`multiplayer/ui-audio/TEST_SUMMARY.json`. Live installation is recorded separately.
Do not restore older whole-file source over this update; main remains separately
managed. Preserve the stable Guild nodes/draft/scroll, reserved battle tool and
announcement rows, persistent chest inbox, and original single-context audio
mixer. Keep the six readable mirrors synchronized, 103 embedded art assets,
`fatebound-save`, session106, protocol/store1, balance110, two equipped spells,
and 20-second/20-slot matchmaking. Held KO loot retains its existing x3 automatic
end-of-solo-match rule; no reward formulas or backend code were changed here.

Use new task branches; no force-push, token exposure, sudo bypass, save reset,
Legionary/Caddy change or Play publication without authorization. The test harness
and audio WAV exports are not production server endpoints. The sound code is
embedded; do not add unnecessary sample network dependencies. After future edits,
update hashes and rerun actual menu/chest/audio/battle interactions, not parsing
alone. Numerical/headless browser checks are not physical-phone listening tests.

---

## Historical v110 instructions and provenance

# Fatebound audit branch instructions

This is `chatgpt/v110-audit-balance`, based on deployed v109 commit
`8705e7e2e150dfbcebe94e81df51b71f7f14af6e`. Read `GROKBOT_HANDOFF.md`, the source
manifest, `multiplayer/docs/AUDIT_V110.md` and `DEPLOYMENT_V110.md` first.
Main remains separately managed; a branch number does not imply a merged release.

Preserve local work, fetch first and use a fresh task branch. Never force-push,
hard-reset user changes, rebuild from old HTML, or rerun historical import jobs.
`fatebound.html` is the full source; mirrors in `multiplayer/src` must remain
synchronized with `multiplayer/tools/sync-inline.py`. Update the source checksum
and manifest after authorized changes and rerun full-HTML runtime tests.

Preserve the v107 idempotent observer/input fix, exclusive menu roots, v108 pass
layer, v109 modal audit, live battle navigation lock, 20-second/20-total-slot
matchmaking, two equipped spells and all embedded artwork. Save key stays
`fatebound-save`, battle-session compatibility 106, arena protocol/store schema 1.
Do not add global input gates, browser-history locks or save-reset migrations.

New rooms use balance 110; old persisted rooms deliberately retain legacy 109
rules. Preserve human-only reward credit, bounded gifts, paid contested capture
bonuses, immutable receipts and pending reward recovery. The test harness and
v109 comparison fixture are test-only; never deploy their controls or ports.

Run both Node test files, Python web-host tests, original full-game browser suite,
added browser audit, module/art checks and seeded balance simulations. Distinguish
simulations from telemetry and mobile emulation from actual phone tests.

Only approved public files may be served. Do not expose save directories, logs,
source/configuration, signed keys or account tokens. Do not modify Legionary or
its port3000 service. No sudo bypasses or permission changes. HTML v110 is not
Android versionCode110; verify consumed Play codes before a separately requested
build, and never replace the upload key or publish without authorization.

## v112 mobile audio unlock patch
The v111 sound synthesis/content remains, but mobile unlock handling is corrected on branch chatgpt/v112-audio-unlock-fix. Preserve the bounded pending-cue queue, delayed AudioContext.resume handling, plain-constructor fallback, silent gesture prime, and Sound Studio status feedback. Do not revert to v111 audio startup logic, which can discard the first cue while Android Chrome is still resuming Web Audio. Balance110/backend/save schemas are unchanged.
