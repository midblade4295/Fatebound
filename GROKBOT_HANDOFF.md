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

# Grokbot handoff — Fatebound v110 audit

Continue from `chatgpt/v110-audit-balance` and verify `fatebound-source.sha256`.
This branch follows the deployed v109 build, not v108 or an older Android branch.
Read `multiplayer/docs/AUDIT_V110.md`, its exact-source evidence in
`multiplayer/audit/`, and `multiplayer/docs/DEPLOYMENT_V110.md` for live status.
Do not treat the historical v109 "deployment pending" report as current status.

Preserve the working UI, original art and save compatibility. The audit closes
spell/gift/Rampage exploits, prevents bot substitutes earning human rewards,
restores interrupted Focus correctly, adds durable old-room/guild receipt
recovery, credits verified dailies once, fixes raid/training callbacks and stored
raid attacks, and guards purchases and malformed metadata. Internal web files
must remain inaccessible. No player-save reset is part of the change.

Fate and temporary lobby-consumable sales are paused because they had no usable
benefit in the current flow. Existing balances, cap relic ownership, pass rewards
and real progression are retained. Do not re-enable them without implementing
and testing a meaningful use/carry-forward design. Online combat remains
normalized; do not introduce purchasable combat advantages.

New matches use balance110 while existing arena snapshots keep their previous
rules. Deploy the engine/server pair together, preserve the private JSON store,
verify queue/bot fill/reconnect/reward/second-match behavior, and never deploy the
debug harness. No global click traps, recursive observers or historical restore
workflows. Do not modify Legionary, keys, Android packaging or Play releases.

The code uses guest-device identity; no claim of Google binding or cross-device
recovery. Seeded policy simulations guide this tuning but do not establish human
win rates or perfect balance. Device tests, real-player telemetry and production
security/load work remain distinct follow-up verification.

Live v110 deployment and six real-clock public TLS checks passed on 2026-09-25 UTC.
See `multiplayer/docs/DEPLOYMENT_V110.md` and `multiplayer/audit/public-smoke.json`.
Review PR #12 is stacked on v109 PR #11; main is unchanged.

The v111 HTML is live as of 2026-09-25 15:07 UTC, verified from code commit
`f950a49606662733e7091663f4946b7615c8009f`. Read
`multiplayer/ui-audio/live-deployment.json`. Arena balance110 and its process
were unchanged; do not overwrite the deployed client with v110.

## v112 mobile audio unlock patch
The v111 sound synthesis/content remains, but mobile unlock handling is corrected on branch chatgpt/v112-audio-unlock-fix. Preserve the bounded pending-cue queue, delayed AudioContext.resume handling, plain-constructor fallback, silent gesture prime, and Sound Studio status feedback. Do not revert to v111 audio startup logic, which can discard the first cue while Android Chrome is still resuming Web Audio. Balance110/backend/save schemas are unchanged.

Live client is now v112 audio-unlock-fix, deployed 2026-09-25T15:29:43Z. Preserve its delayed-resume queue/fallback logic; do not restore v111 audio startup. Balance110/backend remain unchanged.
