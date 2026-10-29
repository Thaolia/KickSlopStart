#!/usr/bin/env python3
# tests/audit_rom_similarity.py — audit de similarité binaire entre NOTRE ROM et une ROM de référence.
#
# Question posée : notre image contient-elle des suites de code reprises de la ROM de référence
# (Kickstart d'origine), y compris relogées à une autre adresse ? La réponse est chiffrée et comparée
# au niveau « normal » des coïncidences entre codes 68000 sans lien (les témoins).
#
# Méthode
#   1. Découpage. Les ROM brutes sont lues telles quelles (base déduite du vecteur de reset). Les
#      exécutables AmigaDOS (hunks) des témoins sont réduits à leurs hunks CODE ; les mots longs
#      relogés (HUNK_RELOC32) y sont remplacés par un marqueur d'adresse. Un .gz est décompressé.
#   2. Normalisation (ce qui varie forcément d'un build à l'autre est neutralisé, pour ne PAS
#      sous-estimer une copie relogée) :
#        - mot long pointant dans la ROM (fenêtre $F80000-$FFFFFF ou plage de l'image) -> jeton ADDR ;
#        - Bcc/BRA/BSR : déplacement 8 bits effacé ; forme .w : mot d'extension -> jeton DISP ;
#        - DBcc et modes d16(PC)/d8(PC,Xn) : mot d'extension -> DISP ;
#        - remplissages (>= 8 mots identiques consécutifs) -> sentinelles uniques, jamais appariées.
#      Deux flux de jetons :
#        - MOTS : le flux de mots de 16 bits normalisé (aucun décodeur requis, insensible aux
#          désalignements d'un désassemblage linéaire) ;
#        - INSTR (si le module capstone est présent) : désassemblage linéaire 68000, une instruction
#          = un jeton « mnémonique + opérandes », cibles de branchement, déplacements PC et adresses
#          ROM masqués ; variante INSTR-SOUPLE où registres et constantes sont aussi effacés (résiste
#          à un renommage de registres).
#   3. Métriques, pour chaque paire (A, B) :
#        - correspondances exactes maximales (statistiques d'appariement par automate des suffixes
#          de B) : longueur maximale, nombre >= 8/16/32/64 jetons, couverture de A par celles-ci ;
#        - recouvrement de n-grammes (n = 4, 8, 16) : part des n-grammes distincts de A présents
#          dans B (n-grammes contenant une sentinelle exclus).
#      Chaque correspondance est classée d'après les octets de A : texte, faible entropie,
#      en-tête/pied de ROM (format imposé), RomTag, ou code/table. Les statistiques « hors données »
#      ne retiennent que la classe code/table.
#   4. Base sans lien : chaque groupe de témoins est mesuré contre la référence (témoin vs réf.) et
#      contre notre ROM (notre ROM vs témoin). Le seuil « notable » vaut, par défaut, la plus longue
#      correspondance code/table observée entre un témoin de base et la référence, plus un ; --base
#      désigne les groupes réellement sans lien (un groupe Commodore ou AROS sert de témoin séparé).
#   5. Sortie : statistiques, puis la liste des correspondances notables avec leur SEUL emplacement
#      dans la PREMIÈRE ROM (offset, adresse, objet et symbole si une table vlink -M est fournie).
#      Rien n'est jamais affiché de la ROM de référence : ni octets, ni désassemblage, ni offset.
#
# Auto-contrôle (--selftest) : insère en mémoire des fragments de la référence, relogés (adresses
# ROM décalées), dans une copie de la première ROM, et vérifie qu'ils sont retrouvés.
#
# Usage : python3 -I tests/audit_rom_similarity.py <notre_rom> <rom_reference> [témoins...]
#           [--temoin NOM CHEMIN...]... [--base NOM...] [--map table.map] [--seuil N] [--selftest]
#         Un témoin est un fichier (hunk, ROM brute, .gz) ou un répertoire (exécutables hunk trouvés
#         dessous). Les témoins positionnels forment le groupe « temoins ».

import argparse
import gzip
import hashlib
import os
import random
import re
import struct
import sys

ADDR = 0x10201
DISP = 0x10200
BR_SHORT = 0x10000
BR_WORD = 0x10100
KS_WINDOW = (0xF80000, 0x1000000)
RELOC_MARK = 0x00F80000
FILL_RUN = 8
NGRAMS = (4, 8, 16)
THRESHOLDS = (8, 16, 32, 64)
PCREL_NIBBLES = {0x0, 0x1, 0x2, 0x3, 0x4, 0x8, 0x9, 0xB, 0xC, 0xD}

_sentinel = [0]


def sentinel():
    _sentinel[0] -= 1
    return _sentinel[0]


# ---------------------------------------------------------------- lecture des fichiers

class Part:
    """Un bloc d'octets à comparer (une ROM, ou un hunk CODE)."""

    def __init__(self, label, data, base, is_rom):
        self.label = label
        self.data = bytes(data[:len(data) & ~1])
        self.base = base
        self.is_rom = is_rom
        self.rom_range = (base, base + len(data)) if is_rom else None

    def in_rom(self, v):
        if KS_WINDOW[0] <= v < KS_WINDOW[1]:
            return True
        return self.rom_range is not None and self.rom_range[0] <= v < self.rom_range[1]


def read_file(path):
    with open(path, 'rb') as f:
        data = f.read()
    if data[:2] == b'\x1f\x8b':
        data = gzip.decompress(data)
    return data


def parse_hunks(data):
    """Renvoie la liste des hunks CODE (bytearray avec relocations marquées) ; None si pas un hunk."""
    if len(data) < 24 or struct.unpack('>I', data[:4])[0] != 0x3F3:
        return None
    p = 4

    def rd():
        nonlocal p
        v = struct.unpack('>I', data[p:p + 4])[0]
        p += 4
        return v
    try:
        while rd() != 0:
            pass
        rd()
        first, last = rd(), rd()
        for _ in range(last - first + 1):
            if rd() & 0xC0000000 == 0xC0000000:
                rd()
        hunks = []
        cur = None
        while p + 4 <= len(data):
            t = rd() & 0x3FFFFFFF
            if t in (0x3E9, 0x3EA):
                n = rd() & 0x3FFFFFFF
                body = bytearray(data[p:p + 4 * n])
                p += 4 * n
                cur = body if t == 0x3E9 else None
                if cur is not None:
                    hunks.append(cur)
            elif t == 0x3EB:
                rd()
                cur = None
            elif t in (0x3EC, 0x3ED, 0x3EE, 0x3F8):
                while True:
                    n = rd()
                    if n == 0:
                        break
                    rd()
                    for _ in range(n):
                        off = rd()
                        if t == 0x3EC and cur is not None and off + 4 <= len(cur):
                            cur[off:off + 4] = struct.pack('>I', RELOC_MARK)
            elif t in (0x3F7, 0x3FC):
                words = []
                while True:
                    n = struct.unpack('>H', data[p:p + 2])[0]
                    p += 2
                    words.append(n)
                    if n == 0:
                        break
                    words.append(struct.unpack('>H', data[p:p + 2])[0])
                    p += 2
                    for _ in range(n):
                        off = struct.unpack('>H', data[p:p + 2])[0]
                        p += 2
                        if t == 0x3F7 and cur is not None and off + 4 <= len(cur):
                            cur[off:off + 4] = struct.pack('>I', RELOC_MARK)
                if p & 2:
                    p += 2
            elif t == 0x3F0:
                while True:
                    n = rd()
                    if n == 0:
                        break
                    p += 4 * (n & 0xFFFFFF) + 4
            elif t == 0x3F1:
                p += 4 * rd()
            elif t == 0x3F2:
                continue
            else:
                break
        return hunks
    except struct.error:
        return hunks if 'hunks' in locals() else []


def rom_part(label, data):
    pc = struct.unpack('>I', data[4:8])[0]
    base = pc & ~(len(data) - 1) & 0xFFFFFF
    return Part(label, data, base, True)


def looks_like_rom(data):
    return len(data) in (0x40000, 0x80000) and data[:2] in (b'\x11\x11', b'\x11\x14')


def load_parts(path, from_dir=False):
    data = read_file(path)
    hunks = parse_hunks(data)
    name = os.path.basename(path)
    if hunks is not None:
        return [Part('%s#%d' % (name, i), h, 0, False) for i, h in enumerate(hunks) if len(h) >= 4]
    if from_dir:
        return []
    if looks_like_rom(data):
        return [rom_part(name, data)]
    return [Part(name, data, 0, False)]


def collect(paths):
    parts = []
    for path in paths:
        if os.path.isdir(path):
            for root, dirs, files in os.walk(path):
                dirs.sort()
                for fn in sorted(files):
                    parts += load_parts(os.path.join(root, fn), from_dir=True)
        else:
            parts += load_parts(path)
    return parts


# ---------------------------------------------------------------- normalisation

def raw_words(data):
    n = len(data) // 2
    return struct.unpack('>%dH' % n, data[:2 * n])


def fill_mask(w):
    mask = bytearray(len(w))
    i = 0
    while i < len(w):
        j = i
        while j + 1 < len(w) and w[j + 1] == w[i]:
            j += 1
        if j - i + 1 >= FILL_RUN:
            mask[i:j + 1] = b'\x01' * (j - i + 1)
        i = j + 1
    return mask


def word_tokens(part):
    w = raw_words(part.data)
    n = len(w)
    tok = [None] * n
    i = 0
    while i < n:
        if tok[i] is not None:
            i += 1
            continue
        x = w[i]
        if i + 1 < n and part.in_rom((x << 16) | w[i + 1]):
            tok[i] = tok[i + 1] = ADDR
            i += 2
            continue
        hi = x >> 12
        if hi == 6:
            lo = x & 0xFF
            if lo == 0 and i + 1 < n:
                tok[i] = BR_WORD | (x >> 8)
                tok[i + 1] = DISP
            else:
                tok[i] = BR_SHORT | (x >> 8)
        elif (x & 0xF0F8) == 0x50C8 and i + 1 < n:
            tok[i] = x
            tok[i + 1] = DISP
        elif hi in PCREL_NIBBLES and (x & 0x3F) in (0x3A, 0x3B) and i + 1 < n:
            tok[i] = x
            tok[i + 1] = DISP
        else:
            tok[i] = x
        i += 1
    fm = fill_mask(w)
    for k in range(n):
        if fm[k]:
            tok[k] = sentinel()
    return tok, fm


_HEX = re.compile(r'\$([0-9a-f]+)')
_PCDISP = re.compile(r'\$[0-9a-f]+(\(pc)')
_LOOSE_NUM = re.compile(r'-?\$[0-9a-f]+|\b\d+\b')
_LOOSE_REG = re.compile(r'\b(?:[da][0-7]|sp)\b')
_BITOPS = ('btst', 'bchg', 'bclr', 'bset', 'bkpt')


def norm_instr(part, mnem, ops):
    if mnem.startswith('db'):
        ops = ops.split(',')[0] + ',T'
    elif mnem.startswith('b') and not mnem.startswith(_BITOPS):
        ops = 'T'
    elif mnem in ('jmp', 'jsr') and not part.is_rom and '(' not in ops:
        ops = 'T'
    else:
        ops = _PCDISP.sub(r'D\1', ops)
        ops = _HEX.sub(lambda m: 'ROM' if part.in_rom(int(m.group(1), 16)) else m.group(0), ops)
    return mnem + ' ' + ops


class Vocab:
    def __init__(self):
        self.ids = {}

    def get(self, s):
        v = self.ids.get(s)
        if v is None:
            v = self.ids[s] = 0x20000 + len(self.ids)
        return v


def instr_tokens(part, fm, md, vocab_strict, vocab_loose):
    # Désassemblage linéaire par fenêtres (une instruction 68000 fait au plus 10 octets) ;
    # un mot non décodable devient une sentinelle et la lecture reprend au mot suivant.
    data = part.data
    strict, loose, offs, sizes = [], [], [], []
    off = 0
    n = len(data)
    while off < n:
        win_end = min(n, off + 4096)
        for (_addr, size, mnem, ops) in md.disasm_lite(data[off:win_end], part.base + off):
            w0, w1 = off // 2, (off + size + 1) // 2
            if any(fm[w0:w1]):
                s = sentinel()
                strict.append(s)
                loose.append(s)
            else:
                t = norm_instr(part, mnem, ops)
                strict.append(vocab_strict.get(t))
                lt = _LOOSE_REG.sub('r', _LOOSE_NUM.sub('N', t.replace('ROM', 'N').replace('T', 'N')))
                loose.append(vocab_loose.get(lt))
            offs.append(off)
            sizes.append(size)
            off += size
            if win_end < n and off >= win_end - 10:
                break
        if off < n and (win_end == n or off < win_end - 10):
            s = sentinel()
            strict.append(s)
            loose.append(s)
            offs.append(off)
            sizes.append(2)
            off += 2
    return strict, loose, offs, sizes


class Stream:
    """Flux de jetons d'un corpus (concaténation de parts séparées par des sentinelles)."""

    def __init__(self, parts, kind, ctx):
        self.tokens = []
        self.where = []
        for pi, part in enumerate(parts):
            wt, fm = ctx.words(part)
            if kind == 'mots':
                toks = wt
                locs = [(pi, 2 * k, 2) for k in range(len(wt))]
            else:
                st, lo, offs, sizes = ctx.instrs(part, fm)
                toks = st if kind == 'instr' else lo
                locs = [(pi, o, s) for o, s in zip(offs, sizes)]
            self.tokens.extend(toks)
            self.where.extend(locs)
            self.tokens.append(sentinel())
            self.where.append((pi, len(part.data), 0))
        self.parts = parts

    def effective(self):
        return sum(1 for t in self.tokens if t >= 0)


class Context:
    def __init__(self):
        self._w = {}
        self._i = {}
        self.vs = Vocab()
        self.vl = Vocab()
        try:
            import capstone
            self.md = capstone.Cs(capstone.CS_ARCH_M68K,
                                  capstone.CS_MODE_BIG_ENDIAN | capstone.CS_MODE_M68K_000)
        except ImportError:
            self.md = None

    def words(self, part):
        key = id(part)
        if key not in self._w:
            self._w[key] = word_tokens(part)
        return self._w[key]

    def instrs(self, part, fm):
        key = id(part)
        if key not in self._i:
            self._i[key] = instr_tokens(part, fm, self.md, self.vs, self.vl)
        return self._i[key]

    def kinds(self):
        return ('mots', 'instr', 'instr-souple') if self.md else ('mots',)


# ---------------------------------------------------------------- automate des suffixes

class SuffixAutomaton:
    def __init__(self, seq):
        nxt = [{}]
        link = [-1]
        length = [0]
        first = [-1]
        last = 0
        for i, c in enumerate(seq):
            cur = len(nxt)
            nxt.append({})
            link.append(0)
            length.append(length[last] + 1)
            first.append(i)
            p = last
            while p != -1 and c not in nxt[p]:
                nxt[p][c] = cur
                p = link[p]
            if p != -1:
                q = nxt[p][c]
                if length[p] + 1 == length[q]:
                    link[cur] = q
                else:
                    clone = len(nxt)
                    nxt.append(dict(nxt[q]))
                    link.append(link[q])
                    length.append(length[p] + 1)
                    first.append(first[q])
                    while p != -1 and nxt[p].get(c) == q:
                        nxt[p][c] = clone
                        p = link[p]
                    link[q] = link[cur] = clone
            last = cur
        self.nxt, self.link, self.length, self.first = nxt, link, length, first

    def matches(self, seq):
        """Correspondances exactes maximales : (début, fin exclue, longueur, fin dans la séquence indexée)."""
        nxt, link, length = self.nxt, self.link, self.length
        v = l = 0
        ms = [0] * len(seq)
        sv = [0] * len(seq)
        for i, c in enumerate(seq):
            while v and c not in nxt[v]:
                v = link[v]
                l = length[v]
            t = nxt[v].get(c)
            if t is None:
                v = l = 0
            else:
                v = t
                l += 1
            ms[i] = l
            sv[i] = v
        out = []
        n = len(seq)
        for i in range(n):
            l = ms[i]
            if l and (i + 1 == n or ms[i + 1] != l + 1):
                out.append((i - l + 1, i + 1, l, self.first[sv[i]] + 1))
        return out


# ---------------------------------------------------------------- classification et statistiques

def region_bytes(stream, a, b):
    pi, o0, _ = stream.where[a]
    pj, o1, s1 = stream.where[b - 1]
    if pi != pj:
        return stream.parts[pi], o0, o0
    return stream.parts[pi], o0, o1 + s1


def arithmetic(w):
    """Vrai si les mots forment, phase par phase (période 1 à 4), des progressions arithmétiques :
    table calculée (ex. localisation de caractères d'une police à chasse fixe)."""
    for p in (1, 2, 3, 4):
        if len(w) < 4 * p:
            break
        ok = True
        for r in range(p):
            d = [(w[k + p] - w[k]) & 0xFFFF for k in range(r, len(w) - p, p)]
            if max(d.count(x) for x in set(d)) < 0.9 * len(d):
                ok = False
                break
        if ok:
            return True
    return False


def classify(part, o0, o1, toks):
    blob = part.data[o0:o1]
    if not blob:
        return 'vide'
    n = len(part.data)
    if part.is_rom and (o0 < 0x20 or o1 > n - 0x20):
        return 'en-tete/pied ROM'
    if sum(1 for t in toks if t in (ADDR, DISP)) >= 0.6 * len(toks):
        return "table d'adresses"
    if len(set(toks)) <= 3:
        return 'faible entropie'
    if arithmetic(raw_words(blob)):
        return 'table arithmetique'
    printable = sum(1 for c in blob if 0x20 <= c < 0x7F or c in (0, 10, 13, 0x9B))
    if printable >= 0.7 * len(blob):
        return 'texte'
    w = raw_words(blob)
    if len(set(w)) <= 3:
        return 'faible entropie'
    for k in range(len(w) - 2):
        if w[k] == 0x4AFC and part.in_rom((w[k + 1] << 16) | w[k + 2]):
            return 'RomTag'
    return 'code/table'


def ngram_set(tokens, n):
    s = set()
    for i in range(len(tokens) - n + 1):
        g = tuple(tokens[i:i + n])
        if min(g) >= 0:
            s.add(g)
    return s


def coverage(n_eff, intervals):
    if not n_eff:
        return 0.0
    iv = sorted(intervals)
    tot = 0
    cs = ce = -1
    for s, e in iv:
        if s > ce:
            tot += ce - cs if ce > cs else 0
            cs, ce = s, e
        else:
            ce = max(ce, e)
    tot += ce - cs if ce > cs else 0
    return 100.0 * tot / n_eff


def summarize(matches, n_eff):
    """matches : liste de (début, fin, longueur, classe) côté de la séquence couverte."""
    res = {}
    for label, sel in (('toutes', matches), ('code/table', [m for m in matches if m[3] == 'code/table'])):
        lens = [m[2] for m in sel]
        row = {'max': max(lens) if lens else 0}
        for t in THRESHOLDS:
            big = [m for m in sel if m[2] >= t]
            row['n%d' % t] = len(big)
            row['c%d' % t] = coverage(n_eff, [(m[0], m[1]) for m in big])
        res[label] = row
    return res


# ---------------------------------------------------------------- table des symboles vlink

class SymMap:
    def __init__(self, path):
        self.objs = []
        self.syms = []
        if not path:
            return
        rx_obj = re.compile(r'^\s+([0-9a-f]{8}) - ([0-9a-f]{8}) (\S+)\((\w+)\)')
        rx_sym = re.compile(r'^\s+0x([0-9a-f]{8}) ([^:\s]+):')
        with open(path, encoding='latin-1') as f:
            for line in f:
                m = rx_obj.match(line)
                if m:
                    self.objs.append((int(m.group(1), 16), int(m.group(2), 16), m.group(3)))
                    continue
                m = rx_sym.match(line)
                if m:
                    self.syms.append((int(m.group(1), 16), m.group(2)))
        self.syms.sort()

    def lookup(self, addr):
        obj = next((o for s, e, o in self.objs if s <= addr < e), '?')
        sym = '?'
        for a, name in self.syms:
            if a > addr:
                break
            sym = '%s+$%X' % (name, addr - a)
        return obj, sym


# ---------------------------------------------------------------- comparaisons

def compare(ctx, sam_cache, a_parts, b_parts, kind, b_key):
    """Correspondances de A dans B, localisées dans A (B indexé par automate)."""
    sa = Stream(a_parts, kind, ctx)
    if (b_key, kind) not in sam_cache:
        sb = Stream(b_parts, kind, ctx)
        sam_cache[(b_key, kind)] = (sb, SuffixAutomaton(sb.tokens))
    sb, sam = sam_cache[(b_key, kind)]
    out = []
    for s, e, l, _ in sam.matches(sa.tokens):
        part, o0, o1 = region_bytes(sa, s, e)
        out.append((s, e, l, classify(part, o0, o1, sa.tokens[s:e])))
    return sa, sb, out


def compare_mapped(ctx, sam_cache, ours_parts, w_parts, kind, our_key):
    """Correspondances témoin -> notre ROM, reportées côté notre ROM (première occurrence)."""
    sw = Stream(w_parts, kind, ctx)
    if (our_key, kind) not in sam_cache:
        so = Stream(ours_parts, kind, ctx)
        sam_cache[(our_key, kind)] = (so, SuffixAutomaton(so.tokens))
    so, sam = sam_cache[(our_key, kind)]
    out = []
    for s, e, l, end in sam.matches(sw.tokens):
        a, b = end - l, end
        part, o0, o1 = region_bytes(so, a, b)
        out.append((a, b, l, classify(part, o0, o1, so.tokens[a:b])))
    return so, sw, out


def ngram_overlap(sa, sb):
    return {n: (100.0 * len(ga & ngram_set(sb.tokens, n)) / len(ga) if ga else 0.0)
            for n in NGRAMS for ga in (ngram_set(sa.tokens, n),)}


def fmt_row(title, n_eff, summ, ng):
    t = summ['toutes']
    c = summ['code/table']
    cells = [title, str(n_eff), str(t['max']), str(c['max'])]
    cells += ['%d / %.2f%%' % (c['n%d' % k], c['c%d' % k]) for k in (8, 16, 32)]
    cells += ['%.1f%%' % ng[n] for n in NGRAMS]
    return '| ' + ' | '.join(cells) + ' |'


HEADER = ('| comparaison | jetons A | max (tout) | max (code) | code >=8 : nb / couv. | code >=16 | '
          'code >=32 | 4-gr. | 8-gr. | 16-gr. |\n'
          '|---|---|---|---|---|---|---|---|---|---|')


def merge_notables(matches, seuil):
    big = sorted((m for m in matches if m[2] >= seuil), key=lambda m: m[0])
    merged = []
    for s, e, l, cls in big:
        if merged and s < merged[-1][1]:
            ps, pe, pl, pc = merged[-1]
            merged[-1] = (ps, max(pe, e), max(pl, l), pc if pc == cls else pc + '+' + cls)
        else:
            merged.append((s, e, l, cls))
    return merged


def selftest(ctx, sam_cache, ours, ref, rng, count=12):
    refw = raw_words(ref.data)
    fm = fill_mask(refw)
    delta = 0x2468
    chunks = []
    for _ in range(count):
        ln = rng.randrange(32, 129)
        while True:
            st = rng.randrange(0x100, len(refw) - ln - 1)
            if not any(fm[st:st + ln]) and len(set(refw[st:st + ln])) > ln // 3:
                break
        chunk = bytearray(ref.data[2 * st:2 * (st + ln)])
        for k in range(0, len(chunk) - 3, 2):
            v = struct.unpack('>I', chunk[k:k + 4])[0]
            if ref.rom_range[0] <= v < ref.rom_range[1]:
                chunk[k:k + 4] = struct.pack('>I', v - ref.rom_range[0] + ours.base + delta)
        chunks.append(bytes(chunk))
    cuts = sorted(rng.sample(range(0x80, len(ours.data) // 2), count))
    data = bytearray()
    placed = []
    prev = 0
    for cut, chunk in zip(cuts, chunks):
        data += ours.data[prev:2 * cut]
        placed.append((len(data), len(chunk) // 2))
        data += chunk
        prev = 2 * cut
    data += ours.data[prev:]
    probe = Part('autocontrole', bytes(data), ours.base, True)
    probe.rom_range = ours.rom_range
    _, _, res = compare(ctx, sam_cache, [probe], [ref], 'mots', 'ref')
    found = 0
    for p, l in placed:
        w0, w1 = p // 2, p // 2 + l
        best = max((min(e, w1) - max(s, w0) for s, e, _, _ in res if s < w1 and e > w0), default=0)
        found += best >= 0.8 * l
    return found, len(placed)


def main():
    ap = argparse.ArgumentParser(description='Audit de similarité binaire 68000 (statistiques et '
                                             'emplacements dans la première ROM uniquement).')
    ap.add_argument('notre_rom')
    ap.add_argument('rom_reference')
    ap.add_argument('temoins', nargs='*')
    ap.add_argument('--temoin', nargs='+', action='append', default=[], metavar=('NOM', 'CHEMIN'),
                    help='groupe de témoins nommé : NOM suivi de fichiers ou répertoires')
    ap.add_argument('--map', help='table vlink -M de la première ROM (objets et symboles)')
    ap.add_argument('--seuil', type=int, help='seuil « notable » en jetons (défaut : base sans lien + 1)')
    ap.add_argument('--base', nargs='+', metavar='NOM',
                    help='groupes formant la base sans lien (défaut : tous les groupes)')
    ap.add_argument('--selftest', action='store_true', help='contrôle positif par copies relogées')
    ap.add_argument('--graine', type=int, default=1, help='graine de l\'auto-contrôle')
    args = ap.parse_args()

    ours = rom_part('notre_rom', read_file(args.notre_rom))
    ref = rom_part('reference', read_file(args.rom_reference))
    groups = []
    if args.temoins:
        groups.append(('temoins', collect(args.temoins)))
    for g in args.temoin:
        if len(g) < 2:
            ap.error('--temoin attend NOM puis au moins un chemin')
        groups.append((g[0], collect(g[1:])))
    ctx = Context()
    symmap = SymMap(args.map)

    print('# Audit de similarité binaire')
    print()
    print('- première ROM : %d o, base $%06X, sha1 %s' % (len(ours.data), ours.base,
                                                       hashlib.sha1(ours.data).hexdigest()))
    print('- référence    : %d o, sha1 %s' % (len(ref.data), hashlib.sha1(ref.data).hexdigest()))
    for name, parts in groups:
        print('- groupe %s : %d hunks/images, %d o' % (name, len(parts), sum(len(p.data) for p in parts)))
    print('- flux mesurés : %s%s' % (', '.join(ctx.kinds()),
                                     '' if ctx.md else ' (capstone absent : flux INSTR omis)'))
    print()

    sam_cache = {}
    baseline_max = {}
    results = {}
    for kind in ctx.kinds():
        print('## Flux %s' % kind)
        print()
        print(HEADER)
        sa, sb, m = compare(ctx, sam_cache, [ours], [ref], kind, 'ref')
        results[kind] = (sa, m)
        print(fmt_row('notre ROM vs référence', sa.effective(), summarize(m, sa.effective()),
                      ngram_overlap(sa, sb)))
        for gname, gparts in groups:
            if not gparts:
                continue
            ga, _, gm = compare(ctx, sam_cache, gparts, [ref], kind, 'ref')
            sg = summarize(gm, ga.effective())
            if args.base is None or gname in args.base:
                baseline_max[kind] = max(baseline_max.get(kind, 0), sg['code/table']['max'])
            print(fmt_row('%s vs référence' % gname, ga.effective(), sg, ngram_overlap(ga, sb)))
            so, sw, om = compare_mapped(ctx, sam_cache, [ours], gparts, kind, 'ours')
            print(fmt_row('notre ROM vs %s' % gname, so.effective(), summarize(om, so.effective()),
                          ngram_overlap(so, sw)))
        print()

    print('## Correspondances notables (emplacements dans la première ROM uniquement)')
    print()
    for kind in ctx.kinds():
        sa, m = results[kind]
        seuil = args.seuil or (baseline_max.get(kind, 15) + 1)
        print('### Flux %s — seuil %d jetons' % (kind, seuil))
        print()
        notables = merge_notables(m, seuil)
        code = [x for x in notables if 'code/table' in x[3].split('+')]
        data = [x for x in notables if 'code/table' not in x[3].split('+')]
        for title, rows in (('Code ou table non classée', code), ('Données classées (ABI, texte, tables)', data)):
            print('%s : %d' % (title, len(rows)))
            print()
            if not rows:
                continue
            print('| offset | adresse | octets | plus longue (jetons) | classe | objet | symbole |')
            print('|---|---|---|---|---|---|---|')
            for s0, e0, l, cls in rows:
                part, o0, o1 = region_bytes(sa, s0, e0)
                obj, sym = symmap.lookup(part.base + o0)
                print('| $%05X | $%06X | %d | %d | %s | %s | %s |' % (o0, part.base + o0, o1 - o0, l, cls,
                                                                   obj, sym))
            print()

    if args.selftest:
        rng = random.Random(args.graine)
        found, total = selftest(ctx, sam_cache, ours, ref, rng)
        print('## Auto-contrôle')
        print()
        print('Fragments de 32 à 128 mots de la référence, relogés et insérés dans une copie de la première '
              'ROM : %d / %d retrouvés (flux mots, >= 80 %% de leur longueur).' % (found, total))
        print()


if __name__ == '__main__':
    main()
