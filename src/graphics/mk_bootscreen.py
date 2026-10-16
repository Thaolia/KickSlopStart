#!/usr/bin/env python3
# src/graphics/mk_bootscreen.py — genere les donnees de l'ecran de boot depuis le JPEG utilisateur.
# Piste IMPLEMENTATION (clean) : PIL + specs d'affichage OCS publiques. Ne lit PAS la ROM.
#
# Sorties :
#   src/graphics/bootscreen.raw       : 5 bitplanes planar (plan 0 = LSB), 5*10240 o
#   src/graphics/bootscreen_data.s    : palette OCS (32x RGB444) + incbin de .raw
#   assets/boot_screen/cat_boot_ref.png : reference de preuve = EXACTEMENT ce que l'Amiga affiche
#                                         (reconstruite depuis les index + la palette RGB444 reelle)
#
# Conventions OCS (seul l'emulateur les revele, pas le round-trip Python) :
#   - plan p = bit p de l'index palette ; plan 0 = LSB (bm_Planes[0] / BPL1PT)
#   - bit 7 de chaque octet = pixel le plus a GAUCHE
#   - couleur = RGB444 : (r4<<8)|(g4<<4)|b4 ; reduite AVANT ecriture (ROM et reference identiques)
#
# Auto-verif : reconstruit le chunky depuis les 5 plans et asserte l'identite avec l'image quantifiee
# -> un bug de planarisation est un echec Python au build, pas un mystere a l'emulateur.

import os
import sys
from PIL import Image

WIDTH, HEIGHT, DEPTH = 352, 272, 5   # overscan PAL lores (remplit l'écran bord-à-bord) ; 44 o/ligne
NCOLORS = 1 << DEPTH                 # 32
BYTES_PER_ROW = WIDTH // 8           # 40
PLANE_SIZE = BYTES_PER_ROW * HEIGHT  # 10240

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "assets", "boot_screen", "cat_amiga_kickslopstart.jpg")
RAW = os.path.join(HERE, "bootscreen.raw")
ASM = os.path.join(HERE, "bootscreen_data.s")
REF = os.path.join(HERE, "..", "..", "assets", "boot_screen", "cat_boot_ref.png")


def main():
    img = Image.open(SRC).convert("RGB").resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
    q = img.quantize(colors=NCOLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    idx = list(q.getdata())                     # index 0..NCOLORS-1 par pixel
    pal = q.getpalette()[:NCOLORS * 3]          # RGB888 x NCOLORS

    # palette OCS RGB444 + re-expansion 8-bit pour la reference (x17 = <<4 | >>0)
    ocs, rgb444 = [], []
    for i in range(NCOLORS):
        r8, g8, b8 = pal[i * 3], pal[i * 3 + 1], pal[i * 3 + 2]
        r4, g4, b4 = r8 >> 4, g8 >> 4, b8 >> 4
        ocs.append((r4 << 8) | (g4 << 4) | b4)
        rgb444.append((r4 * 17, g4 * 17, b4 * 17))

    # planarisation : plan p = bit p de l'index ; bit 7 de l'octet = pixel gauche
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

    # auto-verif : reconstruire le chunky depuis les plans et comparer
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

    with open(RAW, "wb") as f:
        f.write(planes)

    ref = Image.new("RGB", (WIDTH, HEIGHT))
    ref.putdata([rgb444[v] for v in idx])
    ref.save(REF)

    lines = [
        "; src/graphics/bootscreen_data.s — donnees GENEREES par mk_bootscreen.py. NE PAS editer a la main.",
        "; Palette OCS (32x RGB444) + 5 bitplanes planar (plan 0 = LSB) de l'ecran de boot (chaton KickSlopStart).",
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
        '        incbin  "bootscreen.raw"',
        "        EVEN",
        "",
    ]
    with open(ASM, "w") as f:
        f.write("\n".join(lines))

    print("OK: %s (%d o) + %s + %s ; couleurs OCS uniques = %d/%d"
          % (RAW, len(planes), ASM, REF, len(set(ocs)), NCOLORS))


if __name__ == "__main__":
    main()
