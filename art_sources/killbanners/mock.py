#!/usr/bin/env python3
"""Kill banner concepts for Kevin (Fatebound 5v5): each banner on a real phone screen (450 x 1000 logical, 2x),
over the game's own HUD, drawn with the game's fonts, portraits and icons."""
import os
import sys

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
A = "file://" + os.path.join(HERE, "a") + "/"
OUT = os.path.join(HERE, "out")

CSS = """
@font-face { font-family: LG; src: url('%(a)sLuckiestGuy-Regular.ttf'); }
@font-face { font-family: NX; src: url('%(a)sNunito-ExtraBold.woff2'); }
@font-face { font-family: CZ; src: url('%(a)sCinzel-Black.woff2'); }
* { box-sizing: border-box; margin: 0; padding: 0; }
body { width: 450px; height: 1000px; overflow: hidden; background: #000; font-family: NX; color: #fff; position: relative; }
.bg { position: absolute; inset: 0; background: url('%(a)s%(bg)s') center/cover; }
.dim { position: absolute; inset: 0; background: radial-gradient(ellipse at 50%% 34%%, rgba(0,0,0,0.28), rgba(0,0,0,0) 62%%); }
.c { position: absolute; left: 50%%; transform: translateX(-50%%); }
.stroke { text-shadow: 0 3px 0 #1a0c02, 2px 2px 0 #1a0c02, -2px -2px 0 #1a0c02, 2px -2px 0 #1a0c02, -2px 2px 0 #1a0c02,
  0 -2px 0 #1a0c02, 0 2px 0 #1a0c02, 2px 0 0 #1a0c02, -2px 0 0 #1a0c02; }
.gtxt { background: linear-gradient(#fff6c8 10%%, #ffd65a 48%%, #d08a14 52%%, #ffcf5a 90%%); -webkit-background-clip: text;
  background-clip: text; color: transparent; }
.stxt { background: linear-gradient(#ffffff 10%%, #e6edf4 48%%, #8fa2b6 52%%, #dfe8f1 90%%); -webkit-background-clip: text;
  background-clip: text; color: transparent; }
.rtxt { background: linear-gradient(#ffe2b0 10%%, #ff9a3a 48%%, #d8321a 55%%, #ff7a3a 92%%); -webkit-background-clip: text;
  background-clip: text; color: transparent; }
.btxt { background: linear-gradient(#ffffff 10%%, #c8f2ff 45%%, #3aa8d8 55%%, #9fe6ff 92%%); -webkit-background-clip: text;
  background-clip: text; color: transparent; }
.title { position: relative; display: inline-block; white-space: nowrap; }
.title .sh { position: absolute; inset: 0; color: #1a0c02; -webkit-text-stroke: 7px #1a0c02; z-index: 0; }
.title .fg { position: relative; z-index: 1; }

/* the kill ribbon: killer, "has slain", victim */
.rib { position: absolute; left: 50%%; transform: translateX(-50%%); height: 58px; }
.rib .edge { position: absolute; inset: 0; clip-path: polygon(14px 0, calc(100%% - 14px) 0, 100%% 50%%, calc(100%% - 14px) 100%%, 14px 100%%, 0 50%%);
  background: linear-gradient(#f6e2a4, #a77a2c 45%%, #6b4a14 55%%, #d8b25e); }
.rib .face { position: absolute; inset: 3px; clip-path: polygon(13px 0, calc(100%% - 13px) 0, 100%% 50%%, calc(100%% - 13px) 100%%, 13px 100%%, 0 50%%);
  background: linear-gradient(#1d3242, #0a141d 60%%, #101d28); }
.rib.silver .edge { background: linear-gradient(#ffffff, #aab8c6 45%%, #5d6b78 55%%, #dbe4ec); }
.rib.red .face { background: linear-gradient(#3a1a1a, #160909 60%%, #241010); }
.rib .line { position: absolute; left: 0; right: 0; top: 17px; text-align: center; font-size: 17px; white-space: nowrap; }
.rib .line .v { font-family: CZ; font-size: 11px; color: #f2d18d; letter-spacing: 1px; margin: 0 7px; position: relative; top: -1px; }
.blue { color: #7fe0ff; } .red { color: #ff8f6a; } .you { color: #ffd65a; }
.por { position: absolute; top: -9px; width: 76px; height: 76px; border-radius: 50%%; padding: 3px;
  background: linear-gradient(#fff2c0, #b0812c 50%%, #6b4a14); box-shadow: 0 4px 10px rgba(0,0,0,0.6); }
.por .in { width: 100%%; height: 100%%; border-radius: 50%%; overflow: hidden; border: 3px solid #5fd2f0; background: #0b1a24; }
.por .in img { width: 100%%; height: 100%%; object-fit: cover; }
.por.r .in { border-color: #ff7b52; background: #24100a; }
.por.dead .in img { filter: grayscale(1) brightness(0.62) contrast(1.1); }
.por .sk { position: absolute; right: -6px; bottom: -4px; width: 30px; height: 30px; }
.por.l { left: -38px; } .por.rt { right: -38px; }

.pips { position: absolute; left: 50%%; transform: translateX(-50%%); display: flex; gap: 5px; padding: 4px 10px; border-radius: 14px;
  background: rgba(10,8,20,0.82); border: 2px solid #b0812c; }
.pips img { width: 24px; height: 24px; }
.cap { position: absolute; left: 0; right: 0; text-align: center; font-family: CZ; font-size: 12px; letter-spacing: 1.5px; color: #f2d18d; }
.chip { position: absolute; left: 50%%; transform: translateX(-50%%); display: flex; align-items: center; gap: 6px; padding: 4px 16px 4px 8px;
  border-radius: 22px; background: linear-gradient(#3a2608, #1a1004); border: 2px solid #e0b048; box-shadow: 0 3px 8px rgba(0,0,0,0.6); }
.chip img { width: 34px; height: 34px; }
.chip span { font-family: LG; font-size: 28px; }
.vig { position: absolute; inset: 0; box-shadow: inset 0 0 90px 30px rgba(255,190,60,0.55), inset 0 0 22px 6px rgba(255,230,140,0.8);
  pointer-events: none; }
.spark { position: absolute; width: 6px; height: 6px; border-radius: 50%%; background: #fff3b0; box-shadow: 0 0 10px 4px rgba(255,210,90,0.8); }
"""


def portrait(hid, side, dead=False, pos="l"):
    sk = '<img class="sk" src="%sskull.png">' % A if dead else ""
    return '<div class="por %s %s %s"><div class="in"><img src="%sdefault_%s.png"></div>%s</div>' % (
        pos, "r" if side == "red" else "", "dead" if dead else "", A, hid, sk)


def ribbon(top, w, killer, khid, kside, victim, vhid, vside, style="", verb="has slain"):
    return ('<div class="rib %s" style="top:%dpx; width:%dpx"><div class="edge"></div><div class="face"></div>'
            '<div class="line"><span class="%s">%s</span><span class="v">%s</span><span class="%s">%s</span></div>%s%s</div>') % (
        style, top, w, kside, killer, verb.upper(), vside, victim,
        portrait(khid, "blue" if kside in ("blue", "you") else "red", False, "l"),
        portrait(vhid, "red" if vside == "red" else "blue", True, "rt"))


def title(text, size, cls, top, font="LG", spacing=1):
    return ('<div class="c" style="top:%dpx; text-align:center"><div class="title" style="font-family:%s; font-size:%dpx; letter-spacing:%dpx">'
            '<span class="sh">%s</span><span class="fg %s">%s</span></div></div>') % (top, font, size, spacing, text, cls, text)


def pips(n, top, icon="skull"):
    return '<div class="pips" style="top:%dpx">%s</div>' % (top, "".join('<img src="%s%s.png">' % (A, icon) for _ in range(n)))


# ---------------- SVG pieces ----------------
def svg(w, h, body, top, extra=""):
    return ('<svg class="c" style="top:%dpx; %s" width="%d" height="%d" viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg">%s</svg>'
            % (top, extra, w, h, w, h, body))


GRADS = """
<defs>
 <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff2c0"/><stop offset="0.45" stop-color="#d9a640"/>
  <stop offset="0.55" stop-color="#8a5e18"/><stop offset="1" stop-color="#f0c060"/></linearGradient>
 <linearGradient id="silver" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="0.45" stop-color="#b8c6d4"/>
  <stop offset="0.55" stop-color="#5d6b78"/><stop offset="1" stop-color="#e2ebf2"/></linearGradient>
 <linearGradient id="crimson" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b3202a"/><stop offset="0.6" stop-color="#6e0d16"/>
  <stop offset="1" stop-color="#3e050b"/></linearGradient>
 <linearGradient id="navy" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#22384a"/><stop offset="1" stop-color="#0a141d"/></linearGradient>
 <linearGradient id="royal" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5a2a8a"/><stop offset="0.6" stop-color="#2a0f48"/>
  <stop offset="1" stop-color="#14062a"/></linearGradient>
 <linearGradient id="blue" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a8ac0"/><stop offset="0.6" stop-color="#0f3c62"/>
  <stop offset="1" stop-color="#071c32"/></linearGradient>
 <linearGradient id="char" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a2a22"/><stop offset="0.6" stop-color="#1a100c"/>
  <stop offset="1" stop-color="#0c0606"/></linearGradient>
 <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#fff2b0" stop-opacity="0.9"/>
  <stop offset="1" stop-color="#ffb030" stop-opacity="0"/></radialGradient>
 <radialGradient id="redglow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#ff7040" stop-opacity="0.8"/>
  <stop offset="1" stop-color="#ff3010" stop-opacity="0"/></radialGradient>
 <radialGradient id="blueglow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#9fe6ff" stop-opacity="0.85"/>
  <stop offset="1" stop-color="#2a8ac0" stop-opacity="0"/></radialGradient>
</defs>"""


def swallow(w, h, fill, rim, notch=22, y0=0):
    """a banner with swallowtail ends, rimmed"""
    p = "M0,{y0} L{w},{y0} L{w2},{ym} L{w},{y1} L0,{y1} L{n},{ym} Z".format(
        y0=y0, w=w, w2=w - notch, ym=y0 + h / 2, y1=y0 + h, n=notch)
    q = "M6,{a} L{w6},{a} L{wn},{ym} L{w6},{b} L6,{b} L{n6},{ym} Z".format(
        a=y0 + 5, w6=w - 6, wn=w - notch - 4, ym=y0 + h / 2, b=y0 + h - 5, n6=notch + 4)
    return ('<path d="%s" fill="url(#%s)" stroke="#1a0c02" stroke-width="3"/><path d="%s" fill="url(#%s)"/>'
            '<path d="%s" fill="none" stroke="url(#%s)" stroke-width="2.5"/>' % (p, rim, p, fill, q, rim))


def shield(cx, top, w, h, fill, rim):
    """a heraldic shield (flat top, pointed bottom)"""
    l, r = cx - w / 2, cx + w / 2
    p = ("M{l},{t} L{r},{t} L{r},{m} Q{r},{b1} {cx},{b} Q{l},{b1} {l},{m} Z").format(
        l=l, r=r, t=top, m=top + h * 0.48, b1=top + h * 0.86, b=top + h, cx=cx)
    i = 9
    q = ("M{l},{t} L{r},{t} L{r},{m} Q{r},{b1} {cx},{b} Q{l},{b1} {l},{m} Z").format(
        l=l + i, r=r - i, t=top + i, m=top + h * 0.48, b1=top + h * 0.84 - 4, b=top + h - i * 1.6, cx=cx)
    return ('<path d="%s" fill="url(#%s)" stroke="#1a0c02" stroke-width="4"/><path d="%s" fill="url(#%s)"/>'
            '<path d="%s" fill="none" stroke="url(#%s)" stroke-width="3"/>' % (p, rim, q, fill, q, rim))


def laurel(cx, cy, r, side, n=8, color="#e0b048"):
    """a laurel branch: a stem arcing up one side (side -1 left, 1 right), leaves in pairs along it"""
    import math
    pts = []
    for i in range(n + 1):
        a = math.radians(250 - i * (150.0 / n)) if side < 0 else math.radians(-70 + i * (150.0 / n))
        pts.append((cx + r * math.cos(a) * 1.0, cy - r * math.sin(a) * 0.92))
    stem = "M" + " L".join("%.1f,%.1f" % p for p in pts)
    out = ['<path d="%s" fill="none" stroke="#1a0c02" stroke-width="6" stroke-linecap="round"/>' % stem,
           '<path d="%s" fill="none" stroke="url(#gold)" stroke-width="3" stroke-linecap="round"/>' % stem]
    for i in range(1, n + 1):
        (x0, y0), (x1, y1) = pts[i - 1], pts[i]
        ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
        for k in (-1, 1):
            rot = ang + k * 38
            lx = x1 + 9 * math.cos(math.radians(rot))
            ly = y1 + 9 * math.sin(math.radians(rot))
            out.append('<ellipse cx="%.1f" cy="%.1f" rx="10" ry="4.6" fill="url(#gold)" stroke="#1a0c02" stroke-width="1.4" '
                       'transform="rotate(%.1f %.1f %.1f)"/>' % (lx, ly, rot, lx, ly))
    return "".join(out)


def wing(cx, cy, side, scale=1.0, rim="gold"):
    s = side
    feathers = []
    for i in range(5):
        L = (70 - i * 9) * scale
        y = cy - 18 * scale + i * 11 * scale
        x0 = cx + s * 6
        feathers.append('<path d="M{x0},{y} Q{xm},{ym} {x1},{y1} Q{xm2},{ym2} {x0},{y2} Z" fill="url(#{rim})" stroke="#1a0c02" stroke-width="2"/>'.format(
            x0=x0, y=y, xm=x0 + s * L * 0.5, ym=y - 16 * scale, x1=x0 + s * L, y1=y - 6 * scale - i * 2 * scale,
            xm2=x0 + s * L * 0.55, ym2=y + 6 * scale, y2=y + 9 * scale, rim=rim))
    return "".join(reversed(feathers))


def rays(cx, cy, r, n=18, color="#ffd65a", op=0.35):
    import math
    out = []
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = a0 + math.pi / n * 0.8
        out.append('<path d="M{cx},{cy} L{x0:.1f},{y0:.1f} L{x1:.1f},{y1:.1f} Z" fill="{c}" opacity="{o}"/>'.format(
            cx=cx, cy=cy, x0=cx + r * math.cos(a0), y0=cy + r * math.sin(a0), x1=cx + r * math.cos(a1), y1=cy + r * math.sin(a1), c=color, o=op))
    return "".join(out)


def drop(cx, cy, s=1.0):
    return ('<path d="M{cx},{t} C{a},{b} {c},{d} {cx},{e} C{f},{d} {g},{b} {cx},{t} Z" fill="#e02a30" stroke="#2a0204" stroke-width="2.5"/>'
            '<ellipse cx="{hx}" cy="{hy}" rx="{rx}" ry="{ry}" fill="#ff9a9a" opacity="0.8"/>').format(
        cx=cx, t=cy - 22 * s, a=cx + 4 * s, b=cy - 10 * s, c=cx + 17 * s, d=cy + 6 * s, e=cy + 20 * s, f=cx - 17 * s, g=cx - 4 * s,
        hx=cx - 6 * s, hy=cy + 4 * s, rx=3.5 * s, ry=6 * s)


# ---------------- the banners ----------------
def page(bg, body, vignette=False):
    return ("<html><head><style>%s</style></head><body><div class='bg'></div><div class='dim'></div>%s%s</body></html>"
            % (CSS % {"a": A, "bg": bg}, body, "<div class='vig'></div>" if vignette else ""))


K = dict(killer="Midblade", khid="knight", victim="Bot Nora", vhid="mage")


def b_kill():
    return page("bg95.png", ribbon(300, 330, "Midblade", "knight", "you", "Bot Nora", "mage", "red"))


def b_slain():
    return page("bg95.png", ribbon(300, 330, "Bot Gideon", "golem", "red", "You", "knight", "you", style="red"))


def b_ally():
    return page("bg95.png", ribbon(300, 330, "Bot Petra", "druid", "blue", "Bot Hilda", "rogue", "red"))


def b_first_blood():
    s = svg(400, 150, GRADS + swallow(392, 76, "crimson", "gold", 26, 44)
            + '<circle cx="200" cy="40" r="36" fill="url(#glow)"/>'
            + '<circle cx="200" cy="44" r="30" fill="url(#crimson)" stroke="#1a0c02" stroke-width="3"/>'
            + '<circle cx="200" cy="44" r="27" fill="none" stroke="url(#gold)" stroke-width="3.5"/>'
            + drop(200, 46, 0.95)
            + ''.join('<path d="M%d,82 q%d,-10 %d,-2 q%d,8 %d,0" fill="none" stroke="url(#gold)" stroke-width="2.5"/>' % (x, d * 9, d * 18, d * 9, d * 18)
                      for x, d in ((150, -1), (250, 1))), 226, "")
    body = (s + '<img class="c" src="%sswords.png" style="top:214px; width:110px; opacity:0.95; z-index:-1">' % A
            + title("FIRST BLOOD", 34, "gtxt", 278, "CZ", 2)
            + ribbon(344, 320, "Midblade", "knight", "you", "Bot Nora", "mage", "red"))
    # (the crossed swords sit behind the medallion: drawn first)
    body = '<img class="c" src="%sswords.png" style="top:206px; width:120px; opacity:0.95">' % A + s + title("FIRST BLOOD", 34, "gtxt", 280, "CZ", 2) \
        + ribbon(350, 320, "Midblade", "knight", "you", "Bot Nora", "mage", "red")
    return page("bg95.png", body)


def b_double():
    s = svg(420, 70, GRADS + swallow(400, 56, "navy", "silver", 22, 7), 270, "")
    body = (s + title("DOUBLE KILL", 40, "stxt", 274, "LG", 1) + pips(2, 240)
            + ribbon(346, 340, "Midblade", "knight", "you", "Bot Nora", "mage", "red", "silver"))
    return page("bg95.png", body)


def b_triple():
    s = svg(440, 80, GRADS + wing(70, 40, -1, 0.62) + wing(370, 40, 1, 0.62) + swallow(330, 58, "navy", "gold", 22, 11).replace(
        "M0,", "M0,").replace("<path", '<path transform="translate(55,0)"'), 266, "")
    body = (s + title("TRIPLE KILL", 44, "gtxt", 270, "LG", 1) + pips(3, 232)
            + ribbon(350, 350, "Midblade", "knight", "you", "Bot Magnus", "ranger", "red"))
    return page("bg95.png", body)


def b_quadra():
    s = svg(440, 320, GRADS + '<circle cx="220" cy="140" r="150" fill="url(#glow)" opacity="0.55"/>'
            + laurel(220, 150, 138, -1, 9) + laurel(220, 150, 138, 1, 9)
            + shield(220, 34, 200, 196, "royal", "gold")
            + ''.join('<image href="%sskull.png" x="%d" y="%d" width="40" height="40"/>' % (A, x, y)
                      for x, y in ((136, 82), (176, 64), (224, 64), (264, 82)))
            + '<image href="%scrown.png" x="184" y="112" width="72" height="72"/>' % A
            + swallow(400, 70, "crimson", "gold", 26, 196).replace("<path", '<path transform="translate(20,0)"'), 120, "")
    body = (s + title("QUADRA KILL", 48, "gtxt", 324, "LG", 1)
            + ribbon(424, 350, "Midblade", "knight", "you", "Bot Ivo", "rogue", "red"))
    return page("bg300.png", body)


def b_penta():
    s = svg(450, 400, GRADS + rays(225, 160, 260, 22, "#ffd65a", 0.28) + '<circle cx="225" cy="160" r="170" fill="url(#glow)" opacity="0.7"/>'
            + wing(130, 150, -1, 1.5) + wing(320, 150, 1, 1.5)
            + laurel(225, 165, 150, -1, 10) + laurel(225, 165, 150, 1, 10)
            + shield(225, 74, 220, 200, "crimson", "gold")
            + ''.join('<image href="%sskull.png" x="%d" y="%d" width="40" height="40"/>' % (A, x, y)
                      for x, y in ((132, 140), (164, 118), (205, 110), (246, 118), (278, 140)))
            + '<image href="%scrown.png" x="166" y="-8" width="118" height="118"/>' % A
            + swallow(430, 80, "royal", "gold", 28, 234).replace("<path", '<path transform="translate(10,0)"'), 128, "")
    sp = "".join('<div class="spark" style="left:%dpx; top:%dpx; transform:scale(%.1f)"></div>' % (x, y, k)
                 for x, y, k in ((60, 230, 1.2), (390, 210, 1.0), (40, 470, 0.8), (410, 430, 1.3), (110, 160, 0.7), (350, 500, 0.9),
                                 (225, 128, 1.0), (300, 150, 0.6), (150, 500, 0.7)))
    body = (s + sp + title("PENTAKILL", 56, "gtxt", 368, "LG", 2)
            + ribbon(482, 360, "Midblade", "knight", "you", "Bot Greta", "priest", "red"))
    return page("bg300.png", body, vignette=True)


def b_ace():
    s = svg(440, 230, GRADS + '<circle cx="220" cy="100" r="120" fill="url(#blueglow)" opacity="0.6"/>'
            + wing(130, 96, -1, 1.15, "silver") + wing(310, 96, 1, 1.15, "silver")
            + shield(220, 20, 170, 190, "blue", "gold"), 180, "")
    heroes = [("mage", "Nora"), ("ranger", "Magnus"), ("rogue", "Ivo"), ("priest", "Greta"), ("golem", "Gideon")]
    row = "".join(('<div style="position:relative; width:58px; height:58px; border-radius:50%%; padding:2px; '
                   'background:linear-gradient(#fff2c0,#b0812c 50%%,#6b4a14)"><div style="width:100%%; height:100%%; border-radius:50%%; '
                   'overflow:hidden; border:2px solid #ff7b52"><img src="%sdefault_%s.png" style="width:100%%; height:100%%; object-fit:cover; '
                   'filter:grayscale(1) brightness(0.6)"></div><img src="%sskull.png" style="position:absolute; right:-6px; bottom:-4px; width:24px"></div>')
                  % (A, h, A) for h, _ in heroes)
    body = (s + title("ACE", 86, "btxt", 226, "LG", 3)
            + '<div class="c" style="top:408px; display:flex; gap:8px; padding:8px 12px; border-radius:40px; background:rgba(8,14,24,0.85); '
              'border:2px solid #b0812c">%s</div>' % row
            + '<div class="cap" style="top:488px; font-size:13px">ALL FIVE ENEMIES SLAIN</div>'
            + '<div class="cap" style="top:508px; font-family:NX; font-size:14px; letter-spacing:0; color:#ffd65a">Midblade struck the last blow</div>')
    return page("bg300.png", body)


def b_shutdown():
    s = svg(440, 170, GRADS + '<circle cx="220" cy="62" r="70" fill="url(#redglow)" opacity="0.7"/>'
            + swallow(410, 74, "char", "gold", 26, 70).replace("<path", '<path transform="translate(15,0)"')
            + '<image href="%scrown.png" x="180" y="2" width="80" height="80"/>' % A
            + '<path d="M214,10 L224,30 L212,42 L228,62 L218,80" fill="none" stroke="#1a0c02" stroke-width="5"/>'
            + '<path d="M214,10 L224,30 L212,42 L228,62 L218,80" fill="none" stroke="#ff5a2a" stroke-width="2"/>', 196, "")
    body = (s + title("SHUTDOWN", 42, "rtxt", 278, "CZ", 2)
            + ribbon(366, 330, "Midblade", "knight", "you", "Bot Hilda", "barbarian", "red", "", "shut down")
            + '<div class="chip" style="top:440px"><img src="%scoin.png"><span class="gtxt">+1000</span></div>' % A
            + '<div class="c" style="top:488px; padding:3px 10px; border-radius:10px; background:rgba(10,8,20,0.8); font-size:12px; '
              'color:#e8dcc0; white-space:nowrap">300 kill + 700 bounty</div>')
    return page("bg95.png", body)


def b_board():
    def badge(x, y, n):
        return ('<div style="position:absolute; left:%dpx; top:%dpx; display:flex; align-items:center; gap:2px; padding:1px 6px 1px 2px; '
                'border-radius:10px; background:linear-gradient(#ffe58a,#d59a1c 55%%,#9a6410); border:1.5px solid #3a2205; '
                'box-shadow:0 2px 4px rgba(0,0,0,0.6)"><img src="%scoin.png" style="width:14px; height:14px">'
                '<span style="font-family:LG; font-size:12px; color:#3a2205; position:relative; top:1px">%d</span></div>') % (x, y, A, n)
    body = (badge(17, 295, 250) + badge(17, 685, 300) + badge(17, 367, 150)
            + '<div class="c" style="top:850px; width:400px; padding:10px 14px; border-radius:14px; background:rgba(8,12,22,0.88); '
              'border:2px solid #b0812c; font-size:13px; line-height:1.45; color:#e8dcc0; text-align:center">'
              '<span style="color:#ffd65a">BOUNTY</span> on a hero\'s portrait once it reaches 150 gold, in steps of 50. '
              'His killer is paid it (up to 700, on top of the 300 for the kill); a behind team\'s bounties count for less.</div>')
    return ("<html><head><style>%s</style></head><body><div class='bg'></div>%s</body></html>"
            % (CSS % {"a": A, "bg": "board.png"}, body))


SHOTS = [("01_kill", b_kill), ("02_kill_ally", b_ally), ("03_you_slain", b_slain), ("04_first_blood", b_first_blood),
         ("05_double", b_double), ("06_triple", b_triple), ("07_quadra", b_quadra), ("08_penta", b_penta), ("09_ace", b_ace),
         ("10_shutdown", b_shutdown), ("11_bounty_board", b_board)]

if __name__ == "__main__":
    only = sys.argv[1:]
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 450, "height": 1000}, device_scale_factor=2)
        for name, fn in SHOTS:
            if only and name not in only:
                continue
            html = os.path.join(OUT, name + ".html")
            open(html, "w").write(fn())
            pg.goto("file://" + html)
            pg.wait_for_timeout(250)
            pg.screenshot(path=os.path.join(OUT, name + ".png"))
            print("wrote", name)
        b.close()
