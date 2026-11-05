#!/usr/bin/env bash
# tests/fsuae_run.sh - headless FS-UAE run that waits for a serial marker (boot_test.sh waits a fixed time).
# Serial through a socat PTY into <out>/serial.log, Xvfb on a free display, screenshot <out>/screen.png at the end.
# Fast RAM in FSUAE_FAST (KB, default 0). Extra FS-UAE config lines in FSUAE_EXTRA_CFG (e.g. hard_drive_0 = x.hdf); after the marker the emulator keeps
# running FSUAE_AFTER seconds (default 6) so that delayed writes reach the images, then it is stopped.
# Exit: 0 marker seen, 1 timeout, 2 missing tool.
# Usage: tests/fsuae_run.sh <rom> <out dir> <adf> <marker> [timeout s, default 300]
set -u
ROM="${1:?rom}"; OUT="${2:?out dir}"; ADF="${3:?adf}"; MARKER="${4:?marker}"; TMO="${5:-300}"
for t in fs-uae Xvfb xwd convert socat; do command -v "$t" >/dev/null || { echo "missing tool: $t"; exit 2; }; done
mkdir -p "$OUT"
DISP=""
for n in $(seq 121 160); do [ -e "/tmp/.X${n}-lock" ] && continue; DISP=":$n"; break; done
[ -n "$DISP" ] || { echo "no free X display"; exit 2; }
XPID=""; FPID=""; SERPID=""; CATPID=""
cleanup() {
  for p in "$FPID" "$CATPID" "$SERPID" "$XPID"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  sleep 0.5
  for p in "$FPID" "$CATPID" "$SERPID" "$XPID"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
}
trap cleanup EXIT INT TERM
SERLOG="$OUT/serial.log"; : > "$SERLOG"
socat pty,raw,echo=0,link="$OUT/ser_uae" pty,raw,echo=0,link="$OUT/ser_cap" >"$OUT/socat.log" 2>&1 &
SERPID=$!
for _ in $(seq 1 40); do [ -e "$OUT/ser_uae" ] && [ -e "$OUT/ser_cap" ] && break; sleep 0.1; done
cat "$OUT/ser_cap" >> "$SERLOG" 2>/dev/null &
CATPID=$!
Xvfb "$DISP" -screen 0 1024x768x24 >"$OUT/xvfb.log" 2>&1 &
XPID=$!
for _ in $(seq 1 50); do xwd -root -display "$DISP" -silent >/dev/null 2>&1 && break; sleep 0.2; done
CFG="$OUT/run.fs-uae"
cat > "$CFG" <<EOF
[fs-uae]
amiga_model = A500
kickstart_file = $ROM
chip_memory = 512
slow_memory = 512
fast_memory = ${FSUAE_FAST:-0}
floppy_drive_count = 1
floppy_drive_0 = $ADF
writable_floppy_images = 1
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
serial_port = $OUT/ser_uae
EOF
[ -n "${FSUAE_EXTRA_CFG:-}" ] && printf '%s\n' "$FSUAE_EXTRA_CFG" >> "$CFG"
DISPLAY="$DISP" fs-uae "$CFG" >"$OUT/fs-uae.log" 2>&1 &
FPID=$!
rc=1
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt "$TMO" ]; do
  if grep -aqF "$MARKER" "$SERLOG"; then rc=0; break; fi
  kill -0 "$FPID" 2>/dev/null || break
  sleep 1
done
echo "marker after $(( $(date +%s) - t0 )) s (rc $rc)"
[ $rc -eq 0 ] && sleep "${FSUAE_AFTER:-6}"
xwd -root -display "$DISP" -silent 2>/dev/null | convert xwd:- -crop 720x568+0+0 +repage "$OUT/screen.png" 2>/dev/null
exit $rc
