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
RC=0
"$A" wait-serial "$NAME" "FM RD 00000003" 120 || RC=1
if [ $RC = 0 ]; then
  move 1 2; sleep 12; "$A" shot "$NAME" "$OUT/read_in_df2.png" --via ipc >/dev/null
  N1=$(grep -c "^FM RD " "$DIR/serial.log"); sleep 3; N2=$(grep -c "^FM RD " "$DIR/serial.log")
  echo "read blocks while in DF2: $N1 then $N2"
  move 2 1
  "$A" wait-serial "$NAME" "FM WR1" 180 || RC=1
fi
if [ $RC = 0 ]; then
  sleep 7; move 1 2; sleep 20; "$A" shot "$NAME" "$OUT/write_in_df2.png" --via ipc >/dev/null
  move 2 1
  "$A" wait-serial "$NAME" "FM END" 120 || RC=1
  sleep 8   # the file system writes the closed file back a few seconds later
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
