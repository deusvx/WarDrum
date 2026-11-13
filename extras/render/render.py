"""Draws War Drum's windows from the addon's own code, outside the game: the addon runs against a
recording stand-in, and its frames, anchors, textures and texts are laid out and painted here.
A layout check and a design preview. NOT a game screenshot: the fonts and the icon are stand-ins.

Usage: render.py <addon folder> <output folder>
"""
import json, math, os, re, sys
from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

addon, out = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
S = 2  # pixels per UI unit
FONT_FILE, FONT_BOLD = r"C:\Windows\Fonts\candara.ttf", r"C:\Windows\Fonts\candarab.ttf"
FONTS = {  # template -> (size, default color)
    "GameFontNormalLarge": (16, (1, 0.82, 0)), "GameFontNormal": (12, (1, 0.82, 0)), "GameFontHighlight": (12, (1, 1, 1)),
    "GameFontHighlightSmall": (10, (1, 1, 1)), "GameFontNormalSmall": (10, (1, 0.82, 0)), "GameFontDisableSmall": (10, (0.5, 0.5, 0.5)),
}
LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3}
_fonts = {}


def font(size):
    if size not in _fonts:
        _fonts[size] = ImageFont.truetype(FONT_BOLD if size >= 16 else FONT_FILE, int(size * S * 1.08))
    return _fonts[size]


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def scene(script):
    lua = LuaRuntime(unpack_returned_tuples=True)
    load = lua.eval("function(src, name) local f, e = loadstring(src, name) if not f then error(e, 0) end return f() end")
    load(read(os.path.join(addon, "tests", "fakegame.lua")), "@fakegame.lua")
    load(read(os.path.join(here, "recorder.lua")), "@recorder.lua")
    load(read(os.path.join(addon, "WarDrum.lua")), "@WarDrum.lua")
    load(script, "@scene")
    return {r["id"]: r for r in json.loads(lua.eval("export()"))}


def plain(text):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text or "")


def pieces(text, color):
    """(text, color) runs of a string with |cffRRGGBB ... |r codes"""
    runs, cur, pos = [], color, 0
    for m in re.finditer(r"\|c[0-9a-fA-F]{8}|\|r", text):
        if m.start() > pos:
            runs.append((text[pos:m.start()], cur))
        cur = color if m.group() == "|r" else tuple(int(m.group()[i:i + 2], 16) / 255 for i in (4, 6, 8))
        pos = m.end()
    if pos < len(text):
        runs.append((text[pos:], cur))
    return runs


class Layout:
    def __init__(self, regions):
        self.r, self.memo = regions, {}

    def lines(self, r):
        """the text of a font string as drawn lines"""
        size = FONTS.get(r.get("font"), (12,))[0]
        f, text = font(size), r.get("text") or ""
        out = []
        for para in text.split("\n"):
            if r.get("width") and r.get("wrap") is not False:
                line = ""
                for word in para.split(" "):
                    trial = (line + " " + word).strip()
                    if f.getlength(plain(trial)) / S <= r["width"] or not line:
                        line = trial
                    else:
                        out.append(line)
                        line = word
                out.append(line)
            else:
                out.append(para)
        return out, size

    def natural(self, r):
        if r["kind"] != "FontString":
            return r.get("width") or 0, r.get("height") or 0
        lines, size = self.lines(r)
        w = max([font(size).getlength(plain(l)) / S for l in lines] or [0])
        return (r.get("width") or w), (r.get("height") or (len(lines) * (size + 2 + (r.get("spacing") or 0))))

    def rect(self, rid):
        """left, bottom, right, top in UI units, y upwards"""
        if rid in self.memo:
            return self.memo[rid]
        r = self.r[rid]
        if r["parent"] == 0:
            self.memo[rid] = (0, 0, r["width"], r["height"])
            return self.memo[rid]
        if r.get("isThumb"):
            sl = self.r[r["parent"]]
            l, b, rt, t = self.rect(sl["id"])
            frac = ((sl.get("value") or 0) - sl["min"]) / (sl["max"] - sl["min"])
            w, h = r.get("width") or 14, r.get("height") or 14
            cx, cy = l + w / 2 + frac * (rt - l - w), (b + t) / 2
            self.memo[rid] = (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
            return self.memo[rid]
        xs, ys = {}, {}
        for p in r["points"]:
            l, b, rt, t = self.rect(p["rel"])
            rp, pt = p["relPoint"], p["point"]
            tx = (l if "LEFT" in rp else rt if "RIGHT" in rp else (l + rt) / 2) + p["x"]
            ty = (t if "TOP" in rp else b if "BOTTOM" in rp else (b + t) / 2) + p["y"]
            xs["l" if "LEFT" in pt else "r" if "RIGHT" in pt else "c"] = tx
            ys["t" if "TOP" in pt else "b" if "BOTTOM" in pt else "c"] = ty
        nw, nh = self.natural(r)
        w = (xs["r"] - xs["l"]) if ("l" in xs and "r" in xs) else nw
        h = (ys["t"] - ys["b"]) if ("t" in ys and "b" in ys) else nh
        left = xs["l"] if "l" in xs else (xs["r"] - w) if "r" in xs else (xs.get("c", 0) - w / 2)
        top = ys["t"] if "t" in ys else (ys["b"] + h) if "b" in ys else (ys.get("c", 0) + h / 2)
        self.memo[rid] = (left, top - h, left + w, top)
        return self.memo[rid]


_tga = {}


def art(path):
    name = path.replace("\\", "/").split("/")[-1]
    if name not in _tga:
        _tga[name] = Image.open(os.path.join(addon, "media", name + ".tga")).convert("RGBA")
    return _tga[name]


def tinted(img, c, alpha):
    r, g, b, a = img.split()
    a = a.point(lambda v: int(v * (c[3] if len(c) > 3 else 1) * alpha))
    return Image.merge("RGBA", (r.point(lambda v: int(v * c[0])), g.point(lambda v: int(v * c[1])), b.point(lambda v: int(v * c[2])), a))


def nine(img, w, h, m=8):
    """the texture's corners as they are, its edges and middle stretched"""
    w, h = max(1, int(round(w))), max(1, int(round(h)))
    big = img.resize((img.width * S, img.height * S), Image.LANCZOS)
    m, tw, th = m * S, big.width, big.height
    mx, my = min(m, w // 2), min(m, h // 2)
    res = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cols = [(0, m, 0, mx), (m, tw - m, mx, w - mx), (tw - m, tw, w - mx, w)]
    rows = [(0, m, 0, my), (m, th - m, my, h - my), (th - m, th, h - my, h)]
    for sy0, sy1, dy0, dy1 in rows:
        for sx0, sx1, dx0, dx1 in cols:
            if dx1 > dx0 and dy1 > dy0:
                res.paste(big.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS), (dx0, dy0))
    return res


def draw(regions, H=768, W=1366):
    lay = Layout(regions)
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))

    def box(rid):
        l, b, r, t = lay.rect(rid)
        return l * S, (H - t) * S, r * S, (H - b) * S

    def paste(layer, x, y):
        tmp = Image.new("RGBA", img.size, (0, 0, 0, 0))
        tmp.paste(layer, (int(round(x)), int(round(y))))
        img.alpha_composite(tmp)

    def texture(r, alpha):
        x0, y0, x1, y1 = box(r["id"])
        w, h = x1 - x0, y1 - y0
        if w < 0.5 or h < 0.5:
            return
        a = alpha * (r.get("alpha") if r.get("alpha") is not None else 1)
        tex = r.get("texture")
        if tex and "AddOns" in tex:
            c = r.get("vertex") or [1, 1, 1, 1]
            src = tinted(art(tex), c, a)
            if r.get("slice"):
                layer = nine(src, w, h)
            else:
                layer = src.resize((max(1, int(round(w))), max(1, int(round(h)))), Image.LANCZOS)
                if r.get("texcoord") and r["texcoord"][2] > r["texcoord"][3]:
                    layer = layer.transpose(Image.FLIP_TOP_BOTTOM)
                if r.get("rotation"):
                    layer = layer.rotate(math.degrees(r["rotation"]), expand=True, resample=Image.BICUBIC)
                    x0, y0 = (x0 + x1) / 2 - layer.width / 2, (y0 + y1) / 2 - layer.height / 2
            paste(layer, x0, y0)
        elif tex:  # one of the game's icons: not available outside the game
            layer = Image.new("RGBA", (int(w), int(h)), (70, 62, 50, int(255 * a)))
            d = ImageDraw.Draw(layer)
            d.rectangle((0, 0, int(w) - 1, int(h) - 1), outline=(140, 120, 70, int(255 * a)), width=S)
            d.text((w / 2, h / 2), "icon", font=font(7), fill=(200, 190, 160, int(255 * a)), anchor="mm")
            paste(layer, x0, y0)
        elif r.get("rgba"):
            c = r["rgba"]
            layer = Image.new("RGBA", (max(1, int(round(w))), max(1, int(round(h)))), (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(c[3] * 255 * a)))
            paste(layer, x0, y0)

    def text(r, alpha):
        lines, size = lay.lines(r)
        if not any(lines):
            return
        base = tuple((r.get("color") or FONTS.get(r.get("font"), (12, (1, 1, 1)))[1])[:3])
        x0, y0, x1, y1 = box(r["id"])
        f, d = font(size), ImageDraw.Draw(img)
        a = alpha * (r.get("alpha") if r.get("alpha") is not None else 1)
        step = (size + 2 + (r.get("spacing") or 0)) * S
        for i, line in enumerate(lines):
            if r.get("width") and r.get("wrap") is False:  # too long for its column: cut, as the game does
                while f.getlength(plain(line)) > r["width"] * S and len(line) > 3:
                    line = line[:-4] + "..." if not line.endswith("...") else line[:-4] + "..."
            w = f.getlength(plain(line))
            jh = r.get("justifyH") or "CENTER"
            x = x0 if jh == "LEFT" else (x1 - w) if jh == "RIGHT" else (x0 + x1 - w) / 2
            y = y0 + i * step + (step - size * S * 1.25) / 2
            for run, c in pieces(line, base):
                d.text((x + S * 0.6, y + S * 0.6), run, font=f, fill=(0, 0, 0, int(200 * a)))
                d.text((x, y), run, font=f, fill=(int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(255 * a)))
                x += f.getlength(run)

    def frame(r, alpha):
        if not r["shown"] or r["kind"] == "GameTooltip":
            return
        a = alpha * (r.get("alpha") if r.get("alpha") is not None else 1)
        kids = [regions[c] for c in r["children"]]
        for t in sorted((k for k in kids if k["kind"] == "Texture" and k["shown"]), key=lambda k: (LAYERS.get(k.get("layer"), 2), k["id"])):
            texture(t, a)
        for t in (k for k in kids if k["kind"] == "FontString" and k["shown"]):
            text(t, a)
        for k in kids:
            if k["kind"] not in ("Texture", "FontString"):
                frame(k, a)

    frame(regions[1], 1)
    # the game's tooltip, if one is up: a dark box to the right of the row it belongs to
    tip = next((r for r in regions.values() if r.get("name") == "tooltip"), None)
    if tip and tip["shown"] and tip.get("lines") and tip.get("owner"):
        x0, y0, x1, y1 = box(tip["owner"])
        d = ImageDraw.Draw(img)
        f1, f2 = font(12), font(11)
        widths = [(f1 if i == 0 else f2).getlength(l[0]) for i, l in enumerate(tip["lines"])]
        w, h = max(widths) + 20 * S, (len(tip["lines"]) * 15 + 14) * S
        bx, by = x1 + 6 * S, y0 - h + 4 * S
        d.rounded_rectangle((bx, by, bx + w, by + h), radius=5 * S, fill=(12, 12, 16, 240), outline=(150, 150, 150, 255), width=S)
        for i, l in enumerate(tip["lines"]):
            d.text((bx + 10 * S, by + (7 + i * 15) * S), l[0], font=f1 if i == 0 else f2, fill=(int(l[1] * 255), int(l[2] * 255), int(l[3] * 255), 255))
    return img, lay


def crop(img, lay, regions, names, pad=14, extra=(0, 0, 0, 0)):
    xs0, ys0, xs1, ys1 = [], [], [], []
    for r in regions.values():
        if r.get("name") in names and r["shown"]:
            l, b, rt, t = lay.rect(r["id"])
            xs0.append(l), ys0.append(768 - t), xs1.append(rt), ys1.append(768 - b)
    boxc = ((min(xs0) - pad - extra[0]) * S, (min(ys0) - pad - extra[1]) * S, (max(xs1) + pad + extra[2]) * S, (max(ys1) + pad + extra[3]) * S)
    bg = Image.new("RGBA", img.size, (38, 44, 40, 255))  # a plain backdrop standing in for the game world
    bg.alpha_composite(img)
    return bg.crop(tuple(int(v) for v in boxc)).convert("RGB")


SCENES = {
    "list-sample": ("start() slash('demo')", ["list"], (0, 0, 0, 0)),
    "list-tooltip": ("start() slash('demo') list.rows[1].scripts.OnEnter(list.rows[1]) GameTooltip.shown = true", ["list"], (0, 60, 210, 0)),
    "list-empty": ("start()", ["list"], (0, 0, 0, 0)),
    "list-narrow": ("start() slash('demo') db.settings.width = 160 db.settings.showClass = false list.Apply()", ["list"], (0, 0, 0, 0)),
    "list-wide": ("start() slash('demo') db.settings.width = 260 list.Apply()", ["list"], (0, 0, 0, 0)),
    "list-scrolled": ("""WarDrumDB = {version = 2, players = {}}
        local classes = {"ROGUE", "MAGE", "WARRIOR", "HUNTER"}
        for i = 1, 14 do WarDrumDB.players["P" .. i] = {guid = "P" .. i, name = "Ganker Number " .. i, class = classes[i % 4 + 1], level = 30 + i, attacks = i, kills = i % 3 * 5, mine = 0, first = 1, last = i} end
        start() db.settings.rows = 6 list.Apply() list.scripts.OnMouseWheel(list, -1) list.scripts.OnMouseWheel(list, -1)""", ["list"], (0, 0, 0, 0)),
    "options": ("start() slash('demo') slash('options')", ["options"], (0, 0, 0, 0)),
    "options-help": ("start() slash('demo') slash('options') local c = WarDrumOptionsFrame.controls c.onlyDamage.scripts.OnEnter(c.onlyDamage)", ["options"], (0, 0, 0, 0)),
    "options-off": ("start() slash('demo') slash('options') local c = WarDrumOptionsFrame.controls click(c.alert.widget) click(c.showClass.widget) c.width.widget.scripts.OnValueChanged(c.width.widget, 260) c.alert.scripts.OnEnter(c.alert)", ["options"], (0, 0, 0, 0)),
    "both": ("start() slash('demo') slash('options') local c = WarDrumOptionsFrame.controls c.sound.scripts.OnEnter(c.sound)", ["list", "options"], (0, 0, 0, 0)),
}
os.makedirs(out, exist_ok=True)
only = sys.argv[3] if len(sys.argv) > 3 else ""
for name, (script, names, extra) in SCENES.items():
    if only not in name:
        continue
    regions = scene(script)
    img, lay = draw(regions)
    pic = crop(img, lay, regions, names, extra=extra)
    pic.save(os.path.join(out, name + ".png"))
    for r in regions.values():
        if r.get("name") in names:
            l, b, rt, t = lay.rect(r["id"])
            print("%-14s %-8s %dx%d" % (name, r["name"], rt - l, t - b))
