#!/usr/bin/env bash
# tests/boot_test_interactive.sh - headless FS-UAE boot + serial input INJECTION (interactive CLI, milestones E/F).
#
# Extends boot_test.sh: the socat PTY bridge (ser_uae <-> ser_cap) is bidirectional. We wait for the "ready"
# marker (the ROM has emitted its prompt / is waiting for input), then INJECT a line into ser_cap
# (-> socat -> ser_uae -> FS-UAE serial RX -> SERDATR on the ROM side), byte by byte with pacing (avoids RX
# overrun: Paula has only a one-byte buffer). We then assert the presence of the SUCCESS marker (the echo/result).
#
# Why a separate harness: boot_test.sh only CAPTURES. The READ/CLI proofs require FEEDING the input.
# Serial RX under FS-UAE is proven (see memory serial-rx-injection-harness).
#
# Usage: boot_test_interactive.sh <rom> <wait_s> <ready_marker> <inject_str> <success_marker> [adf] [per_char_ms]
#   inject_str: sequence to type; \r = CR (end of line), \n = LF. E.g. 'hello\r'
# Exit codes: 0 = success; 1 = regression/missing; 2 = missing prerequisite.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:-$ROOT/build/kick13.rom}"
WAIT="${2:-90}"
READY="${3:-E1 CON WRITE OK}"
INJECT="${4:-hello\r}"
MARKER="${5:-E1 CON READ=hello}"
ADF="${6:-}"
PCMS="${7:-50}"                      # ms between injected bytes (anti-overrun)
SETTLE="${8:-1}"                     # s to wait after the "ready" marker (lets the boot go quiet)
POSTWAIT="${9:-3}"                    # s to wait AFTER the injection (lets the command load/run)
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

# Wait for the "ready" marker
ready=0
for _ in $(seq 1 $((WAIT*4))); do
  grep -qF "$READY" "$SERLOG" && { ready=1; break; }
  sleep 0.25
done
echo "prêt (« $READY » vu) = $ready"
sleep "$SETTLE"                      # settle: lets the boot markers go quiet + the low-pri client
                                     # reach its blocking READ (handler in stable poll) before injecting

# INJECTION byte by byte, with pacing (anti-overrun)
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
sleep "$POSTWAIT"                    # lets the injected command load/run (disk load = slow)

echo "=== serial.log (fin) ==="
tr -cd '\11\12\15\40-\176\n' < "$SERLOG" | tail -8 | sed 's/^/  [ser] /'

if grep -qi "$FAILMARK" "$SERLOG"; then echo "ECHEC : « $FAILMARK » présent."; exit 1; fi
if grep -qF "$MARKER" "$SERLOG"; then echo "OK : marqueur « $MARKER » présent (round-trip READ injecté)."; exit 0; fi
echo "ECHEC : marqueur « $MARKER » absent."; exit 1
