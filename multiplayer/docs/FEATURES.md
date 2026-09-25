# Fatebound v109 — gameplay and matchmaking preview

Status: implemented and locally tested; remote deployment and physical-device verification pending. Parent is the exact approved v108 source on main, commit a0f5eb059f4ca4b2c3bede2880783c64cbaad230. The stable main branch should not be silently replaced before the deployment boundary is verified.

## Play flow

Prepare is available from Home and the main battle button. Select two distinct spells; two labelled buttons share one two-charge pool. Pin a weapon upgrade and see actual remaining gold/shards. Earn per-hero Assault, Guardian and Commander mastery from damage, damage absorbed/defense and real rally participation/captures. Mastery ranks unlock a cosmetic portrait outline and visible title badge, not combat power. Online reward claims offer a choice of the three existing shard types.

One Camp supply objective is announced at 1:45, active from 2:00 to 2:30 and resolved once. The side with more control time receives a bounded resource bonus; the main crown objective remains unchanged. Online protection and surge durations are displayed. Solo progression retains the original simulator; its opponent supply reward is a brief attack buff because those old bots do not own the player's spell pool.

The new compact online/challenge result screen reports actual contributions, an evidence-based tip, mastery, pinned goal and rewards. Claim & Home, Play again, Change loadout and Practice last tower are explicit actions. The 60-second practice scenario recreates the last tower/score deficit, not a full recorded replay.

Daily challenges rotate Focus Rush, a fixed-loadout trial and Guardian Trial. They use equalized offline combat, clearly labelled bots, and grant no currency/mastery/ranked rewards. They do not fragment the single live matchmaking queue. Solo progression and the original guided training remain available.

## Real 20-player matchmaking

A server lobby waits the complete 20 seconds from the first arrival, including when already full. It then starts exactly **20 total combatants, 10 per side**. Empty slots are labelled bots; a 21st human enters another lobby. No bots are inserted early. Cancellation is allowed while searching but not during a live match. The map is part of the locked battle; Home navigation remains absent.

The dedicated Node service uses a cryptographic random source for online rolls and owns dice, damage, Focus, spell charges, cooldowns, towers, phase clock, bot behavior, final results and reward receipts. Clients send commands and render snapshots; they do not run a separate online battle simulation. Request-ID reuse does not spend twice. A pending-claim journal retries a server-committed reward after a lost response/reload; the local save applies each receipt only once. Disconnects receive an explicit bot substitute and reconnect to the same slot. On reload, a saved arena identity checks for its existing match rather than creating a duplicate player. An unavailable endpoint shows a connection error, not a fake multiplayer game.

The transport is authenticated HTTP polling with gzip snapshots, suitable for this turn-paced alpha. No WebSocket implementation or latency/load guarantee is claimed. Online uses level-10 common-power equipment and server-side class traits; locally editable legacy stats cannot buy a competitive advantage. The original offline inventory/level are restored after an online match. Online critical results resolve server-side rather than trusting a client-reported critical mini-game multiplier.

Guest identity is local to the device. Google-account binding, ranked MMR, party queueing and account recovery are not implemented in this alpha. The current task did not define those systems. Do not call it a finished production authentication service.

## Weekly guild expedition

Create/join a real guild with an invite code. The leader chooses Assault, Defense or Command before the week's progress starts. Verified completed online battles contribute according to actual match metrics, capped at five per battle and 20 per day. Guild members can contribute asynchronously. Stages at 20/60/120 grant once-only milestone rewards to contributors; the final shared Citadel objective is an asynchronous progress boss, not a new 3D raid arena. Route/progress reset on Monday UTC; already collected rewards remain. Old solo clanmates are explicitly described as simulated and are not mixed into the real roster.

## UI audit and preservation

The shared modal layer places Raid, stored attacks, help, resource/chest dialogs and Season Pass above Home; level-up stays above parent dialogs. Hidden elements stay noninteractive. Large dialog content scrolls within the viewport and action controls stay reachable. The v107 observer/input fix and v108 pass semantics are retained. No document-wide click-swallowing gate, history lock, new save reset, or new embedded art was added. Original save key and battle-session compatibility 106 remain.

Source mirrors under src are embedded in the full HTML. tools/sync-inline.py checks/updates only those named current inline sections; it never regenerates the game from an old branch. Tests and local-control fixtures are not production entrypoints. The production service uses src/arena-server.js only. Read DEPLOYMENT.md before activating.
