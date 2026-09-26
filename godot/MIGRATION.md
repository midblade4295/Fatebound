# Fatebound Godot migration

The HTML/WebView game remains the production client until the native client reaches parity. This migration reuses the existing authoritative server instead of reimplementing combat rules.

## Milestone 1 — authoritative battle loop

Current scope:
- live guest session
- 20-second matchmaking and 20 slots
- transport-v2 full/delta decoding over compressed HTTP
- ten tower movement
- three server-confirmed dice
- multipliers and ALL-IN
- HP, shields, KO and server-confirmed respawn
- four spells, rally and ultimate
- native spell effects
- five-minute result and reward claim
- Android preview package separate from production

No permanent economy, guild, raid or Home screen is migrated in M1.

## Milestone 2 — visual parity

Replace native placeholder tokens with imported Fatebound character/environment assets. Add AnimationPlayer/AnimationTree character states, native dice animation, native combat feedback and audio buses.

## Milestone 3 — persistent game shell

Migrate Home, Hero/Armory, Season Pass, Shop, Guild, Raid, friends and progression views. Keep server-authoritative battle state isolated from permanent account state.

## Milestone 4 — Android parity

Physical-device performance, thermal/data tests, lifecycle/reconnect, safe areas, input method editor, accessibility, graphics settings, update path and signed Play bundle.

## Milestone 5 — client cutover

Only after progression compatibility, physical-device testing and rollback procedures pass should the Godot package replace the WebView production package.

## Server contract frozen for M1

- live API: /fatebound/arena
- gameplay protocol/store schema: 1
- transport: 2
- balance: 110
- queue: 20 seconds
- capacity: 20
- teams: 10 vs 10
- battle duration: 5 minutes
- action retries reuse the same actionId
- HP/respawn and dice results are always server authoritative

The Godot client must not silently add combat formulas that can diverge from the arena engine.

## M2 visual parity started

The first M2 pass adds native confirmed-dice settling, simultaneous matching-dice
highlight/pulse, damage/shield/gold/focus/gift floating feedback, field flash/shake,
and KO/shield hero-row treatment. These effects consume server-confirmed results only;
no combat formulas moved into Godot.
