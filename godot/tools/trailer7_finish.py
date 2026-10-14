#!/usr/bin/env python3
"""Fatebound trailer 7 -- the finishing pass over the cut picture (tools/trailer7_edit.py makes cut.mp4 and plan.json).

Per frame: a filmic grade (a gentle S-curve, cool shadows, warm highlights, a touch less saturation, a vignette); the
title cards (Cinzel, the game's serif: fading in while they slowly grow); the white flash on the final hit; the title
card itself -- Home's logo (assets/ui/v2/logo_base.webp + logo_king.webp, laid out as scripts/app/title_logo.gd lays
them) slamming in over the darkened, blurred "titlebg" plate, the tied-up King swinging hard from the impact and settling
into the logo's own gentle swing, a glint of light across the gold, embers rising; and the 2.39:1 letterbox.

    python3 tools/trailer7_finish.py --cut /tmp/trailer7/cut.mp4 --plan /tmp/trailer7/plan.json --out /tmp/trailer7/finished.mkv
    (--only T0:T1 renders just that stretch to check it; --still T saves one frame as a PNG)
Needs numpy, Pillow, OpenCV, fontTools (+ brotli: the fonts ship as woff2), ffmpeg.
"""
import argparse, json, math, os, re, subprocess, sys
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
W, H, FPS = 1920, 1080, 30
BAR = 138                                   # 2.39:1 inside 16:9

# ---------- the logo, as title_logo.gd lays it out ----------
def logo_consts():
    src = open(os.path.join(ROOT, "scripts", "app", "title_logo.gd")).read()
    def v2(name):
        m = re.search(r"const %s := Vector2\(([-\d.]+), ([-\d.]+)\)" % name, src)
        return np.array([float(m.group(1)), float(m.group(2))])
    def f(name):
        return float(re.search(r"const %s := ([-\d.]+)" % name, src).group(1))
    return {"BASE": v2("BASE"), "KING_AT": v2("KING_AT"), "KING_SIZE": v2("KING_SIZE"), "PIVOT": v2("PIVOT"),
            "SWING_DEG": f("SWING_DEG"), "PERIOD": f("PERIOD")}


def load_rgba(path):
    im = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0
    im[..., :3] *= im[..., 3:4]                # premultiplied
    return im


def font_path(name):
    out = "/tmp/trailer7/fonts/%s.ttf" % name
    if not os.path.exists(out):
        from fontTools.ttLib import TTFont
        os.makedirs(os.path.dirname(out), exist_ok=True)
        f = TTFont(os.path.join(ROOT, "assets", "fonts", name + ".woff2"))
        f.flavor = None
        f.save(out)
    return out


# ---------- cards ----------
def card_image(text, size, tracking=0.16, color=(246, 232, 200)):
    """The card's text, premultiplied RGBA at 1.15x (it grows into its size), with a warm glow behind it."""
    f = ImageFont.truetype(font_path("Cinzel-Black"), int(size * 1.15))
    adv = [f.getlength(ch) for ch in text]
    gap = size * 1.15 * tracking
    tw = int(sum(adv) + gap * (len(text) - 1)) + 80
    th = int(size * 1.15 * 1.6) + 80
    txt = Image.new("L", (tw, th), 0)
    d = ImageDraw.Draw(txt)
    x = 40
    for ch, a in zip(text, adv):
        d.text((x, 40), ch, font=f, fill=255)
        x += a + gap
    a = np.asarray(txt).astype(np.float32) / 255.0
    # a dark halo first (it reads on a bright sky), then a faint warm glow, then the letters
    dark = np.asarray(txt.filter(ImageFilter.GaussianBlur(size * 0.30))).astype(np.float32) / 255.0
    glow = np.asarray(txt.filter(ImageFilter.GaussianBlur(size * 0.12))).astype(np.float32) / 255.0
    col = np.array(color, np.float32) / 255.0
    gcol = np.array([1.0, 0.70, 0.35], np.float32)
    da = np.clip(dark * 1.6, 0, 1) * 0.62
    rgb = np.zeros(a.shape + (3,), np.float32)
    alpha = da
    ga = np.clip(glow * 1.2, 0, 1) * 0.35
    rgb = rgb * (1 - ga[..., None]) + gcol * ga[..., None]
    alpha = alpha * (1 - ga) + ga
    rgb = rgb * (1 - a[..., None]) + col * a[..., None]
    alpha = alpha * (1 - a) + a
    out = np.dstack([rgb, alpha]).astype(np.float32)
    return out


def over(dst, src, x0, y0):
    """Premultiplied src over dst (float RGB) at (x0, y0), clipped."""
    h, w = src.shape[:2]
    x1, y1 = x0 + w, y0 + h
    cx0, cy0, cx1, cy1 = max(0, x0), max(0, y0), min(dst.shape[1], x1), min(dst.shape[0], y1)
    if cx0 >= cx1 or cy0 >= cy1:
        return
    s = src[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
    d = dst[cy0:cy1, cx0:cx1]
    d[:] = s[..., :3] + d * (1.0 - s[..., 3:4])


def scaled(img, k):
    h, w = img.shape[:2]
    return cv2.resize(img, (max(1, int(w * k)), max(1, int(h * k))), interpolation=cv2.INTER_AREA if k < 1 else cv2.INTER_LINEAR)


# ---------- grade ----------
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
RAD = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2) / math.sqrt(2)
VIGNETTE = (1.0 - 0.32 * np.clip(RAD, 0, 1) ** 2.2)[..., None].astype(np.float32)


def grade(f):
    lum = (f[..., 0] * 0.2126 + f[..., 1] * 0.7152 + f[..., 2] * 0.0722)[..., None]
    s = f * f * (3.0 - 2.0 * f)                                   # S-curve
    f = f * 0.78 + s * 0.22
    f = lum + (f - lum) * 0.93                                    # a touch less saturation
    sh = (1.0 - lum) ** 2
    hi = lum ** 2
    f = f + sh * np.array([-0.012, 0.010, 0.030], np.float32) + hi * np.array([0.030, 0.012, -0.022], np.float32)
    return np.clip(f * VIGNETTE, 0.0, 1.0)


# ---------- the title ----------
class Title:
    def __init__(self, width=1180):
        c = logo_consts()
        self.c = c
        base = load_rgba(os.path.join(ROOT, "assets", "ui", "v2", "logo_base.webp"))
        king = load_rgba(os.path.join(ROOT, "assets", "ui", "v2", "logo_king.webp"))
        self.k = width / c["BASE"][0]                           # the logo's scale on screen at rest
        self.M = 140                                            # margin round the logo for the swing
        bw, bh = int(c["BASE"][0]), int(c["BASE"][1])
        self.base = np.zeros((bh + 2 * self.M, bw + 2 * self.M, 4), np.float32)
        self.base[self.M:self.M + bh, self.M:self.M + bw] = base
        self.king = king
        self.king_at = c["KING_AT"] + self.M
        self.pivot = c["PIVOT"] + self.M
        # its shadow, soft, under the whole thing
        sa = cv2.GaussianBlur(self.base[..., 3], (0, 0), 18)
        self.shadow = sa
        rng = np.random.default_rng(77)
        n = 140
        self.embers = {"x": rng.uniform(0, W, n), "y0": rng.uniform(H * 0.3, H * 1.3, n), "v": rng.uniform(25, 80, n),
                       "r": rng.uniform(1.2, 3.4, n), "ph": rng.uniform(0, 6.28, n), "sw": rng.uniform(8, 30, n)}

    def king_angle(self, tt):
        # The impact sets him swinging hard; he settles into the logo's own swing (SWING_DEG each way, PERIOD).
        amp = self.c["SWING_DEG"] + 19.0 * math.exp(-tt / 1.5)
        return amp * math.sin(2 * math.pi * tt / self.c["PERIOD"])

    def layer(self, tt):
        """The logo at time tt after the hit: premultiplied RGBA at rest scale (before the slam's scale)."""
        img = self.base.copy()
        ang = self.king_angle(tt)
        # rotate the King about the knot: Control rotation is clockwise on screen for a positive angle
        kh, kw = self.king.shape[:2]
        piv_local = self.c["PIVOT"] - self.c["KING_AT"]
        R = cv2.getRotationMatrix2D((float(piv_local[0]), float(piv_local[1])), -ang, 1.0)
        R[0, 2] += self.king_at[0]
        R[1, 2] += self.king_at[1]
        kimg = cv2.warpAffine(self.king, R, (img.shape[1], img.shape[0]), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0, 0))
        img = kimg + img * (1.0 - kimg[..., 3:4])                # the King hangs in front of the scroll
        # a glint across the gold: a soft diagonal band sweeping left to right
        if 0.9 < tt < 2.2:
            u = (tt - 0.9) / 1.3
            h, w = img.shape[:2]
            gy, gx = np.mgrid[0:h, 0:w].astype(np.float32)
            pos = -0.3 * w + u * 1.6 * w
            band = np.exp(-(((gx + 0.45 * gy) - pos) / (0.07 * w)) ** 2)
            img[..., :3] += (band * img[..., 3] * 0.55)[..., None] * np.array([1.0, 0.93, 0.75], np.float32)
        return img

    def compose(self, bg, tt, t_left):
        """bg: the plate frame (float RGB). tt: seconds since the hit. t_left: seconds to the end."""
        # the plate: darker, softer, warm
        sh = 14.0 * math.exp(-tt / 0.35) if tt < 1.5 else 0.0
        dx, dy = sh * math.sin(tt * 61.0), sh * math.cos(tt * 47.0)
        f = cv2.GaussianBlur(bg, (0, 0), 3.2)
        f = f * 0.42 + np.array([0.035, 0.018, 0.0], np.float32)
        # embers
        e = self.embers
        y = (e["y0"] - e["v"] * (tt + 3.0)) % (H * 1.1)
        x = e["x"] + e["sw"] * np.sin(tt * 0.9 + e["ph"])
        glow = np.zeros((H // 2, W // 2), np.float32)
        for xi, yi, ri, ph in zip(x, y, e["r"], e["ph"]):
            a = 0.55 + 0.45 * math.sin(tt * 3.1 + ph * 3.0)
            cv2.circle(glow, (int(xi / 2), int(yi / 2)), max(1, int(ri / 2 + 0.5)), a, -1, lineType=cv2.LINE_AA)
        glow = cv2.resize(cv2.GaussianBlur(glow, (0, 0), 1.2), (W, H))
        f = f + glow[..., None] * np.array([1.0, 0.55, 0.18], np.float32) * 0.85
        # the logo: slams in from big and see-through, a small bounce, the shake
        if tt < 0.2:
            m = 1.0 + 0.55 * (1.0 - tt / 0.2) ** 2
            al = min(1.0, tt / 0.12)
        else:
            m = 1.0 - 0.025 * math.sin((tt - 0.2) * 18.0) * math.exp(-(tt - 0.2) * 6.0)
            al = 1.0
        lay = self.layer(tt)
        k = self.k * m
        lay = scaled(lay, k)
        cx, cy = W / 2 + dx, H / 2 - 8 + dy
        ox = int(cx - (self.M + self.c["BASE"][0] / 2) * k)
        oy = int(cy - (self.M + self.c["BASE"][1] / 2) * k)
        shadow = scaled(self.shadow, k)
        s4 = np.zeros(shadow.shape + (4,), np.float32)
        s4[..., 3] = shadow * 0.75 * al
        over(f, s4, ox + int(10 * k), oy + int(22 * k))
        over(f, lay * al, ox, oy)
        if t_left < 1.3:
            f = f * max(0.0, t_left / 1.3)
        return f


def frames_of(path, t0=0.0, n=None):
    cmd = ["ffmpeg", "-v", "error", "-ss", "%.3f" % t0, "-i", path]
    if n is not None:
        cmd += ["-frames:v", str(n)]
    cmd += ["-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    while True:
        b = p.stdout.read(W * H * 3)
        if len(b) < W * H * 3:
            break
        yield np.frombuffer(b, np.uint8).reshape(H, W, 3).astype(np.float32) / 255.0
    p.wait()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cut", default="/tmp/trailer7/cut.mp4")
    ap.add_argument("--plan", default="/tmp/trailer7/plan.json")
    ap.add_argument("--out", default="/tmp/trailer7/finished.mkv")
    ap.add_argument("--only", default="")
    ap.add_argument("--still", type=float, default=-1.0)
    a = ap.parse_args()
    plan = json.load(open(a.plan))
    total = plan["total"]
    t_hit = plan["title"]                                     # the hit: the flash, the title
    cards = []
    for c in plan["cards"]:
        cards.append((c["t0"], c["t1"], card_image(c["text"], c.get("size", 72)), c.get("y", 0.5), c.get("snap", False)))
    title = Title()
    t0, t1 = 0.0, total
    if a.only:
        t0, t1 = [float(x) for x in a.only.split(":")]
    if a.still >= 0:
        t0, t1 = a.still, a.still + 0.5 / FPS
    n0 = int(round(t0 * FPS))
    n1 = int(round(t1 * FPS))
    out = None
    if a.still < 0:
        out = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H),
                                "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-crf", "15", "-preset", "medium",
                                "-pix_fmt", "yuv420p", a.out], stdin=subprocess.PIPE)
    fi = n0
    for f in frames_of(a.cut, n0 / FPS, n1 - n0):
        t = fi / FPS
        if t >= t_hit:
            f = title.compose(f, t - t_hit, total - t)
        f = grade(f)
        for (c0, c1, img, yrel, snap) in cards:
            if c0 <= t < c1:
                life = (t - c0) / (c1 - c0)
                fin, fout = (0.05, 0.12) if snap else (0.35, 0.5)          # (a snap card: on the beat, on black)
                al = min(1.0, (t - c0) / fin, (c1 - t) / fout)
                al = max(0.0, al) ** 1.4
                k = (1.0 + (0.09 if snap else 0.06) * life) / 1.15
                im = scaled(img, k) * al
                over(f, im, int(W / 2 - im.shape[1] / 2), int(H * yrel - im.shape[0] / 2))
        # the flash on the hit (it hides the cut into the title)
        if t_hit - 0.05 <= t < t_hit + 0.9:
            u = t - t_hit
            fl = 1.0 if u < 0.07 else math.exp(-(u - 0.07) / 0.22)
            fl = fl if u >= 0 else 0.6
            f = f + (np.array([1.0, 0.96, 0.86], np.float32) - f) * fl
        # fade up from black at the start
        if t < plan.get("fade_in_end", 0.0):
            f = f * max(0.0, (t - plan.get("fade_in_start", 0.0)) / max(0.01, plan["fade_in_end"] - plan.get("fade_in_start", 0.0)))
        f[:BAR] = 0.0
        f[H - BAR:] = 0.0
        o = (np.clip(f, 0, 1) * 255.0 + 0.5).astype(np.uint8)
        if a.still >= 0:
            Image.fromarray(o).save("/tmp/trailer7/finish_still_%.2f.png" % a.still)
            print("STILL", a.still)
            return
        out.stdin.write(o.tobytes())
        fi += 1
        if fi % 150 == 0:
            print("frame", fi, "t=%.1f" % t, flush=True)
    out.stdin.close()
    out.wait()
    print("FINISHED", a.out, fi - n0, "frames")


if __name__ == "__main__":
    main()
