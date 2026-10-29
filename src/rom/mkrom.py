#!/usr/bin/env python3
"""Build a raw Kickstart ROM image from a vasm binary (-Fbin).

Places the binary at the start, pads it to the requested size (256K or 512K),
and writes the size field and the Kickstart checksum into the footer.

Container format (public: Cloanto ROM FAQ, amitools romtool):
  - footer, for a ROM of SIZE bytes:
      offset SIZE-0x18: checksum (longword, big-endian)
      offset SIZE-0x14: ROM size (longword = SIZE)
  - valid checksum = sum of all longwords (carry folded back in)
    equal to 0xFFFFFFFF, checksum field included.

These facts describe the container FORMAT, not Kickstart code: usable
on the implementation side without breaching the clean-room firewall.
"""
import argparse
import sys

CSUM_FROM_END = 0x18    # offset of the checksum from the end
SIZE_FROM_END = 0x14    # offset of the size field from the end
FOOTER_FROM_END = 0x10  # offset of the 8 footer words from the end
ROMBASE = 0xFC0000      # base of a 256K image


def kick_sum(data: bytes) -> int:
    """Sum of longwords with end-around carry (ones' complement addition)."""
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

    # Defensive validation of the reset header (magic/header).
    ssp = int.from_bytes(rom[0:4], "big")
    pc = int.from_bytes(rom[4:8], "big")
    if rom[0:2] != b"\x11\x11":
        sys.exit(f"erreur : mot ROM-ID attendu 0x1111, trouve 0x{rom[0]:02X}{rom[1]:02X}")
    if not (ROMBASE <= pc <= ROMBASE + size - 1):
        sys.exit(f"erreur : PC de reset 0x{pc:08X} hors de la ROM "
                 f"[0x{ROMBASE:06X}..0x{ROMBASE + size - 1:06X}]")

    # Kickstart footer: 8 words 0x0018..0x001F starting at size-0x10
    # (see amitools KickRomAccess.write_footer; check_footer validates 0x19..0x1F).
    off = size - FOOTER_FROM_END
    for i in range(8):
        rom[off:off + 2] = (0x18 + i).to_bytes(2, "big")
        off += 2

    # Size field, then checksum (checksum computed with the field zeroed).
    rom[size - SIZE_FROM_END:size - SIZE_FROM_END + 4] = size.to_bytes(4, "big")
    rom[size - CSUM_FROM_END:size - CSUM_FROM_END + 4] = (0).to_bytes(4, "big")
    partial = kick_sum(rom)
    csum = (0xFFFFFFFF - partial) & 0xFFFFFFFF
    rom[size - CSUM_FROM_END:size - CSUM_FROM_END + 4] = csum.to_bytes(4, "big")

    # Check: the total sum must be 0xFFFFFFFF.
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
    # 256K only: the header (ROMBASE=$FC0000, ROM-ID 0x1111) is specific to
    # 256K. A 512K image is based at $F80000 with a different ROM-ID -> later
    # milestone (base + ROM-ID will need parameters), not just a size change.
    ap.add_argument("--size", type=int, default=256, choices=(256,),
                    help="taille en Kio (256 uniquement pour l'instant)")
    args = ap.parse_args()

    with open(args.src, "rb") as f:
        src = f.read()
    rom = build(src, args.size * 1024)
    with open(args.dst, "wb") as f:
        f.write(rom)


if __name__ == "__main__":
    main()
