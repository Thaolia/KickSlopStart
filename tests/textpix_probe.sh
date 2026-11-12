#!/usr/bin/env bash
# tests/textpix_probe.sh - builds tests/textpix_probe.s, runs it from the startup-sequence of a bootable OFS disk in an
# Amiberry session and writes its "TP" lines (checksums of the planes after Text in every mode, pen pair, write mask
# and x offset within a byte) to <out_dir>/textpix.txt. With a reference file, prints TEXTPIX OK when both match
# (e.g. the output of the ROM before a change to the text path).
#
# Usage: tests/textpix_probe.sh <out_dir> [rom=build/kick13-prod.rom] [reference textpix.txt]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"; REF="${3:-}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/textpix_probe" "$ROOT/tests/textpix_probe.s" || exit 2
printf 'df0:textpix_probe\n' > "$OUT/startup"
ADF="$OUT/textpix_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/textpix_probe" textpix_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="tpx$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" >/dev/null || exit 2
"$A" wait-serial "$NAME" "TP END" 240; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | grep '^TP ' > "$OUT/textpix.txt"
"$A" stop "$NAME" >/dev/null
echo "$(grep -c '^TP [0-9]' "$OUT/textpix.txt") lines in $OUT/textpix.txt"
[ $RC = 0 ] || exit $RC
[ -n "$REF" ] || exit 0
if diff "$REF" "$OUT/textpix.txt"; then echo "TEXTPIX OK"; else echo "TEXTPIX DIFFERS"; exit 1; fi
