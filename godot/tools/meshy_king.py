#!/usr/bin/env python3
"""A far more detailed King for the 3D app icon (0.31.211, Kevin: "make the king higher triangle count so it's more
detail"): his model is ~10.4k triangles with a 512 px texture -- right for a match, faceted and soft in a close-up. Meshy
rebuilds him from four views of himself (tools/render_app_icon.gd VIEWS=1: front, right, back, left, his cleaned-up
textures, flat light, orthographic) at its highest quality: Meshy 7.1 ("latest"), 2k geometry, no remesh (the full
mesh), 4k PBR textures (the gold as metal) guided by the same views. The game's King is unchanged; the icon uses this one.

  python3 tools/meshy_king.py VIEWS_DIR OUT_DIR
      VIEWS_DIR/king_view_<front|right|back|left>.png (transparent) -> set on white at one shared crop, 1024 px;
      OUT_DIR/king_hd.glb, king_hd.png (Meshy's thumbnail), king_hd.json (task id, settings, credits).
Key from MESHY_KEY, else ~/.config/fatebound/meshy_key (never written to the repo).
"""
import base64
import io
import json
import os
import sys
import time
import urllib.request

from PIL import Image

API = "https://api.meshy.ai/openapi/v1"
VIEWS = ("front", "right", "back", "left")


def key():
    k = os.environ.get("MESHY_KEY", "")
    if not k:
        k = open(os.path.expanduser("~/.config/fatebound/meshy_key")).read().strip()
    return k


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": "Bearer " + key(), "Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=120) as f:
        return json.loads(f.read())


def prepared(views_dir, out_dir):
    """The views on white, all cut by the same square round all of them (one scale, the feet on one line)."""
    ims = [Image.open(os.path.join(views_dir, "king_view_%s.png" % v)).convert("RGBA") for v in VIEWS]
    boxes = [im.getbbox() for im in ims]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    side = int(max(x1 - x0, y1 - y0) * 1.12)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    box = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)
    uris = []
    for v, im in zip(VIEWS, ims):
        w = Image.new("RGBA", im.size, (255, 255, 255, 255))
        w.alpha_composite(im)
        w = w.convert("RGB").crop(box).resize((1024, 1024), Image.LANCZOS)
        w.save(os.path.join(out_dir, "king_input_%s.png" % v))
        b = io.BytesIO()
        w.save(b, "PNG")
        uris.append("data:image/png;base64," + base64.b64encode(b.getvalue()).decode())
    return uris


def poll(kind, tid, timeout=2400):
    t0 = time.time()
    while True:
        s = req("GET", "/%s/%s" % (kind, tid))
        if s["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
            return s
        if time.time() - t0 > timeout:
            raise SystemExit("%s %s still %s after %d s" % (kind, tid, s["status"], timeout))
        print("  %s %s %s%%" % (tid, s["status"], s.get("progress", "?")), flush=True)
        time.sleep(15)


def main(views_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    uris = prepared(views_dir, out_dir)
    body = {"image_urls": uris, "ai_model": "latest", "geometry_resolution": "2k", "should_remesh": False,
            "should_texture": True, "enable_pbr": True, "texture_resolution": "4k", "texture_image_urls": uris,
            "image_enhancement": True, "remove_lighting": True, "pose_mode": "", "target_formats": ["glb"]}
    log = {"settings": {k: v for k, v in body.items() if k not in ("image_urls", "texture_image_urls")},
           "inputs": ["king_input_%s.png" % v for v in VIEWS]}
    tid = req("POST", "/multi-image-to-3d", body)["result"]
    log["task"] = tid
    print("multi-image-to-3d", tid, flush=True)
    s = poll("multi-image-to-3d", tid)
    log["status"] = s["status"]
    log["credits"] = s.get("consumed_credits")
    json.dump(log, open(os.path.join(out_dir, "king_hd.json"), "w"), indent=1)
    if s["status"] != "SUCCEEDED":
        raise SystemExit("king: %s %s" % (s["status"], s.get("task_error")))
    urllib.request.urlretrieve(s["model_urls"]["glb"], os.path.join(out_dir, "king_hd.glb"))
    if s.get("thumbnail_url"):
        urllib.request.urlretrieve(s["thumbnail_url"], os.path.join(out_dir, "king_hd.png"))
    print("king done", log)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
    else:
        main(sys.argv[1], sys.argv[2])
