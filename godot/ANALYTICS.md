# Fatebound usage statistics (self-hosted, 0.31.118)

What Firebase Analytics would do, with no SDK and no third party: the phone sends its usage events to our own Siege
server, which keeps them in its state directory for 90 days. Spec: `ANALYTICS_SPEC_FOR_CLAUDE.md` (Kevin, Oct 2026).

## Reading the numbers

On the server (the state directory is root-only):

    sudo python3 godot/tools/analytics_report.py --dir /var/lib/private/fatebound-siege
    sudo python3 godot/tools/analytics_report.py --dir /var/lib/private/fatebound-siege --days 30 --json /tmp/fatebound-stats.json \
        --tz America/Los_Angeles --exclude-file ~/fatebound-test-accounts.txt

The first lines are always **total unique players** (every account file plus every account seen in the statistics)
and **daily active players** for the last 30 days, today first, by UTC day and by Pacific day, as a table and as a JSON
array. Then: WAU/MAU, new players a day, D1/D7/D30 retention, the tutorial funnel, match completion and length
(online / bots), win rate by class, session length, purchase conversion (test purchases left out), social use, update
screens by build, crash-free sessions, opt-outs and events dropped on phones. `--json` writes the same numbers.

Left out: accounts in `--exclude-file` (one id a line, `#` comments; put your own test phones there) and anything sent
by a build ending `-probe` (the deploy probe).

Python 3 standard library only. Test: `python3 godot/tools/test_analytics_report.py` (in `run_siege_tests.sh`).

## Where things are

| Part | File |
|---|---|
| The events and the props each may carry (the allow-list, shared) | `scripts/meta/analytics_events.gd` |
| Phone: queue, sessions, sending, opt-out | `scripts/meta/analytics.gd` (a child of SiegeApp) |
| Phone hooks | `scripts/app/siege_app.gd` (sessions, match_join, shop_view, update_screen, level_up), `siege/siege_mode.gd` (VS BOTS matches, tutorial start/complete/skip), `siege/tutorial.gd` (steps), `app/screens.gd` (forge, the Settings toggle), `app/chest_open.gd` |
| Server: checks, files, rotation | `server/analytics.gd` |
| Server hooks | `server/siege_server.gd` (`an` socket, session_online, online match_start/finish/quit, quick_chat, purchase_verified, update_screen on a min_build refusal), `server/social.gd` (chat_send, friend_add/accept, party_create/invite/join), `server/eco_accounts.gd` (spend: gold and gems spent, below) |

## Gold and gem spending (0.31.208, server)

Kevin: "Gold and gem spending: buying heroes, outfits or the pass with in-game currency to have tracking system for
server". Every op the server replays for an account (`server/eco_accounts.gd` handle) that takes gold or gems -- and the
gold the server takes itself for a clan (`pay_gold`) -- is a `spend` event (src `s`, the ops' app build), props from
`spend_props`: `cat` hero | outfit | pass | chest | clan | other; `item` the hero / outfit id, `premium` / `tiers`, the
chest's kind, `clan`; `op` (buy_hero, buy_hero_gems, use_shard, buy_skin, buy_skin_gold, buy_sale, buy_premium,
skip_tiers, skip_chest, pay_gold); `gold`, `gems` what it cost (what the balances moved -- the server's replay, not the
phone's word); `gold_left`, `gems_left`; `lvl`; and as it applies `hero` (an outfit that brought its locked hero),
`off` (a sale's % off), `n` (tiers skipped), `season`. A buy that fails, an op sent again, gold coming in (a melted
shard, a reward): no spend. An account with the statistics off: none (as every server event).
`tools/analytics_report.py` adds them up: buys, players and their share of the period's actives, gold and gems; by kind;
by item (paid in gold / in gems, on sale, brought the hero); the pass (premium, tier skips, tiers); by day; the median
left after a buy and the buyers' level. No account id in the report; a player's own lines are in the day files
(`"ev":"spend"`, their account id) for support.

## Protocol (stays 35)

- `ver` and `status` answer `"an":1`. The phone sends only after one of them said so; an older app never sends.
- A socket whose first message is `{"t":"an","v":35,"build","acct","key","ev":[...]}` (compressed, like `eco`) hands
  over up to 100 events. The server answers `{"t":"an","ok":[ids],"kept":n}` and closes. A key that doesn't open the
  account: close 4005 `"an"`, nothing written. An older server ignores `an`; the phone keeps its queue and tries again.
- The match hello and the social `hi` carry `"an_off":1` when the player turned the statistics off; the server then writes
  nothing for that account (it remembers in `analytics/opt_out.json` until the phone sends events again).

## On the server

- `$STATE_DIRECTORY/analytics/YYYY-MM-DD.jsonl` (UTC day the line arrived), one JSON line an event:
  `{"rt","acct","ev","ts","sid","b","p","src":"c"|"s","id"}` (+ `"ts_bad":true` when the phone clock was off by more than
  30 days back / 1 day ahead; ts is then clamped). Folder 0700, files 0600, flushed every second.
- At start and every hour: files older than 2 days are gzipped (`.jsonl.gz`), files older than 90 days deleted.
- Limits: 100 events a batch, 2,000 an account a day. Ids seen today or yesterday are written once (rebuilt from the
  files at start), so a phone sending a batch twice is harmless.
- Never written: IP addresses, device or advertising ids, names, chat text, purchase tokens, order ids, keys.
  Out of scope: Caddy's own access logs for `/fatebound/siege` (they can hold IP addresses; that is Caddy's config, not
  this server's).
- Deploy: `install_siege_server.sh` copies `server/analytics.gd` and `scripts/meta/analytics_events.gd`; the accounts
  backup tar before each update also takes the last 7 days of `analytics/` and `opt_out.json`. The probe sends `an`
  (with `SIEGE_PROBE_ACCT`/`SIEGE_PROBE_KEY`: a real batch, build `-probe`; without: a made-up key must be refused).

## On the phone

- Queue `<profile>.analytics_q.jsonl` (normally `user://siege_profile.analytics_q.jsonl`), at most 500 events / 256 KB;
  when full the oldest go and their count is sent as `q_dropped`.
- Settings > PRIVACY > "Share anonymous usage stats" (`settings.analytics`, on by default). Off: the queue is cleared,
  one `opt_out` event goes up (no props), nothing more is logged.
- A session is one time in the foreground. Crash-free sessions = session_end that weren't `lost` / all session_end.
  Script errors go up as a count (`error`, kind `script_error`, n) with the session's end; a stuck start as
  `error` kind `boot_stuck`.

## Tests

`tests/spend_tracking_test.gd` (0.31.208, server: every kind of spend, the ones that aren't, opt-out, the real server
on 8133), `tests/analytics_client_test.gd`, `tests/analytics_server_test.gd`, `tests/analytics_events_test.gd` (real server on
port 8100, the probe included), `tools/test_analytics_report.py`. All in `tools/run_siege_tests.sh`.
