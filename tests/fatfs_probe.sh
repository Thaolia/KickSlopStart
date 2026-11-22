#!/usr/bin/env bash
# tests/fatfs_probe.sh - FAT volumes, read-only, in the ROM filesystem.
# Builds a FAT image with dosfstools + mtools (independent of our code): long names (<= and > 30 characters), an
# accented name, mixed case, nested directories, a directory spanning several clusters, a fragmented file, an empty
# file, a volume label. Boots a copy of the Workbench 1.3.3 disk whose startup-sequence lists and reads the volume
# (outputs to SER:), copies three files per volume to a blank OFS floppy in DF1:, then, after its end marker, tries
# to create a directory on the first volume: the screenshot must show the "is write protected" requester. On the
# host: the copies are compared with the sources (xdftool), the FAT image must be unchanged (md5) and clean
# (fsck.fat -n).
# Modes: uae   FAT32 64 MiB hardfile on uaehf.device (A500), volume DH0:
#        ide   A600 IDE disk, MBR: FAT32 64 MiB, FAT16 24 MiB and FAT12 4 MiB partitions, volumes FAT0:-FAT2:
#        super A600 IDE disk without partition table (FAT16 32 MiB at block 0), volume FAT0:
# Usage: tests/fatfs_probe.sh <rom> <session name> [uae|ide|super, default uae] [timeout s, default 400]
set -u
ROM="${1:?rom}"; NAME="${2:?session name}"; MODE="${3:-uae}"; TMO="${4:-400}"
A=.claude/skills/amiberry/scripts/amiberry-session
OUT=build/fatfs/$NAME; rm -rf "$OUT"; mkdir -p "$OUT/src"
IMG="$PWD/$OUT/disk.img"
S="$OUT/src"
export MTOOLS_SKIP_CHECK=1 LC_ALL=C.UTF-8

printf 'hello from the PC side\r\nsecond line\r\n' > "$S/readme.txt"
head -c 80000 /dev/urandom > "$S/big.bin"
head -c 70000 /dev/urandom > "$S/frag.bin"
head -c 9000 /dev/urandom > "$S/a.bin"; head -c 9000 /dev/urandom > "$S/b.bin"; head -c 9000 /dev/urandom > "$S/c.bin"
: > "$S/empty.txt"
printf 'texte accentue\r\n' > "$S/ete.txt"

fill() {                                        # $1 = mtools image spec
  local i="$1" n
  mmd -i "$i" ::/sub ::/sub/deep ::/many || return 1
  mcopy -i "$i" "$S/readme.txt" ::/readme.txt && mcopy -i "$i" "$S/empty.txt" ::/empty.txt &&
  mcopy -i "$i" "$S/ete.txt" "::/Été 2026.txt" && mcopy -i "$i" "$S/readme.txt" "::/Mixed Case Name.TXT" &&
  mcopy -i "$i" "$S/big.bin" "::/A long file name with spaces.bin" || return 1
  mcopy -i "$i" "$S/a.bin" ::/a.bin && mcopy -i "$i" "$S/b.bin" ::/b.bin && mcopy -i "$i" "$S/c.bin" ::/c.bin &&
  mdel -i "$i" ::/b.bin &&                      # frag.bin fills b.bin's hole, then goes on after c.bin
  mcopy -i "$i" "$S/frag.bin" ::/sub/deep/frag.bin && mcopy -i "$i" "$S/big.bin" ::/big.bin || return 1
  for n in $(seq 1 40); do mcopy -i "$i" "$S/readme.txt" "::/many/file number $n.txt" || return 1; done
}

case "$MODE" in
  uae)
    mkfs.fat -C -F 32 -s 1 -n KSSFAT32 "$IMG" 65536 >/dev/null || { echo "mkfs failed"; exit 2; }
    fill "$IMG" || { echo "mtools failed"; exit 2; }
    VOLS="DH0:"
    EXTRA=(-s "hardfile2=rw,DH0:$IMG,32,1,2,512,-128,,uae0") ;;
  ide)
    truncate -s 96M "$IMG"
    PARTS="2048:131072 133120:49152 182272:8192"
    printf 'label: dos\nstart=2048, size=131072, type=c\nstart=133120, size=49152, type=6\nstart=182272, size=8192, type=1\n' \
      | sfdisk -q "$IMG" || { echo "sfdisk failed"; exit 2; }
    mkfs.fat -F 32 -s 1 -n KSSFAT32 --offset 2048 "$IMG" 65536 >/dev/null &&
    mkfs.fat -F 16 -n KSSFAT16 --offset 133120 "$IMG" 24576 >/dev/null &&
    mkfs.fat -F 12 -n KSSFAT12 --offset 182272 "$IMG" 4096 >/dev/null || { echo "mkfs failed"; exit 2; }
    for p in $PARTS; do fill "$IMG@@$((${p%%:*} * 512))" || { echo "mtools failed"; exit 2; }; done
    VOLS="FAT0: FAT1: FAT2:"
    EXTRA=(-s chipset=ecs_agnus -s chipset_compatible=A600 -s ide=a600/a1200
           -s "hardfile2=rw,DH0:$IMG,0,0,0,512,0,,ide0_mainboard") ;;
  super)
    mkfs.fat -C -F 16 -n KSSFAT16 "$IMG" 32768 >/dev/null || { echo "mkfs failed"; exit 2; }
    fill "$IMG" || { echo "mtools failed"; exit 2; }
    VOLS="FAT0:"
    EXTRA=(-s chipset=ecs_agnus -s chipset_compatible=A600 -s ide=a600/a1200
           -s "hardfile2=rw,DH0:$IMG,0,0,0,512,0,,ide0_mainboard") ;;
  *) echo "mode: uae, ide or super"; exit 2 ;;
esac
MD5_BEFORE=$(md5sum < "$IMG")

ADF="$OUT/wb_$NAME.adf"; DF1="$OUT/df1_$NAME.adf"
cp assets/wb133.adf "$ADF"; chmod u+w "$ADF"
xdftool "$DF1" create + format Copies ofs >/dev/null || { echo "xdftool create failed"; exit 2; }
{
  echo 'echo >SER: "FATFS START"'
  echo 'failat 30'
  echo 'info >SER:'
  k=0
  for V in $VOLS; do
    k=$((k + 1))
    echo "echo >SER: \"== $V\""
    echo "dir >SER: $V opt a"
    echo "list >SER: $V"
    echo "list >SER: ${V}sub/deep"
    echo "type >SER: ${V}readme.txt"
    echo "type >SER: \"${V}été 2026.txt\""
    echo "type >SER: \"${V}MIXED CASE NAME.txt\""
    echo "type >SER: \"${V}many/FILE NUMBER 37.TXT\""
    echo "type >SER: ${V}empty.txt"
    echo "copy ${V}big.bin DF1:big$k.bin"
    echo "copy ${V}sub/deep/frag.bin DF1:frag$k.bin"
    echo "copy ${V}ALONGF~1.BIN DF1:long$k.bin"
    echo "cd ${V}sub/deep"
    echo "cd /"
    echo 'echo >SER: "after cd /:"'
    echo 'dir >SER:'
    echo 'cd //'
    echo 'echo >SER: "after cd //:"'
    echo 'dir >SER:'
    echo "cd ${V}many"
    echo 'cd /'
    echo 'echo >SER: "after cd / from many:"'
    echo 'cd >SER:'
    echo "cd \"${V}many/file number 40.txt//\""      # parent of an entry in a later cluster of its directory
    echo 'echo >SER: "parent of file number 40:"'
    echo 'cd >SER:'
    echo 'cd SYS:'
  done
  echo 'list >SER: DF1:'
  echo 'echo >SER: "FATFS END"'
  echo "makedir ${VOLS%% *}newdir"
} | iconv -f UTF-8 -t LATIN1 > "$OUT/startup"
xdftool "$ADF" delete s/startup-sequence + write "$OUT/startup" s/startup-sequence >/dev/null \
  || { echo "xdftool write failed"; exit 2; }

"$A" start --name "$NAME" --rom "$ROM" --adf "$ADF" --adf "$DF1" --fast 2 -- "${EXTRA[@]}" >/dev/null \
  || { echo "start failed"; exit 2; }
"$A" wait-serial "$NAME" "FATFS END" "$TMO"; rc=$?
SES=build/amiberry/sessions/$NAME
sleep 10                                        # the write-protected requester of the makedir
"$A" shot "$NAME" fatfs.png --via ipc >/dev/null
"$A" stop "$NAME" >/dev/null
tr -d '\r' < "$SES/serial.log" | sed -n '/FATFS START/,/FATFS END/p' | iconv -f LATIN1 -t UTF-8
[ $rc -eq 0 ] || { echo "no FATFS END"; exit 1; }
fail=0
SDF1="$SES/df1-$(basename "$DF1")"             # amiberry-session copies DFn as dfn-<name>
k=0
for V in $VOLS; do
  k=$((k + 1))
  for p in "big$k.bin:big.bin" "frag$k.bin:frag.bin" "long$k.bin:big.bin"; do
    f=${p%%:*}; ref=${p#*:}
    if xdftool "$SDF1" read "$f" "$OUT/$f" 2>/dev/null && cmp -s "$S/$ref" "$OUT/$f"; then
      echo "$V $f: identical ($(stat -c %s "$OUT/$f") bytes)"
    else
      echo "$V $f: DIFFERS or missing"; fail=1
    fi
  done
done
if [ "$(md5sum < "$IMG")" = "$MD5_BEFORE" ]; then echo "image unchanged"; else echo "image CHANGED"; fail=1; fi
[ "$MODE" = ide ] || PARTS="0:$(( $(stat -c %s "$IMG") / 512 ))"
for p in $PARTS; do
  dd if="$IMG" of="$OUT/part.img" bs=512 skip="${p%%:*}" count="${p#*:}" status=none
  if fsck.fat -n "$OUT/part.img" >/dev/null; then echo "fsck.fat ${p%%:*}: clean"; else echo "fsck.fat ${p%%:*}: errors"; fail=1; fi
done
echo "screenshot: $SES/fatfs.png"
exit $fail
