#!/usr/bin/env bash
# tests/mrgcop_probe.sh - builds tests/mrgcop_probe.s (CLI executable), runs it from the startup-sequence of a bootable
# OFS disk in an Amiberry session on our ROM, keeps the "MC ..." serial lines in <out_dir>/mrgcop.txt and checks them
# against docs/analysis/graphics-display-v34.md §5.3-5.4 with tests/mrgcop_check.py.
#
# Usage: tests/mrgcop_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/mrgcop_probe" "$ROOT/tests/mrgcop_probe.s" || exit 2
printf 'df0:mrgcop_probe\n' > "$OUT/startup"
ADF="$OUT/mrgcop_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/mrgcop_probe" mrgcop_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="mcp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" || exit 2
"$A" wait-serial "$NAME" "MC END" 240; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | sed -n '/^MC BEGIN/,/^MC END/p' > "$OUT/mrgcop.txt"
"$A" stop "$NAME" >/dev/null
[ $RC = 0 ] || exit $RC
python3 -I "$ROOT/tests/mrgcop_check.py" "$OUT/mrgcop.txt"
