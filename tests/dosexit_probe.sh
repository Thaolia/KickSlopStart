#!/usr/bin/env bash
# tests/dosexit_probe.sh - harness for tests/dosexit_test.s (dos Exit/GetPacket/QueuePacket, implementation side).
# Copy of tests/garea_probe.sh with a startup-sequence that runs the test once per mode (see the header of
# dosexit_test.s). Boots FS-UAE headless (Xvfb) on the given ROM, captures the serial output into <out>/serial.log.
# Waits until no other FS-UAE is running (one at a time).
# MODES="e c f n" overrides the list of modes run by the startup-sequence.
# Usage: tests/dosexit_probe.sh <rom> <dosexit_test executable> <output directory> [duration s, default 120]
set -u
ROM="${1:?rom}"; EXE="${2:?exe}"; OUT="${3:?sortie}"; DUR="${4:-120}"
rm -rf "$OUT"; mkdir -p "$OUT/base"
for t in fs-uae Xvfb socat xdftool; do command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }; done
ADF="$OUT/gap_$(date +%s).adf"
printf 'df0:dosexit_test %s\n' ${MODES:-m a c z c f n} > "$OUT/startup"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$EXE" dosexit_test >/dev/null || { echo "xdftool en échec"; exit 2; }
while pgrep -x fs-uae >/dev/null || { sleep 3; pgrep -x fs-uae >/dev/null; }; do sleep 2; done
DISP=""; for n in $(seq 99 120); do [ -e "/tmp/.X${n}-lock" ] || { DISP=":$n"; break; }; done
[ -n "$DISP" ] || { echo "aucun display X libre"; exit 2; }
Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 & XP=$!
FP=""; SP=""; CP=""
cleanup() { [ -n "$FP" ] && kill "$FP" 2>/dev/null; kill "$XP" 2>/dev/null; sleep 1
            [ -n "$FP" ] && kill -9 "$FP" 2>/dev/null; kill -9 "$XP" 2>/dev/null
            [ -n "$CP" ] && kill "$CP" 2>/dev/null; [ -n "$SP" ] && kill "$SP" 2>/dev/null; }
trap cleanup EXIT INT TERM
sleep 2
socat pty,raw,echo=0,link="$OUT/ser_uae" pty,raw,echo=0,link="$OUT/ser_cap" >/dev/null 2>&1 & SP=$!
for _ in $(seq 1 40); do [ -e "$OUT/ser_uae" ] && [ -e "$OUT/ser_cap" ] && break; sleep 0.1; done
cat "$OUT/ser_cap" > "$OUT/serial.log" 2>/dev/null & CP=$!
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
writable_floppy_images = 0
fullscreen = 0
window_width = 720
window_height = 568
serial_port = $OUT/ser_uae
joystick_port_1 = none
EOC
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" > "$OUT/fs-uae.log" 2>&1 & FP=$!
for _ in $(seq 1 "$DUR"); do grep -aq 'DOSEXIT END' "$OUT/serial.log" 2>/dev/null && break; sleep 1; done
sleep 8
echo "sortie : $OUT"; cat "$OUT/serial.log"
