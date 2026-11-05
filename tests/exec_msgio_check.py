#!/usr/bin/env python3
"""tests/exec_msgio_check.py - expected results of tests/exec_msgio_probe.s.

Spec: docs/analysis/exec-messages-io-v34.md (exec messages, ports, I/O, libraries, devices), test vectors of §8 and
probe of §9.
  exec_msgio_check.py check <log.txt> [--alert ok|none]    this ROM's model, one PASS/FAIL line per vector
  exec_msgio_check.py check13 <log.txt> [--alert ok|none]  the 1.3 values only (oracle run on the real ROM)

The probe prints "<id> key=hex ..." lines; "MAP" gives the addresses of its structures, so an expected value may be
a symbol ("M1", "P+24"). Every line ending with the wrapper's fields is also checked for rm=0 (D2-D7/A2-A4 kept),
ne=FFFF (IDNestCnt/TDNestCnt -1 after the call) and e6=1 (A6 = ExecBase on return) unless the vector says otherwise.
Registers that §5.2 gives as "changed"/"leak" are printed by the probe but not checked.
This ROM's deliberate differences from 1.3 (docs/PLAN.md, rank 12) are the OURS entries; they are tagged "ours".
"""
import re
import sys

M0V, M1V, M8V = 0x11110000, 0x11110001, 0x11110008
JD1, JD2, JA0, JA1, JA2 = 0xD1D1D1D1, 0xD2D2D2D2, 0xA0A0A0A0, 0xA1A1A1A1, 0xA2A2A2A2
SKIP = object()


def ge(n):
    return lambda v, line, sym: v >= n


def lt(n):
    return lambda v, line, sym: v < n


def low_byte(n):
    return lambda v, line, sym: v & 0xFF == n


def low_word_of(key):
    """low word = upper word of the line's value <key> (the expected sum, stored in the upper half of lib_Sum)"""
    return lambda v, line, sym: v & 0xFFFF == line[key] >> 16


def same_as(key):
    return lambda v, line, sym: v == line[key]


EXP = {}


def e(cid, **kw):
    EXP[cid] = kw


# V1 PutMsg / GetMsg
e('P1', ty=5, sg=1, L=['M1'])
e('P2', L=['M1', 'M2'])
e('P3', ty=5, sg=0, L=['M3'])
e('P4', sc=1, sa1=0xDA7A0000, sa6='EX', ssr=0x2000, it=2, ty=5, L=['M1'])
e('P5', b1=1)
e('P6', sg=1)
e('P8', ac=1, ra0='ACT3', ra1='P', rd0=low_byte(3), rhd='M1', rid=0,
  d0=0x13579BDF, d1=0x2468ACE0, a0=0x0A0A0A0A, a1=0x0B0B0B0B)
for i in (9, 10, 11, 12):
    e('P%d' % i, ty=5, sg=0, sc=0, ac=0, L=['M1'])
for f in ('04', '40', '80'):
    e('P13_' + f, ty=5, sg=1, sc=0, ac=0, fl=int(f, 16))
e('P13_81', ty=5, sg=0, sc=1, ac=0, fl=0x81)
e('P13_82', ty=5, sg=0, sc=0, ac=0, fl=0x82)
for f in ('07', '83'):
    e('P13_' + f, ty=5, sg=0, sc=0, ac=1, fl=int(f, 16))
e('G1', d0='M1', ty=5, su='M2', d1=M1V, sg=1)
e('G2', d0='M2', ty=5, su='M3', d1=M1V, sg=1)
e('G3', d0='M3', ty=5, su='P+24', d1=M1V, sg=1)
e('G4', d0=0, d1=M1V, a0='P+20', a1='P+24')
# V2 ReplyMsg
e('R1', ty=7, sg=1, L=['M1'])
e('R2', ty=6, ls=0, lp=0, d0=0, d1=M1V, a0=M8V, a1='M2')
e('R3', ty=7, sc=1, L=['M1'])
e('R4', ty=7, sg=0, L=['M1'])
e('R5', t1=7, t2=7, L=['M1', 'M2'])
e('R6', ty=7, sg=0, L=['M1'])
# V3 WaitPort
e('WP1', d0='M1', a1='M1', d1=M1V, a0='P', sg=1, L=['M1'])
e('WP2', d0='M1', a1='M1', d1=M1V, a0='P', sg=0, L=['M1'])
for w in ('WP3', 'WP4'):
    e(w, d0='TR', a1='TR', ty=7, d1=same_as('mk'), sg=0, L=['TR'], el=ge(80000))
# V4 ports
e('AP1', ty=0x33, lh='R+24', lt=0, lp='R+20', **{'in': 1}, d1b=5, a1='R')
e('AP2', O=['S1', 'S3', 'R', 'S0', 'S2'], rm=SKIP, ne=SKIP, e6=SKIP)
e('AP3a', d0='R', a1='NPORT')
e('AP3b', d0=0)
e('AP4', d0=M0V, d1=M1V, f=0)
# V5 I/O
e('ADV1', ty=0x77, fl=0, sm=0x5A5A5A5A, hd='FD', d1b=3)
e('IO1', b2=lambda v, line, sym: (v >> 8) & 0xFF == 1, bt=0x55, ba6='FD', ba1='IOR', bn=0xFFFF, bc=1,
  d0=0, ty=0x55, fl=1, L=[])
e('IO2', d0=5)
e('IO3', d0=0xFFFFFFFE)
e('IO4', ty=7, L=[], sg=0, d0=0, el=ge(80000))
e('IO5', ty=0x55, fl=1, d0=0)
e('IO6', ty=7, L=[], sg=1, d0=4)
e('IO7', ty=7, L=['IOR'], fl=1, d0=0)
e('IO8', d1=JD1, d2=JD2, a0=JA0, a1='IOR', a2=JA2, rm=0x41)
e('IO9', d0=M0V, d1=JD1, d2=JD2, a0=JA0, a1=JA1, a2=JA2, rm=0x41)
e('IO10a')
e('IO10b')
for s in 'abc':
    e('IO11' + s, bf=0, d0=M0V)
e('WI1', d0=0xFFFFFFF9, L=['IOR'], sg=1, d1=M1V, a0=M8V, a1='IOR')
e('WI2s', d0=3, ty=7, L=[], sg=1)
e('WI2c', d0=3, ty=7, L=[], sg=0)
e('WI3', xp='Y', ys='X', d0=0)
e('CK10', d0=0)
e('WI4', ty=7, L=[], sg=0, d0=0, el=ge(80000))
e('CK11', d0='TR')
e('WI5', ty=7, L=[], sg=0, d0=0, el=ge(80000))
for i, r in enumerate(['IOR', 'IOR', 0, 'IOR', 0, 0, 'IOR', 'IOR', 0], 1):
    e('CK%d' % i, d0=r, d1=M1V, a0=M8V, a1='IOR')
e('AB1a', d0=0xAB0127ED, fl=0, ty=5, er=0, ba1='IOR', ba6='FD', bn=0xFFFF, bc=1)
e('AB1b', d0=0xAB0127ED, fl=1, ty=7, er=0, ba1='IOR', ba6='FD', bn=0xFFFF, bc=1)
e('AB2a', ty=7, er=0xFE, sg=1)
e('AB2b', d0=0xFFFFFFFE, L=[], el=lt(50000))
e('AB3', d0=7, d1=JD1, a1=JA1, rm=SKIP)
# V6 devices
e('OD1', bd0=2, bd1=3, ba0='FD', ba1='IOR', ba6='FD', bn=0xFF00, bc=1, b0='FD', b1=0, b2=0x9C9D9E00, d0=0, a0='FD')
e('OD2', d0=0xFFFFFFFD, dv='FD')
e('OD3', d0=5, dv='FD')
e('OD4', d0=0)
e('OD5', d0=0xFFFFFFFF, b0=0, b1=0x98999A9B, b2=0x9C9D9EFF, a0=0)
e('OD6', d0=0)
e('OD7', d0=0xFFFFFFFF, c1=1, c3=0, dv='FD')
e('OD8', d0=0, d1=JD1, a1=JA1, rm=SKIP)
e('CD1', d0=same_as('es'), ba6='FD', ba1='IOR', bn=0xFF00, bc=1, dv='FD', un=0x12345678)
e('RD1', d0=same_as('es'), ba6='FD', ba1='FD', bd0='FD', bn=0xFF00, bc=1, **{'in': 1})
e('ADV2', fl=4, sm=same_as('es'))
# V7 libraries, checksum, resources
e('AL1', ty=0x66, fl=0, sm=0x5A5A5A5A)
for i, ok in enumerate([1, 1, 1, 0, 1, 0, 1, 1, 1, 1], 1):
    e('OL%d' % i, d0='FL1' if ok else 0, oc=ok)
for i, ok in enumerate([0, 0, 0, 1, 0, 1, 1, 0], 1):
    e('OLP%d' % i, d0='FL1' if ok else 0, oc=ok)
e('OLE', ba6='FL1', ba0='FL1', bd0='FL1', ba1='NLIB', bd1='NLIB', bn=0xFF00, d0='FL1', d1='NLIB', a0='FL1')
e('OL12', d0='FL1')
e('OL13a', d0='FL2', c1=0, c2=1)
e('OL13b', d0='FL1', c1=1, c2=0)
e('OL15', d0=0, c2=0)
e('OL14a', d0=0)
e('OL14b', d0=0x1234)
e('OL16', d0=0x1234, rm=SKIP)
e('OL17', d0=same_as('gb'), o35=lambda v, line, sym: v == 0 or line['gv'] >= 35)
e('OL19', d0=0)
e('CL1', d0=same_as('es'), ba6='FL1', ba1='FL1', bn=0xFF00, bc=1)
e('RL1', d0=same_as('es'), ba6='FL1', ba1='FL1', bd0='FL1', bn=0xFF00, bc=1, **{'in': 1})
e('AL2a', fl=4, sm=same_as('es'))
e('AL2b', fl=2, sm=0x5A5A5A5A)
e('AL2c', fl=1, sm=0x5A5A5A5A)
e('AL2d', fl=0xFB, sm=0x5A5A5A5A)
e('AL3', fl=4, sm=same_as('es'))
e('SL1', fl=0, sm=0x5A5A5A5A, d0=M0V, d1=M1V)
e('SL2', fl=2, sm=0x5A5A5A5A, d0=M0V, d1=M1V)
e('SL3', fl=4, sm=same_as('es'), d0=lambda v, line, sym: v == (M0V & 0xFFFF0000) | (line['es'] >> 16),
  d1=low_word_of('es'))
e('SL4', fl=4, sm=same_as('es'), d0=M0V, d1=low_word_of('es'))
e('SL5', fl=4, sm=same_as('es'))
e('AR1', ty=0x44, hd='RS', d1b=7)
e('OR1a', d0='RS', ver=5, ty=0x44, oc=0, a1='NRES')
e('OR1b', d0=0)
e('RR1', d0=M0V, d1=M1V, **{'in': 0})

# This ROM's deliberate differences from 1.3 (docs/PLAN.md, rank 12): key -> expected value on our side.
OURS = {
    'N1': dict(d0=0),         # CloseLibrary(NULL) returns 0 (1.3: illegal-instruction Guru, not reproduced)
    # P4: the softint runs from the level-1 interrupt here (SR $2100), 1.3 runs it at IPL 0 (SR $2000); the
    # softint dispatch belongs to exec-scheduling-v34 §8, not to this page.
    'P4': dict(ssr=0x2100),
}
# vectors that only exist on our side (not run on 1.3)
OURS_ONLY = {'N1'}

STD = dict(rm=0, ne=0xFFFF, e6=1)


def parse(path):
    lines = {}
    order = []
    for raw in open(path, encoding='latin-1'):
        raw = raw.rstrip('\n')
        if not raw or raw.startswith('MLP'):
            continue
        parts = raw.split(' ')
        cid = parts[0]
        d = {}
        for p in parts[1:]:
            if '=' not in p:
                continue
            k, v = p.split('=', 1)
            if k in ('L', 'O'):
                d[k] = [int(x, 16) for x in v.split(',') if x]
            else:
                d[k] = int(v, 16)
        lines[cid] = d
        order.append(cid)
    return lines, order


def resolve(x, sym):
    if isinstance(x, str):
        m = re.fullmatch(r'([A-Z0-9]+)(?:\+(\d+))?', x)
        if m.group(1) not in sym:
            return None
        return sym[m.group(1)] + int(m.group(2) or 0)
    return x


def name(v, sym):
    for k, a in sym.items():
        if a == v and k not in ('SIGP',):
            return k
    return '%08X' % v


def check(path, mode, alert):
    lines, order = parse(path)
    sym = lines.get('MAP')
    if sym is None:
        print('FAIL MAP line missing')
        return 1
    fails = 0
    total = 0
    exp_ids = list(EXP) + ([] if mode == 'check13' else sorted(OURS_ONLY))
    for cid in exp_ids:
        exp = dict(STD)
        exp.update(EXP.get(cid, {}))
        tags = []
        if mode == 'check' and cid in OURS:
            exp.update(OURS[cid])
            tags.append('ours')
        total += 1
        line = lines.get(cid)
        if line is None:
            print('FAIL %s missing' % cid)
            fails += 1
            continue
        bad = []
        for k, want in exp.items():
            if want is SKIP:
                continue
            if k not in line:
                if k in STD:
                    continue
                bad.append('%s absent' % k)
                continue
            got = line[k]
            if callable(want):
                ok = want(got, line, sym)
                shown = 'rule'
            elif isinstance(want, list):
                w = [resolve(x, sym) for x in want]
                ok = got == w
                shown = '[' + ','.join(name(x, sym) for x in w) + ']'
                got_s = '[' + ','.join(name(x, sym) for x in got) + ']'
            else:
                w = resolve(want, sym)
                ok = got == w
                shown = want if w is None else name(w, sym) if isinstance(want, str) else '%X' % w
            if not ok:
                if not isinstance(want, list):
                    got_s = name(got, sym) if isinstance(want, str) else '%X' % got
                bad.append('%s=%s want %s' % (k, got_s, shown))
        tag = ' (%s)' % ','.join(tags) if tags else ''
        if bad:
            fails += 1
            print('FAIL %s%s: %s' % (cid, tag, '; '.join(bad)))
        else:
            print('PASS %s%s' % (cid, tag))
    if alert is not None:
        total += 1
        if alert == 'ok':
            print('PASS AL4 (dead-end alert 81000003)')
        else:
            fails += 1
            print('FAIL AL4: no alert 81000003 on the serial port')
    print('%d vectors, %d failed' % (total, fails))
    return 1 if fails else 0


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ('check', 'check13'):
        print(__doc__)
        return 2
    alert = None
    if '--alert' in sys.argv:
        alert = sys.argv[sys.argv.index('--alert') + 1]
    return check(sys.argv[2], sys.argv[1], alert)


if __name__ == '__main__':
    sys.exit(main())
