#!/usr/bin/env bash
# tests/contype_probe.sh - console output speed: a copy of the Workbench 1.3.3 disk (assets/wb133.adf) whose
# startup-sequence is replaced by tests/contype_probe (time stamp on serial), C:Type of a 400-line file (26,000
# bytes) to the boot console, tests/contype_probe again. Prints the two stamps and the time between them in seconds
# (1/50 s ticks). Compare two ROMs by running it once for each; the screenshot end.png shows the last lines.
#
# Usage: tests/contype_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/contype_probe" "$ROOT/tests/contype_probe.s" || exit 2
python3 -I -c "
import sys
open(sys.argv[1],'w').write(''.join('Line %03d: the quick brown fox jumps over the lazy dog 0123456789\n' % i for i in range(1, 401)))" \
  "$OUT/t.txt"
printf 'df0:contype_probe\ntype df0:t.txt\ndf0:contype_probe\n' > "$OUT/startup"
ADF="$OUT/contype_$$.adf"
cp "$ROOT/assets/wb133.adf" "$ADF" && chmod u+w "$ADF"
xdftool "$ADF" delete s/startup-sequence + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/contype_probe" contype_probe + write "$OUT/t.txt" t.txt >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="ctp$$"
LOG="$ROOT/build/amiberry/sessions/$NAME/serial.log"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --slow 512 >/dev/null || exit 2
for _ in $(seq 1 300); do [ "$(tr -d '\r' < "$LOG" 2>/dev/null | grep -c '^CT ')" -ge 2 ] && break; sleep 1; done
"$A" shot "$NAME" "$OUT/end.png" --via ipc >/dev/null
tr -d '\r' < "$LOG" | grep '^CT ' > "$OUT/contype.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/contype.txt"
python3 -I - "$OUT/contype.txt" <<'PY'
import sys
v=[int(l.split()[1],16) for l in open(sys.argv[1])]
if len(v)<2: print('CONTYPE: second stamp missing'); sys.exit(1)
print('CONTYPE %.2f s' % ((v[1]-v[0])/50))
PY
