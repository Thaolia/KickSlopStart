#!/usr/bin/env python3
# tests/patch_bootblock.py — patche le bootblock (secteurs 0+1 = 1024 o) d'un ADF avec un boot code custom
# et un checksum additif VALIDE, puis round-trip un validateur (assert bootable). Lance via `python3 -I`.
#
# Usage : patch_bootblock.py <adf_formate_in> <bootcode_bin> <adf_out>
#
# Checksum bootblock AmigaDOS = somme à retenue CIRCULAIRE (one's-complement / end-around carry) des 256
# longs ; un bloc est valide ssi magic « DOS » ET cette somme (checksum inclus) == 0xFFFFFFFF.
import sys
import struct

BB_LEN = 1024
BB_ENTRY = 12          # offset du boot code
CSUM_OFF = 4           # offset du champ checksum


def ones_complement_sum(block):
    """Somme à retenue circulaire des 256 longs d'un bloc de 1024 o."""
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
    # magic « DOS\0 » (préservé si déjà posé par le format ; on le force pour être sûr)
    bb[0:4] = b"DOS\x00"
    # pointeur rootblock (offset 8) laissé tel que posé par le format (880 sur un DD OFS)
    # champ checksum à 0 avant calcul
    bb[CSUM_OFF:CSUM_OFF + 4] = b"\x00\x00\x00\x00"
    # boot code à +12 (le reste reste tel quel / zéro)
    bb[BB_ENTRY:BB_ENTRY + len(code)] = code
    # checksum = complément à un de la somme (champ checksum = 0)
    csum = (~ones_complement_sum(bb)) & 0xFFFFFFFF
    bb[CSUM_OFF:CSUM_OFF + 4] = struct.pack(">I", csum)

    # round-trip : le bloc patché DOIT être bootable
    if not is_bootable(bb):
        sys.exit("ECHEC round-trip : le bootblock patché n'est pas bootable")

    img[:BB_LEN] = bb
    open(adf_out, "wb").write(img)

    # contrôle négatif : l'ADF formaté d'origine NE doit PAS être bootable (checksum=0)
    orig = open(adf_in, "rb").read(BB_LEN)
    orig_bootable = is_bootable(orig)
    print(f"boot code     : {len(code)} o -> offset +{BB_ENTRY}")
    print(f"checksum posé : 0x{csum:08X}")
    print(f"patché bootable : {is_bootable(bb)}  (attendu True)")
    print(f"ADF formaté d'origine bootable : {orig_bootable}  (attendu False)")
    print(f"écrit : {adf_out} ({len(img)} o)")
    if orig_bootable:
        sys.exit("ANOMALIE : l'ADF formaté d'origine est déjà bootable (contrôle négatif KO)")


if __name__ == "__main__":
    main()
