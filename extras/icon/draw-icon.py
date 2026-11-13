"""Draws the War Drum project icon: a drum with two sticks, in the addon's own colours.
Usage: python draw-icon.py   (writes WarDrum-icon-1024.png and WarDrum-icon-400.png next to it)"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 2048                      # drawn large, scaled down for smooth edges
GOLD, GOLD_DARK = (232, 178, 60), (150, 106, 28)
HIDE, HIDE_DARK = (226, 208, 170), (176, 152, 110)
WOOD, WOOD_DARK = (112, 46, 30), (70, 26, 18)
RED = (214, 52, 40)
BG_TOP, BG_BOTTOM = (34, 28, 22), (12, 10, 9)

img = Image.new("RGB", (S, S), BG_BOTTOM)
d = ImageDraw.Draw(img)
for y in range(S):            # soft top-to-bottom shade
    t = y / S
    d.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))

# a warm glow behind the drum
glow = Image.new("RGB", (S, S), (0, 0, 0))
ImageDraw.Draw(glow).ellipse([S * 0.18, S * 0.22, S * 0.82, S * 0.86], fill=(120, 44, 20))
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.09))
img = Image.blend(img, Image.composite(glow, img, glow.convert("L")), 0.55)
d = ImageDraw.Draw(img)

cx = S / 2
top_y, bot_y = S * 0.46, S * 0.76      # centres of the two rims
rx_top, rx_bot, ry = S * 0.30, S * 0.25, S * 0.085

# body
d.polygon([(cx - rx_top, top_y), (cx + rx_top, top_y), (cx + rx_bot, bot_y), (cx - rx_bot, bot_y)], fill=WOOD)
d.ellipse([cx - rx_bot, bot_y - ry * 0.85, cx + rx_bot, bot_y + ry * 0.85], fill=WOOD)
# shade on the right side of the body
shade = Image.new("L", (S, S), 0)
ImageDraw.Draw(shade).polygon([(cx + rx_top * 0.25, top_y), (cx + rx_top, top_y), (cx + rx_bot, bot_y + ry), (cx + rx_bot * 0.25, bot_y + ry)], fill=120)
shade = shade.filter(ImageFilter.GaussianBlur(S * 0.03))
body = Image.new("L", (S, S), 0)
bd = ImageDraw.Draw(body)
bd.polygon([(cx - rx_top, top_y), (cx + rx_top, top_y), (cx + rx_bot, bot_y), (cx - rx_bot, bot_y)], fill=255)
bd.ellipse([cx - rx_bot, bot_y - ry * 0.85, cx + rx_bot, bot_y + ry * 0.85], fill=255)
from PIL import ImageChops
img.paste(Image.new("RGB", (S, S), WOOD_DARK), mask=ImageChops.multiply(shade, body))
d = ImageDraw.Draw(img)

# lacing: a zigzag between the rims
n = 7
w = round(S * 0.012)
for i in range(n):
    t0, t1, t2 = i / n, (i + 0.5) / n, (i + 1) / n
    xa = cx - rx_top * 0.94 + 2 * rx_top * 0.94 * t0
    xb = cx - rx_bot * 0.94 + 2 * rx_bot * 0.94 * t1
    xc = cx - rx_top * 0.94 + 2 * rx_top * 0.94 * t2
    def dip(x, rx):                       # the rim curves towards the viewer
        return ry * 0.8 * (1 - ((x - cx) / rx) ** 2) ** 0.5
    ya, yb, yc = top_y + dip(xa, rx_top) + ry * 0.25, bot_y + dip(xb, rx_bot) * 0.85 - ry * 0.1, top_y + dip(xc, rx_top) + ry * 0.25
    d.line([(xa, ya), (xb, yb), (xc, yc)], fill=GOLD, width=w, joint="curve")

# bottom rim (front half only) and top rim
d.arc([cx - rx_bot, bot_y - ry * 0.85, cx + rx_bot, bot_y + ry * 0.85], 0, 180, fill=GOLD_DARK, width=round(S * 0.022))
d.ellipse([cx - rx_top - S * 0.012, top_y - ry - S * 0.012, cx + rx_top + S * 0.012, top_y + ry + S * 0.022], fill=GOLD_DARK)
d.ellipse([cx - rx_top, top_y - ry, cx + rx_top, top_y + ry], fill=GOLD)
d.ellipse([cx - rx_top * 0.9, top_y - ry * 0.86, cx + rx_top * 0.9, top_y + ry * 0.82], fill=HIDE)
d.ellipse([cx - rx_top * 0.9, top_y - ry * 0.5, cx + rx_top * 0.9, top_y + ry * 0.82], fill=HIDE)
# a red mark on the skin, like the list's "near" bar
d.ellipse([cx - rx_top * 0.2, top_y - ry * 0.2, cx + rx_top * 0.2, top_y + ry * 0.24], fill=RED)
d.ellipse([cx - rx_top * 0.11, top_y - ry * 0.1, cx + rx_top * 0.11, top_y + ry * 0.14], fill=HIDE)

# two sticks, crossed above the drum
def stick(x0, y0, x1, y1):
    d.line([(x0, y0), (x1, y1)], fill=WOOD_DARK, width=round(S * 0.034))
    d.line([(x0, y0), (x1, y1)], fill=HIDE_DARK, width=round(S * 0.022))
    r = S * 0.036
    d.ellipse([x1 - r - 4, y1 - r - 4, x1 + r + 4, y1 + r + 4], fill=WOOD_DARK)
    d.ellipse([x1 - r, y1 - r, x1 + r, y1 + r], fill=GOLD)
stick(cx - S * 0.31, S * 0.14, cx + S * 0.10, top_y - ry * 0.25)
stick(cx + S * 0.31, S * 0.14, cx - S * 0.10, top_y - ry * 0.25)

# gold frame with rounded corners
frame = Image.new("L", (S, S), 0)
fd = ImageDraw.Draw(frame)
m, rad = S * 0.035, S * 0.09
fd.rounded_rectangle([m, m, S - m, S - m], radius=rad, outline=255, width=round(S * 0.016))
img.paste(Image.new("RGB", (S, S), GOLD_DARK), mask=frame)

here = os.path.dirname(os.path.abspath(__file__))
for size in (1024, 400):
    img.resize((size, size), Image.LANCZOS).save(os.path.join(here, "WarDrum-icon-%d.png" % size))
print("done")
