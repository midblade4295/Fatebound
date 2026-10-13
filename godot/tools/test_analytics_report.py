#!/usr/bin/env python3
"""Fixture test for tools/analytics_report.py (0.31.118). Python 3 standard library only.

Builds a state directory by hand (day files plain and gzipped, account files, a probe account, an excluded account, a
duplicate line) whose numbers are known, runs the report as of 2026-10-12 18:00 UTC and checks: the headline comes
first, total unique and active ever, daily actives by UTC day and by Pacific day, WAU/MAU, new players, D1/D7/D30,
the tutorial funnel, match completion and win rate by class, session length (4 h cap), purchase conversion without
test purchases, social use, update screens, crash-free, opt-outs, dropped events; the text and the JSON agree; no
account id appears anywhere in the report; and the fixture has no IP, token, order, name or chat text field.
Prints ANALYTICS_REPORT_PASS.
  python3 godot/tools/test_analytics_report.py
"""
import datetime as dt
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPORT = os.path.join(HERE, "analytics_report.py")
UTC = dt.timezone.utc

A = "a" * 20
B = "b" * 20
C = "c" * 20
D = "d" * 20
P = "e" * 20          # the probe's account
X = "f" * 20          # a test account (excluded)

fails = []
_n = [0]


def check(ok, what):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok:
        fails.append(what)


def ts(s):
    return int(dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp())


def ev(acct, name, when, p=None, src="c", b="0.31.118", rt=None, eid=None, **extra):
    _n[0] += 1
    t = ts(when)
    line = {"rt": rt if rt is not None else t + 5, "acct": acct, "ev": name, "ts": t, "sid": "0000000%d" % (_n[0] % 10),
            "b": b, "p": p or {}, "src": src, "id": eid or ("%016x" % _n[0])}
    line.update(extra)
    if src == "s":
        line["ts"] = line["rt"] = t
        line["sid"] = ""
    return line


def main():
    d = tempfile.mkdtemp(prefix="an_report_")
    os.makedirs(os.path.join(d, "analytics"))
    os.makedirs(os.path.join(d, "accounts"))
    for acct, created in [(A, "2026-10-01T09:00:00Z"), (B, "2026-10-01T10:00:00Z"), (D, "2026-09-01T10:00:00Z"),
                          (P, "2026-10-12T10:00:00Z"), (X, "2026-10-03T10:00:00Z")]:
        with open(os.path.join(d, "accounts", acct + ".meta.json"), "w") as f:
            json.dump({"v": 1, "key": "0" * 64, "created": ts(created), "seq": 0, "tickets": [], "rev": 0}, f)
        with open(os.path.join(d, "accounts", acct + ".json"), "w") as f:     # (the profile: not an account file)
            f.write("{}")
    dup = ev(A, "session_start", "2026-10-12T17:00:00Z", {"cold": True, "safe_boot": False, "net": "online"})
    days = {
        "2026-10-01": [
            ev(A, "session_start", "2026-10-01T15:00:00Z", {"cold": True, "safe_boot": False, "net": "online"}),
            ev(A, "tutorial_start", "2026-10-01T15:01:00Z"),
            ev(A, "tutorial_step", "2026-10-01T15:01:10Z", {"step": 0, "id": "intro"}),
            ev(A, "tutorial_step", "2026-10-01T15:02:00Z", {"step": 1, "id": "move"}),
            ev(A, "tutorial_complete", "2026-10-01T15:05:00Z", {"dur_s": 240}),
            ev(A, "match_start", "2026-10-01T15:06:00Z", {"match": "x1", "mode": "bots", "class": "knight"}),
            ev(A, "match_finish", "2026-10-01T15:16:00Z", {"match": "x1", "mode": "bots", "dur_s": 600, "result": "win", "team_n": 1, "class": "knight", "class0": "knight"}),
            ev(A, "session_end", "2026-10-01T15:17:00Z", {"dur_s": 60}),
            ev(B, "session_start", "2026-10-01T12:00:00Z", {"cold": True, "safe_boot": False, "net": "offline"}),
            ev(B, "tutorial_start", "2026-10-01T12:00:10Z"),
            ev(B, "tutorial_step", "2026-10-01T12:00:20Z", {"step": 0, "id": "intro"}),
            ev(B, "tutorial_skip", "2026-10-01T12:01:00Z", {"dur_s": 50, "step": 0, "id": "intro"}),
            ev(B, "match_start", "2026-10-01T12:02:00Z", {"match": "y1", "mode": "bots", "class": "ranger"}),
            ev(B, "match_quit", "2026-10-01T12:03:00Z", {"match": "y1", "mode": "bots", "quit_at_s": 60, "class": "ranger", "class0": "ranger"}),
            ev(B, "purchase_verified", "2026-10-01T12:04:00Z", {"product": "gems_80", "test": True}, src="s"),
            ev(B, "session_end", "2026-10-01T12:05:00Z", {"dur_s": 120}),
            ev(B, "opt_out", "2026-10-01T12:06:00Z"),
        ],
        "2026-10-02": [
            ev(A, "session_online", "2026-10-02T03:00:00Z", src="s"),           # (Pacific: still Oct 1)
        ],
        "2026-10-05": [
            ev(C, "session_start", "2026-10-05T20:00:00Z", {"cold": True, "safe_boot": False, "net": "online"}),
            ev(C, "q_dropped", "2026-10-05T20:00:01Z", {"n": 5}),
        ],
        "2026-10-06": [
            ev(C, "chat_send", "2026-10-06T20:00:00Z", {"kind": "global"}, src="s"),
            ev(C, "match_finish", "2026-10-06T20:10:00Z", {"match": "1-2", "mode": "online", "dur_s": 300, "result": "win", "team_n": 2, "class": "mage", "class0": "worker"}, src="s"),
            ev(C, "session_end", "2026-10-06T20:20:00Z", {"dur_s": 20000, "lost": True}),
        ],
        "2026-10-08": [
            ev(A, "match_start", "2026-10-08T10:00:00Z", {"match": "1-3", "mode": "online", "class": "worker"}, src="s"),
            ev(A, "match_finish", "2026-10-08T10:08:00Z", {"match": "1-3", "mode": "online", "dur_s": 480, "result": "loss", "team_n": 3, "class": "mage+", "class0": "worker"}, src="s"),
            ev(A, "purchase_verified", "2026-10-08T10:09:00Z", {"product": "gems_80", "test": False}, src="s"),
            ev(A, "update_screen", "2026-10-08T09:00:00Z", {"from_build": "0.31.116", "need": "0.31.118"}),
            ev(A, "update_screen", "2026-10-08T09:01:00Z", {"from_build": "0.31.116", "need": "0.31.118"}, src="s"),
        ],
        "2026-10-12": [
            dup,
            ev(A, "friend_add", "2026-10-12T17:05:00Z", src="s"),
            ev(A, "error", "2026-10-12T17:06:00Z", {"kind": "boot_stuck"}),
            ev(P, "error", "2026-10-12T17:00:00Z", {"kind": "probe", "n": 0}, b="0.31.118-probe"),
            ev(X, "session_start", "2026-10-12T17:00:00Z", {"cold": True, "safe_boot": False, "net": "online"}),
            ev(X, "purchase_verified", "2026-10-12T17:01:00Z", {"product": "gems_6500", "test": False}, src="s"),
        ],
    }
    for day, lines in days.items():
        body = "".join(json.dumps(l) + "\n" for l in lines)
        if day == "2026-10-01":
            with gzip.open(os.path.join(d, "analytics", day + ".jsonl.gz"), "wt") as f:
                f.write(body)
        else:
            with open(os.path.join(d, "analytics", day + ".jsonl"), "w") as f:
                f.write(body)
    # the same event sent twice (once in another day's file), and a broken line
    with open(os.path.join(d, "analytics", "2026-10-11.jsonl"), "w") as f:
        f.write(json.dumps(dup) + "\n{not json\n")
    with open(os.path.join(d, "exclude.txt"), "w") as f:
        f.write("# test phones\n%s\n" % X)

    # --- the fixture itself: nothing a player could be found by
    raw = ""
    for fn in sorted(os.listdir(os.path.join(d, "analytics"))):
        path = os.path.join(d, "analytics", fn)
        raw += (gzip.open(path, "rt").read() if fn.endswith(".gz") else open(path).read())
    check(not re.search(r"\b\d{1,3}(\.\d{1,3}){3}\b", raw) and not re.search(r'"(ip|token|order|name|text|x|addr)"', raw),
          "fixture: no IP address, token, order id, name or chat text field")

    out_json = os.path.join(d, "out.json")
    cmd = [sys.executable, REPORT, "--dir", d, "--days", "30", "--json", out_json, "--tz", "America/Los_Angeles",
           "--exclude-file", os.path.join(d, "exclude.txt"), "--now", "2026-10-12T18:00:00Z"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    check(res.returncode == 0, "the report runs (exit %d) %s" % (res.returncode, res.stderr[-500:]))
    txt = res.stdout
    lines = txt.splitlines()
    with open(out_json) as f:
        r = json.load(f)                               # (--json validates)

    check(lines and lines[0].startswith("TOTAL UNIQUE PLAYERS: 4 "), "line 1 is the total: %s" % (lines[0] if lines else ""))
    check(len(lines) > 1 and lines[1].startswith("DAILY ACTIVE PLAYERS, last 30 days, today first"), "line 2 starts the daily actives")
    check(len(lines) > 2 and lines[2].split()[:2] == ["2026-10-12", "1"], "line 3 is today: %s" % (lines[2] if len(lines) > 2 else ""))
    check(r["total_unique_players"] == 4 and r["active_ever"] == 3 and r["seen_only_in_analytics"] == 1,
          "total unique 4 (3 account files + 1 seen only in the statistics; probe and excluded left out), active ever 3: %s" % r["total_unique_players"])
    dau = {x["day"]: x["players"] for x in r["dau"]}
    check(len(r["dau"]) == 30 and r["dau"][0]["day"] == "2026-10-12" and r["dau"][-1]["day"] == "2026-09-13", "30 days of DAU, today first")
    check(dau["2026-10-12"] == 1 and dau["2026-10-08"] == 1 and dau["2026-10-06"] == 1 and dau["2026-10-05"] == 1
          and dau["2026-10-02"] == 1 and dau["2026-10-01"] == 2 and dau["2026-10-11"] == 0 and sum(dau.values()) == 7,
          "DAU by UTC day (the copy that arrived in Oct 11's file counts once, on its own day): %s" % {k: v for k, v in dau.items() if v})
    dtz = {x["day"]: x["players"] for x in r["dau_tz"]}
    check(r["dau_tz"][0]["day"] == "2026-10-12" and dtz["2026-10-01"] == 2 and dtz.get("2026-10-02", 0) == 0,
          "DAU by Pacific day (03:00 UTC Oct 2 is still Oct 1 in LA): %s" % {k: v for k, v in dtz.items() if v})
    check(r["wau"] == 2 and r["mau"] == 3, "WAU 2, MAU 3: %d %d" % (r["wau"], r["mau"]))
    np_ = {x["day"]: x["players"] for x in r["new_players"]}
    check(np_["2026-10-01"] == 2 and np_["2026-10-05"] == 1 and r["new_players_total"] == 3,
          "new players: 2 on Oct 1 (account files), 1 on Oct 5 (first event); the September account is outside the 30 days")
    ret = r["retention"]
    check(ret["d1"] == {"cohort": 3, "returned": 2, "pct": 66.7}, "D1 2 of 3: %s" % ret["d1"])
    check(ret["d7"] == {"cohort": 2, "returned": 1, "pct": 50.0}, "D7 1 of 2 (the Oct 5 cohort's day 7 is today, not over): %s" % ret["d7"])
    check(ret["d30"]["cohort"] == 0 and ret["d30"]["pct"] is None, "D30: no cohort old enough")
    tf = r["tutorial_funnel"]
    st = {(s["step"], s["id"]): (s["players"], s["pct"]) for s in tf["steps"]}
    check(tf["start"] == 2 and st[(0, "intro")] == (2, 100.0) and st[(1, "move")] == (1, 50.0)
          and tf["complete"] == 1 and tf["complete_pct"] == 50.0 and tf["skip"] == 1 and tf["skip_pct"] == 50.0,
          "tutorial funnel: 2 start, step 0 2, step 1 1, 1 complete, 1 skip: %s" % tf)
    m = r["matches"]
    check(m["bots"]["finished"] == 1 and m["bots"]["quit"] == 1 and m["bots"]["completion_pct"] == 50.0 and m["bots"]["avg_len_s"] == 600,
          "bots: 1 finished 1 quit = 50%%, 10 min: %s" % m["bots"])
    check(m["online"]["finished"] == 2 and m["online"]["quit"] == 0 and m["online"]["completion_pct"] == 100.0 and m["online"]["avg_len_s"] == 390,
          "online: 2 finished = 100%%, avg 6m30: %s" % m["online"])
    wc = {c["class"]: (c["matches"], c["win_pct"]) for c in m["win_rate_by_class"]}
    check(wc == {"knight": (1, 100.0), "mage": (2, 50.0)}, "win rate by class (mage+ counts as mage): %s" % wc)
    s = r["session_length"]
    check(s["sessions"] == 3 and s["avg_s"] == 4860.0 and s["median_s"] == 120, "sessions: 3, avg 4860 s (20000 capped at 4 h), median 120: %s" % s)
    p = r["purchases"]
    check(p["purchases"] == 1 and p["payers"] == 1 and p["conversion_pct"] == 33.3 and p["test_purchases_left_out"] == 1
          and p["by_product"] == [{"product": "gems_80", "purchases": 1, "payers": 1}] and p["payers_all_time"] == 1,
          "purchases: 1 payer of 3 active (33.3%%), the test one left out, the excluded account's left out: %s" % p)
    so = r["social"]
    check(so["chat"]["players"] == 1 and so["chat"]["pct_of_active"] == 33.3 and so["friends"]["players"] == 1
          and so["party"]["players"] == 0 and so["chat"]["by_kind"] == {"global": 1}, "social: chat 1, friends 1, party 0")
    check(r["update_screen"] == [{"from_build": "0.31.116", "shown_on_phone": 1, "refused_by_server": 1, "players": 1}],
          "update screens by build: %s" % r["update_screen"])
    cf = r["crash_free"]
    check(cf["ended"] == 3 and cf["lost"] == 1 and cf["crash_free_pct"] == 66.7 and cf["errors"] == {"boot_stuck": 1},
          "crash-free 2 of 3 sessions, 1 stuck start: %s" % cf)
    check(r["opt_outs"] == {"period": 1, "all_time": 1}, "opt-outs: 1")
    check(r["dropped_events"]["q_dropped_n"] == 5 and r["dropped_events"]["phones_reporting"] == 1, "dropped on phones: 5")
    check(r["excluded"]["duplicates_skipped"] == 1 and r["excluded"]["probe_only_accounts"] == 1 and r["excluded"]["exclude_list"] == 1,
          "a duplicate id counted once, the probe account and the excluded account left out: %s" % r["excluded"])
    # --- the text and the JSON say the same
    tj = [ln for ln in lines if ln.startswith("  DAU JSON (UTC")]
    check(tj and json.loads(tj[0].split(":", 1)[1]) == [x["players"] for x in r["dau"]], "the text's DAU array is the JSON's")
    check(("WAU %d | MAU %d" % (r["wau"], r["mau"])) in txt and "D1 66.7% (2 of 3)" in txt and "D7 50.0% (1 of 2)" in txt,
          "the text's WAU/MAU and retention are the JSON's")
    check("completion 50.0%" in txt and "conversion 33.3%" in txt and "Crash-free sessions: 66.7%" in txt, "the text's rates are the JSON's")
    allout = txt + json.dumps(r)
    check(not any(a in allout for a in (A, B, C, D, P, X)), "no account id in the report")
    # --- an empty directory still reports (a server before any phone sent anything)
    e = tempfile.mkdtemp(prefix="an_empty_")
    res2 = subprocess.run([sys.executable, REPORT, "--dir", e, "--json", "-", "--now", "2026-10-12T18:00:00Z"], capture_output=True, text=True)
    check(res2.returncode == 0 and res2.stdout.startswith("TOTAL UNIQUE PLAYERS: 0 "), "an empty directory: total 0, no crash")
    shutil.rmtree(d, ignore_errors=True)
    shutil.rmtree(e, ignore_errors=True)
    print("ANALYTICS_REPORT_PASS" if not fails else "ANALYTICS_REPORT_FAIL %s" % fails)
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
