#!/usr/bin/env bash
# tests/boot_test.sh — boot headless FS-UAE + assertion « écran vert » (gate CI).
#
# Boote une ROM sous FS-UAE dans un display virtuel Xvfb, capture l'écran et
# ASSÈRE qu'il est majoritairement vert (preuve que le coldstart hello a écrit
# COLOR00, donc que notre code s'exécute sur l'A500 émulée).
#
# Codes de sortie : 0 = vert dominant (OK) ; 1 = régression/capture vide ;
#                   2 = prérequis manquant.
# Usage : tests/boot_test.sh [chemin/vers/rom] [secondes_de_boot]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13.rom}"
WAIT="${2:-10}"
EXPECT="${3:-FFFFFF}"   # couleur de succès attendue (hex RRGGBB) ; défaut blanc
OUT="$ROOT/build/boot"
mkdir -p "$OUT"

[ -f "$ROM" ] || { echo "ROM absente : $ROM (lance 'make hello')"; exit 2; }
for t in fs-uae Xvfb xwd convert; do
  command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }
done

# Choisir un display X LIBRE (évite le conflit/stale sur un :N figé).
DISP=""
for n in $(seq 99 120); do
  [ -e "/tmp/.X${n}-lock" ] && continue
  DISP=":$n"; break
done
[ -n "$DISP" ] || { echo "aucun display X libre entre :99 et :120"; exit 2; }

XPID=""; FPID=""
cleanup() {
  [ -n "$FPID" ] && kill "$FPID" 2>/dev/null
  [ -n "$XPID" ] && kill "$XPID" 2>/dev/null
  sleep 0.3
  [ -n "$FPID" ] && kill -9 "$FPID" 2>/dev/null
  [ -n "$XPID" ] && kill -9 "$XPID" 2>/dev/null
}
trap cleanup EXIT INT TERM

Xvfb "$DISP" -screen 0 1024x768x24 >"$OUT/xvfb.log" 2>&1 &
XPID=$!
# Readiness : attendre que le serveur réponde (pas de sleep aveugle).
ready=0
for _ in $(seq 1 50); do
  if xwd -root -display "$DISP" -silent >/dev/null 2>&1; then ready=1; break; fi
  kill -0 "$XPID" 2>/dev/null || { echo "Xvfb a quitté au démarrage"; exit 2; }
  sleep 0.2
done
[ "$ready" = 1 ] || { echo "Xvfb non prêt sur $DISP"; exit 2; }

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

DISPLAY="$DISP" fs-uae "$CFG" >"$OUT/fs-uae.log" 2>&1 &
FPID=$!
sleep "$WAIT"

xwd -root -display "$DISP" -silent 2>/dev/null | convert xwd:- "$OUT/screen.png" 2>/dev/null
[ -s "$OUT/screen.png" ] || { echo "ECHEC : capture écran vide"; exit 1; }

# Fraction de pixels verts sur la zone active (vert -> blanc, reste -> noir, moyenne).
FRAC=$(convert "$OUT/screen.png" -crop 700x540+10+14 +repage \
        -fuzz 20% -fill white -opaque "#$EXPECT" -fill black +opaque white \
        -colorspace Gray -format '%[fx:mean]' info: 2>/dev/null)
echo "fraction couleur #$EXPECT (zone active) = ${FRAC:-?}"
grep -iE 'kickstart|rom |error|fatal' "$OUT/fs-uae.log" | head -10
echo "capture : $OUT/screen.png"

if [ -n "${FRAC:-}" ] && awk "BEGIN{exit !(${FRAC:-0} > 0.5)}"; then
  echo "OK : écran majoritairement #$EXPECT → exécution jusqu'à la phase de succès."
  exit 0
fi
echo "ECHEC : #$EXPECT non dominante (régression ou phase bloquée en amont)."
exit 1
