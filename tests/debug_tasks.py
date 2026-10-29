# tests/debug_tasks.py - FS-UAE debugger driver (called by tests/debug_tasks.sh): reads memory with "m addr n"
# (input FIFO, replies read from the log) and walks the TaskReady / TaskWait lists of ExecBase.
import sys, time, re, struct
fifo, log = sys.argv[1], sys.argv[2]
f = open(fifo, 'w')
def cmd(c):
    f.write(c + '\n'); f.flush()
pos = [0]
def wait_lines(addr, n, timeout=60):
    want = {addr + 16*i for i in range(n)}
    got = {}
    t0 = time.time()
    while time.time() - t0 < timeout:
        txt = open(log, errors='replace').read()
        for m in re.finditer(r'^>?([0-9A-F]{8}) ((?:[0-9A-F]{4} ){8})', txt, re.M):
            a = int(m.group(1), 16)
            if a in want: got[a] = bytes.fromhex(m.group(2).replace(' ', ''))
        if len(got) == len(want): break
        time.sleep(0.3)
    return b''.join(got.get(addr + 16*i, b'\0'*16) for i in range(n))
cache = {}
def rd(addr, ln):
    base = addr & ~15; n = (addr + ln - base + 15) // 16
    key = (base, n)
    if key not in cache:
        cmd('m %x %d' % (base, n)); cache[key] = wait_lines(base, n)
    d = cache[key]; return d[addr-base: addr-base+ln]
L = lambda a: struct.unpack('>I', rd(a, 4))[0]
def cstr(a):
    if a == 0 or a > 0xFFFFFF: return '?'
    s = rd(a, 32); return s.split(b'\0')[0].decode('latin1')
eb = L(4); print('ExecBase', hex(eb)); print('ThisTask', hex(L(eb+0x114)), cstr(L(L(eb+0x114)+10)))
def walk(head, label):
    n = L(head)
    k = 0
    while n and L(n) and k < 40:
        t = rd(n, 0xC0)
        name = cstr(struct.unpack('>I', t[10:14])[0])
        st = t[15]; sw = struct.unpack('>I', t[22:26])[0]; sr = struct.unpack('>I', t[26:30])[0]
        line = '%s %s %-22s state=%d sigwait=%08x sigrecvd=%08x' % (label, hex(n), name, st, sw, sr)
        if t[8] == 13:  # NT_PROCESS
            mp = n + 92; first = L(mp + 20)
            msgs = []
            while first and L(first) and len(msgs) < 5:
                msgs.append(hex(first)); first = L(first)
            line += ' port_msgs=%s pktwait=%x tasknum=%d' % (msgs, L(n+180), L(n+140))
        print(line); n = L(n); k += 1
walk(eb + 0x196, 'READY')
walk(eb + 0x1A4, 'WAIT ')
