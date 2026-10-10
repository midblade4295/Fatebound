#!/usr/bin/env python3
"""Content packs (0.31.95, Kevin: "the main game installs a small file from the Play store and itch, then when they
launch the game after first install the game will say it's updating").

The installed build (Play and itch) holds the engine, every script and scene, the fonts, the launcher art and the
loader; the game's art and sound live in a few .pck files on the repo's content-packs branch (GitHub serves them at
raw.githubusercontent.com, with byte ranges; Kevin chose the branch when GitHub refused this session releases). On launch the
loader (scripts/app/content_loader.gd) downloads the packs the build needs that the phone doesn't have yet, checks
them, mounts them, then starts the game. Packs are split by what changes together, and each file is named by a hash
of its inputs, so a build that only changes code downloads nothing and a new weapon re-downloads only "weapons".

  python3 tools/content_packs.py build     export the packs whose inputs changed (build/packs/), strip them to data
                                           only, write content/manifest.json
  python3 tools/content_packs.py upload    commit every pack in the manifest to the content-packs branch and push it
                                           (skips ones there; old files stay for builds still in players' hands)
  python3 tools/content_packs.py check     the manifest matches the inputs and every pack is on the branch, right
                                           size (the build script runs this; exit 1 if not)
  python3 tools/content_packs.py presets   write the base presets' exclude filters (every pack's files) into
                                           export_presets.cfg
  python3 tools/content_packs.py coverage  every exported file under assets/ is in exactly one pack or the base
  python3 tools/content_packs.py base X    an exported APK/AAB holds no pack data, has this manifest, starts the
                                           loader (the build script and verify_play_bundle.py run this)
Env: GODOT (the editor binary); CONTENT_OUT, CONTENT_MANIFEST, CONTENT_PACK_PRESET (tools/content_e2e.sh builds
desktop-format packs elsewhere to test the loader). Uploads use git (no force-push: the branch only grows).
"""
import fnmatch
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import pck_tool  # noqa: E402

GODOT_VERSION = "4.7.2.stable"
REPO = "midblade4295/Fatebound"
BRANCH = "content-packs"
URL = "https://raw.githubusercontent.com/%s/%s/" % (REPO, BRANCH)
MAX_PACK = 95 * 1000 * 1000          # GitHub refuses files over 100 MB
MANIFEST = os.environ.get("CONTENT_MANIFEST", os.path.join(ROOT, "content", "manifest.json"))
UIDS = os.path.join(ROOT, "content", "uids.json")    # the packs' resources' UIDs, for the loader to register
OUT = os.environ.get("CONTENT_OUT", os.path.join(ROOT, "build", "packs"))
PACK_PRESET = os.environ.get("CONTENT_PACK_PRESET", "Content Pack")   # (tools/content_e2e.sh: the desktop one)
BASE_PRESETS = ["Android Play Store", "Android KayKit Rebuild"]
BODIES = ["archmage", "assassin", "barbarian", "berserker", "crusader", "knight", "mage", "necromancer", "priest",
          "ranger", "rogue", "sniper", "villager", "worker"]
# name -> the folders (Godot filter patterns, relative to res://) whose files the pack carries, in download order
PACKS = [
    ("ui", ["assets/ui/*"]),
    ("world", ["assets/meshy/castle/*", "assets/meshy/*_shop/*", "assets/meshy/workshop/*", "assets/meshy/outpost_*/*",
               "assets/kaykit/*", "assets/kings/*", "assets/terrain/*", "assets/props/*"]),
    ("heroes", ["assets/meshy/%s/*" % b for b in BODIES]),
    ("weapons", ["assets/meshy/weapons/*"]),
    ("audio", ["assets/music/*", "assets/sounds/*", "assets/vo/*"]),
]
BASE_ASSETS = ["assets/branding/*", "assets/fonts/*", "assets/vfx/*"]       # what the loader (and the update screen) use
NEVER = ["tests/*", "reports/*", "tools/*", "server/*", "store-listing/*", "assets/meshy/castle/war_*",
         "assets/meshy/castle/floors/war_*"]                                # not exported at all
KEEP_IN_PACK = ("assets/", ".godot/imported/", ".godot/exported/")           # a pack holds data only: no code, no settings
SKIP_FILES = (".txt", ".md", ".py", ".blend", ".blend1")                     # never exported (not resources)


def godot():
    return os.environ.get("GODOT", os.path.expanduser("~/godot/Godot_v4.7.2-stable_linux.x86_64"))


def match(path, patterns):
    return any(fnmatch.fnmatchcase(path, p) for p in patterns)


def asset_files():
    out = []
    for root, dirs, files in os.walk(os.path.join(ROOT, "assets")):
        dirs.sort()
        for f in sorted(files):
            rel = os.path.relpath(os.path.join(root, f), ROOT).replace(os.sep, "/")
            if rel.endswith(".import") or rel.endswith(SKIP_FILES) or match(rel, NEVER):
                continue
            out.append(rel)
    return out


def pack_of(rel):
    hits = [name for name, pats in PACKS if match(rel, pats)]
    return hits


def coverage():
    bad = []
    for rel in asset_files():
        hits = pack_of(rel)
        base = match(rel, BASE_ASSETS)
        if len(hits) + (1 if base else 0) != 1:
            bad.append("%s -> %s%s" % (rel, hits, " + base" if base else ""))
    return bad


def inputs_hash(name, pats):
    # every file the pack is made from (the asset and its .import settings) and the engine that imports it
    h = hashlib.sha256()
    h.update(("%s|%s|%s|%s\n" % (name, GODOT_VERSION, ",".join(pats), ",".join(KEEP_IN_PACK))).encode())
    for rel in asset_files():
        if name in pack_of(rel):
            for p in (rel, rel + ".import"):
                full = os.path.join(ROOT, p)
                if os.path.exists(full):
                    h.update(p.encode() + b"\0")
                    h.update(hashlib.sha256(open(full, "rb").read()).digest())
    return h.hexdigest()


def pack_uids():
    # uid -> res:// path of every imported file in a pack. The build's uid cache only knows the build's own files, so
    # the loader registers these after mounting (else Godot warns and falls back to the path for each reference).
    out = {}
    for rel in asset_files():
        if not pack_of(rel) or not os.path.exists(os.path.join(ROOT, rel + ".import")):
            continue
        m = re.search(r'(?m)^uid="(uid://[a-z0-9]+)"', open(os.path.join(ROOT, rel + ".import"), errors="ignore").read())
        if m:
            out[m.group(1)] = "res://" + rel
    return dict(sorted(out.items()))


def uids_text():
    return json.dumps(pack_uids(), indent=0) + "\n"


def load_manifest():
    if os.path.exists(MANIFEST):
        return json.load(open(MANIFEST))
    return {"format": 1, "url": URL, "packs": []}


def save_manifest(m):
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump(m, f, indent=1)
        f.write("\n")


def _set_preset(cfg, preset, key, value):
    # value of key in the [preset.N] block named preset
    blocks = re.split(r"(?m)^(?=\[preset\.\d+\]\s*$)", cfg)
    for i, b in enumerate(blocks):
        if re.search(r'(?m)^name="%s"$' % re.escape(preset), b):
            new, n = re.subn(r'(?m)^%s=.*$' % re.escape(key), '%s=%s' % (key, value), b, count=1)
            if n != 1:
                raise SystemExit("%s: no %s" % (preset, key))
            blocks[i] = new
            return "".join(blocks)
    raise SystemExit("no preset " + preset)


def export_pack(name, pats, out):
    cfg_path = os.path.join(ROOT, "export_presets.cfg")
    original = open(cfg_path).read()
    cfg = _set_preset(original, PACK_PRESET, "include_filter", '"%s"' % ",".join(pats))
    cfg = _set_preset(cfg, PACK_PRESET, "exclude_filter", '"%s"' % ",".join(NEVER + BASE_ASSETS))
    raw = out[:-len(".pck")] + ".raw.pck"
    try:
        open(cfg_path, "w").write(cfg)
        r = subprocess.run([godot(), "--headless", "--path", ROOT, "--export-pack", PACK_PRESET, raw],
                           capture_output=True, text=True, timeout=1800)
    finally:
        open(cfg_path, "w").write(original)
    if not os.path.exists(raw):
        raise SystemExit("export of %s failed:\n%s" % (name, (r.stdout + r.stderr)[-3000:]))
    removed = strip_to_data(raw, out)
    os.remove(raw)
    return removed


def _base_import_hashes():
    # Godot names an imported file <file>-<md5 of its res:// path>.<ext>: the base assets' imports, by that md5
    return {hashlib.md5(("res://" + rel).encode()).hexdigest() for rel in asset_files() if match(rel, BASE_ASSETS)}


def strip_to_data(src, dst):
    head, es = pck_tool.read(src)
    base = _base_import_hashes()

    def dropped(path):
        if not path.startswith(KEEP_IN_PACK):
            return True                                   # settings, uid cache, the autoload scripts Godot adds
        if path.startswith("assets/") and match(path[:-len(".import")] if path.endswith(".import") else path, BASE_ASSETS):
            return True                                   # the launcher icon Godot adds: the base build has it
        m = re.match(r"\.godot/imported/.*-([0-9a-f]{32})\.", path)
        return bool(m and m.group(1) in base)
    drop = sorted({e["path"] for e in es if dropped(e["path"])})
    pck_tool.strip(src, dst, drop)
    left = [p for p, _, _ in pck_tool.entries(dst)]
    code = [p for p in left if p.endswith((".gd", ".gdc", ".gde", ".gdshader", ".cs", ".dll", ".so", ".dex"))]
    if code:
        raise SystemExit("code in a content pack: %s" % code[:5])
    return drop


def probe_of(path):
    # a file only this pack has: the first asset with an import file (ResourceLoader.exists sees it once mounted)
    for p, _, _ in pck_tool.entries(path):
        if p.startswith("assets/") and p.endswith(".import"):
            return "res://" + p[:-len(".import")]
    for p, _, _ in pck_tool.entries(path):
        if p.startswith("assets/"):
            return "res://" + p
    raise SystemExit("%s: no assets" % path)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build(force=False):
    bad = coverage()
    if bad:
        raise SystemExit("assets not in exactly one pack or the base:\n  " + "\n  ".join(bad[:20]))
    os.makedirs(OUT, exist_ok=True)
    m = load_manifest()
    old = {p["name"]: p for p in m.get("packs", [])}
    packs = []
    for name, pats in PACKS:
        ih = inputs_hash(name, pats)
        prev = old.get(name)
        if prev and prev.get("inputs") == ih and not force:
            packs.append(prev)
            print("%-8s unchanged (%s)" % (name, prev["file"]))
            continue
        out = os.path.join(OUT, "%s-%s.pck" % (name, ih[:12]))
        dropped = export_pack(name, pats, out)
        if os.path.getsize(out) > MAX_PACK:
            raise SystemExit("%s is %.1f MB: GitHub refuses files over 100 MB, split the pack" % (name, os.path.getsize(out) / 1e6))
        entry = {"name": name, "file": os.path.basename(out), "size": os.path.getsize(out), "sha256": sha256_file(out),
                 "inputs": ih, "probe": probe_of(out)}
        packs.append(entry)
        print("%-8s built %s, %.1f MB (dropped %s)" % (name, entry["file"], entry["size"] / 1e6, ", ".join(dropped)))
    m = {"format": 1, "url": URL, "packs": packs}
    save_manifest(m)
    if MANIFEST == os.path.join(ROOT, "content", "manifest.json") or not os.path.exists(UIDS):
        open(UIDS, "w").write(uids_text())
    dupes = overlap()
    if dupes:
        print("note: %d files are in more than one pack (dependencies), e.g. %s" % (len(dupes), dupes[:3]))
    print("manifest: %d packs, %.1f MB" % (len(packs), sum(p["size"] for p in packs) / 1e6))


def overlap():
    seen = {}
    dupes = []
    for p in load_manifest()["packs"]:
        f = os.path.join(OUT, p["file"])
        if not os.path.exists(f):
            continue
        for path, _, _ in pck_tool.entries(f):
            if path in seen and not path.endswith(".import"):
                dupes.append(path)
            seen[path] = p["name"]
    return dupes


def git(*args, inp=None):
    r = subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True, input=inp, text=True)
    if r.returncode != 0:
        raise SystemExit("git %s: %s" % (" ".join(args[:3]), (r.stdout + r.stderr)[-800:]))
    return r.stdout.strip()


README = """# Fatebound content packs

The game's art and sound, downloaded by the game on first launch (and when the art changes) from
https://raw.githubusercontent.com/%s/%s/<file>. Each build's `godot/content/manifest.json` lists
the files it needs, with sizes and SHA-256s; files are named by a hash of what they are made from. Made and pushed by
`godot/tools/content_packs.py` -- don't edit by hand. Old files stay while builds that list them may still be in
players' hands.
""" % (REPO, BRANCH)


def upload():
    m = load_manifest()
    for p in m["packs"]:
        f = os.path.join(OUT, p["file"])
        if not os.path.exists(f) or os.path.getsize(f) != p["size"] or sha256_file(f) != p["sha256"]:
            raise SystemExit("%s: build/packs/%s is missing or not the one in the manifest; run build" % (p["name"], p["file"]))
    remote = git("ls-remote", "origin", "refs/heads/" + BRANCH)
    parent = remote.split()[0] if remote else ""
    entries = {}
    if parent:
        git("fetch", "-q", "origin", "+refs/heads/%s:refs/remotes/origin/%s" % (BRANCH, BRANCH))
        for line in git("ls-tree", "--full-tree", parent).splitlines():
            meta, name = line.split("\t", 1)
            entries[name] = meta
    added = []
    if "README.md" not in entries:
        entries["README.md"] = "100644 blob " + git("hash-object", "-w", "--stdin", inp=README)
        added.append("README.md")
    for p in m["packs"]:
        if p["file"] in entries:
            local = git("hash-object", os.path.join(OUT, p["file"]))
            if entries[p["file"]].split()[2] != local:
                raise SystemExit("%s: the branch has a different %s -- a pack's name must change with its content "
                                 "(its inputs changed without the hash noticing?)" % (p["name"], p["file"]))
            print("%-8s on the branch" % p["name"])
            continue
        entries[p["file"]] = "100644 blob " + git("hash-object", "-w", os.path.join(OUT, p["file"]))
        added.append(p["file"])
        print("%-8s adding %s (%.1f MB)" % (p["name"], p["file"], p["size"] / 1e6))
    if not added:
        print("the %s branch has every pack" % BRANCH)
        return
    tree = git("mktree", inp="".join("%s\t%s\n" % (meta, name) for name, meta in sorted(entries.items())))
    msg = ("Content packs: %s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n"
           "Claude-Session: https://claude.ai/code/session_01E7g828t3p5DgnGnspyvbqX" % ", ".join(added))
    commit = git("commit-tree", tree, *(["-p", parent] if parent else []), "-m", msg)
    git("push", "-q", "origin", "%s:refs/heads/%s" % (commit, BRANCH))
    print("pushed %s to %s: %s" % (commit[:7], BRANCH, ", ".join(added)))


def remote_size(name):
    req = urllib.request.Request(URL + name, method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return int(r.headers.get("Content-Length", -1))
    except Exception:
        return -1


def check():
    problems = []
    bad = coverage()
    if bad:
        problems.append("%d assets not in exactly one pack or the base, e.g. %s" % (len(bad), bad[0]))
    m = load_manifest()
    names = [p["name"] for p in m.get("packs", [])]
    if names != [n for n, _ in PACKS]:
        problems.append("manifest packs %s, expected %s" % (names, [n for n, _ in PACKS]))
    for p in m.get("packs", []):
        pats = dict(PACKS).get(p["name"])
        if pats is not None and inputs_hash(p["name"], pats) != p["inputs"]:
            problems.append("%s: its files changed since the pack was built (run build, then upload)" % p["name"])
    if not os.path.exists(UIDS) or open(UIDS).read() != uids_text():
        problems.append("content/uids.json is out of date (run build)")
    for p in m.get("packs", []):
        if remote_size(p["file"]) != p["size"]:
            problems.append("%s: %s is not on the %s branch (run upload)" % (p["name"], p["file"], BRANCH))
    for p in problems:
        print("CONTENT:", p)
    print("CONTENT OK" if not problems else "CONTENT NOT READY")
    return not problems


def base_problems(res_paths, manifest_bytes):
    # what's wrong with an installed build's files (res:// paths): a pack's asset or its import shipped in the build,
    # or the build's manifest isn't this repo's
    problems = []
    pack_hashes = {hashlib.md5(("res://" + rel).encode()).hexdigest() for rel in asset_files() if pack_of(rel)}
    for p in res_paths:
        src = p[:-len(".import")] if p.endswith(".import") else p
        if src.startswith("assets/") and pack_of(src):
            problems.append(p)
            continue
        m = re.match(r"\.godot/imported/.*-([0-9a-f]{32})\.", p)
        if m and m.group(1) in pack_hashes:
            problems.append(p)
    if manifest_bytes is None:
        problems.append("no content/manifest.json in the build")
    elif manifest_bytes != open(MANIFEST, "rb").read():
        problems.append("the build's content/manifest.json is not the repo's")
    return problems


def check_base(archive):
    # an APK or AAB: the game's files sit under <module>/assets/ beside project.binary
    import zipfile
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        proj = [n for n in names if n == "assets/project.binary" or n.endswith("/assets/project.binary")]
        if len(proj) != 1:
            raise SystemExit("%s: %d project.binary files" % (archive, len(proj)))
        prefix = proj[0][:-len("project.binary")]
        res = [n[len(prefix):] for n in names if n.startswith(prefix)]
        man = z.read(prefix + "content/manifest.json") if prefix + "content/manifest.json" in names else None
        main = z.read(proj[0])
    problems = base_problems(res, man)
    if b"res://scenes/Boot.tscn" not in main:
        problems.append("the main scene is not res://scenes/Boot.tscn (the content loader)")
    for p in problems[:20]:
        print("BASE:", p)
    print("BASE OK: %d files, no pack data, the loader starts first" % len(res) if not problems else
          "BASE NOT OK (%d problems)" % len(problems))
    return not problems


def presets():
    cfg_path = os.path.join(ROOT, "export_presets.cfg")
    cfg = open(cfg_path).read()
    pats = NEVER + [p for _, ps in PACKS for p in ps]
    for name in BASE_PRESETS:
        cfg = _set_preset(cfg, name, "exclude_filter", '"%s"' % ",".join(pats))
    open(cfg_path, "w").write(cfg)
    print("base presets exclude %d patterns" % len(pats))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "build":
        build("--force" in sys.argv)
    elif cmd == "upload":
        upload()
    elif cmd == "check":
        sys.exit(0 if check() else 1)
    elif cmd == "base":
        sys.exit(0 if check_base(sys.argv[2]) else 1)
    elif cmd == "presets":
        presets()
    elif cmd == "coverage":
        bad = coverage()
        print("\n".join(bad) if bad else "every asset is in exactly one pack or the base")
        sys.exit(1 if bad else 0)
    else:
        raise SystemExit(__doc__)
