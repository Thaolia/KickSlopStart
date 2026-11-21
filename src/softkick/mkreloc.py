#!/usr/bin/env python3
"""Build the relocation table of the soft-kick image from two links of the same sources.

`make kick-ram` links the image at $C00000 (the one on the disk) and a second time at another base. Every
difference between the two must be a longword holding an address of the image (a value in [base, base+256K]) that
moved by exactly the difference of the bases; the Kickstart checksum longword of the footer is the only other one
allowed (the disk recomputes it after relocating). Anything else (an address split in words, a value derived from
the base in another way) stops the build, because such a value would not follow the image.

Output (big-endian): a longword N, then N words; word i is the distance in words from the previous relocated
longword (from the start of the image for the first). The disk adds (load address - $C00000) to each of them.
"""
import argparse
import struct
import sys

IMG_SIZE = 0x40000
CSUM_OFF = IMG_SIZE - 0x18      # Kickstart checksum longword (src/rom/mkrom.py footer)


def long_at(img: bytes, off: int) -> int:
    return int.from_bytes(img[off:off + 4], "big")


def find_relocs(a: bytes, b: bytes, base: int, base2: int) -> list[int]:
    delta = (base2 - base) & 0xFFFFFFFF
    relocs: list[int] = []
    end = -1                    # first byte after the last relocated longword
    for pos in range(IMG_SIZE):
        if a[pos] == b[pos] or pos < end or CSUM_OFF <= pos < CSUM_OFF + 4:
            continue
        for start in range(pos - 3, pos + 1):
            if start < max(0, end) or start % 2 or start + 4 > IMG_SIZE:
                continue
            if CSUM_OFF - 4 < start < CSUM_OFF + 4:
                continue
            va, vb = long_at(a, start), long_at(b, start)
            if (vb - va) & 0xFFFFFFFF == delta and base <= va <= base + IMG_SIZE:
                relocs.append(start)
                end = start + 4
                break
        else:
            sys.exit(f"erreur : octet +0x{pos:05X} différent entre les deux liens ({a[pos]:02X}/{b[pos]:02X}) sans "
                     f"être dans une adresse de l'image")
    return relocs


def apply(img: bytes, relocs: list[int], delta: int) -> bytearray:
    out = bytearray(img)
    for off in relocs:
        v = (long_at(out, off) + delta) & 0xFFFFFFFF
        out[off:off + 4] = v.to_bytes(4, "big")
    return out


def encode(relocs: list[int]) -> bytes:
    words = []
    prev = 0
    for off in relocs:
        gap = (off - prev) // 2
        if gap > 0xFFFF:
            sys.exit(f"erreur : écart de {off - prev} o entre deux relocations (max 131070)")
        words.append(gap)
        prev = off
    return struct.pack(f">I{len(words)}H", len(words), *words)


def main() -> None:
    ap = argparse.ArgumentParser(description="Construit la table de relocation de l'image soft-kick.")
    ap.add_argument("--image", required=True, help="image de make kick-ram liée en --base")
    ap.add_argument("--base", type=lambda v: int(v, 0), required=True)
    ap.add_argument("--image2", required=True, help="la même image liée en --base2")
    ap.add_argument("--base2", type=lambda v: int(v, 0), required=True)
    ap.add_argument("--out", required=True, help="table de sortie")
    args = ap.parse_args()

    with open(args.image, "rb") as f:
        a = f.read()
    with open(args.image2, "rb") as f:
        b = f.read()
    if len(a) != IMG_SIZE or len(b) != IMG_SIZE:
        sys.exit("erreur : images de 262144 o attendues")
    if args.base == args.base2:
        sys.exit("erreur : les deux bases doivent différer")

    relocs = find_relocs(a, b, args.base, args.base2)
    moved = apply(a, relocs, (args.base2 - args.base) & 0xFFFFFFFF)
    moved[CSUM_OFF:CSUM_OFF + 4] = b[CSUM_OFF:CSUM_OFF + 4]
    if bytes(moved) != b:
        sys.exit("erreur interne : la table appliquée à l'image ne redonne pas la seconde image")
    table = encode(relocs)
    with open(args.out, "wb") as f:
        f.write(table)
    print(f"relocations : {len(relocs)} | table {len(table)} o | appliquée à l'image = seconde image (OK)")


if __name__ == "__main__":
    main()
