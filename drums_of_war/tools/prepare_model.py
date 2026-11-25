#!/usr/bin/env python3
"""Prepare a generated GLB model for the game.

Rewrites the textures embedded in a GLB at a smaller size and can also write the crimson-team
version of its base colour texture.

Usage:
  prepare_model.py IN.glb OUT.glb [--tex 1024] [--red OUT_red.png] [--canvas] [--strip-textures]

  --tex N            longest side of every embedded texture after the rewrite (default 1024)
  --red PATH         also write the base colour texture with the team blue turned crimson
                     (roofs, awnings, pennants); the game swaps it in for the enemy's structures
  --canvas           turn the team blue in the base colour texture into cream canvas, in the
                     GLB itself; for works that both sides build alike (the gun batteries)
  --strip-textures   shrink every texture to 4 px; for animation-only GLBs, which carry a full
                     copy of the mesh and textures that the game never draws

Needs Pillow and numpy.
"""
import argparse
import io
import json
import struct

import numpy as np
from PIL import Image


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2:
        raise SystemExit(f"{path}: not a glTF 2 binary")
    json_len, json_type = struct.unpack_from("<I4s", data, 12)
    if json_type != b"JSON":
        raise SystemExit(f"{path}: first chunk is not JSON")
    doc = json.loads(data[20:20 + json_len])
    pos = 20 + json_len
    blob = b""
    if pos < len(data):
        bin_len, bin_type = struct.unpack_from("<I4s", data, pos)
        if bin_type == b"BIN\x00":
            blob = data[pos + 8:pos + 8 + bin_len]
    return doc, blob


def write_glb(path, doc, blob):
    payload = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    payload += b" " * (-len(payload) % 4)
    blob += b"\x00" * (-len(blob) % 4)
    total = 12 + 8 + len(payload) + 8 + len(blob)
    with open(path, "wb") as out:
        out.write(struct.pack("<4sII", b"glTF", 2, total))
        out.write(struct.pack("<I4s", len(payload), b"JSON"))
        out.write(payload)
        out.write(struct.pack("<I4s", len(blob), b"BIN\x00"))
        out.write(blob)


def to_crimson(img):
    """Turns saturated blue texels crimson and leaves everything else alone."""
    hsv = np.asarray(img.convert("RGB").convert("HSV"), dtype=np.float32)
    hue, sat, val = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    # PIL hue runs 0..255; blue sits around 150..185 (212..260 degrees).
    blue = (hue > 140) & (hue < 190) & (sat > 70) & (val > 35)
    hue = np.where(blue, 247.0, hue)                 # about 349 degrees
    sat = np.where(blue, np.clip(sat * 1.05, 0, 255), sat)
    val = np.where(blue, np.clip(val * 0.98 + 6, 0, 255), val)
    out = np.stack([hue, sat, val], axis=-1).astype(np.uint8)
    return Image.fromarray(out, "HSV").convert("RGB"), float(blue.mean())


def to_canvas(img):
    """Turns saturated blue texels into pale cream canvas, keeping their light and shade."""
    hsv = np.asarray(img.convert("RGB").convert("HSV"), dtype=np.float32)
    hue, sat, val = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    blue = (hue > 140) & (hue < 190) & (sat > 70) & (val > 35)
    hue = np.where(blue, 28.0, hue)                  # about 40 degrees: warm cream
    sat = np.where(blue, 88.0, sat)
    # The blue cloth is dark; canvas is light. Stretch its shading into the upper range.
    val = np.where(blue, np.clip(222.0 + (val - 120.0) * 0.55, 170, 252), val)
    out = np.stack([hue, sat, val], axis=-1).astype(np.uint8)
    return Image.fromarray(out, "HSV").convert("RGB"), float(blue.mean())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--tex", type=int, default=1024)
    ap.add_argument("--red")
    ap.add_argument("--canvas", action="store_true")
    ap.add_argument("--strip-textures", action="store_true")
    args = ap.parse_args()

    doc, blob = read_glb(args.src)
    views = doc.get("bufferViews", [])
    images = doc.get("images", [])
    image_views = {img["bufferView"]: i for i, img in enumerate(images) if "bufferView" in img}

    # Which image is the base colour of the first material?
    base_image = None
    for mat in doc.get("materials", []):
        tex = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if tex is not None:
            base_image = doc["textures"][tex["index"]].get("source")
            break

    target = 4 if args.strip_textures else args.tex
    new_blob = bytearray()
    before = after = 0
    for index, view in enumerate(views):
        start = view.get("byteOffset", 0)
        chunk = blob[start:start + view["byteLength"]]
        if index in image_views:
            image_index = image_views[index]
            before += len(chunk)
            img = Image.open(io.BytesIO(chunk))
            img.load()
            if max(img.size) > target:
                scale = target / max(img.size)
                img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)
            if args.canvas and image_index == base_image:
                img, share = to_canvas(img)
                print(f"canvas: {share * 100:.1f}% of texels recoloured")
            buf = io.BytesIO()
            has_alpha = img.mode in ("RGBA", "LA") and np.asarray(img.convert("RGBA"))[..., 3].min() < 255
            if has_alpha:
                img.save(buf, "PNG", optimize=True)
                images[image_index]["mimeType"] = "image/png"
            else:
                img.convert("RGB").save(buf, "JPEG", quality=88, optimize=True)
                images[image_index]["mimeType"] = "image/jpeg"
            if args.red and image_index == base_image:
                red, share = to_crimson(img)
                red.save(args.red, "PNG", optimize=True)
                print(f"red texture: {args.red} ({share * 100:.1f}% of texels recoloured)")
            chunk = buf.getvalue()
            after += len(chunk)
        new_blob += b"\x00" * (-len(new_blob) % 4)
        view["byteOffset"] = len(new_blob)
        view["byteLength"] = len(chunk)
        new_blob += chunk
    if doc.get("buffers"):
        doc["buffers"][0]["byteLength"] = len(new_blob) + (-len(new_blob) % 4)
    write_glb(args.dst, doc, bytes(new_blob))
    print(f"{args.dst}: {len(images)} textures, {before / 1e6:.2f} MB -> {after / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
