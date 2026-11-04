#!/usr/bin/env bash
# tests/fsgap_probe.sh - harness for tests/fsgap_test.s (names, 212/205, root FIB, ExNext order, rename into itself,
# write-protected disk). DF0: scratch OFS disk whose startup-sequence runs the test; DF1: OFS disk "WProt" holding a
# file "wf", write-protected (read-only image). Waits for "FSGP END" and prints the result lines.
# Usage: tests/fsgap_probe.sh <rom> <session name> [timeout s, default 180]
set -u
ROM="${1:?rom}"; NAME="${2:?session name}"; TMO="${3:-180}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/fsgap; mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -quiet -o "$OUT/fsgap_test" tests/fsgap_test.s || { echo "vasm failed"; exit 2; }
T=$(date +%s); ADF="$OUT/fsgap_$T.adf"; WP="$OUT/wprot_$T.adf"
printf 'df0:fsgap_test\n' > "$OUT/startup"; printf 'w\n' > "$OUT/wf"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/fsgap_test" fsgap_test >/dev/null || { echo "xdftool failed"; exit 2; }
xdftool "$WP" create + format WProt ofs + write "$OUT/wf" wf >/dev/null || { echo "xdftool failed"; exit 2; }
# write protection: a read-only image (Amiberry's floppy1wp option did not protect the disk); given through the
# configuration because --adf copies the image and makes the copy writable
chmod a-w "$WP"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" -- -s "floppy1=$PWD/$WP" >/dev/null || { echo "start failed"; exit 2; }
"$A" wait-serial "$NAME" "FSGP END" "$TMO"; rc=$?
SES=build/amiberry/sessions/$NAME
grep -a 'FSGP' "$SES/serial.log"
"$A" stop "$NAME" >/dev/null
[ $rc -eq 0 ] || { echo "no FSGP END"; exit 1; }
xdftool "$(ls -t "$SES"/df0-*.adf | head -1)" list
