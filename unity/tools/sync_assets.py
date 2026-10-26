#!/usr/bin/env python3
"""Copies the Godot game's assets into the Unity project, converting what Unity can't import.

  python3 unity/tools/sync_assets.py            # from the repo root (or anywhere)
  python3 unity/tools/sync_assets.py --check    # report what would change, write nothing

Every res:// path keeps its place under Assets/Resources/res/ (res://assets/ui/x.png ->
Assets/Resources/res/assets/ui/x.png), so the game code's paths still work: the host strips the
extension and calls Resources.Load (Client/Core/UnityGuiHost.cs).

  .png .jpg .wav .ogg .mp3 .json      copied as they are
  .webp                                -> .png (Pillow)
  .svg                                 -> .png (rasterised by Godot at the scale Godot imported it)
  .ttf .otf .woff2                     -> <name>.ttf.bytes / <name>.woff2.bytes (TrueType bytes as a TextAsset;
                                          woff2 decompressed with fontTools). The GUI reads fonts itself.
  .glb .gltf .bin .res .scn .tscn .tres  not copied: tools/bake/bake.sh bakes what Godot loads from them into
                                       <path>.bytes (+ _baked/: embedded textures, manifest.json), which this script
                                       keeps (GUI/Scene3D/BakedLoader.cs reads them)
Godot's .import sidecars are not copied; Editor/AssetImport.cs sets the Unity import settings per folder.
"""
import io
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT = os.path.join(ROOT, "godot")
DEST = os.path.join(ROOT, "unity", "Assets", "Resources", "res")
SOURCES = ["assets", "content"]
COPY = {".png", ".jpg", ".jpeg", ".wav", ".ogg", ".mp3", ".json", ".txt"}
SKIP = {".import", ".uid", ".res", ".scn", ".tscn", ".tres", ".md", ".gdignore", ".gdshader", ".glb", ".gltf", ".bin"}
# the bake's outputs (tools/bake): never stale here
BAKED = tuple(e + ".bytes" for e in (".glb", ".gltf", ".scn", ".tscn", ".res", ".tres"))
FONT = {".ttf", ".otf", ".woff2", ".woff"}
CHECK = "--check" in sys.argv
GODOT_BIN = os.environ.get("GODOT", "/root/godot/Godot_v4.7.2-stable_linux.x86_64")


def newer(src, dst):
    return not os.path.exists(dst) or os.path.getmtime(src) > os.path.getmtime(dst) + 1e-6


def write(dst, data):
    if CHECK:
        print("would write", os.path.relpath(dst, ROOT))
        return
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(data)


def copy(src, dst):
    if CHECK:
        print("would copy", os.path.relpath(src, ROOT))
        return
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)


def svg_size(src):
    imp = src + ".import"
    scale = 1.0
    if os.path.exists(imp):
        for line in open(imp):
            if line.startswith("svg/scale="):
                scale = float(line.split("=")[1])
    return scale


def main():
    from PIL import Image
    n = {"copied": 0, "converted": 0, "skipped": 0, "same": 0}
    wanted = set()
    for top in SOURCES:
        for dirpath, _, files in os.walk(os.path.join(GODOT, top)):
            if os.path.exists(os.path.join(dirpath, ".gdignore")):
                continue
            for name in files:
                src = os.path.join(dirpath, name)
                rel = os.path.relpath(src, GODOT)
                stem, ext = os.path.splitext(rel)
                ext = ext.lower()
                if ext in SKIP:
                    n["skipped"] += 1
                    continue
                if ext in COPY:
                    dst = os.path.join(DEST, rel)
                    wanted.add(dst)
                    if newer(src, dst):
                        copy(src, dst)
                        n["copied"] += 1
                    else:
                        n["same"] += 1
                elif ext == ".webp":
                    dst = os.path.join(DEST, stem + ".png")
                    wanted.add(dst)
                    if newer(src, dst):
                        im = Image.open(src)
                        im = im.convert("RGBA") if im.mode in ("P", "LA", "RGBA") or "transparency" in im.info else im.convert("RGB")
                        buf = io.BytesIO()
                        im.save(buf, "PNG", optimize=True)
                        write(dst, buf.getvalue())
                        n["converted"] += 1
                    else:
                        n["same"] += 1
                elif ext == ".svg":
                    dst = os.path.join(DEST, stem + ".png")
                    wanted.add(dst)
                    if newer(src, dst):
                        if not CHECK:
                            os.makedirs(os.path.dirname(dst), exist_ok=True)
                            subprocess.run([GODOT_BIN, "--headless", "-s", os.path.join(ROOT, "unity", "tools", "godot", "svg_to_png.gd"),
                                            "--", src, dst, str(svg_size(src))], check=True, capture_output=True)
                        n["converted"] += 1
                    else:
                        n["same"] += 1
                elif ext in FONT:
                    dst = os.path.join(DEST, rel + ".bytes")
                    wanted.add(dst)
                    if newer(src, dst):
                        if ext in (".woff2", ".woff"):
                            from fontTools.ttLib import TTFont
                            f = TTFont(src)
                            f.flavor = None
                            buf = io.BytesIO()
                            f.save(buf)
                            write(dst, buf.getvalue())
                        else:
                            write(dst, open(src, "rb").read())
                        n["converted"] += 1
                    else:
                        n["same"] += 1
                else:
                    print("unhandled:", rel)
    # Godot's built-in default font (Open Sans SemiBold), for controls without a font override.
    osb = os.path.join(DEST, "assets", "fonts", "OpenSans_SemiBold.ttf.bytes")
    wanted.add(osb)
    if not os.path.exists(osb):
        src = "/home/claude/godot-src/thirdparty/fonts/OpenSans_SemiBold.woff2"
        if os.path.exists(src):
            from fontTools.ttLib import TTFont
            f = TTFont(src)
            f.flavor = None
            buf = io.BytesIO()
            f.save(buf)
            write(osb, buf.getvalue())
    # Remove files whose source is gone (and the .glb/.gltf/.bin copies of earlier syncs), keeping the bake's outputs:
    # <path>.<glb|gltf|scn|tscn|res|tres>.bytes and everything under _baked/.
    stale = 0
    if os.path.isdir(DEST):
        for dirpath, _, files in os.walk(DEST):
            for name in files:
                p = os.path.join(dirpath, name)
                if p.endswith(".meta") or "/_baked/" in p or name.lower().endswith(BAKED):
                    continue
                if p not in wanted:
                    stale += 1
                    if CHECK:
                        print("would remove", os.path.relpath(p, ROOT))
                    else:
                        os.remove(p)
                        if os.path.exists(p + ".meta"):
                            os.remove(p + ".meta")
    print("sync_assets:", n, "stale removed:", stale)


if __name__ == "__main__":
    main()
