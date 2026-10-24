# New-player retention handoff: leave telemetry

## Findings (Oct 24, 2026, 6:10–7:12 AM PT, server logs on 0.31.211)

- Two new players, Alexriver and SayHiPls, quit all 4 of their first online matches.
- In each match they were the only human, against 9 bots.
- Quits came at 5 min, 15 min, 2.4 min, and ~11–12 min. Three were deliberate leaves
  (close reason `leave`). The fourth was the app being backgrounded: the rejoin worked,
  then the player closed the app 20 s later.
- No errors; late join never triggered.
- Alexriver had skipped the tutorial at the shop step.
- Score, kills, and King HP were **not** logged, because matches that end with no
  players log nothing. We could not tell whether these players were losing.

## Task: leave telemetry

When a human leaves or their seat is released (any close reason, including
`leave`, disconnect timeout, and backgrounded-then-closed), log a server line and
record a usage event containing:

- match time (elapsed seconds)
- both team scores / kills
- the player's kills, deaths, assists
- both Kings' HP
- the player's hero

Add these fields to the existing `match_quit` usage event (keep existing fields
backward compatible). Make sure it is emitted even when the match then ends with
no humans left. Add a test covering the new fields.

## Constraints

- Run `python3 godot/tools/content_packs.py check`; it must print `CONTENT OK` before any build.
- Server deploys need Kevin's approval.
- Never commit `override.cfg` or any key / service-account JSON. Never force-push.
