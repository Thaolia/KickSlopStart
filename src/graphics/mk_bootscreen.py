#!/usr/bin/env python3
# src/graphics/mk_bootscreen.py — generates the boot screen data from the user's JPEG.
# IMPLEMENTATION track (clean): PIL + public OCS display specs + the public IFF ByteRun1 scheme. Does NOT read the ROM.
#
# Outputs:
#   src/graphics/bootscreen.br1       : 4 planar bitplanes (plane 0 = LSB, planes one after the other), compressed
#                                       with ByteRun1 as a single stream (runs may cross rows and planes)
#   src/graphics/bootscreen_data.s    : OCS palette (16x RGB444) + incbin of .br1
#   assets/boot_screen/cat_boot_ref.png : proof reference = EXACTLY what the Amiga displays
#                                         (rebuilt from the indices + the actual RGB444 palette)
#
# OCS conventions (only the emulator reveals them, not the Python round trip):
#   - plane p = bit p of the palette index; plane 0 = LSB (bm_Planes[0] / BPL1PT)
#   - bit 7 of each byte = LEFTMOST pixel
#   - colour = RGB444: (r4<<8)|(g4<<4)|b4; reduced BEFORE writing (ROM and reference identical)
#
# ByteRun1 (IFF ILBM compression 1): control byte n, 0..127 -> the next n+1 bytes are copied; -1..-127 -> the next
# byte is repeated -n+1 times; -128 -> nothing. The ROM decoder is gfx_display_init (gfx.s).
#
# Self-checks: the chunky image rebuilt from the planes equals the quantized image, and the ByteRun1 stream unpacks
# to the planes -> a planarization or packing bug is a Python failure at build time, not a mystery in the emulator.

import os
import sys
from PIL import Image

WIDTH, HEIGHT, DEPTH = 352, 272, 4   # PAL lores overscan (fills the screen edge to edge)
NCOLORS = 1 << DEPTH                 # 16
BYTES_PER_ROW = WIDTH // 8           # 44
PLANE_SIZE = BYTES_PER_ROW * HEIGHT  # 11968

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "assets", "boot_screen", "cat_amiga_kickslopstart.jpg")
BR1 = os.path.join(HERE, "bootscreen.br1")
ASM = os.path.join(HERE, "bootscreen_data.s")
REF = os.path.join(HERE, "..", "..", "assets", "boot_screen", "cat_boot_ref.png")


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
    img = Image.open(SRC).convert("RGB").resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
    q = img.quantize(colors=NCOLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    idx = list(q.tobytes())                     # index 0..NCOLORS-1 per pixel (mode P)
    pal = q.getpalette()[:NCOLORS * 3]          # RGB888 x NCOLORS

    # OCS RGB444 palette + 8-bit re-expansion for the reference (x17 = <<4 | >>0)
    ocs, rgb444 = [], []
    for i in range(NCOLORS):
        r8, g8, b8 = pal[i * 3], pal[i * 3 + 1], pal[i * 3 + 2]
        r4, g4, b4 = r8 >> 4, g8 >> 4, b8 >> 4
        ocs.append((r4 << 8) | (g4 << 4) | b4)
        rgb444.append((r4 * 17, g4 * 17, b4 * 17))

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
                sys.exit("ECHEC auto-verif planarisation (%d,%d): %d != %d" % (x, y, v, idx[y * WIDTH + x]))

    packed = byterun1(bytes(planes))
    if unpack(packed, len(planes)) != bytes(planes):
        sys.exit("ECHEC auto-verif ByteRun1")
    with open(BR1, "wb") as f:
        f.write(packed)

    ref = Image.new("RGB", (WIDTH, HEIGHT))
    ref.putdata([rgb444[v] for v in idx])
    ref.save(REF)

    lines = [
        "; src/graphics/bootscreen_data.s — data GENERATED by mk_bootscreen.py. DO NOT edit by hand.",
        "; OCS palette (16x RGB444) + 4 planar bitplanes (plane 0 = LSB) of the boot screen (KickSlopStart kitten),",
        "; packed with ByteRun1 (%d bytes, %d unpacked)." % (len(packed), len(planes)),
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

    print("OK: %s (%d o, %d o unpacked) + %s + %s ; couleurs OCS uniques = %d/%d"
          % (BR1, len(packed), len(planes), ASM, REF, len(set(ocs)), NCOLORS))


if __name__ == "__main__":
    main()
