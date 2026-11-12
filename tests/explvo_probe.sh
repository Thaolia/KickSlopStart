#!/usr/bin/env bash
# tests/explvo_probe.sh - builds tests/explvo_probe.s, boots it from DF0: in an Amiberry session and checks its
# "EXP" lines against the values of docs/analysis/exec-partial-lvos-v34.md §2.4, §3, §4.6, §6,
# graphics-raster-v34.md §10 and intuition-misc-v34.md §6c.
#
# Usage: tests/explvo_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:?out_dir}" && cd "$1" && pwd)"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/explvo_probe" "$ROOT/tests/explvo_probe.s" || exit 2
printf 'df0:explvo_probe\n' > "$OUT/startup"
BOOT="$OUT/exboot_$$.adf"; rm -f "$BOOT"
xdftool "$BOOT" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/explvo_probe" explvo_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="exp$$"; DIR="$ROOT/build/amiberry/sessions/$NAME"
"$A" start --name "$NAME" --rom "$ROM" --adf "$BOOT" >/dev/null || exit 2
RC=0
"$A" wait-serial "$NAME" "EXP fin" 120 >/dev/null || RC=1
tr -d '\r' < "$DIR/serial.log" | grep -a "^EXP " > "$OUT/explvo.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/explvo.txt"
[ $RC = 0 ] || { echo "EXPLVO: timeout"; exit 1; }
BAD=0
expect() { grep -qx "$1" "$OUT/explvo.txt" || { echo "EXPLVO: expected \"$1\""; BAD=1; }; }
expect "EXP SIG 0000FFFF 00008000 0000001F 0000001E 0000001D FFFFFFFF 00000014 00000000 FFFFFFFF E010FFFF 0000000E 0000000D FFFFFFFF 00000014 FFFFFFFF 0000E000 6010FFFF"
expect "EXP CC C0000015"
expect "EXP LIST 00000001"
expect "EXP TASK 00000001"
expect "EXP LIB 00000002 0000001E 00000022"
expect "EXP IS 00000000 12345678 0000ABCD 77777700 000000FF"
expect "EXP BM 0000000E 00000032 00000003 0000AAAA AAAAAAAA 0000000E"
expect "EXP REM 00000000 000000A0"
expect "EXP PRIV 00000001"
expect "EXP OLZ 000000FF"
expect "EXP INT6 00000002 00000001"
expect "EXP MACT 00000000 00000000"
[ $BAD = 0 ] && echo "EXPLVO OK"
exit $BAD
