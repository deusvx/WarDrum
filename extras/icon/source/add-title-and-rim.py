"""Turns artwork-no-title.png into the War Drum project icon: rounded corners, a gold rim and
the carved title. Same recipe as the YaHT Forever icon.

Usage: python add-title-and-rim.py path/to/Cinzel.ttf
(Cinzel is an open font, see Cinzel-OFL.txt: fonts.google.com/specimen/Cinzel. Needs pillow.)
Writes WarDrum-icon-1024.png and WarDrum-icon-400.png into the folder above this one."""
import math, os, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

CINZEL = sys.argv[1] if len(sys.argv) > 1 else "Cinzel.ttf"
here = os.path.dirname(os.path.abspath(__file__))
S, R, RIM = 1200, 150, 24
FADE_FROM, FADE_MAX = 760, 150          # where the picture starts to darken for the title, and how far


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def rmask(box, r):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=r, fill=255)
    return m


art = Image.open(os.path.join(here, "artwork-no-title.png")).convert("RGBA").resize((S, S), Image.LANCZOS)
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
img.paste(art, (0, 0), rmask([0, 0, S - 1, S - 1], R))

# darken the lower part so the title stands out
fade = Image.new("L", (S, S), 0)
fd = ImageDraw.Draw(fade)
for y in range(FADE_FROM, S):
    t = (y - FADE_FROM) / (S - FADE_FROM)
    fd.line([(0, y), (S, y)], fill=int(FADE_MAX * min(1.0, t * 1.9) ** 1.25))
dark = Image.composite(Image.new("RGBA", (S, S), (6, 5, 10, 255)), Image.new("RGBA", (S, S), (0, 0, 0, 0)),
                       ImageChops.multiply(fade, rmask([0, 0, S - 1, S - 1], R)))
img = Image.alpha_composite(img, dark)

# gold bevelled rim and an inner shadow
rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(rim)
for i in range(RIM):
    rd.rounded_rectangle([i, i, S - 1 - i, S - 1 - i], radius=R - i,
                         outline=lerp((110, 74, 18, 255), (255, 226, 140, 255), math.sin(i / (RIM - 1) * math.pi)), width=1)
inner = rmask([RIM, RIM, S - 1 - RIM, S - 1 - RIM], R - RIM)
rim.putalpha(ImageChops.multiply(rim.getchannel("A"), ImageChops.subtract(rmask([0, 0, S - 1, S - 1], R), inner)))
img = Image.alpha_composite(img, rim)
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(sh).rounded_rectangle([RIM, RIM, S - 1 - RIM, S - 1 - RIM], radius=R - RIM, outline=(0, 0, 0, 210), width=26)
sh = sh.filter(ImageFilter.GaussianBlur(18))
sh.putalpha(ImageChops.multiply(sh.getchannel("A"), inner))
img = Image.alpha_composite(img, sh)


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
    for py in range(S):                 # metal: bright top, darker band, lighter lip
        t = min(max((py - bb[1]) / max(bb[3] - bb[1], 1), 0), 1)
        gd.line([(0, py), (S, py)], fill=lerp(grad[0], grad[1], t / 0.55) if t < 0.55 else lerp(grad[1], grad[2], (t - 0.55) / 0.45))
    clear = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.composite(Image.new("RGBA", (S, S), (0, 0, 0, 250)), clear, m).filter(ImageFilter.GaussianBlur(14))
    outline = Image.composite(Image.new("RGBA", (S, S), (18, 12, 4, 255)), clear, m.filter(ImageFilter.MaxFilter(9)))
    fill = Image.composite(g, clear, m)
    top = ImageChops.subtract(m, ImageChops.offset(m, 0, 4)).filter(ImageFilter.GaussianBlur(1))
    bot = ImageChops.subtract(m, ImageChops.offset(m, 0, -4)).filter(ImageFilter.GaussianBlur(1))
    hi = Image.composite(Image.new("RGBA", (S, S), (255, 255, 255, 200)), clear, top)
    lo = Image.composite(Image.new("RGBA", (S, S), (40, 24, 6, 170)), clear, bot)
    return [ImageChops.offset(shadow, 0, 12), shadow, outline, fill, lo, hi]


SILVER = ((255, 255, 255, 255), (176, 186, 204, 255), (230, 236, 246, 255))
GOLD = ((255, 240, 170, 255), (198, 128, 26, 255), (255, 206, 96, 255))
for layer in title("WAR", 210, "Black", 770, SILVER, track=14) + title("DRUM", 112, "Bold", 1004, GOLD, track=44):
    img = Image.alpha_composite(img, layer)

out = os.path.dirname(here)
for size in (1024, 400):
    img.resize((size, size), Image.LANCZOS).save(os.path.join(out, "WarDrum-icon-%d.png" % size))
print("done")
