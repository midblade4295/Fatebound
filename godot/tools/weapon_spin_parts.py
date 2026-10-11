#!/usr/bin/env python3
"""Cut a Meshy weapon's moving pieces into their own nodes so the game can turn them (0.31.103, Kevin: "Can we make
the top of this weapon animate. Like have the rings spins and rotate").

A Meshy weapon is one mesh, but its pieces are often separate connected components (a crystal in a claw, the rings
around it). This writes the same GLB with one node per part: "Body" (everything not named), and each named part
placed at its pivot (the centre of the given components) with its vertices re-expressed about it -- so turning the
node about its own axes turns the piece in place, and at rest the weapon looks (and is held) exactly as before.
weapon_fx.gd's LEGENDARY "spin" turns the nodes by name.

  python3 tools/weapon_spin_parts.py IN.glb --list                  # the components, numbered by size
  python3 tools/weapon_spin_parts.py IN.glb OUT.glb --part Rings:0,3:2 --part Crystal:2
(Rings = components 0 and 3 turning about component 2's centre; Crystal = component 2 about its own.)
Pieces that touch are one component: they move together.
"""
import argparse
import json
import os
import struct
import sys

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

sys.path.insert(0, os.path.dirname(__file__))
import meshy_building_tex as mbt  # noqa: E402  (read_glb / accessor)


def load(path):
    g, binc = mbt.read_glb(path)
    assert len(g["meshes"]) == 1 and len(g["meshes"][0]["primitives"]) == 1 and len(g["nodes"]) == 1, "one mesh, one node"
    node = g["nodes"][0]
    assert not any(k in node for k in ("translation", "rotation", "scale", "matrix")), "the node must be at identity"
    prim = g["meshes"][0]["primitives"][0]
    a = prim["attributes"]
    P = mbt.accessor(g, binc, a["POSITION"]).astype(np.float64)
    N = mbt.accessor(g, binc, a["NORMAL"]).astype(np.float64)
    UV = mbt.accessor(g, binc, a["TEXCOORD_0"]).astype(np.float32)
    I = mbt.accessor(g, binc, prim["indices"]).reshape(-1, 3).astype(np.int64)
    return g, binc, P, N, UV, I


def components(P, I):
    key = np.round(P / 1e-5).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.ravel()
    T = inv[I]
    n = inv.max() + 1
    r = np.concatenate([T[:, 0], T[:, 1], T[:, 2]])
    c = np.concatenate([T[:, 1], T[:, 2], T[:, 0]])
    nc, lab = connected_components(coo_matrix((np.ones(len(r)), (r, c)), shape=(n, n)), directed=False)
    tl = lab[T[:, 0]]
    order = np.argsort(-np.bincount(tl))           # renumber by size
    rank = np.empty_like(order)
    rank[order] = np.arange(len(order))
    return rank[tl], T


def write(path, g, binc, parts):
    # parts: [(name, P_local, N_local, UV, I, translation or None, rotation quaternion or None)]: one node each
    chunks, views, accessors, meshes, nodes = [], [], [], [], []
    pos = 0

    def add(data, target=None):
        nonlocal pos
        pad = (-pos) % 4
        chunks.append(b"\0" * pad)
        pos += pad
        v = {"buffer": 0, "byteOffset": pos, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        chunks.append(data)
        pos += len(data)
        return len(views) - 1

    for name, P, N, UV, I, tr, rot in parts:
        P = P.astype(np.float32)
        acc = {}
        for key, arr, typ in (("POSITION", P, "VEC3"), ("NORMAL", N.astype(np.float32), "VEC3"), ("TEXCOORD_0", UV.astype(np.float32), "VEC2")):
            a = {"bufferView": add(arr.tobytes(), 34962), "componentType": 5126, "count": len(arr), "type": typ}
            if key == "POSITION":
                a["min"] = P.min(0).tolist()
                a["max"] = P.max(0).tolist()
            accessors.append(a)
            acc[key] = len(accessors) - 1
        ind = I.astype(np.uint32).ravel()
        accessors.append({"bufferView": add(ind.tobytes(), 34963), "componentType": 5125, "count": len(ind), "type": "SCALAR"})
        meshes.append({"name": name, "primitives": [{"attributes": acc, "indices": len(accessors) - 1, "mode": 4, "material": 0}]})
        node = {"name": name, "mesh": len(meshes) - 1}
        if tr is not None:
            node["translation"] = [float(v) for v in tr]
        if rot is not None:
            node["rotation"] = rot
        nodes.append(node)
    images = []
    for im in g["images"]:                            # the embedded texture(s), copied after the meshes
        im = dict(im)
        if "bufferView" in im:
            v = g["bufferViews"][im["bufferView"]]
            im["bufferView"] = add(binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]])
        images.append(im)
    body = b"".join(chunks)
    body += b"\0" * ((-len(body)) % 4)
    out = dict(g)
    out.update({"bufferViews": views, "accessors": accessors, "meshes": meshes, "nodes": nodes, "images": images,
                "scenes": [{"nodes": list(range(len(nodes)))}], "scene": 0, "buffers": [{"byteLength": len(body)}]})
    js = json.dumps(out, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(body)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(body), 0x004E4942) + body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--part", action="append", default=[],
                    help="Name:comps[:pivot comps] -- connected components (by size, 0 = most triangles) moved "
                         "together, turning about the centre of the pivot components (default: their own)")
    a = ap.parse_args()
    g, binc, P, N, UV, I = load(a.src)
    tl, _ = components(P, I)
    C = P[I].mean(1)
    if a.list or not a.part:
        for k in range(tl.max() + 1):
            sel = tl == k
            print("comp %d: %d tris, centre %s, lo %s hi %s" % (k, sel.sum(), C[sel].mean(0).round(3),
                                                                 C[sel].min(0).round(3), C[sel].max(0).round(3)))
        return
    lab = np.zeros(len(I), int)
    specs = []
    for i, spec in enumerate(a.part):
        bits = spec.split(":")
        comps = [int(x) for x in bits[1].split(",")]
        lab[np.isin(tl, comps)] = i + 1
        pivot_comps = [int(x) for x in bits[2].split(",")] if len(bits) > 2 else comps
        specs.append((bits[0], C[np.isin(tl, pivot_comps)].mean(0)))
    parts = []

    def part(name, sel, pivot=None):
        used, inv = np.unique(I[sel].ravel(), return_inverse=True)
        Pl = P[used] - (pivot if pivot is not None else 0.0)
        parts.append((name, Pl, N[used], UV[used], inv.reshape(-1, 3), pivot, None))
        print("%-10s %5d tris%s" % (name, sel.sum(), "" if pivot is None else ", pivot %s" % np.round(pivot, 3)))

    part("Body", lab == 0)
    for i, (name, pivot) in enumerate(specs):
        part(name, lab == i + 1, pivot)
    if a.out:
        write(a.out, g, binc, parts)
        print("wrote", a.out)


if __name__ == "__main__":
    main()
