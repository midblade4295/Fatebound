# Current source: v114 battle and Guild feedback

Use `chatgpt/v114-battle-guild-feedback`, based on v113 head
`4affef9e8b8611491d50603ded6ce6129622701c`.
Build `114-battle-guild-feedback`, 36,338,476 bytes; SHA256
`84697859827127e8c9285b0cf57578a8fc2bcedcb3cf8d3247772f0309f3b4e9`.
Read `multiplayer/docs/BATTLE_GUILD_V114.md` and `multiplayer/battle-guild-audit/`.

Deploy the paired HTML, arena-engine.js and arena-server.js. Keep v113
arena-wire.js/http-compression.js and the existing Python web host unchanged.
The private roll bank travels outside the unchanged compact match projection;
protocol/store1, transport2, balance110, solo106 and20seconds/20slots/10v10 stay.
Human substitutes fight in their selected tower but never auto-rotate. Preserve
continued state polling during pending actions, completed-tap map selection,
canvas try/finally restoration, explicit roll effects, single-owner HUD/layout,
the stable native Guild composer, and bounded confirmed spell effects.
The Company War room remains explicitly DEVICE-LOCAL, not network guild chat.
No odds/payout/new-role mechanics, save reset, Legionary, Caddy, signing, Android,
main merge or Google Play change. Installed Android assets need a v114 rebuild.
52 full-HTML browser checks,64 Node and11 Python checks passed on the exact hash.
Browser tests emulate touch and include induced faults, not physical Android.
Live rollout and8public HTTPS checks have passed; source was reverified on continuation.
Read `multiplayer/battle-guild-audit/live-deployment.json`, `public-smoke.json`,
and `resume-verification.json`. Production code commit: `cca34e6ca9d3e9c63730195dc68018cbd25917d8`.
PR#16 is the current review; launch v114 rather than older main/v113 assets.

---
## Earlier instructions retained only as historical provenance

# Current continuation: v113 state/dice/network fix

Use branch `chatgpt/v113-sync-dice-compression`, based on v112 head
`b322d3b9bb30719a2b7de1e058773ce0473f8bb5`, not old main HTML.
Build `113-state-dice-network-fix`; 36,304,138 bytes; SHA-256
`56ad2d138c503d6a9b20bece12276252dd95bcf15e129a7030316383aa159a7f`.
Read `multiplayer/docs/SYNC_NETWORK_V113.md` and `multiplayer/sync-audit/`.
Deploy the matching arena-server.js WITH arena-wire.js and http-compression.js.
Python web-host changes provide gzip and private ETag revalidation. Do not expose
working directories. New optional transport2 is NOT gameplay protocol2:
protocol/store1, balance110, session106, 20-second/20-total-slot matchmaking and
existing v112 audio remain. All103 large embedded assets are unchanged.
Preserve authoritative HP/respawn, monotonic snapshots, roll-index receipt checks,
single-owner HUD labels, all-three-dice winning feedback, bounded wire histories,
Brotli/gzip negotiation and full-snapshot fallback. Never deploy harness controls.
No save reset, Legionary/Caddy route, main merge, Android or signing changes.
Live rollout and seven real-clock public TLS checks are verified. Read
`multiplayer/sync-audit/live-deployment.json` and `public-smoke.json`.
51 browser,56 Node and11 Python checks passed; physical phones are not claimed.
The code commit is `3e07029d8890e0072266c6370665fd341b8eb7a1`; review PR #15.

---
## Earlier instructions retained as historical context

# Fatebound v111 — UI and sound continuation

Current task branch: `chatgpt/v111-ui-audio`, based on v110 head
`8a04f85e0739a4606266c6ec32f99c8bce8b042e`. HTML build
`111-ui-sound-workshop`, 36,286,487 bytes, SHA-256
`8cb7cc7f5c04898183bc298c4f23fb96ce203cf2794df043534cdc36912dad84`.
Read `multiplayer/docs/UI_AUDIO_V111.md`, the manifest and
`multiplayer/ui-audio/TEST_SUMMARY.json`. Live installation is recorded separately.
Do not restore older whole-file source over this update; main remains separately
managed. Preserve the stable Guild nodes/draft/scroll, reserved battle tool and
announcement rows, persistent chest inbox, and original single-context audio
mixer. Keep the six readable mirrors synchronized, 103 embedded art assets,
`fatebound-save`, session106, protocol/store1, balance110, two equipped spells,
and 20-second/20-slot matchmaking. Held KO loot retains its existing x3 automatic
end-of-solo-match rule; no reward formulas or backend code were changed here.

Use new task branches; no force-push, token exposure, sudo bypass, save reset,
Legionary/Caddy change or Play publication without authorization. The test harness
and audio WAV exports are not production server endpoints. The sound code is
embedded; do not add unnecessary sample network dependencies. After future edits,
update hashes and rerun actual menu/chest/audio/battle interactions, not parsing
alone. Numerical/headless browser checks are not physical-phone listening tests.

---

## Historical v110 instructions and provenance

# Fatebound — v110 audited branch

Full game: `fatebound.html`. Branch: `chatgpt/v110-audit-balance`, based on the
deployed v109 feature build. Main is separately managed; this branch is not an
Android versionCode or an automatic Google Play release.

Read [GROKBOT_HANDOFF.md](GROKBOT_HANDOFF.md), [AGENTS.md](AGENTS.md), the
[audit](multiplayer/docs/AUDIT_V110.md) and
[live deployment record](multiplayer/docs/DEPLOYMENT_V110.md).

```sh
sha256sum -c fatebound-source.sha256
python3 multiplayer/tools/sync-inline.py --root .
node --test multiplayer/tests/server.test.js multiplayer/tests/audit.test.js
python3 -m unittest discover -s multiplayer/tests -p 'web_host_test.py' -v
node multiplayer/audit/balance-sim.js
```

Full-browser suites use `multiplayer/tests/harness-server.js` on localhost only.
Never deploy this test harness, comparison fixtures or debug controls. Production
arena remains loopback8081 behind TLS. The allowlisted web host serves the full
HTML and compatible legacy save API without publishing private directories.

Save key `fatebound-save`; solo compatibility106; arena protocol/store schema1;
new-room balance110. Existing artwork, permanent progression and Season Pass
claims are preserved. Online play remains equalized guest-device alpha.

Android's existing workflow copies the root HTML into its generated asset.
Do not edit that generated copy as a second game source, reuse consumed Play
versionCodes or replace the upload key. No Legionary changes are included.

Live v110 deployment and six real-clock public TLS checks passed on 2026-09-25 UTC.
See `multiplayer/docs/DEPLOYMENT_V110.md` and `multiplayer/audit/public-smoke.json`.
Review PR #12 is stacked on v109 PR #11; main is unchanged.

The v111 HTML is live as of 2026-09-25 15:07 UTC, verified from code commit
`f950a49606662733e7091663f4946b7615c8009f`. Read
`multiplayer/ui-audio/live-deployment.json`. Arena balance110 and its process
were unchanged; do not overwrite the deployed client with v110.

Live client is now v112 audio-unlock-fix, deployed 2026-09-25T15:29:43Z. Preserve its delayed-resume queue/fallback logic; do not restore v111 audio startup. Balance110/backend remain unchanged.
