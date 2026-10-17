#!/usr/bin/env bash
# tests/boot_test_kbd.sh — boot headless FS-UAE + INJECTION CLAVIER via xdotool (jalon F2b).
#
# Prouve la chaîne CLAVIER bout-en-bout : xdotool key -> fenêtre FS-UAE (XTEST) -> clavier émulé CIA-A ->
# kbd_interrupt (ICR bit 3) -> keymap -> ring SPSC -> con_handler READ -> shell -> dispatch. Contrairement au
# harnais série (socat), l'entrée arrive par le VRAI clavier émulé. XTEST (pas XSendEvent/--window que SDL ignore).
#
# Usage : boot_test_kbd.sh <rom> <adf> <ready_marker> <keys...> <success_marker> [wait] [settle] [postwait]
#   keys : séquence de noms de touches xdotool séparés par des espaces (ex. "v e r Return").
# Codes de sortie : 0 = succès ; 1 = régression/absent ; 2 = prérequis manquant.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13.rom}"
ADF="${2:-$ROOT/assets/boot_c.adf}"
READY="${3:-E3 CMD RAN OK}"
KEYS="${4:-v e r Return}"
MARKER="${5:-E2 SHELL ver OK}"
WAIT="${6:-90}"
SETTLE="${7:-4}"
POSTWAIT="${8:-5}"
FAILMARK="FAILED"
OUT="$ROOT/build/boot_kbd"; mkdir -p "$OUT"
SERLOG="$OUT/serial.log"; : > "$SERLOG"

[ -f "$ROM" ] || { echo "ROM absente : $ROM"; exit 2; }
[ -f "$ADF" ] || { echo "ADF absent : $ADF"; exit 2; }
for t in fs-uae Xvfb xwd socat xdotool; do command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }; done

XPID=""; FPID=""; SERPID=""; CATPID=""
cleanup() {
  for p in "$FPID" "$CATPID" "$SERPID" "$XPID"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  sleep 0.3
  for p in "$FPID" "$CATPID" "$SERPID" "$XPID"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
}
trap cleanup EXIT INT TERM

socat pty,raw,echo=0,link="$OUT/ser_uae" pty,raw,echo=0,link="$OUT/ser_cap" >"$OUT/socat.log" 2>&1 &
SERPID=$!
for _ in $(seq 1 40); do [ -e "$OUT/ser_uae" ] && break; sleep 0.1; done
cat "$OUT/ser_cap" >> "$SERLOG" 2>/dev/null &
CATPID=$!

DISP=""
for n in $(seq 99 120); do [ -e "/tmp/.X${n}-lock" ] && continue; DISP=":$n"; break; done
[ -n "$DISP" ] || { echo "aucun display X libre"; exit 2; }
Xvfb "$DISP" -screen 0 1024x768x24 >"$OUT/xvfb.log" 2>&1 &
XPID=$!
for _ in $(seq 1 50); do xwd -root -display "$DISP" -silent >/dev/null 2>&1 && break; sleep 0.2; done

CFG="$OUT/kbd.fs-uae"
cat > "$CFG" <<EOF
[fs-uae]
amiga_model = A500
kickstart_file = $ROM
chip_memory = 512
fast_memory = 0
floppy_drive_count = 1
floppy_drive_0 = $ADF
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
serial_port = $OUT/ser_uae
EOF

DISPLAY="$DISP" fs-uae "$CFG" >"$OUT/fs-uae.log" 2>&1 &
FPID=$!

ready=0
for _ in $(seq 1 $((WAIT*4))); do
  grep -qF "$READY" "$SERLOG" && { ready=1; break; }
  sleep 0.25
done
echo "prêt (« $READY » vu) = $ready"
sleep "$SETTLE"

WID="$(DISPLAY="$DISP" xdotool search --name 'FS-UAE' 2>/dev/null | head -1)"
[ -z "$WID" ] && WID="$(DISPLAY="$DISP" xdotool search --class 'fs-uae' 2>/dev/null | head -1)"
echo "fenêtre FS-UAE WID=$WID"
if [ -n "$WID" ]; then
  DISPLAY="$DISP" xdotool windowmap "$WID" 2>/dev/null
  DISPLAY="$DISP" xdotool windowraise "$WID" 2>/dev/null
  DISPLAY="$DISP" xdotool windowfocus --sync "$WID" 2>/dev/null
  DISPLAY="$DISP" xdotool windowactivate --sync "$WID" 2>/dev/null
  DISPLAY="$DISP" xdotool mousemove --window "$WID" 360 284 click 1 2>/dev/null
fi

echo "=== injection clavier (XTEST) : $KEYS ==="
for k in $KEYS; do
  DISPLAY="$DISP" xdotool key --clearmodifiers "$k" 2>/dev/null
  sleep 0.22
done
sleep "$POSTWAIT"

echo "=== serial.log (fin) ==="
tr -cd '\11\12\15\40-\176\n' < "$SERLOG" | tail -14 | sed 's/^/  [ser] /'

if grep -qi "$FAILMARK" "$SERLOG"; then echo "ECHEC : « $FAILMARK » présent."; exit 1; fi
if grep -qF "$MARKER" "$SERLOG"; then echo "OK : « $MARKER » présent (commande tapée au VRAI clavier -> exécutée)."; exit 0; fi
echo "ECHEC : « $MARKER » absent."; exit 1
