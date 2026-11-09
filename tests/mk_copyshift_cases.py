#!/usr/bin/env python3
"""Author shifted bitmap-copy inputs and independent whole-buffer pixel fingerprints."""
import struct

SIZE = 49152


def pattern():
    return bytearray().join(struct.pack(">I", (0x13579BDF + i * 0x0103070B) & 0xFFFFFFFF)
                            for i in range(SIZE // 4))


def cases():
    # Source/destination strides, plane offsets, depths, mask, coordinates, extent, minterm.
    yield [58, 80, 16, 16384, 1, 1, 255, 0, 4, 74, 39, 456, 107, 0xC0]
    for i in range(64):
        yield [58 + ((i >> 5) & 1), 80, 16 + ((i >> 3) & 1), 16384 + ((i >> 2) & 1),
               1, 2, 1 if i & 16 else 3, i & 7, 1 + (i & 3), 32 + ((i >> 3) & 7),
               9 + (i & 3), 1 + ((i * 7) & 63), 3, 0xC0]
    # Aliased BitMap structures, safe leftward overlap. Later source pixels remain intact.
    yield [58, 58, 16, 16, 1, 1, 255, 19, 4, 2, 4, 111, 2, 0xC0]
    yield [58, 80, 0, 16384, 1, 2, 3, 3, 2, 37, 8, 71, 4, 0xC0]
    yield [58, 80, -1, 16384, 1, 2, 3, 3, 2, 37, 8, 71, 4, 0xC0]
    yield [58, 80, 16, 16384, 1, 2, 3, 3, 2, 37, 8, 71, 4, 0x60]
    yield [58, 80, 16, 16384, 1, 2, 0, 3, 2, 37, 8, 71, 4, 0xC0]


def expected(c):
    sb, db, so, do, sd, dd, mask, sx, sy, dx, dy, w, h, mt = c
    initial = pattern()
    result = initial.copy()
    for plane in range(dd):
        if not mask & (1 << plane):
            continue
        for y in range(h):
            for x in range(w):
                source = 0
                if plane < sd:
                    if so == -1:
                        source = 1
                    elif so:
                        off = so + plane * 7424 + (sy + y) * sb + (sx + x) // 8
                        source = (initial[off] >> (7 - ((sx + x) & 7))) & 1
                off = do + plane * 12800 + (dy + y) * db + (dx + x) // 8
                bit = 7 - ((dx + x) & 7)
                dest = (initial[off] >> bit) & 1
                value = (mt >> (4 + source * 2 + dest)) & 1
                result[off] = (result[off] & ~(1 << bit)) | (value << bit)
    value = 0
    for word, in struct.iter_unpack(">I", result):
        value = (((value << 5) | (value >> 27)) + word) & 0xFFFFFFFF
    return value


def main():
    rows = list(cases())
    print("; Generated from authored input patterns and a per-pixel public-operation oracle.")
    print(f"COPY_CASES EQU {len(rows)}")
    print("copy_cases:")
    for row in rows:
        print("        dc.w " + ",".join(map(str, row)))
        print(f"        dc.l ${expected(row):08x}")


if __name__ == "__main__":
    main()
