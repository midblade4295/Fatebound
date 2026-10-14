#!/usr/bin/env python3
"""Fatebound usage statistics from the Siege server's own logs (0.31.118, ANALYTICS_SPEC_FOR_CLAUDE.md section 6).

Python 3 standard library only. Run it on the server, where the files are (the state directory is root-only):

  sudo python3 godot/tools/analytics_report.py --dir /var/lib/private/fatebound-siege
      [--days 30] [--json out.json] [--tz America/Los_Angeles] [--exclude-file test_accounts.txt] [--now 2026-10-12T18:00:00Z]

Reads <dir>/analytics/YYYY-MM-DD.jsonl and .jsonl.gz (one event a line, written by server/analytics.gd) and
<dir>/accounts/*.meta.json (an account's "created" time). The first lines are always the headline:
  1. total unique players: every account file plus every account seen in the statistics (and how many have done anything)
  2. daily active players: accounts with at least one event that day, the last --days days, today first, by UTC day and
     by day in --tz, as a table and as a JSON array
then: WAU/MAU, new players a day, D1/D7/D30 retention, the tutorial funnel, match completion and length (online/bots),
win rate by class, session length, purchase conversion (test purchases left out), social use, update screens by build,
crash-free sessions, opt-outs, dropped events. --json writes the same numbers under the same keys.

Left out: the accounts listed in --exclude-file (one id a line, # comments) and every event from a build ending
"-probe" (the deploy's probe); an account seen only through those is not counted anywhere.

An event's time is its phone time ("ts") unless the server marked the phone's clock as wrong ("ts_bad") -- then the time
it arrived ("rt") -- and never later than it arrived.
"""
import argparse
import datetime as dt
import glob
import gzip
import json
import os
import statistics
import sys

UTC = dt.timezone.utc
SESSION_CAP_S = 4 * 3600            # a session longer than 4 h counts as 4 h
RETENTION_DAYS = (1, 7, 30)


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="Fatebound usage statistics (self-hosted, from the Siege server's files)")
    ap.add_argument("--dir", required=True, help="the server's state directory (holds analytics/ and accounts/)")
    ap.add_argument("--days", type=int, default=30, help="days of history (default 30)")
    ap.add_argument("--json", help="also write the numbers as JSON to this file ('-' for stdout)")
    ap.add_argument("--tz", default="America/Los_Angeles", help="second time zone for daily actives (default America/Los_Angeles)")
    ap.add_argument("--exclude-file", help="account ids to leave out, one a line")
    ap.add_argument("--now", help="report as of this time (ISO 8601 or unix seconds; tests)")
    return ap.parse_args(argv)


def load_tz(name):
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo(name), name
    except Exception:  # (no tz database on this machine)
        return UTC, "UTC (%s not found)" % name


def parse_now(s):
    if not s:
        return dt.datetime.now(UTC)
    if s.replace(".", "", 1).isdigit():
        return dt.datetime.fromtimestamp(float(s), UTC)
    v = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    return v if v.tzinfo else v.replace(tzinfo=UTC)


def read_lines(path):
    opener = gzip.open if path.endswith(".gz") else open
    try:
        with opener(path, "rt", encoding="utf-8", errors="replace") as f:
            for ln in f:
                ln = ln.strip()
                if not ln:
                    continue
                try:
                    v = json.loads(ln)
                except ValueError:
                    continue
                if isinstance(v, dict):
                    yield v
    except (OSError, EOFError):
        return


def load(dirpath, exclude):
    """-> (events, accounts {id: created unix or None}, info)"""
    events = []
    files = sorted(glob.glob(os.path.join(dirpath, "analytics", "*.jsonl")) + glob.glob(os.path.join(dirpath, "analytics", "*.jsonl.gz")))
    probe_only = {}
    seen_ids = set()
    dupes = 0
    for path in files:
        for e in read_lines(path):
            acct = str(e.get("acct", ""))
            if not acct or acct in exclude:
                continue
            if str(e.get("b", "")).endswith("-probe"):
                probe_only.setdefault(acct, True)
                continue
            probe_only[acct] = False
            eid = str(e.get("id", ""))
            if eid:
                if eid in seen_ids:
                    dupes += 1
                    continue
                seen_ids.add(eid)
            try:
                rt = int(e.get("rt", 0))
                ts = int(e.get("ts", rt))
            except (TypeError, ValueError):
                continue
            t = rt if e.get("ts_bad") else min(ts, rt)
            p = e.get("p") if isinstance(e.get("p"), dict) else {}
            events.append({"acct": acct, "ev": str(e.get("ev", "")), "t": t, "src": str(e.get("src", "")), "p": p,
                           "b": str(e.get("b", "")), "sid": str(e.get("sid", "")), "ts_bad": bool(e.get("ts_bad", False))})
    events.sort(key=lambda e: e["t"])
    accounts = {}
    for path in glob.glob(os.path.join(dirpath, "accounts", "*.meta.json")):
        acct = os.path.basename(path)[: -len(".meta.json")]
        if acct in exclude or probe_only.get(acct, False):
            continue
        created = None
        try:
            with open(path, encoding="utf-8") as f:
                m = json.load(f)
            if isinstance(m, dict) and m.get("created") is not None:
                created = int(m["created"])
        except (OSError, ValueError, TypeError):
            pass
        accounts[acct] = created
    info = {"files": len(files), "duplicates_skipped": dupes,
            "probe_only_accounts": sum(1 for v in probe_only.values() if v)}
    return events, accounts, info


def day_utc(t):
    return dt.datetime.fromtimestamp(t, UTC).date()


def pct(a, b):
    return round(100.0 * a / b, 1) if b else None


def build(events, accounts, now, days, tz, tz_name, info):
    today = now.astimezone(UTC).date()
    today_tz = now.astimezone(tz).date()
    period = [today - dt.timedelta(days=i) for i in range(days)]          # today first
    period_set = set(period)
    p_start = period[-1]

    active_utc = {}          # day -> set(acct)
    active_tz = {}
    first_event = {}
    plat_day = {}            # (day, acct) -> "android" | "ios" | ... (0.31.132: session_start's "plat"; none = Android)
    for e in events:
        d = day_utc(e["t"])
        active_utc.setdefault(d, set()).add(e["acct"])
        if e["ev"] == "session_start" and e["p"].get("plat"):
            plat_day[(d, e["acct"])] = str(e["p"]["plat"])
        active_tz.setdefault(dt.datetime.fromtimestamp(e["t"], tz).date(), set()).add(e["acct"])
        first_event.setdefault(e["acct"], e["t"])

    everyone = set(accounts) | set(first_event)
    out = {
        "generated": now.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "days": days,
        "tz": tz_name,
        "data_from": day_utc(events[0]["t"]).isoformat() if events else None,
        "data_to": day_utc(events[-1]["t"]).isoformat() if events else None,
        "total_unique_players": len(everyone),
        "active_ever": len(first_event),
        "accounts_files": len(accounts),
        "seen_only_in_analytics": len(set(first_event) - set(accounts)),
    }
    out["dau"] = [{"day": d.isoformat(), "players": len(active_utc.get(d, ()))} for d in period]
    out["dau_plat"] = []     # 0.31.132 (the iOS port): players a day by phone
    for d in period:
        n = {}
        for a in active_utc.get(d, ()):
            k = plat_day.get((d, a), "android")
            n[k] = n.get(k, 0) + 1
        out["dau_plat"].append({"day": d.isoformat(), "android": n.pop("android", 0), "ios": n.pop("ios", 0),
                                "other": sum(n.values())})
    out["dau_tz"] = [{"day": d.isoformat(), "players": len(active_tz.get(d, ()))}
                     for d in [today_tz - dt.timedelta(days=i) for i in range(days)]]

    def active_between(d0, d1):
        s = set()
        for d, a in active_utc.items():
            if d0 <= d <= d1:
                s |= a
        return s

    period_active = active_between(p_start, today)
    out["wau"] = len(active_between(today - dt.timedelta(days=6), today))
    out["mau"] = len(active_between(today - dt.timedelta(days=29), today))
    out["dau_today"] = out["dau"][0]["players"]
    out["dau_avg"] = round(sum(r["players"] for r in out["dau"]) / days, 2) if days else 0
    out["stickiness_pct"] = pct(out["dau_avg"], out["mau"])
    out["active_in_period"] = len(period_active)

    # ---- new players (first seen: the account's created time, else its first event)
    first_seen = {}
    for a in everyone:
        c = accounts.get(a)
        f = first_event.get(a)
        if c is not None or f is not None:
            first_seen[a] = day_utc(c) if c is not None else day_utc(f)
    new_by_day = {}
    for a, d in first_seen.items():
        new_by_day[d] = new_by_day.get(d, 0) + 1
    out["new_players"] = [{"day": d.isoformat(), "players": new_by_day.get(d, 0)} for d in period]
    out["new_players_total"] = sum(new_by_day.get(d, 0) for d in period)

    # ---- retention: cohorts by first-seen day, from the first day there are statistics; only whole days count
    out["retention"] = {}
    data_first = day_utc(events[0]["t"]) if events else None
    cohorts = {}
    for a, d in first_seen.items():
        if data_first is not None and d >= data_first:
            cohorts.setdefault(d, set()).add(a)
    for n in RETENTION_DAYS:
        size = kept = 0
        for d, members in cohorts.items():
            if d + dt.timedelta(days=n) < today:             # (day N is over)
                size += len(members)
                kept += len(members & active_utc.get(d + dt.timedelta(days=n), set()))
        out["retention"]["d%d" % n] = {"cohort": size, "returned": kept, "pct": pct(kept, size)}
    out["retention_cohorts"] = []
    for d in sorted(cohorts, reverse=True):
        if d not in period_set:
            continue
        row = {"day": d.isoformat(), "size": len(cohorts[d])}
        for n in RETENTION_DAYS:
            dn = d + dt.timedelta(days=n)
            row["d%d" % n] = pct(len(cohorts[d] & active_utc.get(dn, set())), len(cohorts[d])) if dn < today else None
        out["retention_cohorts"].append(row)

    # everything below: the period
    pe = [e for e in events if day_utc(e["t"]) in period_set]

    def accts(evname, cond=lambda e: True):
        return {e["acct"] for e in pe if e["ev"] == evname and cond(e)}

    # ---- tutorial funnel (players)
    t_start = accts("tutorial_start")
    steps = {}
    for e in pe:
        if e["ev"] == "tutorial_step":
            try:
                k = (int(e["p"].get("step", -1)), str(e["p"].get("id", "")))
            except (TypeError, ValueError):
                continue
            steps.setdefault(k, set()).add(e["acct"])
    t_done = accts("tutorial_complete")
    t_skip = accts("tutorial_skip")
    base = len(t_start)
    out["tutorial_funnel"] = {
        "start": base,
        "steps": [{"step": k[0], "id": k[1], "players": len(v), "pct": pct(len(v), base)} for k, v in sorted(steps.items())],
        "complete": len(t_done), "complete_pct": pct(len(t_done), base),
        "skip": len(t_skip), "skip_pct": pct(len(t_skip), base),
        "complete_dur_s_median": _median([e["p"].get("dur_s") for e in pe if e["ev"] == "tutorial_complete"]),
    }

    # ---- matches
    m = {}
    for mode in ("online", "bots"):
        fin = [e for e in pe if e["ev"] == "match_finish" and e["p"].get("mode") == mode]
        quit_ = [e for e in pe if e["ev"] == "match_quit" and e["p"].get("mode") == mode]
        start = [e for e in pe if e["ev"] == "match_start" and e["p"].get("mode") == mode]
        durs = [_num(e["p"].get("dur_s")) for e in fin]
        durs = [d for d in durs if d is not None]
        m[mode] = {"started": len(start), "finished": len(fin), "quit": len(quit_),
                   "completion_pct": pct(len(fin), len(fin) + len(quit_)),
                   "avg_len_s": round(sum(durs) / len(durs), 1) if durs else None,
                   "players": len({e["acct"] for e in start + fin + quit_})}
    joins = {}
    for e in pe:
        if e["ev"] == "match_join":
            k = str(e["p"].get("mode", "?"))
            joins[k] = joins.get(k, 0) + 1
    m["joins"] = joins
    by_class = {}
    for e in pe:
        if e["ev"] == "match_finish":
            c = str(e["p"].get("class") or e["p"].get("class0") or "?").rstrip("+")
            r = by_class.setdefault(c, {"class": c, "matches": 0, "wins": 0, "draws": 0})
            r["matches"] += 1
            if e["p"].get("result") == "win":
                r["wins"] += 1
            elif e["p"].get("result") == "draw":
                r["draws"] += 1
    for r in by_class.values():
        r["win_pct"] = pct(r["wins"], r["matches"])
    m["win_rate_by_class"] = sorted(by_class.values(), key=lambda r: (-r["matches"], r["class"]))
    out["matches"] = m

    # ---- sessions
    lens = [min(SESSION_CAP_S, max(0, _num(e["p"].get("dur_s")) or 0)) for e in pe if e["ev"] == "session_end"]
    out["session_length"] = {"sessions": len(lens),
                             "avg_s": round(sum(lens) / len(lens), 1) if lens else None,
                             "median_s": _median(lens),
                             "starts": sum(1 for e in pe if e["ev"] == "session_start"),
                             "online_starts": sum(1 for e in pe if e["ev"] == "session_start" and e["p"].get("net") == "online")}

    # ---- purchases (test purchases left out)
    def real_purchase(e):
        return e["ev"] == "purchase_verified" and not _truthy(e["p"].get("test"))
    pp = [e for e in pe if real_purchase(e)]
    pall = [e for e in events if real_purchase(e)]
    by_prod = {}
    for e in pp:
        k = str(e["p"].get("product", "?"))
        r = by_prod.setdefault(k, {"product": k, "purchases": 0, "payers": set()})
        r["purchases"] += 1
        r["payers"].add(e["acct"])
    payers = {e["acct"] for e in pp}
    payers_all = {e["acct"] for e in pall}
    out["purchases"] = {
        "purchases": len(pp), "payers": len(payers), "conversion_pct": pct(len(payers), len(period_active)),
        "payers_all_time": len(payers_all), "conversion_all_time_pct": pct(len(payers_all), len(first_event)),
        "test_purchases_left_out": sum(1 for e in pe if e["ev"] == "purchase_verified" and _truthy(e["p"].get("test"))),
        "by_product": [{"product": r["product"], "purchases": r["purchases"], "payers": len(r["payers"])}
                       for r in sorted(by_prod.values(), key=lambda r: (-r["purchases"], r["product"]))],
    }

    # ---- social: share of the day's active players who used it (averaged over days with players) and of the period
    groups = {"chat": ("chat_send",), "friends": ("friend_add", "friend_accept"),
              "party": ("party_create", "party_join", "party_invite"), "quick_chat": ("quick_chat",)}
    soc = {}
    for g, evs in groups.items():
        per_day = {}
        for e in pe:
            if e["ev"] in evs:
                per_day.setdefault(day_utc(e["t"]), set()).add(e["acct"])
        shares = [len(per_day.get(d, set()) & active_utc[d]) / len(active_utc[d]) for d in period if active_utc.get(d)]
        users = set().union(*per_day.values()) if per_day else set()
        soc[g] = {"events": sum(1 for e in pe if e["ev"] in evs), "players": len(users),
                  "pct_of_active": pct(len(users), len(period_active)),
                  "avg_daily_pct_of_dau": round(100.0 * sum(shares) / len(shares), 1) if shares else None}
    chat_kinds = {}
    for e in pe:
        if e["ev"] == "chat_send":
            k = str(e["p"].get("kind", "?"))
            chat_kinds[k] = chat_kinds.get(k, 0) + 1
    soc["chat"]["by_kind"] = chat_kinds
    out["social"] = soc

    # ---- update screens
    ups = {}
    for e in pe:
        if e["ev"] == "update_screen":
            k = str(e["p"].get("from_build", "?"))
            r = ups.setdefault(k, {"from_build": k, "shown_on_phone": 0, "refused_by_server": 0, "players": set()})
            r["shown_on_phone" if e["src"] == "c" else "refused_by_server"] += 1
            r["players"].add(e["acct"])
    out["update_screen"] = [{"from_build": r["from_build"], "shown_on_phone": r["shown_on_phone"],
                             "refused_by_server": r["refused_by_server"], "players": len(r["players"])}
                            for r in sorted(ups.values(), key=lambda r: r["from_build"])]

    # ---- crash-free: sessions that said they ended / all ended (a "lost" one never did: a crash, a freeze, a kill)
    ended = [e for e in pe if e["ev"] == "session_end"]
    lost = [e for e in ended if _truthy(e["p"].get("lost"))]
    errors = {}
    for e in pe:
        if e["ev"] == "error":
            k = str(e["p"].get("kind", "?"))
            errors[k] = errors.get(k, 0) + 1
    out["crash_free"] = {"ended": len(ended), "lost": len(lost),
                         "crash_free_pct": pct(len(ended) - len(lost), len(ended)),
                         "clean_session_markers": sum(1 for e in pe if e["ev"] == "clean_session"),
                         "errors": errors}

    # ---- opt-outs, dropped events, levels, the rest
    out["opt_outs"] = {"period": len(accts("opt_out")),
                       "all_time": len({e["acct"] for e in events if e["ev"] == "opt_out"})}
    out["dropped_events"] = {"q_dropped_n": sum(int(_num(e["p"].get("n")) or 0) for e in pe if e["ev"] == "q_dropped"),
                             "phones_reporting": len(accts("q_dropped")),
                             "ts_bad": sum(1 for e in pe if e["ts_bad"])}
    counts = {}
    for e in pe:
        counts[e["ev"]] = counts.get(e["ev"], 0) + 1
    out["events_in_period"] = dict(sorted(counts.items()))
    out["level_ups"] = counts.get("level_up", 0)
    out["forges"] = counts.get("forge", 0)
    out["chests_opened"] = counts.get("chest_open", 0)
    shop = {}
    for e in pe:
        if e["ev"] == "shop_view":
            k = str(e["p"].get("tab", "?"))
            shop[k] = shop.get(k, 0) + 1
    out["shop_views"] = shop
    out["builds"] = _builds(pe)
    out["excluded"] = dict(info)
    return out


def _builds(pe):
    b = {}
    for e in pe:
        if e["src"] == "c" and e["b"]:
            b.setdefault(e["b"], set()).add(e["acct"])
    return [{"build": k, "players": len(v)} for k, v in sorted(b.items(), reverse=True)]


def _num(v):
    if isinstance(v, bool):
        return int(v)
    if isinstance(v, (int, float)):
        return v
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _truthy(v):
    return v is True or v == 1 or str(v).lower() == "true"


def _median(vals):
    v = [x for x in (_num(a) for a in vals) if x is not None]
    return round(statistics.median(v), 1) if v else None


def _fmt(v, suffix=""):
    return "-" if v is None else "%s%s" % (v, suffix)


def _dur(s):
    if s is None:
        return "-"
    s = int(round(s))
    return "%dm %02ds" % (s // 60, s % 60) if s >= 60 else "%ds" % s


def text(r):
    L = []
    L.append("TOTAL UNIQUE PLAYERS: %d   (active ever: %d; account files %d, seen only in the statistics %d)"
             % (r["total_unique_players"], r["active_ever"], r["accounts_files"], r["seen_only_in_analytics"]))
    L.append("DAILY ACTIVE PLAYERS, last %d days, today first  (UTC days | %s days)" % (r["days"], r["tz"]))
    for a, b in zip(r["dau"], r["dau_tz"]):
        L.append("  %s  %5d   |  %s  %5d" % (a["day"], a["players"], b["day"], b["players"]))
    L.append("  DAU JSON (UTC, today first): " + json.dumps([x["players"] for x in r["dau"]]))
    if r.get("dau_plat"):
        L.append("  DAU by phone (UTC, today first): android %s  ios %s" % (json.dumps([x["android"] for x in r["dau_plat"]]),
                                                                     json.dumps([x["ios"] for x in r["dau_plat"]])))
    L.append("  DAU JSON (%s, today first): %s" % (r["tz"], json.dumps([x["players"] for x in r["dau_tz"]])))
    L.append("")
    L.append("Generated %s; data %s .. %s; period: the last %d days (UTC)" % (r["generated"], r["data_from"] or "-", r["data_to"] or "-", r["days"]))
    L.append("Active: today %d | WAU %d | MAU %d | avg DAU %s | DAU/MAU %s | active in period %d"
             % (r["dau_today"], r["wau"], r["mau"], r["dau_avg"], _fmt(r["stickiness_pct"], "%"), r["active_in_period"]))
    L.append("New players in period: %d   by day (today first): %s" % (r["new_players_total"], json.dumps([x["players"] for x in r["new_players"]])))
    ret = r["retention"]
    L.append("Retention (back on day N; cohorts whose day N is over): " + "  ".join(
        "D%s %s (%d of %d)" % (k[1:], _fmt(v["pct"], "%"), v["returned"], v["cohort"]) for k, v in ret.items()))
    for c in r["retention_cohorts"][:14]:
        L.append("  cohort %s  %4d players   D1 %-6s D7 %-6s D30 %s" % (c["day"], c["size"], _fmt(c["d1"], "%"), _fmt(c["d7"], "%"), _fmt(c["d30"], "%")))
    tf = r["tutorial_funnel"]
    L.append("Tutorial funnel (players): start %d" % tf["start"])
    for s in tf["steps"]:
        L.append("  step %2d %-18s %5d  %s" % (s["step"], s["id"], s["players"], _fmt(s["pct"], "%")))
    L.append("  complete %d (%s), skip %d (%s), median time to complete %s"
             % (tf["complete"], _fmt(tf["complete_pct"], "%"), tf["skip"], _fmt(tf["skip_pct"], "%"), _dur(tf["complete_dur_s_median"])))
    m = r["matches"]
    for mode in ("online", "bots"):
        x = m[mode]
        L.append("Matches %-6s: started %d, finished %d, quit %d -> completion %s, avg length %s, players %d"
                 % (mode, x["started"], x["finished"], x["quit"], _fmt(x["completion_pct"], "%"), _dur(x["avg_len_s"]), x["players"]))
    L.append("  joins from the menu: %s" % json.dumps(m["joins"]))
    L.append("Win rate by class (the class they finished as):")
    for c in m["win_rate_by_class"]:
        L.append("  %-12s %5d matches  %s wins  (%d draws)" % (c["class"], c["matches"], _fmt(c["win_pct"], "%"), c["draws"]))
    s = r["session_length"]
    L.append("Sessions: %d ended, avg %s, median %s (capped at 4 h); %d starts, %d online"
             % (s["sessions"], _dur(s["avg_s"]), _dur(s["median_s"]), s["starts"], s["online_starts"]))
    p = r["purchases"]
    L.append("Purchases (verified, tests left out): %d by %d players -> conversion %s of active in period; all time %d payers (%s of active ever); %d test purchases left out"
             % (p["purchases"], p["payers"], _fmt(p["conversion_pct"], "%"), p["payers_all_time"], _fmt(p["conversion_all_time_pct"], "%"), p["test_purchases_left_out"]))
    for b in p["by_product"]:
        L.append("  %-16s %4d purchases  %4d payers" % (b["product"], b["purchases"], b["payers"]))
    so = r["social"]
    L.append("Social (players, % of active in period, avg daily % of DAU): " + "  ".join(
        "%s %d (%s, %s)" % (k, v["players"], _fmt(v["pct_of_active"], "%"), _fmt(v["avg_daily_pct_of_dau"], "%")) for k, v in so.items()))
    L.append("  chat lines by kind: %s" % json.dumps(so["chat"]["by_kind"]))
    L.append("Update screens by build:" + (" none" if not r["update_screen"] else ""))
    for u in r["update_screen"]:
        L.append("  from %-24s phone %4d  server %4d  players %d" % (u["from_build"], u["shown_on_phone"], u["refused_by_server"], u["players"]))
    cf = r["crash_free"]
    L.append("Crash-free sessions: %s (%d ended, %d never said they ended); clean-start markers %d; errors %s"
             % (_fmt(cf["crash_free_pct"], "%"), cf["ended"], cf["lost"], cf["clean_session_markers"], json.dumps(cf["errors"])))
    L.append("Opt-outs: %d in period, %d all time" % (r["opt_outs"]["period"], r["opt_outs"]["all_time"]))
    d = r["dropped_events"]
    L.append("Dropped on phones (queue full): %d events from %d phones; events with a wrong phone clock: %d" % (d["q_dropped_n"], d["phones_reporting"], d["ts_bad"]))
    L.append("Level-ups %d, forges %d, chests opened %d, shop views %s" % (r["level_ups"], r["forges"], r["chests_opened"], json.dumps(r["shop_views"])))
    L.append("Builds (players): " + ", ".join("%s %d" % (b["build"], b["players"]) for b in r["builds"][:8]))
    L.append("Events in period: " + json.dumps(r["events_in_period"]))
    ex = r["excluded"]
    L.append("Files read %d; duplicate ids skipped %d; probe-only accounts left out %d; excluded accounts %d"
             % (ex["files"], ex["duplicates_skipped"], ex["probe_only_accounts"], ex.get("exclude_list", 0)))
    return "\n".join(L)


def main(argv=None):
    a = parse_args(argv)
    if not os.path.isdir(a.dir):
        print("No such directory: %s" % a.dir, file=sys.stderr)
        return 2
    exclude = set()
    if a.exclude_file:
        with open(a.exclude_file, encoding="utf-8") as f:
            for ln in f:
                ln = ln.split("#", 1)[0].strip()
                if ln:
                    exclude.add(ln)
    tz, tz_name = load_tz(a.tz)
    now = parse_now(a.now)
    events, accounts, info = load(a.dir, exclude)
    info["exclude_list"] = len(exclude)
    r = build(events, accounts, now, max(1, a.days), tz, tz_name, info)
    print(text(r))
    if a.json:
        js = json.dumps(r, indent=1, sort_keys=False)
        if a.json == "-":
            print(js)
        else:
            with open(a.json, "w", encoding="utf-8") as f:
                f.write(js + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
