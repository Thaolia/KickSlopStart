#!/usr/bin/env bash
# tests/gdisp_probe.sh — sonde boîte noire de la construction d'affichage de graphics (PISTE ANALYSE).
# Construit un ADF : bootblock = tests/gdisp_probe.s assemblé avec -DLOADER, corps de la sonde à l'offset 1024.
# Boote FS-UAE (vraie ROM 1.3 par défaut), capture la série et un écran. Un seul FS-UAE à la fois sur la machine.
#
# Usage : GDISP_OUT=<dir> tests/gdisp_probe.sh [pal|ntsc] [durée_s=40]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIDEO="${1:-pal}"; DUR="${2:-40}"
ROM="${GDISP_ROM:-$ROOT/assets/kick34005.A500}"
OUT="${GDISP_OUT:?GDISP_OUT = répertoire de sortie}"
mkdir -p "$OUT"
for t in fs-uae Xvfb xwd convert socat vasmm68k_mot python3; do
  command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }
done
vasmm68k_mot -Fbin -m68000 -quiet -DLOADER=1 -o "$OUT/boot.bin" "$ROOT/tests/gdisp_probe.s" || exit 2
vasmm68k_mot -Fbin -m68000 -quiet -o "$OUT/blob.bin" "$ROOT/tests/gdisp_probe.s" || exit 2
python3 -I - "$OUT/boot.bin" "$OUT/blob.bin" "$OUT/probe.adf" <<'EOF'
import struct, sys
code = open(sys.argv[1], 'rb').read()
blob = open(sys.argv[2], 'rb').read()
assert len(code) <= 1012 and len(blob) <= 24576, (len(code), len(blob))
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
img = bytearray(901120)
img[0:1024] = bb
img[1024:1024 + len(blob)] = blob
open(sys.argv[3], 'wb').write(bytes(img))
EOF
NTSC=0; [ "$VIDEO" = ntsc ] && NTSC=1
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
ntsc_mode = $NTSC
floppy_drive_count = 1
floppy_drive_0 = $OUT/probe.adf
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
serial_port = $OUT/ser_uae
EOF
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" >"$OUT/fs-uae.log" 2>&1 & FP=$!
for _ in $(seq 1 "$DUR"); do
  sleep 1
  grep -q '^END' "$OUT/serial.log" 2>/dev/null && break
done
sleep 1
DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/screen.png" 2>/dev/null
tr -d '\r' < "$OUT/serial.log" | tr -cd '\11\12\40-\176' > "$OUT/serial.txt"
wc -l "$OUT/serial.txt"
