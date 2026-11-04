#!/usr/bin/env python3
"""tests/graster_check.py - case tables and expected results of tests/graster_probe.s.

Spec: docs/analysis/graphics-raster-v34.md (SetRast, RectFill, ScrollRaster, SetAPen/SetBPen/SetDrMd).
  graster_check.py gen <file.i>     writes the case tables included by the probe
  graster_check.py check <log.txt>  compares the probe output with the model, one PASS/FAIL line per vector

The model follows the spec, except where this ROM deliberately differs from 1.3 (docs/PLAN.md, rank 10):
reversed RectFill bounds draw nothing; without a layer RectFill wraps linearly only inside each plane; no
1024-row / 64-word truncation; ScrollRaster without a layer clamps a negative min corner to 0; SIMPLE-layer damage
is exact and existing damage follows the content (-dx, -dy). Those vectors are tagged "ours" in the output.
"""
import re
import sys

W, H = 64, 16                     # no-layer BitMap: 64 x 16 x 2
LW, LH = 64, 32                   # layer screen BitMap: 64 x 32 x 2

# minterm bytes per DrawMode & 7, indexed f + 2 b (spec §2.2)
MT = [[0x2A, 0xEA, 0x2A, 0xEA], [0x0A, 0xCA, 0x3A, 0xFA], [0x6A] * 4, [0x5A] * 4,
      [0x8A, 0xBA, 0x8A, 0xBA], [0x0A, 0x3A, 0xCA, 0xFA], [0x9A] * 4, [0x5A] * 4]


def minterms(fg, bg, mode):
    return [MT[mode & 7][((fg >> i) & 1) + 2 * ((bg >> i) & 1)] for i in range(8)]


def apply_mt(m, b, c):
    """Destination bit after a minterm where A = 1: g(B, C) read from bits 7..4."""
    return (m >> (4 + 2 * b + c)) & 1


# area patterns (word offsets into the probe's pattern block)
PATS = {'none': None, 'f0f0': [0xF0F0, 0x0F0F], '8001': [0x8001], 'diag': [0x8000, 0x4000, 0x2000, 0x1000],
        'f000': [0xF000, 0x0F00], 'multi': [0xFF00, 0xFF00, 0xF0F0, 0x0F0F]}
PSZ = {'none': 0, 'f0f0': 1, '8001': 0, 'diag': 2, 'f000': 1, 'multi': -1}
PORDER = ['f0f0', '8001', 'diag', 'f000', 'multi']


def pat_offset(name):
    if name == 'none':
        return -1
    off = 0
    for p in PORDER:
        if p == name:
            return off
        off += 2 * len(PATS[p])
    raise KeyError(name)


def pattern_bit(name, plane, x, y):
    if name == 'none':
        return 1
    words = PATS[name]
    sz = PSZ[name]
    n = 1 << abs(sz)
    base = plane * n if sz < 0 else 0
    w = words[base + (y % n)]
    return (w >> (15 - (x % 16))) & 1


BGT = {'clr': 0, 'bg': 1, 'content': 2, 'c3': 3}


def background(kind, w=W, h=H):
    img = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if kind == 'bg':
                img[y][x] = (x // 8) % 4
            elif kind == 'content':
                img[y][x] = ((x * 7 + y * 3) ^ (x >> 2)) % 4
            elif kind == 'c3':
                img[y][x] = 3
    return img


FN = {'rect': 0, 'setrast': 1, 'scroll': 2}
AREAOUTLINE = 8

# no-layer cases: id, name, bg kind, fg, bg, mode, mask, pattern, aol, flags OR, LinePtrn, function, args, ours
CASES = []


def case(name, bgk='clr', fg=1, bgp=0, mode=1, mask=0xFF, pat='none', aol=0xFF, flags=0, lptrn=0xFFFF,
         fn='rect', args=(0, 0, 0, 0, 0, 0), ours=False):
    CASES.append(dict(id=len(CASES) + 1, name=name, bgk=bgk, fg=fg, bgp=bgp, mode=mode, mask=mask, pat=pat,
                      aol=aol, flags=flags, lptrn=lptrn, fn=fn, args=tuple(args) + (0,) * (6 - len(args)),
                      ours=ours))


# R2 RectFill basics (spec §3.1, §8.2)
case('R2 A3 (2,1)-(9,3)', fg=3, args=(2, 1, 9, 3))
case('R2 A3 (5,1)-(5,1)', fg=3, args=(5, 1, 5, 1))
case('R2 A3 (60,6)-(70,6) wrap', fg=3, args=(60, 6, 70, 6))
case('R2 A3 (-3,9)-(2,9) wrap', fg=3, args=(-3, 9, 2, 9))
case('R2 A3 (0,14)-(5,17) past the plane', fg=3, args=(0, 14, 5, 17), ours=True)
# R3 reversed bounds (§3.2): 1.3 draws garbage except in the same-word case; we draw nothing
case('R3 A3 (50,1)-(49,1)', fg=3, args=(50, 1, 49, 1))
case('R3 A3 (16,4)-(15,4)', fg=3, args=(16, 4, 15, 4), ours=True)
case('R3 A3 (20,1)-(12,3)', fg=3, args=(20, 1, 12, 3), ours=True)
case('R3 A3 (30,3)-(35,1)', fg=3, args=(30, 3, 35, 1), ours=True)
# R4 modes x pattern (§3.4)
for p in ('none', 'f0f0'):
    for m in range(8):
        case('R4 mode %d %s A1 B2 bg' % (m, p), bgk='bg', fg=1, bgp=2, mode=m, pat=p, args=(0, 1, 63, 6))
# R5 pattern phase (§3.5)
case('R5 8001 n0 JAM1 (3,2)-(40,2)', mode=0, pat='8001', args=(3, 2, 40, 2))
case('R5 4 words n2 JAM1 (0,1)-(15,6)', mode=0, pat='diag', args=(0, 1, 15, 6))
case('R5 F000/0F00 n1 JAM1 (5,3)-(30,5)', mode=0, pat='f000', args=(5, 3, 30, 5))
for fg, bgp, m in ((3, 0, 1), (1, 0, 0), (2, 1, 1), (0, 3, 1), (1, 2, 2), (3, 0, 0), (3, 0, 4), (3, 0, 5)):
    case('R5 multi A%d B%d mode %d bg' % (fg, bgp, m), bgk='bg', fg=fg, bgp=bgp, mode=m, pat='multi',
         args=(0, 1, 63, 6))
# R6 Mask and pens (§3.3)
case('R6 A5 B6 JAM2 solid', fg=5, bgp=6, args=(0, 1, 63, 6))
case('R6 A5 B6 JAM2 F0F0', fg=5, bgp=6, pat='f0f0', args=(0, 1, 63, 6))
case('R6 A3 JAM2 Mask1 bg', bgk='bg', fg=3, mask=1, args=(0, 1, 63, 6))
case('R6 A0 JAM2 Mask2 bg', bgk='bg', fg=0, mask=2, args=(0, 1, 63, 6))
case('R6 COMPLEMENT Mask1 bg', bgk='bg', mode=2, mask=1, args=(0, 1, 63, 6))
case('R6 A3 Mask0 bg', bgk='bg', fg=3, mask=0, args=(0, 1, 63, 6))
# R7 outline (§3.7)
case('R7 JAM2 A1 AOl2 (2,1)-(12,5)', aol=2, flags=AREAOUTLINE, args=(2, 1, 12, 5))
case('R7 COMPLEMENT on 3 AOl2 (2,1)-(12,5)', bgk='c3', mode=2, aol=2, flags=AREAOUTLINE, args=(2, 1, 12, 5))
case('R7 JAM2 A1 B3 AOl2 F0F0 LinePtrn AAAA (2,1)-(21,6)', bgp=3, aol=2, flags=AREAOUTLINE, pat='f0f0',
     lptrn=0xAAAA, args=(2, 1, 21, 6))
for m in (1, 2):
    for r in ((40, 2, 40, 2), (44, 1, 45, 6), (50, 1, 50, 6)):
        case('R7 degenerate mode %d (%d,%d)-(%d,%d)' % ((m,) + r), mode=m, aol=2, flags=AREAOUTLINE, args=r)
case('R7 COMPLEMENT two rows (54,3)-(60,4)', mode=2, aol=2, flags=AREAOUTLINE, args=(54, 3, 60, 4))
case('R7 JAM1 A1 AOl2 Mask1 (2,1)-(12,5)', mode=0, mask=1, aol=2, flags=AREAOUTLINE, args=(2, 1, 12, 5))
case('R7 COMPLEMENT reversed (9,3)-(2,3)', mode=2, aol=2, flags=AREAOUTLINE, args=(9, 3, 2, 3))
# R8 SetRast (§4)
case('R8 SetRast(2) bg A1 COMPLEMENT', bgk='bg', mode=2, fn='setrast', args=(2,))
case('R8 SetRast(5) bg', bgk='bg', fn='setrast', args=(5,))
case('R8 SetRast(3) Mask1 bg', bgk='bg', mask=1, fn='setrast', args=(3,))
case('R8 SetRast(0) Mask2 bg', bgk='bg', mask=2, fn='setrast', args=(0,))
case('R8 SetRast(1) Mask0 bg', bgk='bg', mask=0, fn='setrast', args=(1,))
case('R8 SetRast(1) with AreaPtrn', bgk='bg', pat='f0f0', fn='setrast', args=(1,))
# R9 ScrollRaster without a layer (§5.1, §5.2, §8.4): content, BgPen 2, APen 1, JAM2
SR = dict(bgk='content', fg=1, bgp=2, fn='scroll')
for d in ((3, 0), (-3, 0), (0, 2), (0, -2), (5, -3), (0, 0), (32, 0), (0, 8), (32, 8), (33, 0), (-33, 0), (0, 9),
          (0, -9), (33, 1), (1, 9), (50, 0), (-50, 0)):
    case('R9 (%d,%d) on (8,2)-(40,10)' % d, args=d + (8, 2, 40, 10), **SR)
case('R9 (17,1) on (3,1)-(60,14)', args=(17, 1, 3, 1, 60, 14), **SR)
for m in (0, 2, 3, 4, 5, 6):
    case('R9 (3,0) mode %d F0F0' % m, mode=m, pat='f0f0', args=(3, 0, 8, 2, 40, 10),
         **dict(SR, fn='scroll'))
case('R9 (3,1) Mask1', mask=1, args=(3, 1, 8, 2, 40, 10), **SR)
case('R9 (3,0) on (50,2)-(80,4)', args=(3, 0, 50, 2, 80, 4), **SR)
case('R9 (14,0) on (50,2)-(80,4)', args=(14, 0, 50, 2, 80, 4), **SR)
case('R9 (13,0) on (50,2)-(80,4)', args=(13, 0, 50, 2, 80, 4), **SR)
case('R9 (3,0) on (40,2)-(8,10)', args=(3, 0, 40, 2, 8, 10), **SR)
case('R9 (2,2) on (-100,-100)-(200,200)', args=(2, 2, -100, -100, 200, 200), ours=True, **SR)
case('R9 (-3,-2) on (-6,-1)-(20,9)', args=(-3, -2, -6, -1, 20, 9), ours=True, **SR)

# R1 pens and modes (§2, §8.1): op, value; 0 InitRastPort, 1 SetAPen, 2 SetBPen, 3 SetDrMd, 4 Flags, 5 +$1F,
# 6 AOlPen, 7 +$1E. A header is printed after ops 0-3.
R1 = [(0, 0), (1, 3), (1, 5), (1, 0x1234), (1, 0xFFFFFFFE), (2, 7), (1, 1), (2, 0)] + \
     [(3, m) for m in range(8)] + [(1, 2), (2, 1), (3, 4), (3, 5), (3, 0x11), (3, 0xFF), (3, 0x1205)] + \
     [(4, 0xFFF0), (5, 0x44), (6, 0x55), (7, 0x33), (1, 1), (4, 0), (5, 3), (2, 0), (4, 0x0008), (5, 0x80),
      (3, 1)]


def gen(path):
    out = ['; generated by tests/graster_check.py gen - do not edit', 'cases:']
    for c in CASES:
        out.append('                dc.w    %d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s' % (
            c['id'], BGT[c['bgk']], c['fg'], c['bgp'], c['mode'], c['mask'], PSZ[c['pat']],
            pat_offset(c['pat']), c['aol'], c['flags'], c['lptrn'] - (0x10000 if c['lptrn'] >= 0x8000 else 0),
            FN[c['fn']], ','.join(str(a) for a in c['args'])))
    out.append('                dc.w    -1')
    out.append('patterns:')
    for p in PORDER:
        out.append('                dc.w    ' + ','.join('$%04X' % w for w in PATS[p]))
    out.append('PATSZ           EQU %d' % sum(2 * len(PATS[p]) for p in PORDER))
    for p in PORDER:
        out.append('PO_%s EQU %d' % (p.upper(), pat_offset(p)))
    out.append('r1tab:')
    for op, v in R1:
        out.append('                dc.l    %d,$%08X' % (op, v & 0xFFFFFFFF))
    out.append('                dc.l    -1')
    with open(path, 'w') as f:
        f.write('\n'.join(out) + '\n')


# ---------------------------------------------------------------- model


class RP:
    def __init__(self):
        self.fg, self.bg, self.mode, self.mask, self.aol = 0xFF, 0, 1, 0xFF, 0xFF
        self.flags, self.c1e, self.c1f = 0, 0, 0
        self.mt = [0xCA] * 8
        self.cp = (0, 0)

    def setter(self):
        self.mt = minterms(self.fg, self.bg, self.mode)
        self.flags |= 1
        self.c1f = 15


def put(img, x, y, plane, bit):
    if bit:
        img[y][x] |= 1 << plane
    else:
        img[y][x] &= ~(1 << plane)


def fill_pixel(img, x, y, px, py, fg, bg, mode, mask, pat, depth=2):
    """Pixel (px, py) of the BitMap drawn as RastPort pixel (x, y) (pattern phase)."""
    for i in range(depth):
        if not (mask >> i) & 1:
            continue
        m = MT[mode & 7][((fg >> i) & 1) + 2 * ((bg >> i) & 1)]
        b = pattern_bit(pat, i, x, y)
        c = (img[py][px] >> i) & 1
        put(img, px, py, i, apply_mt(m, b, c))


def rectfill(img, x0, y0, x1, y1, fg, bg, mode, mask, pat, w=W, h=H):
    """No layer: linear addressing clipped to each plane; reversed bounds draw nothing (ours)."""
    if x1 < x0 or y1 < y0:
        return
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            lin = y * w + x
            if 0 <= lin < w * h:
                fill_pixel(img, x, y, lin % w, lin // w, fg, bg, mode, mask, pat)


def draw_line(img, rp, x1, y1, lptrn, w=W, h=H):
    """Draw JAM1 FgPen from cp to (x1, y1), horizontal or vertical (outline sides), counter +$1F."""
    x0, y0 = rp.cp
    dx, dy = x1 - x0, y1 - y0
    m = max(abs(dx), abs(dy))
    sx = (dx > 0) - (dx < 0)
    sy = (dy > 0) - (dy < 0)
    for k in range(m + 1):
        if (lptrn >> ((rp.c1f - k) & 15)) & 1:
            x, y = x0 + k * sx, y0 + k * sy
            if 0 <= x < w and 0 <= y < h:
                for i in range(2):
                    if (rp.mask >> i) & 1:
                        put(img, x, y, i, (rp.fg >> i) & 1)
    rp.c1f = (rp.c1f - m) & 0xFF
    rp.flags &= ~1
    rp.cp = (x1, y1)


def model_case(c):
    img = background(c['bgk'])
    rp = RP()
    rp.fg, rp.bg, rp.mode = c['fg'] & 0xFF, c['bgp'] & 0xFF, c['mode'] & 0xFF
    rp.setter()
    rp.cp = (33, 7)
    rp.c1f = 15
    rp.mask, rp.aol = c['mask'], c['aol']
    rp.flags |= c['flags']
    a = c['args']
    if c['fn'] == 'rect':
        if c['flags'] & AREAOUTLINE:
            x0, y0, x1, y1 = a[:4]
            if rp.mode & 2:
                rectfill(img, x0 + 1, y0 + 1, x1 - 1, y1 - 1, rp.fg, rp.bg, rp.mode, rp.mask, c['pat'])
            else:
                rectfill(img, x0, y0, x1, y1, rp.fg, rp.bg, rp.mode, rp.mask, c['pat'])
            ofg = rp.fg
            rp.fg = rp.aol
            rp.cp = (x0, y0)
            rp.c1f = 15
            for p in ((x0, y1), (x1, y1), (x1, y0), (x0, y0)):
                draw_line(img, rp, p[0], p[1], c['lptrn'])
            rp.fg = ofg
        else:
            rectfill(img, a[0], a[1], a[2], a[3], rp.fg, rp.bg, rp.mode, rp.mask, c['pat'])
    elif c['fn'] == 'setrast':
        for y in range(H):
            for x in range(W):
                for i in range(2):
                    if (rp.mask >> i) & 1:
                        put(img, x, y, i, (a[0] >> i) & 1)
    else:
        img = scroll_nolayer(img, rp, *a)
    return img, rp


def scroll_nolayer(img, rp, dx, dy, x0, y0, x1, y1):
    if dx == 0 and dy == 0:
        return img
    x1, y1 = min(x1, W - 1), min(y1, H - 1)
    if abs(dx) >= x1 - x0 + 1 or abs(dy) >= y1 - y0 + 1:
        return img
    x0, y0 = max(x0, 0), max(y0, 0)
    new = [r[:] for r in img]
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            sx, sy = x + dx, y + dy
            for i in range(2):
                if not (rp.mask >> i) & 1:
                    continue
                if x0 <= sx <= x1 and y0 <= sy <= y1:
                    put(new, x, y, i, (img[sy][sx] >> i) & 1)
                else:
                    put(new, x, y, i, (rp.bg >> i) & 1)
    return new


# ---------------------------------------------------------------- parsing

def parse_dump(lines, i, rows, wbytes=8):
    img = []
    for r in range(rows):
        f = lines[i + r].split()
        p0, p1 = int(f[1], 16), int(f[2], 16)
        bits = wbytes * 8
        img.append([((p0 >> (bits - 1 - x)) & 1) | (((p1 >> (bits - 1 - x)) & 1) << 1) for x in range(bits)])
    return img


HDR = re.compile(r'cp=(\w+),(\w+) fl=(\w+) 1e=(\w+) 1f=(\w+) fg=(\w+) bg=(\w+) md=(\w+) mk=(\w+) ao=(\w+) mt=(\w+)')


def parse_hdr(line):
    m = HDR.search(line)
    if not m or len(m.group(11)) != 16:
        return None
    v = [int(g, 16) for g in m.groups()[:10]]
    return dict(cp=(v[0] - (0x10000 if v[0] & 0x8000 else 0), v[1] - (0x10000 if v[1] & 0x8000 else 0)),
                flags=v[2], c1e=v[3], c1f=v[4], fg=v[5], bg=v[6], mode=v[7], mask=v[8], aol=v[9],
                mt=[int(m.group(11)[2 * k:2 * k + 2], 16) for k in range(8)])


def img_diff(got, exp, w, h, care=None):
    bad = []
    for y in range(h):
        for x in range(w):
            if care and not care(x, y):
                continue
            if got[y][x] != exp[y][x]:
                bad.append((x, y, got[y][x], exp[y][x]))
    return bad


def fmt_bad(bad):
    return ' '.join('(%d,%d)=%d/%d' % b for b in bad[:6]) + (' ...%d' % len(bad) if len(bad) > 6 else '')


class Report:
    def __init__(self):
        self.n = self.fails = 0

    def res(self, name, ok, why='', ours=False):
        self.n += 1
        if not ok:
            self.fails += 1
        print('%s %s%s%s' % ('PASS' if ok else 'FAIL', name, ' [ours]' if ours else '', '' if ok else ': ' + why))


def check_hdr(h, rp, cp=None):
    errs = []
    want = dict(cp=cp if cp else rp.cp, flags=rp.flags, c1f=rp.c1f, fg=rp.fg, bg=rp.bg, mode=rp.mode,
                mask=rp.mask, aol=rp.aol, mt=rp.mt)
    for k, v in want.items():
        if h[k] != v:
            errs.append('%s=%s want %s' % (k, h[k], v))
    return errs


# ------------------------------------------------------------- layer model (R10)

def layer_content(w, h):
    return [[((x * 7 + y * 3) ^ (x >> 2)) % 4 for x in range(w)] for y in range(h)]


def check_layers(blocks, rep):
    LX, LY, LWD, LHT = 5, 3, 46, 25          # back layer at screen (5,3)-(50,27)

    def inlayer(x, y):
        return LX <= x < LX + LWD and LY <= y < LY + LHT

    # (a) RectFill / SetRast in a SMART layer under a SIMPLE one
    for tag, col in (('a-rect', 3), ('a-setrast', 2)):
        for when in ('before', 'after'):
            key = 'L %s %s' % (tag, when)
            if key not in blocks:
                rep.res(key, False, 'missing')
                continue
            got = blocks[key]['img']
            exp = [[0] * LW for _ in range(LH)]
            for y in range(LH):
                for x in range(LW):
                    hidden = 30 <= x <= 63 and 0 <= y <= 15
                    if inlayer(x, y) and (when == 'after' or not hidden):
                        exp[y][x] = col
            bad = img_diff(got, exp, LW, LH)
            rep.res(key, not bad, fmt_bad(bad))
    # (b) pattern phase in layer coordinates
    for key in ('L b-phase', 'L b-phase-uncovered'):
        if key not in blocks:
            rep.res(key, False, 'missing')
            continue
        exp = [[0] * LW for _ in range(LH)]
        for ly in range(0, 4):
            for lx in range(0, 21):
                if pattern_bit('f000', 0, lx, ly):
                    exp[ly + LY][lx + LX] = 1
        bad = img_diff(blocks[key]['img'], exp, LW, LH)
        rep.res(key, not bad, fmt_bad(bad))
    # (c) ScrollRaster in a SMART layer alone
    cont = layer_content(LWD, LHT)
    for key, blk in blocks.items():
        if not key.startswith('L c '):
            continue
        dx, dy, x0, y0, x1, y1 = blk['args']
        exp_l = scroll_layer(cont, dx, dy, x0, y0, x1, y1, 2, lambda x, y: True)[0]
        exp = [[0] * LW for _ in range(LH)]
        for y in range(LHT):
            for x in range(LWD):
                exp[y + LY][x + LX] = exp_l[y][x]
        bad = img_diff(blk['img'], exp, LW, LH)
        rep.res(key, not bad, fmt_bad(bad))
    # (d) SIMPLE layer under SIMPLE front: pixels and exact damage
    for key, blk in blocks.items():
        if not key.startswith('L d '):
            continue
        dx, dy, x0, y0, x1, y1 = blk['args']
        hx0, hy0, hx1, hy1 = blk['hidden']

        def vis(x, y, hx0=hx0, hy0=hy0, hx1=hx1, hy1=hy1):
            return not (hx0 <= x <= hx1 and hy0 <= y <= hy1)
        exp_l, dmg = scroll_layer(cont, dx, dy, x0, y0, x1, y1, 2, vis)
        got = blk['img']
        bad = []
        for y in range(LHT):
            for x in range(LWD):
                if vis(x, y) and got[y + LY][x + LX] != exp_l[y][x]:
                    bad.append((x, y, got[y + LY][x + LX], exp_l[y][x]))
        gd = set()
        for (a, b, c, d) in blk['damage']:
            gd |= {(x, y) for x in range(a, c + 1) for y in range(b, d + 1)}
        refresh = bool(blk['lflags'] & 0x80)
        why = []
        if bad:
            why.append('pixels ' + fmt_bad(bad))
        if gd != dmg:
            why.append('damage got %s want %s' % (rects_of(gd), rects_of(dmg)))
        if refresh != bool(dmg):
            why.append('LAYERREFRESH %d' % refresh)
        rep.res(key, not why, '; '.join(why), ours=True)
    # (e) existing damage follows the content
    for key, blk in blocks.items():
        if not key.startswith('L e '):
            continue
        dx, dy = blk['args'][:2]
        want = {(x - dx, y - dy) for x in range(25, 46) for y in range(0, 13)}
        gd = set()
        for (a, b, c, d) in blk['damage']:
            gd |= {(x, y) for x in range(a, c + 1) for y in range(b, d + 1)}
        rep.res(key, gd == want, 'damage got %s want %s' % (rects_of(gd), rects_of(want)), ours=True)


def rects_of(pts):
    if not pts:
        return '{}'
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return '%d px in (%d,%d)-(%d,%d)' % (len(pts), min(xs), min(ys), max(xs), max(ys))


def scroll_layer(cont, dx, dy, x0, y0, x1, y1, bgp, vis):
    """Layer rules (§5.3): max corner clamped to the layer, min corner not; strips may spill out of the
    rectangle, clipped to the layer; destinations whose source is outside the layer keep their content.
    Returns the new layer image and the exact damage (visible destinations with a hidden source)."""
    lw, lh = len(cont[0]), len(cont)
    x1, y1 = min(x1, lw - 1), min(y1, lh - 1)
    new = [r[:] for r in cont]
    dmg = set()
    cx0, cy0 = max(x0, 0), max(y0, 0)
    for y in range(lh):
        for x in range(lw):
            in_hs = (dx > 0 and x1 - dx + 1 <= x <= x1) or (dx < 0 and x0 <= x <= x0 - dx - 1)
            in_hs = in_hs and y0 <= y <= y1
            in_vs = (dy > 0 and y1 - dy + 1 <= y <= y1) or (dy < 0 and y0 <= y <= y0 - dy - 1)
            in_vs = in_vs and x0 <= x <= x1
            if in_hs or in_vs:
                if vis(x, y):
                    new[y][x] = bgp
                continue
            if not (cx0 <= x <= x1 and cy0 <= y <= y1):
                continue
            sx, sy = x + dx, y + dy
            if not (cx0 <= sx <= x1 and cy0 <= sy <= y1):
                continue
            if not vis(x, y):
                continue
            if vis(sx, sy):
                new[y][x] = cont[sy][sx]
            else:
                dmg.add((x, y))
    return new, dmg


# --------------------------------------------------------------------- check

R0_ALLOWED = {'SetAPen': {'d0', 'd1'}, 'SetBPen': {'d0', 'd1'}, 'SetDrMd': {'d0', 'd1'},
              'SetRast': {'d0', 'd1', 'a0', 'a1'}, 'RectFill': {'d0', 'd1', 'a0', 'a1'},
              'ScrollRaster': {'d0', 'd1', 'a0', 'a1'}}


def check(path):
    lines = [ln.rstrip('\n') for ln in open(path, encoding='latin-1')]
    rep = Report()
    byid = {c['id']: c for c in CASES}
    seen = set()
    blocks = {}
    r1 = []
    i = 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith('R0 '):
            f = ln.split()
            fn = f[1]
            regs = {t.split('=')[0] for t in f[2:]}
            extra = regs - R0_ALLOWED.get(fn, set())
            rep.res('R0 %s registers' % fn, not extra, 'changed ' + ','.join(sorted(extra)))
        elif ln.startswith('R1 '):
            r1.append(parse_hdr(ln))
        elif ln.startswith('T'):
            cid = int(ln[1:].split()[0])
            c = byid[cid]
            seen.add(cid)
            h = parse_hdr(ln)
            try:
                got = parse_dump(lines, i + 1, H)
                g = lines[i + 1 + H]
            except (IndexError, ValueError):
                h = None
            if h is None:
                rep.res('T%d %s' % (cid, c['name']), False, 'garbled serial output, rerun')
                i += 1
                continue
            exp, rp = model_case(c)
            errs = check_hdr(h, rp)
            bad = img_diff(got, exp, W, H)
            if bad:
                errs.append('pixels ' + fmt_bad(bad))
            if g.strip() != 'G':
                errs.append('guards written:' + g[1:60])
            rep.res('T%d %s' % (cid, c['name']), not errs, '; '.join(errs), ours=c['ours'])
            i += 1 + H
        elif ln.startswith('L '):
            m = re.match(r'(L [^:]*?)(?: args=([-\d,]+))?(?: hidden=([-\d,]+))?(?: lflags=(\w+))?(?: dmg=(.*))?$', ln)
            key = m.group(1).strip() + (' ' + m.group(2) if m.group(2) else '')
            blk = dict(args=tuple(int(v) for v in m.group(2).split(',')) if m.group(2) else (),
                       hidden=tuple(int(v) for v in m.group(3).split(',')) if m.group(3) else (),
                       lflags=int(m.group(4), 16) if m.group(4) else 0, damage=[])
            if m.group(5):
                for r in m.group(5).split():
                    blk['damage'].append(tuple(int(v) for v in r.split(',')))
            if i + 1 < len(lines) and re.match(r'^[0-9A-F]{2} ', lines[i + 1]):
                try:
                    blk['img'] = parse_dump(lines, i + 1, LH)
                except (IndexError, ValueError):
                    blk['img'] = [[-1] * LW for _ in range(LH)]
                i += LH
            blocks[key] = blk
        elif ln.startswith('S '):
            f = dict(t.split('=') for t in ln.split()[2:])
            name = ln.split()[1]
            want = {'rect1280': 1280, 'rect10-1100': 1091, 'rect1100rows': 1100, 'setrast1280': 2560,
                    'setrast1100': 1100, 'scroll1280': 0, 'setrast20x3': 12, 'guard20x3': 0}[name]
            rep.res('R11 %s' % name, int(f['n']) == want, 'n=%s want %d' % (f['n'], want),
                    ours=name not in ('setrast20x3', 'guard20x3'))
        i += 1
    for cid in byid:
        if cid not in seen:
            rep.res('T%d %s' % (cid, byid[cid]['name']), False, 'missing')
    # R1: replay the steps
    rp = RP()
    k = 0
    for op, v in R1:
        if op == 0:
            rp = RP()
            rp.mask, rp.fg, rp.aol, rp.mode = 0xFF, 0xFF, 0xFF, 1
            rp.flags, rp.c1f, rp.c1e = 0, 0, 0
        elif op == 1:
            rp.fg = v & 0xFF
            rp.setter()
        elif op == 2:
            rp.bg = v & 0xFF
            rp.setter()
        elif op == 3:
            rp.mode = v & 0xFF
            rp.setter()
        elif op == 4:
            rp.flags = v
        elif op == 5:
            rp.c1f = v
        elif op == 6:
            rp.aol = v
        elif op == 7:
            rp.c1e = v
        if op <= 3:
            name = 'R1 #%d %s(%s)' % (k, ['InitRastPort', 'SetAPen', 'SetBPen', 'SetDrMd'][op], hex(v))
            if k >= len(r1):
                rep.res(name, False, 'missing')
            else:
                h = r1[k]
                if h is None:
                    rep.res(name, False, 'garbled serial output, rerun')
                    k += 1
                    continue
                errs = []
                fields = ['mt', 'fg', 'bg', 'mode', 'aol'] if op == 0 else \
                    ['mt', 'fg', 'bg', 'mode', 'aol', 'flags', 'c1f', 'c1e']
                for f in fields:
                    if h[f] != getattr(rp, f):
                        errs.append('%s=%s want %s' % (f, h[f], getattr(rp, f)))
                rep.res(name, not errs, '; '.join(errs))
            k += 1
    check_layers(blocks, rep)
    print('TOTAL %d vectors, %d FAIL' % (rep.n, rep.fails))
    return rep.fails


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'gen':
        gen(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == 'check':
        sys.exit(1 if check(sys.argv[2]) else 0)
    else:
        sys.exit(__doc__)
