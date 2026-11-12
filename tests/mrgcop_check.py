#!/usr/bin/env python3
"""tests/mrgcop_check.py <mrgcop.txt>: decodes the hardware lists printed by tests/mrgcop_probe.s and compares them
with docs/analysis/graphics-display-v34.md §5.2-5.4 (MrgCop).

A list is cut into groups: a WAIT and the MOVEs that follow it. The WAIT sequence is compared exactly; the MOVEs of
a group are compared as a set (the MOVE order inside MakeVPort's settings block is not specified), except where §5.4
gives the order of two MOVEs of the same register. Our lists start with 16 SPRxPT MOVEs (sprite pointers, ignored
here). Plane addresses are the probe's fake $2i000."""
import sys

END = (0xFFFF, 0xFFFE)


KEEP = []


def parse(path):
    lists, addrs = {}, {}
    for line in open(path):
        f = line.split()
        if len(f) == 3 and f[:2] == ["MC", "KEEP"]:
            KEEP.append(f[2])
            continue
        if len(f) < 3 or f[0] != "MC" or f[1] in ("BEGIN", "END"):
            continue
        n, kind, words = int(f[1], 16), f[2], [int(w, 16) for w in f[3:]]
        if kind in "LS" and any(len(w) != 4 for w in f[3:]):
            FAIL.append("case %d %s: serial line damaged (characters lost on the way), run the probe again" % (n, kind))
        if kind == "A":
            addrs[n] = (words[0], words[1])
        else:
            lists[(n, kind)] = [(words[i], words[i + 1]) for i in range(0, len(words) - 1, 2)]
    return lists, addrs


def groups(pairs):
    """-> [(wait_word or None, [moves])], sprite pointer MOVEs ($120-$13E) dropped."""
    out, cur = [], (None, [])
    for a, b in pairs:
        if a & 1 and b == 0xFFFE:
            out.append(cur)
            cur = (a, [])
            if (a, b) == END:
                break
        elif not 0x120 <= a <= 0x13E:
            cur[1].append((a, b))
    out.append(cur)
    return [g for g in out if g[0] is not None or g[1]]


def settings(colours, diwstop, ddfstrt, ddfstop, bplcon0, mod, planes):
    s = {(0x180 + 2 * i, c) for i, c in enumerate(colours)}
    s |= {(0x8E, 0x0581), (0x90, diwstop), (0x92, ddfstrt), (0x94, ddfstop), (0x100, bplcon0), (0x102, 0),
          (0x108, mod), (0x10A, mod)}
    for i in range(planes):
        a = 0x20000 + i * 0x1000
        s |= {(0xE0 + 4 * i, a >> 16), (0xE2 + 4 * i, a & 0xFFFF)}
    return s


DEF4 = [0x000, 0xF00, 0x0F0, 0xFF0]
FAIL = []


def check(n, got, want):
    """want: [(wait, moves)] where moves is a set (order free), a list (order kept) or None (not checked)."""
    gw = [w for w, _ in got]
    ww = [w for w, _ in want]
    if gw != ww:
        FAIL.append("case %d: WAITs %s, expected %s" % (n, " ".join("%04X" % w if w is not None else "-" for w in gw),
                                                     " ".join("%04X" % w if w is not None else "-" for w in ww)))
        return
    for (w, gm), (_, wm) in zip(got, want):
        if wm is None:
            continue
        if isinstance(wm, list):
            ok = gm == wm
        else:
            ok = set(gm) == wm and len(gm) == len(wm)
        if not ok:
            FAIL.append("case %d, after WAIT %04X: %s, expected %s" % (
                n, w, " ".join("%04X %04X" % m for m in gm),
                " ".join("%04X %04X" % m for m in (wm if isinstance(wm, list) else sorted(wm)))))


def main():
    lists, addrs = parse(sys.argv[1])
    for n in range(1, 10):
        if (n, "L") not in lists:
            FAIL.append("case %d: no list" % n)
    if FAIL:
        print("\n".join(FAIL))
        return 1
    g = {n: groups(lists[(n, "L")]) for n in range(1, 10)}
    off = {(0x100, 0x0200)}

    # §5.3: the probed list, word for word apart from the MOVE order of the settings block
    check(1, g[1], [(0x2B01, settings(DEF4, 0x40C1, 0x38, 0xD0, 0x0200, 0, 2) | {(0x104, 0x24)}),
                    (0x2C01, {(0x100, 0x2200)}), (0xF401, off), (0xFFFF, set())])
    # §5.3, 256 lines: line 255 crossed at $DE, then line $12C noted $2C
    check(2, g[2], [(0x2B01, None), (0x2C01, {(0x100, 0x2200)}), (0xFFDF, set()), (0x2C01, off),
                    (0xFFFF, set())])
    # §5.2 point 4: HIRES 4 planes with DDFSTOP $D4 cross line 255 at the last DDFSTRT
    regs = dict(g[3][0][1]) if len(g[3]) > 1 else {}
    top = dict(g[3][1][1]).get(0x100, 0) if len(g[3]) > 1 else 0    # last BPLCON0 before line 255
    if regs.get(0x94) != 0xD4 or top & 0xF000 != 0xC000:
        FAIL.append("case 3: not a HIRES 4-plane DDFSTOP $D4 ViewPort (%s)" % regs)
    else:
        hx = 0xFF01 | (regs[0x92] & 0xFE)
        check(3, g[3], [(0x2B01, None), (0x2C01, {(0x100, 0xC200)}), (hx, set()), (0x2C01, off),
                        (0xFFFF, set())])
    # §5.3 UCopList, positions relative to the top of the ViewPort
    check(4, g[4], [(0x2B01, None), (0x2C01, {(0x100, 0x1200)}), (0x3601, {(0x180, 0xF00)}),
                    (0x4041, {(0x180, 0x0F0)}), (0xF401, off), (0xFFFF, set())])
    # §5.4 stacked, one empty line ($90) and one preparation line ($91)
    check(5, g[5], [(0x2B01, None), (0x2C01, {(0x100, 0x1200)}), (0x9001, off),
                    (0x9101, None),
                    (0x9201, {(0x100, 0x9200)}), (0xF601, off), (0xFFFF, set())])
    # §5.4 contiguous: vp1's settings during vp0's last line, then vp1 on and at once off again
    check(6, g[6], [(0x2B01, None), (0x2C01, {(0x100, 0x1200)}), (0x8F01, None),
                    (0x9001, [(0x100, 0x1200), (0x100, 0x0200)]), (0xF401, off), (0xFFFF, set())])
    # §5.2: a UCopList WAIT below its ViewPort goes after the bottom WAIT
    check(7, g[7], [(0x2B01, None), (0x2C01, {(0x100, 0x1200)}), (0x9001, off),
                    (0xC201, {(0x180, 0x00F)}), (0xFFFF, set())])
    # §5.3 interlaced: both lists, plane pointers one row apart, COP2LC to the other list
    if (8, "S") not in lists or 8 not in addrs:
        FAIL.append("case 8: no short-frame list")
    else:
        lof, shf = addrs[8]
        gs = groups(lists[(8, "S")])
        for gg, pt, other in ((g[8], 0x0000, shf), (gs, 0x0028, lof)):
            check(8, gg, [(0x2B01, None), (0x2C01, {(0x100, 0x1204)}),
                          (0xF401, {(0x100, 0x0204), (0x84, other >> 16), (0x86, other & 0xFFFF)}),
                          (0xFFFF, set())])
            regs = dict(gg[0][1])
            if (regs.get(0x108), regs.get(0xE0), regs.get(0xE2)) != (0x28, 2, pt):
                FAIL.append("case 8: BPL1MOD/BPL1PT %s, expected 0028 0002 %04X" % (
                    [regs.get(0x108), regs.get(0xE0), regs.get(0xE2)], pt))
    # §7.3 on the displayed list: SetRGB4 and ScrollVPort (RxOffset 3) patch the MOVEs where MrgCop put them
    check(9, g[9], [(0x2B01, None), (0x2C01, {(0x100, 0x2200)}), (0xF401, off), (0xFFFF, set())])
    regs = dict(g[9][0][1]) if g[9] else {}
    if (regs.get(0x182), regs.get(0x102)) != (0x0FF, 0xDD):
        FAIL.append("case 9: COLOR01 / BPLCON1 %s, expected 00FF 00DD" % [regs.get(0x182), regs.get(0x102)])
    for n in range(1, 10):
        print("MC %d: %s" % (n, " | ".join(("%04X" % w if w is not None else "-") + " " +
                                          " ".join("%04X:%04X" % m for m in ms) for w, ms in g[n])))
    if KEEP != ["00000001"]:
        FAIL.append("MC KEEP %s: a View with no CopList must keep its lists (§5.1)" % KEEP)
    print("\n".join(FAIL) if FAIL else "OK: 9 cases equal to graphics-display §5.2-5.4 and §7.3, lists kept without CopList")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
