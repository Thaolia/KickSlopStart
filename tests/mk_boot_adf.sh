#!/usr/bin/env bash
# tests/mk_boot_adf.sh - builds the BOOTABLE test ADF of milestone C.
# Formats a DD ADF (xdftool), assembles tests/bootblock_c.s into a raw binary (vasm -Fbin), then patches the
# bootblock (valid additive checksum + custom boot code) through tests/patch_bootblock.py with a round-trip.
# Output: assets/boot_c.adf (NOT committed - regenerable). The ADF stays a valid OFS filesystem (track 2
# stays readable by M6X, sector 0 keeps the "DOS\0" magic read by M6W). patch_bootblock.py also writes
# spanning markers ("SPAN0010"/"SPAN0011" at the head of free blocks 10/11 = track 0/1 boundary) consumed
# by the M6Z proof (multi-track CMD_READ, prerequisite for D). An OFS file "KickSlop" (1024 bytes) is also
# written to the disk for the D1 proof (read-only OFS: read a file by name).
#
# Usage: tests/mk_boot_adf.sh [output_path.adf]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/assets/boot_c.adf}"
VASM="${VASM:-vasmm68k_mot}"
VLINK="${VLINK:-vlink}"
XDFTOOL="${XDFTOOL:-xdftool}"

for t in "$VASM" "$VLINK" "$XDFTOOL" python3; do
  command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$(dirname "$OUT")"

# 1) OFS-formatted DD ADF (provides a valid filesystem: rootblock @880, readable tracks). NO install:
#    we write OUR bootblock afterwards. Formatting leaves checksum=0 -> not bootable until patched.
"$XDFTOOL" "$TMP/fmt.adf" format "KickSlopC" >/dev/null

# 2) OFS test file "KickSlop" (D1 proof: read by name). MIXED case (stored as "KickSlop", looked up as
#    "kickslop") to exercise the case-insensitive hash+compare. xdftool allocates it near the root (866-869)
#    -> blocks 10/11 stay free for the spanning markers (guard in patch_bootblock.py).
python3 -I "$ROOT/tests/mk_ofs_testfile.py" "$TMP/kickslop.bin"
"$XDFTOOL" "$TMP/fmt.adf" write "$TMP/kickslop.bin" KickSlop >/dev/null

# 2b) HUNK test executable "D2Test" (D2 proof: LoadSeg). vasm -Fhunk -> object; vlink -s -bamigahunk ->
#     stripped load file (HEADER/CODE/RELOC32/END/DATA/END, no SYMBOL). Written to the disk, read by LoadSeg.
"$VASM" -Fhunk -m68000 -o "$TMP/d2.o" "$ROOT/tests/loadseg_d2.s" >/dev/null
"$VLINK" -s -bamigahunk -o "$TMP/d2test" "$TMP/d2.o"
"$XDFTOOL" "$TMP/fmt.adf" write "$TMP/d2test" D2Test >/dev/null
# D3d: same hunk executable but a distinct marker, loaded THROUGH dos (Open/Read via packets) then executed.
"$VASM" -Fhunk -m68000 -o "$TMP/d3d.o" "$ROOT/tests/loadseg_d3d.s" >/dev/null
"$VLINK" -s -bamigahunk -o "$TMP/d3dtest" "$TMP/d3d.o"
"$XDFTOOL" "$TMP/fmt.adf" write "$TMP/d3dtest" D3DTest >/dev/null
# E3: command typed at the shell; name "e3cmd" on the disk, loaded+executed by the shell from DF0: via dos.
"$VASM" -Fhunk -m68000 -o "$TMP/e3.o" "$ROOT/tests/cmd_e3.s" >/dev/null
"$VLINK" -s -bamigahunk -o "$TMP/e3cmd" "$TMP/e3.o"
"$XDFTOOL" "$TMP/fmt.adf" write "$TMP/e3cmd" e3cmd >/dev/null
# LoadSeg cap bump: hunk executable > 16 KB ("bigseg", large DATA hunk + sentinel at the end) -> proves the
# raised READ cap (handler HS_BUF + LoadSeg buffer, 16K->32K). Loaded via LoadSeg(-150) by d3h_client.
"$VASM" -Fhunk -m68000 -o "$TMP/big.o" "$ROOT/tests/loadseg_big.s" >/dev/null
"$VLINK" -s -bamigahunk -o "$TMP/bigseg" "$TMP/big.o"
"$XDFTOOL" "$TMP/fmt.adf" write "$TMP/bigseg" bigseg >/dev/null
# Real OFS streaming: DATA file "BigData" > 32 KB (48000 bytes, > former whole-file cap DOS_FILEMAX) ->
# proves incremental reading data block by data block (the handler no longer buffers the whole file). Read by
# d3j_client via dos Open/Read (NOT LoadSeg, whose buffer stays capped). xdftool allocates it high (934+) -> blocks
# 10/11 (M6Z spanning markers) undisturbed (verified).
python3 -I "$ROOT/tests/mk_bigdata.py" "$TMP/bigdata.bin"
"$XDFTOOL" "$TMP/fmt.adf" write "$TMP/bigdata.bin" BigData >/dev/null
# F1 + OFS subdirectory: startup-sequence in the "s/" subdirectory (real AmigaDOS path "s/startup-sequence",
# resolved by ofs_read_file's subdirectory traversal). CR-terminated lines: "echo F1BOOTOK" proves the
# script is read+executed (builtin echo); "e3cmd" proves an EXTERNAL command launched from the script.
printf 'echo F1BOOTOK\re3cmd\r' > "$TMP/startup-sequence"
"$XDFTOOL" "$TMP/fmt.adf" makedir s >/dev/null
"$XDFTOOL" "$TMP/fmt.adf" write "$TMP/startup-sequence" s/startup-sequence >/dev/null

# 3) custom boot code -> raw binary
"$VASM" -Fbin -m68000 -o "$TMP/bb.bin" "$ROOT/tests/bootblock_c.s"

# 4) bootblock patch + spanning markers + round-trip (python3 -I: untrusted binary input, isolated env)
python3 -I "$ROOT/tests/patch_bootblock.py" "$TMP/fmt.adf" "$TMP/bb.bin" "$OUT"
echo "OK : $OUT"
