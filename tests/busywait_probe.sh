#!/usr/bin/env bash
# tests/busywait_probe.sh - boots a copy of the Workbench 1.3.3 disk whose startup-sequence runs
# tests/busywait_probe.s (an endless CPU loop) with Run, then "Wait 5" and an "T after" marker on the serial line.
# A command must not start under a Forbid level: before the A13 fix, the dev ROM never printed "T after".
#
# Usage: tests/busywait_probe.sh <out_dir> [rom=build/kick13.rom]   (WB_ADF = Workbench 1.3.3 disk, default
#        assets/wb133.adf). Prints PASS or FAIL.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/busy" "$ROOT/tests/busywait_probe.s" || exit 2
printf 'echo >SER: "T before"\nrun df0:busy\nwait 5\necho >SER: "T after"\n' > "$OUT/startup"
ADF="$OUT/busywait_$$.adf"
cp "${WB_ADF:-$ROOT/assets/wb133.adf}" "$ADF" && chmod u+w "$ADF" || exit 2
xdftool "$ADF" delete s/startup-sequence + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/busy" busy >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="bwp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --slow 512 >/dev/null || exit 2
if "$A" wait-serial "$NAME" "T after" 150 >/dev/null; then R=PASS; else R=FAIL; fi
"$A" stop "$NAME" >/dev/null
echo "$R"
[ "$R" = PASS ]
