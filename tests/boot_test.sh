#!/usr/bin/env bash
# tests/boot_test.sh - headless FS-UAE boot + assertion (CI gate).
#
# PRIMARY assertion channel = SERIAL log (SERDAT) captured through a socat PTY bridge
# (as specified in docs/PLAN.md). The ROM emits text markers; the test asserts the
# presence of the SUCCESS marker and the absence of the FAILURE marker.
# AUTOMATIC fallback to the screen colour assertion when no serial output is emitted
# (e.g. the M0 hello-ROM, which only writes COLOR00).
#
# Exit codes: 0 = success; 1 = regression/empty capture; 2 = missing prerequisite.
# Usage: tests/boot_test.sh [rom] [seconds] [hex_colour] [success_marker] [adf]
# [adf] optional: inserts a floppy in DF0 (floppy_drive_count=1) - required for the read tests (B2+).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13.rom}"
WAIT="${2:-10}"
EXPECT="${3:-FFFFFF}"                 # success colour (fallback); default white
MARKER="${4:-self-test passed}"       # serial success marker
ADF="${5:-}"                          # optional floppy in DF0
FAILMARK="FAILED"                     # serial failure marker
OUT="${BOOT_TEST_OUT:-$ROOT/build/boot}"  # BOOT_TEST_OUT: alternate directory (two boots in parallel)
mkdir -p "$OUT"

[ -f "$ROM" ] || { echo "ROM absente : $ROM (lance 'make')"; exit 2; }
for t in fs-uae Xvfb xwd convert socat; do
  command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }
done

# Pick a FREE X display (avoids conflicts/stale locks with a fixed :N).
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

# Serial bridge: socat PTY. FS-UAE writes to ser_uae, we read ser_cap -> serial.log.
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

FDCOUNT=0
FLOPPY0=""
if [ -n "$ADF" ]; then
  [ -f "$ADF" ] || { echo "ADF absent : $ADF"; exit 2; }
  FDCOUNT=1
  FLOPPY0="floppy_drive_0 = $ADF"
fi
CFG="$OUT/hello.fs-uae"
cat > "$CFG" <<EOF
[fs-uae]
amiga_model = A500
kickstart_file = $ROM
chip_memory = ${BOOT_TEST_CHIP:-512}
fast_memory = 0
floppy_drive_count = $FDCOUNT
$FLOPPY0
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
serial_port = $OUT/ser_uae
EOF
# Extra config lines (e.g. cycle-exact to get closer to a real A500) via the BOOT_TEST_EXTRA_CFG env variable.
# Example: BOOT_TEST_EXTRA_CFG=$'cpu_cycle_exact = 1\nblitter_cycle_exact = 1' tests/boot_test.sh ...
if [ -n "${BOOT_TEST_EXTRA_CFG:-}" ]; then
  printf '%s\n' "${BOOT_TEST_EXTRA_CFG}" >> "$CFG"
fi

DISPLAY="$DISP" fs-uae "$CFG" >"$OUT/fs-uae.log" 2>&1 &
FPID=$!
sleep "$WAIT"
sync

# Screen capture (diagnostics + colour fallback).
# FRAC = fraction of active-area pixels close (fuzz 20%) to #EXPECT. CRITICAL ORDER:
# first blacken the NON-matches (+opaque), THEN whiten the matches (-opaque), otherwise pre-existing
# white survives and FRAC returns ~the screen fraction whatever the colour (bug M4a: a white
# screen matched "green" at 0.67). Correct discriminant for any colour, including non-white ones.
xwd -root -display "$DISP" -silent 2>/dev/null | convert xwd:- "$OUT/screen.png" 2>/dev/null
FRAC=""
if [ -s "$OUT/screen.png" ]; then
  FRAC=$(convert "$OUT/screen.png" -crop 700x540+10+14 +repage \
          -fuzz 20% -fill black +opaque "#$EXPECT" -fill white -opaque "#$EXPECT" \
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
# PRIMARY serial channel if bytes were captured; otherwise colour fallback.
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

# Fallback: no serial output -> colour assertion (hello-ROM, etc.).
if [ -n "${FRAC:-}" ] && awk "BEGIN{exit !(${FRAC:-0} > 0.5)}"; then
  echo "OK (repli couleur) : écran majoritairement #$EXPECT."
  exit 0
fi
echo "ECHEC : ni série ni couleur #$EXPECT dominante (régression ou phase bloquée)."
exit 1
