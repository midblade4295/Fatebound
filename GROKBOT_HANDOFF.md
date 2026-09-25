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
