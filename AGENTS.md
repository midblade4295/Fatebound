# Fatebound v109 feature-branch instructions

This branch is `chatgpt/v109-adventure-matchmaking`, based on the approved v108 main at `a0f5eb059f4ca4b2c3bede2880783c64cbaad230`. It contains a **preview**, not a deployed multiplayer release. Main remains the stable v108 source until review and authorized activation.

Read `GROKBOT_HANDOFF.md`, `fatebound-source.json`, and `multiplayer/docs/{FEATURES,TEST_REPORT,DEPLOYMENT}.md`. Fetch and inspect the working tree before editing. Preserve local changes; no force-push, hard reset, or old whole-file replacement. Do not edit the same branch concurrently with another agent.

Preserve the v107 idempotent DOM-observer/input fix, exclusive hidden-Home layout and v108 Season Pass behavior. The new modal layer also covers Raid, help, resources, stored gifts and training. Keep the save key `fatebound-save`, battle-session compatibility 106, and original embedded artwork. Do not introduce a reset migration or a global event-swallowing input gate to repair UI problems.

`fatebound.html` remains the full game. Readable mirrors for the named v109 engine/client/CSS sections live in `multiplayer/src`. `python3 multiplayer/tools/sync-inline.py --root .` checks consistency. To change them, use that tool's explicit write/new-build-marker mode and then run runtime tests; it updates only the current inline sections, never rebuilds from an older base. Update the source manifest/checksum in the same commit. Historical `patches/` import scripts are transport provenance, not development rebuild commands.

Run the Node server tests and full-HTML browser regressions, including two clients, Claim & Home, lost claim acknowledgement/reload and a second match. Syntax checks alone do not establish working input. State which tests actually ran, on what source checksum, and distinguish local emulation from live/physical-device testing.

The live 20-slot queue waits 20 seconds from first join and then fills missing players with labelled bots. No early bot fill, fake multiplayer fallback, client-authoritative damage, or duplicate reward application. Online alpha is equalized guest-device play; it is not Google-bound/ranked/party matchmaking. Do not imply otherwise.

The new server is isolated as `fatebound-arena.service` on loopback 8081, with its own data, and needs a reviewed Caddy route. The remote connection was offline: deployment is pending. Do not replace the existing Fatebound save service on 8080, modify Legionary on 3000 or `/opt/legionary`, change upload keys, or publish a Play release without the user's specific authorization. Never deploy the test control harness/ports.
