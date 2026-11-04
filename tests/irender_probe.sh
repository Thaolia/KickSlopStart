#!/usr/bin/env bash
# tests/irender_probe.sh - builds tests/irender_probe.s (CLI executable), writes it with a startup-sequence that runs it
# on a bootable OFS disk (no SetPatch, no devs/system-configuration), boots the disk in an Amiberry session and copies
# the serial lines between "IRP debut" and "IRP fin" to <out_dir>/irender.txt. Expected values:
# docs/analysis/intuition-render-v34.md §7.
#
# Usage: tests/irender_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# The Commodore ROM is refused by amiberry-session unless IR_ANALYSIS=1 (analysis agent only, see CLAUDE.md).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/irender_probe" "$ROOT/tests/irender_probe.s" || exit 2
printf 'df0:irender_probe\n' > "$OUT/startup"
ADF="$OUT/irender_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/irender_probe" irender_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="irp$$"
EXTRA=(); DIR="$ROOT/build/amiberry/sessions/$NAME"
[ "${IR_ANALYSIS:-0}" = 1 ] && { EXTRA=(--analysis); DIR="$ROOT/build/amiberry/analysis/$NAME"; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" "${EXTRA[@]}" || exit 2
"$A" wait-serial "$NAME" "IRP fin" 300; RC=$?
tr -d '\r' < "$DIR/serial.log" | sed -n '/^IRP debut/,/^IRP fin/p' > "$OUT/irender.txt"
[ "${IR_KEEP:-0}" = 1 ] || "$A" stop "$NAME" >/dev/null
cat "$OUT/irender.txt"
exit $RC
