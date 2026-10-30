#!/usr/bin/env bash
# tests/setmap_probe.sh - harness for tests/setmap_probe.s (TEST ASSET, NOT ROM code; ANALYSIS track,
# docs/analysis/setmap-13.md). Takes a COPY of a Workbench 1.3.3 disk that contains System/SetMap and
# devs/keymaps/d (German WB), replaces s/startup-sequence by a probe script and adds the probe as SYS:sp,
# boots FS-UAE with the REAL 1.3 ROM (default), captures the serial log (each probe run sends its log slowly at
# its end) and takes a screen shot on each "@S x" line. The script ends with "SetMap nosuch" (error requester expected): shot_z.png is taken 10 s after "@S W"
# (tag "W" = the probe waits for the console handler with a plain WaitPort, the others poll).
# Only one FS-UAE at a time on the machine: we wait until `pgrep -x fs-uae` is empty.
# Usage: SETMAP_ADF=<wb disk .adf> tests/setmap_probe.sh <output directory> [max duration in s, default 300]
# SETMAP_SEQ="cmd1;cmd2;..." replaces the default startup-sequence lines (control runs).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?sortie}"; DUR="${2:-300}"
ROM="${CON_ROM:-$ROOT/assets/kick34005.A500}"
SRC="${SETMAP_ADF:?SETMAP_ADF = Workbench disk containing System/SetMap and devs/keymaps/d}"
mkdir -p "$OUT"
for t in fs-uae Xvfb xwd xdotool convert socat vasmm68k_mot xdftool; do
  command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }
done
vasmm68k_mot -Fhunkexe -kick1hunks -m68000 -quiet -o "$OUT/sp" "$ROOT/tests/setmap_probe.s" || exit 2
cp "$SRC" "$OUT/probe.adf"; chmod u+w "$OUT/probe.adf"
if [ -n "${SETMAP_SEQ:-}" ]; then tr ';' '\n' <<< "$SETMAP_SEQ" > "$OUT/startup-sequence"; else
printf '%s\n' "failat 21" "sys:sp a" "sys:System/SetMap" "sys:sp b" "sys:System/SetMap d" "sys:sp c" \
  "sys:System/SetMap D" "sys:sp d" "sys:System/SetMap usa" "sys:sp e" "sys:System/SetMap d" "sys:sp W" \
  "sys:System/SetMap nosuch" "sys:sp z" > "$OUT/startup-sequence"; fi
xdftool "$OUT/probe.adf" delete s/startup-sequence + write "$OUT/startup-sequence" s/startup-sequence \
  + write "$OUT/sp" sp >/dev/null || exit 2
while pgrep -x fs-uae >/dev/null || { sleep 3; pgrep -x fs-uae >/dev/null; }; do sleep 2; done
DISP=""
for n in $(seq 99 120); do [ -e "/tmp/.X${n}-lock" ] || { DISP=":$n"; break; }; done
[ -n "$DISP" ] || { echo "aucun display X libre"; exit 2; }
XP=""; FP=""; SP=""; CP=""
cleanup() { for p in "$FP" "$CP" "$SP" "$XP"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; sleep 0.5
            for p in "$FP" "$CP" "$SP" "$XP"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done; }
trap cleanup EXIT INT TERM
: > "$OUT/serial.log"
socat pty,raw,echo=0,link="$OUT/ser_uae" pty,raw,echo=0,link="$OUT/ser_cap" >/dev/null 2>&1 & SP=$!
for _ in $(seq 1 40); do [ -e "$OUT/ser_cap" ] && break; sleep 0.1; done
cat "$OUT/ser_cap" >> "$OUT/serial.log" 2>/dev/null & CP=$!
Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 & XP=$!
sleep 2
cat > "$OUT/cfg.fs-uae" <<EOF
[fs-uae]
amiga_model = A500
kickstart_file = $ROM
chip_memory = 512
slow_memory = 512
fast_memory = 0
floppy_drive_count = 1
floppy_drive_0 = $OUT/probe.adf
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
serial_port = $OUT/ser_uae
joystick_port_1 = none
EOF
if [ -n "${CON_DBG:-}" ]; then echo "console_debugger = 1" >> "$OUT/cfg.fs-uae"; fi
rm -f "$OUT/in"; mkfifo "$OUT/in"; exec 3<>"$OUT/in"
T0=$(date +%s)
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" < "$OUT/in" >"$OUT/fs-uae.log" 2>&1 & FP=$!
seen=""; tz=""
while [ $(( $(date +%s) - T0 )) -lt "$DUR" ]; do
  sleep 0.4
  log="$(tr -cd '\11\12\15\40-\176' < "$OUT/serial.log")"
  for m in $(grep -o '^@S .' <<< "$log" | cut -c4); do
    case "$seen" in *"<$m>"*) continue;; esac
    seen="$seen<$m>"
    sleep 0.6
    DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/shot_$m.png" 2>/dev/null
    echo "capture $m"
    [ "$m" = W ] && tz=$(date +%s)
  done
  if [ -n "$tz" ] && [ $(( $(date +%s) - tz )) -ge 10 ]; then
    DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/shot_z.png" 2>/dev/null
    break
  fi
done
if [ ! -e "$OUT/shot_z.png" ]; then
  DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/shot_timeout.png" 2>/dev/null
  if [ -n "${CON_DBG:-}" ]; then        # CON_DBG=1: on a hang, task list and registers (FS-UAE debugger)
    WID="$(DISPLAY="$DISP" xdotool search --name 'FS-UAE' 2>/dev/null | head -1)"
    DISPLAY="$DISP" xdotool windowfocus --sync "$WID" 2>/dev/null
    DISPLAY="$DISP" xdotool keydown F12 key d keyup F12 2>/dev/null; sleep 3
    python3 -I "$ROOT/tests/debug_tasks.py" "$OUT/in" "$OUT/fs-uae.log" > "$OUT/tasks.txt" 2>&1
    for i in 1 2 3; do printf 'r\n' >&3; sleep 1; printf 't\n' >&3; sleep 1; done
    sleep 1; cp "$OUT/fs-uae.log" "$OUT/dbg.log"
  fi
fi
tr -cd '\11\12\15\40-\176' < "$OUT/serial.log" > "$OUT/serial.txt"
cat "$OUT/serial.txt"
