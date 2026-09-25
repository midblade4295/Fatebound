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
