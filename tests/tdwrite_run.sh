#!/usr/bin/env bash
# tests/tdwrite_run.sh — harnais de la sonde tests/tdwrite.s (piste analyse, docs/analysis/trackdisk-write-v34.md).
# Fabrique une disquette OFS vierge amorçable (xdftool) dont la startup-sequence lance la sonde, boote FS-UAE headless
# (Xvfb) avec débogueur console, active le journal disque de l'émulateur (« did 2 » : une ligne par écriture DSKLEN avec
# ADKCON et PC), capture le série dans <out>/serial.log et le journal dans <out>/fs-uae.log.
# Dossier de base FS-UAE propre à la séance (<out>/base) : le journal de l'émulateur y est isolé
# (<out>/base/Cache/Logs/fs-uae.log.txt), à l'abri des autres séances.
# TDW_WP=1 : disquette protégée en écriture (ADF en lecture seule + writable_floppy_images = 1 : sans surcouche,
# FS-UAE présente alors le disque comme protégé ; uae_floppy0wp et floppy_write_protect sont ignorés).
# Usage : tests/tdwrite_run.sh <rom> <exécutable tdwrite> <répertoire de sortie> [durée s, défaut 150]
set -u
ROM="${1:?rom}"; EXE="${2:?exe}"; OUT="${3:?sortie}"; DUR="${4:-150}"
rm -rf "$OUT"; mkdir -p "$OUT/base"
for t in fs-uae Xvfb xdotool socat xdftool; do command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }; done
ADF="$OUT/tdw_$(date +%s).adf"
printf 'df0:tdwrite\n' > "$OUT/startup"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$EXE" tdwrite >/dev/null || { echo "xdftool en échec"; exit 2; }
WRW=0; [ -n "${TDW_WP:-}" ] && { chmod 444 "$ADF"; WRW=1; }
while pgrep -x fs-uae >/dev/null || { sleep 3; pgrep -x fs-uae >/dev/null; }; do sleep 2; done
DISP=""; for n in $(seq 99 120); do [ -e "/tmp/.X${n}-lock" ] || { DISP=":$n"; break; }; done
[ -n "$DISP" ] || { echo "aucun display X libre"; exit 2; }
Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 & XP=$!
FP=""; SP=""; CP=""
cleanup() { [ -n "$FP" ] && kill "$FP" 2>/dev/null; kill "$XP" 2>/dev/null; sleep 1
            [ -n "$FP" ] && kill -9 "$FP" 2>/dev/null; kill -9 "$XP" 2>/dev/null; exec 3>&- 2>/dev/null
            [ -n "$CP" ] && kill "$CP" 2>/dev/null; [ -n "$SP" ] && kill "$SP" 2>/dev/null; }
trap cleanup EXIT INT TERM
sleep 2
socat pty,raw,echo=0,link="$OUT/ser_uae" pty,raw,echo=0,link="$OUT/ser_cap" >/dev/null 2>&1 & SP=$!
for _ in $(seq 1 40); do [ -e "$OUT/ser_uae" ] && [ -e "$OUT/ser_cap" ] && break; sleep 0.1; done
cat "$OUT/ser_cap" > "$OUT/serial.log" 2>/dev/null & CP=$!
cat > "$OUT/cfg.fs-uae" <<EOC
[fs-uae]
base_dir = $OUT/base
amiga_model = A500
kickstart_file = $ROM
chip_memory = 512
slow_memory = 512
fast_memory = 0
floppy_drive_count = 1
floppy_drive_0 = $ADF
writable_floppy_images = $WRW
fullscreen = 0
window_width = 720
window_height = 568
serial_port = $OUT/ser_uae
console_debugger = 1
joystick_port_1 = none
EOC
rm -f "$OUT/in"; mkfifo "$OUT/in"; exec 3<>"$OUT/in"
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" < "$OUT/in" > "$OUT/fs-uae.log" 2>&1 & FP=$!
sleep 4
WID="$(DISPLAY="$DISP" xdotool search --name 'FS-UAE' 2>/dev/null | head -1)"
[ -n "$WID" ] && DISPLAY="$DISP" xdotool windowfocus --sync "$WID" 2>/dev/null
DISPLAY="$DISP" xdotool keydown F12 key d keyup F12 2>/dev/null
sleep 3
printf 'did 2\n' >&3; sleep 1; printf 'g\n' >&3
for _ in $(seq 1 "$DUR"); do grep -aq 'TDW fin' "$OUT/serial.log" 2>/dev/null && break; sleep 1; done
sleep 2
echo "sortie : $OUT"; cat "$OUT/serial.log"
