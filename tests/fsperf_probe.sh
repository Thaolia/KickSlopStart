#!/usr/bin/env bash
# tests/fsperf_probe.sh - speed and correctness of the data paths on a floppy: makes an OFS disk holding DF0:big
# (200,000 bytes, the long at byte offset 4n is n) and tests/fsperf_probe.s run from its startup-sequence, boots it
# on the given ROM under Amiberry (A500, 512 KB slow RAM), prints the probe's lines (times in 1/50 s), then checks
# on the host that DF0:out holds the first 120,000 bytes of the pattern and that the disk is consistent
# (tests/ofs_check.py). Compare two ROMs by running it once for each.
#
# Usage: tests/fsperf_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/fsperf_probe" "$ROOT/tests/fsperf_probe.s" || exit 2
python3 -I -c "
import struct,sys
open(sys.argv[1],'wb').write(b''.join(struct.pack('>I',n) for n in range(200000//4)))" "$OUT/big.ref"
printf 'df0:fsperf_probe\n' > "$OUT/startup"
ADF="$OUT/fsperf_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Perf ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/fsperf_probe" fsperf_probe + write "$OUT/big.ref" big >/dev/null || { echo "xdftool adf failed"; exit 2; }
NAME="fsp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --slow 512 >/dev/null || exit 2
"$A" wait-serial "$NAME" "FP END" 600; RC=$?
sleep 6                                        # past the handler's write-back
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | sed -n '/^FP BEGIN/,/^FP END/p' > "$OUT/fsperf.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/fsperf.txt"
[ $RC = 0 ] || exit $RC
ADF="$ROOT/build/amiberry/sessions/$NAME/df0-$(basename "$ADF")"   # --adf runs on a copy in the session directory
xdftool "$ADF" read out "$OUT/out.bin" >/dev/null || { echo "xdftool read failed"; exit 1; }
python3 -I - "$OUT" <<'PY'
import sys
o=sys.argv[1]; bad=[]
f={l.split()[1]: [int(x,16) for x in l.split()[2:]] for l in open(o+'/fsperf.txt') if l.startswith('FP ') and len(l.split())>2}
want={'RD': (1, [200000, 0]), 'SMALL': (1, [0]), 'WR': (1, [120000]), 'WRCHK': (0, [120000, 0]), 'CLR': (1, [0])}
for k,(skip,v) in want.items():
    if k not in f or f[k][skip:] != v: bad.append('%s %s, expected %s after the time' % (k, f.get(k), v))
if 'CPY' not in f: bad.append('CPY missing')
if open(o+'/out.bin','rb').read()!=open(o+'/big.ref','rb').read()[:120000]: bad.append('DF0:out differs from the pattern')
print('\n'.join(bad) if bad else 'FSPERF OK')
sys.exit(1 if bad else 0)
PY
R=$?
python3 -I "$ROOT/tests/ofs_check.py" "$ADF" | tail -2
exit $R
