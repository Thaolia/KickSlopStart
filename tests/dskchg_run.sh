#!/usr/bin/env bash
# tests/dskchg_run.sh — harnais de la sonde tests/dskchg.s (piste analyse, docs/analysis/disk-change-v34.md).
# Boot FS-UAE headless (Xvfb) avec débogueur console, DF0: = <df0>, et trois images dans la liste de disquettes
# (floppy_image_0..2) ; exécute un script de commandes, une par ligne :
#   sleep N                  attente (secondes, horloge murale)
#   shot NOM                 capture X complète -> <out>/NOM.png (écran Amiga en +152+100, 720x568)
#   media COURANT CIBLE [NOM] change la disquette de DF0: par le MENU F12 de FS-UAE (seule méthode qui a marché :
#                            les raccourcis keyboard_key_* = action_*_floppy_* sont ignorés quand on les injecte par
#                            xdotool). Positions du sous-menu « INSERT INTO DF0 » : 0 = EJECT, 1..3 = floppy_image_0..2 ;
#                            la surbrillance part de l'image COURANTE (0 si lecteur vide). Le premier appel descend de
#                            PAUSE à l'entrée DF0 (7 x Bas) ; ensuite le menu s'ouvre déjà sur cette entrée. Entrée sur
#                            l'image ferme le menu (pas de F12 en plus). L'émulation est en pause pendant le menu.
#   rel DX DY [N]            N déplacements relatifs de la souris (pas <= 20 : les grands sauts se perdent)
#   dclick                   double-clic gauche
#   dump                     F12+D, relit le journal mémoire de la sonde (adresse en $3F0) -> <out>/log.txt, puis « g »
# Usage : tests/dskchg_run.sh <rom> <df0.adf> <img1.adf> <img2.adf> <script> <répertoire de sortie>
# Les ADF doivent porter un NOM NEUF à chaque séance (FS-UAE attache une surcouche d'écriture au nom du fichier).
set -u
ROM="${1:?rom}"; F0="${2:?df0}"; F1="${3:?img1}"; F2="${4:?img2}"; SCRIPT="${5:?script}"; OUT="${6:?sortie}"
HERE="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$OUT"; mkdir -p "$OUT"
for t in fs-uae Xvfb xdotool xwd convert python3; do command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }; done
# un seul émulateur à la fois : attendre deux constats successifs d'absence
while pgrep -x fs-uae >/dev/null || { sleep 3; pgrep -x fs-uae >/dev/null; }; do sleep 2; done
DISP=""; for n in $(seq 99 120); do [ -e "/tmp/.X${n}-lock" ] || { DISP=":$n"; break; }; done
[ -n "$DISP" ] || { echo "aucun display X libre"; exit 2; }
Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 & XP=$!
FP=""
cleanup() { [ -n "$FP" ] && kill "$FP" 2>/dev/null; kill "$XP" 2>/dev/null; sleep 1
            [ -n "$FP" ] && kill -9 "$FP" 2>/dev/null; kill -9 "$XP" 2>/dev/null; exec 3>&- 2>/dev/null; }
trap cleanup EXIT INT TERM
sleep 2
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
serial_port = /dev/null
console_debugger = 1
EOC
rm -f "$OUT/in"; mkfifo "$OUT/in"; exec 3<>"$OUT/in"
DISPLAY="$DISP" fs-uae "$OUT/cfg.fs-uae" < "$OUT/in" > "$OUT/fs-uae.log" 2>&1 & FP=$!
T0=$(date +%s)
sleep 3
X() { DISPLAY="$DISP" xdotool "$@" 2>/dev/null; }
tp() { X keydown "$1"; sleep 0.15; X keyup "$1"; sleep 0.35; }
log() { echo "$(( $(date +%s) - T0 )) $*" >> "$OUT/events.log"; }
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
    dump)  X keydown F12 key d keyup F12; sleep 3
           python3 -I "$HERE/dskchg_dump.py" "$OUT/in" "$OUT/fs-uae.log" "$OUT/log.txt" > "$OUT/dump.out" 2>&1
           printf 'g\n' >&3;;
  esac
done < "$SCRIPT"
echo "sortie : $OUT"
