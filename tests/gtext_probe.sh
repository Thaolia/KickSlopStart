#!/usr/bin/env bash
# tests/gtext_probe.sh - builds tests/gtext_probe.s (CLI executable), writes it with a startup-sequence that runs it on
# a bootable OFS disk (no SetPatch, no devs/system-configuration), boots the disk in an Amiberry session and copies
# the serial lines between "GTX debut" and "GTX fin" to <out_dir>/gtext.txt. Expected values:
# docs/analysis/graphics-text-v34.md §10.
#
# Usage: tests/gtext_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# The Commodore ROM is refused by amiberry-session unless GT_ANALYSIS=1 (analysis agent only, see CLAUDE.md).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/gtext_probe" "$ROOT/tests/gtext_probe.s" || exit 2
printf 'df0:gtext_probe\n' > "$OUT/startup"
ADF="$OUT/gtext_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/gtext_probe" gtext_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="gtx$$"
EXTRA=(); DIR="$ROOT/build/amiberry/sessions/$NAME"
[ "${GT_ANALYSIS:-0}" = 1 ] && { EXTRA=(--analysis); DIR="$ROOT/build/amiberry/analysis/$NAME"; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" "${EXTRA[@]}" || exit 2
"$A" wait-serial "$NAME" "GTX fin" 180; RC=$?
tr -d '\r' < "$DIR/serial.log" | sed -n '/^GTX debut/,/^GTX fin/p' > "$OUT/gtext.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/gtext.txt"
exit $RC
