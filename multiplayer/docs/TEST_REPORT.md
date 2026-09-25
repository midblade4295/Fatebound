# Fatebound v109 — implementation and test report

Build: `109-adventure-matchmaking-preview`  
Full HTML bytes: **36,236,165**  
SHA-256: `49178287e6e7d05d317b6f497807cee6193f1867a090e187b99d710e8622c6db`  
Base: exact approved v108 / main commit `a0f5eb059f4ca4b2c3bede2880783c64cbaad230`.

## Deployment status

**NOT deployed or activated on the public server.** Remote Desktop Commander listed the authorized host offline and its ping returned no available device. No SSH login, service/proxy change, Play publication or Legionary modification was performed. The feature branch/package is a locally tested preview; main remains the approved v108 version. Online queue/guild buttons require the supplied isolated arena service to be deployed. Connection failure is explicit, not simulated multiplayer.

## Delivered scope

The full game contains the shared Raid/modal layer audit; two equipped spell buttons/shared charges; pinned upgrade goals; per-hero cosmetic mastery; an announced supply objective; contribution-based results and existing-material reward choice; rotating equalized offline challenges; last-tower practice; and the client for a real twenty-player queue and asynchronous invite-code guild expedition. See FEATURES.md for exact mechanics and intentional alpha limits. It does not claim a new 3D raid arena, full recorded replay, Google-account binding, cross-device recovery, ranked MMR or party queues.

## Actual automated results

- **16/16 Node server tests passed**, against the final server/engine files. See server-tests.txt.
- **23/23 full-HTML browser checks passed**, on the exact HTML checksum above.
- **0 uncaught game JavaScript errors and 0 game-console errors** in the final complete browser run.
- **20 inline JavaScript blocks passed parsing**, and readable engine/client/CSS mirrors equal the embedded modules.
- All **103 large embedded base64 asset payloads** equal the original v108 payloads byte-for-byte. No new save migration, reset, fonts or artwork were bundled.

### Final full-HTML browser checks

- PASS — Full v109 HTML boots with a preserved completed tutorial save
- PASS — Five menus remain exclusive; Season Pass opens and closes above each
- PASS — Raid dialog receives touches above Home and Back remains reachable
- PASS — Raid attempt opens, rolls and exits without leaving covered roots
- PASS — Score help, low-resource and stored-gift modal controls remain above the current menu
- PASS — Two-spell selection persists and pinned upgrade reports actual remaining costs
- PASS — Preparation and raid modal controls fit six portrait/landscape/desktop viewports
- PASS — Live guild create and leader route selection use the real HTTP service
- PASS — Equalized offline challenge starts, all dice settle, and Home navigation is absent
- PASS — Offline challenge result and Claim return Home without granting resources or mastery
- PASS — Two browser clients join one authoritative 20-slot room after the deadline. 18 labelled bots; 10 vs 10
- PASS — Reload automatically resumes the same room/identity without allocating another seat
- PASS — Five server-authorized throws settle on the client and synchronize to the other browser
- PASS — Equipped spell casts from the shared charge pool; tower damage agrees across clients
- PASS — Tower map remains usable during locked online matches and a map tap returns to battle
- PASS — Server result, exact-once reward application, Home restoration and Season Pass after claim
- PASS — A second online battle starts after Claim, pass use and loadout reopening
- PASS — Lost claim acknowledgement recovers on document reload without losing or duplicating rewards
- PASS — Original solo progression remains playable with two spell buttons
- PASS — Guided gift use and menu-navigation lessons retain the coach above their dialogs
- PASS — Guided training introduction, scripted roll and safe exit still work
- PASS — Unavailable networking presents an explicit error and cancel, never a fake live bot match
- PASS — No uncaught game JavaScript or game-console errors in completed runs

### Server coverage

The tests cover the full 20-second deadline, 20-human capacity/21st-player overflow, no early bot fill, duplicate join/cancel, abandoned queues, two clients observing the same room, validated actions/cooldowns/multipliers, shared spell charges, in-place disconnect/reconnect, substitute rolls not earning human eligibility, one-time supply rewards, match completion/duplicate claim/new match, actual guild contributions/milestones/hopping protection, atomic persistence/restart, HTTP authentication/CORS, immutable shard choice and malicious/prototype-key inputs. Online randomness is supplied by the server's cryptographic random generator; practice uses the local engine.

### Environment and fixtures

Node v22.16.0; Chromium at `/usr/bin/chromium` with Playwright mobile/touch emulation. This is not a physical Android/iOS test, public-server deployment test, distributed/load test, or complete production security audit.

The full approximately 36 MB HTML—not a stripped mock—executes in browser documents. A disposable in-memory localStorage adapter supplies isolated test saves; actual fetches are routed to a real loopback HTTP server. Other external requests/fonts are blocked. The tested game source is frozen at test start and its checksum is recorded to prevent mixed-version runs. Real pointer/touch hit tests verify that dialogs are above Home, not merely marked visible.

Layout checks cover 360×640, 393×852, 412×915, 768×1024, 1280×800 and 640×360. Two browser clients share the same server room. Twenty-human capacity and overflow are tested in the backend, not with twenty physical devices.

A **separate localhost-only test harness** advances queue/match clocks and stages resources/HP to exercise spell use and completion. It can stop bots for synchronized-state comparisons. Guided-training tests stage specific lesson indices for gift/menu checks after an actual introductory roll; they do not claim to retest every lesson end-to-end. The lost-claim test commits on the server, drops the reply, reloads the document, verifies receipt recovery and then reloads again to check no duplicate grant. The unavailable-service test returns 503 and verifies explicit error/cancel behavior.

None of those fixtures, test tokens, control endpoints or balance overrides are in the delivered game or the production `arena-server.js` entrypoint. Do not deploy `tests/harness-server.js` or its ports 8851/8852.

### Findings fixed during integration

Raid and other modal controls now receive touches above Home; the Season Pass retains its independent scroller and level-up priority. Guided coach/gift/menu layers stay visible through their real transitions. Delayed raid-summary/KO callbacks are bound to the raid that scheduled them, so they cannot reopen over a later screen. The v107 idempotent observer fix remains intact.

The new server rejects invalid spell/action/claim inputs, preserves action receipts for the whole match, does not resurrect an already-claimed room on restart, and fixes the reward material choice on first claim. The client journals a pending claim before sending it and retries after a lost-response reload; local receipt IDs prevent duplicate application.

Earlier development runs exposed timing assumptions in the test harness (raid exit delay and critical-roll duration) and an uncaught `dmg` access in an earlier mixed-source run. The final harness waits for actual exit/roll completion, freezes the source, and records full error stacks. Two subsequent complete runs passed with no game errors; the final report above is tied only to its exact checksum. This is not a guarantee that every UI edge case or live-device condition is covered.

## Data and operating boundaries

The old save key and battle-session compatibility 106 remain. No existing save/cloud database or upload key is modified. Online combat is equalized guest-device alpha; legacy local stats are not trusted as online power. The original offline hero/inventory is restored before valid online rewards are applied.

Deploy only the separate loopback-8081 service with its private state directory and reviewed TLS proxy route. The single-process JSON store is not a distributed database. See DEPLOYMENT.md for preflight, backup, activation, limits, metrics and rollback. Live activation must be verified with two physical clients before describing it as active.

## Final readable-module hashes

- `arena-client.js`: `3fd4142078101451b5e1641446e38542ab5625e8dbca2095d33c41f071a63e8a`
- `arena-server.js`: `cd295935c06d3abecafd0e5c988b21e766e4a0989aa476d60ee94424536cb296`
- `arena-engine.js`: `2c57c2288d0104aaf7951b5de4c43854ddf87635427966bd0c7a80bc31cfadc3`
- `metrics.js`: `81caa42dcba0794651675934ef51fb4ace80dd403cb0638dcbec98e1f94fecec`
- `adventure.css`: `3d1184a3efffb3a8a359a39eff3fed2e64f952a52ffbd1258d2cea018e0c1334`
