#!/usr/bin/env bash
# tests/fvperf_probe.sh - builds tests/fvperf.s, runs it from the startup-sequence of a bootable OFS disk in an
# Amiberry session (A500, 512 KB slow RAM) and prints its "FV" lines: frames and video lines taken by the graphics
# calls of a vector animation player (lines, filled polygons, full-window copies, RectFills, VBeamPos) on a LORES
# 5-plane screen. Compare two ROMs. ANALYSIS=1 starts the session with --analysis (analysis agents only; the
# session then lives in build/amiberry/analysis/).
#
# Usage: tests/fvperf_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/fvperf" "$ROOT/tests/fvperf.s" || exit 2
printf 'df0:fvperf\n' > "$OUT/startup"
ADF="$OUT/fvperf_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/fvperf" fvperf >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="fvp$$"; DIR="$ROOT/build/amiberry/sessions/$NAME"; EXTRA=""
if [ "${ANALYSIS:-0}" = 1 ]; then EXTRA="--analysis"; DIR="$ROOT/build/amiberry/analysis/$NAME"; fi
"$A" start $EXTRA --name "$NAME" --rom "$ROM" --adf "$ADF" --slow 512 >/dev/null || exit 2
"$A" wait-serial "$NAME" "FV END" 600; RC=$?
tr -d '\r' < "$DIR/serial.log" | grep -a '^FV ' > "$OUT/fvperf.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/fvperf.txt"
exit $RC
