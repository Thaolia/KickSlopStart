# tests/debug_cia.py — pilote du débogueur FS-UAE (commande « cia » de tests/dskchg_run.sh) : pour ciaa.resource et
# ciab.resource de NOTRE ROM (ExecBase->ResourceList), masque ICR activé et vecteurs des 5 sources (nom, is_Code,
# is_Data). Les registres des CIA ne sont pas lisibles par le débogueur.
# Usage : debug_cia.py <fifo> <journal>
import sys, time, re, struct
fifo, log = sys.argv[1], sys.argv[2]
f = open(fifo, 'w')
def cmd(c):
    f.write(c + '\n'); f.flush()
def rd(addr, ln):
    base = addr & ~15; cnt = (addr + ln - base + 15) // 16
    want = {base + 16*i for i in range(cnt)}; got = {}
    pos = len(open(log, errors='replace').read())   # seules les lignes écrites après la commande comptent
    cmd('m %x %d' % (base, cnt)); t0 = time.time()
    while time.time() - t0 < 30 and len(got) < len(want):
        txt = open(log, errors='replace').read()[pos:]
        for m in re.finditer(r'^>?([0-9A-F]{8}) ((?:[0-9A-F]{4} ){8})', txt, re.M):
            a = int(m.group(1), 16)
            if a in want: got[a] = bytes.fromhex(m.group(2).replace(' ', ''))
        time.sleep(0.2)
    d = b''.join(got.get(base + 16*i, b'\0'*16) for i in range(cnt)); return d[addr-base: addr-base+ln]
L = lambda a: struct.unpack('>I', rd(a, 4))[0]
def cstr(a):
    if a == 0 or a > 0xFFFFFF: return '?'
    return rd(a, 32).split(b'\0')[0].decode('latin1')
eb = L(4); n = L(eb + 0x150)
while n and L(n):
    nm = cstr(L(n + 10))
    if nm.startswith('cia'):
        mask = rd(n + 34 + 4, 1)[0]
        print('%s base %x hw %x masque %02x' % (nm, n, L(n + 34), mask))
        for b in range(5):
            v = L(n + 40 + 4*b)
            if v: print('  bit %d : interrupt %x nom %s code %x data %x' % (b, v, cstr(L(v + 10)), L(v + 18), L(v + 14)))
    n = L(n)
