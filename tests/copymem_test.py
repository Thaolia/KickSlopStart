# tests/copymem_test.py - runs exec_CopyMem and exec_CopyMemQuick of OUR ROM (unicorn, 68000) on every
# source/destination alignment 0-3 and sizes 0-600 plus a few large ones, and on overlapping ranges whose
# destination lies below the source (ascending copy, exec-memory-semaphores-v34 §3). Checks the copied bytes, that
# no byte outside the destination changed, that d2-d7/a2-a6 are preserved, and the internal contract used by the
# file system and LoadSeg: a0/a1 come back just past the copied bytes. Prints the instructions executed by a few
# large copies (a speed proxy to compare two ROMs).
# Dependency: Python module unicorn.
# Usage: python3 tests/copymem_test.py <rom> <vlink -M map of that rom>
import random
import re
import struct
import sys
from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN, UC_HOOK_CODE
from unicorn.m68k_const import (UC_CPU_M68K_M68000, UC_M68K_REG_A0, UC_M68K_REG_A1, UC_M68K_REG_A2, UC_M68K_REG_A3, UC_M68K_REG_A4,
                                UC_M68K_REG_A5, UC_M68K_REG_A6, UC_M68K_REG_A7, UC_M68K_REG_D0, UC_M68K_REG_D1,
                                UC_M68K_REG_D2, UC_M68K_REG_D3, UC_M68K_REG_D4, UC_M68K_REG_D5, UC_M68K_REG_D6,
                                UC_M68K_REG_D7)

rom = open(sys.argv[1], 'rb').read()
syms = {}
for line in open(sys.argv[2]):
    m = re.match(r'\s+0x([0-9a-f]+) (\w+):', line)
    if m:
        syms[m.group(2)] = int(m.group(1), 16)
COPY, QUICK = syms['exec_CopyMem'], syms['exec_CopyMemQuick']

RAM = 0x800000
STOP = 0x00FFF0              # return address: an address in RAM where emulation stops
STACK = 0x00FF00
SRC, DST, AREA = 0x10000, 0x40000, 0x20000
KEPT = [UC_M68K_REG_D2, UC_M68K_REG_D3, UC_M68K_REG_D4, UC_M68K_REG_D5, UC_M68K_REG_D6, UC_M68K_REG_D7,
        UC_M68K_REG_A2, UC_M68K_REG_A3, UC_M68K_REG_A4, UC_M68K_REG_A5, UC_M68K_REG_A6]

count = [0]


def hook(uc, addr, size, user):
    count[0] += 1


def new_emu(counted):
    # a separate instance counts instructions: a hook added later does not reach blocks already translated
    uc = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
    uc.ctl_set_cpu_model(UC_CPU_M68K_M68000)   # the default model is a ColdFire (no DBcc)
    uc.mem_map(0, RAM)
    uc.mem_map(0xFC0000, 0x40000)
    uc.mem_write(0xFC0000, rom[:0x40000])
    if counted:
        uc.hook_add(UC_HOOK_CODE, hook)
    return uc


mu = new_emu(False)
rng = random.Random(1234)
SRCDATA = rng.randbytes(AREA)
FILL = rng.randbytes(AREA)
mu.mem_write(SRC, SRCDATA)
fails = 0


def call(entry, a0, a1, d0):
    mu.reg_write(UC_M68K_REG_A7, STACK - 4)
    mu.mem_write(STACK - 4, struct.pack('>I', STOP))
    mu.reg_write(UC_M68K_REG_A0, a0)
    mu.reg_write(UC_M68K_REG_A1, a1)
    mu.reg_write(UC_M68K_REG_D0, d0)
    mu.reg_write(UC_M68K_REG_D1, 0x5A5A5A5A)
    for i, r in enumerate(KEPT):
        mu.reg_write(r, 0x11110000 + i)
    count[0] = 0
    mu.emu_start(entry, STOP, count=50_000_000)
    kept = all(mu.reg_read(r) == 0x11110000 + i for i, r in enumerate(KEPT))
    sp = mu.reg_read(UC_M68K_REG_A7) == STACK
    return mu.reg_read(UC_M68K_REG_A0), mu.reg_read(UC_M68K_REG_A1), kept and sp, count[0]


def fail(msg):
    global fails
    fails += 1
    if fails <= 20:
        print('FAIL', msg)


def run_disjoint(entry, name, so, do, n):
    eff = n & ~3 if entry == QUICK else n
    span = min(AREA, n + 16)
    mu.mem_write(DST, FILL[:span])
    a0, a1, kept, ins = call(entry, SRC + so, DST + do, n)
    got = bytes(mu.mem_read(DST, span))
    want = FILL[:do] + SRCDATA[so:so + eff] + FILL[do + eff:span]
    if got != want:
        fail(f'{name} src+{so} dst+{do} n={n}: wrong bytes')
    if bytes(mu.mem_read(SRC, span)) != SRCDATA[:span]:
        fail(f'{name} src+{so} dst+{do} n={n}: source changed')
    if (a0, a1) != (SRC + so + eff, DST + do + eff):
        fail(f'{name} src+{so} dst+{do} n={n}: a0/a1 = {a0:x}/{a1:x}')
    if not kept:
        fail(f'{name} src+{so} dst+{do} n={n}: a preserved register or sp changed')
    return ins


sizes = list(range(0, 601)) + [1023, 1024, 1025, 4096, 4099, 65535, 65536, 65541, 100003]
cases = 0
for so in range(4):
    for do in range(4):
        for n in sizes:
            run_disjoint(COPY, 'CopyMem', so, do, n)
            cases += 1
for so in (0, 2):
    for do in (0, 2):
        for n in sizes:
            run_disjoint(QUICK, 'CopyMemQuick', so, do, n)
            cases += 1

# overlapping, destination below the source: the ascending copy must give memmove's result
for gap in range(1, 40):
    for n in (0, 1, 3, 7, 8, 31, 32, 33, 63, 64, 65, 255, 488, 512, 1000):
        for base in range(4):
            data = rng.randbytes(2048)
            mu.mem_write(SRC, data)
            s = SRC + 64 + base + gap
            d = SRC + 64 + base
            ref = bytearray(data)
            ref[d - SRC:d - SRC + n] = data[s - SRC:s - SRC + n]
            a0, a1, kept, _ = call(COPY, s, d, n)
            if bytes(mu.mem_read(SRC, 2048)) != bytes(ref):
                fail(f'CopyMem overlap gap={gap} base={base} n={n}')
            cases += 1
# more than 65536 blocks of 32 bytes: the 16-bit loop counter must carry over (2 MB + 37 bytes)
BIG, BSRC, BDST = 65537 * 32 + 37, 0x100000, 0x480000
big = rng.randbytes(BIG)
mu.mem_write(BSRC, big)
mu.mem_write(BDST, bytes(BIG + 8))
a0, a1, kept, _ = call(COPY, BSRC, BDST, BIG)
if bytes(mu.mem_read(BDST, BIG + 8)) != big + bytes(8) or (a0, a1) != (BSRC + BIG, BDST + BIG) or not kept:
    fail('CopyMem 2 MB')
cases += 1

mu = new_emu(True)
mu.mem_write(SRC, SRCDATA)

for n in (488, 512, 4096, 65536):
    print(f'instructions CopyMem n={n}: aligned {run_disjoint(COPY, "CopyMem", 0, 0, n)}, '
          f'odd/odd {run_disjoint(COPY, "CopyMem", 1, 3, n)}, '
          f'CopyMemQuick {run_disjoint(QUICK, "CopyMemQuick", 0, 0, n)}')

print(f'{cases} cases, {fails} failures')
print('copymem_test PASS' if fails == 0 else 'copymem_test FAIL')
sys.exit(1 if fails else 0)
