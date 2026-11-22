#!/usr/bin/env bash
# tests/ide_rdb_probe.sh - RDB partitions on the A600/A1200 IDE disk, read and write, in the ROM filesystem.
# Builds a hard disk with amitools (independent of our code): rdbtool makes an RDB with four 10 MB partitions,
# DH0: OFS (DOS\0, flagged bootable, with a startup-sequence that must NOT run), DH1: FFS (DOS\1), DH2: FFS
# international (DOS\3), DH3: OFS international (DOS\2); xdftool formats and fills each one (nested directories,
# 80 files in one directory for hash chains, an accented name on the international ones). Boots a copy of the
# Workbench 1.3.3 disk whose startup-sequence, on every partition, lists, types, copies files to a blank OFS floppy
# in DF1:, then writes: makedir, a 150 KB copy from DF1:, rename, delete (one in the middle of a hash chain),
# copy all; every command that warns prints "FAIL: <command>" to SER:. It ends with LoadWB for a screenshot.
# On the host: the copies on DF1: and the files written on each partition are compared with their sources, the
# RDB cylinder must be unchanged, each partition must pass tests/ofs_check.py (headers, extension blocks, bitmap;
# also valid for FFS) and amitools' xdfscan.
# Profiles: a600   ECS, 68000, IDE on the Gayle port
#           a1200  AGA, 68020, 2 MB chip RAM
# Usage: tests/ide_rdb_probe.sh <rom> <session name> [a600|a1200, default a600] [timeout s, default 600]
set -u
ROM="${1:?rom}"; NAME="${2:?session name}"; PROF="${3:-a600}"; TMO="${4:-600}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/idehd/$NAME; rm -rf "$OUT"; mkdir -p "$OUT/src" "$OUT/out"
IMG="$PWD/$OUT/disk.hdf"
S="$OUT/src"
export LC_ALL=C.UTF-8
PARTS="DH0:ofs DH1:ffs DH2:ffs+intl DH3:ofs+intl"
CYL0=$((16 * 63 * 512))                         # heads x sectors x 512: the RDB area

case "$PROF" in
  a600)  EXTRA=(-s chipset=ecs_agnus -s chipset_compatible=A600); MEM=() ;;
  a1200) EXTRA=(-s cpu_model=68020 -s chipset=aga -s chipset_compatible=A1200); MEM=(--chip 2048) ;;
  *) echo "profile: a600 or a1200"; exit 2 ;;
esac
EXTRA+=(-s ide=a600/a1200 -s "hardfile2=rw,DH0:$IMG,0,0,0,512,0,,ide0_mainboard")

rdbtool "$IMG" create chs=100,16,63 + init \
  + add size=20 name=DH0 dostype=ofs bootable=1 pri=5 \
  + add size=20 name=DH1 dostype=ffs \
  + add size=20 name=DH2 dostype=ffs+intl \
  + add size=20 name=DH3 dostype=ofs+intl >/dev/null || { echo "rdbtool failed"; exit 2; }

printf 'echo >SER: "BOOTED FROM DH0 PARTITION"\n' > "$S/startup-sequence"
head -c 20000 /dev/urandom > "$S/data.bin"
head -c 5000 /dev/urandom > "$S/todelete.bin"
head -c 153600 /dev/urandom > "$S/src150.bin"
printf 'accented name file\n' > "$S/accent.txt"
k=0
for P in $PARTS; do
  V=${P%%:*}; T=${P#*:}
  head -c 60000 /dev/urandom > "$S/big$k.bin"
  printf 'readme of %s (%s)\nsecond line\n' "$V" "$T" > "$S/readme$k.txt"
  printf 'deep note on %s\n' "$V" > "$S/note$k.txt"
  cmd=(xdftool "$IMG" open part=$V + format "Vol$k" "$T" + makedir sub + makedir sub/deep + makedir many
       + write "$S/readme$k.txt" readme.txt + write "$S/big$k.bin" big.bin + write "$S/data.bin" sub/deep/data.bin
       + write "$S/note$k.txt" sub/deep/note.txt + write "$S/todelete.bin" todelete.bin)
  for n in $(seq 1 80); do cmd+=(+ write "$S/note$k.txt" "many/f$n.txt"); done
  [ $k -eq 0 ] && cmd+=(+ makedir s + write "$S/startup-sequence" s/startup-sequence)
  [ $k -ge 2 ] && cmd+=(+ write "$S/accent.txt" "Été.txt")
  "${cmd[@]}" >/dev/null || { echo "xdftool fill $V failed"; exit 2; }
  k=$((k + 1))
done
RDB_MD5=$(head -c $CYL0 "$IMG" | md5sum)

ADF="$OUT/wb_$NAME.adf"; DF1="$OUT/df1_$NAME.adf"
cp assets/wb133.adf "$ADF"; chmod u+w "$ADF"
xdftool "$ADF" read c/List "$S/List" >/dev/null || { echo "xdftool read c/List failed"; exit 2; }
xdftool "$DF1" create + format Copies ofs + write "$S/src150.bin" src150.bin >/dev/null \
  || { echo "xdftool create failed"; exit 2; }
run() { printf '%s\nif warn\necho >SER: "FAIL: %s"\nendif\n' "$1" "$1"; }
{
  echo 'echo >SER: "IDERDB START"'
  echo 'failat 30'
  run 'info >SER:'
  run 'assign >SER:'
  k=0
  for P in $PARTS; do
    V=${P%%:*}:
    echo "echo >SER: \"== $V\""
    run "list >SER: $V"
    run "dir >SER: $V opt a"
    run "type >SER: ${V}readme.txt"
    run "type >SER: ${V}SUB/Deep/NOTE.TXT"
    run "list >SER: ${V}many/f77.txt"
    [ $k -ge 2 ] && run "type >SER: ${V}été.txt"
    run "copy >SER: ${V}big.bin DF1:big$k.bin"
    run "copy >SER: ${V}sub/deep/data.bin DF1:data$k.bin"
    run "makedir >SER: ${V}newdir"
    run "copy >SER: DF1:src150.bin ${V}newdir/w150.bin"
    run "copy >SER: c:List ${V}list"
    run "rename >SER: ${V}list ${V}newdir/list2"
    run "rename >SER: ${V}readme.txt ${V}readme2.txt"
    run "delete >SER: ${V}todelete.bin"
    run "delete >SER: ${V}many/f40.txt"
    run "copy >SER: ${V}sub ${V}subcopy all quiet"
    run "list >SER: ${V}newdir"
    run "dir >SER: $V"
    k=$((k + 1))
  done
  run 'list >SER: DF1:'
  run 'info >SER:'
  echo 'echo >SER: "IDERDB END"'
  echo 'loadwb'
  echo 'endcli >NIL:'
} | iconv -f UTF-8 -t LATIN1 > "$OUT/startup"
xdftool "$ADF" delete s/startup-sequence + write "$OUT/startup" s/startup-sequence >/dev/null \
  || { echo "xdftool write failed"; exit 2; }

"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --adf "$DF1" "${MEM[@]}" --fast 2 -- "${EXTRA[@]}" >/dev/null \
  || { echo "start failed"; exit 2; }
"$A" wait-serial "$NAME" "IDERDB END" "$TMO"; rc=$?
SES=build/amiberry/sessions/$NAME
sleep 40                                        # LoadWB draws the desktop and the four volume icons
"$A" shot "$NAME" end.png --via ipc >/dev/null
"$A" stop "$NAME" >/dev/null
tr -d '\r' < "$SES/serial.log" | iconv -f LATIN1 -t UTF-8 > "$OUT/serial.txt"
sed -n '/IDERDB START/,/IDERDB END/p' "$OUT/serial.txt"
[ $rc -eq 0 ] || { echo "no IDERDB END"; exit 1; }
fail=0
if grep -n "FAIL:" "$OUT/serial.txt"; then fail=1; fi
if grep -q "BOOTED FROM DH0" "$OUT/serial.txt"; then echo "DH0 startup-sequence ran (partitions must not boot)"; fail=1; fi
if [ "$(head -c $CYL0 "$IMG" | md5sum)" = "$RDB_MD5" ]; then echo "RDB cylinder unchanged"; else echo "RDB CHANGED"; fail=1; fi
SDF1="$SES/df1-$(basename "$DF1")"             # amiberry-session copies DFn as dfn-<name>
cmpf() {                                        # $1 source, $2 image, $3 path in it (after "open part=..." or not)
  local got="$OUT/out/cmp"; rm -f "$got"
  if xdftool "$2" $3 "$got" >/dev/null 2>&1 && cmp -s "$1" "$got"; then echo "  ${3##* }: identical ($(stat -c %s "$got") bytes)"
  else echo "  ${3##* }: DIFFERS or missing"; fail=1; fi
}
k=0
for P in $PARTS; do
  V=${P%%:*}
  echo "== $V (${P#*:})"
  cmpf "$S/big$k.bin"    "$SDF1" "read big$k.bin"
  cmpf "$S/data.bin"     "$SDF1" "read data$k.bin"
  cmpf "$S/src150.bin"   "$IMG"  "open part=$V + read newdir/w150.bin"
  cmpf "$S/List"         "$IMG"  "open part=$V + read newdir/list2"
  cmpf "$S/readme$k.txt" "$IMG"  "open part=$V + read readme2.txt"
  cmpf "$S/data.bin"     "$IMG"  "open part=$V + read subcopy/deep/data.bin"
  cmpf "$S/note$k.txt"   "$IMG"  "open part=$V + read subcopy/deep/note.txt"
  cmpf "$S/big$k.bin"    "$IMG"  "open part=$V + read big.bin"
  for gone in todelete.bin readme.txt list many/f40.txt; do
    if xdftool "$IMG" open part=$V + read $gone "$OUT/out/gone" >/dev/null 2>&1; then echo "  $gone still present"; fail=1; fi
  done
  n=$(xdftool "$IMG" open part=$V + list many | grep -c 'f[0-9]*\.txt')
  if [ "$n" -eq 79 ]; then echo "  many/: 79 entries"; else echo "  many/: $n entries, 79 expected"; fail=1; fi
  rdbtool -r "$IMG" export $V "$OUT/p$k.hdf" >/dev/null || { echo "  rdbtool export failed"; fail=1; }
  python3 -I tests/ofs_check.py "$OUT/p$k.hdf" | sed 's/^/  /' | tail -4
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
  scan=$(xdfscan -l 1 "$OUT/p$k.hdf" 2>&1)
  if echo "$scan" | grep -qw ok; then echo "  xdfscan: ok"; else echo "  xdfscan: $scan" | head -8; fail=1; fi
  k=$((k + 1))
done
echo "screenshot: $SES/end.png"
exit $fail
