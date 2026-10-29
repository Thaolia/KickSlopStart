#!/usr/bin/env python3
# tests/mk_bigdata.py - test DATA file "BigData" for the proof of real OFS streaming.
# Size 48000 bytes = > 32768 (the old whole-file cap DOS_FILEMAX) WITHOUT ambiguity: the old handler
# would have truncated at FINDINPUT; the streaming handler (incremental read, data block by data block, a single
# 512-byte buffer) reads it entirely. Deterministic pattern (i*73+17 & 0xFF) + sentinel $B16B00B5 in the last 4
# bytes. Written to the test ADF by mk_boot_adf.sh; read by d3j_client via dos Open/Read. NO ROM read.
import sys, struct

SIZE = 48000
SENTINEL = 0xB16B00B5

buf = bytearray(SIZE)
for i in range(SIZE - 4):
    buf[i] = (i * 73 + 17) & 0xFF
struct.pack_into(">I", buf, SIZE - 4, SENTINEL)

with open(sys.argv[1], "wb") as f:
    f.write(buf)

# Constants for the client's assertion (avoids an arithmetic mistake on the asm side).
at500 = struct.unpack(">I", buf[500:504])[0]
print(f"BigData {SIZE} o, sentinelle $B16B00B5 @{SIZE-4}, long@500 = ${at500:08X}")
