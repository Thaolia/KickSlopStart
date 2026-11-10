#!/usr/bin/env bash
# tests/waittof_probe.sh - builds tests/waittof_probe.s (CLI executable), runs it from the startup-sequence of a bootable
# OFS disk in an Amiberry session and keeps the "WT ..." serial lines in <out_dir>/waittof.txt (meaning of each line:
# the header of tests/waittof_probe.s; 1.3 values: graphics-display-v34 §7.2/§7.4).
#
# Usage: tests/waittof_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/waittof_probe" "$ROOT/tests/waittof_probe.s" || exit 2
printf 'df0:waittof_probe\n' > "$OUT/startup"
ADF="$OUT/waittof_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/waittof_probe" waittof_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="wtp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" || exit 2
"$A" wait-serial "$NAME" "WT END" 200; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | grep "^WT " > "$OUT/waittof.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/waittof.txt"
exit $RC
