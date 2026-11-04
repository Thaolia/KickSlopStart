#!/usr/bin/env bash
# tests/fslock_probe.sh - harness for tests/fslock_test.s (DF0: locks and conflicts, SET_DATE, RENAME_DISK, FLUSH).
# Builds the test, makes a scratch OFS disk "Probe" whose startup-sequence runs it, boots it under Amiberry on the
# given ROM, waits for "FSLK END", then lists the disk the emulator wrote back with xdftool (volume "Renamed", f1 with
# its comment and date, d2 a file).
# Usage: tests/fslock_probe.sh <rom> <session name> [timeout s, default 180]
set -u
ROM="${1:?rom}"; NAME="${2:?session name}"; TMO="${3:-180}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/fslock; mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -quiet -o "$OUT/fslock_test" tests/fslock_test.s || { echo "vasm failed"; exit 2; }
ADF="$OUT/fslock_$(date +%s).adf"
printf 'df0:fslock_test\n' > "$OUT/startup"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/fslock_test" fslock_test >/dev/null || { echo "xdftool failed"; exit 2; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" >/dev/null || { echo "start failed"; exit 2; }
"$A" wait-serial "$NAME" "FSLK END" "$TMO"; rc=$?
sleep 5                                         # let the handler's writes reach the disk image
SES=build/amiberry/sessions/$NAME
grep -a 'FSLK' "$SES/serial.log"
"$A" stop "$NAME" >/dev/null
[ $rc -eq 0 ] || { echo "no FSLK END"; exit 1; }
DISK=$(ls -t "$SES"/*.adf | head -1)
xdftool "$DISK" list
python3 -I - "$DISK" <<'EOP'
import sys, struct
d = open(sys.argv[1], 'rb').read()
blk = lambda n: d[n * 512:(n + 1) * 512]
root = blk(880)
print('volume', root[432 + 1:432 + 1 + root[432]].decode())
for h in struct.unpack('>72L', root[24:24 + 288]):
    while h:
        b = blk(h)
        name = b[433:433 + b[432]].decode()
        if name == 'f1':
            print('f1 comment length', b[328], 'date', struct.unpack('>3l', b[420:432]))
        h = struct.unpack('>L', b[496:500])[0]
EOP
