#!/usr/bin/env python3
"""Extract the 8x16 bitmap font from the kernel tree into a C header."""
import re, sys, pathlib

src = pathlib.Path("/root/sunny/src/kernel/lib/fonts/font_8x16.c")
if not src.exists():
    # fallback: any font_8x16.c
    cands = list(pathlib.Path("/root/sunny/src/kernel").rglob("font_8x16.c"))
    if not cands:
        sys.exit("no font_8x16.c found")
    src = cands[0]

text = src.read_text(errors="ignore")
i = text.find("fontdata_8x16")
if i < 0:
    sys.exit("fontdata_8x16 not found")
body = text[i:]
vals = [int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]{2}),", body)]
print(f"# parsed {len(vals)} bytes from {src}", file=sys.stderr)
if len(vals) < 4096:
    sys.exit(f"too few bytes: {len(vals)}")
vals = vals[:4096]

out = pathlib.Path("/mnt/c/Users/brown/Documents/Default Project/sunny-linux/src/sunnyfont.h")
with out.open("w") as f:
    f.write("/* generated from %s */\n" % src)
    f.write("static const unsigned char font8x16[4096] = {\n")
    for i in range(0, 4096, 16):
        f.write("    " + ",".join("0x%02x" % v for v in vals[i:i+16]) + ",\n")
    f.write("};\n")
print("wrote", out, file=sys.stderr)
