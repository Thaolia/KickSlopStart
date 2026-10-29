#!/usr/bin/env bash
# tests/debug_tasks.sh - FS-UAE boot (same configuration as tests/boot_test.sh) with the console debugger; at T0
# seconds (after a hang), F12+D then tests/debug_tasks.py walks exec's task lists (READY / WAIT:
# name, state, signals waited for and received, messages pending on the processes' port).
# Usage: tests/debug_tasks.sh <rom> <adf> [T0=240] [output directory=build/debug_tasks]
set -u
ROM="${1:?rom}"; ADF="${2:?adf}"; T0="${3:-240}"; S="$(cd "$(dirname "$0")" && pwd)"; OUT="${4:-$S/../build/debug_tasks}"
mkdir -p "$OUT"; cp "$ADF" "$OUT/disk.adf"; chmod 644 "$OUT/disk.adf"
DISP=""; for n in $(seq 99 120); do [ -e "/tmp/.X${n}-lock" ] || { DISP=":$n"; break; }; done
Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 & XP=$!
FP=""; cleanup() { [ -n "$FP" ] && kill "$FP" 2>/dev/null; kill "$XP" 2>/dev/null; sleep 1; [ -n "$FP" ] && kill -9 "$FP" 2>/dev/null; kill -9 "$XP" 2>/dev/null; exec 3>&- 2>/dev/null; }
trap cleanup EXIT INT TERM
sleep 2; rm -f "$OUT/in"; mkfifo "$OUT/in"
cat > "$OUT/cfg.fs-uae" <<CFG
[fs-uae]
amiga_model = A500
kickstart_file = $ROM
chip_memory = 512
fast_memory = 0
floppy_drive_count = 1
floppy_drive_0 = $OUT/disk.adf
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
serial_port = /dev/null
console_debugger = 1
CFG
exec 3<>"$OUT/in"
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" < "$OUT/in" > "$OUT/uae.log" 2>&1 & FP=$!
sleep "$T0"
DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/screen.png" 2>/dev/null
WID="$(DISPLAY="$DISP" xdotool search --name 'FS-UAE' 2>/dev/null | head -1)"
[ -n "$WID" ] && DISPLAY="$DISP" xdotool windowfocus --sync "$WID" 2>/dev/null
DISPLAY="$DISP" xdotool keydown F12 key d keyup F12
sleep 3
python3 -I "$S/debug_tasks.py" "$OUT/in" "$OUT/uae.log"
