#!/usr/bin/env python3
"""tests/mvport_check.py <mvport.txt>: decodes the MakeVPort fragments printed by tests/mvport_probe.s and compares
them with the probed vectors of docs/analysis/graphics-display-v34.md §4.4 (and the colour count of §4.2).

Fragment layout (src/graphics/graphics.i): (register, value) word pairs; a pseudo-WAIT is ($FFFF, line), (hpos, 0),
($01FE, 0); the end marker is ($FFFF, $8000). Plane addresses are the probe's fake $2i000 / $28000 + i*$1000."""
import sys

REG = {0x8E: "DIWSTRT", 0x90: "DIWSTOP", 0x92: "DDFSTRT", 0x94: "DDFSTOP", 0x102: "BPLCON1", 0x108: "BPL1MOD",
       0x10A: "BPL2MOD", 0xE0: "BPL1PTH", 0xE2: "BPL1PTL", 0xE4: "BPL2PTH", 0xE6: "BPL2PTL"}
P0, Q0 = 0x20000, 0x28000

# (DIWSTRT, DIWSTOP, DDFSTRT, DDFSTOP, BPLCON1, BPL1MOD, BPL2MOD, BPL1PT, BPL2PT or None, top BPLCON0, colours, L0)
EXPECT = {
    1: (0x0581, 0x40C1, 0x38, 0xD0, 0x00, 0, 0, P0, None, 0x2200, 4, -1),
    2: (0x0581, 0x40C1, 0x3C, 0xD0, 0x00, 0, 0, P0, None, 0xC200, 16, -1),
    3: (0x0581, 0x40C1, 0x30, 0xD0, 0xBB, 0x26, 0x26, P0 + 0xF0, None, 0x2200, 4, -1),
    4: (0x0581, 0x40C1, 0x34, 0xD0, 0x77, -4, -4, P0 - 2, None, 0xA200, 4, -1),
    5: (0x0577, 0x40B7, 0x30, 0xC8, 0x66, 0, 0, P0, None, 0x1200, 2, -1),
    6: (0x0581, 0x40D1, 0x38, 0xD8, 0x00, 8, 8, P0, None, 0x1200, 2, -1),
    7: (0x0595, 0x405D, 0x40, 0xA0, 0x44, 0x0E, 0x0E, P0, None, 0x1200, 2, -1),
    8: (0x0585, 0x40C5, 0x38, 0xD0, 0x44, 0, 0, P0, None, 0x1200, 2, -1),
    9: (0x0581, 0x40C0, 0x30, 0xD0, 0xD0, -2, -2, P0 - 2, Q0, 0x4600, 16, -1),
    10: (0x0581, 0x40C1, 0x38, 0xD0, 0x00, 0, 0, P0, None, 0x6A00, 16, -2),
    11: (0x0581, 0x40C1, 0x38, 0xD0, 0x00, 0, 0, P0, None, 0x6200, 32, -2),
    12: (0x0581, 0x40C1, 0x38, 0xD0, 0x00, 0, 0, P0, Q0, 0x6600, 16, -1),
    13: (0x0581, 0x40C1, 0x38, 0xD0, 0x00, 0x28, 0x28, P0, None, 0x1204, 2, -2),
}
NAMES = ("DIWSTRT", "DIWSTOP", "DDFSTRT", "DDFSTOP", "BPLCON1", "BPL1MOD", "BPL2MOD", "BPL1PT", "BPL2PT",
         "top BPLCON0", "colours", "L0")


def decode(words):
    regs, waits, colours, top, i = {}, [], 0, None, 0
    pairs = [(words[j], words[j + 1]) for j in range(0, len(words) - 1, 2)]
    while i < len(pairs):
        r, v = pairs[i]
        if r == 0xFFFF:
            if v == 0x8000:
                break
            waits.append(v - 0x10000 if v & 0x8000 else v)
            i += 3
            continue
        if 0x180 <= r < 0x1C0:
            colours += 1
        elif r == 0x100 and len(waits) == 2 and top is None:
            top = v
        elif r in REG and REG[r] not in regs:
            regs[REG[r]] = v
        i += 1
    s16 = lambda v: v - 0x10000 if v & 0x8000 else v
    pt = lambda h, l: (regs[h] << 16 | regs[l]) if h in regs and l in regs else None
    return (regs.get("DIWSTRT"), regs.get("DIWSTOP"), regs.get("DDFSTRT"), regs.get("DDFSTOP"), regs.get("BPLCON1"),
            s16(regs.get("BPL1MOD", 0)), s16(regs.get("BPL2MOD", 0)), pt("BPL1PTH", "BPL1PTL"),
            pt("BPL2PTH", "BPL2PTL"), top, colours, waits[0] if waits else None)


def main():
    bad = 0
    seen = set()
    for line in open(sys.argv[1]):
        f = line.split()
        if len(f) < 2 or f[0] != "MV" or not f[1].isalnum() or f[1] in ("BEGIN", "END"):
            continue
        n = int(f[1], 16)
        got = decode([int(w, 16) for w in f[2:]])
        exp = EXPECT[n]
        seen.add(n)
        diffs = []
        for k, (e, g) in enumerate(zip(exp, got)):
            if k == 8 and e is None:
                continue
            if e != g:
                diffs.append("%s %s (spec %s)" % (NAMES[k], hex(g) if isinstance(g, int) and g >= 0 else g,
                                                  hex(e) if isinstance(e, int) and e >= 0 else e))
        print("row %2d: %s" % (n, "OK" if not diffs else "; ".join(diffs)))
        bad += bool(diffs)
    missing = set(EXPECT) - seen
    if missing:
        print("missing rows:", sorted(missing))
    print("MVPORT %s" % ("OK" if not bad and not missing else "FAIL"))
    return 1 if bad or missing else 0


if __name__ == "__main__":
    sys.exit(main())
