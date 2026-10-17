#!/usr/bin/env bash
# tests/boot_test_interactive.sh — boot headless FS-UAE + INJECTION d'entrée série (CLI interactif, jalons E/F).
#
# Étend boot_test.sh : le pont PTY socat (ser_uae <-> ser_cap) est bidirectionnel. On attend le marqueur
# « prêt » (la ROM a émis son invite / est en attente d'entrée), puis on INJECTE une ligne dans ser_cap
# (-> socat -> ser_uae -> RX série FS-UAE -> SERDATR côté ROM), octet par octet avec cadence (évite l'overrun
# RX : Paula n'a qu'un octet de buffer). On assère ensuite la présence du marqueur de SUCCÈS (l'écho/résultat).
#
# Pourquoi un harnais séparé : boot_test.sh ne fait que CAPTURER. Les preuves READ/CLI exigent de FEEDER l'entrée.
# La RX série sous FS-UAE est prouvée (voir mémoire serial-rx-injection-harness).
#
# Usage : boot_test_interactive.sh <rom> <wait_s> <ready_marker> <inject_str> <success_marker> [adf] [per_char_ms]
#   inject_str : séquence à taper ; \r = CR (fin de ligne), \n = LF. Ex. 'hello\r'
# Codes de sortie : 0 = succès ; 1 = régression/absent ; 2 = prérequis manquant.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13.rom}"
WAIT="${2:-90}"
READY="${3:-E1 CON WRITE OK}"
INJECT="${4:-hello\r}"
MARKER="${5:-E1 CON READ=hello}"
ADF="${6:-}"
PCMS="${7:-50}"                      # ms entre octets injectés (anti-overrun)
FAILMARK="FAILED"
OUT="$ROOT/build/boot_itx"
mkdir -p "$OUT"
SERLOG="$OUT/serial.log"; : > "$SERLOG"

[ -f "$ROM" ] || { echo "ROM absente : $ROM"; exit 2; }
for t in fs-uae Xvfb xwd socat; do command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }; done

XPID=""; FPID=""; SERPID=""; CATPID=""
cleanup() {
  for p in "$FPID" "$CATPID" "$SERPID" "$XPID"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  sleep 0.3
  for p in "$FPID" "$CATPID" "$SERPID" "$XPID"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
}
trap cleanup EXIT INT TERM

socat pty,raw,echo=0,link="$OUT/ser_uae" pty,raw,echo=0,link="$OUT/ser_cap" >"$OUT/socat.log" 2>&1 &
SERPID=$!
for _ in $(seq 1 40); do [ -e "$OUT/ser_uae" ] && [ -e "$OUT/ser_cap" ] && break; sleep 0.1; done
cat "$OUT/ser_cap" >> "$SERLOG" 2>/dev/null &
CATPID=$!

DISP=""
for n in $(seq 99 120); do [ -e "/tmp/.X${n}-lock" ] && continue; DISP=":$n"; break; done
[ -n "$DISP" ] || { echo "aucun display X libre"; exit 2; }
Xvfb "$DISP" -screen 0 1024x768x24 >"$OUT/xvfb.log" 2>&1 &
XPID=$!
for _ in $(seq 1 50); do xwd -root -display "$DISP" -silent >/dev/null 2>&1 && break; sleep 0.2; done

FDCOUNT=0; FLOPPY0=""
if [ -n "$ADF" ]; then
  [ -f "$ADF" ] || { echo "ADF absent : $ADF"; exit 2; }
  FDCOUNT=1; FLOPPY0="floppy_drive_0 = $ADF"
fi
CFG="$OUT/itx.fs-uae"
cat > "$CFG" <<EOF
[fs-uae]
amiga_model = A500
kickstart_file = $ROM
chip_memory = 512
fast_memory = 0
floppy_drive_count = $FDCOUNT
$FLOPPY0
fullscreen = 0
window_width = 720
window_height = 568
fade_in_duration = 0
serial_port = $OUT/ser_uae
EOF

DISPLAY="$DISP" fs-uae "$CFG" >"$OUT/fs-uae.log" 2>&1 &
FPID=$!

# Attendre le marqueur « prêt »
ready=0
for _ in $(seq 1 $((WAIT*4))); do
  grep -qF "$READY" "$SERLOG" && { ready=1; break; }
  sleep 0.25
done
echo "prêt (« $READY » vu) = $ready"
sleep 1                              # settle : laisse le client pri basse atteindre son READ bloquant
                                     # (handler en boucle de poll stable) avant d'injecter le 1er octet

# INJECTION octet par octet, avec cadence (anti-overrun)
exec 7>"$OUT/ser_cap"
python3 - "$PCMS" >&7 <<PYEOF
import sys, time
s = "$INJECT".encode().decode('unicode_escape')
ms = int("$PCMS")
for ch in s:
    sys.stdout.write(ch); sys.stdout.flush()
    time.sleep(ms/1000.0)
PYEOF
exec 7>&-
sleep 2

echo "=== serial.log (fin) ==="
tr -cd '\11\12\15\40-\176\n' < "$SERLOG" | tail -8 | sed 's/^/  [ser] /'

if grep -qi "$FAILMARK" "$SERLOG"; then echo "ECHEC : « $FAILMARK » présent."; exit 1; fi
if grep -qF "$MARKER" "$SERLOG"; then echo "OK : marqueur « $MARKER » présent (round-trip READ injecté)."; exit 0; fi
echo "ECHEC : marqueur « $MARKER » absent."; exit 1
