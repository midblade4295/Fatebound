#!/usr/bin/env python3
"""The Grave Wyrm's model (0.31.166): Meshy's output from Kevin's concept "A" (image-to-3D task
01a14b3e-8210-7263-9815-3097895d4cca, 14k polygons) made into assets/meshy/wyrm/wyrm.glb.

  python3 tools/wyrm_prep.py MESHY.glb assets/meshy/wyrm/wyrm.glb [PLOT.png]

1. Off its base: triangles wholly below CUT (Meshy's units) go, then every piece but the largest (the rocks were loose
   pieces); then only the vertices those triangles use.
2. Turned YAW degrees about +Y so its head faces +Z (the view turns every body so +Z is the way it faces: worked out
   from where its front and back feet stand), feet on y 0, centred on its legs, scaled to HEIGHT metres tall, the
   colour texture down to TEX px.
3. Its limbs painted into the vertex colours for the view's shader (scripts/siege/wyrm_body.gd -- the model has no
   rig): over the mesh's surface (Dijkstra on the welded mesh), everything farther than LIMB_CUT from the torso falls
   apart into eight pieces -- two wings, the neck and head, the tail, four legs -- each named by the extremity in it.
   R wing, G neck, B tail, A legs (128/255 at rest; up to +127/255 on the front-left and back-right legs, down on the
   other pair, which step in turn); each weight rising from 0 where the limb leaves the torso. Prints each limb's
   root, which wyrm_body.gd's WING_L / WING_R / NECK / TAIL are.
"""
import io
import os
import sys

import numpy as np
from PIL import Image
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components, dijkstra

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_building_tex as mbt  # noqa: E402

CUT = -0.37          # Meshy's units: the base's top
YAW = 19.0
HEIGHT = 4.0
TEX = 1024
LIMB_CUT = 0.9       # metres over the surface from the torso


def prep(src):
    g, binc = mbt.read_glb(src)
    binc = bytearray(binc)
    p = g['meshes'][0]['primitives'][0]

    def view(i):
        a = g['accessors'][i]
        bv = g['bufferViews'][a['bufferView']]
        return bv.get('byteOffset', 0) + a.get('byteOffset', 0), a
    po, pa = view(p['attributes']['POSITION'])
    no, na = view(p['attributes']['NORMAL'])
    io_, ia = view(p['indices'])
    pos = np.frombuffer(bytes(binc[po:po + pa['count'] * 12]), np.float32).reshape(-1, 3).astype(np.float64)
    nor = np.frombuffer(bytes(binc[no:no + na['count'] * 12]), np.float32).reshape(-1, 3).astype(np.float64)
    dt = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32}[ia['componentType']]
    idx = np.frombuffer(bytes(binc[io_:io_ + ia['count'] * np.dtype(dt).itemsize]), dt).reshape(-1, 3).astype(np.int64)
    tri = idx[pos[idx][:, :, 1].max(1) >= CUT]
    key = np.round(pos / 1e-4).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    wt = weld[tri]
    n = weld.max() + 1
    A = coo_matrix((np.ones(3 * len(wt)), (np.concatenate([wt[:, 0], wt[:, 1], wt[:, 2]]),
                                           np.concatenate([wt[:, 1], wt[:, 2], wt[:, 0]]))), shape=(n, n))
    _, lab = connected_components(A, directed=False)
    tl = lab[wt[:, 0]]
    ids, cnt = np.unique(tl, return_counts=True)
    tri = tri[tl == ids[np.argmax(cnt)]]
    used = np.unique(tri)
    c, s = np.cos(np.radians(YAW)), np.sin(np.radians(YAW))
    R = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    P = pos @ R.T
    N = nor @ R.T
    U = P[used]
    lo, hi = U[:, 1].min(), U[:, 1].max()
    low = U[U[:, 1] < lo + 0.45 * (hi - lo)]                       # the legs and the body's underside: its middle
    centre = np.array([(low[:, 0].min() + low[:, 0].max()) / 2, lo, (low[:, 2].min() + low[:, 2].max()) / 2])
    P = (P - centre) * (HEIGHT / (hi - lo))
    binc[po:po + pa['count'] * 12] = P.astype(np.float32).tobytes()
    binc[no:no + na['count'] * 12] = N.astype(np.float32).tobytes()
    # only the vertices the kept triangles use, in every attribute
    remap = -np.ones(len(pos), np.int64)
    remap[used] = np.arange(len(used))
    for acc_i in p['attributes'].values():
        a = g['accessors'][acc_i]
        v = g['bufferViews'][a['bufferView']]
        w = {'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        off = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        arr = np.frombuffer(bytes(binc[off:off + a['count'] * w * 4]), np.float32).reshape(-1, w)[used].copy()
        binc[off:off + arr.nbytes] = arr.tobytes()
        a['count'] = int(len(used))
        v['byteLength'] = int(a.get('byteOffset', 0) + arr.nbytes)
        if 'min' in a:
            a['min'] = arr.min(0).tolist()
            a['max'] = arr.max(0).tolist()
    new = remap[tri].reshape(-1).astype(np.uint32 if len(used) > 65535 else np.uint16)
    binc[io_:io_ + new.nbytes] = new.tobytes()
    ia['count'] = int(new.size)
    ia['componentType'] = 5125 if new.dtype == np.uint32 else 5123
    g['bufferViews'][ia['bufferView']]['byteLength'] = int(ia.get('byteOffset', 0) + new.nbytes)
    bv = g['bufferViews'][g['images'][mbt.base_color_image(g)]['bufferView']]
    im = Image.open(io.BytesIO(bytes(binc[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]))).convert('RGB')
    im = im.resize((TEX, TEX), Image.LANCZOS)
    b = io.BytesIO()
    im.save(b, 'JPEG', quality=88)
    return g, binc, b.getvalue()


def ss(a, b, t):
    t = np.clip((t - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def paint(g, binc):
    p = g['meshes'][0]['primitives'][0]
    pos = mbt.accessor(g, binc, p['attributes']['POSITION']).astype(np.float64)
    idx = mbt.accessor(g, binc, p['indices']).reshape(-1, 3).astype(np.int64)
    key = np.round(pos / 1e-4).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    n = weld.max() + 1
    wp = np.zeros((n, 3))
    wp[weld] = pos
    e = np.concatenate([idx[:, [0, 1]], idx[:, [1, 2]], idx[:, [2, 0]]])
    e = weld[e]
    e = e[e[:, 0] != e[:, 1]]
    E = np.unique(np.sort(e, 1), axis=0)
    ln = np.linalg.norm(wp[E[:, 0]] - wp[E[:, 1]], axis=1)
    A = coo_matrix((ln, (E[:, 0], E[:, 1])), shape=(n, n)).tocsr()
    A = A.maximum(A.T)
    x, y, z = wp.T
    low = np.where(y < 0.3)[0]

    def foot(cx, cz):
        return low[np.argmin((x[low] - cx) ** 2 + (z[low] - cz) ** 2)]
    seeds = {'wingL': np.argmin(x), 'wingR': np.argmax(x), 'neck': np.argmax(np.where(y > 2.3, z, -9)),
             'tail': np.argmax(np.where((y < 1.5) & (z < -2.0), x - 0.3 * z, -99)),
             'legFL': foot(-1.0, 2.2), 'legFR': foot(2.1, 1.7), 'legBL': foot(-1.1, -1.5), 'legBR': foot(1.6, -0.9)}
    core = np.where((np.abs(x - 0.3) < 0.5) & (y > 1.3) & (y < 2.5) & (z > -0.9) & (z < 0.7))[0]
    dcore = dijkstra(A, directed=False, indices=core, min_only=True)
    keep = dcore > LIMB_CUT
    ee = E[keep[E[:, 0]] & keep[E[:, 1]]]
    _, lab = connected_components(coo_matrix((np.ones(len(ee)), (ee[:, 0], ee[:, 1])), shape=(n, n)), directed=False)
    assert len({lab[v] for v in seeds.values()}) == len(seeds), 'two limbs joined: change LIMB_CUT'
    limb = {k: (lab == lab[v]) & keep for k, v in seeds.items()}
    d = dcore - LIMB_CUT
    mid = 128.0 / 255.0                              # A's rest: exactly a byte, so it reads back as no leg
    W = np.zeros((n, 4))
    W[:, 3] = mid
    wings = limb['wingL'] | limb['wingR']
    W[wings, 0] = ss(0.0, 0.7, d)[wings]
    W[limb['neck'], 1] = ss(0.0, 1.7, d)[limb['neck']]
    W[limb['tail'], 2] = ss(0.0, 0.9, d)[limb['tail']]
    for k, sgn in [('legFL', 1), ('legBR', 1), ('legFR', -1), ('legBL', -1)]:
        W[limb[k], 3] = mid + (127.0 / 255.0) * sgn * ss(0.2, 1.8, d)[limb[k]]
    for k in seeds:
        m = limb[k] & (d < 0.2)
        print('%-6s %4d vertices, root %s' % (k, limb[k].sum(), np.round(wp[m].mean(0), 2)))
    return W[weld].astype(np.float32), wp, W


def main():
    src, out = sys.argv[1], sys.argv[2]
    g, binc, jpeg = prep(src)
    # (re-read through write_glb so the accessors are packed before painting)
    tmp = out + '.tmp.glb'
    mbt.write_glb(tmp, g, bytes(binc), jpeg)
    g, binc = mbt.read_glb(tmp)
    os.remove(tmp)
    binc = bytearray(binc)
    col, wp, W = paint(g, binc)
    p = g['meshes'][0]['primitives'][0]
    binc += b'\0' * ((-len(binc)) % 4)
    g['bufferViews'].append({'buffer': 0, 'byteOffset': len(binc), 'byteLength': col.nbytes, 'target': 34962})
    binc += col.tobytes()
    g['accessors'].append({'bufferView': len(g['bufferViews']) - 1, 'componentType': 5126, 'count': len(col), 'type': 'VEC4'})
    p['attributes']['COLOR_0'] = len(g['accessors']) - 1
    mbt.write_glb(out, g, bytes(binc), jpeg)
    pos = mbt.accessor(g, binc, p['attributes']['POSITION'])
    print('%d vertices, %d triangles; %.2f x %.2f x %.2f m' % (len(pos), mbt.accessor(g, binc, p['indices']).size // 3,
                                                             np.ptp(pos[:, 0]), np.ptp(pos[:, 1]), np.ptp(pos[:, 2])))
    if len(sys.argv) > 3:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(4, 3, figsize=(27, 30))
        for r, (ch, nm) in enumerate([(0, 'wing'), (1, 'neck'), (2, 'tail'), (3, 'legs')]):
            for a, (i, j, t) in zip(ax[r], [(0, 2, 'top x-z'), (2, 1, 'side z-y'), (0, 1, 'front x-y')]):
                a.scatter(wp[:, i], wp[:, j], s=0.8, c=W[:, ch], cmap='coolwarm' if ch == 3 else 'viridis', vmin=0, vmax=1)
                a.set_aspect('equal')
                a.set_title(nm + ' ' + t)
                a.grid(True)
        plt.tight_layout()
        plt.savefig(sys.argv[3], dpi=40)


if __name__ == '__main__':
    main()
