#!/usr/bin/env bash
# tests/sched_probe.sh - builds tests/sched_probe.s (CLI executable), runs it from the startup-sequence of a bootable
# OFS disk in an Amiberry session on our ROM, keeps the "SP ..." serial lines in <out_dir>/sched.txt and checks them
# against docs/analysis/exec-scheduling-v34.md §2.3, §2.7, §8 and timer-v34.md §3.
#
# Usage: tests/sched_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/sched_probe" "$ROOT/tests/sched_probe.s" || exit 2
printf 'df0:sched_probe\n' > "$OUT/startup"
ADF="$OUT/sched_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/sched_probe" sched_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="scp$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" || exit 2
"$A" wait-serial "$NAME" "SP END" 240; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | sed -n '/^SP BEGIN/,/^SP END/p' > "$OUT/sched.txt"
"$A" stop "$NAME" >/dev/null
[ $RC = 0 ] || exit $RC
cat "$OUT/sched.txt"
python3 -I - "$OUT/sched.txt" <<'PY'
import sys
f = {l.split()[1]: l.split()[2:] for l in open(sys.argv[1]) if l.startswith("SP ") and len(l.split()) > 2}
bad = []
q = f.get("Q", [])
if (len(q) != 10 or q[0] != "0010" or q[1] != "E" or not all(1 <= int(e, 16) <= 16 for e in q[2:])
        or all(e == "0010" for e in q[2:])):
    bad.append("Quantum/Elapsed %s: expected Quantum 0010 and Elapsed counting down within 1..16" % q)
s = [int(v, 16) for v in f.get("SIG", [])]
if len(s) != 2 or s[0] & 0x100000 or s[1] != s[0] | 0x100000:
    bad.append("Signal returns %s: expected the previous tc_SigRecvd, the second with $00100000" % s)
o = [int(v, 16) for v in f.get("SOFT", [])]
if len(o) != 2 or o[0] & 0x2700 != 0x2000 or o[1] & 4:
    bad.append("software interrupt SR/INTENAR %s: expected SR $2000 and SOFTINT off in INTENA" % o)
if f.get("ORD") != ["CEBDFA"]:
    bad.append("software interrupt order %s: expected CEBDFA (five priority queues, FIFO inside one)" % f.get("ORD"))
print("\n".join(bad) if bad else "SCHED OK")
sys.exit(1 if bad else 0)
PY
