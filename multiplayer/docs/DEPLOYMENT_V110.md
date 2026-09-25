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
