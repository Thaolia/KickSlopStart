#!/usr/bin/env bash
# tests/validate_probe.sh - bitmap validation at mount (rom-filesystem-v34 §2.3, dos-lvo-partial-v34 §1.4). The
# Workbench 1.3.3 disk boots in DF0: and its startup-sequence (output on SER:) works on a test disk in DF1:, made with
# xdftool (files, a directory, a file with an extension block) whose root block says "bitmap not valid":
#   valid    writable disk: rebuilt at mount, written back; the image must then have its flag valid and exactly the
#            bitmap xdftool wrote (tests/ofs_check.py --dump-bitmap before / after); MakeDir works afterwards.
#   wprot    the same disk read-only: validated in memory, Info "Read Only" with used blocks, Protect fails (214, no
#            requester), MakeDir -> "Volume Test is write protected" (screenshot mkdir.png, Cancel), image unchanged.
#   corrupt  (inserted in DF1: during a 10 s Wait, so that the requesters are in front of the CLI window; the image is
#            used in place, it must come back unchanged) a hash chain pointing outside the disk: requesters "Error validating disk" / "Key 5000 out of range",
#            then "Disk structure corrupt" (screenshots req1.png, req2.png, Cancel clicked on each), then Protect
#            fails (213), MakeDir -> "is not validated" (mkdir.png, Cancel), Info shows no used / free figures.
# Usage: tests/validate_probe.sh <rom> <case: valid|wprot|corrupt> <session name>
set -u
ROM="${1:?rom}"; CASE="${2:?case}"; NAME="${3:?session name}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/validate/$NAME; rm -rf "$OUT"; mkdir -p "$OUT"
T="$OUT/test.adf"
xdftool assets/wb133.adf read c/Ed "$OUT/ed" + read c/Edit "$OUT/edit" + read c/List "$OUT/list" >/dev/null || exit 2
cat "$OUT/ed" "$OUT/edit" > "$OUT/big"
xdftool "$T" create + format Test ofs + write "$OUT/list" list + makedir d + write "$OUT/ed" d/ed \
  + write "$OUT/big" big >/dev/null || exit 2
python3 -I tests/ofs_check.py "$T" --dump-bitmap "$OUT/bits.before" || exit 2
if [ "$CASE" = corrupt ]; then                  # the header of "list" gets a hash chain to block 5000
  python3 -I - "$T" <<'EOF' || exit 2
import struct, sys
p = sys.argv[1]; d = bytearray(open(p, 'rb').read())
root = struct.unpack_from('>128l', d, 880 * 512)
for k in root[6:78]:
    if k:
        h = bytearray(d[k * 512:(k + 1) * 512])
        if bytes(h[433:437]) == b'list':
            struct.pack_into('>l', h, 496, 5000)
            struct.pack_into('>l', h, 20, 0)
            struct.pack_into('>L', h, 20, (-sum(struct.unpack('>128L', bytes(h)))) & 0xFFFFFFFF)
            d[k * 512:(k + 1) * 512] = h
            break
open(p, 'wb').write(d)
EOF
fi
python3 -I tests/ofs_check.py "$T" --clear-flag "$T.nv" && mv "$T.nv" "$T" || exit 2
cp "$T" "$OUT/test.orig"
ADF="$OUT/wb.adf"
cp assets/wb133.adf "$ADF"; chmod u+w "$ADF"
cat > "$OUT/startup" <<'EOF'
echo >SER: "VAL START"
wait 10
failat 30
info >SER:
protect df1:list r
makedir df1:newdir
list >SER: df1:
info >SER:
echo >SER: "VAL END"
EOF
xdftool "$ADF" delete s/startup-sequence + write "$OUT/startup" s/startup-sequence >/dev/null || exit 2
DF1=(--adf "$T")
if [ "$CASE" = corrupt ]; then                  # inserted once the CLI window is open: its requesters show in front
  xdftool "$OUT/blank.adf" create + format Blank ofs >/dev/null || exit 2
  DF1=(--adf "$OUT/blank.adf")
fi
if [ "$CASE" = wprot ]; then chmod a-w "$T"; DF1=(-- -s "floppy1=$PWD/$T"); fi
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" "${DF1[@]}" >/dev/null || exit 2
SES=build/amiberry/sessions/$NAME
if [ "$CASE" = corrupt ]; then
  "$A" wait-serial "$NAME" "VAL START" 200 >/dev/null
  "$A" ipc "$NAME" INSERTFLOPPY "$PWD/$T" 1 >/dev/null
  sleep 15                                      # the requester takes a few seconds to draw
  "$A" shot "$NAME" req1.png --via ipc >/dev/null
  printf 'mouse:-900,-400\nwait:300\nmouse:257,113\nwait:300\nclick\nwait:10000\n' | "$A" input "$NAME" - >/dev/null
  "$A" shot "$NAME" req2.png --via ipc >/dev/null
  printf 'click\nwait:2000\n' | "$A" input "$NAME" - >/dev/null
  echo "requesters: $SES/req1.png $SES/req2.png"
fi
if [ "$CASE" != valid ]; then                    # MakeDir -> "is write protected" / "is not validated": Cancel
  "$A" wait-serial "$NAME" "Protect failed" 200 >/dev/null
  sleep 10
  "$A" shot "$NAME" mkdir.png --via ipc >/dev/null
  printf 'mouse:-900,-400\nwait:300\nmouse:257,113\nwait:300\nclick\nwait:2000\n' | "$A" input "$NAME" - >/dev/null
  echo "requester: $SES/mkdir.png"
fi
"$A" wait-serial "$NAME" "VAL END" 200; rc=$?
sleep 6
[ "$CASE" = corrupt ] && "$A" shot "$NAME" end.png --via ipc >/dev/null
"$A" stop "$NAME" >/dev/null
tr -d '\r' < "$SES/serial.log" | sed -n '/VAL START/,/VAL END/p'
[ $rc -eq 0 ] || { echo "no VAL END"; exit 1; }
IMG="$T"
[ "$CASE" = valid ] && IMG="$SES/df1-test.adf"
case "$CASE" in
  valid)
    python3 -I tests/ofs_check.py "$IMG"
    cp "$IMG" "$OUT/after.adf"; chmod u+w "$OUT/after.adf"
    xdftool "$OUT/after.adf" delete newdir >/dev/null   # back to the files of the original disk
    python3 -I tests/ofs_check.py "$OUT/after.adf" --dump-bitmap "$OUT/bits.after"
    cmp "$OUT/bits.before" "$OUT/bits.after" && echo "rebuilt bitmap = bitmap written by xdftool"
    ;;
  wprot)
    cmp "$OUT/test.orig" "$IMG" && echo "read-only image unchanged" ;;
  corrupt)
    cmp "$OUT/test.orig" "$IMG" && echo "corrupt image unchanged" ;;
esac
