#!/usr/bin/env bash
# tests/wbfs_probe.sh - Workbench 1.3.3 floppy session on the ROM file system: the startup-sequence copies files to
# RAM: and to the floppy itself (prints "WBFS COPY OK" on the serial port), then LoadWB; the boot disk's window is
# opened by a double-click and captured (wbfs.png in the session directory, to look at). The floppy image the
# emulator wrote is then checked with tests/ofs_check.py (bitmap flag valid, bitmap = blocks in use).
# Usage: tests/wbfs_probe.sh <rom> <session name>
set -u
ROM="${1:?rom}"; NAME="${2:?session name}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/wbfs; mkdir -p "$OUT"
ADF="$OUT/wb_$NAME.adf"
cp assets/wb133.adf "$ADF"; chmod u+w "$ADF"
xdftool "$ADF" read s/startup-sequence "$OUT/ss" >/dev/null || exit 2
awk '/^LoadWB/ { print "copy c:List RAM:l1"; print "copy c:Dir sys:d1"; print "copy sys:d1 RAM:d2";
                 print "echo >SER: \"WBFS COPY OK\"" } { print }' "$OUT/ss" > "$OUT/ss.new"
xdftool "$ADF" delete s/startup-sequence + write "$OUT/ss.new" s/startup-sequence >/dev/null || exit 2
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" >/dev/null || exit 2
"$A" wait-serial "$NAME" "WBFS COPY OK" 200; rc=$?
sleep 20                                        # the disk icon comes 9-12 s after LoadWB
printf 'mouse:-900,-400\nwait:300\nmouse:591,97\nwait:300\ndclick\nwait:8000\n' | "$A" input "$NAME" - >/dev/null
"$A" shot "$NAME" wbfs.png --via ipc >/dev/null
"$A" stop "$NAME" >/dev/null
SES=build/amiberry/sessions/$NAME
echo "screenshot: $SES/wbfs.png"
[ $rc -eq 0 ] || { echo "no WBFS COPY OK"; exit 1; }
python3 -I tests/ofs_check.py "$SES/df0-wb_$NAME.adf"
