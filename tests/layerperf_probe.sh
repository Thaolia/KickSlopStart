#!/usr/bin/env bash
# tests/layerperf_probe.sh - builds tests/layerperf_probe.s, runs it from the startup-sequence of a bootable OFS disk in
# an Amiberry session (A500, 512 KB slow RAM) and prints its "LP" lines: DateStamp ticks and AllocMem calls of 300
# menu-like CreateUpfrontLayer/DeleteLayer and 300 MoveLayer over three overlapping windows. Compare two ROMs.
#
# Usage: tests/layerperf_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/layerperf_probe" "$ROOT/tests/layerperf_probe.s" || exit 2
printf 'df0:layerperf_probe\n' > "$OUT/startup"
ADF="$OUT/layerperf_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/layerperf_probe" layerperf_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="lpp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --slow 512 >/dev/null || exit 2
"$A" wait-serial "$NAME" "LP END" 300; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | grep '^LP ' > "$OUT/layerperf.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/layerperf.txt"
exit $RC
