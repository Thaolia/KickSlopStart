#!/usr/bin/env python3
# src/graphics/mk_bootscreen.py — generates the insert-disk screen data from the user's KSS logo (SVG).
# IMPLEMENTATION track (clean): PIL + public OCS display specs + the public IFF ByteRun1 scheme. Does NOT read the ROM.
#
# Input:
#   assets/boot_screen/kss_logo.svg   : the user's pixel-art logo, 200 x 200 units, filled paths made only of
#                                       M/h/v/z commands (1 unit = 1 pixel here), transparent background
# Outputs:
#   src/graphics/bootscreen.br1       : 4 planar bitplanes (plane 0 = LSB, planes one after the other), compressed
#                                       with ByteRun1 as a single stream (runs may cross rows and planes)
#   src/graphics/bootscreen_data.s    : OCS palette (16x RGB444) + incbin of .br1
#   assets/boot_screen/kss_boot_ref.png : proof reference = EXACTLY the image the ROM unpacks (the text and the build
#                                         number are drawn at boot by gfx_display_init, not here)
#
# Layout (352 x 272 PAL lores overscan): colour 0 = Workbench purple background (also the border, COLOR00), colour 1 =
# black, reserved for the text gfx_display_init writes in the right-hand column, colours 2-15 = the logo, whose distinct
# colours are reduced to 14 by median cut. Logo at (LOGO_X, LOGO_Y).
#
# OCS conventions (only the emulator reveals them, not the Python round trip):
#   - plane p = bit p of the palette index; plane 0 = LSB (bm_Planes[0] / BPL1PT)
#   - bit 7 of each byte = LEFTMOST pixel
#   - colour = RGB444: (r4<<8)|(g4<<4)|b4; reduced BEFORE writing (ROM and reference identical)
#
# ByteRun1 (IFF ILBM compression 1): control byte n, 0..127 -> the next n+1 bytes are copied; -1..-127 -> the next
# byte is repeated -n+1 times; -128 -> nothing. The ROM decoder is gfx_display_init (gfx.s).
#
# Self-checks: the chunky image rebuilt from the planes equals the composed image, and the ByteRun1 stream unpacks
# to the planes -> a planarization or packing bug is a Python failure at build time, not a mystery in the emulator.

import os
import re
import sys
from PIL import Image

WIDTH, HEIGHT, DEPTH = 352, 272, 4   # PAL lores overscan (fills the screen edge to edge)
NCOLORS = 1 << DEPTH                 # 16
BYTES_PER_ROW = WIDTH // 8           # 44
PLANE_SIZE = BYTES_PER_ROW * HEIGHT  # 11968
LOGO = 200                           # logo side, in pixels (= SVG units)
LOGO_X, LOGO_Y = 16, (HEIGHT - LOGO) // 2
BG_RGB444 = 0xA9C                    # Workbench purple (screens.s palette)
TEXT_RGB444 = 0x000                  # black text, as on the Workbench
NLOGO = NCOLORS - 2                  # colours left for the logo

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "assets", "boot_screen", "kss_logo.svg")
BR1 = os.path.join(HERE, "bootscreen.br1")
ASM = os.path.join(HERE, "bootscreen_data.s")
REF = os.path.join(HERE, "..", "..", "assets", "boot_screen", "kss_boot_ref.png")


def parse_svg(text):
    """-> [(rgb, [polygon, ...])] in document order; a polygon is a list of integer (x, y) vertices."""
    paths = []
    for fill, d in re.findall(r'<path\s+fill="#([0-9a-fA-F]{6})"\s+d="([^"]*)"', text):
        rgb = tuple(int(fill[i:i + 2], 16) for i in (0, 2, 4))
        polys, cur, x, y = [], None, 0, 0
        for cmd, args in re.findall(r"([A-Za-z])([^A-Za-z]*)", d):
            nums = [int(v) for v in re.findall(r"-?\d+", args)]
            if cmd == "M" and len(nums) == 2:
                x, y = nums
                cur = [(x, y)]
                polys.append(cur)
            elif cmd in "hv" and len(nums) == 1 and cur is not None:
                if cmd == "h":
                    x += nums[0]
                else:
                    y += nums[0]
                cur.append((x, y))
            elif cmd == "z" and not nums and cur is not None:
                x, y = cur[0]
                cur = None
            else:
                sys.exit("unsupported path command %r %r (only M/h/v/z)" % (cmd, args))
        paths.append((rgb, polys))
    if not paths:
        sys.exit("no <path fill=... d=...> in %s" % SRC)
    return paths


def rasterize(polys):
    """Pixels covered by rectilinear polygons, SVG nonzero rule, sampled at pixel centres -> set of (x, y)."""
    edges = []                                   # vertical edges: (x, ymin, ymax, direction)
    for poly in polys:
        for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
            if x0 == x1 and y0 != y1:
                edges.append((x0, min(y0, y1), max(y0, y1), 1 if y1 > y0 else -1))
            elif x0 != x1 and y0 != y1:
                sys.exit("diagonal edge (%d,%d)-(%d,%d)" % (x0, y0, x1, y1))
    pixels = set()
    for y in range(LOGO):
        crossing = sorted((x, w) for x, a, b, w in edges if a <= y < b)
        wind = 0
        for (x, w), (xn, _) in zip(crossing, crossing[1:] + [(None, 0)]):
            wind += w
            if wind and xn is not None:
                for px in range(max(x, 0), min(xn, LOGO)):
                    pixels.add((px, y))
    return pixels


def rgb444(rgb):
    r, g, b = rgb
    return ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)


def byterun1(data):
    out = bytearray()
    i, n = 0, len(data)
    while i < n:
        run = 1
        while i + run < n and run < 128 and data[i + run] == data[i]:
            run += 1
        if run >= 3:                                    # a run of 3 or more: 2 bytes
            out += bytes([(257 - run) & 0xFF, data[i]])
            i += run
            continue
        j = i                                           # literals up to the next run of 3 (128 at most)
        while j < n and j - i < 128 and not (j + 2 < n and data[j] == data[j + 1] == data[j + 2]):
            j += 1
        out.append(j - i - 1)
        out += data[i:j]
        i = j
    return bytes(out)


def unpack(stream, size):
    out = bytearray()
    i = 0
    while len(out) < size:
        c = stream[i]
        i += 1
        if c < 128:
            out += stream[i:i + c + 1]
            i += c + 1
        elif c != 128:
            out += bytes([stream[i]]) * (257 - c)
            i += 1
    return bytes(out)


def main():
    with open(SRC) as f:
        paths = parse_svg(f.read())

    logo = {}                                           # (x, y) -> RGB888, later paths painted over earlier ones
    for rgb, polys in paths:
        for p in rasterize(polys):
            logo[p] = rgb
    if not logo:
        sys.exit("empty logo")

    # the logo's distinct colours (each counted once, so small accents such as the lettering keep their own entry)
    # reduced to NLOGO by median cut, then each colour mapped to the nearest entry
    # (in RGB444 already, so two entries never collapse into one OCS colour)
    to444 = {c: tuple((v >> 4) * 17 for v in c) for c in set(logo.values())}
    colours = sorted(set(to444.values()))
    strip = Image.new("RGB", (len(colours), 1))
    strip.putdata(colours)
    q = strip.quantize(colors=NLOGO, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    qpal = [tuple(q.getpalette()[i * 3:i * 3 + 3]) for i in range(NLOGO)]
    nearest = {c: min(range(NLOGO), key=lambda i: sum((a - b) ** 2 for a, b in zip(to444[c], qpal[i])))
               for c in to444}

    ocs = [BG_RGB444, TEXT_RGB444] + [rgb444(c) for c in qpal]
    idx = [0] * (WIDTH * HEIGHT)
    for (x, y), c in logo.items():
        idx[(LOGO_Y + y) * WIDTH + LOGO_X + x] = 2 + nearest[c]

    # planarization: plane p = bit p of the index; bit 7 of the byte = left pixel
    planes = bytearray(DEPTH * PLANE_SIZE)
    for y in range(HEIGHT):
        row = y * BYTES_PER_ROW
        for x in range(WIDTH):
            v = idx[y * WIDTH + x]
            off = row + (x >> 3)
            bit = 7 - (x & 7)
            for p in range(DEPTH):
                if (v >> p) & 1:
                    planes[p * PLANE_SIZE + off] |= (1 << bit)

    # self-check: rebuild the chunky image from the planes and compare
    for y in range(HEIGHT):
        row = y * BYTES_PER_ROW
        for x in range(WIDTH):
            off = row + (x >> 3)
            bit = 7 - (x & 7)
            v = 0
            for p in range(DEPTH):
                if planes[p * PLANE_SIZE + off] & (1 << bit):
                    v |= (1 << p)
            if v != idx[y * WIDTH + x]:
                sys.exit("planarization self-check failed at (%d,%d): %d != %d" % (x, y, v, idx[y * WIDTH + x]))

    packed = byterun1(bytes(planes))
    if unpack(packed, len(planes)) != bytes(planes):
        sys.exit("ByteRun1 self-check failed")
    with open(BR1, "wb") as f:
        f.write(packed)

    expand = [(((c >> 8) & 15) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17) for c in ocs]
    ref = Image.new("RGB", (WIDTH, HEIGHT))
    ref.putdata([expand[v] for v in idx])
    ref.save(REF)

    lines = [
        "; src/graphics/bootscreen_data.s — data GENERATED by mk_bootscreen.py. DO NOT edit by hand.",
        "; OCS palette (16x RGB444: 0 background, 1 text, 2-15 logo) + 4 planar bitplanes (plane 0 = LSB) of the",
        "; insert-disk screen (KSS logo), packed with ByteRun1 (%d bytes, %d unpacked)." % (len(packed), len(planes)),
        "",
        "                xdef    bootscreen_palette",
        "                xdef    bootscreen_planes",
        "",
        "bootscreen_palette:",
    ]
    for i in range(0, NCOLORS, 8):
        lines.append("        dc.w    " + ",".join("$%03X" % ocs[j] for j in range(i, i + 8)))
    lines += [
        "        EVEN",
        "bootscreen_planes:",
        '        incbin  "bootscreen.br1"',
        "        EVEN",
        "",
    ]
    with open(ASM, "w") as f:
        f.write("\n".join(lines))

    print("OK: %s (%d bytes, %d unpacked) + %s + %s; %d paths, %d logo pixels, %d distinct OCS colours"
          % (BR1, len(packed), len(planes), ASM, REF, len(paths), len(logo), len(set(ocs))))


if __name__ == "__main__":
    main()
