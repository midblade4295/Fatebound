# Fatebound v110 — code, gameplay, economy and UI audit

Base: the exact deployed v109 source at `8705e7e2e150dfbcebe94e81df51b71f7f14af6e`.
Source branch: `chatgpt/v110-audit-balance`. HTML build: `110-audit-balance`.
See `../../fatebound-source.json`, `../audit/integrity.json` and the checksum file
for the exact tested artifact. Deployment evidence is separate in
`DEPLOYMENT_V110.md`; this report does not equate local tests with phone testing.

## Confirmed defects and changes

### Combat and rewards

1. **ALL-IN gifts:** the old fixed 500-damage base produced a 24,000-damage
   opening triple at ×16 in the equalized arena, whose heroes have roughly
   1,700–2,100 health. Gift power now follows attack power, result units,
   multiplier and phase/Surge, rather than the unrelated old constant. Pending
   and received banks are each bounded at two of their owner's maximum health
   bars. Partial transfers retain the excess with the sender instead of losing it.
2. **Self-funding spells:** a neutral capture used to refund Barrage's charge and
   add Focus. Capture bonuses now require a paid dice attack changing an
   enemy-held tower; neutral tags, spells, ultimates and stored attacks cannot
   refund a spell. Contested paid capture bonuses have a per-player/per-tower
   30-second cooldown. Triples keep their ordinary charge and final-30-second
   double-charge behavior.
3. **Barrage consistency:** the spell's 1.5× description now means 1.5× a triple
   sword's base power: 225 damage at 30 attack before phase/defenses, versus 90
   previously. The solo version resolves a spell strike, not a hidden dice roll
   with free Focus, roll progress or additional charges.
4. **Free ALL-IN:** Rampage now provides five free ×1 rolls with its existing
   double attack effect, not five free high-multiplier/ALL-IN attacks. Normal
   paid ALL-IN remains a commitment of available Focus.
5. **Bot gift funnel:** bots select an eligible recipient rather than feeding
   every gift to the first teammate in the array. Human gift choice is unchanged.
6. **AFK reward credit:** substitute bots still fight in the disconnected
   player's slot, but their gold, damage, defense time, mastery and guild merits
   no longer increase the absent human's personal earnings. Reconnection resumes
   human credit without retroactively claiming the substitute's work. The team's
   result still includes all combatants' actions.
7. **Hero ability omissions:** Rogue's enchanted critical sequence includes its
   advertised extra critical multiplier; Ranger's Volley refunds Focus for actual
   knockouts, capped at the normal Focus maximum.
8. **Interrupted rolls:** pending Focus payments now refund only their matching
   unfinished battle's Focus. They no longer turn into permanent Fate, nor credit
   an unrelated replacement match. Waiting while Focus is capped no longer banks
   regeneration ticks for an immediate refill after spending.
9. **Input validation:** zero/string/fractional multipliers, non-boolean ALL-IN
   flags, non-object request bodies and invalid actions are rejected before
   spending resources. Existing action-ID replay protection is retained.
10. **Lost network replies:** the client retries a committed action with its
    original action ID, not a fresh roll. Expired/missing rooms and cancellation
    races return to a usable state rather than leaving the live-menu lock set.
11. **Unclaimed rewards:** earned receipts remain discoverable after their room
    expires. Completed result summaries are cached rather than recalculated from
    mutable runtime heroes. Guild milestone grants also remain pending until
    acknowledged, so a lost milestone response can be recovered once.
12. **Progression credit:** verified online contributions update the appropriate
    lifetime statistics and same-day daily quests once. A gift daily requires an
    actual send, not just rolling a gift. Old-season claims retain currency but
    cannot move old points into the new season or complete today's dailies.

### Menus, training, raids and purchases

13. Invalid optional adventure, daily, tier, gift and Season Pass metadata is
    normalized without wiping valid progression or blocking menu rendering.
14. Guided training can be saved/exited during a throw. The real exit button is
    enabled; delayed throws are scoped to the match/player/raid that created them.
15. Leaving a raid invalidates its delayed dice and bot attacks. Stored raid
    attacks now credit the player and their damage quest rather than the boss
    object. Already-finished attempts cannot consume another stored attack.
16. Raid screens no longer show the arena-only two-spell controls, which had no
    working cast path in that mode. Existing raid ultimates remain available.
17. A delayed guild connection or action cannot reopen a dismissed guild modal.
    Guild reward delivery uses the durable claim path, never the temporary
    equalized battle hero.
18. **Shop traps:** temporary combat consumables purchased at Home were discarded
    when a new match was constructed. Those sales are paused instead of charging
    for a lost benefit. The audit also found no active Fate-spending call in the
    current game. Gold-to-Fate and Fate-cap relic sales are paused; balances,
    previously owned relics and pass rewards are preserved. The Shop explains why.
    A clearly labelled temporary training purchase still teaches the transaction
    flow without consuming real resources. No speculative new currency exchange
    was introduced simply to make the economy appear complete.
19. Forge/relic transactions now roll back resource costs and hero changes when
    persistence fails. Invalid/stale purchase controls are guarded. Forge copy
    no longer falsely says Epic/Legendary require all nine base weapons; the
    displayed costs are the actual requirements.

### Server and host

20. Token lookup uses a hash index instead of scanning all accounts per poll.
    Result caching reduces redundant reward/stat calculations. Persistent receipt
    and cleanup writes remain explicit.
21. **Internal file exposure:** the legacy Python web host served its entire
    working directory, including save listings, server source and logs. It now
    uses explicit public routes only, including matching GET/HEAD rules; private
    and traversal/encoded paths return 404. The live protection was verified with
    status-only requests, without downloading private contents.
22. Web-save writes validate body shape, length and stored JSON, serialize writes,
    use private unique temporary files and atomic replacement, and retain existing
    valid save representations. Concurrent same-device writes no longer collide
    on one shared `.tmp` path. Origins are restricted to the allowed alpha host
    and local-file origin; HTML reads are cached and invalidated on file change.

## Deliberate balance choices

| Mechanic | Before | Audited behavior |
| --- | --- | --- |
| Opening ALL-IN triple gift at 30 attack | 24,000 damage | 3,000 before bank cap; each bank capped at 2× its owner's max HP |
| Barrage at 30 attack, no defense/phase bonus | 90 | 225; no roll, Focus or capture-charge refund |
| Neutral/spell capture reward | +1 Focus and +1 charge | None; a paid contested capture is required |
| Repeated capture bonus | No per-tower cooldown | 30 seconds per player/tower |
| Rampage | Free elevated multipliers possible | Free ×1 rolls with double attacks |
| Bot substitute reward credit | Could continue growing | Only active human contributions count |

The queue still waits 20 seconds and creates 20 total combatants, 10 per side.
The 5-minute timer, overtime, supply-objective timing, ordinary Focus cap,
spell pool, season tiers and Premium price are unchanged. Forge prices and
reward tier quantities were not inflated without player data. Normal ALL-IN
still reaches ×16 at eight Focus; it is not intended to dominate steady rolling.

### Simulation evidence and limits

`../audit/balance-sim.js` runs **730 complete matches**: 400 before/after policy
runs, 180 two-spell-loadout runs and 150 hero runs. Each uses two scripted human
controllers plus 18 ordinary bots, matched seed sets, alternating primary side,
and 500 ms simulation steps. The original v109 engine is a hash-verifiable,
test-only fixture. Results are in `../audit/balance-simulation.json`.

In the audited policy runs, steady ×1 averaged about 82 rolls and 5,846 objective
damage; waiting for ALL-IN averaged about seven rolls and 2,904 damage. This
supports retaining ALL-IN as a situational burst rather than rewarding constant
ALL-IN spam. These are outputs of the specified controllers, **not measured
human win rates or proof of perfect balance**. Loadout/hero samples are too small
and policy-dependent to justify broad hero nerfs. Production tuning should use
real match completion, spell use, objective contribution and reward telemetry.

The remaining Fate-design gap is explicit: its balance is preserved, but this
build still needs an intentionally designed permanent use. The audit prevents
paying gold/tokens for that unused capacity rather than silently resetting Fate
or inventing an untested exchange rate.

## Verification

Final automated counts and source hashes are in `../audit/TEST_SUMMARY.json`.
Raw evidence:

- `../audit/server-tests.txt`: original backend suite plus added audit regressions.
- `../audit/web-tests.txt`: private-file denial, save validation, compatibility,
  concurrent writes, allowed origins, HEAD and HTML-cache invalidation.
- `../audit/full-browser-tests.json`: the full-game menu/raid/pass/preparation/
  online/offline/training/result/second-match regression flow at six viewports.
- `../audit/browser-audit.json`: interruption, malformed-save, receipt, shop,
  rollback and network-race regressions; failed replies are deliberately induced.
- `../audit/integrity.json`: full HTML hash/size, 20 parsed inline scripts,
  readable-module hashes and all 103 large embedded payloads unchanged.

Browser tests use the actual full HTML in desktop Chromium with mobile touch
emulation, isolated saves and a real loopback arena. Selected failure/receipt
cases are explicit fixtures; queue/match deadlines and resources are advanced
only through the separate test harness. These controls are **not deployed**.
No physical-phone, Google-login, cross-device account recovery, internet-load or
complete production penetration test is claimed.

## Compatibility, rollout and remaining limits

No new save migration/reset. Save key `fatebound-save`, solo battle-session
compatibility 106, arena protocol/store schema 1 and all art remain intact.
New arena rooms stamp balance 110; persisted 109 rooms retain their old combat
formulas so a restart does not change a match halfway through. Deploy the paired
client/engine/server only after verification and back up the private arena data.

Online identities remain device-local guests. The legacy cloud-save API remains
code-based, not Google-bound authenticated account recovery; origin restrictions
are not a substitute for identity authorization. The single-process JSON store
and existing user-level startup/watchdog arrangement are alpha infrastructure,
not a distributed high-availability service. No signing keys, Android packaging,
Legionary files/service or Google Play release are changed by this audit.

### Test-runner correction

One intermediate full-browser run ended with Chromium `Page crashed` during a
reload fixture. The harness retained old browser contexts and logged exceptions
without a nonzero exit. It now disposes of those contexts and fails the process
when any check fails. The final report is accepted only when every check passes
on the exact source checksum; a zero process exit alone is not counted as proof.
No gameplay changes were made to hide that intermediate test failure.
