# tests/td_decode_test.py - runs td_decode_track of OUR ROM (unicorn, 68000) on synthetic MFM tracks:
# 11 AmigaDOS sectors + a gap of 532, 700 or 830 bytes (830 = amiga500-esp32 emulator, track of 6,399 words), read
# of TD_RAWWORDS words started after the first sync of each of the 11 sectors (WORDSYNC). Expected: 11 sectors,
# correct track, mask $7FF, data identical to the ADF. Dependency: Python module unicorn.
# Usage: python3 tests/td_decode_test.py <rom> <hex address of td_decode_track (vlink -M)> <adf>
import sys, struct, random
from unicorn import *
from unicorn.m68k_const import *
rom = open(sys.argv[1], 'rb').read(); DEC = int(sys.argv[2], 16); adf = open(sys.argv[3], 'rb').read()

def build_rev(track, gap):
    out = bytearray(); st = {'bits': 0, 'n': 0, 'prev': 0}
    def bit(b):
        clk = 1 if (not st['prev'] and not b) else 0
        st['bits'] = ((st['bits'] << 2) | (clk << 1) | b) & 0xFFFFFFFF; st['prev'] = b; st['n'] += 2
        while st['n'] >= 8: st['n'] -= 8; out.append((st['bits'] >> st['n']) & 0xFF)
    def raw16(w):
        for i in range(15, -1, -1):
            st['bits'] = ((st['bits'] << 1) | ((w >> i) & 1)) & 0xFFFFFFFF; st['n'] += 1
            while st['n'] >= 8: st['n'] -= 8; out.append((st['bits'] >> st['n']) & 0xFF)
        st['prev'] = w & 1
    def oddeven(d):
        for half in (0, 1):
            for x in d:
                for b in range(7 - half, -1, -2): bit((x >> b) & 1)
    def ck(a, b):
        c = 0
        for p in range(a, b, 4): c ^= struct.unpack('>I', out[p:p+4])[0] & 0x55555555
        return c
    starts = []
    for s in range(11):
        for _ in range(16): bit(0)
        starts.append(len(out)); raw16(0x4489); raw16(0x4489)
        h0 = len(out); oddeven(bytes([0xFF, track, s, 11 - s])); oddeven(bytes(16)); h1 = len(out)
        oddeven(struct.pack('>I', ck(h0, h1)))
        dpos = len(out); oddeven(bytes(4))
        d0 = len(out); oddeven(adf[(track * 11 + s) * 512:(track * 11 + s + 1) * 512]); dck = ck(d0, len(out))
        save = (dict(st), len(out)); tail = out[dpos + 8:]
        del out[dpos:]; st['prev'] = 1; oddeven(struct.pack('>I', dck)); out.extend(tail); st.update(save[0])
    out.extend(b'\xAA' * (11 * 1088 + gap - len(out)))
    return bytes(out), starts

def run(raw):
    mu = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
    try: mu.ctl_set_cpu_model(UC_CPU_M68K_M68000)
    except Exception: pass
    mu.mem_map(0, 0x100000); mu.mem_map(0xFC0000, 0x40000); mu.mem_write(0xFC0000, rom)
    RAW, SEC, SP, STOP = 0x10000, 0x20000, 0x7F000, 0x7FF00
    mu.mem_write(RAW, raw); mu.mem_write(SEC, b'\xEE' * 5632)
    mu.mem_write(STOP, b'\x4e\x71\x4e\x71'); mu.mem_write(SP, struct.pack('>I', STOP))
    mu.reg_write(UC_M68K_REG_A7, SP); mu.reg_write(UC_M68K_REG_A0, RAW); mu.reg_write(UC_M68K_REG_A1, SEC)
    mu.emu_start(DEC, STOP, count=5_000_000)
    return mu.reg_read(UC_M68K_REG_D0), mu.reg_read(UC_M68K_REG_D1), mu.reg_read(UC_M68K_REG_A0), bytes(mu.mem_read(SEC, 5632))

bad = 0
for gap in (532, 700, 830):
    for track in (0, 41, 159):
        rev, starts = build_rev(track, gap); W = len(rev) // 2
        for k in range(11):
            w0 = starts[k] // 2 + 1                     # DMA after the 1st sync (WORDSYNC)
            raw = b''.join(rev[2 * ((w0 + i) % W): 2 * ((w0 + i) % W) + 2] for i in range(6400))
            n, t, m, sec = run(raw)
            ok = n == 11 and t == track and m == 0x7FF and sec == adf[track * 5632:(track + 1) * 5632]
            if not ok: bad += 1
            print('gap %d piste %3d début secteur %2d : %2d secteurs, piste %3d, masque %03X %s' % (gap, track, k, n, t, m, 'OK' if ok else 'ECHEC'))
print('ÉCHECS :', bad)
sys.exit(1 if bad else 0)
