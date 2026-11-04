#!/usr/bin/env bash
# tests/reqg_probe.sh - builds the requester gadget probe disk (tests/reqg_probe.s: code at offset 12, the
# bootblock reloads the rest), boots it in an Amiberry session on our ROM and copies the "GQ/GS ..." serial lines to
# <out_dir>/reqg.txt, plus a screenshot.
#
# Usage: tests/reqg_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# The Commodore ROM is refused by amiberry-session unless GQ_ANALYSIS=1 (analysis agent only, see CLAUDE.md).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fbin -m68000 -quiet -o "$OUT/probe.bin" "$ROOT/tests/reqg_probe.s" || exit 2
python3 -I - "$OUT/probe.bin" "$OUT/reqg.adf" <<'PY'
import struct, sys
code = open(sys.argv[1], 'rb').read()
assert len(code) <= 8192 - 12, len(code)
img = bytearray(901120)
img[0:4] = b'DOS\0'
struct.pack_into('>I', img, 8, 880)
img[12:12 + len(code)] = code
s = 0
for i in range(0, 1024, 4):
    s += struct.unpack('>I', img[i:i + 4])[0]
    if s > 0xFFFFFFFF:
        s = (s & 0xFFFFFFFF) + 1
struct.pack_into('>I', img, 4, (~s) & 0xFFFFFFFF)
open(sys.argv[2], 'wb').write(bytes(img))
PY
NAME="gq$$"
EXTRA=(); DIR="$ROOT/build/amiberry/sessions/$NAME"
[ "${GQ_ANALYSIS:-0}" = 1 ] && { EXTRA=(--analysis); DIR="$ROOT/build/amiberry/analysis/$NAME"; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$OUT/reqg.adf" "${EXTRA[@]}" || exit 2
"$A" wait-serial "$NAME" "GQ END" 90; RC=$?
"$A" shot "$NAME" "$OUT/reqg.png" --via ipc >/dev/null
tr -d '\r' < "$DIR/serial.log" | grep -E '^G[QS] ' > "$OUT/reqg.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/reqg.txt"
exit $RC
