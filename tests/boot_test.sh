#!/usr/bin/env bash
# tests/boot_test.sh — boot headless de la hello-ROM sous FS-UAE, contrôle écran.
#
# Lance FS-UAE dans un display virtuel (Xvfb), laisse la ROM booter, capture
# l'écran et rapporte les couleurs dominantes. Pour la hello-ROM M0, un fond
# vert confirme que le coldstart a écrit COLOR00 (donc que notre code s'exécute).
#
# Usage : tests/boot_test.sh [chemin/vers/rom] [secondes_de_boot]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13-hello.rom}"
WAIT="${2:-10}"
DISP=":99"
OUT="$ROOT/build/boot"
mkdir -p "$OUT"

[ -f "$ROM" ] || { echo "ROM absente : $ROM (lance 'make hello')"; exit 2; }
command -v fs-uae >/dev/null || { echo "fs-uae absent"; exit 2; }
command -v Xvfb   >/dev/null || { echo "Xvfb absent"; exit 2; }

CFG="$OUT/hello.fs-uae"
cat > "$CFG" <<EOF
[fs-uae]
amiga_model = A500
kickstart_file = $ROM
chip_memory = 512
fast_memory = 0
floppy_drive_count = 0
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
EOF

Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 &
XPID=$!
sleep 1
DISPLAY="$DISP" fs-uae "$CFG" >"$OUT/fs-uae.log" 2>&1 &
FPID=$!
sleep "$WAIT"

xwd -root -display "$DISP" -silent 2>/dev/null | convert xwd:- "$OUT/screen.png" 2>/dev/null
echo "=== couleurs dominantes (hors bordure) ==="
convert "$OUT/screen.png" -crop 700x540+10+14 +repage -colors 6 -format "%c" histogram:info:- 2>/dev/null \
  | sort -rn | head -6

kill "$FPID" 2>/dev/null; wait "$FPID" 2>/dev/null
kill "$XPID" 2>/dev/null; wait "$XPID" 2>/dev/null

echo "=== log FS-UAE (lignes clés) ==="
grep -iE 'kickstart|rom |error|fatal|checksum|cpu ' "$OUT/fs-uae.log" | head -20
echo "capture : $OUT/screen.png"
