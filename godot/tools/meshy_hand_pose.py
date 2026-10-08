#!/usr/bin/env python3
"""Curl the fingers of a Meshy-rigged character (0.31.77, Kevin on the Worker: "The hand needs to close around the
handle to properly grab it. Also the fingers on other hand should be slightly bent so it looks more natural").

Meshy's auto-rig has no finger bones (24 bones: the hand is one bone), and its characters come in a T-pose with flat,
open hands. So the hands are posed in the mesh itself, in its bind pose: each finger vertex (past the knuckle line) is
turned about three joints -- knuckle, middle, tip -- and its normal and tangent with it; the thumb is turned from its
base. Skin weights stay (the whole hand follows the hand bone), so every baked animation still fits.

  grip  (the weapon hand): a fist (joints 75/80/30 degrees by default), thumb turned in and down. The handle goes
        where the closed hand hides it best seen from the side (the chunky fingers fold right against the palm: no
        hole to pass it through -- like the KayKit fists), at least 0.3 handle radii under the knuckles' palm side.
        rig.json's hand slot moves there (its turn kept) and is also written as "grip_r"/"grip_l", which
        retarget_meshy.gd keeps when it re-writes rig.json.
  relax (the other hand): fingers slightly bent (20/30/20), thumb a little.

Usage: meshy_hand_pose.py in.glb out.glb rig.json --grip r --relax l --knuckle-r 0.12 --knuckle-l 0.105
         [--grip-angles A B C] [--relax-angles A B C] [--hinge 0.45] [--handle 0.07] [--thumb-z 0.07]
  in.glb must be Meshy's ORIGINAL rigged GLB (posing twice bends twice): git history has it. rig.json is updated in
    place (fit and slots from retarget_meshy.gd).
  --knuckle-<r|l>: the knuckle line, metres (bind space) past the wrist along the forearm -> wrist direction, read off
    the hand renders (where the fingers leave the glove/palm).
  --handle: the held weapon's handle radius in KayKit metres (axe_1handed: 0.065-0.075 round the grip).
  --thumb-z: thumb vertices are the hand's vertices this far forward (+Z, bind metres) of the wrist, short of the
    knuckles.
  HAND_DEBUG=<png>: saves the side silhouette with the handle's disc.
"""
import argparse
import json
import struct

import numpy as np

from meshy_building_tex import read_glb


def view(g, binc, i):
    a = g["accessors"][i]
    bv = g["bufferViews"][a["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
    dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a["componentType"]]
    if bv.get("byteStride", 0) not in (0, n * np.dtype(dt).itemsize):
        raise SystemExit("interleaved accessor %d: not handled" % i)
    o = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return o, np.frombuffer(binc, dtype=dt, count=a["count"] * n, offset=o).reshape(a["count"], n).copy()


def rot(axis, ang):
    axis = axis / np.linalg.norm(axis)
    k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + np.sin(ang) * k + (1 - np.cos(ang)) * (k @ k)


def smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def grip_centre(P, g, binc, prim, wr, u, hand, d_lo, d_hi, zt, y_top, r, px=0.001):
    """Where the handle (radius r) is best hidden in the closed hand, seen from the side (d along the hand, y up):
    the centre, at least 0.3 r under the knuckles' palm side (y_top), whose disc the hand's side silhouette (thumb
    left out) covers most. Chunky Meshy fingers fold right against the palm -- there is no hole to pass it through, so
    the handle goes into the fist like the KayKit fists' handles do."""
    from scipy import ndimage
    from PIL import Image, ImageDraw
    import os
    _, I = view(g, binc, prim["indices"])
    I = I.reshape(-1, 3).astype(int)
    d = (P - wr) @ u
    y = P[:, 1] - wr[1]
    z = P[:, 2] - wr[2]
    keep = hand[I].all(1) & (z[I] < zt).all(1)
    y_lo, y_hi = -0.2, 0.08
    x0 = d_lo - 0.06
    W_ = int((d_hi + 0.06 - x0) / px)
    H_ = int((y_hi - y_lo) / px)
    im = Image.new("L", (W_, H_), 0)
    dr = ImageDraw.Draw(im)
    for t in I[keep]:
        dr.polygon([((d[k] - x0) / px, (y_hi - y[k]) / px) for k in t], fill=255)
    solid = ndimage.binary_closing(np.asarray(im) > 0, iterations=2)
    rp = int(round(r / px))
    yy, xx = np.mgrid[-rp:rp + 1, -rp:rp + 1]
    disc = (xx * xx + yy * yy) <= rp * rp
    best = (-1.0, 0, 0)
    for cy in np.arange(y_top - 1.2 * r, y_top - 0.3 * r, 0.002):
        for cd in np.arange(d_lo, d_hi, 0.002):
            ix, iy = int((cd - x0) / px), int((y_hi - cy) / px)
            win = solid[iy - rp:iy + rp + 1, ix - rp:ix + rp + 1]
            if win.shape != disc.shape:
                continue
            cov = float((win & disc).sum()) / disc.sum()
            if cov > best[0]:
                best = (cov, cd, cy)
    if os.environ.get("HAND_DEBUG"):
        dbg = np.stack([solid * 200] * 3, -1).astype(np.uint8)
        ix, iy = int((best[1] - x0) / px), int((y_hi - best[2]) / px)
        sub = dbg[iy - rp:iy + rp + 1, ix - rp:ix + rp + 1]
        sub[disc, 2] = 255
        Image.fromarray(dbg).resize((W_ * 3, H_ * 3), Image.NEAREST).save(os.environ["HAND_DEBUG"])
    return np.array([best[1], best[2], best[0]])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("rig")
    ap.add_argument("--grip", choices=["r", "l"], default=None)
    ap.add_argument("--relax", choices=["r", "l"], default=None)
    ap.add_argument("--knuckle-r", type=float, required=True)
    ap.add_argument("--knuckle-l", type=float, required=True)
    ap.add_argument("--grip-angles", type=float, nargs=3, default=[75.0, 80.0, 30.0], help="knuckle, middle, tip joint bends (deg)")
    ap.add_argument("--relax-angles", type=float, nargs=3, default=[20.0, 30.0, 20.0])
    ap.add_argument("--hinge", type=float, default=0.45, help="the joints' height in the finger, 0 palm side .. 1 back")
    ap.add_argument("--handle", type=float, default=0.07, help="the held handle's radius, KayKit metres")
    ap.add_argument("--thumb-z", type=float, default=0.07)
    ap.add_argument("--grip-thumb", type=float, nargs=2, default=[15.0, 25.0], help="thumb turn toward the fingers, then down (deg)")
    ap.add_argument("--relax-thumb", type=float, nargs=2, default=[8.0, 15.0])
    a = ap.parse_args()

    g, binc = read_glb(a.inp)
    binc = bytearray(binc)
    prim = g["meshes"][0]["primitives"][0]
    at = prim["attributes"]
    po, P = view(g, binc, at["POSITION"])
    no, N = view(g, binc, at["NORMAL"])
    to, T = view(g, binc, at["TANGENT"]) if "TANGENT" in at else (None, None)
    _, J = view(g, binc, at["JOINTS_0"])
    _, W = view(g, binc, at["WEIGHTS_0"])
    P = P.astype(np.float64)
    N = N.astype(np.float64)
    skin = g["skins"][0]
    names = [g["nodes"][j]["name"] for j in skin["joints"]]
    _, ibm = view(g, binc, skin["inverseBindMatrices"])
    BIND = np.linalg.inv(ibm.reshape(-1, 4, 4).transpose(0, 2, 1).astype(np.float64))
    rig = json.load(open(a.rig))
    fit = float(rig["fit"])

    for side, mode in [(a.grip, "grip"), (a.relax, "relax")]:
        if side is None:
            continue
        bone = ("Right" if side == "r" else "Left") + "Hand"
        hi = names.index(bone)
        fi = names.index(("Right" if side == "r" else "Left") + "ForeArm")
        wh = sum(np.where(J[:, k] == hi, W[:, k], 0.0) for k in range(4))
        B = BIND[hi]
        wr = B[:3, 3]
        u = wr - BIND[fi][:3, 3]
        u[1] = 0.0                                          # (the T-pose arm is level; keep the curl in a vertical plane)
        u /= np.linalg.norm(u)
        up = np.array([0.0, 1.0, 0.0])
        d = (P - wr) @ u
        y = P[:, 1] - wr[1]
        z = P[:, 2] - wr[2]                                 # +Z: forward, for both hands
        dk = a.knuckle_r if side == "r" else a.knuckle_l
        hand = wh > 0.5
        fing = hand & (d > dk)
        near = hand & (d > dk) & (d < dk + 0.015)
        y_fb = float(y[near].min())                         # the fingers' palm side at the knuckles
        y_ft = float(y[near].max())                         # ... and their backs
        L = float(d[fing].max()) - dk                       # finger length
        side_axis = np.cross(u, up)                         # the joints' hinge axis (turning u towards -Y is negative)
        # Fingers: three joints (knuckle, middle, tip) along each finger, hinged a little under the finger's middle (the
        # palm side folds into the fist, the back stays rounded); each joint's bend eases in (see below). The tip joint first, then the middle, then
        # the knuckle (each about where it was on the straight hand: a joint moves with those nearer the palm).
        angles = a.grip_angles if mode == "grip" else a.relax_angles
        joints = [(0.0, angles[0]), (0.42 * L, angles[1]), (0.72 * L, angles[2])]
        y_piv = y_fb + a.hinge * (y_ft - y_fb)
        idx = np.nonzero(fing)[0]
        s = d[idx] - dk
        Rtot = np.repeat(np.eye(3)[None], len(idx), 0)
        Q = P[idx].copy()
        for n_, (js_, ang) in enumerate(reversed(joints)):
            piv = wr + u * (dk + js_) + up * y_piv
            # (the knuckle bends over the finger's first 12 mm -- the glove before it stays put; the others over +-4 mm)
            t = smooth(s / 0.012) if js_ == 0.0 else smooth((s - js_ + 0.004) / 0.008)
            for k in range(len(idx)):
                if t[k] <= 0.0:
                    continue
                R = rot(side_axis, -np.radians(ang) * t[k])
                Q[k] = piv + R @ (Q[k] - piv)
                Rtot[k] = R @ Rtot[k]
        P[idx] = Q
        for k, jj in enumerate(idx):
            N[jj] = Rtot[k] @ N[jj]
            if T is not None:
                T[jj, :3] = Rtot[k] @ T[jj, :3].astype(np.float64)
        # Thumb: towards the fingers (about Y) then down (about the forearm direction), from its base.
        thumb = hand & (z > a.thumb_z) & (d < dk)
        if thumb.any():
            tz0 = a.thumb_z
            base = np.array([wr[0], wr[1], wr[2]]) + u * float(np.median(d[thumb])) + np.array([0.0, float(np.median(y[thumb])), tz0])
            yaw_deg, down_deg = a.grip_thumb if mode == "grip" else a.relax_thumb
            for j in np.nonzero(thumb)[0]:
                t = smooth((z[j] - tz0) / 0.02)             # the bend eases in over its first 2 cm
                # +Z towards +u: about +Y for a hand whose u is -X (right), about -Y for +X (left)
                R1 = rot(np.cross(np.array([0.0, 0.0, 1.0]), u), np.radians(yaw_deg) * t)
                R2 = rot(np.array([1.0, 0.0, 0.0]), np.radians(down_deg) * t)      # +Z towards -Y
                R = R2 @ R1
                P[j] = base + R @ (P[j] - base)
                N[j] = R @ N[j]
                if T is not None:
                    T[j, :3] = R @ T[j, :3].astype(np.float64)
        print("%s hand (%s): %d finger verts, %d thumb verts, knuckles %.3f, finger %.3f long, palm side %.3f..%.3f" %
              (bone, mode, int(fing.sum()), int(thumb.sum()), dk, L, y_fb, y_ft))
        if mode == "grip":
            # The weapon's handle goes through the hole the fingers close round: the largest empty circle in the hand's
            # side view (d, y) of the middle fingers, enclosed by the palm and the fingers. The hand slot moves there.
            hc = grip_centre(P, g, binc, prim, wr, u, hand, d_lo=dk - 0.03, d_hi=dk + 0.04, zt=a.thumb_z, y_top=y_fb, r=a.handle / fit)
            hw = wr + u * hc[0] + up * hc[1]
            key = "slot_" + side
            sl = rig[key]
            loc = np.linalg.inv(B) @ np.array([hw[0], hw[1], hw[2], 1.0])
            old = np.array(sl[9:12])
            sl[9:12] = [float(v) for v in loc[:3]]
            rig["grip_" + side] = sl[9:12]
            print("  handle through (d %.3f, y %.3f), %.0f %% of it hidden in the hand (side view); %s origin %s -> %s (bone units)" %
                  (hc[0], hc[1], hc[2] * 100, key, old.round(3).tolist(), np.round(loc[:3], 3).tolist()))

    N /= np.linalg.norm(N, axis=1, keepdims=True)
    binc[po:po + P.size * 4] = P.astype(np.float32).tobytes()
    binc[no:no + N.size * 4] = N.astype(np.float32).tobytes()
    if T is not None:
        binc[to:to + T.size * 4] = T.astype(np.float32).tobytes()
    pa = g["accessors"][at["POSITION"]]
    pa["min"] = [float(v) for v in P.min(0)]
    pa["max"] = [float(v) for v in P.max(0)]
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    bb = bytes(binc) + b"\0" * ((4 - len(binc) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(bb)
    with open(a.out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<I", len(js)) + b"JSON" + js)
        f.write(struct.pack("<I", len(bb)) + b"BIN\0" + bb)
    json.dump(rig, open(a.rig, "w"))


if __name__ == "__main__":
    main()
