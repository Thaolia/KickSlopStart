#!/usr/bin/env python3
# tests/audit_aros_similarity.py — audit de similarité textuelle entre notre assembleur (src/) et AROS.
#
# Usage : python3 -I tests/audit_aros_similarity.py <dossier_src> <dossier_aros> [options]
#
# Outil autonome (bibliothèque standard seule). Il mesure, sans jugement a priori :
#   1. asm contre asm : empreintes de k-grammes de tokens (winnowing façon MOSS) après canonicalisation
#      des deux dialectes (vasm Motorola chez nous ; GNU as « %reg », MIT « a0@ » et Motorola chez AROS),
#      à trois niveaux : « exact » (identifiants et nombres conservés), « norm » (identifiants -> ID,
#      nombres -> N, chaînes -> S), « struct » (norm + registres génériques Dn/An + mnémoniques fusionnées).
#      Pour chaque niveau : couverture de nos tokens par des passages communs de >= k tokens, recouvrement
#      d'empreintes par paire de fichiers et passages communs maximaux (fichiers + lignes des deux côtés).
#   2. asm contre C : la comparaison de tokens n'a pas de sens ; on compare les commentaires (n-grammes de
#      mots), les identifiants non imposés par l'ABI et les constantes « magiques ».
#      Liste blanche ABI : tout identifiant ou nombre présent dans les en-têtes publics d'AROS
#      (compiler/include) et dans les fichiers .conf/.fd (noms de LVO).
#   3. base sans lien : le même calcul entre l'asm AROS « comparable » (exec, dos, boot...) et un corpus
#      68000 sans rapport (FPSP/ISP Motorola, libgcc1, AHI, diskimage...) pour situer le bruit de fond,
#      ainsi qu'entre notre code et ce corpus sans rapport.
#
# Les chemins affichés sont relatifs aux dossiers passés en argument (aucun chemin propre à la machine).

import argparse
import json
import os
import random
import re
import sys
import zlib
from collections import Counter, defaultdict

OUR_ASM_EXT = ('.s', '.i', '.asm')
AROS_ASM_EXT = ('.s', '.S', '.asm', '.inc', '.i')
AROS_C_EXT = ('.c', '.h')

# Sous-arbres AROS sans rapport avec un Kickstart (code 68000 tiers ou hors périmètre) : base de bruit.
DEFAULT_UNRELATED = [
    'm680x0/', 'libgcc1/', '/stdc/', '/posixc/', 'workbench/devs/AHI/', 'workbench/devs/diskimage/',
    '/inflate/', '/rexxsyslib/', 'workbench/devs/networks/', '/mathieee', 'pfs3/', 'workbench/system/VMM/',
]
# Partie « Amiga tiers » du corpus sans rapport : logiciel système Amiga en asm écrit hors du projet AROS
# (VMM, AHI, diskimage) ; même domaine et mêmes conventions d'appel que nous, d'où une base plus exigeante
# que le FPSP Motorola (qui pèse 80 % du corpus sans rapport).
DEFAULT_AMIGA_TIERS = ['workbench/system/VMM/', 'workbench/devs/AHI/', 'workbench/devs/diskimage/']

# Déclarations et données (constantes, champs de structure, dc/ds) : gardées au niveau « exact » (une table
# recopiée y apparaît), retirées des niveaux « norm »/« struct » où toute table « NOM equ N » ou « dc.b N,N »
# se ressemble (faux positifs massifs sinon).
DECL = {'equ', 'dc', 'ds', 'dcb', 'rs', 'so', 'fo', 'bitdef', 'structure', 'struct', 'aptr', 'bptr', 'ulong', 'uword', 'ubyte',
        'long', 'word', 'byte', 'label', 'libdef', 'enum', 'eitem', 'cptr', 'short', 'ushort', 'float',
        'double', 'bool', 'rptr', 'fptr'}

# Mnémoniques 680x0 / 6888x (de base, sans suffixe de taille) ; sert à séparer le suffixe MIT (« movel »).
BASE_MNEM = set('''
abcd add adda addi addq addx and andi asl asr bcc bcs beq bge bgt bhi bhs ble blo bls blt bmi bne bpl bvc bvs
bra bsr bchg bclr bset btst chk clr cmp cmpa cmpi cmpm dbcc dbcs dbeq dbf dbra dbge dbgt dbhi dble dbls dblt
dbmi dbne dbpl dbt dbvc dbvs divs divu eor eori exg ext extb illegal jmp jsr lea link lsl lsr move movea movem
movep moveq movec moves muls mulu nbcd neg negx nop not or ori pea reset rol ror roxl roxr rte rtr rts rtd sbcd
scc scs seq sf sge sgt shi sle sls slt smi sne spl st svc svs stop sub suba subi subq subx swap tas trap trapv
tst unlk bfchg bfclr bfexts bfextu bfffo bfins bfset bftst bkpt callm cas cas2 chk2 cmp2 divsl divul pack unpk
rtm trapcc cinva cinvl cinvp cpusha cpushl cpushp move16 pflush ptest pmove plpaw
fabs fadd fbeq fbne fbgt fbge fblt fble fbra fcmp fdiv fint fintrz fmove fmovem fmul fneg fsqrt fsub ftst
fsave frestore fmovecr fmod frem fscale fsin fcos ftan fatan fetox flogn flog10 flog2 fgetexp fgetman
'''.split())
NO_SIZE = {'lea', 'pea', 'moveq', 'exg', 'swap', 'jsr', 'jmp', 'bsr', 'bra', 'rts', 'rte', 'rtr', 'nop',
           'unlk', 'trap', 'illegal', 'reset', 'stop', 'trapv', 'scc', 'scs', 'seq', 'sne', 'st', 'sf'}
BRANCH = re.compile(r'^(b(ra|sr|cc|cs|eq|ne|ge|gt|hi|hs|le|lo|ls|lt|mi|pl|vc|vs)|db\w+)$')
STRUCT_MERGE = {'movea': 'move', 'moveq': 'move', 'addq': 'add', 'addi': 'add', 'adda': 'add',
                'subq': 'sub', 'subi': 'sub', 'suba': 'sub', 'cmpi': 'cmp', 'cmpa': 'cmp', 'cmpm': 'cmp',
                'andi': 'and', 'ori': 'or', 'eori': 'eor', 'jsr': 'call', 'bsr': 'call', 'jmp': 'jump',
                'bra': 'jump', 'dbra': 'dbf'}
DIRECTIVE_MAP = {'.long': 'dc.l', '.int': 'dc.l', '.word': 'dc.w', '.short': 'dc.w', '.byte': 'dc.b',
                 '.ascii': 'dc.b', '.asciz': 'dc.b', '.string': 'dc.b', '.equ': 'equ', '.set': 'equ',
                 'set': 'equ', '=': 'equ', 'mov': 'move'}
# Directives purement déclaratives (aucune logique) : ignorées pour les empreintes.
SKIP_DIRECTIVES = {
    'xdef', 'xref', 'section', 'text', 'data', 'bss', 'include', 'incdir', 'align', 'even', 'cnop', 'end',
    'public', 'global', 'ifnd', 'ifd', 'ifne', 'ifeq', 'endc', 'endif', 'else', 'machine', 'mc68000', 'opt',
    'idnt', 'ttl', 'list', 'nolist', 'page', 'xcom', 'code', 'far', 'near', 'rsreset', 'clrfo',
    '.globl', '.global', '.extern', '.text', '.data', '.bss', '.section', '.align', '.balign', '.p2align',
    '.even', '.func', '.endfunc', '.type', '.size', '.file', '.ident', '.cfi_startproc', '.cfi_endproc',
    '.chip', '.end', '.previous', '.weak', '.hidden', '.local', '.include', '.macro', '.endm', '.if', '.endif',
    '.else', '.ifdef', '.ifndef', '.org', '.cpu', '.arch', '.loc', '.debug', '.version', '.fpu',
}
REGS = {f'd{i}' for i in range(8)} | {f'a{i}' for i in range(8)} | {
    'sp', 'pc', 'sr', 'ccr', 'usp', 'ssp', 'vbr', 'cacr', 'caar', 'msp', 'isp', 'sfc', 'dfc', 'zpc',
    'fpcr', 'fpsr', 'fpiar'} | {f'fp{i}' for i in range(8)}
C_KEYWORDS = set('''auto break case char const continue default do double else enum extern float for goto if
inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void
volatile while define include ifdef ifndef endif undef pragma elif error bool true false null'''.split())

TOK_RE = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|0x[0-9a-f]+|\$[0-9a-f]+|%[01]+|\d+[fb]\b|\d+'
                    r'|[a-z_.][\w.$]*|\S')
REG_PCT_RE = re.compile(r'%(?=(d[0-7]|a[0-7]|sp|fp[0-7]?|pc|sr|ccr|usp|ssp|vbr|cacr|caar|msp|isp|sfc|dfc|zpc|'
                        r'fpcr|fpsr|fpiar)\b)')
MIT_RE = re.compile(r'\b(a[0-7]|sp|fp|pc)@(\+|-)?(?:\(([^()]*)\))?')
DISP_NEW_RE = re.compile(r'\(\s*([^(),]+?)\s*,\s*(a[0-7]|sp|pc)\b')


def _mit_sub(m):
    reg, post, inner = m.group(1), m.group(2), m.group(3)
    reg = 'a6' if reg == 'fp' else reg
    if post == '+':
        return f'({reg})+'
    if post == '-':
        return f'-({reg})'
    if inner is None:
        return f'({reg})'
    parts = [p.strip().replace(':', '.') for p in inner.split(',')]
    return f'{parts[0]}({",".join([reg] + parts[1:])})'


def _disp_new_sub(m):
    disp = m.group(1).strip()
    if disp in REGS or re.fullmatch(r'[ad][0-7](\.[wl])?', disp):
        return m.group(0)
    return f'{disp}({m.group(2)}'


def parse_number(tok):
    try:
        if tok.startswith('0x'):
            return int(tok[2:], 16)
        if tok.startswith('$'):
            return int(tok[1:], 16)
        if tok.startswith('%'):
            return int(tok[1:], 2)
        if tok.isdigit():
            return int(tok)
    except ValueError:
        pass
    return None


def strip_block_comments(text):
    """Remplace les commentaires /* */ par des espaces (lignes conservées) ; renvoie (texte, [(ligne, txt)])."""
    out, comments = [], []
    i, n, line = 0, len(text), 1
    while i < n:
        if text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            chunk = text[i:j]
            for k, part in enumerate(chunk.split('\n')):
                comments.append((line + k, part.strip('/* \t')))
            out.append(''.join('\n' if c == '\n' else ' ' for c in chunk))
            line += chunk.count('\n')
            i = j
        else:
            c = text[i]
            if c == '\n':
                line += 1
            out.append(c)
            i += 1
    return ''.join(out), comments


def split_comment(line, chars):
    """Coupe une ligne au premier caractère de commentaire hors chaîne."""
    q = None
    for i, c in enumerate(line):
        if q:
            if c == q:
                q = None
        elif c in '"\'':
            if c == "'" and i + 2 < len(line) and line[i + 2] != "'":
                continue
            q = c
        elif c in chars:
            return line[:i], line[i + 1:]
    return line, ''


class AsmFile:
    """Fichier assembleur canonicalisé : statements, tokens par niveau, commentaires, identifiants, nombres."""

    def __init__(self, rel, text):
        self.rel = rel
        self.comments = []
        self.idents = []
        self.numbers = []
        self.toks = {'exact': [], 'norm': [], 'struct': []}
        self.lines = {'exact': [], 'norm': [], 'struct': []}
        gas = bool(re.search(r'%(d[0-7]|a[0-7]|sp)\b|^\s*\.globl\b|\b(a[0-7]|sp)@', text, re.M))
        if gas or '/*' in text:
            text, cm = strip_block_comments(text)
            self.comments.extend(cm)
        for ln, raw in enumerate(text.split('\n'), 1):
            self._line(ln, raw, gas)

    def _line(self, ln, raw, gas):
        s = raw.rstrip()
        st = s.lstrip()
        if not st:
            return
        if st[0] in '*;' and (st[0] == ';' or s[0] == '*'):
            self.comments.append((ln, st[1:].strip()))
            return
        if st[0] == '#' and s[0] == '#':
            if not re.match(r'#\s*(include|define|undef|if|ifdef|ifndef|else|elif|endif|pragma|error)\b', st):
                self.comments.append((ln, st[1:].strip()))
            return
        if gas and st[0] == '|':
            self.comments.append((ln, st[1:].strip()))
            return
        if gas:
            if '//' in s:
                s, c = s.split('//', 1)
                self.comments.append((ln, c.strip()))
            stmts = [x for x in s.split(';')]
        else:
            s, c = split_comment(s, ';')
            if c.strip():
                self.comments.append((ln, c.strip()))
            stmts = [s]
        for k, stmt in enumerate(stmts):
            self._stmt(ln, stmt, column0=(k == 0 and not gas))

    def _stmt(self, ln, stmt, column0):
        if not stmt.strip():
            return
        label = None
        m = re.match(r'^\s*([\w.$]+):+', stmt)
        if m:
            label, stmt = m.group(1), stmt[m.end():]
        elif column0 and stmt[0] not in ' \t':
            parts = stmt.split(None, 1)
            label, stmt = parts[0], (parts[1] if len(parts) > 1 else '')
        body = stmt.strip()
        mnem, ops = '', ''
        if body:
            parts = body.split(None, 1)
            mnem, ops = parts[0].lower(), (parts[1] if len(parts) > 1 else '')
            # « NOM equ valeur » / « .equ NOM, valeur »
            if mnem in ('.equ', '.set') and ',' in ops:
                label, ops = ops.split(',', 1)
                label = label.strip()
        mnem = DIRECTIVE_MAP.get(mnem, mnem)
        if mnem in SKIP_DIRECTIVES:
            if label:
                self._emit_label(ln, label)
            return
        if label:
            self._emit_label(ln, label)
        if not mnem:
            return
        base, size = mnem, ''
        if '.' in mnem[1:]:
            base, size = mnem.split('.', 1)
        elif mnem not in BASE_MNEM and mnem[:-1] in BASE_MNEM and mnem[-1] in 'bwlsxdp':
            base, size = mnem[:-1], mnem[-1]
        if base == 'mov':
            base = 'move'
        if re.fullmatch(r'j(b?ra|bsr|b?(cc|cs|eq|ne|ge|gt|hi|hs|le|lo|ls|lt|mi|pl|vc|vs))', base):
            base = {'jra': 'bra', 'jbra': 'bra', 'jbsr': 'bsr'}.get(base, 'b' + base.lstrip('jb'))
        if base in ('bhs',):
            base = 'bcc'
        if base in ('blo',):
            base = 'bcs'
        if BRANCH.match(base) or base in NO_SIZE:
            size = ''
        mn_exact = base + ('.' + size if size else '')
        ops_c = REG_PCT_RE.sub('', ops.lower())
        ops_c = MIT_RE.sub(_mit_sub, ops_c)
        ops_c = DISP_NEW_RE.sub(_disp_new_sub, ops_c)
        ops_c = re.sub(r'\b([ad][0-7]):([wl])\b', r'\1.\2', ops_c)
        ops_c = re.sub(r'\bsp\b', 'a7', ops_c).replace('&', '#')
        ops_toks = TOK_RE.findall(ops_c)
        decl = base in DECL
        self._emit(ln, mn_exact, mn_exact, STRUCT_MERGE.get(base, base) + ('.' + size if size else ''), decl)
        is_data = base in ('dc', 'ds', 'equ')
        for t in ops_toks:
            num = parse_number(t)
            if num is not None:
                self.numbers.append((ln, num, is_data))
                self._emit(ln, str(num), 'N', 'N', decl)
            elif re.fullmatch(r'\d+[fb]', t):
                self._emit(ln, 'LL', 'LL', 'LL', decl)
            elif t[0] in '"\'':
                self._emit(ln, t, 'S', 'S', decl)
            elif t in REGS:
                self._emit(ln, t, t, 'D' if t[0] == 'd' else ('A' if t[0] == 'a' else t), decl)
            elif re.fullmatch(r'[ad][0-7]\.[wl]', t):
                self._emit(ln, t, t, ('D' if t[0] == 'd' else 'A') + t[2:], decl)
            elif re.match(r'[a-z_.]', t):
                self.idents.append((ln, t))
                self._emit(ln, t, 'ID', 'ID', decl)
            else:
                self._emit(ln, t, t, t, decl)

    def _emit_label(self, ln, label):
        # Définitions de labels : niveau « exact » seulement (en norm/struct, « ID : » n'apporte que du bruit,
        # par ex. une suite de labels de tables de données).
        if re.fullmatch(r'\d+', label):
            self._emit(ln, 'LL', None, None, True)
        else:
            self.idents.append((ln, label.lower()))
            self._emit(ln, label.lower(), None, None, True)
        self._emit(ln, ':', None, None, True)

    def _emit(self, ln, e, n, s, decl=False):
        for lvl, t in (('exact', e), ('norm', n), ('struct', s)):
            if decl and lvl != 'exact':
                continue
            self.toks[lvl].append(t)
            self.lines[lvl].append(ln)


def read_text(path):
    with open(path, 'rb') as f:
        data = f.read()
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        return data.decode('latin-1')


def walk(root, exts, skip_git=True):
    for d, dirs, files in os.walk(root):
        if skip_git:
            dirs[:] = sorted(x for x in dirs if x != '.git')
        for fn in sorted(files):
            if fn.endswith(exts):
                p = os.path.join(d, fn)
                yield os.path.relpath(p, root).replace(os.sep, '/'), p


# --------------------------------------------------------------------------------------------------------
# Empreintes : k-grammes de tokens, hachage déterministe (crc32), winnowing (Schleimer et al., 2003).
# --------------------------------------------------------------------------------------------------------

def kgram_hashes(toks, k):
    return [zlib.crc32('\x1f'.join(toks[i:i + k]).encode()) for i in range(len(toks) - k + 1)]


def winnow(hashes, w):
    fps = set()
    if not hashes:
        return fps
    if len(hashes) <= w:
        fps.add(min(hashes))
        return fps
    prev = -1
    for i in range(len(hashes) - w + 1):
        win = hashes[i:i + w]
        m = min(win)
        j = i + w - 1 - win[::-1].index(m)
        if j != prev:
            fps.add(m)
            prev = j
    return fps


class Corpus:
    """Index complet des k-grammes d'un ensemble de fichiers (pour retrouver les passages communs)."""

    def __init__(self, files, lvl, k, w, cap):
        self.files, self.lvl, self.k = files, lvl, k
        self.index = defaultdict(list)
        self.common = set()
        self.fps = []
        for fi, f in enumerate(files):
            hs = kgram_hashes(f.toks[lvl], k)
            self.fps.append(winnow(hs, w))
            for pos, h in enumerate(hs):
                lst = self.index[h]
                if len(lst) < cap:
                    lst.append((fi, pos))
                else:
                    self.common.add(h)
        self.fp_owner = defaultdict(set)
        for fi, s in enumerate(self.fps):
            for h in s:
                self.fp_owner[h].add(fi)


def find_runs(qfile, corpus, lvl, k):
    """Passages maximaux (en tokens) communs entre qfile et le corpus ; un seul par diagonale."""
    qt = qfile.toks[lvl]
    hs = kgram_hashes(qt, k)
    runs = []
    last_end = {}
    for i, h in enumerate(hs):
        if h in corpus.common or h not in corpus.index:
            continue
        for fi, j in corpus.index[h]:
            diag = (fi, j - i)
            if last_end.get(diag, -1) > i:
                continue
            tt = corpus.files[fi].toks[lvl]
            if qt[i:i + k] != tt[j:j + k]:
                continue
            n = k
            while i + n < len(qt) and j + n < len(tt) and qt[i + n] == tt[j + n]:
                n += 1
            last_end[diag] = i + n
            runs.append((n, i, fi, j))
    return runs


def coverage(qfiles, corpus, lvl, k, min_len):
    total = covered = 0
    all_runs = []
    per_file = []
    for qi, f in enumerate(qfiles):
        runs = [r for r in find_runs(f, corpus, lvl, k) if r[0] >= min_len]
        mark = bytearray(len(f.toks[lvl]))
        for n, i, fi, j in runs:
            mark[i:i + n] = b'\x01' * n
        c = sum(mark)
        total += len(mark)
        covered += c
        per_file.append((c, len(mark), f.rel))
        all_runs.extend((n, qi, i, fi, j) for n, i, fi, j in runs)
    return total, covered, per_file, all_runs


def top_passages(qfiles, corpus, lvl, runs, limit):
    """Plus longs passages, sans chevauchement côté requête."""
    out, taken = [], defaultdict(list)
    for n, qi, i, fi, j in sorted(runs, key=lambda r: -r[0]):
        if any(a < i + n and i < b for a, b in taken[qi]):
            continue
        taken[qi].append((i, i + n))
        qf, tf = qfiles[qi], corpus.files[fi]
        out.append({
            'tokens': n,
            'ours': f'{qf.rel}:{qf.lines[lvl][i]}-{qf.lines[lvl][i + n - 1]}',
            'theirs': f'{tf.rel}:{tf.lines[lvl][j]}-{tf.lines[lvl][j + n - 1]}',
            'text': ' '.join(qf.toks[lvl][i:i + n])[:240],
        })
        if len(out) >= limit:
            break
    return out


def pair_overlap(qfiles, qcorpus, corpus, limit):
    """Recouvrement d'empreintes winnowées par paire : |Fq ∩ Ft| / |Fq| (pourcentage façon MOSS)."""
    res = []
    for qi, f in enumerate(qfiles):
        fq = qcorpus.fps[qi]
        if not fq:
            continue
        cnt = Counter()
        for h in fq:
            for fi in corpus.fp_owner.get(h, ()):
                cnt[fi] += 1
        for fi, c in cnt.most_common(3):
            ft = corpus.fps[fi]
            res.append({'ours': f.rel, 'theirs': corpus.files[fi].rel, 'shared': c,
                        'pct_ours': round(100.0 * c / len(fq), 2), 'pct_theirs': round(100.0 * c / len(ft), 2)})
    res.sort(key=lambda r: (-r['pct_ours'], -r['shared']))
    return res[:limit]


def compare_asm(qfiles, tfiles, lvl, k, w, cap, min_len, limit):
    corpus = Corpus(tfiles, lvl, k, w, cap)
    qcorpus = Corpus(qfiles, lvl, k, w, cap)
    total, covered, per_file, runs = coverage(qfiles, corpus, lvl, k, min_len)
    qfp = set().union(*qcorpus.fps) if qcorpus.fps else set()
    tfp = set(corpus.fp_owner)
    return {
        'level': lvl, 'k': k, 'w': w, 'min_len': min_len,
        'query_tokens': total, 'covered_tokens': covered,
        'coverage_pct': round(100.0 * covered / total, 3) if total else 0.0,
        'fingerprints_query': len(qfp), 'fingerprints_shared': len(qfp & tfp),
        'fingerprint_pct': round(100.0 * len(qfp & tfp) / len(qfp), 3) if qfp else 0.0,
        'longest_run': max((r[0] for r in runs), default=0),
        'top_files': [{'file': r, 'covered': c, 'tokens': t, 'pct': round(100.0 * c / t, 2) if t else 0}
                      for c, t, r in sorted(per_file, key=lambda x: (-x[0], x[2]))[:limit] if c],
        'top_pairs': pair_overlap(qfiles, qcorpus, corpus, limit),
        'passages': top_passages(qfiles, corpus, lvl, runs, limit),
    }


# --------------------------------------------------------------------------------------------------------
# Côté C : commentaires, identifiants, constantes.
# --------------------------------------------------------------------------------------------------------

C_STRING_RE = re.compile(r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'')
C_IDENT_RE = re.compile(r'\b[A-Za-z_]\w*\b')
C_NUM_RE = re.compile(r'\b(0[xX][0-9a-fA-F]+|\d+)[uUlL]*\b')
WORD_RE = re.compile(r"[a-zà-öø-ÿœæ0-9_]+")
EN_STOP = set('the of to and a in is it that for this be on with as are by not if we at from or an has have '
              'must should will can when which then than so do does'.split())
FR_STOP = set('le la les de des du un une et est en que qui pour dans sur par au aux pas ne se ce cette il '
              'sont avec ou si on'.split())


class CFile:
    def __init__(self, rel, text):
        self.rel = rel
        code, self.comments = strip_block_comments(text)
        lines = code.split('\n')
        out = []
        for ln, l in enumerate(lines, 1):
            if '//' in l:
                pre, c = split_comment(l.replace('//', '\x00', 1), '\x00')
                if c:
                    self.comments.append((ln, c.strip()))
                l = pre
            out.append(C_STRING_RE.sub(' ', l))
        self.idents = []
        self.numbers = []
        for ln, l in enumerate(out, 1):
            for m in C_IDENT_RE.finditer(l):
                self.idents.append((ln, m.group(0)))
            for m in C_NUM_RE.finditer(l):
                t = m.group(1).lower()
                self.numbers.append((ln, int(t, 16) if t.startswith('0x') else int(t)))


def ident_key(name):
    n = name.lower()
    for p in ('_lvo', 'lvo_'):
        if n.startswith(p):
            n = n[len(p):]
    return n.replace('_', '').replace('.', '').replace('$', '')


def is_trivial_number(v):
    # < $1000 : offsets de structures, tailles, codes de caractères ; trop banals pour signer une origine.
    if v < 0x1000:
        return True
    if v % 100 == 0:
        return True
    for width in (16, 32):
        if v < (1 << width):
            b = format(v, f'0{width}b')
            if len(re.findall(r'1+', b)) <= 1 or len(re.findall(r'0+', b)) <= 1:
                return True
    return False


def hw_number(v):
    return (0xDFF000 <= v <= 0xDFF1FF or 0xBFD000 <= v <= 0xBFEFFF or 0xF80000 <= v <= 0xFFFFFF
            or 0xE80000 <= v <= 0xE8FFFF or 0xC00000 <= v <= 0xDFFFFF or 0xA00000 <= v <= 0xBFFFFF)


def english_ratio(text):
    ws = WORD_RE.findall(text.lower())
    if len(ws) < 4:
        return None
    en = sum(w in EN_STOP for w in ws)
    fr = sum(w in FR_STOP for w in ws)
    return 'en' if en >= 2 and en > fr else ('fr' if fr >= 1 else None)


def shingles(comments, n):
    out = defaultdict(list)
    for ln, txt in comments:
        ws = WORD_RE.findall(txt.lower())
        for i in range(len(ws) - n + 1):
            out[' '.join(ws[i:i + n])].append(ln)
    return out


def compare_comments(ours, theirs, n, limit):
    ours_sh = defaultdict(list)
    for f in ours:
        for s, lns in shingles(f.comments, n).items():
            ours_sh[s].append(f'{f.rel}:{lns[0]}')
    theirs_sh = defaultdict(list)
    for f in theirs:
        for s, lns in shingles(f.comments, n).items():
            theirs_sh[s].append(f'{f.rel}:{lns[0]}')
    shared = sorted(set(ours_sh) & set(theirs_sh), key=lambda s: (-len(theirs_sh[s]), s))
    lang = Counter()
    for f in ours:
        for _, txt in f.comments:
            lang[english_ratio(txt)] += 1
    return {
        'n': n, 'our_comment_lines': sum(len(f.comments) for f in ours),
        'our_lang': {'fr': lang['fr'], 'en': lang['en'], 'indetermine': lang[None]},
        'our_shingles': len(ours_sh), 'their_shingles': len(theirs_sh), 'shared': len(shared),
        'examples': [{'shingle': s, 'ours': ours_sh[s][:3], 'theirs': theirs_sh[s][:3],
                      'their_count': len(theirs_sh[s])} for s in shared[:limit]],
    }


def build_whitelist(aros_root, unrelated):
    """Identifiants et nombres imposés par l'ABI : en-têtes publics + listes de fonctions (.conf/.fd/.sfd).

    En-têtes publics = compiler/include/ et tout dossier « include/ » d'un module (ex. rom/devs/console/include
    fournit devices/conunit.h), hors sous-arbres sans rapport."""
    ids, nums = set(), set()
    nfiles = 0
    for rel, p in walk(aros_root, ('.h', '.i', '.inc', '.hpp')):
        if '/include/' not in '/' + rel or any(u in '/' + rel for u in unrelated):
            continue
        cf = CFile(rel, read_text(p))
        ids.update(ident_key(x) for _, x in cf.idents)
        nums.update(v for _, v in cf.numbers)
        nfiles += 1
    for rel, p in walk(aros_root, ('.conf', '.fd', '.sfd')):
        for w in C_IDENT_RE.findall(read_text(p)):
            ids.add(ident_key(w))
        nfiles += 1
    return ids, nums, nfiles


def compare_idents(ours, theirs_by_group, whitelist, min_len, limit):
    skip = {ident_key(x) for x in BASE_MNEM | REGS | C_KEYWORDS}
    our_names = defaultdict(list)
    for f in ours:
        for ln, name in f.idents:
            our_names[ident_key(name)].append((name, f'{f.rel}:{ln}'))
    res = {'our_distinct': len(our_names), 'groups': {}}
    for group, files in theirs_by_group.items():
        their = defaultdict(list)
        for f in files:
            seen = set()
            for ln, name in f.idents:
                key = ident_key(name)
                if key in seen:
                    continue
                seen.add(key)
                their[key].append((name, f'{f.rel}:{ln}'))
        common = set(our_names) & set(their)
        shared = sorted((k for k in common if len(k) >= min_len and k not in whitelist and k not in skip),
                        key=lambda k: (-len(their[k]), k))
        res['groups'][group] = {
            'their_distinct': len(their), 'common_raw': len(common),
            'common_whitelisted': sum(1 for k in common if k in whitelist),
            'shared_nonabi': len(shared),
            'examples': [{'key': k, 'ours': sorted({n for n, _ in our_names[k]})[:3],
                          'ours_at': our_names[k][0][1], 'theirs': sorted({n for n, _ in their[k]})[:3],
                          'theirs_at': their[k][0][1], 'their_files': len(their[k])}
                         for k in shared[:limit]],
        }
    return res


def compare_numbers(ours, theirs_by_group, wl_nums, limit):
    our_vals = defaultdict(list)
    for f in ours:
        for ln, v, _ in f.numbers:
            our_vals[v].append(f'{f.rel}:{ln}')
    res = {'our_distinct': len(our_vals),
           'our_magic': sum(1 for v in our_vals if not is_trivial_number(v) and not hw_number(v)), 'groups': {}}
    for group, files in theirs_by_group.items():
        their = defaultdict(list)
        for f in files:
            for ln, v in ([(a, b) for a, b, *_ in f.numbers]):
                if not their[v] or their[v][-1].split(':')[0] != f.rel:
                    their[v].append(f'{f.rel}:{ln}')
        common = set(our_vals) & set(their)
        magic = sorted((v for v in common if not is_trivial_number(v) and not hw_number(v) and v not in wl_nums),
                       key=lambda v: (len(their[v]), -v))
        res['groups'][group] = {
            'common_raw': len(common), 'shared_magic': len(magic),
            'examples': [{'value': hex(v), 'ours': our_vals[v][:2], 'theirs': their[v][:2],
                          'their_files': len(their[v])} for v in magic[:limit]],
        }
    return res


# --------------------------------------------------------------------------------------------------------

def load(src, aros, unrelated):
    ours = [AsmFile(rel, read_text(p)) for rel, p in walk(src, OUR_ASM_EXT)]
    comp, unrel, cfiles_comp, cfiles_unrel = [], [], [], []
    for rel, p in walk(aros, AROS_ASM_EXT + AROS_C_EXT):
        if rel.startswith('compiler/include/'):
            continue
        is_unrel = any(u in '/' + rel for u in unrelated)
        if rel.endswith(AROS_C_EXT):
            (cfiles_unrel if is_unrel else cfiles_comp).append(CFile(rel, read_text(p)))
        else:
            (unrel if is_unrel else comp).append(AsmFile(rel, read_text(p)))
    return ours, comp, unrel, cfiles_comp, cfiles_unrel


def fmt_report(r):
    o = []
    p = o.append
    p('# Audit de similarité src/ <-> AROS\n')
    p('## Corpus')
    for k, v in r['corpus'].items():
        p(f'- {k} : {v}')
    if r['corpus']['AROS asm sans rapport'].startswith('0 '):
        p('\n**ATTENTION** : aucun asm « sans rapport » dans le dossier AROS fourni : les lignes BASE et la base à '
          'taille égale sont vides ; la liste blanche ABI est réduite aux en-têtes présents. Utiliser une copie '
          'AROS contenant compiler/include, arch/m68k-*, rom/, workbench/ (voir docs/audit/aros-similarity.md).')
    p('\n## asm contre asm (couverture = % de tokens de la requête dans un passage commun >= min_len tokens)')
    p('| comparaison | niveau | k | w | tokens requête | couverts | couverture % | empreintes partagées % | '
      'plus long passage |')
    p('|---|---|---|---|---|---|---|---|---|')
    for c in r['asm']:
        p(f"| {c['name']} | {c['level']} | {c['k']} | {c['w']} | {c['query_tokens']} | {c['covered_tokens']} | "
          f"{c['coverage_pct']} | {c['fingerprint_pct']} | {c['longest_run']} |")
    if r['matched']:
        p('\nBase à taille égale : src -> sous-ensembles aléatoires de l\'asm Amiga tiers, de la taille du corpus '
          'comparable')
        p('| niveau | k | tokens cible | tirages | couverture moyenne % | min | max |')
        p('|---|---|---|---|---|---|---|')
        for m in r['matched']:
            p(f"| {m['level']} | {m['k']} | {m['target_tokens']} | {m['draws']} | {m['mean']} | {m['min']} | "
              f"{m['max']} |")
    for c in r['asm']:
        if not c['passages']:
            continue
        p(f"\n### Passages les plus longs — {c['name']} / {c['level']} k={c['k']}")
        for x in c['passages']:
            p(f"- {x['tokens']} tokens : {x['ours']}  <->  {x['theirs']}\n    `{x['text']}`")
        p(f"\nPaires de fichiers (empreintes winnowées partagées) — {c['name']} / {c['level']} k={c['k']}")
        for x in c['top_pairs'][:8]:
            p(f"- {x['ours']} <-> {x['theirs']} : {x['shared']} empreintes, {x['pct_ours']} % / "
              f"{x['pct_theirs']} %")
    cm = r['comments']
    p(f"\n## Commentaires ({cm['n']}-grammes de mots)")
    p(f"- lignes de commentaire chez nous : {cm['our_comment_lines']} (langue : {cm['our_lang']})")
    p(f"- n-grammes : nous {cm['our_shingles']}, AROS {cm['their_shingles']}, communs {cm['shared']}")
    for x in cm['examples']:
        p(f"  - « {x['shingle']} » : {x['ours']} <-> {x['theirs']} (AROS : {x['their_count']} fichiers)")
    idn = r['idents']
    p(f"\n## Identifiants (liste blanche ABI : {r['whitelist']['identifiers']} identifiants)")
    for g, d in idn['groups'].items():
        p(f"- {g} : communs bruts {d['common_raw']}, dont ABI {d['common_whitelisted']}, "
          f"hors ABI (>= {r['params']['ident_min_len']} car.) {d['shared_nonabi']}")
        for x in d['examples']:
            p(f"  - {x['key']} : {x['ours']} ({x['ours_at']}) <-> {x['theirs']} ({x['theirs_at']}, "
              f"{x['their_files']} fichiers)")
    nm = r['numbers']
    p(f"\n## Constantes (nous : {nm['our_distinct']} valeurs distinctes, dont {nm['our_magic']} non triviales)")
    for g, d in nm['groups'].items():
        p(f"- {g} : communes brutes {d['common_raw']}, « magiques » hors en-têtes publics {d['shared_magic']}")
        for x in d['examples']:
            p(f"  - {x['value']} : {x['ours']} <-> {x['theirs']} ({x['their_files']} fichiers)")
    return '\n'.join(o)


def main():
    ap = argparse.ArgumentParser(description='Audit de similarité textuelle src/ <-> AROS')
    ap.add_argument('src')
    ap.add_argument('aros')
    ap.add_argument('-k', type=int, nargs='+', default=[12], help='longueur(s) des k-grammes de tokens')
    ap.add_argument('-w', type=int, default=8, help='fenêtre de winnowing')
    ap.add_argument('--levels', nargs='+', default=['exact', 'norm', 'struct'])
    ap.add_argument('--min-len', type=int, default=0, help='longueur minimale de passage (défaut : k)')
    ap.add_argument('--cap', type=int, default=200, help='occurrences max par k-gramme (au-delà : banal)')
    ap.add_argument('--unrelated', nargs='*', default=DEFAULT_UNRELATED, help='motifs de chemins sans rapport')
    ap.add_argument('--shingle', type=int, default=5, help='n-grammes de mots des commentaires')
    ap.add_argument('--ident-min-len', type=int, default=6)
    ap.add_argument('--limit', type=int, default=15)
    ap.add_argument('--draws', type=int, default=5, help='tirages de la base à taille égale')
    ap.add_argument('--amiga-tiers', nargs='*', default=DEFAULT_AMIGA_TIERS,
                    help='motifs (inclus dans --unrelated) du sous-corpus Amiga tiers')
    ap.add_argument('--json', help='écrit aussi les résultats bruts en JSON')
    a = ap.parse_args()

    ours, comp, unrel, cc, cu = load(a.src, a.aros, a.unrelated)
    wl_ids, wl_nums, wl_files = build_whitelist(a.aros, a.unrelated)
    r = {'params': vars(a).copy(), 'asm': [], 'matched': []}
    r['params'].pop('src')
    r['params'].pop('aros')
    r['params'].pop('json')
    r['corpus'] = {
        'nos fichiers asm': f"{len(ours)} ({sum(len(f.toks['exact']) for f in ours)} tokens)",
        'AROS asm comparable': f"{len(comp)} ({sum(len(f.toks['exact']) for f in comp)} tokens)",
        'AROS asm sans rapport': f"{len(unrel)} ({sum(len(f.toks['exact']) for f in unrel)} tokens)",
        'AROS C comparable': len(cc), 'AROS C sans rapport': len(cu),
        'fichiers de liste blanche (en-têtes publics, .conf/.fd)': wl_files,
    }
    r['whitelist'] = {'identifiers': len(wl_ids), 'numbers': len(wl_nums)}
    tiers = [f for f in unrel if any(t in '/' + f.rel for t in a.amiga_tiers)]
    r['corpus']['dont asm Amiga tiers (VMM, AHI, diskimage)'] = (
        f"{len(tiers)} ({sum(len(f.toks['exact']) for f in tiers)} tokens)")
    pairs = [('src -> AROS asm comparable', ours, comp), ('src -> AROS asm sans rapport', ours, unrel),
             ('src -> asm Amiga tiers', ours, tiers),
             ('BASE : AROS comparable -> AROS sans rapport', comp, unrel),
             ('BASE : AROS comparable -> asm Amiga tiers', comp, tiers)]
    for k in a.k:
        for lvl in a.levels:
            for name, q, t in pairs:
                res = compare_asm(q, t, lvl, k, a.w, a.cap, a.min_len or k, a.limit)
                res['name'] = name
                r['asm'].append(res)
                print(f'[{name}] {lvl} k={k} : couverture {res["coverage_pct"]} %', file=sys.stderr)
            # Base à taille égale : sous-ensembles tirés au hasard (graine fixe) de l'asm Amiga tiers, de même
            # nombre de tokens que le corpus comparable ; la couverture croît avec la taille du corpus cible.
            target = sum(len(f.toks[lvl]) for f in comp)
            covs = []
            for seed in range(a.draws):
                pool = tiers[:]
                random.Random(seed).shuffle(pool)
                sub, n = [], 0
                for f in pool:
                    if n >= target:
                        break
                    sub.append(f)
                    n += len(f.toks[lvl])
                corpus = Corpus(sub, lvl, k, a.w, a.cap)
                total, covered, _, _ = coverage(ours, corpus, lvl, k, a.min_len or k)
                covs.append(100.0 * covered / total if total else 0.0)
            if covs:
                r['matched'].append({'level': lvl, 'k': k, 'target_tokens': target, 'draws': len(covs),
                                     'mean': round(sum(covs) / len(covs), 3), 'min': round(min(covs), 3),
                                     'max': round(max(covs), 3)})
    r['comments'] = compare_comments(ours, comp + cc, a.shingle, a.limit)
    r['idents'] = compare_idents(ours, {'AROS comparable (C+asm)': cc + comp,
                                        'AROS sans rapport (C+asm)': cu + unrel},
                                 wl_ids, a.ident_min_len, a.limit)
    r['numbers'] = compare_numbers(ours, {'AROS comparable (C+asm)': cc + comp,
                                          'AROS sans rapport (C+asm)': cu + unrel}, wl_nums, a.limit)
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as f:
            json.dump(r, f, ensure_ascii=False, indent=1)
    print(fmt_report(r))


if __name__ == '__main__':
    main()
