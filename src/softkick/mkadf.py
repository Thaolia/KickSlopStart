#!/usr/bin/env python3
"""Build the soft-kick disk: a DD ADF whose bootblock loads the KickSlopStart RAM image into slow RAM.

Layout (public AmigaDOS formats: bootblock, OFS root and bitmap blocks):
  - blocks 0-1: "DOS\\0", bootblock checksum, root pointer 880, boot code at +12 (src/softkick/bootblock.s);
  - blocks 2..513: the 256K image built by `make kick-ram` (linked at $C00000);
  - an empty OFS filesystem named "KickSlopStart" whose bitmap marks the image blocks as used, so that the disk
    stays readable and writing to it never overwrites the image.
Dates are fixed so that the same inputs always give the same ADF.
"""
import argparse
import struct
import sys

BLOCK = 512
BLOCKS = 1760                # DD floppy: 80 cylinders x 2 heads x 11 sectors
BOOT_LEN = 2 * BLOCK
BOOT_CODE = 12
IMG_FIRST = 2
IMG_SIZE = 0x40000
IMG_BASE = 0xC00000
ROOT = 880
BITMAP = 881
VOLUME = b"KickSlopStart"
DATE = (0, 0, 0)             # days, minutes, ticks since 1978-01-01


def kick_sum(data: bytes) -> int:
    """Sum of longwords with end-around carry (bootblock and Kickstart checksums)."""
    s = 0
    for i in range(0, len(data), 4):
        s += int.from_bytes(data[i:i + 4], "big")
        if s > 0xFFFFFFFF:
            s = (s & 0xFFFFFFFF) + 1
    return s


def plain_sum(block: bytes) -> int:
    return sum(struct.unpack(">128I", block)) & 0xFFFFFFFF


def check_image(img: bytes) -> None:
    if len(img) != IMG_SIZE:
        sys.exit(f"erreur : image de {len(img)} o, 262144 attendus")
    if img[0:2] != b"\x11\x11":
        sys.exit("erreur : l'image ne commence pas par l'en-tête Kickstart $1111")
    pc = int.from_bytes(img[4:8], "big")
    if not IMG_BASE <= pc < IMG_BASE + IMG_SIZE:
        sys.exit(f"erreur : PC de reset 0x{pc:08X} hors de [$C00000,$C40000) : image construite par make kick-ram ?")
    if kick_sum(img) != 0xFFFFFFFF:
        sys.exit("erreur : somme Kickstart de l'image invalide")


def bootblock(code: bytes) -> bytes:
    if BOOT_CODE + len(code) > BOOT_LEN:
        sys.exit(f"erreur : code de boot de {len(code)} o (max {BOOT_LEN - BOOT_CODE})")
    bb = bytearray(BOOT_LEN)
    bb[0:4] = b"DOS\x00"
    bb[8:12] = ROOT.to_bytes(4, "big")
    bb[BOOT_CODE:BOOT_CODE + len(code)] = code
    bb[4:8] = ((~kick_sum(bb)) & 0xFFFFFFFF).to_bytes(4, "big")
    assert kick_sum(bb) == 0xFFFFFFFF
    return bytes(bb)


def root_block() -> bytes:
    b = bytearray(BLOCK)
    struct.pack_into(">I", b, 0x000, 2)            # T_HEADER
    struct.pack_into(">I", b, 0x00C, 72)           # hash table size
    struct.pack_into(">I", b, 0x138, 0xFFFFFFFF)   # bitmap valid
    struct.pack_into(">I", b, 0x13C, BITMAP)
    for off in (0x1A4, 0x1D8, 0x1E4):              # root, volume and creation dates
        struct.pack_into(">3I", b, off, *DATE)
    b[0x1B0] = len(VOLUME)
    b[0x1B1:0x1B1 + len(VOLUME)] = VOLUME
    struct.pack_into(">I", b, 0x1FC, 1)            # ST_ROOT
    struct.pack_into(">I", b, 0x014, (-plain_sum(b)) & 0xFFFFFFFF)
    return bytes(b)


def bitmap_block() -> bytes:
    used = set(range(IMG_FIRST, IMG_FIRST + IMG_SIZE // BLOCK)) | {ROOT, BITMAP}
    longs = [0] * 128
    for blk in range(2, BLOCKS):                   # bit set = free; blocks 0-1 are not in the map
        if blk not in used:
            n = blk - 2
            longs[1 + n // 32] |= 1 << (n % 32)
    b = bytearray(struct.pack(">128I", *longs))
    struct.pack_into(">I", b, 0, (-plain_sum(b)) & 0xFFFFFFFF)
    return bytes(b)


def main() -> None:
    ap = argparse.ArgumentParser(description="Construit la disquette de soft-kick KickSlopStart.")
    ap.add_argument("--boot", required=True, help="code de boot (vasm -Fbin de src/softkick/bootblock.s)")
    ap.add_argument("--image", required=True, help="image RAM de make kick-ram")
    ap.add_argument("--out", required=True, help="ADF de sortie")
    args = ap.parse_args()

    with open(args.boot, "rb") as f:
        code = f.read()
    with open(args.image, "rb") as f:
        img = f.read()
    check_image(img)

    adf = bytearray(BLOCKS * BLOCK)
    adf[0:BOOT_LEN] = bootblock(code)
    adf[IMG_FIRST * BLOCK:IMG_FIRST * BLOCK + IMG_SIZE] = img
    adf[ROOT * BLOCK:(ROOT + 1) * BLOCK] = root_block()
    adf[BITMAP * BLOCK:(BITMAP + 1) * BLOCK] = bitmap_block()
    with open(args.out, "wb") as f:
        f.write(adf)
    print(f"ADF : {len(adf)} o | code de boot {len(code)} o | image blocs {IMG_FIRST}..{IMG_FIRST + IMG_SIZE // BLOCK - 1}")


if __name__ == "__main__":
    main()
