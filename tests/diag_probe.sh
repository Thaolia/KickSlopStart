#!/usr/bin/env bash
# tests/diag_probe.sh - the power-on diagnostic (src/exec/diag.s, README "Power-on diagnostic"). Boots a ROM with no
# disk in an Amiberry session, takes a screenshot after a few seconds and keeps the serial lines of the diagnostic.
#
# Usage: tests/diag_probe.sh <out_dir> <case>
#   case pass      the production ROM as built (build/kick13-prod.rom): the boot reaches the insert-disk screen
#   case dev       the dev ROM (build/kick13.rom): "DIAG OK" on the serial port, then the usual boot
#   case rom       a copy of the production ROM with one byte changed: violet screen, "ROM checksum ... FAILED"
#   case 1|2|4|5|6|7  a test build with -DDIAG_FAKE=n (prod flags): 1 chip RAM (magenta, no text), 2 Agnus beam,
#                  4 Paula, 5 CIA-A (orange), 6 ROM checksum (violet), 7 CPU exception (turquoise)
# Read <out_dir>/<case>.png and <out_dir>/<case>.txt.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; C="${2:?case}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
cd "$ROOT" || exit 2
case "$C" in
  pass) ROM="$ROOT/build/kick13-prod.rom" ;;
  dev)  ROM="$ROOT/build/kick13.rom" ;;
  rom)  ROM="$OUT/badsum.rom"
        cp build/kick13-prod.rom "$ROM" && chmod u+w "$ROM" || exit 2
        printf '\x5A' | dd of="$ROM" bs=1 seek=$((0x3F000)) conv=notrunc 2>/dev/null ;;
  [124567])
        make BUILD="build/diag$C" VASMDEF="-DPROD=1 -DDIAG_FAKE=$C" KICK_ROM="build/kick13-diag$C.rom" kick \
          >"$OUT/make$C.log" 2>&1 || { echo "build failed: $OUT/make$C.log"; exit 2; }
        ROM="$ROOT/build/kick13-diag$C.rom" ;;
  *) echo "unknown case $C"; exit 2 ;;
esac
NAME="dgp$$"
"$A" start --name "$NAME" --rom "$ROM" >/dev/null || exit 2
sleep "${WAIT:-8}"
"$A" shot "$NAME" "$OUT/$C.png" --via ipc >/dev/null
tr -d '\r' < "build/amiberry/sessions/$NAME/serial.log" | grep -a -E 'KickSlopStart|DIAG|Chip|Agnus|Paula|CIA|ROM|Vector|PC |Left' \
  > "$OUT/$C.txt"
"$A" stop "$NAME" >/dev/null
echo "$OUT/$C.png"
cat "$OUT/$C.txt"
