#!/usr/bin/env python3
"""tests/ofs_check.py - host-side consistency check of an OFS image (ADF or plain hardfile, no RDB).

Walks the directory tree from the root block (public OFS layout: headers, file extension blocks, data block
tables), checks the block checksums and that no block is used twice, rebuilds the allocation bitmap from what it
found and compares it with the bitmap stored on the disk (bm_pages of the root, then bitmap extension blocks).
Prints the root bitmap flag, the counts and every difference; exit status 0 when the flag is valid and the bitmaps
are equal, 1 otherwise.

Usage: tests/ofs_check.py <image> [--reserved N] [--blocks N] [--offset BYTES] [--ignore-flag]
       tests/ofs_check.py <image> --clear-flag OUT      (copy of the image with the root bitmap flag set to 0)
       tests/ofs_check.py <image> --dump-bitmap OUT     (the stored bitmap bits, one byte per block, for comparisons)
       tests/ofs_check.py <image> --fill A B OUT        (copy with blocks [A, B) marked used in the bitmap, no file:
                                                         the file system then allocates beyond them)
       tests/ofs_check.py <image> --filled A B          (check an image made with --fill: [A, B) counts as used)
"""
import argparse
import struct
import sys

BS = 512
BITS = 127 * 32


class Vol:
    def __init__(self, img, reserved, blocks, offset):
        self.img = img
        self.res = reserved
        self.n = blocks
        self.off = offset
        self.root = (blocks - 1 + reserved) // 2

    def blk(self, k):
        o = self.off + k * BS
        return bytearray(self.img[o:o + BS])

    def L(self, k):
        return struct.unpack('>128l', bytes(self.blk(k)))

    def ok(self, k):
        return self.res <= k < self.n

    def bm_keys(self):
        r = self.L(self.root)
        keys = [k for k in r[79:104]]
        ext = r[104]
        need = (self.n - self.res + BITS - 1) // BITS
        out = []
        exts = []
        for k in keys:
            if len(out) == need:
                break
            out.append(k)
        while len(out) < need and ext:
            exts.append(ext)
            e = self.L(ext)
            for k in e[0:127]:
                if len(out) == need:
                    break
                out.append(k)
            ext = e[127]
        return out, exts


def sum32(b):
    return sum(struct.unpack('>128L', bytes(b))) & 0xFFFFFFFF


def walk(v, errors):
    used = set()

    def mark(k, what):
        if not v.ok(k):
            errors.append('%s: key %d out of range' % (what, k))
            return False
        if k in used:
            errors.append('%s: key %d used twice' % (what, k))
            return False
        used.add(k)
        return True

    mark(v.root, 'root')
    keys, exts = v.bm_keys()
    for k in keys:
        mark(k, 'bitmap')
    for k in exts:
        mark(k, 'bitmap extension')
    stack = [v.root]
    while stack:
        d = stack.pop()
        D = v.L(d)
        for slot in D[6:78]:
            k = slot
            guard = 0
            while k:
                guard += 1
                if guard > v.n:
                    errors.append('hash chain loop at %d' % k)
                    break
                if not mark(k, 'header'):
                    break
                b = v.blk(k)
                H = struct.unpack('>128l', bytes(b))
                if sum32(b) != 0:
                    errors.append('header %d checksum' % k)
                if H[0] != 2 or H[1] != k:
                    errors.append('header %d type/key' % k)
                if H[125] != d:
                    errors.append('header %d parent %d != %d' % (k, H[125], d))
                if H[127] == 2:
                    stack.append(k)
                elif H[127] == -3:
                    tab = H
                    while True:
                        for e in tab[6:78]:
                            if e:
                                mark(e, 'data of %d' % k)
                        ext = tab[126]
                        if not ext:
                            break
                        if not mark(ext, 'extension of %d' % k):
                            break
                        eb = v.blk(ext)
                        if sum32(eb) != 0:
                            errors.append('extension %d checksum' % ext)
                        tab = struct.unpack('>128l', bytes(eb))
                else:
                    errors.append('header %d secondary type %d' % (k, H[127]))
                k = H[124]
    return used


def stored_bits(v):
    keys, _ = v.bm_keys()
    bits = []
    for k in keys:
        b = v.blk(k) if v.ok(k) else bytearray(BS)
        L = struct.unpack('>128L', bytes(b))
        for w in L[1:]:
            for i in range(32):
                bits.append((w >> i) & 1)
    return bits[:v.n - v.res], keys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image')
    ap.add_argument('--reserved', type=int, default=2)
    ap.add_argument('--blocks', type=int)
    ap.add_argument('--offset', type=int, default=0)
    ap.add_argument('--ignore-flag', action='store_true')
    ap.add_argument('--clear-flag')
    ap.add_argument('--dump-bitmap')
    ap.add_argument('--fill', nargs=3)
    ap.add_argument('--filled', nargs=2, type=int)
    a = ap.parse_args()
    img = open(a.image, 'rb').read()
    blocks = a.blocks or (len(img) - a.offset) // BS
    v = Vol(img, a.reserved, blocks, a.offset)
    r = v.L(v.root)
    if a.clear_flag:
        out = bytearray(img)
        o = a.offset + v.root * BS
        rb = bytearray(out[o:o + BS])
        struct.pack_into('>l', rb, 78 * 4, 0)
        struct.pack_into('>l', rb, 20, 0)
        struct.pack_into('>L', rb, 20, (-sum32(rb)) & 0xFFFFFFFF)
        out[o:o + BS] = rb
        open(a.clear_flag, 'wb').write(out)
        print('root %d: bitmap flag cleared -> %s' % (v.root, a.clear_flag))
        return 0
    if a.fill:
        lo, hi, outname = int(a.fill[0]), int(a.fill[1]), a.fill[2]
        out = bytearray(img)
        keys, _ = v.bm_keys()
        for i, k in enumerate(keys):
            o = a.offset + k * BS
            bb = bytearray(out[o:o + BS])
            for blk in range(max(lo, v.res + i * BITS), min(hi, v.res + (i + 1) * BITS)):
                idx = blk - v.res - i * BITS
                w = 4 + (idx // 32) * 4
                val = struct.unpack_from('>L', bb, w)[0] & ~(1 << (idx % 32))
                struct.pack_into('>L', bb, w, val)
            struct.pack_into('>L', bb, 0, 0)
            struct.pack_into('>L', bb, 0, (-sum32(bb)) & 0xFFFFFFFF)
            out[o:o + BS] = bb
        open(outname, 'wb').write(out)
        print('blocks %d-%d marked used -> %s' % (lo, hi - 1, outname))
        return 0
    bits, keys = stored_bits(v)
    if a.dump_bitmap:
        open(a.dump_bitmap, 'wb').write(bytes(bits))
        return 0
    errors = []
    if sum32(v.blk(v.root)) != 0 or r[0] != 2 or r[127] != 1:
        errors.append('root block %d invalid' % v.root)
    used = walk(v, errors)
    if a.filled:
        used |= set(range(a.filled[0], a.filled[1]))
    for k in keys:
        if v.ok(k) and sum32(v.blk(k)) != 0:
            errors.append('bitmap block %d checksum' % k)
    diff = []
    for i, b in enumerate(bits):
        want = 0 if (i + v.res) in used else 1
        if b != want:
            diff.append(i + v.res)
    flag = r[78]
    print('blocks %d root %d bitmap blocks %d (%s) flag %d used %d free %d' %
          (v.n, v.root, len(keys), ','.join(map(str, keys[:4])) + (',...' if len(keys) > 4 else ''),
           flag, len(used), v.n - v.res - len(used)))
    for e in errors[:20]:
        print('ERROR', e)
    if diff:
        print('bitmap differs on %d blocks: %s' % (len(diff), diff[:20]))
    good = not errors and not diff and (flag == -1 or a.ignore_flag)
    print('OFS CHECK %s' % ('OK' if good else 'FAIL'))
    return 0 if good else 1


if __name__ == '__main__':
    sys.exit(main())
