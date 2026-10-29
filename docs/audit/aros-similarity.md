# Textual similarity audit: our assembly against the AROS source code

This document answers a question raised in a GitHub issue: **does the code in `src/` reuse code
from AROS?** The README states that AROS was read as a reference (read-only) and that nothing was
copied. The measurement below compares all of our assembly (`src/**/*.s`, `src/**/*.i`) with the AROS
source code, then places the result relative to the "normal" level of coincidences between independent
68000 programs.

AROS is a public project (APL licence). Both sides are therefore quoted freely, in short excerpts.

## Verdict

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
