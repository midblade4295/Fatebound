#!/usr/bin/env python3
"""Fatebound SEND TO DEVELOPER reports (0.31.120): list them, show one.

Python 3 standard library only. Run it on the server, where the files are (the state directory is root-only):

  sudo python3 godot/tools/diag_reports.py --dir /var/lib/private/fatebound-siege            # the newest 30
  sudo python3 godot/tools/diag_reports.py --dir /var/lib/private/fatebound-siege --all
  sudo python3 godot/tools/diag_reports.py --dir /var/lib/private/fatebound-siege --since 2026-10-01
  sudo python3 godot/tools/diag_reports.py --dir /var/lib/private/fatebound-siege show 7F3A9C   # a report, whole
  sudo python3 godot/tools/diag_reports.py --dir /var/lib/private/fatebound-siege show 7F3A9C --errors   # its errors

Each report is <dir>/diag/YYYYMMDD-HHMMSS-<ID>.txt (server/diag_reports.gd): one JSON header line
({"id", "at", "acct", "name", "build", "model", "os", "gpu", "note", "bytes"}), then the game's log as the phone sent it.
The player gives the ID they were shown ("Sent -- report #7F3A9C").
"""
import argparse
import datetime as dt
import glob
import json
import os
import sys


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="Fatebound SEND TO DEVELOPER reports")
    ap.add_argument("--dir", required=True, help="the server's state directory (holds diag/)")
    ap.add_argument("--all", action="store_true", help="every report, not just the newest 30")
    ap.add_argument("--since", help="only reports from this UTC day on (YYYY-MM-DD)")
    ap.add_argument("--build", help="only reports from builds containing this text")
    ap.add_argument("cmd", nargs="?", default="list", choices=["list", "show"])
    ap.add_argument("id", nargs="?", help="show: the report's ID")
    ap.add_argument("--errors", action="store_true", help="show: only the header, the note and lines with ERROR/STALL/fatal")
    return ap.parse_args(argv)


def load(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        first = f.readline()
        body = f.read()
    try:
        head = json.loads(first)
    except ValueError:
        head = {"id": os.path.basename(path), "note": "(no header)"}
    return head, body


def reports(d):
    return sorted(glob.glob(os.path.join(d, "diag", "*.txt")))


def when(t):
    return dt.datetime.fromtimestamp(int(t or 0), dt.timezone.utc).strftime("%Y-%m-%d %H:%M")


def cmd_list(a, out=sys.stdout):
    files = reports(a.dir)
    rows = []
    for p in files:
        head, _ = load(p)
        if a.since and when(head.get("at")) < a.since:
            continue
        if a.build and a.build not in str(head.get("build", "")):
            continue
        rows.append(head)
    rows.reverse()                                     # newest first
    shown = rows if a.all else rows[:30]
    print("%d report(s)%s" % (len(rows), "" if a.all or len(rows) <= 30 else ", the newest 30 (--all for every one)"), file=out)
    for h in shown:
        note = str(h.get("note", "")).replace("\n", " ")
        print("#%-6s %s UTC  %-22s %-24s %-14s %6d ch  %s" % (
            h.get("id", "?"), when(h.get("at")), str(h.get("build", ""))[:22], str(h.get("model", ""))[:24],
            str(h.get("name", "") or "-")[:14], int(h.get("bytes", 0) or 0), (note[:60] + "...") if len(note) > 60 else note), file=out)
    return 0


def cmd_show(a, out=sys.stdout):
    if not a.id:
        print("show needs a report ID", file=sys.stderr)
        return 2
    want = a.id.strip().lstrip("#").upper()
    for p in reports(a.dir):
        if p.endswith("-%s.txt" % want):
            head, body = load(p)
            print("Report #%s  %s UTC" % (head.get("id", want), when(head.get("at"))), file=out)
            for k in ["name", "acct", "build", "model", "os", "gpu"]:
                print("  %-6s %s" % (k, head.get(k, "") or "-"), file=out)
            print("  note   %s" % (head.get("note", "") or "-"), file=out)
            print("", file=out)
            if a.errors:
                for line in body.split("\n"):
                    if any(w in line for w in ("ERROR", "STALL", "fatal", "SESSION", "====")):
                        print(line, file=out)
            else:
                print(body, file=out)
            return 0
    print("no report #%s" % want, file=sys.stderr)
    return 1


def main(argv=None):
    a = parse_args(argv)
    if not os.path.isdir(os.path.join(a.dir, "diag")):
        print("no reports yet (%s has no diag/)" % a.dir, file=sys.stderr)
        return 1
    return cmd_show(a) if a.cmd == "show" else cmd_list(a)


if __name__ == "__main__":
    sys.exit(main())
