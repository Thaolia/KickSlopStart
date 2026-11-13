#!/usr/bin/env bash
# tests/taskheld_probe.sh - boots a copy of the Workbench 1.3.3 disk whose startup-sequence runs tests/taskheld_probe.s
# (a CLI command that takes a CPU exception) in an Amiberry session, then takes screenshots: A once the fault is
# expected, B after a click on Retry, C after a click on Cancel (Retry and Cancel of the requester at (0,0), 320 x 72,
# docs/analysis/task-held-v34.md §2). Read the pictures: requester in A and B, Guru in C; or Guru at once in A.
#
# Usage: tests/taskheld_probe.sh <out_dir> [letter of tests/taskheld_probe.s, "" = illegal] [rom=build/kick13-prod.rom]
#        RUN=1 starts the command with Run (task-held-v34 T5); WB_ADF = Workbench 1.3.3 disk (default assets/wb133.adf).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; L="${2:-}"; ROM="${3:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/taskheld" "$ROOT/tests/taskheld_probe.s" || exit 2
if [ "${RUN:-0}" = 1 ]; then printf 'run df0:taskheld %s\n' "$L" > "$OUT/startup"
else printf 'df0:taskheld %s\n' "$L" > "$OUT/startup"; fi
ADF="$OUT/taskheld_$$.adf"
cp "${WB_ADF:-$ROOT/assets/wb133.adf}" "$ADF" && chmod u+w "$ADF" || exit 2
xdftool "$ADF" delete s/startup-sequence + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/taskheld" taskheld >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="thp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --slow 512 >/dev/null || exit 2
sleep "${BOOTWAIT:-45}"
"$A" shot "$NAME" "$OUT/A.png" --via ipc >/dev/null
printf 'mouse:-900,-400 wait:300\nmouse:43,114 wait:300 click wait:2000\n' | "$A" input "$NAME" - >/dev/null
"$A" shot "$NAME" "$OUT/B.png" --via ipc >/dev/null
printf 'mouse:-900,-400 wait:300\nmouse:257,114 wait:300 click wait:3000\n' | "$A" input "$NAME" - >/dev/null
"$A" shot "$NAME" "$OUT/C.png" --via ipc >/dev/null
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | grep -a 'SOFTWARE FAILURE' > "$OUT/serial.txt"
"$A" stop "$NAME" >/dev/null
echo "$OUT/A.png $OUT/B.png $OUT/C.png"
cat "$OUT/serial.txt"
