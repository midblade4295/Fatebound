#!/usr/bin/env python3
"""A character from a T-pose turnaround sheet through Meshy (the pipeline the class bodies went through in 0.31.76-81,
as a tool: the minions, after Kevin's concept picks).

  meshy_character.py split TURNAROUND.png OUTDIR NAME
      cuts the front / side / back views where the sheet is emptiest near each third, each figure cropped and set on a
      white square at ONE shared scale (feet on the same line), 1024 px: OUTDIR/NAME_<front|side|back>.png
  meshy_character.py model OUTDIR NAME [--poly 10000]
      Meshy multi-image-to-3D (latest model, t-pose, image enhancement off, the views also the texture references,
      remeshed to --poly triangles, no PBR), then the auto-rig (24-bone humanoid): OUTDIR/NAME_mesh.glb,
      OUTDIR/NAME_rigged.glb, OUTDIR/NAME.json (task ids, credits). Key from MESHY_KEY (never written to disk).
Then: assets/meshy/<name>/rigged.glb and tools/retarget_meshy.gd (NAME=<name>) for rig.json and the baked animations.
"""
import base64
import json
import os
import sys
import time
import urllib.request

API = "https://api.meshy.ai/openapi/v1"


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": "Bearer " + os.environ["MESHY_KEY"], "Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=120) as f:
        return json.loads(f.read())


def data_uri(p):
    return "data:image/png;base64," + base64.b64encode(open(p, "rb").read()).decode()


def split(sheet, outdir, name):
    from PIL import Image
    import numpy as np
    os.makedirs(outdir, exist_ok=True)
    im = Image.open(sheet).convert("RGB")
    a = np.asarray(im).astype(int)
    W, H = im.size
    ink = (np.abs(255 - a).sum(2) > 40).sum(0)
    cuts = []
    for third in (W // 3, 2 * W // 3):
        lo, hi = third - W // 10, third + W // 10
        seg = ink[lo:hi]
        best = np.where(seg == seg.min())[0]
        cuts.append(lo + int(best[len(best) // 2]))
    xs = [0] + cuts + [W]
    figs = []
    for i in range(3):
        v = im.crop((xs[i], 0, xs[i + 1], H))
        m = np.abs(255 - np.asarray(v).astype(int)).sum(2) > 40
        ys, xx = np.where(m)
        figs.append(v.crop((xx.min(), ys.min(), xx.max() + 1, ys.max() + 1)))
    side = int(max(max(f.size) for f in figs) * 1.1)
    tallest = max(f.height for f in figs)
    for f, view in zip(figs, ["front", "side", "back"]):
        sq = Image.new("RGB", (side, side), (255, 255, 255))
        sq.paste(f, ((side - f.width) // 2, (side - tallest) // 2 + tallest - f.height))
        sq.resize((1024, 1024), Image.LANCZOS).save(os.path.join(outdir, "%s_%s.png" % (name, view)))
    print(name, "cuts", cuts)


def poll(kind, tid, timeout=1500):
    t0 = time.time()
    while True:
        s = req("GET", "/%s/%s" % (kind, tid))
        if s["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
            return s
        if time.time() - t0 > timeout:
            raise SystemExit("%s %s still %s after %d s" % (kind, tid, s["status"], timeout))
        time.sleep(10)


def model(outdir, name, poly=10000, height=1.0):
    views = [os.path.join(outdir, "%s_%s.png" % (name, v)) for v in ("front", "side", "back")]
    uris = [data_uri(p) for p in views]
    body = {"image_urls": uris, "ai_model": "latest", "should_texture": True, "enable_pbr": False,
            "should_remesh": True, "topology": "triangle", "target_polycount": int(poly), "pose_mode": "t-pose",
            "image_enhancement": False, "texture_image_urls": uris, "target_formats": ["glb"]}
    log = {"name": name}
    tid = req("POST", "/multi-image-to-3d", body)["result"]
    log["mesh_task"] = tid
    print(name, "multi-image-to-3d", tid, flush=True)
    s = poll("multi-image-to-3d", tid)
    if s["status"] != "SUCCEEDED":
        raise SystemExit("%s mesh %s: %s" % (name, s["status"], s.get("task_error")))
    log["mesh_credits"] = s.get("consumed_credits")
    urllib.request.urlretrieve(s["model_urls"]["glb"], os.path.join(outdir, name + "_mesh.glb"))
    if s.get("thumbnail_url"):
        urllib.request.urlretrieve(s["thumbnail_url"], os.path.join(outdir, name + "_mesh.png"))
    rid = req("POST", "/rigging", {"input_task_id": tid, "height_meters": float(height)})["result"]
    log["rig_task"] = rid
    print(name, "rigging", rid, flush=True)
    r = poll("rigging", rid)
    if r["status"] != "SUCCEEDED":
        raise SystemExit("%s rig %s: %s" % (name, r["status"], r.get("task_error")))
    log["rig_credits"] = r.get("consumed_credits")
    urllib.request.urlretrieve(r["result"]["rigged_character_glb_url"], os.path.join(outdir, name + "_rigged.glb"))
    json.dump(log, open(os.path.join(outdir, name + ".json"), "w"), indent=1)
    print(name, "done", log)


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        print(__doc__)
    elif a[0] == "split":
        split(a[1], a[2], a[3])
    elif a[0] == "model":
        poly = int(a[a.index("--poly") + 1]) if "--poly" in a else 10000
        height = float(a[a.index("--height") + 1]) if "--height" in a else 1.0
        model(a[1], a[2], poly, height)
    else:
        print(__doc__)
