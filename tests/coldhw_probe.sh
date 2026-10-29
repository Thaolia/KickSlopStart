#!/usr/bin/env bash
# tests/coldhw_probe.sh - black-box probe of the coldstart under FS-UAE with the REAL 1.3 ROM (ANALYSIS track).
# Builds an ADF whose bootblock is tests/coldhw_probe.s (chosen MODE), boots it, captures the serial output and
# timestamped screenshots, and can inject left clicks (to acknowledge a Guru). Output: $OUT/serial.log,
# $OUT/shot_*.png. Only one FS-UAE at a time on the machine: wait until `pgrep -x fs-uae` is empty.
#
# Usage: tests/coldhw_probe.sh <mode> <chip_kb> <slow_kb> <duration_s> [clicks "t1 t2 ..."] [captures "t1 t2 ..."]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:?mode}"; CHIP="${2:-512}"; SLOW="${3:-0}"; DUR="${4:-30}"; CLICKS="${5:-}"; SHOTS="${6:-}"
ROM="${COLDHW_ROM:-$ROOT/assets/kick34005.A500}"
OUT="${COLDHW_OUT:?COLDHW_OUT = répertoire de sortie}"
mkdir -p "$OUT"
for t in fs-uae Xvfb xwd convert socat xdotool vasmm68k_mot python3; do
  command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }
done
vasmm68k_mot -Fbin -m68000 -quiet -DMODE="$MODE" -o "$OUT/bb.bin" "$ROOT/tests/coldhw_probe.s" || exit 2
python3 -I - "$OUT/bb.bin" "$OUT/probe.adf" <<'EOF'
import struct, sys
code = open(sys.argv[1], 'rb').read()
assert len(code) <= 1012, len(code)
bb = bytearray(1024)
bb[0:4] = b'DOS\0'
struct.pack_into('>I', bb, 8, 880)
bb[12:12 + len(code)] = code
s = 0
for i in range(0, 1024, 4):
    s += struct.unpack('>I', bb[i:i + 4])[0]
    if s > 0xFFFFFFFF:
        s = (s & 0xFFFFFFFF) + 1
struct.pack_into('>I', bb, 4, (~s) & 0xFFFFFFFF)
open(sys.argv[2], 'wb').write(bytes(bb) + bytes(901120 - 1024))
EOF
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
chip_memory = $CHIP
slow_memory = $SLOW
fast_memory = 0
floppy_drive_count = 1
floppy_drive_0 = $OUT/probe.adf
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
serial_port = $OUT/ser_uae
EOF
T0=$(date +%s.%N)
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" >"$OUT/fs-uae.log" 2>&1 & FP=$!
EVENTS=$( { for t in $CLICKS; do echo "$t c"; done; for t in $SHOTS; do echo "$t s"; done; } | sort -n )
WID=""
while read -r t kind; do
  [ -z "$t" ] && continue
  now=$(echo "$(date +%s.%N) - $T0" | bc); d=$(echo "$t - $now" | bc)
  awk "BEGIN{exit !($d > 0)}" && sleep "$d"
  if [ "$kind" = c ]; then
    [ -z "$WID" ] && WID="$(DISPLAY="$DISP" xdotool search --name 'FS-UAE' 2>/dev/null | head -1)"
    [ -n "$WID" ] && DISPLAY="$DISP" xdotool mousemove --window "$WID" 360 284 2>/dev/null
    DISPLAY="$DISP" xdotool mousedown 1 2>/dev/null; sleep 0.3; DISPLAY="$DISP" xdotool mouseup 1 2>/dev/null
    echo "clic @ $t s"
  else
    DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/shot_$t.png" 2>/dev/null
    echo "capture @ $t s"
  fi
done <<< "$EVENTS"
now=$(echo "$(date +%s.%N) - $T0" | bc); d=$(echo "$DUR - $now" | bc)
awk "BEGIN{exit !($d > 0)}" && sleep "$d"
tr -cd '\11\12\15\40-\176' < "$OUT/serial.log"
