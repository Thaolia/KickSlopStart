#!/usr/bin/env bash
# tests/adf_suite_amiberry.sh — même non-régression que tests/adf_suite.sh, mais sous Amiberry (cœur WinUAE) en
# configuration A500 fidèle au matériel : 68000 cycle-exact (CPU, mémoire, blitter), OCS, PAL, 512 Ko chip + 512 Ko
# slow, disquette à vitesse réelle. Chaque disquette de assets/test_adf/ est bootée sur une copie inscriptible.
# Par disquette : bootblock exécuté ? (marqueur ROM « M6Y STRAP BOOTED OK » sur le série), alerte/guru, capture finale.
# Le série passe par TCP (Amiberry écoute, attend la connexion avant de démarrer : rien n'est perdu).
#
# Usage : tests/adf_suite_amiberry.sh [rom] [secondes par disquette] [filtre de nom (grep -i)]
# Variable : AMIBERRY = binaire (défaut ~/dev/tools/amiberry/build/amiberry, compilé depuis les sources).
# Sortie : build/adf_suite_amiberry/<n>/{screen.png,serial.log,amiberry.log} + build/adf_suite_amiberry/summary.txt
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13.rom}"
WAIT="${2:-90}"
FILTER="${3:-}"
AMIBERRY="${AMIBERRY:-$HOME/dev/tools/amiberry/build/amiberry}"
DIR="$ROOT/assets/test_adf"
OUT="$ROOT/build/adf_suite_amiberry"
MARKER="M6Y STRAP BOOTED OK"
[ -f "$ROM" ] || { echo "ROM absente : $ROM"; exit 2; }
[ -d "$DIR" ] || { echo "répertoire absent : $DIR"; exit 2; }
[ -x "$AMIBERRY" ] || { echo "Amiberry absent : $AMIBERRY"; exit 2; }
for t in Xvfb xwd convert socat; do command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }; done
ROM="$(readlink -f "$ROM")"
mkdir -p "$OUT"
SUMMARY="$OUT/summary.txt"
printf 'Amiberry A500 cycle-exact — ROM %s (md5 %s), %s s par disquette\n' "$ROM" "$(md5sum "$ROM" | cut -c1-8)" \
  "$WAIT" > "$SUMMARY"

DISP=""
for n in $(seq 99 140); do [ -e "/tmp/.X${n}-lock" ] && continue; DISP=":$n"; break; done
[ -n "$DISP" ] || { echo "aucun display X libre"; exit 2; }
Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 &
XPID=$!
APID=""; CPID=""
cleanup() {
  for p in "$APID" "$CPID"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  kill "$XPID" 2>/dev/null
}
trap cleanup EXIT INT TERM
for _ in $(seq 1 50); do xwd -root -display "$DISP" -silent >/dev/null 2>&1 && break; sleep 0.2; done

n=0
fails=0
for adf in "$DIR"/*.adf; do
  name="$(basename "$adf" .adf)"
  if [ -n "$FILTER" ] && ! printf '%s' "$name" | grep -qi -- "$FILTER"; then continue; fi
  n=$((n + 1))
  d="$OUT/$n"
  rm -rf "$d"; mkdir -p "$d"
  cp "$adf" "$d/disk.adf"; chmod 644 "$d/disk.adf"
  : > "$d/serial.log"
  port=$((23100 + n))
  (cd "$(dirname "$AMIBERRY")/.." && DISPLAY="$DISP" SDL_AUDIODRIVER=dummy exec "$AMIBERRY" --model A500 -G \
      -r "$ROM" -0 "$d/disk.adf" -b 2 -s "serial_port=TCP://127.0.0.1:$port/wait") > "$d/amiberry.log" 2>&1 &
  APID=$!
  ( for _ in $(seq 1 60); do socat -u "TCP:127.0.0.1:$port" - >> "$d/serial.log" 2>/dev/null && break; sleep 0.5; done ) &
  CPID=$!
  sleep "$WAIT"
  xwd -root -display "$DISP" -silent 2>/dev/null | convert xwd:- "$d/screen.png" 2>/dev/null
  kill "$APID" 2>/dev/null; sleep 1; kill -9 "$APID" 2>/dev/null
  kill "$CPID" 2>/dev/null; wait "$APID" "$CPID" 2>/dev/null
  APID=""; CPID=""
  boot=KO; grep -aqF "$MARKER" "$d/serial.log" && boot=OK
  [ "$boot" = OK ] || fails=$((fails + 1))
  alert=""
  grep -aqiE 'guru meditation|software failure' "$d/serial.log" 2>/dev/null && alert=" ALERTE"
  colors=$(convert "$d/screen.png" -format '%k' info: 2>/dev/null || echo '?')
  printf '%-2s %-4s couleurs=%-5s%s  %s\n' "$n" "$boot" "$colors" "$alert" "$name" | tee -a "$SUMMARY"
  printf '      dernières lignes série : %s\n' \
    "$(tr -cd '\11\12\15\40-\176' < "$d/serial.log" | grep -av '^\s*$' | tail -2 | tr '\n' '|' | cut -c1-160)" \
    >> "$SUMMARY"
done
echo "résumé : $SUMMARY ($n disquettes, $fails sans boot)"
[ "$fails" = 0 ]
