#!/usr/bin/env python3
"""Checker for tests/exec_memsem_probe.s (exec memory and signal semaphores).

Expected values: docs/analysis/exec-memory-semaphores-v34.md §9 (vectors) and §5 (registers), translated to the
probe's private headers (F = attributes $0805, C = $0803, linked at the head of the MemList; R = an unlinked
header). Where this ROM deliberately differs from 1.3 (docs/PLAN.md, "exec memory and semaphores"), the value of
this ROM is used by `check` and the 1.3 value by `check13`; vectors that only make sense on this ROM are skipped
by `check13`.

Usage: exec_memsem_check.py check|check13 <probe output>  (one PASS/FAIL line per vector, exit 1 on any FAIL)
"""
import re
import sys

# Registers a function may change (its result register included), spec §5.
ALLOWED = {
    'Allocate': 'd0 a1', 'Deallocate': 'd0 d1 a1', 'AllocMem': 'd0 a0 a1', 'FreeMem': 'd0 d1 a0',
    'FreeMem0': '', 'AvailMem': 'd0 a0 a1', 'AllocAbs': 'd0 a0 a1', 'AllocEntry': 'd0 d1 a0 a1',
    'FreeEntry': 'd0 d1 a0 a1', 'TypeOfMem': 'd0 a0', 'AddMemList': 'd0 d1 a0 a1', 'CopyMem': 'd0 d1 a0 a1',
    'InitSemaphore': 'a1', 'ObtainSemaphore': '', 'AttemptSemaphore': 'd0 a1', 'ReleaseSemaphore': '',
    'ObtainSemaphoreList': 'd0 d1 a0 a1', 'ReleaseSemaphoreList': 'a0', 'FindSemaphore': 'd0 d1 a0',
    'RemSemaphore': 'a0 a1', 'AddSemaphore': 'd0 d1 a0 a1', 'Procure': 'd0', 'Vacate': 'd0 d1 a0 a1',
}

E = {}      # id -> (function for x=, expected fields)
D13 = {}    # id -> 1.3 fields where this ROM deliberately differs (None: not run against 1.3)


def v(i, fn, **kw):
    E[i] = (fn, {k.rstrip('_'): x if isinstance(x, list) else str(x) for k, x in kw.items()})


# --- no Forbid/Disable level left between the probe's sections (ExecBase TDNestCnt/IDNestCnt = -1) ---
for i in range(7):
    v('Z%d' % i, None, td='FF', id_='FF')

# --- Allocate / Deallocate (R) ---
v('A1', 'Allocate', r='R0', c='R8:3F8', f='3F8')
v('A2', 'Allocate', r='R8', c='R10:3F0', f='3F0')
v('A3', 'Allocate', r='R10', c='R20:3E0', f='3E0')
v('A4', 'Allocate', r='-', c='R20:3E0', f='3E0')
v('A5', 'Allocate', r='-', c='R20:3E0', f='3E0')
v('A6', 'Allocate', r='-', c='R0:40,R80:40,R100:40', f='C0')
v('A7a', 'Allocate', r='R0', c='R80:40,R100:40', f='80')
v('A7b', 'Allocate', r='R80', c='RA0:20,R100:40', f='60')
v('A7c', 'Allocate', r='R100', c='RA0:20,R128:18', f='38')
v('A8', 'Allocate', r='R20', c='-', f='0')
v('A9', 'Allocate', r='R0', c='-', f='0')
v('A10', 'Allocate', r='-', c='R0:400', f='400')
v('A10b', 'Allocate', r='-', c='R0:400', f='400')
v('A11', 'Allocate', r='-', c='R0:400', f='400')
D13['A11'] = {'r': 'R0'}
v('D1', 'Deallocate', c='R0:80,R100:40', f='C0')
v('D2', 'Deallocate', c='R40:80,R100:40', f='C0')
v('D3', 'Deallocate', c='R40:40,RC0:80', f='C0')
v('D4', 'Deallocate', c='R40:100', f='100')
v('D5', 'Deallocate', c='R40:40,RA0:20,R100:40', f='A0')
v('D6', 'Deallocate', c='R40:40,R100:40,R200:40', f='C0')
v('D7', 'Deallocate', c='R100:40', f='40', x='-')
v('D8', 'Deallocate', c='R0:8', f='8')
v('D9a', 'Deallocate', c='R0:8,R100:40', f='48')
v('D9b', 'Deallocate', c='R0:10,R100:40', f='50')
v('D9c', 'Deallocate', c='R0:10,R100:40', f='50')
v('D9d', 'Deallocate', c='R0:8,R100:40', f='48')
v('D9e', 'Deallocate', c='R0:18,R100:40', f='58')
v('D9f', 'Deallocate', c='R0:8,R100:40', f='48')

# --- AllocMem (M, F, MC), FreeMem size 0 (G), AvailMem (T) ---
for n, d in zip(range(1, 9), ['8', '8', '8', '8', '10', '10', '10', '18']):
    v('M%d' % n, 'AllocMem', r='F0', d=d, rs='1')
v('M9', 'AllocMem', r='-', d='0', rs='1')
for i in ('M10', 'M10b'):
    v(i, 'AllocMem', r='-', d='0', rs='1')
    D13[i] = {'r': 'F0'}
for i in ('M11', 'M12', 'M13', 'M14'):
    v(i, 'AllocMem', r='-', d='0', rs='1')
v('M14b', 'AllocMem', r='F0', d='400', rs='1')
for n, r in enumerate('F F C C F F - - - - - - F F F F F C C'.split(), 1):
    v('F%d' % n, None, r=r if r == '-' else r + '0')
v('MC1', None, r='F0', h='00000000,00000400,A5A5A5A5')
v('MC2', None, r='F0', h='00000000,00000000,00000000,00000000,00000000,000003F0')
v('MC3', None, r='F0', h='00000000,00000000,00000000,000003F8')
v('G2', 'FreeMem0', d='0')
v('G7', 'FreeMem0', d='10')
for i, val in zip(range(1, 8), ['800', '400', '800', '800', '400', '400', '0']):
    v('Tp%d' % i, 'AvailMem', v_=val, ref=val)
for i in range(1, 18):
    v('T%d' % i, 'AvailMem', ref='=v')

# --- AllocAbs (L) on F ---
v('L1', 'AllocAbs', r='F100', c='F0:100,F140:2C0', f='3C0')
v('L1f', None, c='F0:400', f='400')
v('L2', 'AllocAbs', r='F100', c='F0:100,F148:2B8', f='3B8')
v('L2f', None, c='F0:400', f='400')
v('L3', 'AllocAbs', r='F100', c='F0:100,F140:2C0', f='3C0')
v('L4', None, c='F0:400', f='400')
v('L5', 'AllocAbs', r='F0', c='F40:3C0', f='3C0')
for i in ('L6', 'L7', 'L8', 'L9'):
    v(i, 'AllocAbs', r='-', c='F40:3C0', f='3C0')
v('L9f', None, c='F0:400', f='400')
v('L10', 'AllocAbs', r='F200', c='F0:200,F200:200', f='400')
v('L10m', 'AllocAbs', r='F1F8', c='F0:1F8,F200:200', f='3F8')
v('L10f', None, c='F0:400', f='400')
v('L11', 'AllocAbs', r='F0', c='-', f='0')
v('L11f', None, c='F0:400', f='400')
v('L11b', 'AllocAbs', r='F3C0', c='F0:3C0', f='3C0')
v('L11g', None, c='F0:400', f='400')
v('L11c', 'AllocAbs', r='C100', c='F0:400', f='400')
v('L11h', None, c='F0:400', f='400')
v('L12', 'AllocAbs', r='-', c='F0:400', f='400')

# --- AllocEntry / FreeEntry (E, H) ---
v('E1', 'AllocEntry', r='F0', n='2', nd='1', e='F20:64,C0:32', z='1', l='a20/10000,a64/1,a32/10002', same='1')
v('E1h', 'FreeEntry', l='fF20/64,fC0/32,fF0/20', rs='1')
v('E2', 'AllocEntry', r='F0', n='2', nd='1', e='-:0,C0:8', z='1', l='a20/10000,a8/2', same='1')
v('E2h', 'FreeEntry', l='fC0/8,fF0/20', rs='1')
v('E4', None, r='!80010004', l='a28/10000,a40/1,a7FFFFFF0/10004,fF28/40', same='1', lk='28')
v('E5', None, r='!80000008', l='a18/10000,a40/8', same='1', lk='18')
v('E6', None, r='!80000006', l='a20/10000,a40/2,a40/6,fC0/40', same='1', lk='20')
v('E7', None, r='!80010000', l='a30010/10000', same='1', lk='0')
v('E8', 'AllocEntry', r='F0', n='0', nd='1', e='', l='a10/10000', same='1')
v('E8h', 'FreeEntry', l='fF0/10', rs='1')
D13['E8'] = None
D13['E8h'] = None
v('H3', None, l='fF0/18', lk='8')

# --- AddMemList (K) ---
for i, (p, lo, f) in {'K1': ('5', 'K20', 'FE0'), 'K2': (None, 'K20', 'FE0'), 'K3': ('-14', 'K20', 'FE0'),
                      'K4': ('5', 'K28', 'FD8'), 'K5': ('5', 'K28', 'FD8')}.items():
    kw = dict(t='A', nm='1', a='41', lo=lo, hi='K1000', fi=lo, c='%s:%s' % (lo, f), f=f, o='order')
    if p:
        kw['p'] = p
    v(i, 'AddMemList', **kw)
v('K6', None, r='K20,K20', t='3,41,41,3')

# --- CopyMem / CopyMemQuick (B) ---
v('B0', 'CopyMem')
v('B1', None, n='77', bad='0')
v('B2', None, n='28', bad='0')
v('B3', None, n='F', bad='0')
v('B4', None, n='F', bad='0')
v('B5', None, n='1E', bad='0')
v('B5q', None, n='10', bad='0')

# --- Semaphores (S, C, Q, N, P) ---
def sem(n, q, o, w='-'):
    return dict(n=n, q=q, o=o, w=w)


v('S1', 'InitSemaphore', nd='1', ml='1', a1='10', **sem('0', 'FFFF', '-'))
v('S2', 'ObtainSemaphore', **sem('1', '0', 'M'))
v('S3', 'ObtainSemaphore', **sem('2', '1', 'M'))
v('S4', 'AttemptSemaphore', d='1', a1='M', **sem('3', '2', 'M'))
v('S5', 'AttemptSemaphore', d='1', a1='M', **sem('1', '0', 'M'))
v('S7', 'ReleaseSemaphore', **sem('2', '1', 'M'))
v('S7b', 'ReleaseSemaphore', **sem('1', '0', 'M'))
v('S8', 'ReleaseSemaphore', **sem('0', 'FFFF', '-'))
v('S6', 'AttemptSemaphore', d='0', a1='M', **sem('1', '0', 'T'))
v('C7', 'AttemptSemaphore', d='0', a1='M', **sem('1', '1', 'T', 'U'))
v('C7e', None, **sem('0', 'FFFF', '-'))
v('C0', None, **sem('1', '0', 'T'))
v('C3a', None, **sem('1', '1', 'T', 'U'))
v('C3', None, sg='0', **sem('1', '2', 'T', 'U,M'))
v('C4b', None, **sem('0', '1', 'U', 'M'))
v('C4u', None, **sem('1', '1', 'U', 'M'))
v('C1', 'ObtainSemaphore', **sem('1', '0', 'M'))
v('C8x', None, **sem('0', 'FFFF', '-'))
v('C5', 'ReleaseSemaphore', **sem('1', '1', 'M', 'T'))
v('C5t', None, **sem('1', '0', 'T'))
v('C5e', 'ReleaseSemaphore', **sem('0', 'FFFF', '-'))
v('C6', 'ReleaseSemaphore', **sem('0', 'FFFF', '-'))
v('C2', None, **sem('1', '0', 'M'))
D13['C2'] = {'n': '2', 'q': '1', 'o': 'T'}
ALL = lambda n, q, o: [sem(n, q, o)] * 3
v('Q1', 'ObtainSemaphoreList', parts=ALL('1', '0', 'M'))
v('Q2', 'ObtainSemaphoreList', parts=ALL('2', '1', 'M'))
v('Q7', 'ReleaseSemaphoreList', parts=ALL('1', '0', 'M'))
v('Q8', 'ReleaseSemaphoreList', parts=ALL('0', 'FFFF', '-'))
v('Q3a', None, **sem('1', '0', 'M'))
v('Q3b', None, **sem('1', '1', 'T', '*M'))
v('Q3c', None, **sem('1', '0', 'M'))
v('Q3d', None, **sem('0', '0', 'M'))
v('Q3e', None, parts=ALL('1', '0', 'M'))
v('Q5', None, parts=ALL('1', '0', 'M'))
v('Q4a', None, **sem('0', '0', 'M'))
v('Q4b', None, **sem('0', '0', 'M'))
v('Q4c', None, parts=ALL('1', '0', 'M'))
v('Q6', None, parts=ALL('1', '0', 'M'))
v('N2', 'AddSemaphore', in_='1', **sem('0', 'FFFF', '-'))
D13['N2'] = None
v('N3', 'FindSemaphore', r='S')
v('N4', 'FindSemaphore', r='0')
v('N5', 'FindSemaphore', r='0')
v('N7', 'RemSemaphore', in_='1', dl='1')
v('N6', 'RemSemaphore', in_='0')
for i in ('N3', 'N4', 'N5', 'N6', 'N7'):
    D13[i] = None     # they follow the working AddSemaphore of N2
v('P1', 'Procure', d='1', lk='1', b='0', q='-', rq='-', t2='5')
v('P2', 'Procure', d='0', lk='1', b='1', q='2', rq='-', t2='5')
v('P3', 'Vacate', lk='2', b='0', q='-', rq='2', t2='7')
v('P4', 'Vacate', lk='-', b='FFFF', q='-', rq='2', t2='7')

TOK = re.compile(r'(\w+)=(\S*)')


def parse(line):
    head, *parts = line.split(' |')
    ident = head.split(' ', 1)[0]
    fields = dict(TOK.findall(head[len(ident):]))
    xs = re.findall(r' x=(\S+)', head)
    return ident, fields, [dict(TOK.findall(p)) for p in parts], xs


def regs(x):
    return set() if x == '-' else {x[i:i + 2] for i in range(0, len(x), 2)}


def shex(t):
    return -int(t[1:], 16) if t.startswith('-') else int(t, 16)


def order_ok(o, pri):
    """AddMemList inserts after every header of equal or higher priority (Enqueue)."""
    items = [(t[0], shex(t[1:])) for t in o.split(',')]
    idx = [k for k, (t, _) in enumerate(items) if t == 'N']
    if len(idx) != 1:
        return False
    k = idx[0]
    return all(p >= pri for _, p in items[:k]) and all(p < pri for _, p in items[k + 1:])


def main():
    mode, path = sys.argv[1], sys.argv[2]
    lines = [l.rstrip() for l in open(path, encoding='latin-1')]
    seen = {}
    for l in lines:
        if not l or l.startswith('MSP') or l.startswith('Y'):
            if l.startswith('Y'):
                seen.setdefault(l.split(' ', 1)[0], l)
            continue
        ident = l.split(' ', 1)[0]
        seen.setdefault(ident, l)
    fails = 0
    out = []
    for ident, (fn, exp) in E.items():
        exp = dict(exp)
        if mode == 'check13' and ident in D13:
            if D13[ident] is None:
                out.append('SKIP %s (this ROM only)' % ident)
                continue
            exp.update(D13[ident])
        if ident not in seen:
            out.append('FAIL %s missing' % ident)
            fails += 1
            continue
        _, got, parts, xs = parse(seen[ident])
        bad = []
        want_parts = exp.pop('parts', None)
        for k, want in exp.items():
            if k == 'x':
                continue
            g = got.get(k)
            if want == 'order':
                if g is None or not order_ok(g, shex(got.get('p', '0'))):
                    bad.append('o=%s' % g)
            elif want == '=v':
                if g != got.get('v'):
                    bad.append('v=%s ref=%s' % (got.get('v'), g))
            elif g != want:
                bad.append('%s=%s (want %s)' % (k, g, want))
        if want_parts is not None:
            for n, (wp, gp) in enumerate(zip(want_parts, parts + [{}] * 3)):
                for k, want in wp.items():
                    if gp.get(k) != want:
                        bad.append('sem%d %s=%s (want %s)' % (n, k, gp.get(k), want))
        if fn:
            allowed = regs(''.join(ALLOWED[fn].split()))
            if 'x' in exp:
                allowed = regs(exp['x']) if exp['x'] != '-' else set()
            fns = [fn, 'CopyMem'] if ident == 'B0' else [fn]
            if not xs:
                bad.append('x missing')
            for x in xs[:len(fns)]:
                extra = regs(x) - allowed
                if extra:
                    bad.append('x=%s (not allowed: %s)' % (x, ' '.join(sorted(extra))))
        if bad:
            fails += 1
            out.append('FAIL %s: %s   | %s' % (ident, '; '.join(bad), seen[ident]))
        else:
            out.append('PASS %s' % ident)
    # TypeOfMem: per system header "0,0,A,A,0"; fixed addresses 0
    for ident, l in sorted(seen.items()):
        if not ident.startswith('Y'):
            continue
        _, got, _, xs = parse(l)
        if ident == 'Yf':
            ok = got.get('v') == '0,0,0,0'
        else:
            a = got.get('a')
            ok = got.get('v') == '0,0,%s,%s,0' % (a, a) and not (regs(xs[0] if xs else '?') - regs('d0a0'))
        fails += not ok
        out.append(('PASS %s' if ok else 'FAIL %s: ' + l) % ident)
    if 'Y0' not in seen:
        out.append('FAIL Y missing')
        fails += 1
    print('\n'.join(out))
    print('%s: %d vector(s) failed' % ('FAIL' if fails else 'OK', fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
