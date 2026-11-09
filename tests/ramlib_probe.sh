#!/usr/bin/env bash
# tests/ramlib_probe.sh - harness for tests/ramlib_probe.s (disk loading of libraries/devices, low-memory expunge;
# docs/analysis/ramlib-v34.md §8.1). Builds the probe, copies the Workbench 1.3.3 boot disk to <out_dir>, replaces its
# startup-sequence (no SetPatch: "stack 16000", then the probe with its output redirected to df0:rl.out) and writes
# the probe onto it, boots it in an Amiberry session, waits for "RL DONE" on the serial line, then stops the session
# and extracts df0:rl.out from the disk image the emulator wrote back.
# Results: <out_dir>/serial.txt (the "RL" lines of the serial log up to the first "RL DONE"; on our ROM the
# console echoes the later "type" there too) and <out_dir>/rl.out (the Output() copy).
#
# Usage: tests/ramlib_probe.sh <rom> <out_dir> [timeout s, default 240]
# RL_ANALYSIS=1 passes --analysis to amiberry-session (Commodore ROM): ANALYSIS AGENT ONLY (CLAUDE.md firewall).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:?rom}"; OUT="${2:?out_dir}"; TMO="${3:-240}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
WB="$ROOT/assets/wb133.adf"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -quiet -o "$OUT/ramlib_probe" "$ROOT/tests/ramlib_probe.s" \
  || { echo "vasm failed"; exit 2; }
ADF="$OUT/rlp_$(date +%s).adf"
cp "$WB" "$ADF" && chmod u+w "$ADF" || exit 2
printf 'stack 16000\ndf0:ramlib_probe >df0:rl.out\ntype df0:rl.out\n' > "$OUT/startup-sequence"
xdftool "$ADF" delete s/startup-sequence + write "$OUT/startup-sequence" s/startup-sequence \
  + write "$OUT/ramlib_probe" ramlib_probe >/dev/null || { echo "xdftool failed"; exit 2; }

NAME="rlp$$"
if [ "${RL_ANALYSIS:-0}" = 1 ]; then
  MODE=(--analysis); SES="$ROOT/build/amiberry/analysis/$NAME"
else
  MODE=(); SES="$ROOT/build/amiberry/sessions/$NAME"
fi
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" "${MODE[@]}" >/dev/null || { echo "start failed"; exit 2; }
"$A" wait-serial "$NAME" "RL DONE" "$TMO"; RC=$?
sleep 5                                         # let the handler close rl.out and the image reach the file
"$A" shot "$NAME" "$OUT/screen.png" --via ipc >/dev/null 2>&1
"$A" stop "$NAME" >/dev/null
tr -d '\r' < "$SES/serial.log" | awk '/^RL /{print} /^RL DONE/{exit}' > "$OUT/serial.txt"
cp "$SES/serial.log" "$OUT/serial.log"
DISK=$(ls -t "$SES"/*.adf | head -1)
xdftool "$DISK" read rl.out "$OUT/rl.out" >/dev/null 2>&1 || echo "(no rl.out on the disk)"
cat "$OUT/serial.txt"
[ $RC -eq 0 ] || echo "no RL DONE within $TMO s"
exit $RC
