#!/usr/bin/env python3
"""tests/rawdofmt_check.py - case table and expected results of tests/rawdofmt_probe.s.

Spec: docs/analysis/exec-rawdofmt-v34.md (exec RawDoFmt, LVO -522), test vectors of §7 and probe of §8.
  rawdofmt_check.py gen <file.i>        writes the case table included by the probe
  rawdofmt_check.py check <log.txt>     compares the probe output with this ROM's model, one PASS/FAIL per vector
  rawdofmt_check.py check13 <log.txt>   same, against the 1.3 values only (oracle run on the real ROM)

The model is the spec, except where this ROM deliberately differs from 1.3 (docs/PLAN.md, rank 11): a format that
ends inside a conversion stops at its terminator (no NUL sent as a character, no scan past the end); D0 on exit is
the next data pointer; PutChProc gets D0 with the upper 24 bits clear and the caller's A6; A1 on exit is the data
cursor even when PutChProc changed A1. Those checks are tagged "ours" in the output.
"""
import sys

# string area of the probe: name -> (offset, bytes); every string longword-aligned
STRS = {'hello': (0, b'hello\0'), 'abc': (8, b'abc\0'), '': (12, b'\0'), 'B3': (16, b'\x03abcXYZ\0'),
        'B0': (24, b'\0'), 'B5': (28, b'\x05Hello\0')}

# probe kinds
STORE, COUNT, A6ODD, REC, BUMP = 0, 1, 2, 3, 4
TOL = {'d0': 5, 'd1': 6, 'd4': 7, 'd7': 8, 'a0': 9, 'a1': 10}
STACK, ZERO0, NULLFMT = 11, 12, 13

CASES = []


def W(v):
    return ('W', v & 0xFFFF)


def L(v):
    return ('L', v & 0xFFFFFFFF)


def P(name):
    return ('P', name)


def B(name):
    return ('B', name)


def case(cid, fmt, data, out, read, kind=STORE, ours_out=None, ours_read=None, raw=None):
    """out: expected bytes (final NUL included) or a character count for COUNT; raw: exact format bytes."""
    if isinstance(fmt, str):
        fmt = fmt.encode('latin-1')
    if raw is None:
        raw = fmt + b'\0'
    if isinstance(out, str):
        out = out.encode('latin-1') + b'\0'
    if isinstance(ours_out, str):
        ours_out = ours_out.encode('latin-1') + b'\0'
    CASES.append(dict(id=cid, raw=raw, data=list(data), out=out, read=read, kind=kind,
                      ours_out=ours_out, ours_read=ours_read))


def S(n):
    return ' ' * n


# V1 plain text, %% and the terminator
case('E1', '', [], '', 0)
case('E2', 'abc', [], 'abc', 0)
case('E3', '%%', [], '%', 0)
case('E4', 'a%%b%%', [], 'a%b%', 0)
# V2 %d and %ld
case('D1', '%d', [W(0x04D2)], '1234', 2)
case('D2', '%d', [W(0xFFFB)], '-5', 2)
case('D3', '%d', [W(0x8000)], '-32768', 2)
case('D4', '%d', [W(0)], '0', 2)
case('D5', '%d', [W(0xFFFF)], '-1', 2)
case('D6', '%ld', [L(0xFFFFFFFF)], '-1', 4)
case('D7', '%ld', [L(0x80000000)], '-2147483648', 4)
case('D8', '%ld', [L(0x7FFFFFFF)], '2147483647', 4)
case('D9', '%ld', [L(0)], '0', 4)
case('D10', '%d|', [W(1), W(2)], '1|', 2)
case('D11', '%ld', [L(0x186A0)], '100000', 4)
case('M25', '%ld|', [L(0x80000001)], '-2147483647|', 4)
case('M50', '%d', [W(0x8000)], '-32768', 2)
case('M39', '%ldx%dx', [L(0x10000), W(0x7FFF)], '65536x32767x', 6)
# V3 %x and %lx
case('X1', '%x', [W(0xABCD)], 'ABCD', 2)
case('X2', '%lx', [L(0xDEADBEEF)], 'DEADBEEF', 4)
case('X5', '%x', [W(0)], '0', 2)
case('X6', '%x', [W(0xFFFF)], 'FFFF', 2)
case('X7', '%lx', [L(0)], '0', 4)
case('X8', '%08lx', [L(0x1F)], '0000001F', 4)
case('X9', '%8lx|', [L(0xABC)], S(5) + 'ABC|', 4)
case('X10', '%-8lx|', [L(0xABC)], 'ABC' + S(5) + '|', 4)
case('X11', '%04x', [W(0xA)], '000A', 2)
case('M16', '%08x|', [W(0x8000)], '00008000|', 2)
case('M17', '%lx|', [L(0x0A0B0C0D)], 'A0B0C0D|', 4)
case('M26', '%x|', [W(0x1234), W(0x5678)], '1234|', 2)
case('M51', '%-06x|', [W(0xF)], 'F00000|', 2)
case('M52', '%0x|', [W(0)], '0|', 2)
case('M54', '%08lx.%08lx', [L(0xB), L(0xC026E2)], '0000000B.00C026E2', 8)
# V4 %c and %lc
case('C1', '%c', [W(0x41)], 'A', 2)
case('C2', '%c%c', [W(0x41), W(0x42)], 'AB', 4)
case('C3', '%lc', [L(0x43)], 'C', 4)
case('C4', '%c', [W(0x4142)], 'B', 2)
case('C5', '%5c|', [W(0x41)], S(4) + 'A|', 2)
case('C6', '%-3c|', [W(0x41)], 'A' + S(2) + '|', 2)
case('C7', '%03c', [W(0x41)], '00A', 2)
case('C8', '%lc', [L(0x41424344)], 'D', 4)
case('M9', '%c|', [W(0)], '|', 2)
case('M24', '%c', [W(0xE9)], '\xE9', 2)
case('M27', '%-5c|', [W(0x41)], 'A' + S(4) + '|', 2)
case('M28', '%.3c|', [W(0x41)], 'A|', 2)
case('M29', '%.0c|', [W(0x41)], 'A|', 2)
case('M45', '%lc%c', [L(0x4142), W(0x43)], 'BC', 6)
case('M46', 'A%cB', [W(0)], 'AB', 2)
case('M47', '%3c|', [W(0)], S(3) + '|', 2)
case('M55', '%c%c%c', [W(0xA), W(0xD), W(0xFF)], '\n\r\xFF', 6)
case('M18', '%05c|', [W(0x2A)], '0000*|', 2)
# V5 %s
case('S1', '%s', [P('hello')], 'hello', 4)
case('S2', '%s|', [P('')], '|', 4)
case('S3', '%8s|', [P('hello')], S(3) + 'hello|', 4)
case('S4', '%-8s|', [P('hello')], 'hello' + S(3) + '|', 4)
case('S5', '%.3s|', [P('hello')], 'hel|', 4)
case('S6', '%8.3s|', [P('hello')], S(5) + 'hel|', 4)
case('S7', '%-8.3s|', [P('hello')], 'hel' + S(5) + '|', 4)
case('S8', '%3s|', [P('hello')], 'hello|', 4)
case('S9', '%08s|', [P('hello')], '000hello|', 4)
case('S10', '%.0s|', [P('hello')], 'hello|', 4)
case('S11', '%.9s|', [P('hello')], 'hello|', 4)
case('S12', '%ls|', [P('hello')], 'hello|', 4)
case('S13', '%5s|', [P('')], S(5) + '|', 4)
case('M3', '%-.2s|', [P('hello')], 'he|', 4)
case('M10', '%10.0s|', [P('abc')], S(7) + 'abc|', 4)
case('M13', '%-1s|', [P('abc')], 'abc|', 4)
case('M14', '%.1s%.1s|', [P('abc'), P('hello')], 'ah|', 8)
case('M21', '%.65537s|', [P('hello')], 'h|', 4)
case('M30', '%05.2s|', [P('hello')], '000he|', 4)
case('M35', '%.32768s|', [P('hello')], 'hello|', 4)
case('M42', '%-8.0s|', [P('abc')], 'abc' + S(5) + '|', 4)
case('M49', '%9.1s|', [P('hello')], S(8) + 'h|', 4)
# V6 field width and flags
case('W1', '%5d|', [W(0x2A)], S(3) + '42|', 2)
case('W2', '%-5d|', [W(0x2A)], '42' + S(3) + '|', 2)
case('W3', '%05d|', [W(0x2A)], '00042|', 2)
case('W4', '%05d|', [W(0xFFD6)], '00-42|', 2)
case('W5', '%-05d|', [W(0x2A)], '42000|', 2)
case('W6', '%0-5d|', [W(0x2A)], '-5d|', 0)
case('W7', '%2d|', [W(0x3039)], '12345|', 2)
case('W8', '%5ld|', [L(0xFFFFFFD6)], S(2) + '-42|', 4)
case('W9', '%012ld|', [L(0xFFFE1DC0)], '00000-123456|', 4)
case('W10', '%30d|', [W(7)], S(29) + '7|', 2)
case('W11', '%1d|', [W(0xFFF9)], '-7|', 2)
case('W12', '%005d|', [W(3)], '00003|', 2)
case('W13', '%10x|', [W(0xBEEF)], S(6) + 'BEEF|', 2)
case('W14', '%-10lx|', [L(0xBEEF)], 'BEEF' + S(6) + '|', 4)
case('W15', '%010lx|', [L(0xBEEF)], '000000BEEF|', 4)
case('M5', '%5ld|', [L(5)], S(4) + '5|', 4)
case('M6', '%--5d|', [W(5)], '-5d|', 0)
case('M7', '%00005d|', [W(5)], '00005|', 2)
case('M8', '%300d|', [W(1)], S(299) + '1|', 2)
case('M11', '%0.2d|', [W(0xFFFB)], '-5|', 2)
case('M12', '%-05ld|', [L(0xFFFFFFFB)], '-5000|', 4)
case('M19', '%-0d|', [W(5)], '5|', 2)
case('M20', '%65536d|', [W(5)], '5|', 2)
case('M33', '%65535d|', [W(5)], '5|', 2)
case('M38', '%2147483648d|', [W(5)], '5|', 2)
case('M40', '%05ld|', [L(0)], '00000|', 4)
# V7 precision on numbers
case('P1', '%.3d|', [W(5)], '5|', 2)
case('P2', '%.2d|', [W(0x3039)], '12|', 2)
case('P3', '%5.1d|', [W(0x7B)], S(4) + '1|', 2)
case('P4', '%.3ld|', [L(0x1E240)], '123|', 4)
case('P5', '%.2x|', [W(0xABCD)], 'AB|', 2)
case('P6', '%8.2ld|', [L(0xFFFFFB2E)], S(6) + '-1|', 4)
case('M1', '%.0d|', [W(0x7B)], '123|', 2)
case('M2', '%.d|', [W(0x7B)], '123|', 2)
case('M15', '%3.5d|', [W(0x8000)], '-3276|', 2)
case('M31', '%-08.3lx|', [L(0xABCDEF)], 'ABC00000|', 4)
case('M37', '%10.8ld|', [L(0xF8A432EB)], S(2) + '-1234567|', 4)
case('M41', '%08.3ld|', [L(0x1E240)], '00000123|', 4)
case('M48', '%.1ld|', [L(0xFFFFFFFB)], '-|', 4)
# V8 conversions V34 does not know
case('U1', '%u', [W(0xFFFF)], 'u', 0)
case('U2', '%lu', [W(0xFFFF), W(0xFFFF)], 'u', 0)
case('U3', '%u|', [W(5)], 'u|', 0)
case('X3', '%X', [W(0xABCD)], 'X', 0)
case('X4', '%lX', [W(0), W(0x1F)], 'X', 0)
case('B1', '%b|', [B('B3')], 'b|', 0)
case('B2', '%b|', [B('B0')], 'b|', 0)
case('B3', '%6b|', [B('B3')], 'b|', 0)
case('B4', '%-6b|', [B('B3')], 'b|', 0)
case('B5', '%.2b|', [B('B5')], 'b|', 0)
case('B6', '%lb|', [B('B5')], 'b|', 0)
case('B7', '%2b|', [B('B5')], 'b|', 0)
case('Q1', '%q|', [W(0x41)], 'q|', 0)
case('Q2', '%y|', [], 'y|', 0)
case('Q3', '%D|', [W(5)], 'D|', 0)
case('Q4', '%i|', [W(5)], 'i|', 0)
case('Q5', '%5q|', [W(5)], 'q|', 0)
case('Q6', '%5%|', [], '%|', 0)
case('Q7', '%l%|', [], '%|', 0)
case('Q8', '%lq|', [], 'q|', 0)
case('Q9', '%-q|', [], 'q|', 0)
case('Q10', '%o|', [W(8)], 'o|', 0)
case('Q11', '%p|', [W(0), W(0x1234)], 'p|', 0)
case('Q12', '%ll d|', [], 'l d|', 0)
case('Q13', '%lld|', [W(0), W(5), W(0), W(6)], 'ld|', 0)
case('Q14', '%h d', [], 'h d', 0)
case('Q15', '%*d|', [W(5), W(9)], '*d|', 0)
case('Q16', '% d|', [W(5)], ' d|', 0)
case('Q17', '%+d|', [W(5)], '+d|', 0)
case('M4', '%l5d|', [W(0), W(5)], '5d|', 0)
case('M22', '%L d|', [W(5)], 'L d|', 0)
case('M32', '%5.3%|', [], '%|', 0)
case('M36', '%-l5d|', [W(0), W(5)], '5d|', 0)
case('M43', '%5%|', [], '%|', 0)
case('M44', '%-5%|', [], '%|', 0)
# V9 data stream layout
case('A1', '%d%d', [W(1), W(2)], '12', 4)
case('A2', '%d%ld', [W(1), L(2)], '12', 6)
case('A3', '%ld%d', [L(1), W(2)], '12', 6)
case('A4', '%d%s', [W(1), P('abc')], '1abc', 6)
case('A5', '%c%ld', [W(0x41), L(7)], 'A7', 6)
case('A6', '%d %x %c %s %b', [W(1), W(0x2A), W(0x5A), P('abc'), B('B3')], '1 2A Z abc b', 10)
case('A7', '%ld%ld%ld', [L(1), L(2), L(3)], '123', 12)
case('M53', 'Workbench release 1.2.  %ld free memory', [L(0x64190)],
     'Workbench release 1.2.  410000 free memory', 4)
# V10 format ending inside a conversion: 1.3 sends the NUL and goes on past it; we stop at the terminator
for cid, f in (('Z1', 'abc%'), ('Z2', 'abc%5'), ('Z3', 'abc%l'), ('Z4', 'abc%-'), ('Z5', 'abc%0'),
               ('Z6', 'abc%.'), ('Z7', 'abc%5.2')):
    case(cid, f, [], b'abc\0\0', 0, ours_out=b'abc\0')
# §2.6 with the bytes that follow the terminator
for cid, raw, data, out, read, ours in (
        ('T1', b'abc%\0XYZ\0', [], b'abc\0XYZ\0', 0, b'abc\0'),
        ('T2', b'abc%5\0XY\0', [], b'abc\0XY\0', 0, b'abc\0'),
        ('T3', b'abc%l\0Q\0', [], b'abc\0Q\0', 0, b'abc\0'),
        ('T4', b'ab%\0%ld!\0', [L(0x4D)], b'ab\x0077!\0', 4, b'ab\0'),
        ('T5', b'a%.\0R\0', [], b'a\0R\0', 0, b'a\0'),
        ('T6', b'x%\0\0', [], b'x\0\0', 0, b'x\0'),
        ('T7', b'a%-\0S\0', [], b'a\0S\0', 0, b'a\0'),
        ('T8', b'a%0\0T\0', [], b'a\0T\0', 0, b'a\0')):
    case(cid, raw.split(b'\0')[0], data, out, read, raw=raw, ours_out=ours, ours_read=0)
# V11 very large widths and limits, counting PutChProc (count includes the final NUL)
for cid, f, d, n, r in (('K1', '%32768d', W(5), 32769, 2), ('K2', '%32769d', W(5), 2, 2),
                        ('K3', '%32768d', W(12), 32769, 2), ('K4', '%32767d', W(5), 32768, 2),
                        ('K5', '%32770d', W(0xFFFB), 3, 2), ('K6', '%40000s', P('abc'), 4, 4),
                        ('K7', '%32770s', P('abc'), 32771, 4), ('K8', '%-32768d', W(5), 32769, 2),
                        ('K9', '%.32768s', P('hello'), 6, 4), ('K10', '%.65535s', P('hello'), 6, 4),
                        ('K11', '%.32769s', P('hello'), 6, 4)):
    case(cid, f, [d], n, r, kind=COUNT)
# V12 NULL pointers (N2/N3: "Z\0" written at address 0 under Disable; N4: A0 = 0)
case('N1', '[%s]', [L(0)], '[]', 4)
case('N2', '[%s]', [L(0)], '[Z]', 4, kind=ZERO0)
case('N3', '[%5s]', [L(0)], '[    Z]', 4, kind=ZERO0)
case('N4', '', [], '', 0, kind=NULLFMT)
# V13 registers
case('R2', '%ld-%s', [L(42), P('abc')], '42-abc', 8, kind=A6ODD)
case('R3', 'Ab%ld%s', [L(-7), P('abc')], 'Ab-7abc', 8, kind=REC)
case('R4', 'xyz', [], 4, 0, kind=BUMP)
R5DATA = [L(123456), P('hello'), W(-9), W(0x1F), P('abc')]
R5OUT = 'A123456BhelloC   -9D1FEabc |'
case('R5', 'A%ldB%sC%5dD%xE%-4s|', R5DATA, R5OUT, 16)
for reg in ('d0', 'd1', 'd4', 'd7', 'a0', 'a1'):
    case('R5 ' + reg, 'A%ldB%sC%5dD%xE%-4s|', R5DATA, R5OUT, 16, kind=TOL[reg],
         ours_read=16 if reg == 'a1' else None)
# R6 stack depth: pairs without / with padding
for cid, f, d in (('R6a', '%ld', L(0x80000000)), ('R6b', '%12ld', L(0x80000000)), ('R6c', '%s', P('hello')),
                  ('R6d', '%-8s|', P('hello')), ('R6e', 'abc', None), ('R6f', '%05d', W(0xFFD6))):
    case(cid, f, [d] if d else [], None, None, kind=STACK)
STACK_MAX = 72                    # 1.3 budget (spec §1.3): a deeper frame would break callers sized for 1.3


def data_bytes(items):
    out = []
    for t, v in items:
        if t == 'W':
            out.append(('W', v))
        elif t == 'L':
            out.append(('L', v))
        elif t == 'P':
            out.append(('P', STRS[v][0]))
        else:
            out.append(('B', STRS[v][0]))
    return out


def gen(path):
    ty = {'W': 0, 'L': 1, 'P': 2, 'B': 3}
    out = ['; generated by tests/rawdofmt_check.py gen - do not edit', 'cases:']
    for c in CASES:
        raw = c['raw']
        if len(raw) > 63:
            raise ValueError(c['id'])
        out.append('                dc.w    %d,%d,%d' % (c['kind'], len(raw), len(c['data'])))
        if raw:
            out.append('                dc.b    ' + ','.join('$%02X' % b for b in raw))
        out.append('                even')
        for t, v in data_bytes(c['data']):
            out.append('                dc.w    %d' % ty[t])
            out.append('                dc.l    $%08X' % v)
    out.append('                dc.w    -1')
    out.append('strs:')
    blob = bytearray(36)
    for off, b in STRS.values():
        blob[off:off + len(b)] = b
    out.append('                dc.b    ' + ','.join('$%02X' % b for b in blob))
    out.append('STRSZ           EQU %d' % len(blob))
    out.append('                even')
    with open(path, 'w') as f:
        f.write('\n'.join(out) + '\n')


class Report:
    def __init__(self):
        self.n = self.fails = 0

    def res(self, name, ok, why='', ours=False):
        self.n += 1
        if not ok:
            self.fails += 1
        print('%s %s%s%s' % ('PASS' if ok else 'FAIL', name, ' [ours]' if ours else '', '' if ok else ': ' + why))


def s32(h):
    v = int(h, 16)
    return v - (1 << 32) if v & 0x80000000 else v


def show(b):
    return ''.join(chr(x) if 32 <= x < 127 and x != 92 else '\\x%02X' % x for x in b)


def check(path, oracle=False):
    rep = Report()
    lines = {}
    for ln in open(path, encoding='latin-1'):
        if ln.startswith('V'):
            f = ln.split()
            lines[int(f[0][1:])] = dict(t.split('=', 1) for t in f[1:] if '=' in t)
    d0ok = d0n = 0
    for i, c in enumerate(CASES):
        name = c['id']
        f = lines.get(i)
        if f is None:
            rep.res(name, False, 'missing')
            continue
        regs = f.get('x', '-')
        errs = [] if regs == '-' else ['registers changed: ' + regs]
        if oracle and name == 'R5 d7':
            errs = []                 # 1.3 does not save D7: the PutChProc's D7 reaches the caller (spec §8a)
        read = s32(f['r'])
        ours = False
        k = c['kind']
        if k == STACK:
            depth = int(f['s'], 16)
            rep.res('%s stack %d bytes (1.3: 68 without padding, 72 with)' % (name, depth),
                    depth <= STACK_MAX and not errs, 'deeper than the 1.3 budget; ' + '; '.join(errs), ours=True)
            continue
        if k in (COUNT, BUMP):
            got = int(f['n'], 16)
        else:
            got = bytes.fromhex(f['o'])
        want, wread = c['out'], c['read']
        if not oracle and c['ours_out'] is not None:
            want, ours = c['ours_out'], True
        if not oracle and c['ours_read'] is not None:
            wread, ours = c['ours_read'], True
        if got != want:
            errs.append('output %s want %s' % ((got, want) if isinstance(got, int) else (show(got), show(want))))
        if read != wread and not (oracle and k in (TOL['a1'], BUMP)):   # R4's PutChProc moves A1 (spec §8a)
            errs.append('read %d want %d' % (read, wread))
        if k == REC:
            errs += check_rec(f, rep, oracle)
        if k == BUMP:
            seen = [s32(v) for v in f['rec'].split(',') if v]
            if seen != [0, 1, 2, 3]:
                errs.append('A3 seen %s want 0,1,2,3' % seen)
        rep.res(name, not errs, '; '.join(errs), ours=ours)
        if k not in (COUNT, BUMP, REC) and k != TOL['a1']:
            d0n += 1
            d0ok += s32(f['q']) == read
    if not oracle:
        rep.res('D0 on exit = next data pointer (%d/%d calls)' % (d0ok, d0n), d0ok == d0n, 'not always', ours=True)
    print('TOTAL %d vectors, %d FAIL' % (rep.n, rep.fails))
    return rep.fails


def check_rec(f, rep, oracle):
    """R3: records d0, a3 - entry a3, a6, caller's SP - SP, a1 - data start per PutChProc call."""
    errs = []
    recs = [r.split(',') for r in f['rec'].split(';') if r]
    want = b'Ab-7abc\0'
    if len(recs) != len(want):
        return ['%d PutChProc calls want %d' % (len(recs), len(want))]
    eb = int(f['eb'], 16)
    hi_ok = a6_ok = True
    for j, (d0, a3, a6, sp, a1) in enumerate(recs):
        d0 = int(d0, 16)
        if d0 & 0xFF != want[j]:
            errs.append('call %d low byte %02X want %02X' % (j, d0 & 0xFF, want[j]))
        if int(a3, 16) != 0:
            errs.append('call %d A3 moved' % j)
        wa1 = 0 if j < 2 else 4 if j < 4 else 8
        if s32(a1) != wa1 and not oracle:   # 1.3 sets A1 only when a conversion fetches: the PutChProc's A1 (§8a)
            errs.append('call %d A1 = data+%d want +%d' % (j, s32(a1), wa1))
        hi_ok &= d0 >> 8 == 0
        a6_ok &= int(a6, 16) == eb
        depth = int(sp, 16)
    if not oracle:
        rep.res('R3 PutChProc D0 upper 24 bits clear (1.3: not cleared)', hi_ok, 'garbage seen', ours=True)
        rep.res('R3 PutChProc A6 = caller\'s A6 (1.3: a stack pointer)', a6_ok, 'A6 changed', ours=True)
    else:
        rep.res('R3 PutChProc A6 differs from ExecBase', not a6_ok, 'A6 = ExecBase')
    rep.res('R3 PutChProc SP = caller\'s SP - %d (1.3: 68)' % depth, depth <= STACK_MAX, 'deeper than 1.3',
            ours=not oracle)
    return errs


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'gen':
        gen(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] in ('check', 'check13'):
        sys.exit(1 if check(sys.argv[2], sys.argv[1] == 'check13') else 0)
    else:
        sys.exit(__doc__)
