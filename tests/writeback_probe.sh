#!/usr/bin/env bash
# tests/writeback_probe.sh - copy time and image consistency of the ROM file system's writes (rom-filesystem-v34
# §8.4). Workbench 1.3.3 in DF0:, a blank OFS floppy in DF1:, a blank 10 MiB OFS hardfile as DH0: (Amiberry). The
# startup-sequence copies C: to RAM:, then RAM:c to DF1: and to DH0: between serial markers; the host records when
# each marker arrives (copy times), snapshots the hardfile during its copy (root flag 0: modified, bitmap
# not written back yet), waits past the write-back, stops the emulator and checks both images with
# tests/ofs_check.py (bitmap flag valid, bitmap = blocks in use) and the copied files against the originals.
# Usage: tests/writeback_probe.sh <rom> <session name>
set -u
ROM="${1:?rom}"; NAME="${2:?session name}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/writeback/$NAME; rm -rf "$OUT"; mkdir -p "$OUT"
HDF="$PWD/$OUT/hd.hdf"
xdftool "$HDF" create size=10Mi + format Work ofs >/dev/null || exit 2
xdftool "$OUT/df1.adf" create + format Blank ofs >/dev/null || exit 2
ADF="$OUT/wb.adf"
cp assets/wb133.adf "$ADF"; chmod u+w "$ADF"
cat > "$OUT/startup" <<'EOF'
copy c RAM:c all quiet
echo >SER: "T1 START"
copy RAM:c DF1:c all quiet
echo >SER: "T1 END"
echo >SER: "T2 START"
copy RAM:c DH0:c all quiet
echo >SER: "T2 END"
wait 8
echo >SER: "WB END"
EOF
xdftool "$ADF" delete s/startup-sequence + write "$OUT/startup" s/startup-sequence >/dev/null || exit 2
"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --adf "$OUT/df1.adf" --fast 2 -- \
  -s "hardfile2=rw,DH0:$HDF,32,1,2,512,-128,,uae0" >/dev/null || exit 2
SES=build/amiberry/sessions/$NAME
declare -A T
for m in "T1 START" "T1 END" "T2 START" "T2 END" "WB END"; do
  "$A" wait-serial "$NAME" "$m" 600 >/dev/null || { echo "no $m"; "$A" stop "$NAME" >/dev/null; exit 1; }
  T[$m]=$(date +%s.%N)
  if [ "$m" = "T2 START" ]; then sleep 6; cp "$HDF" "$OUT/hd_during_copy.hdf"; fi   # modified, not written back: flag 0
done
sleep 4
"$A" stop "$NAME" >/dev/null
printf 'copy to DF1: %.1f s\ncopy to DH0: %.1f s\n' "$(echo "${T[T1 END]} - ${T[T1 START]}" | bc)" \
  "$(echo "${T[T2 END]} - ${T[T2 START]}" | bc)"
python3 -I - "$OUT/hd_during_copy.hdf" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
print('DH0 root bitmap flag during the copy: %d' % struct.unpack_from('>l', d, 10240 * 512 + 312)[0])
PY
rc=0
for img in "$SES/df1-df1.adf" "$HDF"; do
  python3 -I tests/ofs_check.py "$img" || rc=1
  n=0; bad=0
  for f in $(xdftool assets/wb133.adf list c 2>/dev/null | awk 'NR>1 && $2 ~ /^[0-9]+$/ {print $1}'); do
    xdftool assets/wb133.adf read "c/$f" "$OUT/a" >/dev/null && xdftool "$img" read "c/$f" "$OUT/b" >/dev/null \
      && cmp -s "$OUT/a" "$OUT/b" && n=$((n + 1)) || bad=$((bad + 1))
  done
  echo "$(basename "$img"): $n files identical, $bad different"
  [ $bad -eq 0 ] || rc=1
done
exit $rc
