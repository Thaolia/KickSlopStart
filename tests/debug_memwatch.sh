#!/usr/bin/env bash
# tests/debug_memwatch.sh — boot FS-UAE avec le débogueur console, puis point d'arrêt mémoire posé en cours de route.
# Sert à trouver QUI écrit à une adresse (ex. SERDAT $DFF030 quand des octets parasites sortent sur la série) : à T0
# secondes, F12+D (injecté par xdotool) entre dans le débogueur, les commandes CMDS sont envoyées puis « g » ; après T1
# secondes, registres (« r ») et désassemblage autour du PC sont relevés. Sortie : build/debug_memwatch/uae.log.
# Le désassemblage affiché est celui du code en cours (souvent un programme tiers) : n'en tirer que du comportement.
#
# Usage : tests/debug_memwatch.sh <rom> <adf> [T0=75] [T1=120] [CMDS="w 0 dff030 2 w"]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:?rom}"; ADF="${2:?adf}"; T0="${3:-75}"; T1="${4:-120}"; CMDS="${5:-w 0 dff030 2 w}"
OUT="$ROOT/build/debug_memwatch"
mkdir -p "$OUT"
for t in fs-uae Xvfb xdotool xwd convert; do command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }; done
cp "$ADF" "$OUT/disk.adf"; chmod 644 "$OUT/disk.adf"
DISP=""
for n in $(seq 99 120); do [ -e "/tmp/.X${n}-lock" ] || { DISP=":$n"; break; }; done
[ -n "$DISP" ] || { echo "aucun display X libre"; exit 2; }
Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 & XP=$!
FP=""
cleanup() { [ -n "$FP" ] && kill "$FP" 2>/dev/null; kill "$XP" 2>/dev/null; sleep 1
            [ -n "$FP" ] && kill -9 "$FP" 2>/dev/null; kill -9 "$XP" 2>/dev/null; exec 3>&- 2>/dev/null; }
trap cleanup EXIT INT TERM
sleep 2
rm -f "$OUT/in"; mkfifo "$OUT/in"
cat > "$OUT/cfg.fs-uae" <<EOF
[fs-uae]
amiga_model = A500
kickstart_file = $ROM
chip_memory = 512
slow_memory = 512
fast_memory = 0
floppy_drive_count = 1
floppy_drive_0 = $OUT/disk.adf
console_debugger = 1
fullscreen = 0
window_width = 720
window_height = 568
EOF
exec 3<>"$OUT/in"
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" < "$OUT/in" > "$OUT/uae.log" 2>&1 & FP=$!
sleep "$T0"
WID="$(DISPLAY="$DISP" xdotool search --name 'FS-UAE' 2>/dev/null | head -1)"
[ -n "$WID" ] && DISPLAY="$DISP" xdotool windowfocus --sync "$WID" 2>/dev/null
DISPLAY="$DISP" xdotool keydown F12 key d keyup F12
sleep 3
printf '%s\n' "$CMDS" "g" >&3
sleep "$T1"
printf 'r\n' >&3; sleep 2
printf 'd pc-30 20\n' >&3; sleep 2
DISPLAY="$DISP" xwd -root -silent 2>/dev/null | convert xwd:- "$OUT/screen.png" 2>/dev/null
echo "log : $OUT/uae.log ; capture : $OUT/screen.png"
