# Fatebound v114 — battle feedback, tower safety, Guild hall and spell effects

## Source and scope

Based on the exact v113 deployed source from `chatgpt/v113-sync-dice-compression`, head `4affef9e8b8611491d50603ded6ce6129622701c`. Parent HTML SHA-256: `56ad2d138c503d6a9b20bece12276252dd95bcf15e129a7030316383aa159a7f`.

New branch: `chatgpt/v114-battle-guild-feedback`. Build: `114-battle-guild-feedback`.
The canonical full HTML and readable source mirrors remain synchronized. The existing 103 large embedded artwork blocks and v112 audio are preserved. Matchmaking still waits 20 seconds, then fills 20 total slots in 10-vs-10 teams. Combat protocol/store1, transport2, balance110 and solo session106 remain. This task does not merge main, publish an AAB, change signing or touch Legionary/Caddy.

## What was actually found

1. Human substitution was also eligible for bot relocation. Random/supply movement and bot rallies could therefore change a disconnected human slot's tower. The client also paused state polling whenever an action was pending, so a sufficiently delayed response could cause the server to substitute a still-open client.
2. Map rendering changed the shared global canvas context and restored it only after successful drawing. In a fault-injection reproduction, a failed hero draw left the active context pointing at the map canvas with scale4. That is a confirmed unsafe code path, not a recovered stack trace from the user's physical device. Similar temporary QTE/boss context switches lacked guaranteed restoration.
3. Tower map selection happened on pointer-down, before the browser knew whether the gesture was a scroll. Outer synchronous tower wrappers could also act before the asynchronous network move completed.
4. Personal gold/XP was earned on the server and banked for match completion, while the old wallet displayed owned persistent resources. Short symbol notifications were then replaced by nearby bot messages. This made successful rolls appear to grant nothing.
5. The battle menu used a lower stacking layer than its own footer. The original 393x852 check measured the drawer beneath a z90 footer (drawer z70). The duplicate tactical/HUNT strip competed with the header. Shorter viewports exposed the overlap.
6. Ordinary Chromium typing did not reproduce reversed text. However, a changed match identity replaced the old Guild input during render; the induced test moved its selection from2 to5 while keeping the draft. The new composer does not re-create/rewrite the editable input on live refresh, so native insertion/composition can keep its own selection.

`multiplayer/battle-guild-audit/baseline-proof.json` records the induced canvas/caret scenarios and their limits.

## Implemented corrections

### Authoritative rolls and visible effects

Action replies include a numeric summary of actual server-side changes: damage/absorption, new shield absorption, Focus returned, gift damage, capped gold/XP accrual, spell charge and paid-roll count. Periodic state carries the player's own capped banked totals outside the compact match projection. Existing v113 transport field lists are unchanged, so old full/delta clients remain compatible.

A reserved result panel shows the last personal result independently of ambient announcements. Gold says **banked**; gifts say to use **Attacks**; full Focus, stronger existing shields, and reached gold caps do not pretend to grant more. Gold/XP are still applied to the persistent wallet by the existing exact-once match receipt, not by the visual panel. Practice still grants no persistent resources. Older retried rolls identify themselves rather than leaving the panel stuck at ROLLING or replacing newer confirmed dice.

### Tower control and canvas recovery

Only real bots may move automatically. A substitute keeps fighting from its human's selected tower but cannot relocate it for supply/rallies/random choices. Active state polling continues while action requests wait. Authoritative HP/respawn, monotonic snapshots and same-action-ID retries remain.

Map dragging/scrolling no longer selects a tower. Selection needs a completed short tap with small movement, and online view changes wait for the accepted move. Local coordinate caches, lunges, effects and camera offsets are cleared at scene boundaries. A successful roll can still be collected/displayed when its old-board animation is cancelled by an intentional tower change.

Map/QTE/boss drawing now restores temporary contexts in finally blocks. The outer battle renderer recovers from a failed/clipped/scaled frame; it does not reset the canvas on normal frames. Injected failures are logged as recovery warnings, not silently counted as successful draws. No new rendering loop or document-wide input gate is added.

### HUD and Guild redesign

The scoreboard has its own height; the duplicate tactical/HUNT strip is hidden while the compact rival card remains. Results, notifications, dice field, multipliers, spells, ROLL and footer use separate layout regions. The More drawer and dimmer sit above the footer and can scroll inside the visible phone viewport. Safe-area padding and visual-viewport height are included; portrait/landscape layouts are checked separately.

The Guild hall has Overview, Company and War room tabs, a crest/header, live-expedition summary, solo-company score/stat cards, and an explanation of the selected hero's existing perks. Its input is mounted once, left-to-right, native text editing, with composition-aware submission and a preserved device-local draft. Sending uses text nodes and submits once. Updating scores, rosters or messages does not overwrite the draft or caret.

The existing solo/company chat was not a network guild-chat service. The redesigned War room explicitly labels messages as device-local; real guild membership/expeditions remain separately available through Live guild. This update does not pretend local bots/messages are other human players.

### Spell effects

Confirmed Barrage draws three falling impact trails and sparks; Bulwark draws allied protective domes/rings; War Horn emits golden rally ripples and a beacon; Arcane Surge draws purple runic arcs. Effects are scoped to the current match/tower, recent confirmed nearby casts, and expire after1.5seconds. At most8 instances are active. Reduced-motion variants have less movement, the clipping region keeps them off dice/health/control surfaces, and no new artwork/audio downloads are added.

## Test methodology and limits

Full-HTML browser tests use Chromium with mobile touch emulation and disposable local save/API fixtures. Artificial outcomes, time advancement, errors, and delayed replies exist only in tests and are never deployed. Tests compare actual numeric receipts with state, exercise all216 dice combinations, delayed action polling, accepted moves, map drag/tap, canvas restoration, native caret/composition handling, four spell actions, dialogs at seven viewport sizes, match-end collection and another match.

Node tests also simulate thirty seeds with twenty-four substitute action steps each, and forced rallies, to ensure human tower choice is not overwritten. Existing protocol, wire projection, compression, reward caps and exact-once receipts remain covered. Source hashes in every report identify the exact tested HTML; historical reports are not counted as new tests.

An intermediate browser-test fetch shim accidentally returned a function, which Playwright invoked with null; its wrapper was corrected. Another run completed all23 original checks but failed to write its report because an output directory was missing; the test now creates its report directories and was rerun. These test-runner failures are documented rather than described as production fixes.

Final counts and live-rollout evidence will be recorded under `multiplayer/battle-guild-audit/`. Emulation/induced faults are not physical Android keyboard, phone GPU or acoustic validation. Real guild chat, Google-bound accounts, and production-scale load testing are not added in this patch.
