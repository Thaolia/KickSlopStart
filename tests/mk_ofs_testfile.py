#!/usr/bin/env python3
# tests/mk_ofs_testfile.py — génère le contenu déterministe du fichier de test OFS « KickSlop » (preuve D1).
# 1024 octets (= 3 data blocks OFS de 488 o) avec marqueurs aux frontières de block : @0 « D1OFSOK0 »,
# @488 « D1OFSOK1 » (2e block), @976 « D1OFSOK2 » (3e block). Le reste = motif déterministe.
# Lancer via `python3 -I`. Usage : mk_ofs_testfile.py <sortie.bin>
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
