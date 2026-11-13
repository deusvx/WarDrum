"""Puts several renders side by side on one sheet, each with its name, to look at them together."""
import os, sys
from PIL import Image, ImageDraw, ImageFont

folder, outfile, names = sys.argv[1], sys.argv[2], sys.argv[3:]
f = ImageFont.truetype(r"C:\Windows\Fonts\segoeui.ttf", 18)
pics = [(n, Image.open(os.path.join(folder, n + ".png"))) for n in names]
pad = 16
W = sum(p.width for _, p in pics) + pad * (len(pics) + 1)
H = max(p.height for _, p in pics) + 2 * pad + 28
sheet = Image.new("RGB", (W, H), (24, 26, 28))
d, x = ImageDraw.Draw(sheet), pad
for n, p in pics:
    d.text((x, pad - 4), n, font=f, fill=(210, 210, 210))
    sheet.paste(p, (x, pad + 26))
    x += p.width + pad
sheet.save(outfile)
print(sheet.size)
