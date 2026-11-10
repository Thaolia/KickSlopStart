#!/usr/bin/env bash
# tests/clipblit_probe.sh - builds tests/clipblit_probe.s (CLI executable), runs it from the startup-sequence of a bootable
# OFS disk in an Amiberry session on our ROM, keeps the "CB ..." serial lines in <out_dir>/clipblit.txt and checks them
# against docs/analysis/graphics-blitter-v34.md §5.3 step 3 (no wrong pixel after an overlapping ClipBlit).
#
# Usage: tests/clipblit_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/clipblit_probe" "$ROOT/tests/clipblit_probe.s" || exit 2
printf 'df0:clipblit_probe\n' > "$OUT/startup"
ADF="$OUT/clipblit_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/clipblit_probe" clipblit_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="cbp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" || exit 2
"$A" wait-serial "$NAME" "CB END" 240; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | sed -n '/^CB BEGIN/,/^CB END/p' > "$OUT/clipblit.txt"
"$A" stop "$NAME" >/dev/null
[ $RC = 0 ] || exit $RC
cat "$OUT/clipblit.txt"
grep -q "^CB BAD 0000" "$OUT/clipblit.txt" && echo "CLIPBLIT OK" || { echo "CLIPBLIT: wrong pixels after the overlapping copy"; exit 1; }
