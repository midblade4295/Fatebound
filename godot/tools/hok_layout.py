#!/usr/bin/env python3
"""The Honor of Kings map's layout (0.31.216, Kevin: "the map needs to be redone like the attached image").

Drawn in the Honor of Kings frame -- u right, v up, blue's keep in the bottom-left corner, the square HOK_HALF either
side -- and turned into the game's world coordinates (x = (u - v) / sqrt 2, y = (-u - v) / sqrt 2: the diamond
siege_land.gd describes). Blue's half only: red's is the point mirror; the east jungle is the west's mirror across the
middle line (u <-> v).

  python3 tools/hok_layout.py            preview: /tmp/hok_layout.png (the square as the landscape camera sees it)
  python3 tools/hok_layout.py --apply    and write the constants into siege_land.gd (LANES, EDGE_BLUE, RIDGES_BLUE,
                                         TRAILS_BLUE), moba.gd (TOWERS_BLUE's side lanes, CAMPS_BLUE) and
                                         moba_vision.gd (BRUSH_BLUE); then rebake (tools/bake_land.gd) and run
                                         tests/siege_land_check.gd and tests/path_clear_test.gd
"""
import sys
import math, json
from PIL import Image, ImageDraw
S2 = math.sqrt(2)
H = 78.0
def w(u, v): return ((u - v) / S2, (-u - v) / S2)
def s(x, y): return ((x - y) / S2, (-x - y) / S2)
KC = s(0, 96); KR = 14.0

def arc(c, r, a0, a1, n):
    return [(c[0] + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)), c[1] + r * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]

LG = -67.9   # the side lanes' line
# lane 0 (top), in screen coords
cr = 18.0
top = [(LG, -53.9), (LG, -40), (LG, -20), (LG, 0), (LG, 20), (LG, 40)] + arc((LG + cr, -LG - cr), cr, 180, 90, 4)[0:] + [(-40, -LG), (-20, -LG), (0, -LG), (20, -LG), (40, -LG), (53.9, -LG)]
mid = [(-58, -58), (-40, -40), (-20, -20), (0, 0), (20, 20), (40, 40), (58, 58)]
D = {}
D["lanes_s"] = [top, mid]
# towers (blue) [lane, tier, (u,v)]
TI = 4.6
towers = [[0, 3, (LG + TI, -38.0)], [0, 2, (LG + TI, 0.0)], [0, 1, (LG + TI, 40.0)],
          [2, 3, (-38.0, LG + TI)], [2, 2, (0.0, LG + TI)], [2, 1, (40.0, LG + TI)]]
D["towers_s"] = towers
mid_towers_w = [(4.0, 30.0), (4.0, 54.0), (4.0, 74.5)]
camps = [("archers", (-48, -20)), ("arcane", (-40, 6)), ("pack", (-53, 30)),
         ("archers", (-20, -48)), ("ember", (6, -40)), ("pack", (30, -53))]
POOL_X = 42.0
def river_c(x): return 0.0
pits_w = [(-POOL_X, river_c(-POOL_X)), (POOL_X, river_c(POOL_X))]
# ridges (blue half; screen) -- HoK's curved rock walls. Each: (points, r, look)
ridges = [
    # west jungle (blue's top-left quarter): the buff in a pocket open toward the river and the middle lane, the
    # Archers by the keep with a wall behind them, the Pack under a tree line toward the top lane's corner
    (arc((-40, 6), 9.5, 150, 250, 4), 1.7, "rock"),            # the buff's pocket (its back to the top lane)
    ([(-62, -4), (-58, -11), (-52, -14)], 1.5, "rock"),         # between the lane's way in and the buff
    (arc((-48, -20), 8.0, 230, 320, 3), 1.4, "trees"),          # behind the Archers (toward the keep)
    ([(-26, -14), (-22, -8), (-22, -1)], 1.5, "rock"),           # off the middle lane
    (arc((-53, 30), 8.0, 95, 175, 3), 1.4, "trees"),            # the Pack's back, toward the corner
    # east jungle: the west's mirror across the middle line (u <-> v)
]
west = list(ridges)
for pts, r, look in west:
    ridges.append(([(b, a) for a, b in pts], r, look))
D["ridges_s"] = ridges
brush = [((-73.5, 10.0), 2.8), ((-73.5, 32.0), 2.6), ((-58.0, 40.0), 2.6), ((-30.0, -2.0), 2.4), ((-14.0, -4.0), 2.6),
         ((-46.0, 20.0), 2.4), ((-23.0, 13.0), 2.6), ((-60.0, -30.0), 2.4)]
for (u, v), r in list(brush):
    brush.append(((v, u), r))
D["brush_s"] = brush
trails = [
    [(LG + 3, -20), (-56, -20), (-48, -20), (-38, -20), (-28, -24), (-20, -24)],     # lane - Archers - middle lane
    [(-48, -20), (-36, -10), (-40, 6)],                                           # Archers - buff
    [(-40, 6), (-30, 6), (-18, 2), (-6, -4)],                                     # buff - middle lane
    [(LG + 3, 22), (-58, 26), (-53, 30), (-46.3, 24.4), (-40.7, 21.6), (-38.7, 20.8)],   # lane - Pack - the pit's causeway
    [(-40, 6), (-44, 16), (-50, 24), (-53, 30)],                                  # buff - Pack
]
for t in list(trails):
    trails.append([(v, u) for u, v in t])
D["trails_s"] = trails

def to_w(p): return w(p[0], p[1])

# ---------- the edge (blue half, world): bottom-right corner by the river -> along x + y = L -> round the keep's back ->
# along y - x = L -> top-left corner by the river
L = H * S2
def on_line_xy(y):  # x + y = L
    return (L - y, y)
edge = []
for y in [9.0, 24.0, 40.0, 56.0, 72.0, 86.0]:
    edge.append(on_line_xy(y))
# where the line meets the keep (R 15 from C)
edge.append((15.0, 95.3))
back = []
for a in [20, 50, 75, 90, 105, 130, 160]:
    back.append((15.2 * math.cos(math.radians(a)), 96 + 15.2 * math.sin(math.radians(a))))
edge += back
edge.append((-15.0, 95.3))
for y in [86.0, 72.0, 56.0, 40.0, 24.0, 9.0, 1.5]:
    edge.append((y - L, y))
skip = list(range(6, 6 + len(back) + 1))
D["edge_w"] = edge
D["edge_skip"] = skip

def r1(p): return (round(p[0], 2), round(p[1], 2))
# The river isn't mirrored across the middle line (it's point-symmetric: c(x) = -c(-x)), so on the east side, where it
# swings toward blue, what's near its bank moves up with it (world +y by the difference).
def bank_fix(p):
    x, y = p
    if x > 0 and y > 0:
        dy = 0.0
        near = max(0.0, 1.0 - max(0.0, y - 16.0) / 8.0)
        return (x, y + max(0.0, dy) * near)
    return p
out = {
    "lanes": [[r1(to_w(p)) for p in top], [r1(to_w(p)) for p in mid]],
    "towers": [[l, t, r1(to_w(p))] for l, t, p in towers],
    "camps": [[k, r1(to_w(p))] for k, p in camps],
    "ridges": [[[r1(to_w(p)) for p in pts], r, look] for pts, r, look in ridges],
    "brush": [[r1(bank_fix(to_w(p))), r] for p, r in brush],
    "trails": [[r1(bank_fix(to_w(p))) for p in t] for t in trails],
    "edge": [r1(p) for p in edge], "skip": skip, "L": L,
}
json.dump(out, open("/tmp/hok_layout.json", "w"), indent=0)

# ---------- preview in the HoK frame (screen), both halves ----------
PP = 5
Wd = int(2 * (H + 12) * PP)
img = Image.new("RGB", (Wd, Wd), (110, 110, 105))
d = ImageDraw.Draw(img)
def px(p): return ((p[0] + H + 12) * PP, (H + 12 - p[1]) * PP)
def mir(p): return (-p[0], -p[1])
d.rectangle([px((-H, H)), px((H, -H))], fill=(100, 170, 80))
# river band
for k in range(-120, 121):
    x = k
    y = river_c(x)
    hw = 4.5 + 7.5 * math.exp(-((abs(x) - POOL_X) / 9.0) ** 2)
    a = s(x, y - hw); b = s(x, y + hw)
    d.line([px(a), px(b)], fill=(60, 130, 200), width=PP * 2)
for pc in pits_w:
    d.ellipse([px((s(*pc)[0] - 7, s(*pc)[1] + 7)), px((s(*pc)[0] + 7, s(*pc)[1] - 7))], outline=(40, 40, 40), width=4, fill=(90, 160, 80))
for side in (1, -1):
    def f(p): return p if side == 1 else mir(p)
    for ln in [top, mid]:
        d.line([px(f(p)) for p in ln], fill=(200, 170, 110), width=int(4.2 * PP))
    lane2 = [mir(p) for p in reversed(top)]
    d.line([px(f(p)) for p in lane2], fill=(200, 170, 110), width=int(4.2 * PP))
    for t in trails:
        d.line([px(f(p)) for p in t], fill=(190, 160, 100), width=int(2.6 * PP))
    for pts, r, look in ridges:
        d.line([px(f(p)) for p in pts], fill=(70, 70, 75) if look == "rock" else (40, 90, 40), width=int(2 * r * PP), joint="curve")
    kc = f(KC)
    d.ellipse([px((kc[0] - KR, kc[1] + KR)), px((kc[0] + KR, kc[1] - KR))], outline=(40, 40, 40), width=6, fill=(200, 190, 150))
    col = (60, 110, 230) if side == 1 else (220, 60, 60)
    for l, t, p in towers:
        q = f(p)
        d.ellipse([px((q[0] - 2, q[1] + 2)), px((q[0] + 2, q[1] - 2))], fill=col)
        d.ellipse([px((q[0] - 11.5, q[1] + 11.5)), px((q[0] + 11.5, q[1] - 11.5))], outline=col)
    for p in mid_towers_w:
        q = f(s(*p))
        d.ellipse([px((q[0] - 2, q[1] + 2)), px((q[0] + 2, q[1] - 2))], fill=col)
        d.ellipse([px((q[0] - 11.5, q[1] + 11.5)), px((q[0] + 11.5, q[1] - 11.5))], outline=col)
    for k, p in camps:
        q = f(p)
        c = {"archers": (160, 100, 200), "pack": (160, 100, 200), "arcane": (90, 200, 240), "ember": (240, 140, 50)}[k]
        d.ellipse([px((q[0] - 2.5, q[1] + 2.5)), px((q[0] + 2.5, q[1] - 2.5))], fill=c)
    for p, r in brush:
        q = f(p)
        d.ellipse([px((q[0] - r, q[1] + r)), px((q[0] + r, q[1] - r))], fill=(40, 120, 90))
# edge
ed = [s(*p) for p in edge] + [mir(s(*p)) for p in edge]
d.line([px(p) for p in ed] + [px(ed[0])], fill=(30, 30, 30), width=3)
img.save("/tmp/hok_layout.png")
print("HOK_LAYOUT /tmp/hok_layout.png")


# ---------- the constants ----------
d=json.load(open('/tmp/hok_layout.json'))
def fl(x):
    x=round(x,2)
    if x==0: x=0.0
    s=("%.2f" % x).rstrip('0')
    if s.endswith('.'): s+='0'
    return s
def vv(p): return "Vector2(%s, %s)" % (fl(p[0]), fl(p[1]))
lane0=d['lanes'][0]; mid=d['lanes'][1]
lane2=[(-x,-y) for x,y in reversed(lane0)]
def lst(pts, per=5, ind="\t\t"):
    out=[]
    for i in range(0,len(pts),per):
        out.append(", ".join(vv(p) for p in pts[i:i+per]))
    return (",\n"+ind).join(out)
o=[]
o.append("const LANES := [\n\t[" + lst(lane0) + "],\n\t[" + lst(mid) + "],\n\t[" + lst(lane2) + "],\n]")
o.append("const EDGE_BLUE := [\n\t" + lst(d['edge'],5,"\t") + ",\n]")
o.append("SKIP %s" % d['skip'])
r=["const RIDGES_BLUE := ["]
for pts,rr,look in d['ridges']:
    r.append('\t{"pts": [%s], "r": %s, "look": "%s"},' % (", ".join(vv(p) for p in pts), fl(rr), look))
r.append("]"); o.append("\n".join(r))
t=["const TRAILS_BLUE := ["]
for tr in d['trails']:
    t.append("\t[%s]," % ", ".join(vv(p) for p in tr))
t.append("]"); o.append("\n".join(t))
o.append("TOWERS " + str([[l,tt,vv(p)] for l,tt,p in d['towers']]))
o.append("CAMPS " + str([[k,vv(p)] for k,p in d['camps']]))
o.append("BRUSH " + ", ".join("[%s, %s]" % (vv(p), fl(rr)) for p,rr in d['brush']))
open('/tmp/hok_consts.txt','w').write("\n\n".join(o))


if '--apply' in sys.argv:
    import re, json, os
    G=os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
    C=open('/tmp/hok_consts.txt').read()
    d=json.load(open('/tmp/hok_layout.json'))
    def fl(x):
        x=round(x,2)
        if x==0: x=0.0
        s=("%.2f" % x).rstrip('0')
        if s.endswith('.'): s+='0'
        return s
    def vv(p): return "Vector2(%s, %s)" % (fl(p[0]), fl(p[1]))
    P=G+'scripts/siege/siege_land.gd'
    s=open(P).read()
    for name in ["LANES","EDGE_BLUE","RIDGES_BLUE","TRAILS_BLUE"]:
        blk=re.search(r"const %s := \[.*?\n\]" % name, C, re.S).group(0)
        s=re.sub(r"const %s := \[.*?\n\]" % name, lambda m: blk, s, count=1, flags=re.S)
    open(P,'w').write(s)
    # towers
    P=G+'scripts/siege/moba.gd'
    s=open(P).read()
    T={(l,t):p for l,t,p in d['towers']}
    new=("const TOWERS_BLUE := [[0, 1, %s], [0, 2, %s], [0, 3, %s],\n" % (vv(T[(0,1)]),vv(T[(0,2)]),vv(T[(0,3)])) +
         "\t[1, 1, Vector2(4.0, 30.0)], [1, 2, Vector2(4.0, 54.0)], [1, 3, Vector2(4.0, 74.5)],\n" +
         "\t[2, 1, %s], [2, 2, %s], [2, 3, %s]," % (vv(T[(2,1)]),vv(T[(2,2)]),vv(T[(2,3)])))
    s=re.sub(r"const TOWERS_BLUE := \[\[0, 1.*?\n.*?\n\t\[2, 1, [^\n]*,", lambda m: new, s, count=1, flags=re.S)
    cm={}
    for k,p in d['camps']:
        cm.setdefault(k,[]).append(p)
    order=[("pack",0),("archers",0),("arcane",0),("pack",1),("archers",1),("ember",0)]
    lines=["const CAMPS_BLUE := ["]+['\t{"kind":"%s", "p":%s},' % (k, vv(cm[k][i])) for k,i in order]+["]"]
    s=re.sub(r"const CAMPS_BLUE := \[.*?\n\]", lambda m: "\n".join(lines), s, count=1, flags=re.S)
    open(P,'w').write(s)
    # brush
    P=G+'scripts/siege/moba_vision.gd'
    s=open(P).read()
    br=d['brush']; half=len(br)//2
    def row(items): return ", ".join("[%s, %s]" % (vv(p), fl(r)) for p,r in items)
    txt="const BRUSH_BLUE := [" + row(br[:4]) + ",\n\t" + row(br[4:half]) + ",\n\t" + row(br[half:half+4]) + ",\n\t" + row(br[half+4:]) + "]\n"
    s=re.sub(r"const BRUSH_BLUE := \[.*?\]\]\n", lambda m: txt, s, count=1, flags=re.S)
    open(P,'w').write(s)
    print("applied")
