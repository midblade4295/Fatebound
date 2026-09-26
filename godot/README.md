# Fatebound Godot Client — Milestone 1

This is a parallel client for the existing Fatebound authoritative arena. It does not replace or fork the server rules.

Target engine: Godot 4.7.2 stable.

Implemented in M1:
- device-local guest arena identity
- gzip HTTP through Godot HTTPRequest
- Fatebound transport-v2 full/delta state decoder
- 20-second / 20-slot / 10v10 matchmaking
- native tower selection
- server-authoritative x1–x4 and ALL-IN rolls
- three confirmed dice faces with pair/triple highlighting
- authoritative HP/KO/respawn display
- Barrage, Bulwark, War Horn and Arcane Surge actions and native VFX
- rally and ultimate actions
- live hero/tower/score/focus/spell/ultimate state
- end-of-match result and reward claim
- same-action-ID retry safety
- a separate Android preview package so it can coexist with the existing Fatebound app

The first milestone intentionally uses native vector/control placeholders rather than re-embedding the 36 MB HTML artwork. Art and animation migration comes after the authoritative server loop is proven.

Run the project with Godot using the godot directory as the project path.

Headless checks:
- res://tests/wire_smoke.gd
- res://tests/api_smoke.gd

The API smoke creates or reuses an explicitly named test guest, joins the real queue, verifies 20 seconds / 20 slots, and cancels immediately.
