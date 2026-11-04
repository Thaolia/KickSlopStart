#!/usr/bin/env bash
# tests/fsrw_probe.sh - harness for tests/fsrw_test.s (OFS write streams, MODE_READWRITE, dos Info/Seek fixes).
# Builds the test, makes a scratch OFS disk whose startup-sequence runs it, boots it under Amiberry on the given ROM,
# waits for "FSRW END", then reads the disk the emulator wrote back with xdftool (files t1/t2 must be readable, with the
# sizes the test expects).
# Usage: tests/fsrw_probe.sh <rom> <session name> [timeout s, default 180]
set -u
ROM="${1:?rom}"; NAME="${2:?session name}"; TMO="${3:-180}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/fsrw; mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -quiet -o "$OUT/fsrw_test" tests/fsrw_test.s || { echo "vasm failed"; exit 2; }
ADF="$OUT/fsrw_$(date +%s).adf"
printf 'df0:fsrw_test\n' > "$OUT/startup"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/fsrw_test" fsrw_test >/dev/null || { echo "xdftool failed"; exit 2; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" >/dev/null || { echo "start failed"; exit 2; }
"$A" wait-serial "$NAME" "FSRW END" "$TMO"; rc=$?
sleep 5                                         # let the handler's writes reach the disk image
SES=build/amiberry/sessions/$NAME
grep -a 'FSRW' "$SES/serial.log"
"$A" stop "$NAME" >/dev/null
[ $rc -eq 0 ] || { echo "no FSRW END"; exit 1; }
DISK=$(ls -t "$SES"/*.adf | head -1)
xdftool "$DISK" list
for f in t1 t2; do xdftool "$DISK" read "$f" "$OUT/$f.out" && echo "$f: $(stat -c %s "$OUT/$f.out") bytes"; done
