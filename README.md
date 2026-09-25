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
