# Fatebound v111 — Guild stability, battle layout, chest access and custom sound

Build: `111-ui-sound-workshop`  
Base: `8a04f85e0739a4606266c6ec32f99c8bce8b042e` (deployed v110)  
Branch: `chatgpt/v111-ui-audio`  
HTML bytes: 36,286,487  
SHA-256: `8cb7cc7f5c04898183bc298c4f23fb96ce203cf2794df043534cdc36912dad84`

Deployment status is recorded separately in `multiplayer/ui-audio/live-deployment.json`
after rollout. These local results alone do not claim deployment or physical-phone testing.

## Reproduced problems and fixes

### Guild page jerk

The original Guild renderer replaced the whole screen every second. A separate
UI refresh then inserted the expedition button above the new contents. The
recorded baseline alternated between 2,628 and 2,686 pixels of content; a fixed
scroll position jumped from 430 to 488 and onward as the extra 58-pixel element
returned. This also replaced the chat input and could discard an unsent draft.

Guild structure, expedition slot, member rows and input now remain mounted.
Changing scores, health and messages update in place. The refresh does not sort
or replace the roster underneath a reader. It only writes scrollTop if a repair
is actually needed; it does not repeatedly interrupt inertial scrolling. A
five-second sampled test retained the same input/button nodes, draft, scrollTop
430 and content height 2,715 while data refreshed. Sending chat also updates in
place. The v107 idempotent notification observer remains intact.

### Battle HUD

The nemesis/revenge portrait, stored attacks and chest access occupy a dedicated
utility row, separate from the canvas and garrison health. ROLL, multipliers,
Rally, ultimate and the two equipped spells have their own normal-flow rows.
The obsolete single-spell footer widget is not shown alongside the two-spell UI.
Notifications and phase/hero banners use one reserved announcement strip rather
than covering enemy nameplates, health or lower-left controls. Guild gift
notifications also occupy their own space instead of covering ROLL.

On short portrait screens duplicate tactical/momentum detail is compacted;
landscape uses a side control column. Six sizes were checked: 360x640, 393x852,
412x915, 768x1024, 1280x800 and 640x360. The tests include actual centre-point hit
tests and bounding-box intersections, not only visibility flags, plus long
reconnect/objective/defense labels and a guild gift shown together. The tower map
still works while Home navigation is locked during a live match.

### Chests

The original roll-chest rewards were already saved; their notification and access
were too transient. A persistent Chests badge now exists at Home, in battle and
on the tower map. The inbox has no countdown and shows the banked gold/shard
amounts. The roll-progress strip opens this inbox rather than silently collecting.
Later and menu changes do not discard the bank. Collection reuses the existing
atomic reward path, including repeat-claim protection and saved-state recovery.
The test left the inbox open past the old toast interval, reloaded the document,
and collected the original 400 gold / 2 shards once with no duplicated grant.

Unopened KO loot can be dismissed with **Decide later — keep saved** and revisited.
**Held KO loot still follows the original automatic x3 end-of-solo-match rule.**
That rule, loot odds and reward amounts were not rebalanced. The inbox explains
it rather than implying every type waits forever. Collection is temporarily
disabled during a throw/choice/training or an online match, with an explanation;
existing offline rewards can be collected after returning Home. Online battle
completion receipts remain separate; no new multiplayer chest drops were added.

## Custom sound design

41 original, layered procedural PCM cues cover menu taps/open/close/confirmation,
equipment/purchases/errors, dice roll and landing, sword/axe/bow/magic attacks,
impacts/critical hits, shields/shield breaks/parries, damage/defeats, four spells,
hero ultimates, gold/Fate/gifts, level-up/chest readiness/opening, capture/timers,
match start and victory/defeat. These use shaped noise, transients, resonant
metal partials, plucks, bells, additive brass and swept magic tones—not downloaded
samples or additional music. Weapon variations use their own deterministic RNG
and do not consume gameplay random numbers.

Solo/raid attacks use weapon-specific cues. Online effects follow confirmed
results; other players are quieter and only recent nearby events play. Reconnect
snapshots do not replay old attack sounds. Menu feedback is nonblocking, and
purchase feedback runs after success rather than promising an unsuccessful buy.

Sound studio is available from the Home speaker icon and battle More > Sound.
Master, combat/spells and menus/rewards have separate saved sliders. Existing
`ds-mute` is honored, and new levels use `fatebound-audio-prefs`. There is one
lazy AudioContext unlocked by an actual user gesture, cached sample buffers,
rate limiting, a 16-voice cap and cleanup of ended/background sources. Missing
Web Audio or preference-storage access does not break the game. The old countdown
beeps no longer create a fresh AudioContext each time.

The real production mixer uses compression, an oversampled soft limiter and
master headroom. Initial maximum-volume stress testing exposed overshoot; the
limiter ceiling was reduced before release. The final actual Chromium graph was
rendered with 16 simultaneous voices for **every one of the 41 cues** at maximum
bus volumes. All samples were finite; the highest measured sample peak was
0.954023, below digital full scale. This is a numerical
headroom check, not a claim that loudness/timbre was evaluated on a physical phone.

The optional WAV preview/export pack comes from the same generator. Runtime
sounds stay embedded as code in the HTML; no network audio fetch or large sample
bundle is required. The complete HTML grew by 37,849 bytes over v110.

## Verification

- 42 Node tests passed: 39 existing backend tests plus 3 sound-generation tests.
- 9 Python web-host tests passed.
- 64 full-HTML browser checks passed: 23 original, 23 v110 regressions, 13 new
  Guild/chest/HUD/audio checks and 5 additional mixer/short-layout checks.
- An additional actual browser mixer stress run covered all 41 cues x 16 voices.
- All 22 inline JavaScript blocks parsed; six readable inline mirrors synchronize.
- All 103 large embedded artwork blocks are byte-for-byte unchanged.
- Server engine, arena server, metrics and Python web host are byte-for-byte v110.
- Save key, solo compatibility106, arena protocol/store1 and balance110 remain.

These checks include two browser clients sharing the actual loopback server,
queue/bot fill, rolls, spells, map, reconnect, results, exact-once claims and a
second match; Home/Pass/raid/training regressions; chest persistence and audio
preferences, unavailable audio, background cleanup and high voice overlap.
No uncaught game JavaScript or game-console errors occurred in the final runs.

## Test harness corrections and limits

The old completion fixture forced only Tower X to one side and occasionally
created a valid tie against random bot scores. Its test-only finish setup now
forces all test towers before requesting regulation completion. This avoids a
false expectation that tied matches skip overtime. Production scoring is
unchanged. A new test initially used the wrong Continue selector; it was corrected
to the existing staged result controls, not bypassed in game code.

One concurrent harness run reported **Page crashed** while many full-HTML browser
contexts and the 41-cue offline stress renderer were running together. The final
UI/audio suite was rerun separately and completed. This was a harness process
failure, not silently counted as a pass. No physical-device memory/performance
or subjective speaker-quality guarantee is inferred from the tests.

Tests use installed Chromium with touch emulation and isolated in-memory saves;
requests are routed to a private loopback fixture. Deliberate resources/deadlines,
connection failures and old receipts are test fixtures only. None of those
fixtures or debug HTTP endpoints appear in the shipped HTML/production server.
No user account tokens, player save data, font files or server backups are in the
package. The earlier v110 match simulations are historical and were not rerun
for this UI-only update; production combat formulas did not change.

No main merge, Android version/signing change or Google Play publication is
implied. The live Fatebound HTML update can be atomic without restarting the
arena, modifying Caddy or touching Legionary. See the deployment record for the
actual installed hash and verified public response.
