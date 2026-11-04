# Textual similarity audit: our assembly against the AROS source code

This document answers a question raised in a GitHub issue: **does the code in `src/` reuse code
from AROS?** The README states that AROS was read as a reference (read-only) and that nothing was
copied. The measurement below compares all of our assembly (`src/**/*.s`, `src/**/*.i`) with the AROS
source code, then places the result relative to the "normal" level of coincidences between independent
68000 programs.

AROS is a public project (APL licence). Both sides are therefore quoted freely, in short excerpts.

## Verdict

*Re-measured on 2026-11-03 (commit `2c6b1c6`) and on 2026-11-04 (commit `ac2546a`), all of `src/`: same verdict, see
the "Re-run" sections below.*

- **No measurable reuse of AROS code beyond the background noise, with one exception, short and
  mandated by the ABI.** At the 20-token threshold, 132 tokens out of 221,721 (0.06%) coincide textually
  with the AROS assembly. At the 30-token threshold, 69 remain (0.03%), in **only two
  passages**.
- **The only notable passage** is the entry and return of the BCPL runtime (`bcpl_call` / `bcpl_ret`,
  `src/dos/bcpl.s:51-62`). These are 8 instructions, identical to AROS's `BCPL_jsr` / `BCPL_rts`
  (`arch/m68k-all/dos/bcpl.S:23-29` and `:55-58`).
  - The shape of this code is dictated by the binary ABI of the Workbench 1.3 BCPL commands: frame
    layout (-12/-8/-4), registers A1/A3/A4/D0, multiplication **necessarily** at `+$10` and division
    at `+$12`.
  - The entry sequence is **exactly 16 bytes** long (2 + 6 + 2 + 4 + 2), which places `bra.s mul` at
    `+$10` without padding. There is hardly any other way to write it as directly.
  - See "Notable matches" for the details and the recommendation.
- **Everything else is made of 68000 and Amiga idioms**: save/restore `movem.l d2-d7/a2-a6`,
  copy `move.l (a0)+,(a1)+`, BPTR conversion `lsl.l #2`. These same idioms are found, in comparable
  proportion, in third-party Amiga code with no link at all to AROS (VMM, AHI, diskimage).
- **On the C side** (the bulk of AROS), no signal:
  - 4 comment n-grams in common, all explained;
  - the shared identifiers outside the ABI are generic descriptive names;
  - the shared "magic" constants are all public (HRM, documented formats).
- **The method does detect a real copy.** A positive control (two AROS files transliterated into
  vasm syntax, labels renamed, comments replaced) is found at 62–100% coverage, with
  passages of 76 to 199 tokens. Our real files peak at 42 tokens.

## Inputs

| Item | Value |
|---|---|
| Our code | `src/` at commit `ec9f9ab`, plus the uncommitted changes in `src/intuition/` present at the time of the measurement; 75 `.s`/`.i` files, 221,721 tokens (exact level) |
| AROS | official repository `aros-development-team/AROS`, commit `4dbf6509f4fea9a48643ec39565f60c9a6acac9a` (2026-10-29), partial (sparse) clone of the subtrees listed below |
| Tool | `tests/audit_aros_similarity.py` (Python 3, standard library only) |

### Local copy `third_party/aros`: insufficient for the audit

The project's working copy is a partial clone (`blob:none`) in *sparse checkout*, commit `30cdf16`.
It contains only the following subtrees:

- `rom/dos`;
- `arch/m68k-all/dos` (`bcpl.S`, `bcpl_writef.S`, `callentry.S`, `bcpl.inc`...);
- `arch/m68k-amiga/dos`;
- `compiler/include/dos`.

It therefore lacks:

- the other libraries: `rom/exec`, `rom/graphics`, `rom/intuition`, `rom/hyperlayers` (AROS's
  layers), `rom/expansion`, `rom/devs/*`, `rom/timer`, `rom/keymap`, `rom/filesys`;
- `workbench/libs/{workbench,icon,mathffp}`;
- the `arch/m68k-*` asm outside dos;
- all the public headers outside `dos`, which shrinks the ABI whitelist;
- any unrelated corpus for the baseline.

The tool runs on this copy and then displays a warning. Its results there are consistent with
those of the full audit: longest passage of 39 tokens (the same BCPL passage), 0.046% coverage
at k = 20. They are however not enough to conclude. The reference audit uses a wider partial
clone (see "Commands").

### What is comparable in AROS

- **AROS is written in C**: exec, dos, graphics, intuition, layers, devices... Its 68000 assembly is
  limited to primitives.
- "Comparable AROS" corpus: 65 files, 22,757 tokens. It includes:
  - the dos BCPL runtime (`bcpl.S`, `bcpl_writef.S`, `callentry.S`), i.e. 38% of this corpus;
  - exec: `Dispatch`, `Switch`, `Wait`, `Supervisor`, `StackSwap`, `CopyMem*`, caches, `Forbid`...;
  - the ROM startup (`arch/m68k-amiga/boot`) and the graphics blitter/layers stubs;
  - utility (32/64-bit multiplication/division) and mathffp (`spcmp`, `sptst`).
- Comparable C: 2,439 `.c`/`.h` files from `rom/`, `arch/m68k-*`, `workbench/{libs,c,fs,devs,system}`.
- "Unrelated" corpus: 202 asm files, 374,229 tokens, plus 1,308 C files. It consists of:
  - third-party code vendored in the AROS tree: Motorola 68060 FPSP/ISP (`m680x0/`), `libgcc1`, `stdc`,
    `posixc`, `inflate`, `rexxsyslib`, `mathieee*`;
  - third-party Amiga drivers and applications: AHI, diskimage, networking, VMM, pfs3.
  - **"Third-party Amiga"** subset: VMM, AHI and diskimage (86 files, 52,214 tokens). This is
    Amiga system software in asm, written outside the AROS project, with the same calling conventions as
    us. It is the most demanding baseline.

## Method

### asm vs asm: token fingerprints (MOSS-style)

1. **Dialect canonicalisation.** We use vasm in Motorola syntax. AROS uses GNU as
   with `%reg`, MIT syntax `a0@+` / `sp@-` / `a6@(8)` or Motorola syntax, `0x` or `$`. After
   canonicalisation, both sides write `move.l (a0)+,-(a7)`.
   - `sp` becomes `a7`; MIT suffixes (`movel`) become `move.l`; `jbsr`/`jra`/`jXX` become
     `bsr`/`bra`/`bXX`.
   - The branch size is removed: it is a choice of the assembler.
   - Numbers are converted to decimal.
   - Comments and purely declarative directives (`xdef`, `section`, `.globl`, `include`...) are
     removed.
2. **Three normalisation levels**:
   - `exact`: identifiers, numbers and registers kept (lower case);
   - `norm`: identifiers → `ID`, numbers → `N`, strings → `S`; label definitions and
     declarations (`equ`, `dc`/`ds`, structure macros) are removed, otherwise any "`NOM equ N`" table
     looks like any other;
   - `struct`: `norm`, plus generic registers (`D`/`A`) and merged mnemonics (`addq`/`addi`/`adda`
     → `add`, `jsr`/`bsr` → `call`, `jmp`/`bra` → `jump`...).
3. **Fingerprints.** We compute the token k-grams (k = 12, 20, 30), a deterministic hash (crc32)
   and *winnowing* (Schleimer et al., 2003) with a window w = 8. The overlap per pair of
   files is |F(us) ∩ F(AROS)| / |F(us)|.
4. **Maximal common passages.** A full index of the k-grams of the target corpus is used to extend each
   match to its maximal length. Each passage is checked token by token, with no hash false
   positive. For each one, the file and lines on both sides are recorded.
   - **Coverage**: % of our tokens located in a common passage of at least k tokens.
   - A k-gram present more than 200 times in the target corpus is deemed trivial and is not used as a
     starting point.

Order of magnitude: a 68000 instruction is 4 to 8 tokens (`move.l ( a0 ) + , d1` = 8). k = 12
therefore corresponds to about 2 instructions, k = 20 to 3–4, k = 30 to 5–6.

### asm vs C: comments, identifiers, constants

Comparing asm tokens with C tokens would make no sense. Instead we compare:

- **Comments.** We look for the word 5-grams common to our comments and those of AROS
  (C and asm).
  - **Bias**: our comments are in French (6,789 lines identified as French, 5 lines
    classified as English, 4 of them false positives), those of AROS in English.
  - A literal translation of an AROS comment would therefore escape this measurement; only
    English quotations are detectable.
- **Identifiers.** We compare our labels and symbols with the identifiers of the AROS C and asm, ignoring
  case and `_`, and after stripping the `LVO_`/`_LVO` prefix. Only names of at
  least 6 characters are kept.
  - **ABI whitelist**: any identifier present in an AROS public header (`compiler/include`
    and the modules' `include/` folders, for example `rom/devs/console/include` → `devices/conunit.h`)
    or in the `.conf`/`.fd` function lists.
  - That makes 30,249 identifiers: LVO names, NDK structure fields, constants of the public
    headers. These names are mandated by the ABI and prove nothing.
- **"Magic" constants.** We keep the values ≥ `$1000` that are:
  - not multiples of 100;
  - not contiguous bit masks;
  - not in the HRM hardware address ranges;
  - not present in the public headers.

### Baselines

- **src → third-party Amiga asm** (VMM, AHI, diskimage) and **src → all unrelated asm**: same computation,
  other targets.
- **Equal-size baseline.** Coverage grows with the size of the target corpus. We therefore draw 5
  random subsets (seeds 0 to 4) of the third-party Amiga asm, each the size of the comparable AROS
  corpus (22,757 tokens), and measure the coverage of our code against them.
- **BASELINE: comparable AROS → third-party Amiga asm**: the level of overlap between AROS and independent Amiga
  code.
- **Positive control** (outside the tool, throwaway unversioned scripts), to check that the tool sees a
  real copy:
  - two AROS files, `arch/m68k-all/exec/dispatch.S` and `arch/m68k-all/dos/bcpl_writef.S`, were
    automatically transliterated into vasm Motorola syntax;
  - their labels were renamed (`ks_…`, `.nN`), their comments removed and a French
    comment added on each line;
  - both files were added to a copy of `src/`;
  - the tool was then run on this copy.

## Commands

```sh
# 1. Partial clone of AROS limited to the useful subtrees (about 56 MB excluding .git)
git clone --filter=blob:none --sparse --depth 1 https://github.com/aros-development-team/AROS.git aros
cd aros
git fetch --depth 1 origin 4dbf6509f4fea9a48643ec39565f60c9a6acac9a
git checkout FETCH_HEAD
git sparse-checkout set --no-cone '/arch/m68k-all/' '/arch/m68k-amiga/' '/rom/exec/' '/rom/dos/' \
  '/rom/graphics/' '/rom/intuition/' '/rom/hyperlayers/' '/rom/expansion/' '/rom/devs/console/' \
  '/rom/devs/gameport/' '/rom/devs/input/' '/rom/devs/keyboard/' '/rom/devs/trackdisk/' '/rom/timer/' \
  '/rom/keymap/' '/rom/utility/' '/rom/misc/' '/rom/disk/' '/rom/filesys/' '/rom/dosboot/' \
  '/rom/lddemon/' '/rom/kernel/' '/rom/hidds/' '/workbench/libs/mathffp/' '/workbench/libs/workbench/' \
  '/workbench/libs/icon/' '/workbench/devs/' '/workbench/c/' '/workbench/system/' '/workbench/fs/' \
  '/compiler/include/'
cd ..

# 2. Audit (about 2 minutes; Markdown report on stdout, raw results in JSON)
python3 -I tests/audit_aros_similarity.py src aros -k 12 20 30 --limit 20 --json audit.json > audit.md
```

Useful options:

- `-w`: winnowing window;
- `--levels`: normalisation levels to compute;
- `--unrelated` / `--amiga-tiers`: path patterns of the baseline corpora;
- `--shingle`: size of the comment n-grams;
- `--ident-min-len`: minimum length of the compared identifiers;
- `--draws`: number of draws of the equal-size baseline.

## Results

### asm vs asm: coverage of our code (% of tokens)

"Equal-size baseline" gives the mean and the [min–max] interval of 5 draws of third-party Amiga asm of
22,757 tokens (21,195 at the norm/struct levels).

| k | level | src → comparable AROS | src → equal-size baseline (third-party Amiga) | src → third-party Amiga (52 k tokens) | src → all unrelated asm (374 k) | BASELINE: comparable AROS → third-party Amiga |
|---|---|---|---|---|---|---|
| 12 | exact | 2.876 | 1.563 [0.969–2.071] | 2.642 | 2.957 | 6.402 |
| 12 | norm | 6.362 | 8.698 [7.361–10.538] | 12.751 | 14.249 | 13.286 |
| 12 | struct | 28.552 | 34.192 [28.806–40.188] | 42.646 | 49.337 | 30.073 |
| 20 | exact | **0.060** | 0.004 [0–0.009] | 0.009 | 0.009 | 0 |
| 20 | norm | 0.517 | 0.438 [0.241–0.713] | 0.835 | 0.845 | 0.193 |
| 20 | struct | 3.309 | 3.126 [1.748–4.431] | 4.939 | 5.986 | 2.085 |
| 30 | exact | **0.031** | 0 | 0 | 0 | 0 |
| 30 | norm | 0.139 | 0.003 [0–0.017] | 0.017 | 0.017 | 0 |
| 30 | struct | 0.622 | 0.056 [0–0.087] | 0.104 | 0.330 | 0.311 |

How to read the table:

- **norm and struct levels.** Our code resembles AROS less than it resembles third-party Amiga code of the same
  size, or hardly more.
- **Exact level at k = 12.** The excess over the baseline (2.9% against 1.6%) is explained by the composition
  of the AROS corpus.
  - This corpus is small, centred on the same calling conventions as us, and 38% made of the BCPL
    runtime that we also implement.
  - The 199 distinct passages are dominated by `movem.l (a7)+,d2-d7/a2-a6` / `rts`,
    `movem.l d0-d1/a0-a1,…` and `move.l (a0)+,(a1)+`.
  - The AROS asm itself shares twice as much (6.4%) with the third-party Amiga code.
- **Exact level at k ≥ 20 and norm/struct levels at k = 30.** The excess is entirely due to the few
  passages listed below: 132 tokens in total at k = 20 exact.

### Fingerprint overlap per pair of files (maximum over all our pairs)

| k | exact | norm | struct |
|---|---|---|---|
| 12 | 1.45% (`exec/romboot.s` ↔ `bcpl.S`, 2 fingerprints) | 3.33% | 8.57% |
| 20 | 0.24% (`dos/bcpl.s` ↔ `bcpl.S`) | 0.38% | 1.79% |
| 30 | 0.08% (`dos/bcpl.s` ↔ `bcpl.S`) | 0.05% | 0.11% |

### Positive control (transliterated and renamed copy)

| Control file | k = 12 exact | k = 12 norm | k = 30 norm | overlap per pair (k = 12 norm) | longest passage |
|---|---|---|---|---|---|
| `bcpl_writef.S` transliterated | 89.6% | 100% | 99.3% | 93.1% | 199 tokens (norm) |
| `dispatch.S` transliterated | 75.8% | (\*) | 62.0% | 54.2% | 76 tokens |

(\*) This file does not appear in the top 15 by covered tokens at this level; it is 62% covered
at the k = 20 and k = 30 levels.

The tool therefore finds a real copy, even reformatted and renamed, with scores at least 25 times
higher than those of our real files. It also sees a real copy inside the AROS tree
itself: `arch/m68k-all/exec/stackswap.S:54-108` ↔ `rom/filesys/pfs3/fs/m68k/stackswap.S:57-112`,
160 tokens, 97% overlap.

### Comments (word 5-grams)

60,136 n-grams on our side, 169,240 on the AROS side, **4 in common**:

| On our side | On the AROS side | Nature |
|---|---|---|
| `src/dos/dos_lib.s:181`: "AutoDoc: *All three elements are zero if the date is unset*" (2 n-grams) | `rom/dos/datestamp.c:41` (AutoDoc block of `DateStamp`) | Explicit quotation, in quotation marks and attributed to "AutoDoc", of a sentence describing the public behaviour of `DateStamp()` |
| `src/dos/bcpl.s:1072`, `src/exec/keyboard.s:90`, `src/graphics/gfx.s:22`: list "d0 d1 a0 a1 a2" | `arch/m68k-all/dos/bcpl.S:1669` | Register list |
| `src/intuition/menus.s:1041`: fields "Left, Top, Width, Height, Depth" of `struct Image` | `rom/intuition/openscreentaglist.c:248` | Public field names |

### Identifiers

- We have 8,374 distinct identifiers.
  - With comparable AROS: 903 in common, 784 of them on the ABI whitelist. That leaves **53** names
    of at least 6 characters outside the ABI.
  - With unrelated AROS: 557 in common, 470 of them ABI. That leaves **21** names outside the ABI.
- All 53 names were reviewed. They break down as follows:
  - **Public function name + module prefix**: `exec_openlibrary` ↔ `ExecOpenLibrary`,
    `dos_expunge` ↔ `DosExpunge`, `intuition_open`, `timer_open`, `cia_init` ↔ `Cia_Init`,
    `cia_romtag`, `romboot_end`, `gfx_vblank`, `dev_open`/`dev_close`.
  - **Generic words**: `delete`, `frame_size`, `task_name`, `input_size`, `msg_fail`, `c_block`,
    `cb_next`.
  - **Case collisions with public names**: our `TD_MOTORON` (state byte in low RAM) ↔
    `td_motoron` (AROS function); our labels `.findinput`/`.findoutput`/`.copydir`/`.diskinfo`, named
    after the public packet actions `ACTION_*`.
  - **`Layer` structure field prefix**: our equates `LY_FRONT`... `LY_LOCK`... `LY_DAMAGE`
    (complete series, `src/graphics/layers.s:37`, `draw.s:76`). AROS only generates `ly_Lock`
    (`compiler/include/asm.c:166`). The abbreviation "LaYer" is natural and the series on our side is
    much wider: a naming coincidence with no significance.
- The rate outside the ABI (53 out of 41,856 names on the comparable AROS side) is of the same order as against the
  unrelated corpus (21 out of 55,724). No distinctive internal AROS name appears.

### Constants

- We have 805 distinct values, 175 of them non-trivial.
  - In common with comparable AROS: 22 "magic" ones outside the public headers.
  - In common with unrelated AROS: 31.
- All those of the comparable list are public or trivial:
  - **MFM sync word** `$4489` / `$44894489` (HRM);
  - **4-character identifiers** `'CON\0'`, `'RAW\0'`, `'BAD\0'`, `'BUSY'`, `'HELP'`;
  - **PAL E-clock frequency** 709,379 Hz (`$AD303`);
  - **FFP format** `$80000041` (1.0 in FFP);
  - **custom register values** `$2C81` (standard DIWSTRT) and `$8240` (DMACON);
  - **patterns** `$DEADBEEF`, `$11111111`, `$8888`, `$2222`, `$F0F0`, `$80008000`, `$30003`, `$20003`.
- No AROS-specific private constant.

## Notable matches

| # | On our side | On the AROS side | Length | Nature |
|---|---|---|---|---|
| 1 | `src/dos/bcpl.s:51-57` (`bcpl_call`) | `arch/m68k-all/dos/bcpl.S:23-29` (`BCPL_jsr`) | 39 tokens exact, 7 instructions + 2 `bra.s` | BCPL entry, mandated by the ABI (see below) |
| 2 | `src/dos/bcpl.s:59-62` (`bcpl_ret`) | `arch/m68k-all/dos/bcpl.S:55-58` (`BCPL_rts`) | 23 tokens exact, 3 instructions | BCPL return, mandated by the ABI |
| 3 | `src/dos/handler.s:962-964` | `arch/m68k-all/exec/copymem_020.S:51-53` | 30 tokens, 3 × `move.l (a0)+,(a1)+` | Copy of a 12-byte `DateStamp`: idiom |
| 4 | `src/dos/bcpl.s:1892-1896` (`g_compstamp`) | `arch/m68k-all/dos/bcpl.S:831-835` | 20 tokens | BPTR → address conversion (`lsl.l #2` then `move.l` to An), twice: universal BCPL idiom |
| 5 | `src/graphics/layers.s:1174-1183` and about ten other function epilogues | `arch/m68k-all/dos/callentry.S:118-129` | 20–36 tokens | `movem.l (a7)+,d2-d7/a2-a6` / `rts` / `movem.l d2-d7/a2-a6,-(a7)`: Amiga register convention, also present in AHI and VMM |
| 6 | `src/dos/bcpl.s:2107-2115` (writef `%S %T %C…`), `src/exec/rawdofmt.s:83-91` | `arch/m68k-all/dos/bcpl.S:1218-1226` (number parsing) | 33 tokens, struct level only | `cmp.b #c,Dn` / `beq` chain on different characters: same shape, different code |

### The BCPL passage (no. 1 and 2) in detail

On our side (`src/dos/bcpl.s:51-62`):

```
bcpl_call:
        move.l  (sp)+,a3
        movem.l a1/a3-a4,-12(a1,d0.l)
        adda.l  d0,a1
        movem.l d1-d4,(a1)
        jmp     (a4)
        bra.s   bcpl_mul             ; bcpl_call+$10
        bra.s   bcpl_divmod          ; bcpl_call+$12
bcpl_ret:
        movem.l -12(a1),a1/a3
        move.l  -4(a1),a4
        jmp     (a3)
```

On the AROS side (`arch/m68k-all/dos/bcpl.S:23-29`, `:55-58`), the same instructions are found in GNU
syntax (`%sp@+`, `%a1`...). The routines that follow differ entirely:

- in AROS, `BCPL_jsr_mult` / `_divmod` call GCC's `__mulsi3` / `__modsi3` / `__divsi3`;
- on our side, `bcpl_mul` / `bcpl_divmod` are hand-written 32-bit multiplications and divisions
  using `mulu.w` / `divu.w`.

The rest of `bcpl.s` (3,027 lines: global vector, 150 globals, `writef`, `rdargs`, `splitname`...)
shares little with `bcpl.S`:

- **exact level**: no passage longer than 20 tokens;
- **norm level**: a single one, of 22 tokens (`bcpl.s:1892`, double BPTR conversion);
- **struct level** (registers and names erased): 34 tokens at most. These are BPTR conversions followed
  by a byte loop, and `cmp.b`/`beq` chains, i.e. about 5 instructions of ordinary shape.

This passage is constrained by the ABI, not by a writing choice:

- the Workbench 1.3 BCPL commands do `jsr (a5)` to call, `jsr $10(a5)` to multiply and
  `jsr $12(a5)` to divide;
- the callee reads its arguments in the frame starting at A1, and the old A1, the return address and the called
  routine at -12/-8/-4.

The entry must therefore fit in exactly 16 bytes before the two `bra.s`. The sequence above is
2 + 6 + 2 + 4 + 2 = 16 bytes. It is the minimal expression of this convention, and AROS arrived at the
same one. The header of `bcpl.s` moreover states that AROS `arch/m68k-all/dos` was read as a reference
("read-only, nothing copied"). The textual resemblance of these 10 lines is therefore real, and it is
documented.

**Recommendation** (at the maintainers' choice, none is required for compliance):

- (a) **keep** the passage, adding in `bcpl.s` a comment saying that the sequence is
  mandated (16 bytes, `+$10`/`+$12`) and identical to that of AROS `BCPL_jsr`/`BCPL_rts`;
- (b) **rewrite** the entry with another functionally equivalent 16-byte sequence, for
  example by saving the old A1, the return address and A4 with three `move.l` after `adda.l`, then adjusting the
  padding. This gives zero textual identity, at the cost of slightly less direct code.

### AutoDoc quotation (comments)

The sentence "*All three elements are zero if the date is unset*" is quoted in quotation marks and
attributed to the AutoDoc. If it comes from the AROS AutoDoc and not from the Commodore AutoDoc, it is enough to
fix the attribution, or to rephrase it in French.

*Follow-up (2026-10-29): the quotation was removed from `src/dos/dos_lib.s` and replaced by a plain comment.*

## Re-run 2026-11-03 (commit `2c6b1c6`, tag `v0.2.15`)

The measurement was repeated over **all of `src/`** (the procedure of this document), 69 commits after `ec9f9ab`,
by a separate analysis agent. Same tool, same AROS commit, same options.

### Inputs

| Item | Value |
|---|---|
| Our code | `src/` at commit `2c6b1c6`, clean tree; 76 `.s`/`.i` files (the new one is `src/softkick/bootblock.s`), 248,319 tokens (exact level, +12% since `ec9f9ab`), 209,420 at the norm/struct levels |
| AROS | same commit `4dbf6509f4fea9a48643ec39565f60c9a6acac9a`, same sparse subtrees, cloned into `build/audit/aros` |
| Corpora | unchanged: comparable AROS asm 65 files / 22,757 tokens; unrelated asm 202 files / 374,229 tokens; third-party Amiga 86 files / 52,214 tokens; 2,439 + 1,308 C files; 599 whitelist files, 30,249 ABI identifiers |

```sh
python3 -I tests/audit_aros_similarity.py src build/audit/aros -k 12 20 30 --limit 20 \
    --json build/audit/aros-audit.json > build/audit/aros-audit.md
# full lists of shared comments, identifiers and constants (same tool, larger limit):
python3 -I tests/audit_aros_similarity.py src build/audit/aros -k 20 --levels exact --draws 1 --limit 300 \
    --json build/audit/aros-full.json > build/audit/aros-full.md
```

The rows that do not depend on our code ("BASELINE: comparable AROS → third-party Amiga", all levels and k) are
identical to the original table, which confirms the same corpora.

### asm vs asm: coverage of our code (% of tokens), 2026-11-03

Previous values (`ec9f9ab`) in parentheses.

| k | level | src → comparable AROS | src → equal-size baseline (third-party Amiga) | src → third-party Amiga (52 k tokens) | src → all unrelated asm (374 k) | BASELINE: comparable AROS → third-party Amiga |
|---|---|---|---|---|---|---|
| 12 | exact | 2.858 (2.876) | 1.601 [1.081–2.061] | 2.670 (2.642) | 3.028 (2.957) | 6.402 |
| 12 | norm | 6.348 (6.362) | 8.536 [7.268–10.392] | 12.484 (12.751) | 14.069 (14.249) | 13.286 |
| 12 | struct | 28.206 (28.552) | 33.733 [28.542–39.741] | 42.091 (42.646) | 48.790 (49.337) | 30.073 |
| 20 | exact | **0.053** (0.060) | 0.003 [0–0.008] | 0.008 (0.009) | 0.047 (0.009) | 0 |
| 20 | norm | 0.513 (0.517) | 0.425 [0.225–0.731] | 0.830 (0.835) | 0.861 (0.845) | 0.193 |
| 20 | struct | 3.194 (3.309) | 2.948 [1.694–4.227] | 4.702 (4.939) | 5.746 (5.986) | 2.085 |
| 30 | exact | **0.028** (0.031) | 0 | 0 | 0.039 (0) | 0 |
| 30 | norm | 0.124 (0.139) | 0.003 [0–0.015] | 0.015 (0.017) | 0.015 (0.017) | 0 |
| 30 | struct | 0.584 (0.622) | 0.050 [0–0.078] | 0.093 (0.104) | 0.310 (0.330) | 0.311 |

- **Against comparable AROS, the covered tokens did not grow**: 132 tokens at k = 20 exact and 69 at k = 30 exact,
  exactly as before, in the same five passages. The percentages fall only because our code grew.
- **Longest passages, unchanged:** 39 tokens exact (`bcpl_call`, now `src/dos/bcpl.s:55-61`), 42 tokens at the
  norm and struct levels (the same passage plus the two `bra.s`). Then the 30-token `DateStamp` copy
  (`src/dos/handler.s:997-999`), `bcpl_ret` (23 tokens, `bcpl.s:63-66`), the double BPTR conversion (20 tokens,
  `bcpl.s:1938-1942`) and the `movem.l d2-d7/a2-a6` epilogues of `layers.s` (20 tokens): the passages no. 1 to 5 of
  "Notable matches", moved by a few lines.
- **New at the struct level, k = 30** (registers and names erased, shape only): 30–35-token passages between
  function epilogue/prologue pairs (`lea`/`addq` of the stack, `movem.l` restore, `rts`, `movem.l` save) of
  `intuition/gadgets.s:1645`, `intuition/sysreq.s:123`, `dos/shell.s:289`, `dos/ofs.s:491`, `graphics/gels.s:713`
  and AROS `callentry.S` / `cachecontrol_.S`; and a character-class test chain in `dos/ofs.s:306` (`sub.b`, `cmp.b`,
  `bcs`/`bhi`) against `bcpl.S` number parsing. Same nature as passages no. 5 and 6: the Amiga register convention
  and `cmp`/`branch` chains.
- **"All unrelated asm" at k = 20/30 exact rises (0.009 → 0.047, 0 → 0.039).** The cause is a single 48-token
  passage, twice: the zero-filled `dc.l 0,0,0,0` rows of the keymap tables (`src/exec/keymapdata.s:63-68` and
  `:157-162`) against zero tables of the Motorola 68060 FPSP. Padding, not code.

### Fingerprint overlap per pair of files (maximum), 2026-11-03

| k | exact | norm | struct |
|---|---|---|---|
| 12 | 1.45% (`exec/romboot.s` ↔ `bcpl.S`) | 3.33% (`exec/ramlib.s` ↔ `bcpl.S`) | 7.14% (`exec/misc.s` ↔ `bcpl.S`) |
| 20 | 0.24% (`dos/bcpl.s` ↔ `bcpl.S`) | 0.38% (`dos/bcpl.s` ↔ `bcpl.S`) | 1.79% (`exec/romboot.s` ↔ `cachepredma_.S`) |
| 30 | 0.08% (`dos/bcpl.s` ↔ `bcpl.S`) | 0.05% (`dos/bcpl.s` ↔ `bcpl.S`) | 0.11% (`graphics/gels.s` ↔ `callentry.S`) |

Same maxima as before, except struct k = 12 (7.14% against 8.57%).

### Comments

- Our comments are now in English (13,708 comment lines: 5,449 identified as English, 74 as French, the rest
  undetermined). The language bias noted in "Limits" is therefore gone, and the comparison is now meaningful.
- 66,156 word 5-grams on our side, 169,240 on the AROS side, **102 in common** (4 before, while our comments were in
  French). All 102 were reviewed (`build/audit/aros-full.json`):
  - **generic English phrases**, the vast majority: "at the end of the", "to the start of the", "the head of the
    list", "remove it from the list", "if the screen is not", "the rest of the line"...;
  - **register lists**: "d0 d1 a0 a1 a2", "d0 d1 a0 a1 a5", "d0 d7 a0 a6 60" (a 15-register frame of 60 bytes);
  - **public Amiga vocabulary** (RKRM/AutoDoc terms): "parts of a simple layer", "layer in front of which",
    "contents of the ClipRect's bitmap", "the screen's title bar", "the task's user stack", "Left, Top, Width,
    Height, Depth" (already listed).
- The longest common phrases are 6 words. Three were checked against both sources:
  - `src/graphics/layers.s:547` ("the layer shows the SuperBitMap from its corner (0,0)") ↔
    `rom/hyperlayers/basicfuncs.c:1202` ("the layer shows the superbitmap from Scroll_X/Y"): a natural description
    of SUPERBITMAP layers; the rest of the sentences differ;
  - `src/graphics/layers.s:1198` (`SwapBitsRastPortClipRect`: "swaps the contents of the ClipRect's area...") ↔
    `rom/hyperlayers/swapbitsrastportcliprect.c:75` ("Display the contents of the ClipRect's BitMap"): the public
    function name spelt out;
  - `src/exec/boot.s:820` ("a caller can block itself, the resource does not track owners", attributed to the
    AutoDoc of `AllocPotBits`) ↔ `arch/m68k-amiga/potgo/freepotbits.c:36` (AROS AutoDoc NOTES: "The resource does
    not track task ownership"): same fact, four words in common, different sentences.
- No comment sentence of AROS is reproduced.

### Identifiers

- 9,264 distinct identifiers on our side (8,374 before).
  - With comparable AROS: 949 in common, 817 of them on the ABI whitelist, **61** outside the ABI (53 before).
  - With unrelated AROS: 576 in common, 479 ABI, **24** outside the ABI (21 before).
- All 61 were reviewed; they fall into the same categories as before:
  - public function names with a module prefix (`exec_openlibrary`, `dos_expunge`, `intuition_open`, `cia_init`,
    `timer_open`...);
  - generic words or sizes (`buf_size`, `img_size`, `frame_size`, `.normal`, `.delete`, `task_name`, `msg_fail`,
    `init_memory`, `resmax`);
  - lower-case forms of public structure fields and constants (`cr_flags`, `rp_font`, `ib_gfxbase`, `ib_prefs`,
    `ly_lock`, `ns_type`, `km_name`, `color00`, `tdu_present`, `.findinput`/`.findupdate`/`.diskinfo` after the
    `ACTION_*` packets);
  - descriptive names of our trackdisk and Workbench routines (`td_motor_on`, `td_read_track`, `td_select`,
    `wb_window`, `wb_menupick`, `wb_opendrawer`, `wb_version`) colliding with AROS trackdisk and Workbook names.
- New since `ec9f9ab`: `cpu_detect` (`src/exec/boot.s:263`, 68010/68020 support) ↔ AROS
  `arch/m68k-amiga/boot/cpu_detect.S`. The name is descriptive. A dedicated k = 12 run over `exec/boot.s`,
  `execmisc.s`, `interrupts.s` and `exec.i` finds **no passage** between our routine and `cpu_detect.S`, at any
  level; the only k = 12 passages of these files against AROS exec are `movem.l` register restores (14 tokens).
- No distinctive internal AROS name appears.

### Constants

- 904 distinct values on our side, 256 non-trivial (805 / 175 before).
  - In common with comparable AROS: **26** "magic" ones outside the public headers (22 before).
  - In common with unrelated AROS: 36 (31 before).
- The comparable list is still public or trivial: the values of the original review (MFM sync `$4489`/`$44894489`,
  `'CON\0'`/`'RAW\0'`/`'BAD\0'`/`'BUSY'`/`'HELP'`, `$AD303`, FFP `$80000041`, `$2C81`, `$8240`, the
  `$DEADBEEF`/`$11111111`/`$8888`/`$2222`/`$F0F0`/`$80008000`/`$30003`/`$20003` patterns), plus:
  - `$800000C1` (-1.0 in FFP, `src/exec/mathffp.s`), public FFP format;
  - `$01000200` (`src/intuition/alert.s`, copper move of BPLCON0) and `$F4C1` (`graphics_lib.s`, standard DIWSTOP):
    custom register values from the HRM;
  - `$40C0` (`interrupts.s`): the public opcode of `move.w sr,Dn`, tested for 68010 privilege handling;
  - `$8100` (`pointer.s`, a row of our own pointer image), `$4444` (`gadgets.s`, a fill pattern) and `$B2B2B2B2`
    (`keymapdata.s`, keymap bytes): coincidences, each found in a single AROS file with an unrelated purpose.
- No AROS-specific private constant.

### Notable matches and verdict 2026-11-03

- The notable matches are the same six as in "Notable matches", at new line numbers: `bcpl_call` (39 tokens) and
  `bcpl_ret` (23 tokens), mandated by the BCPL ABI; recommendation (a) has since been applied (`src/dos/bcpl.s:52-54`
  states that the sequence is fixed and identical to AROS `BCPL_jsr`/`BCPL_rts`). The others are idioms.
- **No new passage** of 20 tokens or more (exact) comes from the code added since `ec9f9ab`.
- **Verdict: PASS.** No measurable reuse of AROS code beyond the background noise and the documented, ABI-imposed
  BCPL entry/return. The positive control (transliterated copy) was not re-run: the tool and its parameters are
  unchanged.

## Re-run 2026-11-04 (commit `ac2546a`)

Same tool, same AROS checkout (`build/audit/aros`, commit `4dbf650`), all of `src/` of a clean worktree at `ac2546a`
(after the console commands, the gadget list and requester rules, the string gadgets, the DF0: locks and disk
requesters, the packed boot image):

```sh
python3 -I tests/audit_aros_similarity.py <worktree>/src build/audit/aros -k 12 20 30 --limit 20 --json aros.json > aros.md
```

| comparison (k = 12, w = 8) | level | our tokens | longest run (tokens), 2026-11-03 → 2026-11-04 |
|---|---|---|---|
| src → AROS asm comparable | exact | 263,627 | 39 → 39 |
| src → AROS asm comparable | norm / struct | 223,004 | 42 → 42 |
| src → unrelated AROS asm (baseline) | norm / struct | 223,004 | 31 / 49 → 33 / 49 |
| src → third-party Amiga asm (baseline) | norm / struct | 223,004 | 31 / 33 → 33 / 33 |

Coverage against comparable AROS asm stays at 0.11 % (exact), 0.33 % (norm) and 1.36 % (struct), at or below the
baselines. **Verdict unchanged**: the longest run against AROS is still the 42-token BCPL bridge entry imposed by the
1.3 ABI, below the unrelated-code baseline.

## Limits

- **Scope of the compared code.** AROS is almost entirely in C; the comparable asm is only 22,757
  tokens, about 10% of our code.
  - A transcription of AROS C into assembly (same algorithm, same decomposition) leaves no lexical
    trace. Neither this tool nor any textual comparison would detect it.
  - Only a design review would. The clean-room discipline described in
    `docs/CLEANROOM.md` addresses this risk.
- **Language bias.** Our comments are in French, those of AROS in English. The comment
  comparison only sees English quotations, not translations.
  *Note: this describes the state at measurement time. On 2026-10-29, after the measurement, all code comments
  were translated to English (object code byte-identical); re-running the comment comparison now would remove this
  bias.*
- **AROS version.** The measurement covers AROS as of 2026-10-29. A passage present in an older
  AROS version, consulted at the time and since rewritten on their side, would escape this measurement.
  `arch/m68k-all/dos/bcpl.S` and `callentry.S` have however existed in this form for a long time.
- **Whitelist.** It is built from the AROS headers, not from the Commodore NDK.
  - A public NDK name absent from the AROS headers would wrongly appear as "outside the ABI". The error goes
    in the cautious direction: it overestimates.
  - The identifier comparison ignores case and `_`, which also overestimates collisions.
- **Baseline.** The third-party Amiga corpus (VMM, AHI, diskimage) has its own style. The equal-size
  baseline varies from one draw to another, hence the [min–max] intervals given.
- **Parameters.** With k = 12 (about 2 instructions), idioms dominate; from k = 20 on, the
  measurement becomes discriminating. The results are given for three values of k so that the reader
  can judge stability.
- **Other possible source.** This audit only covers the relationship with AROS. The relationship with the Commodore
  ROM is the subject of a separate audit: `docs/audit/rom-similarity.md`.
