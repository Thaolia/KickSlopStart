#!/usr/bin/env bash
# tests/gregion_probe.sh - builds tests/gregion_probe.s (CLI executable), writes it with a startup-sequence that runs it
# on a bootable OFS disk, boots the disk in an Amiberry session and copies the serial lines between "GRG debut" and
# "GRG fin" to <out_dir>/gregion.txt. Expected values: docs/analysis/graphics-regions-v34.md §11, §6-§7.
#
# Usage: tests/gregion_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# The Commodore ROM is refused by amiberry-session unless GR_ANALYSIS=1 (analysis agent only, see CLAUDE.md).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/gregion_probe" "$ROOT/tests/gregion_probe.s" || exit 2
printf 'df0:gregion_probe\n' > "$OUT/startup"
ADF="$OUT/gregion_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/gregion_probe" gregion_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="grg$$"
EXTRA=(); DIR="$ROOT/build/amiberry/sessions/$NAME"
[ "${GR_ANALYSIS:-0}" = 1 ] && { EXTRA=(--analysis); DIR="$ROOT/build/amiberry/analysis/$NAME"; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" "${EXTRA[@]}" || exit 2
"$A" wait-serial "$NAME" "GRG fin" 300; RC=$?
tr -d '\r' < "$DIR/serial.log" | sed -n '/^GRG debut/,/^GRG fin/p' > "$OUT/gregion.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/gregion.txt"
exit $RC
