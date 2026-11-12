# tests/allocmem_clear_test.py - runs exec_AllocMem of OUR ROM (unicorn, 68000) with MEMF_CLEAR on a minimal
# ExecBase (Forbid/Permit vectors that return at once, one MemHeader with one free chunk). For sizes 1-400 and a few
# large ones (past 65536 blocks of 32 bytes): the block is the start of the chunk, its rounded size (8-byte units)
# is zeroed, the bytes after it are untouched, d1-d7/a2-a6 and sp are preserved. Without MEMF_CLEAR the contents
# stay as they were. Prints the instructions executed by a few clears (a speed proxy to compare two ROMs).
# Dependency: Python module unicorn.
# Usage: python3 tests/allocmem_clear_test.py <rom> <vlink -M map of that rom>
import re
import struct
import sys
from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN, UC_HOOK_CODE
from unicorn.m68k_const import (UC_CPU_M68K_M68000, UC_M68K_REG_A0, UC_M68K_REG_A1, UC_M68K_REG_A2,
                                UC_M68K_REG_A3, UC_M68K_REG_A4, UC_M68K_REG_A5, UC_M68K_REG_A6, UC_M68K_REG_A7,
                                UC_M68K_REG_D0, UC_M68K_REG_D1, UC_M68K_REG_D2, UC_M68K_REG_D3, UC_M68K_REG_D4,
                                UC_M68K_REG_D5, UC_M68K_REG_D6, UC_M68K_REG_D7)

rom = open(sys.argv[1], 'rb').read()
syms = {}
for line in open(sys.argv[2]):
    m = re.match(r'\s+0x([0-9a-f]+) (\w+):', line)
    if m:
        syms[m.group(2)] = int(m.group(1), 16)
ALLOC = syms['exec_AllocMem']

# exec.i
EB_THISTASK, EB_MEMLIST, LVO_FORBID, LVO_PERMIT = 0x114, 0x142, -132, -138
MH_ATTRIBUTES, MH_FIRST, MH_LOWER, MH_UPPER, MH_FREE = 14, 16, 20, 24, 28
MEMF_PUBLIC, MEMF_CLEAR = 1, 1 << 16

RAM = 0x800000
STOP, STACK = 0x00FFF0, 0x00FF00
EXECBASE, HEADER = 0x2000, 0x3000
CHUNK, CHUNKSIZE = 0x10000, 0x700000
KEPT = [UC_M68K_REG_D2, UC_M68K_REG_D3, UC_M68K_REG_D4, UC_M68K_REG_D5, UC_M68K_REG_D6, UC_M68K_REG_D7,
        UC_M68K_REG_A2, UC_M68K_REG_A3, UC_M68K_REG_A4, UC_M68K_REG_A5]
count = [0]


def hook(uc, addr, size, user):
    count[0] += 1


def new_emu(counted):
    uc = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
    uc.ctl_set_cpu_model(UC_CPU_M68K_M68000)   # the default model is a ColdFire (no DBcc)
    uc.mem_map(0, RAM)
    uc.mem_map(0xFC0000, 0x40000)
    uc.mem_write(0xFC0000, rom[:0x40000])
    for lvo in (LVO_FORBID, LVO_PERMIT):
        uc.mem_write(EXECBASE + lvo, b'\x4e\x75')            # rts
    uc.mem_write(EXECBASE + EB_THISTASK, struct.pack('>I', 0))
    lst = EXECBASE + EB_MEMLIST                                 # list: head -> HEADER -> &lh_Tail
    uc.mem_write(lst, struct.pack('>III', HEADER, 0, HEADER))
    uc.mem_write(HEADER, struct.pack('>II', lst + 4, lst))
    if counted:
        uc.hook_add(UC_HOOK_CODE, hook)
    return uc


fails = 0


def fail(msg):
    global fails
    fails += 1
    if fails <= 20:
        print('FAIL', msg)


def alloc(mu, size, req, fill):
    mu.mem_write(HEADER + MH_ATTRIBUTES, struct.pack('>H', 0x0003))
    mu.mem_write(HEADER + MH_FIRST, struct.pack('>IIII', CHUNK, CHUNK, CHUNK + CHUNKSIZE, CHUNKSIZE))
    span = min(CHUNKSIZE, ((size + 7) & ~7) + 64)
    mu.mem_write(CHUNK, fill * span)
    mu.mem_write(CHUNK, struct.pack('>II', 0, CHUNKSIZE))       # the free chunk's own header
    mu.reg_write(UC_M68K_REG_A7, STACK - 4)
    mu.mem_write(STACK - 4, struct.pack('>I', STOP))
    mu.reg_write(UC_M68K_REG_A6, EXECBASE)
    mu.reg_write(UC_M68K_REG_D0, size)
    mu.reg_write(UC_M68K_REG_D1, req)
    for i, r in enumerate(KEPT):
        mu.reg_write(r, 0x22220000 + i)
    count[0] = 0
    mu.emu_start(ALLOC, STOP, count=100_000_000)
    kept = all(mu.reg_read(r) == 0x22220000 + i for i, r in enumerate(KEPT))
    kept = kept and mu.reg_read(UC_M68K_REG_D1) == req and mu.reg_read(UC_M68K_REG_A6) == EXECBASE
    kept = kept and mu.reg_read(UC_M68K_REG_A7) == STACK
    return mu.reg_read(UC_M68K_REG_D0), bytes(mu.mem_read(CHUNK, span)), kept, count[0]


mu = new_emu(False)
sizes = list(range(1, 401)) + [4095, 4096, 4097, 65536, 100001, 65537 * 32 + 3]
for size in sizes:
    rounded = (size + 7) & ~7
    d0, mem, kept, _ = alloc(mu, size, MEMF_PUBLIC | MEMF_CLEAR, b'\xa5')
    if d0 != CHUNK:
        fail(f'size {size}: d0 = {d0:x}')
    if mem[:rounded] != bytes(rounded):
        fail(f'size {size}: block not cleared')
    if mem[rounded + 8:] != b'\xa5' * (len(mem) - rounded - 8):   # the first 8 bytes past it: the new chunk header
        fail(f'size {size}: bytes past the block changed')
    if not kept:
        fail(f'size {size}: a preserved register or sp changed')
for size in (1, 8, 40, 1000):
    d0, mem, kept, _ = alloc(mu, size, MEMF_PUBLIC, b'\x5a')
    if d0 != CHUNK or mem[8:size] != b'\x5a' * (len(mem[8:size])) or not kept:
        fail(f'size {size} without MEMF_CLEAR')

mu = new_emu(True)
for size in (40, 512, 4096, 65536):
    print(f'instructions AllocMem MEMF_CLEAR size={size}: {alloc(mu, size, MEMF_PUBLIC | MEMF_CLEAR, b"\xa5")[3]}')
print(f'{len(sizes) + 4} cases, {fails} failures')
print('allocmem_clear_test PASS' if fails == 0 else 'allocmem_clear_test FAIL')
sys.exit(1 if fails else 0)
