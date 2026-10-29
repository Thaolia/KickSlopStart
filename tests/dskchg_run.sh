#!/usr/bin/env bash
# tests/dskchg_run.sh - harness for the tests/dskchg.s probe (analysis track, docs/analysis/disk-change-v34.md).
# Headless FS-UAE boot (Xvfb) with the console debugger, DF0: = <df0>, and three images in the floppy list
# (floppy_image_0..2); runs a command script, one command per line:
#   sleep N                  wait (seconds, wall clock)
#   shot NAME                full X capture -> <out>/NAME.png (Amiga screen at +152+100, 720x568)
#   media CURRENT TARGET [NAME] changes the DF0: floppy through the FS-UAE F12 MENU (the only method that worked:
#                            the keyboard_key_* = action_*_floppy_* shortcuts are ignored when injected through
#                            xdotool). Positions in the "INSERT INTO DF0" submenu: 0 = EJECT, 1..3 = floppy_image_0..2;
#                            the highlight starts on the CURRENT image (0 if the drive is empty). The first call moves
#                            down from PAUSE to the DF0 entry (7 x Down); afterwards the menu already opens on that
#                            entry. Return on the image closes the menu (no extra F12). Emulation is paused while the
#                            menu is open.
#   rel DX DY [N]            N relative mouse moves (step <= 20: large jumps get lost)
#   dclick                   left double-click
#   click                    single left click
#   rdown / rup              right button pressed / released (menus)
#   key KEY                  key in xdotool format (Down, ctrl+F1...)
#   keyraw KEYS              same without --clearmodifiers (Super_R+q = right Amiga + Q under FS-UAE)
#   cia NAME                 ciaa/ciab.resource vectors and masks (debug_cia.py) -> <out>/NAME.cia
#   dcmd NAME CMDS           raw debugger commands separated by ";", "_" for a space -> <out>/NAME.dcmd
#   tpc NAME TASK [N]        N samples of the task's saved context (PC, registers) -> <out>/NAME.tpc
#   pcs NAME [N] [ADDR]      N debugger stops (registers, and code at ADDR) -> <out>/NAME.pcs
#   dbg NAME                 debugger: tasks (debug_tasks.py) -> <out>/NAME.tasks; registers, code around the PC,
#                            registers $DFF010-$DFF02F (INTENAR/INTREQR) and 40 "t" steps -> <out>/NAME.dbglog; resume
#   dump                     F12+D, reads back the probe's memory log (address at $3F0) -> <out>/log.txt, then "g"
# DSKCHG_SERIAL=1: captures the serial port into <out>/serial.log (trace ROM, e.g. -DDOSTRACE=1).
# Usage: tests/dskchg_run.sh <rom> <df0.adf> <img1.adf> <img2.adf> <script> <output directory>
# The ADFs must carry a NEW NAME for every session (FS-UAE attaches a write overlay keyed by the file name).
set -u
ROM="${1:?rom}"; F0="${2:?df0}"; F1="${3:?img1}"; F2="${4:?img2}"; SCRIPT="${5:?script}"; OUT="${6:?sortie}"
HERE="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$OUT"; mkdir -p "$OUT"
for t in fs-uae Xvfb xdotool xwd convert python3; do command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }; done
# only one emulator at a time: wait for two successive observations of absence
while pgrep -x fs-uae >/dev/null || { sleep 3; pgrep -x fs-uae >/dev/null; }; do sleep 2; done
DISP=""; for n in $(seq 99 120); do [ -e "/tmp/.X${n}-lock" ] || { DISP=":$n"; break; }; done
[ -n "$DISP" ] || { echo "aucun display X libre"; exit 2; }
Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 & XP=$!
FP=""
SP=""; CP=""
cleanup() { [ -n "$FP" ] && kill "$FP" 2>/dev/null; kill "$XP" 2>/dev/null; sleep 1
            [ -n "$FP" ] && kill -9 "$FP" 2>/dev/null; kill -9 "$XP" 2>/dev/null; exec 3>&- 2>/dev/null
            [ -n "$CP" ] && kill "$CP" 2>/dev/null; [ -n "$SP" ] && kill "$SP" 2>/dev/null; }
trap cleanup EXIT INT TERM
sleep 2
SERDEV=/dev/null
if [ -n "${DSKCHG_SERIAL:-}" ]; then           # serial captured into <out>/serial.log (socat PTY bridge)
  command -v socat >/dev/null || { echo "outil absent : socat"; exit 2; }
  socat pty,raw,echo=0,link="$OUT/ser_uae" pty,raw,echo=0,link="$OUT/ser_cap" >/dev/null 2>&1 & SP=$!
  for _ in $(seq 1 40); do [ -e "$OUT/ser_uae" ] && [ -e "$OUT/ser_cap" ] && break; sleep 0.1; done
  cat "$OUT/ser_cap" > "$OUT/serial.log" 2>/dev/null & CP=$!
  SERDEV="$OUT/ser_uae"
fi
cat > "$OUT/cfg.fs-uae" <<EOC
[fs-uae]
amiga_model = A500
kickstart_file = $ROM
chip_memory = 512
slow_memory = 512
fast_memory = 0
floppy_drive_count = 1
floppy_drive_0 = $F0
floppy_image_0 = $F0
floppy_image_1 = $F1
floppy_image_2 = $F2
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
serial_port = $SERDEV
console_debugger = 1
joystick_port_1 = none
EOC
rm -f "$OUT/in"; mkfifo "$OUT/in"; exec 3<>"$OUT/in"
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" < "$OUT/in" > "$OUT/fs-uae.log" 2>&1 & FP=$!
T0=$(date +%s)
sleep 3
X() { DISPLAY="$DISP" xdotool "$@" 2>/dev/null; }
tp() { X keydown "$1"; sleep 0.15; X keyup "$1"; sleep 0.35; }
log() { echo "$(( $(date +%s) - T0 )) $*" >> "$OUT/events.log"; }
# dbgon: F12+D opens the debugger; if the chord is missed, F12 alone opens the FS-UAE menu (nothing in the log):
# close it with F12 and retry (3 attempts).
dbgon() { local p n; for n in 1 2 3; do p=$(stat -c%s "$OUT/fs-uae.log"); X keydown F12 key d keyup F12; sleep 3
            grep -aq 'Next PC' <(tail -c +$((p+1)) "$OUT/fs-uae.log") && return 0; tp F12; sleep 1; done; }
MSEEN=""
while read -r cmd a b c; do
  case "$cmd" in
    sleep) sleep "$a";;
    shot)  DISPLAY="$DISP" xwd -root -silent | convert xwd:- "$OUT/$a.png"; log "shot $a";;
    media) WID="$(X search --name 'FS-UAE' | head -1)"; X windowfocus --sync "$WID"
           tp F12; sleep 1
           if [ -z "$MSEEN" ]; then for i in 1 2 3 4 5 6 7; do tp Down; done; MSEEN=1; fi
           tp Return; sleep 1
           if [ "$b" -lt "$a" ]; then for i in $(seq 1 $((a-b))); do tp Up; done
           else for i in $(seq 1 $((b-a))); do tp Down; done; fi
           [ -n "${c:-}" ] && DISPLAY="$DISP" xwd -root -silent | convert xwd:- "$OUT/$c.png"
           tp Return; sleep 1; log "media $a->$b";;
    rel)   for i in $(seq 1 "${c:-1}"); do X mousemove_relative -- "$a" "$b"; sleep 0.05; done;;
    dclick) for i in 1 2; do X mousedown 1; sleep 0.1; X mouseup 1; sleep 0.15; done;;
    click) X mousedown 1; sleep 0.12; X mouseup 1;;
    rdown) X mousedown 3;;
    rup)   X mouseup 3;;
    key)   WID="$(X search --name 'FS-UAE' | head -1)"; X windowfocus --sync "$WID"
           X key --clearmodifiers "$a"; sleep 0.3;;
    keyraw) WID="$(X search --name 'FS-UAE' | head -1)"; X windowfocus --sync "$WID"
           X key "$a"; sleep 0.3;;
    cia)   WID="$(X search --name 'FS-UAE' | head -1)"; X windowfocus --sync "$WID"
           X keydown F12 key d keyup F12; sleep 3
           python3 -I "$HERE/debug_cia.py" "$OUT/in" "$OUT/fs-uae.log" > "$OUT/$a.cia" 2>&1; printf 'g\n' >&3; log "cia $a";;
    dcmd)  WID="$(X search --name 'FS-UAE' | head -1)"; X windowfocus --sync "$WID"
           P0=$(stat -c%s "$OUT/fs-uae.log"); dbgon
           echo "$b" | tr ';_' '\n ' | while read -r dc; do printf '%s\n' "$dc" >&3; sleep 1; done
           sleep 1; tail -c +$((P0+1)) "$OUT/fs-uae.log" > "$OUT/$a.dcmd"; printf 'g\n' >&3; log "dcmd $a";;
    tpc)   WID="$(X search --name 'FS-UAE' | head -1)"; X windowfocus --sync "$WID"
           X keydown F12 key d keyup F12; sleep 3
           python3 -I "$HERE/debug_taskpc.py" "$OUT/in" "$OUT/fs-uae.log" "$b" "${c:-5}" \
             "DISPLAY=$DISP xdotool keydown F12 key d keyup F12" > "$OUT/$a.tpc" 2>&1; log "tpc $a";;
    pcs)   WID="$(X search --name 'FS-UAE' | head -1)"; X windowfocus --sync "$WID"
           for i in $(seq 1 "${b:-5}"); do X keydown F12 key d keyup F12; sleep 2; printf 'r\n' >&3; sleep 1
             [ -n "${c:-}" ] && { printf 'd %s 24\n' "$c" >&3; sleep 1; }
             printf 'g\n' >&3; sleep 1; done
           cp "$OUT/fs-uae.log" "$OUT/$a.pcs"; log "pcs $a";;
    dbg)   WID="$(X search --name 'FS-UAE' | head -1)"; X windowfocus --sync "$WID"
           X keydown F12 key d keyup F12; sleep 3
           python3 -I "$HERE/debug_tasks.py" "$OUT/in" "$OUT/fs-uae.log" > "$OUT/$a.tasks" 2>&1
           printf 'r\n' >&3; sleep 2; printf 'd pc-40 40\n' >&3; sleep 2
           printf 'm dff010 2\n' >&3; sleep 1
           for i in $(seq 1 40); do printf 't\n' >&3; sleep 0.2; done; sleep 1
           cp "$OUT/fs-uae.log" "$OUT/$a.dbglog"; printf 'g\n' >&3; log "dbg $a";;
    dump)  WID="$(X search --name 'FS-UAE' | head -1)"; X windowfocus --sync "$WID"; dbgon
           python3 -I "$HERE/dskchg_dump.py" "$OUT/in" "$OUT/fs-uae.log" "$OUT/log.txt" > "$OUT/dump.out" 2>&1
           printf 'g\n' >&3;;
  esac
done < "$SCRIPT"
echo "sortie : $OUT"
