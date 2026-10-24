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
| Phone: HeyCatch (0.31.212, below) | `scripts/meta/heycatch.gd` (a child of SiegeApp; Analytics.hc) |
| Phone hooks | `scripts/app/siege_app.gd` (sessions, match_join, shop_view, update_screen, level_up), `siege/siege_mode.gd` (VS BOTS matches, tutorial start/complete/skip), `siege/tutorial.gd` (steps), `app/screens.gd` (forge, the Settings toggle), `app/chest_open.gd` |
| Server: checks, files, rotation | `server/analytics.gd` |
| Server hooks | `server/siege_server.gd` (`an` socket, session_online, online match_start/finish/quit, match_shop_buy, quick_chat, purchase_verified, update_screen on a min_build refusal), `server/social.gd` (chat_send, friend_add/accept, party_create/invite/join), `server/eco_accounts.gd` (spend: gold and gems spent, below) |

## HeyCatch (0.31.212, the phone)

Kevin: "Set up HeyCatch analytics in this project following https://heycatch.ai/agents.md exactly" (project key
`hck_pk_C3_tEJ-...`, the dashboard's). agents.md is for web and React Native; a native app goes to its
`/agents-native.md` (Kevin pasted it): HeyCatch's ingest speaks PostHog's protocol, Swift / Kotlin / Flutter put
PostHog's SDK on it. A Godot game has none of those SDKs, so `scripts/meta/heycatch.gd` takes that guide's plain-HTTP
route: `POST https://in.heycatch.ai/batch/`, the standard PostHog capture format, HeyCatch's write-only ingest token
(`phc_oiDt...`, the same for every app: not a secret) as `api_key`, and on every event's properties the project key
as `heycatch_project_key` and as `$groups.project` (without them an event "belongs to no project").
- What goes: every event the phone logs for our own server (Analytics.log_ev hands it over with its allowed props),
  `$screen` (`$screen_name`: the tab -- home, shop, pass, locker, alliance, settings, quests -- or match_online,
  match_bots, tutorial), `purchase_completed` (`product`) when a purchase is granted, one `$identify` when the phone
  first has an account. Props: also `$lib` fatebound-godot, `$app_version` (the build), `$os`.
- distinct_id: never the account id (half of how the account signs in): `fb_` + 20 hex of SHA-256("fatebound-heycatch:"
  + id); before the account exists a random `anon_` id, joined to it by the `$identify` (`$anon_distinct_id`). Kept in
  `<profile>.heycatch.json`. No name, chat text, email, device or ad id.
- When: Settings > "Share anonymous usage stats" on (off: what's waiting goes, nothing more -- not even opt_out); on a
  phone only (Android, iOS -- the real OS, not a test's Platform.forced); a desktop run only with `HEYCATCH=1`
  (`HEYCATCH=0`: never). In memory, every 10 s or 50 events and at once when the app goes to the background; an event
  over an hour old is dropped (the guide: long-held events can be dropped). 2xx accepted; 4xx (not 408/429) dropped;
  no answer / 5xx: again after 5, 15, 30, 60, 120 s.
- `tests/heycatch_test.gd` (a stand-in ingest on 8141); `tools/heycatch_verify.gd` runs the real app against the real
  ingest (`HEYCATCH=1`, through `HTTPS_PROXY` with `HEYCATCH_CA` when the machine has one) and prints what it answered.
- Kevin's to do: the privacy policy and Play's Data safety form (and App Store privacy) -- usage events now also go to
  HeyCatch, a third party; then press "I've installed" on the dashboard's Install page.

## Leaving an online match, and its shop (0.31.212, server)

`NEW_PLAYER_RETENTION_HANDOFF.md` (Codex, from 0.31.211's logs: new players, the only human against 9 bots, quit their
first matches, and "We could not tell whether these players were losing"; "whether new players actually buy upgrades
from the match shop"). Server only -- the app is unchanged (VS BOTS matches, the phone's, log match_quit as before).
- `match_quit` (src `s`, mode `online`) -- the match as the player left it, taken at the drop: `quit_at_s` (their time
  in it), `class`, `class0` as before; `why` the drop's reason (`left` quit on purpose -- the app's close; `closed`,
  `silent`, `handshake timeout` the connection went; `idle` removed for idling); `held` their seat waited for them and
  they never came back -- written when it was let go (the wait ran out, or the match ended: then no `match_finish` for
  them, though they're still paid; a match a player didn't see the end of is a quit); `rejoins` times they came back to
  the seat; `match_s` the match's clock; `hero`, `team` (0 blue, 1 red), `lvl`; from their side `score_us`/`score_them`
  (Kings toppled), `kills_us`/`kills_them` (the teams'), `k`/`d`/`a` (theirs), `king_us_pct`/`king_them_pct` (each
  King's HP, %); their shop totals `items`, `gold_spent`, `gold_left`. Written at once for a leave, so a match that then
  ends with nobody in it (it stops; nothing more is logged for it) still has it.
- `match_shop_buy` -- each upgrade a player bought with the match's gold (a refused buy, a bot's buy -- the seat's
  before them, or while they're idle or away -- is none): `match`, `mode`, `item`, `cost` (with the components they
  owned taken off), `match_s`, `hero`, `gold_left`.
- `match_finish` adds the player's `items`, `gold_spent`, `gold_left`.
- The server log: each `leave` line (and a held seat's `let go`) ends with the same (`at 312 s (300 s in), golem L5
  blue, K/D/A 1/4/2, kills 8-15, score 0-0, Kings 64% vs 100%, shop 2 bought (750 gold), 120 gold left`); a `shop`
  line per buy; `paid` lines carry the shop totals; `match ... end` and `stopped (no players)` lines how the match stood.
- `tools/analytics_report.py`: "Online quits as they left them" (why, held, when, kills behind/even/ahead, K/D/A, Kings,
  bought nothing) and "Match shop" (buys, players, gold, matches with a buy finished / quit, first buy, by item).
- MAX_PROPS 12 -> 32 (still only the listed keys).

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
port 8100, the probe included; 0.31.212: match_quit's new props for a quit and a held seat whose match ends with nobody
in it, match_shop_buy for each buy and none for a refused one, the totals on match_finish), `tools/test_analytics_report.py`. All in `tools/run_siege_tests.sh`.
