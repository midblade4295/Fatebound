#!/usr/bin/env python3
"""0.31.153: every script the server installs can load what it preloads/loads.

server/deploy/install_siege_server.sh copies a list of files (SERVER_SCRIPTS, META_SCRIPTS, SERVER_FILES) to the
server, not the whole project. A script on the list that preloads one off it (0.31.153: the sim's COMMANDER section
preloads scripts/meta/cards.gd) fails to compile there -- the server wouldn't start. This follows every
preload("res://...") / load("res://...") of a listed .gd and says which aren't on the list.
    python3 tools/test_server_files.py        -> SERVER_FILES_PASS / SERVER_FILES_FAIL
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INSTALL = os.path.join(ROOT, "server", "deploy", "install_siege_server.sh")
RES = re.compile(r'(?:preload|load)\(\s*"res://([^"]+)"\s*\)')


def listed():
    text = open(INSTALL).read()
    out = set()
    for var in ("SERVER_SCRIPTS", "META_SCRIPTS", "SERVER_FILES"):
        m = re.search(r'^%s="([^"]*)"' % var, text, re.M)
        if not m:
            raise SystemExit("SERVER_FILES_FAIL: %s not found in the installer" % var)
        out.update(m.group(1).split())
    return out


def main():
    files = listed()
    missing = {}
    todo = [f for f in files if f.endswith(".gd")]
    seen = set()
    while todo:
        f = todo.pop()
        if f in seen:
            continue
        seen.add(f)
        path = os.path.join(ROOT, f)
        if not os.path.exists(path):
            missing.setdefault(f, []).append("(the installer's own list)")
            continue
        for dep in RES.findall(open(path, encoding="utf-8").read()):
            if not dep.endswith(".gd"):
                continue                     # (resources the server never touches are loaded only on the phone)
            if dep not in files:
                missing.setdefault(dep, []).append(f)
            elif dep not in seen:
                todo.append(dep)
    if missing:
        for dep, by in sorted(missing.items()):
            print("FAIL %s (loaded by %s) is not installed on the server" % (dep, ", ".join(sorted(set(by)))))
        print("SERVER_FILES_FAIL")
        return 1
    print("ok   %d server scripts, every script they load is installed too" % len([f for f in seen]))
    print("SERVER_FILES_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
