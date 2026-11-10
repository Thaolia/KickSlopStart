#!/usr/bin/env bash
# tests/bigfile_probe.sh - a file of more than 65535 data blocks on a hard disk partition: makes a 40 MiB OFS
# hardfile holding DH0:huge (33,600,000 bytes = 68,853 data blocks, the long at byte offset 4n is n), boots a probe
# disk running tests/bigfile_probe.s on the given ROM (Examine, Seek + Read past 65535 * 488 bytes, an in-place
# Write), then checks on the host the values read, the written bytes, the rest of the file and the bitmap
# (tests/ofs_check.py).
#
# Usage: tests/bigfile_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/bigfile_probe" "$ROOT/tests/bigfile_probe.s" || exit 2
python3 -I -c "
import struct,sys
open(sys.argv[1],'wb').write(b''.join(struct.pack('>I',n) for n in range(33600000//4)))" "$OUT/huge.ref"
HDF="$OUT/big.hdf"; rm -f "$HDF"
xdftool "$HDF" create size=40Mi + format Big ofs + write "$OUT/huge.ref" huge >/dev/null || { echo "xdftool hdf failed"; exit 2; }
printf 'df0:bigfile_probe\n' > "$OUT/startup"
ADF="$OUT/bigfile_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/bigfile_probe" bigfile_probe >/dev/null || { echo "xdftool adf failed"; exit 2; }
NAME="bfp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --fast 2 -- -s "hardfile2=rw,DH0:$HDF,32,1,2,512,-128,,uae0" \
  >/dev/null || exit 2
"$A" wait-serial "$NAME" "BF END" 300; RC=$?
sleep 6                                        # past the handler's write-back
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | sed -n '/^BF BEGIN/,/^BF END/p' > "$OUT/bigfile.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/bigfile.txt"
[ $RC = 0 ] || exit $RC
xdftool "$HDF" read huge "$OUT/huge.out" >/dev/null || { echo "xdftool read failed"; exit 1; }
python3 -I - "$OUT" <<'PY'
import sys,struct
o=sys.argv[1]; bad=[]
lines=[l.split() for l in open(o+'/bigfile.txt') if l.startswith('BF ')]
ex=[l for l in lines if l[1]=='EX']
if not ex or int(ex[0][2],16)!=33600000 or int(ex[0][3],16)!=68853:
    bad.append('Examine %s, expected size 33600000 and 68853 blocks' % (ex[0][2:] if ex else '-'))
for l in lines:
    if l[1]=='RD':
        off,a,b=(int(x,16) for x in l[2:5])
        if (a,b)!=(off//4,off//4+1): bad.append('Read at %d gave %08x %08x' % (off,a,b))
if sum(1 for l in lines if l[1]=='RD')!=5: bad.append('missing reads')
wr=[l for l in lines if l[1]=='WR']
if not wr or int(wr[0][2],16)!=8: bad.append('Write returned %s' % (wr[0][2] if wr else '-'))
ref=bytearray(open(o+'/huge.ref','rb').read()); ref[32000000:32000008]=b'KSSWRITE'
out=open(o+'/huge.out','rb').read()
if out!=bytes(ref): bad.append('file on the disk differs from the pattern + KSSWRITE (%d bytes)' % len(out))
print('\n'.join(bad) if bad else 'BIGFILE OK')
sys.exit(1 if bad else 0)
PY
R=$?
python3 -I "$ROOT/tests/ofs_check.py" "$HDF" | tail -2
exit $R
