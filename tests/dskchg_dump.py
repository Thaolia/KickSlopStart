# tests/dskchg_dump.py — relit au débogueur FS-UAE le journal mémoire de tests/dskchg.s (ASSET DE TEST, piste analyse).
# Usage : python3 -I tests/dskchg_dump.py <fifo débogueur> <journal fs-uae> <fichier de sortie> (appelé par dskchg_run.sh).
import sys, time, re, struct
fifo, log, out = sys.argv[1:4]
f = open(fifo, 'w')
def cmd(c): f.write(c + '\n'); f.flush()
def rd(addr, n, timeout=120):
    want = {addr + 16*i for i in range(n)}; got = {}
    cmd('m %x %d' % (addr, n)); t0 = time.time()
    while time.time() - t0 < timeout:
        txt = open(log, errors='replace').read()
        for m in re.finditer(r'^>?([0-9A-F]{8}) ((?:[0-9A-F]{4} ){8})', txt, re.M):
            a = int(m.group(1), 16)
            if a in want: got[a] = bytes.fromhex(m.group(2).replace(' ', ''))
        if len(got) == len(want): break
        time.sleep(0.5)
    return b''.join(got.get(addr + 16*i, b'?'*16) for i in range(n))
h = rd(0x3f0, 1)
buf, magic = struct.unpack('>I4s', h[:8])
print('buf', hex(buf), magic)
ln = struct.unpack('>I', rd(buf, 1)[:4])[0]
print('len', ln)
data = b''
a = buf + 4; end = buf + 4 + ln
while a < end:
    n = min(64, (end - a + 15)//16)
    data += rd(a & ~15, n)[a - (a & ~15):] if a & 15 else rd(a, n)
    a = (a & ~15) + 16*n
open(out, 'wb').write(data[:ln])
print('ok', len(data[:ln]))
