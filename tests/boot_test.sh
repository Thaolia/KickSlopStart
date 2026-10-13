#!/usr/bin/env bash
# tests/boot_test.sh — boot headless FS-UAE + assertion (gate CI).
#
# Canal d'assertion PRIMAIRE = log SÉRIE (SERDAT) capturé via un pont PTY socat
# (conforme à docs/PLAN.md). La ROM émet des marqueurs texte ; le test assère la
# présence du marqueur de SUCCÈS et l'absence du marqueur d'ÉCHEC.
# Repli AUTOMATIQUE sur l'assertion couleur d'écran quand aucun série n'est émis
# (ex. hello-ROM M0 qui ne fait qu'écrire COLOR00).
#
# Codes de sortie : 0 = succès ; 1 = régression/capture vide ; 2 = prérequis manquant.
# Usage : tests/boot_test.sh [rom] [secondes] [couleur_hex] [marqueur_succès]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13.rom}"
WAIT="${2:-10}"
EXPECT="${3:-FFFFFF}"                 # couleur de succès (repli) ; défaut blanc
MARKER="${4:-self-test passed}"       # marqueur série de succès
FAILMARK="FAILED"                     # marqueur série d'échec
OUT="$ROOT/build/boot"
mkdir -p "$OUT"

[ -f "$ROM" ] || { echo "ROM absente : $ROM (lance 'make')"; exit 2; }
for t in fs-uae Xvfb xwd convert socat; do
  command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }
done

# Choisir un display X LIBRE (évite le conflit/stale sur un :N figé).
DISP=""
for n in $(seq 99 120); do
  [ -e "/tmp/.X${n}-lock" ] && continue
  DISP=":$n"; break
done
[ -n "$DISP" ] || { echo "aucun display X libre entre :99 et :120"; exit 2; }

XPID=""; FPID=""; SERPID=""; CATPID=""
cleanup() {
  for p in "$FPID" "$CATPID" "$SERPID" "$XPID"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  sleep 0.3
  for p in "$FPID" "$CATPID" "$SERPID" "$XPID"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
}
trap cleanup EXIT INT TERM

# Pont série : PTY socat. FS-UAE écrit sur ser_uae, on lit ser_cap -> serial.log.
SERLOG="$OUT/serial.log"
: > "$SERLOG"
socat pty,raw,echo=0,link="$OUT/ser_uae" pty,raw,echo=0,link="$OUT/ser_cap" \
      >"$OUT/socat.log" 2>&1 &
SERPID=$!
serready=0
for _ in $(seq 1 40); do
  [ -e "$OUT/ser_uae" ] && [ -e "$OUT/ser_cap" ] && { serready=1; break; }
  kill -0 "$SERPID" 2>/dev/null || break
  sleep 0.1
done
if [ "$serready" = 1 ]; then
  cat "$OUT/ser_cap" >> "$SERLOG" 2>/dev/null &
  CATPID=$!
else
  echo "note : pont série socat non prêt — assertion couleur seulement"
fi

Xvfb "$DISP" -screen 0 1024x768x24 >"$OUT/xvfb.log" 2>&1 &
XPID=$!
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
serial_port = $OUT/ser_uae
EOF

DISPLAY="$DISP" fs-uae "$CFG" >"$OUT/fs-uae.log" 2>&1 &
FPID=$!
sleep "$WAIT"
sync

# Capture écran (diagnostic + repli couleur).
xwd -root -display "$DISP" -silent 2>/dev/null | convert xwd:- "$OUT/screen.png" 2>/dev/null
FRAC=""
if [ -s "$OUT/screen.png" ]; then
  FRAC=$(convert "$OUT/screen.png" -crop 700x540+10+14 +repage \
          -fuzz 20% -fill white -opaque "#$EXPECT" -fill black +opaque white \
          -colorspace Gray -format '%[fx:mean]' info: 2>/dev/null)
fi
echo "fraction couleur #$EXPECT (zone active) = ${FRAC:-?}"
echo "capture : $OUT/screen.png"

SERBYTES=$(stat -c%s "$SERLOG" 2>/dev/null || echo 0)
echo "série capturée : ${SERBYTES} o -> $SERLOG"
if [ "$SERBYTES" -gt 0 ]; then
  tr -cd '\11\12\15\40-\176\n' < "$SERLOG" | sed 's/^/  [ser] /' | head -20
fi

# --- Assertion ---
# Canal PRIMAIRE série si des octets ont été capturés ; sinon repli couleur.
if [ "$SERBYTES" -gt 0 ]; then
  if grep -qi "$FAILMARK" "$SERLOG"; then
    echo "ECHEC : marqueur série d'échec « $FAILMARK » présent."
    exit 1
  fi
  if grep -qF "$MARKER" "$SERLOG"; then
    echo "OK : marqueur série de succès « $MARKER » présent."
    exit 0
  fi
  echo "ECHEC : marqueur série « $MARKER » absent (phase bloquée en amont ?)."
  exit 1
fi

# Repli : aucune émission série -> assertion couleur (hello-ROM, etc.).
if [ -n "${FRAC:-}" ] && awk "BEGIN{exit !(${FRAC:-0} > 0.5)}"; then
  echo "OK (repli couleur) : écran majoritairement #$EXPECT."
  exit 0
fi
echo "ECHEC : ni série ni couleur #$EXPECT dominante (régression ou phase bloquée)."
exit 1
