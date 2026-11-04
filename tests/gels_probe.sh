#!/usr/bin/env bash
# tests/gels_probe.sh - builds tests/gels_probe.s (CLI executable), writes it with a startup-sequence that runs it on
# a bootable OFS disk (no SetPatch), boots the disk in an Amiberry session and copies the serial lines between
# "GEL debut" and "GEL fin" to <out_dir>/gels.txt. Expected values: docs/analysis/graphics-gels-v34.md §11.
#
# Usage: tests/gels_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# The Commodore ROM is refused by amiberry-session unless GE_ANALYSIS=1 (analysis agent only, see CLAUDE.md).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/gels_probe" "$ROOT/tests/gels_probe.s" || exit 2
printf 'df0:gels_probe\n' > "$OUT/startup"
ADF="$OUT/gels_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/gels_probe" gels_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="gls$$"
EXTRA=(); DIR="$ROOT/build/amiberry/sessions/$NAME"
[ "${GE_ANALYSIS:-0}" = 1 ] && { EXTRA=(--analysis); DIR="$ROOT/build/amiberry/analysis/$NAME"; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" "${EXTRA[@]}" || exit 2
"$A" wait-serial "$NAME" "GEL fin" 300; RC=$?
tr -d '\r' < "$DIR/serial.log" | sed -n '/^GEL debut/,/^GEL fin/p' > "$OUT/gels.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/gels.txt"
exit $RC
