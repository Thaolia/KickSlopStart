#!/usr/bin/env python3
# tests/mk_ofs_testfile.py - generates the deterministic content of the OFS test file "KickSlop" (proof D1).
# 1024 bytes (= 3 OFS data blocks of 488 bytes) with markers at the block boundaries: @0 "D1OFSOK0",
# @488 "D1OFSOK1" (2nd block), @976 "D1OFSOK2" (3rd block). The rest = deterministic pattern.
# Run via `python3 -I`. Usage: mk_ofs_testfile.py <output.bin>
import sys

SIZE = 1024
MARKERS = {0: b"D1OFSOK0", 488: b"D1OFSOK1", 976: b"D1OFSOK2"}


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: mk_ofs_testfile.py <out.bin>")
    data = bytearray((i * 7) & 0xFF for i in range(SIZE))
    for off, mark in MARKERS.items():
        data[off:off + len(mark)] = mark
    open(sys.argv[1], "wb").write(data)
    print(f"fichier test OFS : {SIZE} o, marqueurs @ {sorted(MARKERS)} -> {sys.argv[1]}")


if __name__ == "__main__":
    main()
