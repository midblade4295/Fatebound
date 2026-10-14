#!/usr/bin/env python3
"""iOS port step 8 (IOS_PORT_SPEC_FOR_CLAUDE.md section 5): may the iPhone use the very same content packs as Android?

Exports packs with an iOS content-pack preset (added to export_presets.cfg only while this runs) exactly the way
tools/content_packs.py builds Android's, strips them the same way, and compares each with the pack the manifest lists
(its sha256). Identical packs mean one set of packs serves both phones: same manifest, same files, same branch.
  GODOT=... python3 tools/ios_pack_check.py [PACK ...]        (default: every pack; packs already in
                                                              build/packs/ are compared byte for byte too)
Prints IOS_PACKS_SAME when every pack checked is identical.
"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import content_packs as cp  # noqa: E402

PRESET = "Content Pack (iOS check)"


def ios_preset_block(cfg):
    # the Android pack preset's block, as an iOS preset (Godot fills every iOS option it doesn't find with its default)
    import re
    n = max(int(x) for x in re.findall(r"(?m)^\[preset\.(\d+)\]$", cfg)) + 1
    return ("\n[preset.%d]\n\nname=\"%s\"\nplatform=\"iOS\"\nrunnable=false\nadvanced_options=false\ndedicated_server=false\n"
            "custom_features=\"\"\nexport_filter=\"resources\"\nexport_files=PackedStringArray()\ninclude_filter=\"\"\n"
            "exclude_filter=\"\"\nexport_path=\"build/packs/ios.pck\"\npatches=PackedStringArray()\n"
            "encryption_include_filters=\"\"\nencryption_exclude_filters=\"\"\nencrypt_pck=false\nencrypt_directory=false\n\n"
            "[preset.%d.options]\n\narchitectures/arm64=true\napplication/bundle_identifier=\"com.fatebound.game\"\n"
            "application/app_store_team_id=\"YBKRZRW845\"\n") % (n, PRESET, n)


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    want = sys.argv[1:]
    man = cp.load_manifest()
    listed = {p["name"]: p for p in man["packs"]}
    out_dir = os.path.join(cp.ROOT, "build", "ios_pack_check")
    os.makedirs(out_dir, exist_ok=True)
    cfg_path = os.path.join(cp.ROOT, "export_presets.cfg")
    original = open(cfg_path).read()
    results = []
    try:
        open(cfg_path, "w").write(original + ios_preset_block(original))
        cp.PACK_PRESET = PRESET
        for name, pats in cp.PACKS:
            if want and name not in want:
                continue
            out = os.path.join(out_dir, "%s-ios.pck" % name)
            cp.export_pack(name, pats, out)
            got = sha(out)
            exp = listed.get(name, {}).get("sha256", "")
            local = os.path.join(cp.ROOT, "build", "packs", listed.get(name, {}).get("file", "-"))
            same_local = os.path.exists(local) and open(local, "rb").read() == open(out, "rb").read()
            results.append({"pack": name, "ios_sha256": got, "manifest_sha256": exp, "same": got == exp,
                            "same_as_local_android_file": same_local if os.path.exists(local) else None,
                            "bytes": os.path.getsize(out)})
            print(json.dumps(results[-1]))
            os.remove(out)
    finally:
        open(cfg_path, "w").write(original)
    ok = bool(results) and all(r["same"] for r in results)
    print("IOS_PACKS_SAME" if ok else "IOS_PACKS_DIFFER")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
