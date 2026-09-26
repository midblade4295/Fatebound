# Fatebound Godot M1 verification

Verified against the existing live Fatebound arena without replacing the production HTML client.

## Native-client scope

Godot 4.7.2 M1 implements live guest identity, 20-second / 20-slot matchmaking,
transport-v2 state decoding, tower movement, server-authoritative dice and multipliers,
ALL-IN, spells, rally, ultimate, KO/respawn state, five-minute results and reward claim.

The production combat engine remains server-authoritative. Godot does not duplicate
damage, reward, respawn or dice formulas.

## Real-match verification

Two Godot clients completed a real public five-minute match before the cursor correction.
That proved actions/KO/respawn/results but showed the Godot cursor was serialized as
floating-point query values such as revision=4.0, causing the strict arena server to fall
back to full snapshots.

After casting cursor revision/sequence to integer strings, an isolated transport test
switched from one full state to deltas, and a second real public match passed:

- rolls: [76, 62]
- moves: [1, 1]
- spells: [1, 1]
- rallies: [1, 1]
- ultimates: [1, 1]
- KOs observed: [2, 3]
- confirmed respawns: [2, 3]
- matching final score on both clients: [13.0, 37.0]
- transport A: {'delta': 458, 'full': 1, 'resync': 0, 'stale': 0}
- transport B: {'delta': 445, 'full': 1, 'resync': 0, 'stale': 0}
- response bodies across both clients: 1,516,000 bytes
- response-body reduction versus the first full-snapshot Godot run: 91.27%

This response-byte count excludes request/TLS headers and is not phone carrier metering.

## Android preview

A separate debug APK was exported so it can coexist with the production app:

- package: com.fatebound.godotpreview
- version: 0.1.0-m1 / code 1
- min SDK 24
- target SDK 36
- APK SHA-256: f83dcc6528bf539a5997424606169148d0f1f6b1127c9ab9f2b27f4d87ec589c
- size: 56,997,694 bytes

The APK uses a dedicated Android debug key for preview continuity. It is not a Play
release and is not signed with the production Fatebound key.

## Remaining M1 limitation

The native battle UI currently uses Godot controls/vector placeholders. It proves the
server loop but does not yet reproduce the complete production artwork, character
animation, Home/Guild/Raid/Shop shell, or permanent progression UI. Physical Android
touch/render/audio/thermal testing is still required.
