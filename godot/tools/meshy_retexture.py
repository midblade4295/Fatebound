#!/usr/bin/env python3
"""A hero skin's texture through Meshy's retexture (0.31.186, Kevin: "I want the same IAP system as league of legends"
-- hero skins): the hero's own rigged model (assets/meshy/HERO/rigged.glb) repainted from a prompt with its own UV
layout kept (enable_original_uv), so the new base colour fits the model the game already has -- same mesh, same rig,
same silhouette, only the paint changes.

  MESHY_KEY=... python3 tools/meshy_retexture.py HERO OUTDIR "prompt"
      -> OUTDIR/HERO.jpg (the base colour, 2048, the source the game's 1024 skin is made from: tools/build_skins.py),
         OUTDIR/HERO_meshy_preview.png (Meshy's preview), and HERO's entry in OUTDIR/tasks.json (task id, credits, the
         prompt). 10 credits a skin. The key comes from the environment and is never written down.
"""
import base64
import io
import json
import os
import sys
import time
import urllib.request

API = "https://api.meshy.ai/openapi/v1"
GODOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": "Bearer " + os.environ["MESHY_KEY"], "Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=300) as f:
        return json.loads(f.read())


def main():
    from PIL import Image
    hero, out, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out, exist_ok=True)
    glb = open(os.path.join(GODOT, "assets", "meshy", hero, "rigged.glb"), "rb").read()
    t = req("POST", "/retexture", {"model_url": "data:application/octet-stream;base64," + base64.b64encode(glb).decode(),
                                   "text_style_prompt": prompt, "enable_original_uv": True, "enable_pbr": False,
                                   "target_formats": ["glb"]})
    tid = t["result"]
    print(hero, "task", tid, flush=True)
    while True:
        time.sleep(10)
        s = req("GET", "/retexture/" + tid)
        if s["status"] in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            break
    if s["status"] != "SUCCEEDED":
        sys.exit("%s: %s %s" % (hero, s["status"], s.get("task_error")))
    raw = urllib.request.urlopen(s["texture_urls"][0]["base_color"], timeout=300).read()
    Image.open(io.BytesIO(raw)).convert("RGB").save(os.path.join(out, hero + ".jpg"), "JPEG", quality=90)
    if s.get("thumbnail_url"):
        prev = urllib.request.urlopen(s["thumbnail_url"], timeout=300).read()
        Image.open(io.BytesIO(prev)).save(os.path.join(out, hero + "_meshy_preview.png"))
    tp = os.path.join(out, "tasks.json")
    tasks = json.load(open(tp)) if os.path.exists(tp) else {}
    tasks[hero] = {"task": tid, "credits": s.get("consumed_credits"), "prompt": prompt}
    json.dump(tasks, open(tp, "w"), indent=1)
    print(hero, "done", s.get("consumed_credits"), "credits")


if __name__ == "__main__":
    main()
