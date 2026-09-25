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
