#!/usr/bin/env bash
# tests/iwin_probe.sh - builds tests/iwin_probe.s (CLI executable), writes it with a startup-sequence that runs it on
# a bootable OFS disk (no SetPatch, no devs/system-configuration), boots the disk in an Amiberry session and copies
# the serial lines between "IW BEGIN" and "IW END" to <out_dir>/iwin.txt, plus a screenshot. Expected values:
# docs/analysis/intuition-windows-v34.md §8 (probe described in §9).
#
# Usage: tests/iwin_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# The Commodore ROM is refused by amiberry-session unless IW_ANALYSIS=1 (analysis agent only, see CLAUDE.md).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/iwin_probe" "$ROOT/tests/iwin_probe.s" || exit 2
printf 'df0:iwin_probe\n' > "$OUT/startup"
ADF="$OUT/iwin_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/iwin_probe" iwin_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="iwp$$"
EXTRA=(); DIR="$ROOT/build/amiberry/sessions/$NAME"
[ "${IW_ANALYSIS:-0}" = 1 ] && { EXTRA=(--analysis); DIR="$ROOT/build/amiberry/analysis/$NAME"; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" "${EXTRA[@]}" || exit 2
"$A" wait-serial "$NAME" "IW END" 240; RC=$?
"$A" shot "$NAME" "$OUT/iwin.png" --via ipc >/dev/null
tr -d '\r' < "$DIR/serial.log" | sed -n '/^IW BEGIN/,/^IW END/p' > "$OUT/iwin.txt"
[ "${IW_KEEP:-0}" = 1 ] || "$A" stop "$NAME" >/dev/null
cat "$OUT/iwin.txt"
exit $RC
