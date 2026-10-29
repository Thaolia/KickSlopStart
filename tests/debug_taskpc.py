# tests/debug_taskpc.py - FS-UAE debugger driver (called by tests/dskchg_run.sh, "tpc" command): finds a
# task by name in TaskReady / TaskWait and reads its context frame (TC_SPREG -> [d0-d7/a0-a6 60 bytes][SR][PC]),
# N times, resuming emulation between two stops ("g", pause, then the stop command passed as argument); at
# each stop, also the current task (name, priority, PC and processor mode, USP).
# Usage: debug_taskpc.py <fifo> <log> <task name> <n> <stop command file>
import sys, time, re, struct, subprocess
fifo, log, name, n, brk = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
f = open(fifo, 'w')
def cmd(c):
    f.write(c + '\n'); f.flush()
def rd(addr, ln):
    base = addr & ~15; cnt = (addr + ln - base + 15) // 16
    want = {base + 16*i for i in range(cnt)}; got = {}
    pos = len(open(log, errors='replace').read())   # only lines written after the command count
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
def find():
    eb = L(4)
    for head in (eb + 0x196, eb + 0x1A4):
        t = L(head)
        while t and L(t):
            if cstr(L(t + 10)) == name: return t
            t = L(t)
    return 0
for i in range(n):
    if i:
        cmd('g'); time.sleep(1.5); subprocess.run(['bash', '-c', brk]); time.sleep(2)
    eb = L(4); cur = L(eb + 0x114)
    pos = len(open(log, errors='replace').read())
    cmd('r'); time.sleep(1.5)
    txt = open(log, errors='replace').read()[pos:]
    pcs = re.findall(r'Next PC: ([0-9a-f]+)', txt); usp = re.findall(r'USP +([0-9A-F]+)', txt); srm = re.findall(r'T=.. S=(\d)', txt)
    print('courante %x %s pc %s S=%s usp %s pri %d sigwait %08x sigrecvd %08x' % (cur, cstr(L(cur + 10)),
          pcs[-1] if pcs else '?', srm[-1] if srm else '?', usp[-1] if usp else '?', struct.unpack('b', rd(cur + 9, 1))[0],
          L(cur + 22), L(cur + 26)))
    top = L(eb + 0x36)               # SysStkUpper: the outermost frame (interrupt taken in user mode) lies just below
    fr = rd(top - 6, 6)
    print('  trame externe : sr %04x pc %08x' % (struct.unpack('>H', fr[:2])[0], struct.unpack('>I', fr[2:])[0]))
    if rd(cur + 8, 1)[0] == 13:      # NT_PROCESS: messages pending on pr_MsgPort
        m = L(cur + 92 + 20); k = 0
        while m and L(m) and k < 50: k += 1; m = L(m)
        print('  messages en attente : %d' % k)
    t = find()
    if not t: print('tâche introuvable'); continue
    sp = L(t + 0x36); fr = rd(sp, 66)
    regs = struct.unpack('>15I', fr[:60]); sr = struct.unpack('>H', fr[60:62])[0]; pc = struct.unpack('>I', fr[62:66])[0]
    print('tcb %x state %d sp %x sr %04x pc %08x' % (t, rd(t + 15, 1)[0], sp, sr, pc))
    print('  d: ' + ' '.join('%08x' % r for r in regs[:8])); print('  a: ' + ' '.join('%08x' % r for r in regs[8:]))
cmd('g')
