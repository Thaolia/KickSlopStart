#!/usr/bin/env bash
# tests/wbdemo_capture.sh - black-box capture harness (ANALYSIS TRACK): boots a WRITABLE COPY of a Workbench
# ADF whose s/startup-sequence is replaced by "run <cmd>" + "endcli >nil:", on the given ROM under FS-UAE
# (Xvfb, A500, 512K chip + 512K slow), and takes one xwd screen capture per second as <out>/cap_NNN.png.
# The original ADF is never modified. Waits until no other FS-UAE runs.
# Usage: tests/wbdemo_capture.sh <rom> <adf> <amiga command> <output directory> [duration s, default 70]
set -u
ROM="${1:?rom}"; SRC="${2:?adf}"; CMD="${3:?command}"; OUT="${4:?out}"; DUR="${5:-70}"
for t in fs-uae Xvfb xwd convert xdftool; do command -v "$t" >/dev/null || { echo "missing tool: $t"; exit 2; }; done
rm -rf "$OUT"; mkdir -p "$OUT/base"
ADF="$OUT/disk.adf"
cp "$SRC" "$ADF"; chmod u+w "$ADF"
printf 'run %s\nendcli >nil:\n' "$CMD" > "$OUT/startup"
xdftool "$ADF" delete s/startup-sequence + write "$OUT/startup" s/startup-sequence >/dev/null || { echo "xdftool failed"; exit 2; }
while pgrep -x fs-uae >/dev/null || { sleep 3; pgrep -x fs-uae >/dev/null; }; do sleep 2; done
DISP=""; for n in $(seq 99 120); do [ -e "/tmp/.X${n}-lock" ] || { DISP=":$n"; break; }; done
[ -n "$DISP" ] || { echo "no free X display"; exit 2; }
Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 & XP=$!
FP=""
cleanup() { [ -n "$FP" ] && kill "$FP" 2>/dev/null; kill "$XP" 2>/dev/null; sleep 1
            [ -n "$FP" ] && kill -9 "$FP" 2>/dev/null; kill -9 "$XP" 2>/dev/null; }
trap cleanup EXIT INT TERM
sleep 2
cat > "$OUT/cfg.fs-uae" <<EOC
[fs-uae]
base_dir = $OUT/base
amiga_model = A500
kickstart_file = $ROM
chip_memory = 512
slow_memory = 512
fast_memory = 0
floppy_drive_count = 1
floppy_drive_0 = $ADF
writable_floppy_images = 1
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
joystick_port_1 = none
EOC
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" > "$OUT/fs-uae.log" 2>&1 & FP=$!
for i in $(seq -w 1 "$DUR"); do
  sleep 1
  DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/cap_$i.png" 2>/dev/null
done
echo "output: $OUT"
