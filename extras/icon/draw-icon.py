"""Draws the War Drum project icon: a lit war drum with two mallets, a gold rim and a carved title.

Usage: python draw-icon.py path/to/Cinzel.ttf
(Cinzel is an open font: fonts.google.com/specimen/Cinzel. Needs pillow and numpy.)
Writes WarDrum-icon-1024.png and WarDrum-icon-400.png next to this file."""
import math, os, sys
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

CINZEL = sys.argv[1] if len(sys.argv) > 1 else "Cinzel.ttf"
S = 1200                    # the icon is composed at 1200 x 1200
K = 2                       # ... and the artwork is painted at twice that, then scaled down
N = S * K
rng = np.random.default_rng(7)

yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
xx /= K
yy /= K


def blur(a, r):
    """Gaussian blur of a float array (H x W or H x W x 3), radius in icon units."""
    if a.ndim == 2:
        im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
        return np.asarray(im.filter(ImageFilter.GaussianBlur(r * K)), dtype=np.float32) / 255
    return np.dstack([blur(a[..., i], r) for i in range(3)])


def mask(draw_fn):
    """A soft-edged mask painted with PIL drawing calls, as a float array 0..1."""
    im = Image.new("L", (N, N), 0)
    draw_fn(ImageDraw.Draw(im))
    return np.asarray(im, dtype=np.float32) / 255


def P(*pts):
    return [(x * K, y * K) for x, y in pts]


def over(img, color, m):
    """Paints color (3-vector or H x W x 3) over img where the mask is set."""
    m = m[..., None]
    return img * (1 - m) + np.asarray(color, dtype=np.float32) * m


# ---------------------------------------------------------------- background
CX = 600
d = np.hypot(xx - CX, (yy - 430) * 1.1)
img = np.zeros((N, N, 3), np.float32)
img += np.array([7, 10, 20], np.float32) / 255                               # near-black navy
img += np.array([20, 30, 58], np.float32) / 255 * np.clip(1 - d / 760, 0, 1)[..., None] ** 1.5
fire = np.clip(1 - d / 430, 0, 1) ** 2.2                                     # warm light behind the drum
img += np.array([255, 120, 30], np.float32) / 255 * (fire * 0.9)[..., None]
# faint shafts of light from the upper left
shaft = (np.sin((xx * 0.9 + yy * 0.55) / 34.0) * 0.5 + 0.5) ** 6 * np.clip(1 - np.hypot(xx - 330, yy - 250) / 520, 0, 1)
img += np.array([255, 170, 80], np.float32) / 255 * (blur(shaft, 6) * 0.10)[..., None]

# ---------------------------------------------------------------- the drum's geometry
TOP_Y, BOT_Y = 395.0, 650.0          # centres of the top and bottom ellipses
RX_T, RX_B = 300.0, 246.0
RY_T, RY_B = 92.0, 76.0


def rx_at(y):
    t = np.clip((y - TOP_Y) / (BOT_Y - TOP_Y), 0, 1)
    return RX_T + (RX_B - RX_T) * t


def ellipse_box(cy, rx, ry):
    return [(CX - rx) * K, (cy - ry) * K, (CX + rx) * K, (cy + ry) * K]


def cylinder(y0, y1, grow=0.0):
    """Mask of the drum's side between two heights (front of the lower ellipse included)."""
    r0, r1 = float(rx_at(np.float32(y0))) + grow, float(rx_at(np.float32(y1))) + grow
    ry0, ry1 = RY_T * r0 / RX_T, RY_T * r1 / RX_T

    def fn(dr):
        dr.polygon(P((CX - r0, y0), (CX + r0, y0), (CX + r1, y1), (CX - r1, y1)), fill=255)
        dr.ellipse(ellipse_box(y1, r1, ry1), fill=255)
        dr.ellipse(ellipse_box(y0, r0, ry0), fill=255)
    return mask(fn)


u = np.clip((xx - CX) / rx_at(yy), -1.2, 1.2)                 # -1 .. 1 across the drum at this height
lit = np.clip(1 - ((u + 0.42) / 1.25) ** 2, 0, 1)             # light from the upper left
rimlight = np.clip((u - 0.72) / 0.28, 0, 1) ** 2             # a little firelight on the right edge

# shadow on the ground
ground = np.clip(1 - np.hypot((xx - CX) / 330, (yy - 716) / 46), 0, 1) ** 1.3
img *= (1 - 0.85 * blur(ground, 10))[..., None]

# ---------------------------------------------------------------- body
body = cylinder(TOP_Y, BOT_Y)
wood = np.zeros((N, N, 3), np.float32)
wood += np.array([150, 44, 26], np.float32) / 255
grain = blur(rng.random((N, N)).astype(np.float32), 0.6)
grain = np.asarray(Image.fromarray((grain * 255).astype(np.uint8)).resize((N, N // 24)).resize((N, N), Image.BICUBIC), np.float32) / 255
wood *= (0.82 + 0.36 * np.asarray(Image.fromarray((grain * 255).astype(np.uint8)).rotate(90), np.float32) / 255)[..., None]
shade = 0.16 + 0.95 * lit
wood = wood * shade[..., None] + np.array([255, 120, 40], np.float32) / 255 * (rimlight * 0.35)[..., None]
# seams between the staves, where they would sit on a round drum
theta = np.arcsin(np.clip(u, -1, 1))
seam = np.abs(((theta / math.radians(18)) + 0.5) % 1.0 - 0.5) * math.radians(18) * rx_at(yy) * np.cos(theta)
wood *= (1 - 0.55 * np.clip(1 - seam / 2.2, 0, 1))[..., None]
wood *= (0.72 + 0.28 * np.clip(1 - (yy - TOP_Y) / 330, 0, 1))[..., None]          # darker towards the ground
img = over(img, wood, body)


def gold(m, strength=1.0):
    """Paints metal with a bright band where the light hits it."""
    base = np.array([214, 150, 40], np.float32) / 255
    band = np.exp(-((u + 0.45) / 0.16) ** 2) + 0.35 * np.exp(-((u - 0.55) / 0.10) ** 2)
    col = base * (0.22 + 0.95 * lit)[..., None] + np.array([255, 244, 200], np.float32) / 255 * (band * 0.85 * strength)[..., None]
    col += np.array([255, 110, 30], np.float32) / 255 * (rimlight * 0.4)[..., None]
    return over(img, np.clip(col, 0, 1), m)


# ---------------------------------------------------------------- lacing
def on_rim(deg, cy, rx, ry):
    t = math.radians(deg)
    return CX + rx * math.sin(t), cy + ry * math.cos(t)


lace_top, lace_bot = TOP_Y + 40, BOT_Y - 30
rt, rb = float(rx_at(np.float32(lace_top))), float(rx_at(np.float32(lace_bot)))
pts = []
for i, deg in enumerate(np.arange(-90, 90.1, 20)):
    pts.append(on_rim(deg, lace_top, rt, RY_T * rt / RX_T) if i % 2 == 0 else on_rim(deg, lace_bot, rb, RY_T * rb / RX_T))
lace = mask(lambda dr: dr.line(P(*pts), fill=255, width=9 * K, joint="curve"))
lace_shadow = blur(mask(lambda dr: dr.line(P(*[(x + 5, y + 7) for x, y in pts]), fill=255, width=11 * K, joint="curve")), 3)
img *= (1 - 0.6 * lace_shadow * body)[..., None]
rope = np.array([226, 190, 120], np.float32) / 255 * (0.3 + 0.85 * lit)[..., None]
twist = 0.82 + 0.18 * np.sin((xx + yy * 2.0) / 3.2)
img = over(img, np.clip(rope * twist[..., None], 0, 1), lace * body)

# ---------------------------------------------------------------- hoops and studs
hoop_top = np.clip(cylinder(TOP_Y, TOP_Y + 40, grow=7) - 0, 0, 1)
hoop_bot = cylinder(BOT_Y - 30, BOT_Y, grow=6) * np.clip((yy - (BOT_Y - 30 - RY_B)) / 4, 0, 1)
hoop_bot *= 1 - cylinder(TOP_Y, BOT_Y - 30)                                   # only its visible front
img = gold(np.clip(hoop_bot, 0, 1))
img = gold(hoop_top)
for hoop, hy, hr in ((hoop_top, TOP_Y + 20, RX_T + 7), (hoop_bot, BOT_Y - 15, RX_B + 9)):
    edge = np.clip(hoop - blur(hoop, 2.5), 0, 1)
    img *= (1 - 0.45 * edge)[..., None]
studs = np.zeros((N, N), np.float32)
for deg in np.arange(-80, 80.1, 20):
    sx, sy = on_rim(deg, TOP_Y + 22, RX_T + 4, RY_T)
    studs = np.maximum(studs, np.clip(1 - np.hypot(xx - sx, yy - sy) / 9, 0, 1) ** 0.6)
img = over(img, np.array([255, 236, 170], np.float32) / 255 * (0.35 + 0.8 * lit)[..., None], studs * (studs > 0.2))

# ---------------------------------------------------------------- the skin
head = mask(lambda dr: dr.ellipse(ellipse_box(TOP_Y, RX_T - 12, RY_T - 5), fill=255))
hd = np.hypot((xx - CX) / (RX_T - 12), (yy - TOP_Y) / (RY_T - 5))               # 0 centre .. 1 edge
skin = np.array([236, 208, 160], np.float32) / 255 * (1.02 - 0.42 * hd ** 2.2)[..., None]
skin *= (0.80 + 0.30 * np.clip(1 - np.hypot((xx - 470) / 420, (yy - 372) / 120), 0, 1))[..., None]
blot = blur(rng.random((N, N)).astype(np.float32), 5)
skin *= (0.93 + 0.14 * blot)[..., None]
img = over(img, np.clip(skin, 0, 1), head)
img *= (1 - 0.5 * np.clip(mask(lambda dr: dr.ellipse(ellipse_box(TOP_Y, RX_T - 12, RY_T - 5), outline=255, width=6 * K)), 0, 1))[..., None]

# the beat: rings of red light spreading over the skin
glow = np.zeros((N, N), np.float32)
for r, w, a in ((0.20, 0.050, 1.0), (0.46, 0.040, 0.55), (0.72, 0.035, 0.28)):
    glow += a * np.exp(-((hd - r) / w) ** 2)
glow += 0.9 * np.exp(-(hd / 0.09) ** 2)
glow *= head
img += np.array([255, 70, 20], np.float32) / 255 * (glow * 1.1)[..., None]
img += np.array([255, 190, 90], np.float32) / 255 * (np.clip(glow - 0.6, 0, 1) * 0.9)[..., None]

# ---------------------------------------------------------------- two mallets, crossed over the drum
def mallet(x0, y0, x1, y1):
    global img
    length = math.hypot(x1 - x0, y1 - y0)
    ux, uy = (x1 - x0) / length, (y1 - y0) / length
    t = (xx - x0) * ux + (yy - y0) * uy                       # along the stick
    s = -(xx - x0) * uy + (yy - y0) * ux                      # across it
    half = 15 - 5 * np.clip(t / length, 0, 1)                 # it tapers towards the head
    stick = np.clip((half - np.abs(s)) * K, 0, 1) * np.clip(t * K, 0, 1) * np.clip((length - t) * K, 0, 1)
    sh = blur(np.clip((half + 2 - np.abs(s - 9)) * K, 0, 1) * (t > 0) * (t < length), 5)
    img *= (1 - 0.45 * sh * np.maximum(head, body))[..., None]
    round_ = np.clip(1 - (s / half) ** 2, 0, 1) ** 0.5
    col = np.array([196, 150, 96], np.float32) / 255 * (0.25 + 0.85 * round_ * (0.75 + 0.25 * np.sign(-s) * 0.5 + 0.12))[..., None]
    wrap = (np.sin(t / 5.0) > 0.2) & (t < length * 0.32)        # leather grip
    col = np.where(wrap[..., None], col * np.array([0.55, 0.36, 0.28], np.float32), col)
    img = over(img, np.clip(col, 0, 1), stick)
    # gold collar and the padded head
    collar = np.clip((half + 3 - np.abs(s)) * K, 0, 1) * (t > length - 58) * (t < length - 40)
    img = over(img, np.array([255, 214, 120], np.float32) / 255 * (0.45 + 0.6 * round_)[..., None], collar)
    hx, hy, hr = x1 - ux * 6, y1 - uy * 6, 44
    hdist = np.hypot(xx - hx, yy - hy)
    ball = np.clip((hr - hdist) * K, 0, 1)
    hsh = blur(np.clip(1 - np.hypot((xx - hx - 6) / 60, (yy - hy - 26) / 26), 0, 1), 5)
    img *= (1 - 0.6 * hsh * head * (1 - ball))[..., None]
    light = np.clip(1 - np.hypot(xx - (hx - 15), yy - (hy - 17)) / (hr * 1.7), 0, 1)
    bcol = np.array([240, 226, 196], np.float32) / 255 * (0.22 + 0.9 * light ** 1.3)[..., None]
    bcol += np.array([255, 90, 30], np.float32) / 255 * (np.clip((yy - hy) / hr, 0, 1) * 0.35)[..., None]   # lit from the skin below
    img = over(img, np.clip(bcol, 0, 1), ball)
    stitch = np.clip(1 - np.abs(hdist - hr * 0.62) / 1.6, 0, 1) * (np.sin(np.arctan2(yy - hy, xx - hx) * 14) > 0)
    img *= (1 - 0.35 * stitch * ball)[..., None]


mallet(985, 70, 520, 372)
mallet(215, 70, 680, 372)

# ---------------------------------------------------------------- sparks and bloom
sparks = np.zeros((N, N), np.float32)
for _ in range(46):
    a, r = rng.uniform(-2.6, -0.5), rng.uniform(250, 520)
    sx, sy, sr = CX + r * math.cos(a) * 1.05, 430 + r * math.sin(a) * 0.95, rng.uniform(1.6, 4.2)
    sparks = np.maximum(sparks, np.clip(1 - np.hypot(xx - sx, yy - sy) / sr, 0, 1) * rng.uniform(0.5, 1.0))
img += np.array([255, 170, 70], np.float32) / 255 * sparks[..., None]
bright = np.clip(img - 0.62, 0, 1)
img = img + blur(bright, 14) * 0.9 + blur(bright, 46) * 0.6
vign = np.clip(np.hypot(xx - 600, yy - 560) / 900, 0, 1) ** 2.2
img *= (1 - 0.75 * vign)[..., None]
img = np.clip(img, 0, 1) ** 0.94

art = Image.fromarray((img * 255).astype(np.uint8)).resize((S, S), Image.LANCZOS).convert("RGBA")

# ---------------------------------------------------------------- rim and title (same recipe as the YaHT Forever icon)
R, RIM = 150, 24


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def rmask(box, r):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=r, fill=255)
    return m


out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
out.paste(art, (0, 0), rmask([0, 0, S - 1, S - 1], R))
fade = Image.new("L", (S, S), 0)                                # darker towards the bottom, so the title stands out
fd = ImageDraw.Draw(fade)
for y in range(730, S):
    fd.line([(0, y), (S, y)], fill=int(150 * (y - 730) / (S - 730)))
out = Image.alpha_composite(out, Image.composite(Image.new("RGBA", (S, S), (4, 6, 12, 255)), Image.new("RGBA", (S, S), (0, 0, 0, 0)),
                                                 ImageChops.multiply(fade, rmask([0, 0, S - 1, S - 1], R))))
rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(rim)
for i in range(RIM):
    rd.rounded_rectangle([i, i, S - 1 - i, S - 1 - i], radius=R - i,
                         outline=lerp((110, 74, 18, 255), (255, 226, 140, 255), math.sin(i / (RIM - 1) * math.pi)), width=1)
inner = rmask([RIM, RIM, S - 1 - RIM, S - 1 - RIM], R - RIM)
rim.putalpha(ImageChops.multiply(rim.getchannel("A"), ImageChops.subtract(rmask([0, 0, S - 1, S - 1], R), inner)))
out = Image.alpha_composite(out, rim)
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(sh).rounded_rectangle([RIM, RIM, S - 1 - RIM, S - 1 - RIM], radius=R - RIM, outline=(0, 0, 0, 210), width=26)
sh = sh.filter(ImageFilter.GaussianBlur(18))
sh.putalpha(ImageChops.multiply(sh.getchannel("A"), inner))
out = Image.alpha_composite(out, sh)


def title(text, size, weight, y, grad, track=0):
    f = ImageFont.truetype(CINZEL, size)
    f.set_variation_by_name(weight)
    m = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(m)
    w = sum(md.textlength(c, font=f) for c in text) + track * (len(text) - 1)
    x = (S - w) / 2
    for c in text:
        md.text((x, y), c, font=f, fill=255)
        x += md.textlength(c, font=f) + track
    bb = m.getbbox()
    g = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(g)
    for py in range(S):                                         # metal: bright top, darker band, lighter lip
        t = min(max((py - bb[1]) / max(bb[3] - bb[1], 1), 0), 1)
        gd.line([(0, py), (S, py)], fill=lerp(grad[0], grad[1], t / 0.55) if t < 0.55 else lerp(grad[1], grad[2], (t - 0.55) / 0.45))
    clear = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.composite(Image.new("RGBA", (S, S), (0, 0, 0, 240)), clear, m).filter(ImageFilter.GaussianBlur(12))
    outline = Image.composite(Image.new("RGBA", (S, S), (18, 12, 4, 255)), clear, m.filter(ImageFilter.MaxFilter(9)))
    fill = Image.composite(g, clear, m)
    top = ImageChops.subtract(m, ImageChops.offset(m, 0, 4)).filter(ImageFilter.GaussianBlur(1))
    bot = ImageChops.subtract(m, ImageChops.offset(m, 0, -4)).filter(ImageFilter.GaussianBlur(1))
    hi = Image.composite(Image.new("RGBA", (S, S), (255, 255, 255, 200)), clear, top)
    lo = Image.composite(Image.new("RGBA", (S, S), (40, 24, 6, 170)), clear, bot)
    return [ImageChops.offset(shadow, 0, 12), outline, fill, lo, hi]


SILVER = ((255, 255, 255, 255), (176, 186, 204, 255), (230, 236, 246, 255))
GOLD = ((255, 240, 170, 255), (198, 128, 26, 255), (255, 206, 96, 255))
for layer in title("WAR", 210, "Black", 752, SILVER, track=14) + title("DRUM", 118, "Bold", 988, GOLD, track=44):
    out = Image.alpha_composite(out, layer)

here = os.path.dirname(os.path.abspath(__file__))
for size in (1024, 400):
    out.resize((size, size), Image.LANCZOS).save(os.path.join(here, "WarDrum-icon-%d.png" % size))
print("done")
