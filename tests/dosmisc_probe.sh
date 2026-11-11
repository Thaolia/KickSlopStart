#!/usr/bin/env bash
# tests/dosmisc_probe.sh - builds tests/dosmisc_probe.s, boots it from DF0: in an Amiberry session: four instances
# started with Run (Delay 50, -50, -49, -1) and one in the foreground (Seek, Info, UnLoadSeg(0), LoadSeg of a missing
# file and of a 2.0-style attribute hunk). Keeps the "DM ..." serial lines in <out_dir>/dosmisc.txt, sorted, and
# checks them against the 1.3 values of docs/analysis/dos-lvo-partial-v34.md §4 and dos-memory-v34.md §8.
# Success: DOSMISC OK.
# C:Run, C:Mount, L:Newcon-Handler and DEVS:MountList are copied from the local Workbench 1.3 disk (assets/wb133.adf);
# the startup-sequence mounts NEWCON: first, as the Workbench one does.
#
# Usage: tests/dosmisc_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:?out_dir}" && cd "$1" && pwd)"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/dosmisc_probe" "$ROOT/tests/dosmisc_probe.s" || exit 2
for f in c/Run c/Mount l/Newcon-Handler devs/MountList; do
  xdftool "$ROOT/assets/wb133.adf" read "$f" "$OUT/${f#*/}" >/dev/null || { echo "$f not found"; exit 2; }
done
{ printf 'mount newcon:\n'; for n in 1 2 3 4; do printf 'run >nil: df0:dosmisc_probe %s\n' $n; done; printf 'df0:dosmisc_probe S\n'; } > "$OUT/startup"
# a hunk header whose size long has bits 31-30 = 11 and an attribute long MEMF_CHIP (2.0 format); one code hunk: rts
python3 -I -c '
import struct, sys
w = [0x3F3, 0, 1, 0, 0, 0xC0000001, 2, 0x3E9, 1, 0x4E754E71, 0x3F2]
open(sys.argv[1], "wb").write(struct.pack(">%dL" % len(w), *w))
' "$OUT/attr"
ADF="$OUT/dosmisc_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + makedir c + makedir l + makedir devs \
  + write "$OUT/startup" s/startup-sequence + write "$OUT/Run" c/Run + write "$OUT/Mount" c/Mount \
  + write "$OUT/Newcon-Handler" l/Newcon-Handler + write "$OUT/MountList" devs/MountList + write "$OUT/dosmisc_probe" dosmisc_probe + write "$OUT/attr" attr \
  >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="dmp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" || exit 2
"$A" wait-serial "$NAME" "DM END" 240; RC=$?
sleep 20                              # Delay(50) and whatever negative Delay returns in time
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | grep -a "^DM " | sort > "$OUT/dosmisc.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/dosmisc.txt"
[ $RC = 0 ] || { echo "DOSMISC: timeout"; exit 1; }
# 1.3 values (analysis run of 2026-11-11, dos-lvo-partial-v34 §2.2, §2.6, §2.13, dos-memory-v34 §3.3, §3.5):
# Delay(50) 50-59 ticks, the negative Delays never return; Info writes 36 bytes from the aligned start, InUse = a lock
python3 -I - "$OUT/dosmisc.txt" <<'PY'
import sys
f = {}
for l in open(sys.argv[1]):
    w = l.split()
    if len(w) >= 3:
        f.setdefault(w[1], []).append(w[2:])
bad = []
def want(k, v):
    if [v] != [x for x in f.get(k, []) if x != ["start"]]:
        bad.append("%s %s: expected %s" % (k, f.get(k), v))
want("ATT", ["00000000", "00000067", "00000000"])
want("LSM", ["00000000", "000000CD", "00000000"])
want("SKF", ["0000000A", "0000000A", "0000000A", "00000000"])
for k in ("SKO", "SKR", "SKN"):
    want(k, ["00000000", "000000D1"])
want("UL0", ["00000000", "000000FF", "00000000", "00000000", "000000FF"])
d1 = [x for x in f.get("DL1", []) if x != ["start"]]
if len(d1) != 1 or not 50 <= int(d1[0][0], 16) <= 59:
    bad.append("DL1 %s: expected 50-59 ticks" % d1)
for k in ("DL2", "DL3", "DL4"):
    if f.get(k) != [["start"]]:
        bad.append("%s %s: a negative Delay must not return" % (k, f.get(k)))
inf = f.get("INF", [[]])[0]
if (len(inf) != 13 or inf[0] != "FFFFFFFF" or inf[1:8] != ["00000000", "00000000", "00000052", "000006DE", "0000003A",
        "000001E8", "444F5300"] or inf[9] == "00000000" or inf[10:] != ["5A5A5A5A"] * 3):
    bad.append("INF %s: expected the 1.3 layout with InUse != 0" % inf)
print("\n".join(bad) if bad else "DOSMISC OK")
sys.exit(1 if bad else 0)
PY
