#!/usr/bin/env bash
# tests/hdfs_probe.sh - the ROM file system on a hard-disk partition (UAE "uaehf" hardfile, no RDB: the driver
# leaves dn_SegList and dn_Handler at 0, so dos starts the ROM OFS handler on first use of DH0:).
# Makes a blank OFS hardfile with xdftool and a copy of the Workbench 1.3.3 disk whose startup-sequence works on
# DH0: (copy, makedir, rename, delete, list, dir, info; outputs to SER:), boots it on the given ROM,
# waits for "HDFS END", then checks the hardfile on the host: xdftool lists it and tests/ofs_check.py walks the tree
# and compares the bitmap (all bitmap blocks, extension blocks included) with what the files use.
# Runs under Amiberry (hardfile2, uaehf.device), or under FS-UAE with EMU=fsuae (tests/fsuae_run.sh, hard_drive_0).
# Usage: [FILL="A B"] tests/hdfs_probe.sh <rom> <session name> [size MiB, default 40] [timeout s, default 400]
set -u
ROM="${1:?rom}"; NAME="${2:?session name}"; MB="${3:-40}"; TMO="${4:-400}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/hdfs; mkdir -p "$OUT"
HDF="$PWD/$OUT/hd_$NAME.hdf"
rm -f "$HDF"
xdftool "$HDF" create size="${MB}"Mi + format Work ofs >/dev/null || { echo "xdftool create failed"; exit 2; }
if [ -n "${FILL:-}" ]; then                     # FILL="A B": blocks [A, B) marked used beforehand, so that the files go
  python3 -I tests/ofs_check.py "$HDF" --fill $FILL "$HDF.f" && mv "$HDF.f" "$HDF"   # to bitmap blocks found
fi                                              # through a bitmap extension block (64 MiB: FILL="65571 101700")
ADF="$OUT/wb_$NAME.adf"
cp assets/wb133.adf "$ADF"; chmod u+w "$ADF"
cat > "$OUT/startup" <<'EOF'
echo >SER: "HDFS START"
failat 30
info >SER:
copy c RAM:c all quiet
join c:Ed c:Edit c:List c:Dir as RAM:big
join RAM:big RAM:big RAM:big RAM:big as RAM:b4
makedir DH0:d1
copy RAM:c DH0:d1 all quiet
copy RAM:big DH0:big
copy c:List DH0:list
copy devs:system-configuration DH0:
rename DH0:list DH0:list2
copy DH0:list2 RAM:list3
copy DH0:big RAM:big2
makedir DH0:d2
rename DH0:system-configuration DH0:d2/sc
delete DH0:d1/Assign
copy RAM:b4 DH0:b1
copy RAM:b4 DH0:b2
copy RAM:b4 DH0:b3
copy RAM:b4 DH0:b4
copy RAM:b4 DH0:b5
copy RAM:b4 DH0:b6
copy RAM:b4 DH0:b7
copy RAM:b4 DH0:b8
copy RAM:b4 DH0:b9
copy RAM:b4 DH0:b10
copy RAM:b4 DH0:b11
delete DH0:b2
copy RAM:b4 DH0:d2/b4
list >SER: RAM:
dir >SER: DH0:
list >SER: DH0:d2
info >SER:
echo >SER: "HDFS END"
EOF
xdftool "$ADF" delete s/startup-sequence + write "$OUT/startup" s/startup-sequence >/dev/null || { echo "xdftool write failed"; exit 2; }
xdftool "$OUT/wb_$NAME.adf" read c/Ed "$OUT/ed" && xdftool "$OUT/wb_$NAME.adf" read c/Edit "$OUT/edit" \
  && xdftool "$OUT/wb_$NAME.adf" read c/List "$OUT/list" && xdftool "$OUT/wb_$NAME.adf" read c/Dir "$OUT/dir" \
  || { echo "xdftool read failed"; exit 2; }
if [ "${EMU:-amiberry}" = amiberry ]; then
  "$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --fast 2 -- \
    -s "hardfile2=rw,DH0:$HDF,32,1,2,512,-128,,uae0" >/dev/null || { echo "start failed"; exit 2; }
  "$A" wait-serial "$NAME" "HDFS END" "$TMO"; rc=$?
  sleep 6                                       # past the handler's write-back
  SES=build/amiberry/sessions/$NAME
  "$A" shot "$NAME" hdfs.png --via ipc >/dev/null
  "$A" stop "$NAME" >/dev/null
else
  SES=$OUT/fsuae_$NAME
  FSUAE_FAST=2048 FSUAE_EXTRA_CFG="hard_drive_0 = $HDF
hard_drive_0_priority = -128" tests/fsuae_run.sh "$ROM" "$SES" "$PWD/$ADF" "HDFS END" "$TMO"; rc=$?
fi
tr -d '\r' < "$SES/serial.log" | sed -n '/HDFS START/,/HDFS END/p'
[ $rc -eq 0 ] || { echo "no HDFS END"; exit 1; }
xdftool "$HDF" list | tail -3
cat "$OUT/ed" "$OUT/edit" "$OUT/list" "$OUT/dir" > "$OUT/big.ref"
xdftool "$HDF" read big "$OUT/big.out" && cmp "$OUT/big.ref" "$OUT/big.out" && echo "big: identical ($(stat -c %s "$OUT/big.out") bytes)"
xdftool "$HDF" read d2/sc "$OUT/sc.out" && echo "d2/sc: $(stat -c %s "$OUT/sc.out") bytes"
cat "$OUT/big.ref" "$OUT/big.ref" "$OUT/big.ref" "$OUT/big.ref" > "$OUT/b4.ref"
for f in b1 b11 d2/b4; do
  xdftool "$HDF" read "$f" "$OUT/b.out" && cmp -s "$OUT/b4.ref" "$OUT/b.out" && echo "$f: identical ($(stat -c %s "$OUT/b.out") bytes)" \
    || echo "$f: DIFFERS"
done
if [ -n "${FILL:-}" ]; then python3 -I tests/ofs_check.py "$HDF" --filled $FILL; else python3 -I tests/ofs_check.py "$HDF"; fi
