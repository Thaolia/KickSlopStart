#!/usr/bin/env bash
# tests/fpuctx_probe.sh - builds tests/fpuctx_probe.s (CLI executable), runs it from the startup-sequence of a bootable
# OFS disk in an Amiberry session on our ROM with the given CPU/FPU, keeps the "FC ..." serial lines in
# <out_dir>/fpuctx.txt and checks them against docs/analysis/cpu-fpu-v34.md §1, §3 and §5.
#
# Usage: tests/fpuctx_probe.sh <out_dir> <cpu> [fpu] [rom=build/kick13-prod.rom]
#   cpu = 68000 | 68010 | 68020 | 68030 | 68040; fpu = none | 68881 | 68882 (a 68040 always has its own)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; CPU="${2:?cpu}"; FPU="${3:-none}"; ROM="${4:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -no-opt -m68020 -m68881 -quiet -o "$OUT/fpuctx_probe" \
  "$ROOT/tests/fpuctx_probe.s" || exit 2
printf 'df0:fpuctx_probe\n' > "$OUT/startup"
ADF="$OUT/fpuctx_$$.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/fpuctx_probe" fpuctx_probe >/dev/null || { echo "xdftool failed"; exit 2; }
OPTS=(-s cpu_model=$CPU)
[ "$CPU" = 68040 ] && FPU=68040
[ "$FPU" != none ] && OPTS+=(-s fpu_model=$FPU)
case $CPU in 68000|68010) OPTS+=(-s cpu_24bit_addressing=true);; *) OPTS+=(-s cpu_24bit_addressing=false);; esac
NAME="fpc$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" -- "${OPTS[@]}" >/dev/null || exit 2
"$A" wait-serial "$NAME" "FC END" 240; RC=$?
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | grep -a '^FC ' > "$OUT/fpuctx.txt"
"$A" stop "$NAME" >/dev/null
[ $RC = 0 ] || exit $RC
cat "$OUT/fpuctx.txt"
python3 -I - "$OUT/fpuctx.txt" "$CPU" "$FPU" <<'PY'
import sys
lines = [l.split() for l in open(sys.argv[1])]
cpu, fpu = sys.argv[2], sys.argv[3]
f = {l[1]: l[2:] for l in lines if len(l) > 1}
bad = []
want = {"68000": 0, "68010": 1}.get(cpu, 3) | (0x10 if fpu != "none" else 0)
attn = f.get("ATTN", [])
if len(attn) != 3 or int(attn[0], 16) != want:
    bad.append("AttnFlags %s: expected %04X (cpu-fpu-v34 §1)" % (attn, want))
elif int(attn[2], 16) != (1 if cpu in ("68020", "68030") else 0):
    bad.append("CACR %s: expected 1 on a 68020/68030, 0 otherwise (§5)" % attn[2])
if fpu == "none":
    if "NOFPU" not in f:
        bad.append("FC NOFPU missing")
else:
    c = [int(v, 16) for v in f.get("CTX", [])]
    if len(c) != 5 or c[0] < 150 or c[1] == 0 or c[2] or c[3] or c[4] < 60:
        bad.append("FPU context %s: expected both tasks running, no error, switches" % c)
print("\n".join(bad) if bad else "FPUCTX OK")
sys.exit(1 if bad else 0)
PY
