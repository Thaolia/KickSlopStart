#!/usr/bin/env bash
# tests/strg_probe.sh - builds tests/strg_probe.s (CLI executable), writes it with a startup-sequence that runs it on a
# bootable OFS disk, boots the disk in an Amiberry session, types the keys of each test after its "ST WAIT <n>" line,
# and copies the "ST ..." serial lines to <out_dir>/strg.txt, plus a screenshot (and box.png: the GADGHBOX cursor
# of test 10).
#
# Usage: tests/strg_probe.sh <out_dir> [rom=build/kick13-prod.rom]
# The Commodore ROM is refused by amiberry-session unless ST_ANALYSIS=1 (analysis agent only, see CLAUDE.md).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?out_dir}"; ROM="${2:-$ROOT/build/kick13-prod.rom}"
A="$ROOT/.claude/skills/amiberry/scripts/amiberry-session"
mkdir -p "$OUT"
vasmm68k_mot -Fhunkexe -kick1hunks -quiet -o "$OUT/strg_probe" "$ROOT/tests/strg_probe.s" || exit 2
printf 'df0:strg_probe\n' > "$OUT/startup"
ADF="$OUT/strg.adf"; rm -f "$ADF"
xdftool "$ADF" create + format Probe ofs + boot install + makedir s + write "$OUT/startup" s/startup-sequence \
  + write "$OUT/strg_probe" strg_probe >/dev/null || { echo "xdftool failed"; exit 2; }
NAME="st$$"
EXTRA=(); DIR="$ROOT/build/amiberry/sessions/$NAME"
[ "${ST_ANALYSIS:-0}" = 1 ] && { EXTRA=(--analysis); DIR="$ROOT/build/amiberry/analysis/$NAME"; }
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" "${EXTRA[@]}" || exit 2
keys() {   # keys <n> <input script>
  "$A" wait-serial "$NAME" "ST WAIT 0$1" 120 >/dev/null || { echo "no ST WAIT $1"; return 1; }
  printf '%s\n' "wait:500" "$2" | tr ';' '\n' | "$A" input "$NAME" - >/dev/null
}
RC=0
keys 1 'text:abc;wait:300;key:44' &&
keys 2 'text:5-x9;wait:300;key:44' &&
keys 3 'down:60;key:4f;up:60;wait:200;text:Z;wait:200;key:4e;wait:200;key:46;wait:200;down:60;key:4e;up:60;wait:200;key:41;wait:200;key:43' &&
keys 4 'down:67;key:32;up:67;wait:200;text:Q;wait:300;key:44' &&
keys 5 'text:zz;wait:200;down:67;key:10;up:67;wait:300;key:44' &&
keys 6 'text:123;wait:300;key:44' &&
keys 7 'text:abcdefgh;wait:300;key:44' &&
{ "$A" wait-serial "$NAME" "ST WAIT 0A" 120 >/dev/null && sleep 2 && "$A" shot "$NAME" box.png --via ipc >/dev/null &&
  cp "$DIR/box.png" "$OUT/box.png"; } &&
keys A 'key:44' || RC=1
"$A" wait-serial "$NAME" "ST END" 60 >/dev/null || RC=1
"$A" shot "$NAME" "$OUT/strg.png" --via ipc >/dev/null
tr -d '\r' < "$DIR/serial.log" | grep '^ST ' > "$OUT/strg.txt"
"$A" stop "$NAME" >/dev/null
cat "$OUT/strg.txt"
exit $RC
