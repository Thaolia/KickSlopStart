#!/usr/bin/env bash
# tests/oldwrite_probe.sh - builds tests/oldwrite_probe.s, boots it from DF0: in an Amiberry session with a 37-byte
# file DF0:t, then checks the serial lines and the file on the host (docs/analysis/rom-filesystem-v34.md §5.1:
# writes through a MODE_OLDFILE handle are accepted).
#
# Usage: tests/oldwrite_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:?out_dir}" && cd "$1" && pwd)"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/oldwrite_probe" "$ROOT/tests/oldwrite_probe.s" || exit 2
printf 'df0:oldwrite_probe\n' > "$OUT/startup"
printf 'The quick brown fox jumps over a dog\n' > "$OUT/t"
BOOT="$OUT/owboot_$$.adf"; rm -f "$BOOT"
xdftool "$BOOT" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/oldwrite_probe" oldwrite_probe + write "$OUT/t" t >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="owp$$"; DIR="$ROOT/build/amiberry/sessions/$NAME"
"$A" start --name "$NAME" --rom "$ROM" --adf "$BOOT" >/dev/null || exit 2
RC=0
"$A" wait-serial "$NAME" "OW END" 120 >/dev/null || RC=1
sleep 8   # the file system writes the bitmap and the closed file back a few seconds later
tr -d '\r' < "$DIR/serial.log" | grep "^OW " > "$OUT/oldwrite.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/oldwrite.txt"
[ $RC = 0 ] || { echo "OLDWRITE: timeout"; exit 1; }
SUM=$(python3 -I -c 'd=b"The q"+b"W"*200; print("%08X" % sum(d))')
grep -qx "OW A 00000005 000000C8 000000CD 000000CD $SUM FFFFFFFF" "$OUT/oldwrite.txt" || { echo "OLDWRITE: part A differs"; exit 1; }
grep -qx "OW B 00000000 00000004 FFFFFFFF" "$OUT/oldwrite.txt" || { echo "OLDWRITE: part B differs"; exit 1; }
grep -q "^OW C 00000003 " "$OUT/oldwrite.txt" || { echo "OLDWRITE: part C differs"; exit 1; }
xdftool "$DIR/df0-$(basename "$BOOT")" read t "$OUT/t.out" >/dev/null 2>&1   # the session works on its own copy
python3 -I -c 'import sys; e=b"abc"+b" q"+b"W"*200+b"END\n"; sys.exit(open(sys.argv[1],"rb").read()!=e)' "$OUT/t.out" \
  || { echo "OLDWRITE: file t differs"; exit 1; }
echo "OLDWRITE OK"
