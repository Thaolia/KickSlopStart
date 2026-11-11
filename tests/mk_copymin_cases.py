#!/usr/bin/env python3
"""Authored bitmap Boolean/copy cases with independently evaluated pixel fingerprints."""
import struct


def cases():
    for mt in range(256):
        kind = mt & 3
        sb, db, so, do = (9, 11, 17, 2049) if kind == 3 else (8, 8, 16, 2048)
        sx, sy, dx, dy, w, h = [(8, 1, 8, 4, 24, 24), (8, 1, 16, 4, 24, 24),
                                (3, 2, 13, 5, 29, 5), (8, 1, 8, 4, 32, 20)][kind]
        yield [sb, db, so, do, 2, 2, 1 if mt & 8 else 3, sx, sy, dx, dy, w, h, mt, 32, 1024]
    for so in [0, -1]:
        yield [8, 8, so, 2048, 2, 2, 3, 0, 2, 0, 4, 32, 20, 0xCC, 32, 1024]
    yield [8, 8, 16, 16, 2, 2, 3, 16, 4, 0, 4, 40, 20, 0xCC, 32, 1024]
    yield [8, 8, 16, 2048, 2, 2, 0, 0, 2, 0, 4, 32, 20, 0xCC, 32, 1024]
    yield [8, 8, 16, 2048, 2, 2, 3, 0, 0, -8, -2, 40, 24, 0xCC, 32, 1024]
    for width in [520, 592, 632]:
        yield [80, 80, 16, 8192, 2, 2, 3, 0, 1, 0, 4, width, 20, 0xCC, 32, 4096]
    # Menu-strip backups, masked popup edges and unequal depths through every bitmap API.
    for mt in [0xC0, 0xCC]:
        for sb, db, sx, dx, width, height, sd, dd, mask in [
                (40, 40, 0, 0, 320, 11, 5, 5, 31),
                (22, 40, 0, 0, 167, 72, 5, 5, 31),
                (40, 22, 0, 0, 167, 72, 5, 5, 21),
                (40, 40, 3, 9, 167, 72, 2, 5, 3),
                (40, 14, 72, 8, 87, 176, 5, 5, 31),
                (14, 40, 8, 72, 87, 176, 5, 5, 5)]:
            yield [sb, db, 16, 51232, sd, dd, mask, sx, 0, dx, 1, width, height, mt, 256, 27648]
    for so, do in [(16, 51232), (17, 51233), (16, 51233)]:
        yield [40, 40, so, do, 5, 5, 31, 0, 11, 0, 11, 296, 245, 0xCC, 256, 27648]


def expected(c):
    sb, db, so, do, sd, dd, mask, sx, sy, dx, dy, w, h, mt, rows, units = c
    original = bytearray().join(struct.pack(">I", (0x13579BDF + i * 0x0103070B) & 0xFFFFFFFF)
                                for i in range(units))
    result = original.copy()
    for p in range(min(sd, dd)):
        if not mask & (1 << p):
            continue
        for y in range(h):
            for x in range(w):
                tx, ty, rx, ry = dx + x, dy + y, sx + x, sy + y
                if not (0 <= tx < db * 8 and 0 <= ty < rows and 0 <= rx < sb * 8 and 0 <= ry < rows):
                    continue
                b = 0 if so == 0 else 1 if so == -1 else (
                    original[so + p * sb * rows + ry * sb + rx // 8] >> (7 - (rx & 7))) & 1
                off = do + p * db * rows + ty * db + tx // 8
                bit = 7 - (tx & 7)
                dest = (original[off] >> bit) & 1
                value = (mt >> (4 + 2 * b + dest)) & 1
                result[off] = (result[off] & ~(1 << bit)) | (value << bit)
    value = 0
    for word, in struct.iter_unpack(">I", result):
        value = (((value << 5) | (value >> 27)) + word) & 0xFFFFFFFF
    return value


def main():
    data = list(cases())
    print("; Generated from authored bitmap patterns and an independent per-pixel Boolean oracle.")
    print(f"COPYMIN_CASES EQU {len(data)}")
    print("copymin_cases:")
    for i, c in enumerate(data):
        if i == len(data) - 3:
            print("copymin_large:")
        print("        dc.w " + ",".join(map(str, c)))
        print(f"        dc.l ${expected(c):08x}")


if __name__ == "__main__":
    main()
