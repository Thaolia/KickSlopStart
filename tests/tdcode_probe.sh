#!/usr/bin/env bash
# tests/tdcode_probe.sh - builds tests/tdcode_probe.s, runs it from the startup-sequence of a bootable OFS disk in an
# Amiberry session on our ROM, ejects the floppy when the probe asks for it ("TC EJECT"), keeps the "TC ..." lines in
# <out_dir>/tdcode.txt and checks them against trackdisk-write-v34 §5.2/§7 and trackdisk-raw-changeint-v34 §1.
#
# Usage: tests/tdcode_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/tdcode_probe" "$ROOT/tests/tdcode_probe.s" || exit 2
printf 'df0:tdcode_probe\n' > "$OUT/startup"
ADF="$OUT/tdcode_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/tdcode_probe" tdcode_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="tdc$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" || exit 2
LOG="$ROOT/build/amiberry/sessions/$NAME/serial.log"
"$A" wait-serial "$NAME" "TC EJECT" 240 || { "$A" stop "$NAME" >/dev/null; exit 1; }
"$A" ipc "$NAME" EJECT_FLOPPY 0 >/dev/null
"$A" wait-serial "$NAME" "TC END" 120; RC=$?
tr -d '\r' < "$LOG" | grep '^TC ' > "$OUT/tdcode.txt"
"$A" stop "$NAME" >/dev/null
[ $RC = 0 ] || exit $RC
cat "$OUT/tdcode.txt"
python3 -I - "$OUT/tdcode.txt" <<'PY'
import sys
got = {l.split()[1]: l.split()[2:] for l in open(sys.argv[1]) if len(l.split()) == 4}
want = {"READ-BEYOND": "FC", "ETD-OLDCOUNT": "1D", "ETD-COUNT": "00", "READ-NODISK": "1D", "FORMAT-NODISK": "1D"}
bad = ["%s: io_Error %s, expected %s" % (k, got.get(k, ["-"])[0], v) for k, v in want.items() if got.get(k, ["-"])[0] != v]
if got.get("FORMAT-NODISK", ["", "-"])[1] != "00000000":
    bad.append("FORMAT-NODISK: io_Actual %s, expected 00000000" % got.get("FORMAT-NODISK", ["", "-"])[1])
print("\n".join(bad) if bad else "TDCODE OK")
sys.exit(1 if bad else 0)
PY
