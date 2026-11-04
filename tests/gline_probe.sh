#!/usr/bin/env bash
# tests/gline_probe.sh - builds tests/gline_probe.s (CLI executable), writes it with a startup-sequence that runs it on
# a bootable OFS disk (no SetPatch, no devs/system-configuration), boots the disk in an Amiberry session and copies
# the serial lines between "GLP debut" and "GLP fin" to <out_dir>/gline.txt. Expected values:
# docs/analysis/graphics-line-v34.md §10.
#
# Usage: tests/gline_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# The Commodore ROM is refused by amiberry-session unless GL_ANALYSIS=1 (analysis agent only, see CLAUDE.md).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/gline_probe" "$ROOT/tests/gline_probe.s" || exit 2
printf 'df0:gline_probe\n' > "$OUT/startup"
ADF="$OUT/gline_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/gline_probe" gline_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="glx$$"
EXTRA=(); DIR="$ROOT/build/amiberry/sessions/$NAME"
[ "${GL_ANALYSIS:-0}" = 1 ] && { EXTRA=(--analysis); DIR="$ROOT/build/amiberry/analysis/$NAME"; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" "${EXTRA[@]}" || exit 2
"$A" wait-serial "$NAME" "GLP fin" 600; RC=$?
tr -d '\r' < "$DIR/serial.log" | sed -n '/^GLP debut/,/^GLP fin/p' > "$OUT/gline.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/gline.txt"
exit $RC
