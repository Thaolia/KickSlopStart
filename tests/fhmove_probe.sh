#!/usr/bin/env bash
# tests/fhmove_probe.sh - builds tests/fhmove_probe.s, boots it from DF0: in an Amiberry session with three drives
# (DF1: = a data disk "Data3" holding a 203,199-byte "longfile", DF2: empty) and moves the data disk
# DF1 -> DF2 -> DF1 while the probe reads, then while it writes (docs/analysis/disk-change-v34.md §2.4.1).
# Screenshots with the disk in DF2 go to <out_dir> (expected: "Please replace volume / Data3 / in unit  1").
# Checks: the read completes with the host's byte count and sum, the file w = "line one\nline two\n".
#
# Usage: tests/fhmove_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:?out_dir}" && cd "$1" && pwd)"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/fhmove_probe" "$ROOT/tests/fhmove_probe.s" || exit 2
printf 'df0:fhmove_probe\n' > "$OUT/startup"
python3 -I -c '
import sys
with open(sys.argv[1], "w") as f:
    for i in range(3175):
        f.write("%05d %s\n" % (i, "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVW"[: 56 + i % 3]))
' "$OUT/longfile"
BOOT="$OUT/fmboot_$$.adf"; DATA="$OUT/fmdata_$$.adf"; rm -f "$BOOT" "$DATA"
xdftool "$BOOT" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/fhmove_probe" fhmove_probe >/dev/null || { echo "xdftool failed"; exit 2; }
xdftool "$DATA" create + format Data3 ofs + write "$OUT/longfile" longfile >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="fmp$$"; DIR="$ROOT/build/amiberry/sessions/$NAME"
"$A" start --name "$NAME" --rom "$ROM" --adf "$BOOT" -- -s nr_floppies=3 -s floppy2type=0 -s "floppy1=$DATA" || exit 2
move() {  # move the data disk from drive $1 to drive $2
  "$A" ipc "$NAME" EJECT_FLOPPY "$1" >/dev/null; sleep 2; "$A" ipc "$NAME" INSERTFLOPPY "$DATA" "$2" >/dev/null
}
# back() <marker>: wait for the marker once the disk is back in DF1. An ejection that fell while the file system still
# had a write pending or a transfer under way leaves "You MUST replace volume", which reinsertion does not close (as on
# 1.3, disk-change §2.2.1 point 2): when the serial output stalls, answer it with Retry (left Amiga + V) as a user
# would, then wait again.
back() {
  local i n0
  for i in $(seq 16); do
    n0=$(stat -c %s "$DIR/serial.log")
    "$A" wait-serial "$NAME" "$1" 15 >/dev/null && return 0
    [ "$(stat -c %s "$DIR/serial.log")" = "$n0" ] || continue   # still progressing (a long read): keep waiting
    printf 'down:66 wait:100 key:34 wait:100 up:66\n' | "$A" input "$NAME" - >/dev/null
    echo "retry sent while waiting for $1"
  done
  return 1
}
RC=0
"$A" wait-serial "$NAME" "FM RD 00000003" 120 || RC=1
if [ $RC = 0 ]; then
  move 1 2; sleep 12; "$A" shot "$NAME" "$OUT/read_in_df2.png" --via ipc >/dev/null
  N1=$(grep -c "^FM RD " "$DIR/serial.log"); sleep 3; N2=$(grep -c "^FM RD " "$DIR/serial.log")
  echo "read blocks while in DF2: $N1 then $N2"
  move 2 1
  back "FM WR1" || RC=1
fi
if [ $RC = 0 ]; then
  sleep 12; move 1 2; sleep 20; "$A" shot "$NAME" "$OUT/write_in_df2.png" --via ipc >/dev/null
  move 2 1
  back "FM END" || RC=1
  # the file system writes the closed file back a few seconds after END: wait until the ADF holds it (emulated time
  # runs slower than the wall clock on a loaded host), 40 s at most
  for i in $(seq 20); do
    sleep 2
    xdftool "$DATA" read w "$OUT/w" >/dev/null 2>&1 && printf 'line one\nline two\n' | cmp -s - "$OUT/w" && break
  done
fi
tr -d '\r' < "$DIR/serial.log" | sed -n '/^FM BEGIN/,/^FM END/p' | grep -v "^FM RD " > "$OUT/fhmove.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/fhmove.txt"
[ $RC = 0 ] || { echo "FHMOVE: timeout"; exit 1; }
EXP=$(python3 -I -c 'import sys; d=open(sys.argv[1],"rb").read(); print("FM RDEND %08X %08X" % (len(d), sum(d)))' "$OUT/longfile")
grep -qx "$EXP" "$OUT/fhmove.txt" || { echo "FHMOVE: read differs (expected $EXP)"; exit 1; }
xdftool "$DATA" read w "$OUT/w" >/dev/null 2>&1
printf 'line one\nline two\n' | cmp -s - "$OUT/w" || { echo "FHMOVE: file w differs"; exit 1; }
echo "FHMOVE OK"
