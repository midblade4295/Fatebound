# v110 deployment record

The v110 gameplay build is locally verified and staged for an isolated rollout.
The final live record will be appended after the deployed source/module hashes
and public endpoint checks succeed; local testing alone is not deployment.

## Web protection already applied

At 2026-09-25T05:32:27Z, the allowlisted Python web host was installed on the
existing authorized Fatebound host. Public save-directory, server-source and log
paths changed from HTTP200 to HTTP404. The web health route reported build110.
All 16 save-file hashes matched before/after the replacement. No save contents
were read through those public paths. The arena and Legionary remained active.
A private backup of the previous web host was made before replacement.

## Gameplay rollout plan

Use the clean v110 branch based on v109. Verify the HTML checksum, inline mirrors,
39 backend tests, 9 web-host tests, and source/art integrity on the VM. Back up
the current HTML, engine/server, and private arena store. Install only the owned
Fatebound files, retain the store, and restart only its own Node process after
checking current active rooms. Keep the existing user startup/watchdog paths.
Do not change Caddy/Legionary routes, root-owned configuration or permissions.

The private arena service remains 127.0.0.1:8081; the web host remains loopback8080.
The existing public paths remain `/fatebound/` and `/fatebound/arena/*`.
Protocol/store schema1 and solo session106 stay compatible. New rooms use
balance110; old room snapshots keep balance109. Never copy or run the test
harness, its debug endpoints, or the archived comparison engine in production.

Verify the public health, exact served game bytes (allowing only the existing
web-host save-client injection), two authenticated programmatic clients through
a real 20-second queue and full battle/reconnect/reward/new-queue flow, private
path404s, and unchanged Legionary health. This is not two physical phone tests.
No Google Play release or Android bundle publication is part of this deployment.


## Verified live rollout — 2026-09-25 UTC

Code commit: `5ff199afc810d6c63d7f69cc012ec7a465a53ade`.
The paired engine/server and full HTML were installed at 06:13:52Z after checking
there were no unfinished rooms. New health reports balance110, queueMs20000 and
capacity20. The exact served HTML matches the audited source plus only the
existing save-client injection. No Caddy, Legionary, Android or signing changes.

All 16 legacy save hashes, arena accounts and guilds were preserved. The private
backup location and exact install/source checks are recorded in
`../audit/live-installation.json`; no user saves or tokens are committed.
The VM independently passed all 39 Node and 9 Python web tests and parsed all
20 scripts while verifying all 103 unchanged embedded assets.

### Real-clock public TLS test — PASS

Two explicitly labelled programmatic verification clients entered the same room
after observing the full 20-second deadline (20.62 seconds at the polling client).
The room contained 2 humans and 18 labelled bots, 10 combatants per side.
Both clients rolled, a spell and tower move worked, one client lost heartbeats
long enough to receive a substitute and then recovered the same slot. The actual
battle completed after 300.74 seconds; the clients recorded 98 and 106 own paid
rolls, agreed on the score, and qualified for rewards. Duplicate claims returned
the same receipt/material choice without increasing earned balances. Both then
joined a new shared queue and cancelled it cleanly.

All six checks passed, finished 06:19:34Z; see `../audit/public-smoke.json`.
No clock/resource overrides or test-control endpoints were used. These clients
ran from the authorized VM through its public HTTPS address; they are not two
physical phones or a multi-region load test. The two verification guest records
are explicitly labelled and are not evidence of organic retention.

`../audit/public-routing.json` verifies private paths return 404, the complete
web HTML is correct, and Legionary/Caddy remain healthy. Historical v109 pending
status and the plan above are retained as provenance, not current live status.
The existing user-level startup/watchdog arrangement remains; physical-device
verification and larger production authentication/load work are still separate.
Main remains separately managed; the audit is on `chatgpt/v110-audit-balance`
and review PR #12. No Google Play release was performed.
