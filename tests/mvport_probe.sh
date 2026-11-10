#!/usr/bin/env bash
# tests/mvport_probe.sh - builds tests/mvport_probe.s (CLI executable), runs it from the startup-sequence of a bootable
# OFS disk in an Amiberry session on our ROM, keeps the "MV ..." serial lines in <out_dir>/mvport.txt and checks them
# against docs/analysis/graphics-display-v34.md §4.4 with tests/mvport_check.py.
#
# Usage: tests/mvport_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/mvport_probe" "$ROOT/tests/mvport_probe.s" || exit 2
printf 'df0:mvport_probe\n' > "$OUT/startup"
ADF="$OUT/mvport_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/mvport_probe" mvport_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="mvp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" || exit 2
"$A" wait-serial "$NAME" "MV END" 240; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | sed -n '/^MV BEGIN/,/^MV END/p' > "$OUT/mvport.txt"
"$A" stop "$NAME" >/dev/null
[ $RC = 0 ] || exit $RC
python3 -I "$ROOT/tests/mvport_check.py" "$OUT/mvport.txt"
