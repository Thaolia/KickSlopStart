#!/usr/bin/env bash
# tests/concmd_probe.sh - builds the console command probe disk (tests/concmd_probe.s: code at offset 12, the
# bootblock reloads the rest), boots it in an Amiberry session on our ROM and copies the "CC ..." serial lines to
# <out_dir>/concmd.txt, plus a screenshot.
#
# Usage: tests/concmd_probe.sh <out_dir> [rom=build/kick13-prod.rom]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fbin -m68000 -quiet -o "$OUT/probe.bin" "$ROOT/tests/concmd_probe.s" || exit 2
python3 -I - "$OUT/probe.bin" "$OUT/concmd.adf" <<'PY'
import struct, sys
code = open(sys.argv[1], 'rb').read()
assert len(code) <= 4096 - 12, len(code)
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
NAME="cc$$"
"$A" start --name "$NAME" --rom "$ROM" --adf "$OUT/concmd.adf" || exit 2
"$A" wait-serial "$NAME" "CC END" 90; RC=$?
"$A" shot "$NAME" "$OUT/concmd.png" --via ipc >/dev/null
tr -d '\r' < "$ROOT/build/amiberry/sessions/$NAME/serial.log" | grep '^CC ' > "$OUT/concmd.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/concmd.txt"
exit $RC
