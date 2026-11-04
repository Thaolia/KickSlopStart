#!/usr/bin/env bash
# tests/fsnodisk_probe.sh - harness for tests/fsnodisk_test.s ("No disk present / in unit 1" requester). DF0: scratch
# OFS disk whose startup-sequence runs the test; DF1: a 3.5" drive left empty (floppy1type=0). The requester is
# captured (req.png in the session directory), then answered Cancel with left Amiga + B.
# Usage: tests/fsnodisk_probe.sh <rom> <session name> [timeout s, default 180]
set -u
ROM="${1:?rom}"; NAME="${2:?session name}"; TMO="${3:-180}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/fsnodisk; mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -quiet -o "$OUT/fsnodisk_test" tests/fsnodisk_test.s || { echo "vasm failed"; exit 2; }
ADF="$OUT/fsnodisk_$(date +%s).adf"
printf 'df0:fsnodisk_test\n' > "$OUT/startup"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/fsnodisk_test" fsnodisk_test >/dev/null || { echo "xdftool failed"; exit 2; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" -- -s floppy1type=0 >/dev/null || { echo "start failed"; exit 2; }
SES=build/amiberry/sessions/$NAME
if "$A" wait-serial "$NAME" "FSND REQ" "$TMO"; then
  sleep 4
  "$A" shot "$NAME" req.png --via ipc
  printf 'down:66 wait:100\nkey:35 wait:100\nup:66\n' | "$A" input "$NAME" - >/dev/null
fi
"$A" wait-serial "$NAME" "FSND END" 60; rc=$?
grep -a 'FSND' "$SES/serial.log"
"$A" stop "$NAME" >/dev/null
[ $rc -eq 0 ] || { echo "no FSND END"; exit 1; }
