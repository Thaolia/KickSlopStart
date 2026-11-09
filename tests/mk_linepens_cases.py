#!/usr/bin/env python3
"""Authored lines, per-plane truth tables and independent full-buffer pixel fingerprints."""
import struct

SIZE = 8192
PLANE = 1536
LINES = [(8, 4, 112, 4), (112, 8, 8, 8), (12, 10, 12, 84), (20, 84, 20, 10),
         (28, 16, 104, 48), (104, 54, 28, 22), (30, 30, 60, 84), (80, 84, 50, 30),
         (102, 18, 38, 64), (34, 68, 98, 22), (96, 12, 68, 80), (64, 80, 92, 12),
         (55, 42, 55, 42)]


def points(line):
    x, y, end_x, end_y = line
    dx, dy = abs(end_x - x), abs(end_y - y)
    sx, sy = (1 if end_x >= x else -1), (1 if end_y >= y else -1)
    major, minor = max(dx, dy), min(dx, dy)
    error = 2 * minor - major
    for k in range(major + 1):
        yield x, y, k
        if dx > dy:
            x += sx
            if error >= 0:
                y += sy
        else:
            y += sy
            if error >= 0:
                x += sx
        error += 2 * (minor - major) if error >= 0 else 2 * minor


def fingerprint(case):
    mode, depth, odd, layer, pattern, mask, repeats, _, *mt = case
    data = bytearray().join(struct.pack(">I", (0x2468ACE1 + i * 0x01030507) & 0xFFFFFFFF)
                            for i in range(SIZE // 4))
    for _ in range(repeats):
        for line in LINES:
            for x, y, k in points(line):
                source = (pattern >> ((15 - k) & 15)) & 1
                x += 5 if layer else 0
                y += 3 if layer else 0
                for plane in range(depth):
                    if not mask & (1 << plane):
                        continue
                    off = 16 + odd + plane * PLANE + y * 16 + x // 8
                    bit = 7 - (x & 7)
                    destination = (data[off] >> bit) & 1
                    value = (mt[plane] >> (4 + source * 2 + destination)) & 1
                    data[off] = (data[off] & ~(1 << bit)) | (value << bit)
    value = 0
    for word, in struct.iter_unpack(">I", data):
        value = (((value << 5) | (value >> 27)) + word) & 0xFFFFFFFF
    return value


def main():
    cases = []
    for depth, odd, layer, pattern, mask, mt in [
            (2, 0, 0, 0xFFFF, 3, [0x6A, 0xAA]),
            (5, 0, 0, 0xA35C, 31, [0x6A, 0xAA, 0x3A, 0xCA, 0xFA]),
            (5, 0, 1, 0xFFFF, 21, [0x6A, 0xAA, 0x3A, 0xCA, 0x0A]),
            (2, 1, 0, 0xA35C, 3, [0x6A, 0x5A])]:
        for mode in range(8):
            cases.append([mode, depth, odd, layer, pattern, mask, 1, 0] + mt + [0xAA] * (8 - len(mt)))
    # Erase a complete crosshair/line set by drawing it twice, with pens/mode deliberately inconsistent.
    cases.append([1, 5, 0, 0, 0xFFFF, 31, 2, 0] + [0x6A] * 8)
    print("; Authored input vectors and independently rasterized public-operation expectations.")
    print(f"LINE_CASES EQU {len(cases)}")
    print(f"LINE_COUNT EQU {len(LINES)}")
    print("line_cases:")
    for case in cases:
        print("        dc.w " + ",".join(map(str, case[:8])))
        print("        dc.b " + ",".join(map(str, case[8:])))
        print(f"        dc.l ${fingerprint(case):08x}")
    print("line_points:")
    for line in LINES:
        print("        dc.w " + ",".join(map(str, line)))


if __name__ == "__main__":
    main()
