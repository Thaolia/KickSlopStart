#!/usr/bin/env bash
# tests/alert_probe.sh — sonde boîte noire d'intuition DisplayAlert / exec Alert sous FS-UAE avec la VRAIE ROM 1.3
# (piste ANALYSE). Bootblock = tests/alert_probe.s (MODE choisi). Harnais RÉACTIF : il lit la série et, à chaque
# marqueur « @X » (juste avant un DisplayAlert), prend des captures horodatées puis clique (gauche ou droit).
# Après le dernier marqueur, il capture et clique à gauche toutes les 6 s jusqu'à « IDLE » (cas du Guru d'alert.hook).
# Un seul FS-UAE à la fois sur la machine : attendre que `pgrep -x fs-uae` soit vide.
#
# Usage : tests/alert_probe.sh <mode> <chip_ko> <slow_ko> <durée_max_s>
# Variables : ALERT_OUT (obligatoire) ; CLICK_A/CLICK_B/CLICK_C = L ou R (défaut L, R, L).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:?mode}"; CHIP="${2:-512}"; SLOW="${3:-0}"; DUR="${4:-90}"
ROM="${ALERT_ROM:-$ROOT/assets/kick34005.A500}"
OUT="${ALERT_OUT:?ALERT_OUT = répertoire de sortie}"
mkdir -p "$OUT"
for t in fs-uae Xvfb xwd convert socat xdotool vasmm68k_mot python3; do
  command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }
done
vasmm68k_mot -Fbin -m68000 -quiet -DMODE="$MODE" -o "$OUT/bb.bin" "$ROOT/tests/alert_probe.s" || exit 2
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
T0=$(date +%s)
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" >"$OUT/fs-uae.log" 2>&1 & FP=$!
WID=""
shot() { DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/shot_$1.png" 2>/dev/null; echo "capture $1"; }
click() {
  local b=1; [ "$1" = R ] && b=3
  [ -z "$WID" ] && WID="$(DISPLAY="$DISP" xdotool search --name 'FS-UAE' 2>/dev/null | head -1)"
  [ -n "$WID" ] && DISPLAY="$DISP" xdotool mousemove --window "$WID" 360 284 2>/dev/null
  DISPLAY="$DISP" xdotool mousedown "$b" 2>/dev/null; sleep 0.3; DISPLAY="$DISP" xdotool mouseup "$b" 2>/dev/null
  echo "clic $1"
}
done_marks=""
last=""
idle_t=0
while [ $(( $(date +%s) - T0 )) -lt "$DUR" ]; do
  sleep 0.5
  log="$(tr -cd '\11\12\15\40-\176' < "$OUT/serial.log")"
  for m in A B C; do
    case "$done_marks" in *$m*) continue;; esac
    if grep -q "^@$m" <<< "$log"; then
      done_marks="$done_marks$m"; last=$m
      shot "${m}_0"
      sleep 2;  shot "${m}_2.0"
      sleep 0.3; shot "${m}_2.3"
      sleep 0.3; shot "${m}_2.6"
      sleep 0.3; shot "${m}_2.9"
      sleep 0.3; shot "${m}_3.2"
      v="CLICK_$m"; d=L; [ "$m" = B ] && d=R
      click "${!v:-$d}"
      sleep 2; shot "${m}_apres"
    fi
  done
  if grep -q "IDLE" <<< "$log"; then
    [ "$idle_t" = 0 ] && { idle_t=$(date +%s); shot "idle"; }
    [ $(( $(date +%s) - idle_t )) -ge 3 ] && break
  elif [ -n "$last" ] && [ $(( $(date +%s) - T0 )) -gt 20 ] && [ $(( ( $(date +%s) - T0 ) % 6 )) -eq 0 ]; then
    shot "t$(( $(date +%s) - T0 ))"; click L; sleep 1
  fi
done
tr -cd '\11\12\15\40-\176' < "$OUT/serial.log"
