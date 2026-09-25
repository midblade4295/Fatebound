# Fatebound v113 — state synchronization, dice feedback and network payloads

Base: the exact deployed v112 HTML from branch `chatgpt/v112-audio-unlock-fix`, commit `b322d3b9bb30719a2b7de1e058773ce0473f8bb5`. Its SHA-256 was `ad01a9aeee842484a330ed6a4eb613b28069ef8ef1b9a670faf09702b6a50985`.
New branch: `chatgpt/v113-sync-dice-compression`.
Build: `113-state-dice-network-fix`. See `fatebound-source.json` for the exact current hash.

## What the baseline actually reproduced

The original `down()` predicate considered only a locally mapped respawn deadline. With authoritative HP still zero, an expired local deadline returned `false`, allowing the drawing code to select an alive pose even though the server correctly rejected dice rolls. A fallback sprite path could also draw the idle image while the death animation's high-resolution atlas was decoding.

The core HUD, V2 progress renderer and arena extras each wrote the same roll-chest label. A full-HTML baseline test captured 18 alternating label changes in about 1.6 seconds between a solo "energy to chest" message and the online/practice participant count. The stored-attack count had two similar competing writers.

The three-dice result resolvers did **not** ignore the first two dice. All 216 combinations were checked: the solo and server resolvers agreed. The presentation was misleading: the right die settled last, matching dice were not highlighted, and the online action path played an attack lunge even for shields/gold/gifts. The fix does not change dice odds, reroll rules or payouts.

## State and input corrections

Online life state now comes from authoritative HP. A zero-HP hero remains down until a received snapshot confirms positive HP; passing a local timer is never a resurrection. Dead attack tweens are cleared, a missing death atlas has a visibly down fallback, and nameplates display KO status.

ROLL explains why it cannot be used: knocked out with a countdown, waiting for confirmed respawn, reconnecting, checking a pending action, dice settling/server cooldown, or insufficient Focus. If received state becomes more than four seconds old, controls wait for confirmation instead of implying that local state is authoritative. Polling pauses in the background and resumes on return. Authenticated rejected actions can return a current snapshot immediately.

Snapshots retain a monotonic revision guard. The client decoder keeps bounded recent baselines, handles action/poll responses arriving out of order, and requests a full resync when a baseline is unavailable. This resync does not create a new paid action. Existing same-action-ID retries and durable reward claims remain intact. Roll receipts now include their original roll index and application time, so retrying an older accepted roll cannot replace newer confirmed dice or replay an old lunge after a substitute has acted. The latest snapshot still wins.

## UI and dice corrections

A single idempotent function now owns the roll-progress label and another owns the stored-attack badge. The other renderers delegate instead of alternating text. Offline chests remain saved and accessible through the persistent Chests inbox; online matches still award their separate completion receipts.

All three dice retain their physical throws and land on their confirmed symbols. The pair/triple's contributing dice are highlighted together, with clear labels and a confirmed-result message. Left+middle, left+right and middle+right pairs are each tested. Shield/gold/gift results do not animate a sword lunge. Reconnecting restores confirmed dice without replaying old action notifications. An invalid boolean-array argument in an existing training dice illustration was also replaced with actual symbol faces.

## Compression and caching

The old API already gzip-compressed large JSON responses, but it resent the entire detailed 20-hero state and the last 80 events on each poll. This release adds optional **transport version 2**, distinct from gameplay protocol 1 and balance version 110.

A new client requests a full projected snapshot initially, then only changed fields/slots and recent unacknowledged events. Private scoring ledgers and bot schedules are not sent. Encoder and decoder histories are bounded; a restart, lost baseline or cache eviction causes a full snapshot, never a guessed delta. Old clients still receive the full compatible representation.

JSON responses negotiate Brotli or gzip, honoring encoding quality/disable parameters. Compression runs asynchronously; tiny bodies are left uncompressed when overhead would outweigh the benefit. Browsers handle standard Content-Encoding normally. Small action uploads remain ordinary JSON; no client-supplied damage or reward results are trusted.

The web host keeps its private-file allowlist and no-store save responses. Game HTML gains a weak ETag, private revalidation and cached gzip. Unchanged conditional reloads can return HTTP 304 without downloading the embedded-art HTML again. A first load, new build, hard reload or evicted browser cache still needs the full file. This does not shrink or replace the artwork.

### Measured comparison (state response bodies only)

`multiplayer/tools/measure-wire.js` encodes the **same** authoritative snapshots both ways across three seeded five-minute, 20-combatant matches (two scripted humans, 18 bots), with 401 polls per match. Initial full synchronization is included. `multiplayer/sync-audit/bandwidth.json` contains exact totals and assumptions.

The measured five-minute averages are approximately **1.75 MB with the old full+gzip responses versus 0.21 MB with projected deltas and gzip/Brotli**, about **88% fewer state-response bytes**. This is not a carrier data estimate: it excludes HTTP/TLS headers, uploads, cloud-save sync, extra actions between polls, reconnects and the initial game download. The full embedded-art client still requires approximately 26.6 MB compressed when a body is downloaded.

## Tests and limits

The current Node suite comprises 56 tests: 39 existing server/economy checks, five existing sound/unlock checks and 12 added network/codec/dice checks. The web-host suite contains 11 checks including gzip round trips, 304 revalidation, cache invalidation, q=0 handling and private save/file behavior. The original 23-check browser suite and a new 15-check full-HTML synchronization suite are recorded separately with their source hashes.

New tests exercise zero-HP/delayed-respawn rendering, delayed and out-of-order responses, real physical dice top faces, all 216 result combinations, stable progress text, shield/gift/attack outcomes for each pair position, chests, sound, input hit areas, claims and a second shared match. Backend tests cover exact delta reconstruction through 400 updates, compression round trips, old-client compatibility, missing baselines and authenticated rejected-action recovery.

Pre-release regression runs caught an omitted projected `spellsCast` counter, which was restored. Transport query parameters were also restricted to snapshot-bearing endpoints rather than unrelated reward/profile calls. These intermediate runs are not claimed as passes. Browser tests use Chromium mobile/touch emulation and isolated localhost fixtures, not physical phones. Never deploy the test harness or its control ports.

## Deployment contract / Grokbot handoff

Deploy the exact client **and** `arena-server.js`, **`arena-wire.js`** and **`http-compression.js`** together. The new server requires both companion modules. `arena-engine.js` and its balance remain byte-for-byte v110; `game-audio.js` remains v112. Update the reviewed Python web host for gzip/ETag behavior without exposing working-directory files.

Use a separate worktree from the stated parent; do not replace live source with old `main`. Check active rooms and queued users before a brief arena restart, back up the owned service code and arena data, and preserve current player records. Apply the server first, then atomically replace the HTML. A missing/older peer falls back to full snapshots. Verify public compression headers, health, conditional HTML revalidation, two-client matchmaking and reward flow before describing the rollout as verified.

Keep save key `fatebound-save`, solo compatibility106, gameplay protocol1, store schema1, balance110, the 20-second/20-total-player rule, 10-vs-10 teams, previous Guild/modal/chest fixes and v112 sound behavior. No reset or change to Legionary, Caddy routing, signing keys, Android versionCode, main, or Google Play publication is part of this task. An Android bundle embedding older HTML still needs a matching rebuild; updating the website cannot replace an installed local asset.
