#!/usr/bin/env bash
# tests/bltrp_probe.sh - builds tests/bltrp_probe.s (CLI executable), runs it from the startup-sequence of a bootable
# OFS disk in an Amiberry session on our ROM and checks that BltBitMapRastPort copied every pixel of every case
# (minterm $C0 for every source phase 0-15 against every destination phase, $30/$60/$80/$E0 every third phase,
# blitter-sized rectangles, two planes).
#
# Usage: tests/bltrp_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/bltrp_probe" "$ROOT/tests/bltrp_probe.s" || exit 2
printf 'df0:bltrp_probe\n' > "$OUT/startup"
ADF="$OUT/bltrp_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/bltrp_probe" bltrp_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="brp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" >/dev/null || exit 2
"$A" wait-serial "$NAME" "BR END" 2400; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | grep -a '^BR ' > "$OUT/bltrp.txt"
"$A" stop "$NAME" >/dev/null
[ $RC = 0 ] || exit $RC
cat "$OUT/bltrp.txt"
if grep -q '^BR CASES .* BAD 00000000$' "$OUT/bltrp.txt"; then echo "BLTRP OK"; else echo "BLTRP FAIL"; exit 1; fi
