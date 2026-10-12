#!/usr/bin/env python3
"""Assemble une image ROM Kickstart brute a partir d'un binaire vasm (-Fbin).

Place le binaire au debut, complete a la taille voulue (256K ou 512K),
inscrit le champ de taille et la somme de controle Kickstart dans le footer.

Format conteneur (public : Cloanto ROM FAQ, amitools romtool) :
  - footer, pour une ROM de SIZE octets :
      offset SIZE-0x18 : somme de controle (longword, big-endian)
      offset SIZE-0x14 : taille de la ROM (longword = SIZE)
  - somme de controle valide = somme de tous les longwords (carry replie)
    egale a 0xFFFFFFFF, champ checksum inclus.

Ces faits sont du FORMAT de conteneur, pas du code Kickstart : utilisables
cote implementation sans violer le firewall clean-room.
"""
import argparse
import sys

CSUM_FROM_END = 0x18    # offset du checksum depuis la fin
SIZE_FROM_END = 0x14    # offset du champ taille depuis la fin
FOOTER_FROM_END = 0x10  # offset des 8 mots de footer depuis la fin
ROMBASE = 0xFC0000      # base d'une image 256K


def kick_sum(data: bytes) -> int:
    """Somme des longwords avec repli de la retenue (addition 1-complement)."""
    s = 0
    for i in range(0, len(data), 4):
        s += int.from_bytes(data[i:i + 4], "big")
        if s > 0xFFFFFFFF:
            s = (s & 0xFFFFFFFF) + 1
    return s


def build(src: bytes, size: int) -> bytes:
    if len(src) > size:
        sys.exit(f"erreur : binaire ({len(src)} o) plus grand que la ROM ({size} o)")

    rom = bytearray(size)
    rom[:len(src)] = src

    # Validation defensive de l'en-tete de reset (magic/header).
    ssp = int.from_bytes(rom[0:4], "big")
    pc = int.from_bytes(rom[4:8], "big")
    if rom[0:2] != b"\x11\x11":
        sys.exit(f"erreur : mot ROM-ID attendu 0x1111, trouve 0x{rom[0]:02X}{rom[1]:02X}")
    if not (ROMBASE <= pc <= ROMBASE + size - 1):
        sys.exit(f"erreur : PC de reset 0x{pc:08X} hors de la ROM "
                 f"[0x{ROMBASE:06X}..0x{ROMBASE + size - 1:06X}]")

    # Footer Kickstart : 8 mots 0x0018..0x001F a partir de size-0x10
    # (cf. amitools KickRomAccess.write_footer ; check_footer valide 0x19..0x1F).
    off = size - FOOTER_FROM_END
    for i in range(8):
        rom[off:off + 2] = (0x18 + i).to_bytes(2, "big")
        off += 2

    # Champ taille puis checksum (checksum calcule champ a zero).
    rom[size - SIZE_FROM_END:size - SIZE_FROM_END + 4] = size.to_bytes(4, "big")
    rom[size - CSUM_FROM_END:size - CSUM_FROM_END + 4] = (0).to_bytes(4, "big")
    partial = kick_sum(rom)
    csum = (0xFFFFFFFF - partial) & 0xFFFFFFFF
    rom[size - CSUM_FROM_END:size - CSUM_FROM_END + 4] = csum.to_bytes(4, "big")

    # Verification : la somme totale doit faire 0xFFFFFFFF.
    total = kick_sum(rom)
    if total != 0xFFFFFFFF:
        sys.exit(f"erreur interne : checksum invalide (somme=0x{total:08X})")

    print(f"image : {size} o | SSP=0x{ssp:08X} PC=0x{pc:08X} | "
          f"checksum=0x{csum:08X} (somme=0x{total:08X} OK)")
    return bytes(rom)


def main() -> None:
    ap = argparse.ArgumentParser(description="Assemble une image ROM Kickstart brute.")
    ap.add_argument("--in", dest="src", required=True, help="binaire vasm -Fbin")
    ap.add_argument("--out", dest="dst", required=True, help="image ROM de sortie")
    ap.add_argument("--size", type=int, default=256, choices=(256, 512),
                    help="taille en Kio (defaut 256)")
    args = ap.parse_args()

    with open(args.src, "rb") as f:
        src = f.read()
    rom = build(src, args.size * 1024)
    with open(args.dst, "wb") as f:
        f.write(rom)


if __name__ == "__main__":
    main()
