#!/usr/bin/env python3
"""Adds up the match lines written by tools/balance.gd.

Usage: balance_report.py FILE [FILE ...]

Prints how matches ended, and for each card how its holder fared in the matches where only
one side had it (so a card that wins more than half of those is pulling its weight, and one
well under half is dead weight), with how often it was played.
"""
import json
import sys
from collections import Counter, defaultdict


def main():
    rows = []
    for path in sys.argv[1:]:
        with open(path) as f:
            rows += [json.loads(line) for line in f if line.strip()]
    n = len(rows)
    if n == 0:
        raise SystemExit("no matches")
    how = Counter(r["how"] for r in rows)
    wins = Counter(r["winner"] for r in rows)
    print(f"{n} matches: side 0 won {wins[0]}, side 1 won {wins[1]}, drawn {wins[2]}")
    print("ended by: " + ", ".join(f"{k} {v * 100 // n}%" for k, v in how.most_common()))
    fell = sum(r["lost"][0] + r["lost"][1] for r in rows) / n
    some = sum(1 for r in rows if r["lost"][0] + r["lost"][1] > 0) * 100 // n
    falls = [r["first_fall"] for r in rows if r["first_fall"] >= 0]
    print(f"batteries fallen per match {fell:.2f}; at least one fell in {some}% of matches"
          + (f"; first one at {sum(falls) / len(falls):.0f} s on average" if falls else ""))
    print(f"average length {sum(r['time'] for r in rows) / n:.0f} s; structure damage per side {sum(sum(r['damage']) for r in rows) / n / 2:.0f}; "
          f"routs per match {sum(r['routs'] for r in rows) / n:.0f}")
    held = defaultdict(lambda: [0, 0.0, 0])        # card -> [matches only one side had it, wins, plays]
    for r in rows:
        for side in (0, 1):
            for card in r["decks"][side]:
                if card in r["decks"][1 - side]:
                    continue
                h = held[card]
                h[0] += 1
                h[1] += 1.0 if r["winner"] == side else (0.5 if r["winner"] == 2 else 0.0)
                h[2] += r["plays"][side].get(card, 0)
    if held:
        print(f"{'card':<16} {'held':>5} {'win %':>6} {'+/-':>4} {'plays':>6}")
        for card, (count, won, plays) in sorted(held.items(), key=lambda kv: -kv[1][1] / max(1, kv[1][0])):
            if count == 0:
                continue
            rate = won / count
            err = 100 * (0.25 / count) ** 0.5
            print(f"{card:<16} {count:>5} {rate * 100:>5.0f}% {err:>4.0f} {plays / count:>6.1f}")


if __name__ == "__main__":
    main()
