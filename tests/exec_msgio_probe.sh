#!/usr/bin/env bash
# tests/exec_msgio_probe.sh - builds tests/exec_msgio_probe.s (CLI executable), writes it with a startup-sequence
# that runs it on a bootable OFS disk (with empty libs/ and devs/ directories, so the not-found names fail without a
# requester), boots the disk in an Amiberry session, reads the probe's output buffer through gdb (its bounds are
# printed on the serial port before "MLP fin") into <out_dir>/exec_msgio.txt and checks it with
# tests/exec_msgio_check.py (one PASS/FAIL line per vector). Expected values: docs/analysis/exec-messages-io-v34.md
# §8, with this ROM's deliberate differences (docs/PLAN.md, rank 12).
#
# Usage: tests/exec_msgio_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# MLP_ARGS: probe arguments (default "N": also runs N1, CloseLibrary(NULL); give "" for a ROM where that crashes).
# MLP_ALERT=1: a second boot with the argument A checks AL4 (dead-end alert $81000003 on the serial port).
# The Commodore ROM is refused by amiberry-session unless MLP_ANALYSIS=1 (analysis agent only, see CLAUDE.md); the
# output is then checked against the 1.3 values (check13), and MLP_ARGS should be "".
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
ARGS="${MLP_ARGS-N}"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/exec_msgio_probe" \
  "$ROOT/tests/exec_msgio_probe.s" || exit 2
mkadf() {  # mkadf <adf> <probe arguments>
  printf 'df0:exec_msgio_probe %s\n' "$2" > "$OUT/startup"
  rm -f "$1"
  xdftool "$1" create + format Probe ofs + boot install + makedir s + makedir libs + makedir devs \
    + write "$OUT/startup" s/startup-sequence + write "$OUT/exec_msgio_probe" exec_msgio_probe >/dev/null \
    || { echo "xdftool failed"; exit 2; }
}
NAME="${MLP_NAME:-mlp$$}"
EXTRA=(); DIR="$ROOT/build/amiberry/sessions/$NAME"; MODE=check
[ "${MLP_ANALYSIS:-0}" = 1 ] && { EXTRA=(--analysis); DIR="$ROOT/build/amiberry/analysis/$NAME"; MODE=check13; }
ADF="$OUT/exec_msgio_$$.adf"; mkadf "$ADF" "$ARGS"
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --timeout 120 "${EXTRA[@]}" || exit 2
"$A" wait-serial "$NAME" "MLP fin" 600; RC=$?
if [ $RC = 0 ]; then
  BUF=$(tr -d '\r' < "$DIR/serial.log" | grep -a -m1 -o 'MLP buf=[0-9A-F]\{8\} end=[0-9A-F]\{8\}$')
  S=${BUF#MLP buf=}; S=${S%% *}; E=${BUF##*end=}
  [ -n "$BUF" ] && "$A" gdb "$NAME" -ex "dump binary memory $OUT/exec_msgio.bin 0x$S 0x$E" >/dev/null
  tr -d '\r' < "$OUT/exec_msgio.bin" | sed -n '/^MLP debut/,/^MLP fin/p' > "$OUT/exec_msgio.txt"
fi
"$A" stop "$NAME" >/dev/null
[ $RC = 0 ] || { echo "no MLP fin (timeout)"; exit 1; }
[ -s "$OUT/exec_msgio.txt" ] || { echo "output buffer not read"; exit 1; }
ALERT=()
if [ "${MLP_ALERT:-0}" = 1 ]; then
  ADF2="$OUT/exec_msgio_al4_$$.adf"; mkadf "$ADF2" A
  "$A" start --name "${NAME}a" --rom "$ROM" --adf "$ADF2" --timeout 120 "${EXTRA[@]}" || exit 2
  if "$A" wait-serial "${NAME}a" "81000003" 300; then ALERT=(--alert ok); else ALERT=(--alert none); fi
  "$A" stop "${NAME}a" >/dev/null
fi
python3 -I "$ROOT/tests/exec_msgio_check.py" $MODE "$OUT/exec_msgio.txt" "${ALERT[@]}" > "$OUT/exec_msgio_check.txt"
RC=$?
grep -v '^PASS' "$OUT/exec_msgio_check.txt"
exit $RC
