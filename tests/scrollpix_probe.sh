#!/usr/bin/env bash
# tests/scrollpix_probe.sh - builds tests/scrollpix_probe.s, runs it from the startup-sequence of a bootable OFS disk
# in an Amiberry session and writes its "SR" lines (checksums of the planes after a vertical ScrollRaster for many
# edges and distances) to <out_dir>/scrollpix.txt. With a reference file, prints SCROLLPIX OK when both match (e.g.
# the output of the ROM before a change to ScrollRaster).
#
# Usage: tests/scrollpix_probe.sh <out_dir> [rom=build/kick13-prod.rom] [reference scrollpix.txt]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"; REF="${3:-}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/scrollpix_probe" "$ROOT/tests/scrollpix_probe.s" || exit 2
printf 'df0:scrollpix_probe\n' > "$OUT/startup"
ADF="$OUT/scrollpix_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/scrollpix_probe" scrollpix_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="spx$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" >/dev/null || exit 2
"$A" wait-serial "$NAME" "SR END" 240; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | grep '^SR ' > "$OUT/scrollpix.txt"
"$A" stop "$NAME" >/dev/null
echo "$(grep -c '^SR [0-9]' "$OUT/scrollpix.txt") lines in $OUT/scrollpix.txt"
[ $RC = 0 ] || exit $RC
[ -n "$REF" ] || exit 0
if diff "$REF" "$OUT/scrollpix.txt"; then echo "SCROLLPIX OK"; else echo "SCROLLPIX DIFFERS"; exit 1; fi
