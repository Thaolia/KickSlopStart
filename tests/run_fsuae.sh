#!/usr/bin/env bash
# tests/run_fsuae.sh - runs our ROM in FS-UAE, WINDOWED (to see it on screen).
# Unlike boot_test.sh (headless Xvfb + assertion), this script opens a real window:
# a display is therefore required (WSLg under WSL2, or X). Usage: tests/run_fsuae.sh [rom]
# E.g.: make && tests/run_fsuae.sh        (shows the "KickSlopStart" boot screen)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13.rom}"
[ -f "$ROM" ] || { echo "ROM absente : $ROM (lance 'make' d'abord)"; exit 1; }
command -v fs-uae >/dev/null || { echo "fs-uae introuvable dans le PATH"; exit 1; }
[ -n "${DISPLAY:-}" ] || echo "note : DISPLAY non défini — sous WSL2, WSLg doit fournir l'affichage."

exec fs-uae \
  --amiga_model=A500 \
  --kickstart_file="$ROM" \
  --chip_memory=512 \
  --fast_memory=0 \
  --floppy_drive_count=0 \
  --fullscreen=0 \
  --window_width=720 \
  --window_height=568
