#!/usr/bin/env bash
# tests/fsnodisk_probe.sh - harness for tests/fsnodisk_test.s (dos unit requesters). DF0: scratch OFS disk whose
# startup-sequence runs the test. Case "nodisk" (default): DF1: a 3.5" drive left empty (floppy1type=0), 226
# "No disk present". Case "notdos": DF1: an all-zero image, 225 "Not a DOS disk". Case "notval": DF1: a DOS disk
# whose validation fails, 213 "is not validated". The requester is captured (req.png in the session directory), then
# answered Cancel with left Amiga + B.
# Usage: tests/fsnodisk_probe.sh <rom> <session name> [nodisk|notdos|notval] [timeout s, default 180]
set -u
ROM="${1:?rom}"; NAME="${2:?session name}"; CASE="${3:-nodisk}"; TMO="${4:-180}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/fsnodisk; mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -quiet -o "$OUT/fsnodisk_test" tests/fsnodisk_test.s || { echo "vasm failed"; exit 2; }
ADF="$OUT/fsnodisk_$(date +%s).adf"
ARG=""; DF1=(-s floppy1type=0)
if [ "$CASE" = notdos ]; then
  ARG=" d"; head -c 901120 /dev/zero > "$OUT/zero.adf"; DF1=(-s "floppy1=$PWD/$OUT/zero.adf")
elif [ "$CASE" = notval ]; then              # root: bitmap flag 0 and a hash entry out of range -> validation fails
  ARG=" v"; xdftool "$OUT/bad.adf" create + format Bad ofs >/dev/null
  python3 -I - "$OUT/bad.adf" <<'EOP'
import struct, sys
p = sys.argv[1]; d = bytearray(open(p, 'rb').read()); r = 880 * 512
struct.pack_into('>L', d, r + 24, 5000)                  # hash slot 0 -> block 5000 (outside the disk)
struct.pack_into('>l', d, r + 312, 0)                    # bm_flag 0: not validated
struct.pack_into('>L', d, r + 20, 0)
struct.pack_into('>L', d, r + 20, (-sum(struct.unpack_from('>128L', d, r))) & 0xFFFFFFFF)
open(p, 'wb').write(d)
EOP
  DF1=(-s "floppy1=$PWD/$OUT/bad.adf")
fi
printf 'df0:fsnodisk_test%s\n' "$ARG" > "$OUT/startup"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/fsnodisk_test" fsnodisk_test >/dev/null || { echo "xdftool failed"; exit 2; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" -- "${DF1[@]}" >/dev/null || { echo "start failed"; exit 2; }
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
