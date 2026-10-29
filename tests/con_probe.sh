#!/usr/bin/env bash
# tests/con_probe.sh - harness for the tests/con_probe.s probe (ANALYSIS track,
# docs/analysis/console-keymap-v34.md): FS-UAE boot with the REAL 1.3 ROM, floppy = probe
# (two-stage bootblock), serial log captured; on each "@S x" line a capture <out>/shot_x.png;
# on the "@K" line the harness types a sequence of real keys (xdotool) into the FS-UAE window.
# Only one FS-UAE at a time on the machine: we wait until `pgrep -x fs-uae` is empty.
# Usage: tests/con_probe.sh <output directory> [max duration in s, default 240]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?sortie}"; DUR="${2:-240}"
ROM="${CON_ROM:-$ROOT/assets/kick34005.A500}"
mkdir -p "$OUT"
for t in fs-uae Xvfb xwd xdotool convert socat vasmm68k_mot python3; do
  command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }
done
vasmm68k_mot -Fbin -m68000 -quiet -o "$OUT/probe.bin" "$ROOT/tests/con_probe.s" || exit 2
python3 -I - "$OUT/probe.bin" "$OUT/probe.adf" <<'EOF'
import struct, sys
code = open(sys.argv[1], 'rb').read()
assert len(code) <= 32768 - 12, len(code)
img = bytearray(901120)
img[0:4] = b'DOS\0'
struct.pack_into('>I', img, 8, 880)
img[12:12 + len(code)] = code
s = 0
for i in range(0, 1024, 4):
    s += struct.unpack('>I', img[i:i + 4])[0]
    if s > 0xFFFFFFFF:
        s = (s & 0xFFFFFFFF) + 1
struct.pack_into('>I', img, 4, (~s) & 0xFFFFFFFF)
open(sys.argv[2], 'wb').write(bytes(img))
EOF
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
# CON_DBG=1: console debugger; on a hang, task list (debug_tasks.py) and current registers
if [ -n "${CON_DBG:-}" ]; then echo "console_debugger = 1" >> "$OUT/cfg.fs-uae"; fi
rm -f "$OUT/in"; mkfifo "$OUT/in"; exec 3<>"$OUT/in"
T0=$(date +%s)
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" < "$OUT/in" >"$OUT/fs-uae.log" 2>&1 & FP=$!
seen=""
while [ $(( $(date +%s) - T0 )) -lt "$DUR" ]; do
  sleep 0.4
  log="$(tr -cd '\11\12\15\40-\176' < "$OUT/serial.log")"
  for m in $(grep -o '^@S .' <<< "$log" | cut -c4); do
    case "$seen" in *"<$m>"*) continue;; esac
    seen="$seen<$m>"
    sleep 0.6
    DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/shot_$m.png" 2>/dev/null
    echo "capture $m"
  done
  if [ -z "${typed:-}" ] && grep -q "^@K" <<< "$log"; then
    typed=1; sleep 1
    WID="$(DISPLAY="$DISP" xdotool search --name 'FS-UAE' 2>/dev/null | head -1)"
    DISPLAY="$DISP" xdotool windowfocus --sync "$WID" 2>/dev/null
    for k in a shift+a alt+f e alt+k u Up shift+Up F1 shift+F10 ctrl+c Tab shift+Tab Escape BackSpace Delete Return KP_Enter KP_1 KP_Subtract alt+Escape ctrl+Return shift+space alt+space; do
      DISPLAY="$DISP" xdotool key --clearmodifiers "$k" 2>/dev/null; echo "key $k"; sleep 2.2
    done
  fi
  grep -q "^IDLE" <<< "$log" && { sleep 1; DISPLAY="$DISP" xwd -root -silent | convert xwd:- "$OUT/shot_end.png"; break; }
  grep -q "^FAIL" <<< "$log" && break
done
if [ ! -e "$OUT/shot_end.png" ]; then
  DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/shot_timeout.png" 2>/dev/null
  if [ -n "${CON_DBG:-}" ]; then
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
