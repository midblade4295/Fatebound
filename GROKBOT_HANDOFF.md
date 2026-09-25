# Grokbot handoff — v109 Adventure / matchmaking preview

## Current status

Kevin requested the complete gameplay package plus real 20-player matchmaking after a full 20-second search, and the raid/modal audit. The code and isolated server are in **`chatgpt/v109-adventure-matchmaking`**. It is based on the exact approved v108 main (`a0f5eb059f4ca4b2c3bede2880783c64cbaad230`). **It is not live and has not replaced main.** The Remote Desktop Commander connection to the existing host was offline, so no SSH deployment was performed.

Use `fatebound-source.json` and `sha256sum -c fatebound-source.sha256` to verify this preview. Do not use a different old branch's HTML merely because its Android versionCode is higher. Preserve all player and Season Pass progress; no new save reset is part of this update.

## Implemented here

Two equipped spell buttons with a shared pool; cosmetic hero mastery; pinned weapon goal; choice of existing shard rewards; one announced supply objective; contribution-based results/advice; last-tower practice; equalized rotating offline challenges; and real invite-code guild expeditions driven asynchronously by verified match contributions. The expedition's Citadel is a shared progress objective, not a newly modeled raid arena. The old solo guild roster is explicitly labelled simulated.

The separate Node server owns actions, dice, damage, timers, Focus, bots, results and receipts. It waits the full 20 seconds from first join (even if full), then starts 20 total combatants, 10 per side, with labelled bots in the remaining slots. Cancellation, in-place disconnect substitution/reconnect, action deduplication, persistent identities/results, reward caps, immutable material choice and a lost-claim recovery journal are implemented. Online is equalized level-10 common-power guest-device alpha, not Google-account/ranked/party play. Existing offline progression remains intact.

## Before live activation

Reconnect the authorized existing host. Inspect its current configuration; the prior Fatebound checkout was `/home/midblade4295/Fatebound`, with a save/web service on 127.0.0.1:8080. Follow `multiplayer/docs/DEPLOYMENT.md` to install **only** the separate 8081 arena service and the `/fatebound/arena/*` route, after backups and configuration validation. Do not touch Legionary's files/service/port3000 or signing keys. The provided Caddy file is only a fragment.

Verify the private and public health endpoints. Test two separate physical clients through queue/bot-fill/roll/spell/map/disconnect/reconnect/result/claim/second battle before calling multiplayer activated. No production load/security audit, Google binding or account recovery is claimed. Do not deploy `multiplayer/tests/harness-server.js`; it contains test-only controls.

## Continue safely

Fetch, inspect and preserve any existing working tree, then create your own task branch from this verified feature tip. Read `AGENTS.md`, the features, deployment and test reports. Keep the stable v108 observer fix and pass changes. Never rerun historical import payloads against newer source. Keep the inline modules synchronized and update the source manifest/checksum after tests. Report commit, source hash, test evidence and deployment state separately.

HTML v109 is not Android versionCode 109. Before any later requested Play build, verify consumed versionCodes and packaging metadata; do not reuse old codes or swap back to older HTML.
