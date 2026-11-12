# tests/td_encode_test.py - runs td_encode_track of two ROMs (unicorn, 68000) on the same sectors and compares the
# encoded tracks byte for byte: random sectors on 40 tracks, plus all-zero, all-one and alternating sectors (the
# clock rule between neighbours and across long and sector boundaries). Also decodes each new track with the new
# ROM's td_decode_track: 11 sectors, the mask $7FF, the track number and the data must come back. Checks that
# d2-d7/a2-a6 and sp are preserved, and prints the instructions of one encode for each ROM.
# Dependency: Python module unicorn.
# Usage: python3 tests/td_encode_test.py <rom> <map> <reference rom> <reference map>   (maps from vlink -M)
import random
import re
import struct
import sys
from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN, UC_HOOK_CODE
from unicorn.m68k_const import (UC_CPU_M68K_M68000, UC_M68K_REG_A0, UC_M68K_REG_A1, UC_M68K_REG_A2,
                                UC_M68K_REG_A3, UC_M68K_REG_A4, UC_M68K_REG_A5, UC_M68K_REG_A6, UC_M68K_REG_A7,
                                UC_M68K_REG_D0, UC_M68K_REG_D1, UC_M68K_REG_D2, UC_M68K_REG_D3, UC_M68K_REG_D4,
                                UC_M68K_REG_D5, UC_M68K_REG_D6, UC_M68K_REG_D7)

SECBUF, GAP, RAWBYTES = 5632, 1660, 0x3200
WRBYTES = GAP + 11 * 1088 + 2
STOP, STACK, SEC, OUT, DEC = 0x00FFF0, 0x00FF00, 0x10000, 0x20000, 0x40000
KEPT = [UC_M68K_REG_D2, UC_M68K_REG_D3, UC_M68K_REG_D4, UC_M68K_REG_D5, UC_M68K_REG_D6, UC_M68K_REG_D7,
        UC_M68K_REG_A2, UC_M68K_REG_A3, UC_M68K_REG_A4, UC_M68K_REG_A5, UC_M68K_REG_A6]


def load(rom_path, map_path):
    rom = open(rom_path, 'rb').read()
    syms = {}
    for line in open(map_path):
        m = re.match(r'\s+0x([0-9a-f]+) (\w+):', line)
        if m:
            syms[m.group(2)] = int(m.group(1), 16)
    return rom, syms


class Emu:
    def __init__(self, rom, counted=False):
        self.uc = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
        self.uc.ctl_set_cpu_model(UC_CPU_M68K_M68000)   # the default model is a ColdFire (no DBcc)
        self.uc.mem_map(0, 0x100000)
        self.uc.mem_map(0xFC0000, 0x40000)
        self.uc.mem_write(0xFC0000, rom[:0x40000])
        self.count = 0
        if counted:
            self.uc.hook_add(UC_HOOK_CODE, self._hook)

    def _hook(self, uc, addr, size, user):
        self.count += 1

    def call(self, entry, regs):
        uc = self.uc
        uc.reg_write(UC_M68K_REG_A7, STACK - 4)
        uc.mem_write(STACK - 4, struct.pack('>I', STOP))
        for i, r in enumerate(KEPT):
            uc.reg_write(r, 0x33330000 + i)
        for r, v in regs.items():
            uc.reg_write(r, v)
        self.count = 0
        uc.emu_start(entry, STOP, count=20_000_000)
        kept = all(uc.reg_read(r) == (regs[r] if r in regs else 0x33330000 + i) for i, r in enumerate(KEPT))
        return kept and uc.reg_read(UC_M68K_REG_A7) == STACK

    def encode(self, entry, sectors, track):
        self.uc.mem_write(SEC, sectors)
        self.uc.mem_write(OUT, b'\x77' * (WRBYTES + 64))
        ok = self.call(entry, {UC_M68K_REG_A0: SEC, UC_M68K_REG_A1: OUT, UC_M68K_REG_D0: track})
        return bytes(self.uc.mem_read(OUT, WRBYTES + 64)), ok


new_rom, new_syms = load(sys.argv[1], sys.argv[2])
ref_rom, ref_syms = load(sys.argv[3], sys.argv[4])
NEW, REF, DECODE = new_syms['td_encode_track'], ref_syms['td_encode_track'], new_syms['td_decode_track']
new, ref = Emu(new_rom), Emu(ref_rom)
rng = random.Random(4489)
cases = [(rng.randbytes(SECBUF), t) for t in rng.sample(range(160), 40)]
cases += [(bytes(SECBUF), 0), (b'\xff' * SECBUF, 79), (b'\x55' * SECBUF, 80), (b'\xaa' * SECBUF, 159),
          (bytes([0x80, 0x01] * (SECBUF // 2)), 1)]
fails = 0
for sectors, track in cases:
    got, ok_new = new.encode(NEW, sectors, track)
    want, ok_ref = ref.encode(REF, sectors, track)
    msg = []
    if got != want:
        first = next(i for i in range(len(got)) if got[i] != want[i])
        msg.append(f'differs from the reference from byte {first}')
    if not ok_new:
        msg.append('a preserved register or sp changed')
    raw = got[GAP:WRBYTES] + bytes(RAWBYTES - (WRBYTES - GAP))   # a raw read starting at sector 0's preamble
    new.uc.mem_write(OUT, raw)
    new.uc.mem_write(DEC, bytes(SECBUF))
    new.call(DECODE, {UC_M68K_REG_A0: OUT, UC_M68K_REG_A1: DEC})
    mask, trk = new.uc.reg_read(UC_M68K_REG_A0), new.uc.reg_read(UC_M68K_REG_D1)
    if (new.uc.reg_read(UC_M68K_REG_D0), mask, trk) != (11, 0x7FF, track) or \
            bytes(new.uc.mem_read(DEC, SECBUF)) != sectors:
        msg.append(f'decode gives {new.uc.reg_read(UC_M68K_REG_D0)} sectors, mask {mask:x}, track {trk}')
    if msg:
        fails += 1
        print(f'FAIL track {track}:', '; '.join(msg))

cn, cr = Emu(new_rom, True), Emu(ref_rom, True)
cn.encode(NEW, cases[0][0], cases[0][1])
cr.encode(REF, cases[0][0], cases[0][1])
print(f'instructions td_encode_track: {cn.count} (reference {cr.count})')
print(f'{len(cases)} tracks, {fails} failures')
print('td_encode_test PASS' if fails == 0 else 'td_encode_test FAIL')
sys.exit(1 if fails else 0)
