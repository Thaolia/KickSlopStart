#!/usr/bin/env bash
# tests/adf_suite.sh - end-of-step non-regression: boots EACH floppy in assets/test_adf/ (copies of the user's
# ADFs, read-only) from a writable copy, with 512 KB of slow RAM like an expanded A500.
# Per floppy: bootblock executed? (ROM marker "M6Y STRAP BOOTED OK"), alert/guru, final screen capture.
# The screen contents (game started, Workbench, SysInfo...) are judged on the capture: there is no serial oracle.
#
# Usage: tests/adf_suite.sh [rom] [seconds per floppy] [name filter (grep -i)]
# Output: build/adf_suite/<n>/{screen.png,serial.log} + build/adf_suite/summary.txt
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13.rom}"
WAIT="${2:-90}"
FILTER="${3:-}"
DIR="$ROOT/assets/test_adf"
OUT="$ROOT/build/adf_suite"
[ -f "$ROM" ] || { echo "ROM absente : $ROM"; exit 2; }
[ -d "$DIR" ] || { echo "répertoire absent : $DIR"; exit 2; }
mkdir -p "$OUT"
SUMMARY="$OUT/summary.txt"
printf 'ROM %s (md5 %s), %s s par disquette\n' "$ROM" "$(md5sum "$ROM" | cut -c1-8)" "$WAIT" > "$SUMMARY"

n=0
fails=0
for adf in "$DIR"/*.adf; do
  name="$(basename "$adf" .adf)"
  if [ -n "$FILTER" ] && ! printf '%s' "$name" | grep -qi -- "$FILTER"; then continue; fi
  n=$((n + 1))
  d="$OUT/$n"
  rm -rf "$d"; mkdir -p "$d"
  cp "$adf" "$d/disk.adf"; chmod 644 "$d/disk.adf"
  BOOT_TEST_OUT="$d" BOOT_TEST_EXTRA_CFG=$'slow_memory = 512\nwritable_floppy_images = 1' \
    timeout $((WAIT + 60)) "$ROOT/tests/boot_test.sh" "$ROM" "$WAIT" FFFFFF "M6Y STRAP BOOTED OK" "$d/disk.adf" \
    > "$d/run.log" 2>&1
  rc=$?
  boot=KO; [ "$rc" = 0 ] && boot=OK
  [ "$rc" = 0 ] || fails=$((fails + 1))
  alert=""
  grep -aqiE 'guru meditation|software failure' "$d/serial.log" 2>/dev/null && alert=" ALERTE"
  colors=$(convert "$d/screen.png" -crop 700x540+10+14 +repage -format '%k' info: 2>/dev/null || echo '?')
  printf '%-2s %-4s couleurs=%-4s%s  %s\n' "$n" "$boot" "$colors" "$alert" "$name" | tee -a "$SUMMARY"
  printf '      dernières lignes série : %s\n' \
    "$(tr -cd '\11\12\15\40-\176' < "$d/serial.log" | grep -av '^\s*$' | tail -2 | tr '\n' '|' | cut -c1-160)" \
    >> "$SUMMARY"
done
echo "résumé : $SUMMARY ($n disquettes, $fails sans boot)"
[ "$fails" = 0 ]
