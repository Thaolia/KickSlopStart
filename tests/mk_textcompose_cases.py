#!/usr/bin/env python3
"""Authored proportional-font glyph cases and independent per-pixel Text fingerprints."""
import struct

STRIKE = bytes(((i * 37 + 0x96) ^ (i >> 1)) & 255 for i in range(41))

def expected(src, width, dx, mode, mask, kern, spacing, foreground, background):
    image = bytearray((0xA5 ^ (i * 29)) & 255 for i in range(544))
    advance = 10 + kern + spacing
    left, right = min(0, kern), 12 * advance
    for y in range(8):
        for x in range(128):
            rel = x - dx
            if not left <= rel < right:
                continue
            glyph = 0
            for n in range(12):
                bit = rel - (n * advance + kern)
                if 0 <= bit < width:
                    pos = src + bit
                    byte = STRIKE[(src & 1) + y * 5 + pos // 8]
                    glyph |= (byte >> (7 - (pos & 7))) & 1
            for p in range(2):
                if not mask & (1 << p):
                    continue
                off = 16 + p * 256 + (y + 2) * 16 + x // 8
                bit = 7 - (x & 7)
                old = (image[off] >> bit) & 1
                fg, bg = (foreground >> p) & 1, (background >> p) & 1
                if mode == 0:
                    value = fg if glyph else old
                elif mode == 1:
                    value = fg if glyph else bg
                elif mode == 2:
                    value = old ^ glyph
                else:
                    value = old if glyph else fg
                image[off] = (image[off] & ~(1 << bit)) | value << bit
    checksum = 0
    for word, in struct.iter_unpack('>I', image):
        checksum = (((checksum << 5) | (checksum >> 27)) + word) & 0xFFFFFFFF
    return checksum


def main():
    print('; Generated from authored strike bytes and an independent pixel model.')
    print('TEXTCOMPOSE_CASES EQU 8*9*8*4')
    print('compose_strike:')
    print('        dc.b ' + ','.join(f'${x:02x}' for x in STRIKE))
    print('        even')
    print('compose_cases:')
    for src in range(8):
        for width in range(1, 10):
            for dx in range(8):
                for mode in [0, 1, 2, 4]:
                    mask = 3 if (src + dx) & 1 else 1
                    kern, spacing = (-2 if src & 1 else 0), dx & 1
                    cursor = dx + 12 * (10 + kern + spacing)
                    foreground, background = src >> 1, dx >> 1
                    print('        dc.w ' + ','.join(map(str, [src, width, dx, mode, mask, kern, spacing, cursor, foreground, background])))
                    print(f'        dc.l ${expected(src, width, dx, mode, mask, kern, spacing, foreground, background):08x}')



if __name__ == '__main__':
    main()
