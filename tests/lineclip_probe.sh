#!/usr/bin/env bash
# tests/lineclip_probe.sh - builds tests/lineclip_probe.s (CLI executable), runs it from the startup-sequence of a bootable
# OFS disk in an Amiberry session, and keeps the "LC ..." serial lines in <out_dir>/lineclip.txt. The fingerprints
# ("LC CKS") of two ROMs must be equal when only the speed of line drawing changed; "LC TICKS" is the drawing time.
#
# Usage: tests/lineclip_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/lineclip_probe" "$ROOT/tests/lineclip_probe.s" || exit 2
printf 'df0:lineclip_probe\n' > "$OUT/startup"
ADF="$OUT/lineclip_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/lineclip_probe" lineclip_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="lcp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" || exit 2
"$A" wait-serial "$NAME" "LC END" 240; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | sed -n '/^LC BEGIN/,/^LC END/p' > "$OUT/lineclip.txt"
"$A" stop "$NAME" >/dev/null
[ $RC = 0 ] || exit $RC
cat "$OUT/lineclip.txt"
