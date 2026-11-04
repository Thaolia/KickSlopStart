#!/usr/bin/env bash
# tests/defprefs_probe.sh - builds the GetDefPrefs probe disk (tests/defprefs_probe.s as a bootblock), boots it
# in an Amiberry session and copies the "DP ..." serial lines to <out_dir>/defprefs.txt.
#
# Usage: tests/defprefs_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# The Commodore ROM is refused by amiberry-session unless DP_ANALYSIS=1 (analysis agent only, see CLAUDE.md).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fbin -m68000 -quiet -o "$OUT/boot.bin" "$ROOT/tests/defprefs_probe.s" || exit 2
python3 -I - "$OUT/boot.bin" "$OUT/defprefs.adf" <<'EOF'
import struct, sys
code = open(sys.argv[1], 'rb').read()
assert len(code) <= 1012, len(code)
bb = bytearray(1024)
bb[0:4] = b'DOS\0'
struct.pack_into('>I', bb, 8, 880)
bb[12:12 + len(code)] = code
s = 0
for i in range(0, 1024, 4):
    s += struct.unpack('>I', bb[i:i + 4])[0]
    if s > 0xFFFFFFFF:
        s = (s & 0xFFFFFFFF) + 1
struct.pack_into('>I', bb, 4, (~s) & 0xFFFFFFFF)
img = bytearray(901120)
img[0:1024] = bb
open(sys.argv[2], 'wb').write(bytes(img))
EOF
NAME="dp$$"
EXTRA=(); [ "${DP_ANALYSIS:-0}" = 1 ] && EXTRA=(--analysis)
"$A" start --name "$NAME" --rom "$ROM" --adf "$OUT/defprefs.adf" "${EXTRA[@]}" || exit 2
"$A" wait-serial "$NAME" "DP END" 90; RC=$?
DIR="$ROOT/build/amiberry/sessions/$NAME"; [ "${DP_ANALYSIS:-0}" = 1 ] && DIR="$ROOT/build/amiberry/analysis/$NAME"
tr -d '\r' < "$DIR/serial.log" | grep '^DP ' > "$OUT/defprefs.txt"
"$A" stop "$NAME"
wc -l "$OUT/defprefs.txt"
exit $RC
