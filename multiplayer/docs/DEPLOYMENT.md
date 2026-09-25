# Fatebound arena deployment — PENDING

The remote machine connection was offline during development. No SSH login, live service install, reverse-proxy edit, public matchmaking activation or Play publication was performed. The supplied endpoint is configured for the user's existing Fatebound host, but needs this new service and proxy route.

## Isolation and prerequisites

Use the authorized existing host only. The known Fatebound checkout was `/home/midblade4295/Fatebound` and its existing save/web service used loopback port 8080. Inspect the live configuration before relying on either detail. **Do not change `/opt/legionary`, `legionary.service`, port 3000, upload keys, or the existing cloud-save database.**

The new service is independently named `fatebound-arena.service`, uses **127.0.0.1:8081**, and stores its own data in `/var/lib/fatebound-arena/arena.json`. It does not replace the legacy Fatebound web/save server. Node 20+ is required; tests used Node 22. Verify the node executable location before using the supplied unit.

First reconnect the host through Remote Desktop Commander (or use the user's authorized SSH connection). Back up the current Fatebound HTML, Caddy configuration and existing save data. Confirm that port 8081 and `/srv/fatebound-arena` are not already in use. Do not overwrite an unrelated service or directory.

## Install the isolated service

After reviewing the feature branch and tests, from the repository root:

```sh
node --test multiplayer/tests/server.test.js
python3 multiplayer/tools/sync-inline.py --root .
sha256sum -c fatebound-source.sha256
command -v node
# Inspect an existing destination before installing; use a separate release directory if needed.
sudo install -d -m 0755 /srv/fatebound-arena
sudo install -m 0644 multiplayer/src/arena-engine.js multiplayer/src/arena-server.js multiplayer/src/metrics.js /srv/fatebound-arena/
sudo install -m 0644 multiplayer/deploy/fatebound-arena.service /etc/systemd/system/fatebound-arena.service
# Create this config only if it does not already exist; review/merge an existing config instead.
sudo install -m 0600 multiplayer/deploy/fatebound-arena.env.example /etc/fatebound-arena.env
sudo systemctl daemon-reload
sudo systemctl enable --now fatebound-arena.service
curl --fail http://127.0.0.1:8081/health
```

Expected health: `ok:true`, `protocol:1`, `queueMs:20000`, `capacity:20`. Do not bind this plain HTTP service to all interfaces. TLS terminates at the existing proxy. Never put SSH keys or server credentials inside HTML.

## Proxy and client release

`multiplayer/deploy/caddy-route.fragment` is a **fragment, not a full Caddyfile**. Insert its `/fatebound/arena/*` route inside the correct existing HTTPS site, taking precedence over the general `/fatebound/*` route. Keep the existing 8080 and 3000 routes intact. Validate the complete modified Caddyfile before reloading the proxy. This configuration was not validated against the inaccessible live host.

The client default API is `https://136-113-125-3.sslip.io/fatebound/arena` for local HTML/WebView files, or the same origin's `/fatebound/arena` for HTTPS. `window.FATEBOUND_ARENA_URL` can explicitly configure another authorized endpoint before the client script. Do not disable TLS verification. `ALLOW_LOCAL_CLIENTS=1` admits the null origin used by the local-file alpha. Prefer an allowlisted HTTPS app origin and turn it off for a later production release.

Verify the public `/fatebound/arena/health` route, then test **two separate physical clients**: join the same lobby, wait 20 seconds, verify 20 total participants and bot labels, roll/cast/rotate, disconnect/reconnect, complete, claim, and start a second battle. Only then serve the new `fatebound.html` from the existing web server and build/publish an Android update when requested. HTML v109 is not Android versionCode 109. Check consumed Play codes before building a new release.

## Identity, persistence and operating limits

This is an anonymous, persistent **guest-device alpha**, not Google-account authentication or cross-device account recovery. Tokens are generated using 32 random bytes and only their hashes are stored server-side. Losing the device identity prevents access to that guest's arena account; existing offline progression is separate and is not reset. The old local/cloud save is not trusted as online combat strength. Online combat is equalized; valid completion receipts are mirrored into the existing local game exactly once. A device-local pending-claim journal retries a lost claim response after reload; it is cleared only after local persistence succeeds.

Run only one instance against this JSON store. It has atomic file replacement, action-ID deduplication, persistent results and claim receipts, input/resource validation, request limits and origin checks, but is not a distributed datastore or a completed public-service security/load audit. Use filesystem backups and monitor disk capacity, logs and resource use. Queued lobbies are transient across a restart; active rooms and rewards persist. A disconnected participant receives a labelled substitute in the same slot and can reconnect; substitute rolls do not earn the absent player participation credit.

The administrator-only `metrics.js` reads the local arena store and outputs aggregates. Do not publish the store, tokens or individual account data. Retention output is guest-device/completed-battle data, not a claim of improved engagement.

Rollback: stop only `fatebound-arena.service`, remove only its added proxy route, and restore the separately backed-up Fatebound HTML after review. Retain the arena data for later recovery. Do not delete player saves or restore an old Legionary deployment.
