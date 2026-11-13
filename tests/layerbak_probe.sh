#!/usr/bin/env bash
# tests/layerbak_probe.sh - builds tests/layerbak_probe.s, runs it from the startup-sequence of a bootable OFS disk in
# an Amiberry session (A500, 512 KB slow RAM) and prints its "LB" lines: ReadPixel hashes of two SMART layers and
# screen sums after each layer step, free memory pre-filled with $A5. Two ROMs must print the same lines.
#
# Usage: tests/layerbak_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/layerbak_probe" "$ROOT/tests/layerbak_probe.s" || exit 2
printf 'df0:layerbak_probe\n' > "$OUT/startup"
ADF="$OUT/layerbak_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/layerbak_probe" layerbak_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="lbp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --slow 512 >/dev/null || exit 2
"$A" wait-serial "$NAME" "LB END" 300; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | grep '^LB ' > "$OUT/layerbak.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/layerbak.txt"
exit $RC
