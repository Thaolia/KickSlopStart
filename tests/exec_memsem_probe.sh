#!/usr/bin/env bash
# tests/exec_memsem_probe.sh - builds tests/exec_memsem_probe.s (CLI executable), writes it with a startup-sequence
# that runs it on a bootable OFS disk, boots the disk in an Amiberry session, reads the probe's output buffer through
# gdb (its bounds are printed on the serial port before "MSP fin") into <out_dir>/memsem.txt and checks it with
# tests/exec_memsem_check.py (one PASS/FAIL line per vector). Expected values: docs/analysis/
# exec-memory-semaphores-v34.md §9, with this ROM's deliberate differences (docs/PLAN.md).
# With MSP_ALERTS=1 it then runs the dead-end alert vectors, one session each (the probe's command-line argument
# selects one; the alert number is read from $100.l, where this ROM's dead-end alert leaves it before rebooting).
#
# Usage: tests/exec_memsem_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# The Commodore ROM is refused by amiberry-session unless MSP_ANALYSIS=1 (analysis agent only, see CLAUDE.md); the
# output is then checked against the 1.3 values (check13).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/exec_memsem_probe" \
  "$ROOT/tests/exec_memsem_probe.s" || exit 2
EXTRA=(); MODE=check; BASE="$ROOT/build/amiberry/sessions"
[ "${MSP_ANALYSIS:-0}" = 1 ] && { EXTRA=(--analysis); BASE="$ROOT/build/amiberry/analysis"; MODE=check13; }

# mkadf <adf> <command line>
mkadf() {
  printf '%s\n' "$2" > "$OUT/startup"
  rm -f "$1"
  xdftool "$1" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
    + write "$OUT/exec_memsem_probe" exec_memsem_probe >/dev/null || { echo "xdftool failed"; exit 2; }
}

NAME="${MSP_NAME:-msp$$}"
ADF="$OUT/memsem_$$.adf"
mkadf "$ADF" "df0:exec_memsem_probe"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --timeout 120 "${EXTRA[@]}" || exit 2
"$A" wait-serial "$NAME" "MSP fin" 600; RC=$?
if [ $RC = 0 ]; then
  BUF=$(tr -d '\r' < "$BASE/$NAME/serial.log" | grep -a -m1 -o 'MSP buf=[0-9A-F]\{8\} end=[0-9A-F]\{8\}$')
  S=${BUF#MSP buf=}; S=${S%% *}; E=${BUF##*end=}
  [ -n "$BUF" ] && "$A" gdb "$NAME" -ex "dump binary memory $OUT/memsem.bin 0x$S 0x$E" >/dev/null
  tr -d '\r' < "$OUT/memsem.bin" | sed -n '/^MSP debut/,/^MSP fin/p' > "$OUT/memsem.txt"
fi
"$A" stop "$NAME" >/dev/null
[ $RC = 0 ] || { echo "no MSP fin (timeout)"; exit 1; }
[ -s "$OUT/memsem.txt" ] || { echo "output buffer not read"; exit 1; }
python3 -I "$ROOT/tests/exec_memsem_check.py" $MODE "$OUT/memsem.txt" > "$OUT/memsem_check.txt"; RC=$?
grep -v '^PASS' "$OUT/memsem_check.txt"

if [ "${MSP_ALERTS:-0}" = 1 ]; then
  # selector:id:expected alert
  for spec in 1:G1:81000005 3:G3:81000005 4:G4:81000005 5:G5:81000009 6:G6:81000009 v:V1:81000009 \
              w:V4:81000009 x:V5:81000009 s:S9:81000008 h:H4:81000005; do
    IFS=: read -r sel id want <<< "$spec"
    N="${NAME}a$sel"; AADF="$OUT/memsem_${sel}_$$.adf"
    mkadf "$AADF" "df0:exec_memsem_probe $sel"
    "$A" start --name "$N" --rom "$ROM" --adf "$AADF" --timeout 120 "${EXTRA[@]}" >/dev/null || { echo "FAIL $id start"; RC=1; continue; }
    got=""
    if "$A" wait-serial "$N" "MSP alert $sel" 300 >/dev/null; then
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 2
        got=$("$A" gdb "$N" -ex 'x/1xw 0x100' 2>/dev/null | grep -o '0x[0-9a-f]\{8\}' | tail -1)
        [ -n "$got" ] && [ "$got" != "0x00000000" ] && break
      done
    fi
    "$A" stop "$N" >/dev/null
    if [ "$got" = "0x$want" ]; then echo "PASS $id alert $want"; else echo "FAIL $id alert: got ${got:-none}, want $want"; RC=1; fi
  done
fi
exit $RC
