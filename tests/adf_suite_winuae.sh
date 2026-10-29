#!/usr/bin/env bash
# tests/adf_suite_winuae.sh - end-of-step non-regression under WinUAE Linux (Unix port of WinUAE, AppImage) in a
# hardware-faithful A500 configuration: cycle-exact 68000, OCS, PAL, 512 KB chip + 512 KB slow, floppy at
# real speed. Each floppy in assets/test_adf/ is booted from a writable copy, under Xvfb, without GUI.
# Per floppy: bootblock executed? (ROM marker "M6Y STRAP BOOTED OK" on the serial), alert/guru, final capture.
# The serial goes over TCP: key `unix.serial_port` (the `serial_port` key of Windows WinUAE is unknown here).
#
# Usage: tests/adf_suite_winuae.sh [rom] [seconds per floppy] [name filter (grep -i)]
# Variable: WINUAE = WinUAE Linux launcher (AppRun of the extracted AppImage); default: "winuae" taken from the PATH.
# Output: build/adf_suite_winuae/<n>/{screen.png,serial.log,winuae.log,a500.uae} + build/adf_suite_winuae/summary.txt
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13.rom}"
WAIT="${2:-120}"
FILTER="${3:-}"
WINUAE="${WINUAE:-winuae}"
DIR="$ROOT/assets/test_adf"
OUT="$ROOT/build/adf_suite_winuae"
MARKER="M6Y STRAP BOOTED OK"
[ -f "$ROM" ] || { echo "ROM absente : $ROM"; exit 2; }
[ -d "$DIR" ] || { echo "répertoire absent : $DIR"; exit 2; }
WINUAE="$(command -v "$WINUAE")" || { echo "WinUAE absent : définir WINUAE (chemin de AppRun) ou le mettre dans le PATH"; exit 2; }
for t in Xvfb xwd convert socat; do command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }; done
ROM="$(readlink -f "$ROM")"
mkdir -p "$OUT"
SUMMARY="$OUT/summary.txt"
printf 'WinUAE Linux A500 cycle-exact — ROM %s (md5 %s), %s s par disquette\n' "$ROM" "$(md5sum "$ROM" | cut -c1-8)" \
  "$WAIT" > "$SUMMARY"

DISP=""
for n in $(seq 99 140); do [ -e "/tmp/.X${n}-lock" ] && continue; DISP=":$n"; break; done
[ -n "$DISP" ] || { echo "aucun display X libre"; exit 2; }
Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 &
XPID=$!
WPID=""; CPID=""
cleanup() {
  for p in "$WPID" "$CPID"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
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
  port=$((23200 + n))
  cat > "$d/a500.uae" <<CFG
use_gui=no
cpu_type=68000
cpu_model=68000
cpu_compatible=true
cpu_cycle_exact=true
cycle_exact=true
chipset=ocs
chipset_compatible=A500
chipmem_size=1
bogomem_size=2
fastmem_size=0
kickstart_rom_file=$ROM
floppy0=$d/disk.adf
floppy0type=0
nr_floppies=1
floppy_speed=100
gfx_width_windowed=720
gfx_height_windowed=568
gfx_fullscreen_amiga=false
sound_output=none
unix.serial_port=TCP://127.0.0.1:$port
CFG
  DISPLAY="$DISP" QT_QPA_PLATFORM=xcb SDL_AUDIODRIVER=dummy "$WINUAE" -f "$d/a500.uae" > "$d/winuae.log" 2>&1 &
  WPID=$!
  ( for _ in $(seq 1 60); do socat -u "TCP:127.0.0.1:$port" - >> "$d/serial.log" 2>/dev/null && break; sleep 0.25; done ) &
  CPID=$!
  sleep "$WAIT"
  xwd -root -display "$DISP" -silent 2>/dev/null | convert xwd:- "$d/screen.png" 2>/dev/null
  kill "$WPID" 2>/dev/null; sleep 1; kill -9 "$WPID" 2>/dev/null
  kill "$CPID" 2>/dev/null; wait "$WPID" "$CPID" 2>/dev/null
  WPID=""; CPID=""
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
