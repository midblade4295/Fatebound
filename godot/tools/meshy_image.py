#!/usr/bin/env python3
"""2D art through Meshy's image API (0.31.106: the shop's pack art; ElevenLabs' credits had run out).

  meshy_image.py gen OUT.png "PROMPT" [--ref REF.png ...] [--model gpt-image-2-5-sunburst] [--aspect 1:1] [--bg 0|1]
      one image; with --ref it is image-to-image (the references steer the design and style: up to 5, sent as data
      URIs), else text-to-image; --bg 1 (default) asks Meshy to remove the background (a transparent PNG).
      Prints the task id and the credits used. Key from MESHY_KEY (never written to disk).
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
    ext = os.path.splitext(p)[1].lower().lstrip(".")
    mime = {"jpg": "jpeg", "jpeg": "jpeg", "png": "png", "webp": "webp"}[ext]
    return "data:image/%s;base64,%s" % (mime, base64.b64encode(open(p, "rb").read()).decode())


def gen(out, prompt, refs, model="gpt-image-2-5-sunburst", aspect="1:1", bg=True, timeout=600):
    body = {"ai_model": model, "prompt": prompt, "aspect_ratio": aspect, "remove_background": bool(bg)}
    kind = "text-to-image"
    if refs:
        kind = "image-to-image"
        body["reference_image_urls"] = [data_uri(p) for p in refs]
    tid = req("POST", "/" + kind, body)["result"]
    print(os.path.basename(out), kind, "task", tid, flush=True)
    t0 = time.time()
    while True:
        s = req("GET", "/%s/%s" % (kind, tid))
        if s["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
            break
        if time.time() - t0 > timeout:
            raise SystemExit("%s still %s" % (out, s["status"]))
        time.sleep(4)
    if s["status"] != "SUCCEEDED":
        raise SystemExit("%s %s: %s" % (out, s["status"], s.get("task_error")))
    urllib.request.urlretrieve(s["image_urls"][0], out)
    print(os.path.basename(out), "done", s.get("consumed_credits"), "credits", flush=True)


def main():
    a = sys.argv[1:]
    if not a or a[0] != "gen":
        raise SystemExit(__doc__)
    out, prompt = a[1], a[2]
    refs, opt = [], {}
    i = 3
    while i < len(a):
        if a[i] == "--ref":
            refs.append(a[i + 1])
        else:
            opt[a[i][2:]] = a[i + 1]
        i += 2
    gen(out, prompt, refs, opt.get("model", "gpt-image-2-5-sunburst"), opt.get("aspect", "1:1"), opt.get("bg", "1") != "0")


if __name__ == "__main__":
    main()
