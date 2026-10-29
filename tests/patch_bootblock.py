#!/usr/bin/env python3
# tests/patch_bootblock.py - patches the bootblock (sectors 0+1 = 1024 bytes) of an ADF with custom boot code
# and a VALID additive checksum, then round-trips through a validator (assert bootable). Run via `python3 -I`.
#
# Usage: patch_bootblock.py <formatted_adf_in> <bootcode_bin> <adf_out>
#
# AmigaDOS bootblock checksum = sum with CIRCULAR carry (one's-complement / end-around carry) of the 256
# longwords; a block is valid iff magic "DOS" AND this sum (checksum included) == 0xFFFFFFFF.
import sys
import struct

BB_LEN = 1024
BB_ENTRY = 12          # offset of the boot code
CSUM_OFF = 4           # offset of the checksum field

# Spanning markers (M6z): 8 bytes at the start of logical blocks 10 and 11. Block 10 is the LAST sector of
# track 0, block 11 the FIRST of track 1 -> a CMD_READ of 1024 bytes from offset 10*512
# CROSSES the track 0/1 boundary and must assemble both tracks. Free blocks (zeros) on an empty OFS: writing
# them alters neither the bootblock (0-1) nor the root block (880); the filesystem is not mounted by M6z.
SECTOR = 512
SPAN_BLOCKS = {10: b"SPAN0010", 11: b"SPAN0011"}


def ones_complement_sum(block):
    """Sum with circular carry of the 256 longwords of a 1024-byte block."""
    s = 0
    for i in range(0, BB_LEN, 4):
        s += struct.unpack(">I", block[i:i + 4])[0]
        if s > 0xFFFFFFFF:
            s = (s & 0xFFFFFFFF) + 1
    return s & 0xFFFFFFFF


def is_bootable(block):
    return block[:3] == b"DOS" and ones_complement_sum(block) == 0xFFFFFFFF


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: patch_bootblock.py <adf_in> <bootcode_bin> <adf_out>")
    adf_in, bin_in, adf_out = sys.argv[1], sys.argv[2], sys.argv[3]

    img = bytearray(open(adf_in, "rb").read())
    code = open(bin_in, "rb").read()
    if len(img) < BB_LEN:
        sys.exit(f"ADF trop petit : {len(img)} o")
    if BB_ENTRY + len(code) > BB_LEN:
        sys.exit(f"boot code trop gros : {len(code)} o (max {BB_LEN - BB_ENTRY})")

    bb = bytearray(img[:BB_LEN])
    # magic "DOS\0" (preserved if already set by the format; forced here to be sure)
    bb[0:4] = b"DOS\x00"
    # rootblock pointer (offset 8) left as set by the format (880 on a DD OFS)
    # checksum field set to 0 before the computation
    bb[CSUM_OFF:CSUM_OFF + 4] = b"\x00\x00\x00\x00"
    # boot code at +12 (the rest stays as is / zero)
    bb[BB_ENTRY:BB_ENTRY + len(code)] = code
    # checksum = one's complement of the sum (checksum field = 0)
    csum = (~ones_complement_sum(bb)) & 0xFFFFFFFF
    bb[CSUM_OFF:CSUM_OFF + 4] = struct.pack(">I", csum)

    # round-trip: the patched block MUST be bootable
    if not is_bootable(bb):
        sys.exit("ECHEC round-trip : le bootblock patché n'est pas bootable")

    img[:BB_LEN] = bb

    # spanning markers (M6z): placed on free blocks, checked after writing
    for blk, mark in SPAN_BLOCKS.items():
        off = blk * SECTOR
        if any(img[off:off + len(mark)]):
            sys.exit(f"ANOMALIE : bloc {blk} non libre avant marqueur (0x{img[off:off+len(mark)].hex()})")
        img[off:off + len(mark)] = mark
    for blk, mark in SPAN_BLOCKS.items():
        off = blk * SECTOR
        if img[off:off + len(mark)] != mark:
            sys.exit(f"ECHEC round-trip marqueur bloc {blk}")

    open(adf_out, "wb").write(img)

    # negative check: the original formatted ADF must NOT be bootable (checksum=0)
    orig = open(adf_in, "rb").read(BB_LEN)
    orig_bootable = is_bootable(orig)
    print(f"boot code     : {len(code)} o -> offset +{BB_ENTRY}")
    print(f"checksum posé : 0x{csum:08X}")
    print(f"patché bootable : {is_bootable(bb)}  (attendu True)")
    print(f"marqueurs spanning : blocs {sorted(SPAN_BLOCKS)} posés + round-trip OK")
    print(f"ADF formaté d'origine bootable : {orig_bootable}  (attendu False)")
    print(f"écrit : {adf_out} ({len(img)} o)")
    if orig_bootable:
        sys.exit("ANOMALIE : l'ADF formaté d'origine est déjà bootable (contrôle négatif KO)")


if __name__ == "__main__":
    main()
