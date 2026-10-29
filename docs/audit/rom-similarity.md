# Binary similarity audit: our ROM against the original Kickstart 1.3

This document answers a precise question: **does our ROM contain code taken from the Commodore
Kickstart**, for example through memorisation of the leaked Kickstart sources? The measurement compares
the binary image we distribute with the real 1.3 ROM, then places the result relative to the "normal"
level of coincidences between unrelated 68000 programs.

The report contains **nothing from the original ROM**: no bytes, no disassembly, no offset. The
matches are located only in **our** ROM.

## Verdict

- **No code sequence of our ROM coincides with the original ROM beyond what unrelated
  programs already share with it.** The longest code match in our ROM
  is **20 16-bit words (13 instructions)**. A corpus of third-party games and utilities unrelated
  to Commodore goes up to **39 words (18 instructions)**.
- The only matches longer than this baseline are **mandated data**:
  - six function vector tables (libraries and `dos`), whose normalisation keeps only
    the number of entries, fixed by the ABI;
  - an arithmetic character-location table (fixed-width 8-pixel font), which is
    also found identically in the AROS ROM.
- The method **does detect a real kinship** when one exists:
  - the Commodore code of the Workbench 1.3.3 disk (commands, handlers, libraries), outside the ROM but
    coming from the same toolchain, shares with the ROM up to 121 words (96 exact instructions,
    257 in loose mode) and covers 3.8% of its code with matches of 8 words or more;
  - the self-check using relocated copies finds 12 fragments out of 12.
- **None of our code's routines needs rewriting** in view of this measurement.

## Inputs

| role | file | size | sha1 |
|---|---|---|---|
| our ROM (production, distributed) | `build/kick13-prod.rom` (`make kick-prod`) | 262,144 bytes | `3736299fe3bb5daf64732b349d76870b019e60d7` |
| our ROM (dev) | `build/kick13.rom` (`make kick`) | 262,144 bytes | `aa2d86620eebc48188594ea50c75e41a5b72c89d` |
| reference | `assets/kick34005.A500`, Kickstart 1.3 rev. 34.5 (A500), outside the repository | 262,144 bytes | `891e9a547772fe0c6c19b610baf8bc4ea7fcb785` |

Both ROMs were measured on the builds of 2026-10-29 (commit `ec9f9ab`). The dev ROM
also contained in-progress local changes in `src/intuition/`.

**Symbol table.** It comes from a relink of the existing objects, without recompiling anything, with
the exact object list and link script of the `Makefile`. The resulting binary is **byte-for-byte
identical** to the `build/kick.bin` of the dev build. It is also identical to the first 201,532 (dev) and 200,020
(prod) bytes of the corresponding ROM: `mkrom.py` only adds the padding and the footer
(size, checksum, vectors).

**Controls.** Their executables were extracted from the ADFs in `assets/test_adf/` with
`xdftool <adf> unpack <folder>`. Only CODE hunks are measured.

| group | role | contents | code volume |
|---|---|---|---|
| `tiers` | **unrelated baseline** (sets the threshold) | Holiday Lemmings (`HolidayLemmings`, `flt-intro`), Monkey Island FR disk 1 (`monkey_island`, `defjam`), SimCity 1.2 (`SimCity`, `SimData3`, `ZoneEvolutionChart`, `S/RAZOR.EXE`), SysInfo (`SysInfo`, `68040.library`, `68060.library`, `mmu.library`, recent `c/SetPatch`), `c/muchmore` (public domain, WB disk) | 596,048 bytes, 21 hunks |
| `commodore` | kinship control (Commodore code outside the ROM) | Workbench 1.3.3: `c/*` except `muchmore` and `TDPatch13`, `l/*` except `MSDOSFileSystem`, `libs/`, `devs/*` except `mfm.device` and `keymaps`, `System/`, `Prefs/`, `Utilities/` | 413,374 bytes, 390 hunks |
| `aros` | another independent reimplementation | AROS m68k boot disk: `aros.rom.gz` (decompressed), `AROSBootstrap`, `C/*`, `Libs/*` | 1,167,084 bytes, 50 hunks |

The Scooby-Doo disk provides no usable hunk executable, Monkey Island disk 4
contains only data, and the file system of the Caesar ADF is unreadable by `xdftool`.
The executables shipped with the games (`c/` of Monkey Island, `C/`, `L/`, `LIBS/` and `Devs/` of
SimCity) are copies of Commodore files: they are not in the `tiers` group.

## Method

The tool is `tests/audit_rom_similarity.py` (Python 3, stdlib; `capstone` optional for the instruction
streams). Its header details the method, summarised here.

1. **16-bit alignment**, as the 68000 requires.
2. **Normalisation of what necessarily changes from one build to another**, so as not to underestimate a
   relocated copy:
   - every long word pointing into the ROM (window `$F80000`–`$FFFFFF`) becomes the token `ADDR`;
   - in hunks, relocated long words (`HUNK_RELOC32`) also become `ADDR`;
   - the displacements of `Bcc`/`BRA`/`BSR` (8 and 16 bits), of `DBcc` and of the `d16(PC)` and
     `d8(PC,Xn)` modes are erased;
   - padding runs (8 identical words or more) become sentinels that never
     match.
3. **Three token streams**:
   - `mots` (words): raw normalised stream, without a decoder, hence insensitive to disassembly
     desynchronisations;
   - `instr`: linear 68000 disassembly (capstone), one instruction = mnemonic + operands,
     with targets, PC displacements and ROM addresses masked;
   - `instr-souple` (loose instructions): like `instr`, but with registers and constants erased, to withstand
     register renaming.
4. **Metrics**, for each pair (A, B):
   - maximal exact matches of A in B, computed with the suffix automaton of B:
     maximum length, number of matches of 8, 16 and 32 tokens or more, and share of A
     they cover;
   - n-gram overlap (n = 4, 8, 16): share of the distinct n-grams of A present in B.
5. **Classification of each match** from the bytes of A: text, low entropy, address
   table (≥ 60% `ADDR`/`DISP` tokens), arithmetic table (progression by phase), RomTag,
   ROM header/footer, or **unclassified code/table**. Only this last class could reveal
   copied code. The "code" columns of the tables count only this class.
6. **"Notable" threshold**: the longest code/table match between the `tiers` group and the
   reference, plus one. This gives 40 words, 19 instructions and 19 loose instructions. The groups
   `commodore` and `aros` are measured but do not set the threshold: they are not "unrelated".
7. **Self-check** (`--selftest`): 12 fragments of 32 to 128 words from the reference, whose
   ROM addresses have been shifted as after a relink, are inserted in memory into a copy
   of our ROM. The tool must find each of them over at least 80% of its length.

### Exact commands

They are run from the repository root. `<travail>` is a working directory outside the repository.

```sh
# 1. Symbol table: relink of the prod build objects (same list and same order as the Makefile)
OBJS="boot lists memory library rawdofmt tasks ports io ramlib interrupts resident libinit cia misc timer \
trackdisk strap keyboard input console keymap keymapdata gameport expansion romboot mathffp diskres potgo \
kbddev audio semaphores execmisc gfx graphics_lib draw regions layers bootscreen_data font8x8 text gels area \
intuition_lib screens menus requester request pointer prefs gadgets sysreq alert dos_lib ofs ofswrite loadseg \
bcpl process handler conhandler conwin shell diskvalidator feeder workbench"
L=""; for o in $OBJS; do L="$L build/prod/$o.o"; done          # build/ for the dev ROM
vlink -b rawbin1 -T src/exec/kick.ld -M<travail>/kick-prod.map -o <travail>/kick-prod.bin $L
cmp <travail>/kick-prod.bin <(head -c $(stat -c%s <travail>/kick-prod.bin) build/kick13-prod.rom)   # no difference

# 2. Controls
for adf in assets/test_adf/*.adf; do xdftool "$adf" unpack "<travail>/adf/<nom>"; done

# 3. Measurement (file lists of the groups: see the "Controls" table)
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom assets/kick34005.A500 \
    --temoin tiers <fichiers tiers...> --temoin commodore <fichiers Workbench...> \
    --temoin aros "<travail>/adf/aros/AROS Kickstart" \
    --map <travail>/kick-prod.map --base tiers --selftest
```

The full measurement takes about 30 s. Without capstone, only the `mots` stream is measured.

## Results (production ROM)

How to read the columns:
- "A tokens": useful size of A, excluding padding;
- "max (all)" and "max (code)": longest match, all classes or code/table only;
- "code ≥ N": number of code/table matches of at least N tokens and share of A they
  cover;
- "n-gr.": share of the distinct n-grams of A present in B, all classes combined.

### `mots` stream (16-bit words)

| comparison | A tokens | max (all) | max (code) | code ≥ 8: no. / cov. | code ≥ 16 | code ≥ 32 | 4-gr. | 8-gr. | 16-gr. |
|---|---|---|---|---|---|---|---|---|---|
| **our ROM vs reference** | 96,875 | 218 | **20** | 71 / 0.69% | 5 / 0.09% | **0** / 0.00% | 2.4% | 0.8% | 0.3% |
| tiers vs reference | 272,295 | 216 | 39 | 23 / 0.12% | 5 / 0.05% | 1 / 0.01% | 0.9% | 0.1% | 0.0% |
| our ROM vs tiers | 96,875 | 224 | 10 | 13 / 0.07% | 0 / 0.00% | 0 / 0.00% | 1.6% | 0.1% | 0.0% |
| commodore vs reference | 205,583 | 121 | 121 | 700 / 3.80% | 69 / 1.20% | 22 / 0.74% | 6.0% | 1.3% | 0.5% |
| our ROM vs commodore | 96,875 | 47 | 11 | 34 / 0.09% | 0 / 0.00% | 0 / 0.00% | 1.3% | 0.1% | 0.0% |
| aros vs reference | 579,070 | 282 | 282 | 147 / 0.27% | 5 / 0.06% | 2 / 0.05% | 1.2% | 0.2% | 0.1% |
| our ROM vs aros | 96,875 | 224 | 12 | 31 / 0.17% | 0 / 0.00% | 0 / 0.00% | 2.6% | 0.4% | 0.2% |

### `instr` stream (instructions, operands kept except addresses and displacements)

| comparison | A tokens | max (all) | max (code) | code ≥ 8: no. / cov. | code ≥ 16 | code ≥ 32 | 4-gr. | 8-gr. | 16-gr. |
|---|---|---|---|---|---|---|---|---|---|
| **our ROM vs reference** | 61,691 | 17 | **13** | 4 / 0.06% | **0** / 0.00% | 0 / 0.00% | 0.9% | 0.1% | 0.0% |
| tiers vs reference | 166,017 | 18 | 18 | 10 / 0.06% | 1 / 0.01% | 0 / 0.00% | 0.2% | 0.0% | 0.0% |
| our ROM vs tiers | 61,691 | 14 | 6 | 0 / 0.00% | 0 / 0.00% | 0 / 0.00% | 0.5% | 0.0% | 0.0% |
| commodore vs reference | 129,075 | 96 | 96 | 114 / 1.69% | 32 / 1.04% | 12 / 0.70% | 2.3% | 0.7% | 0.3% |
| our ROM vs commodore | 61,691 | 16 | 7 | 0 / 0.00% | 0 / 0.00% | 0 / 0.00% | 0.4% | 0.0% | 0.0% |
| aros vs reference | 364,095 | 28 | 28 | 4 / 0.02% | 2 / 0.01% | 0 / 0.00% | 0.2% | 0.0% | 0.0% |
| our ROM vs aros | 61,691 | 19 | 8 | 1 / 0.01% | 0 / 0.00% | 0 / 0.00% | 0.7% | 0.0% | 0.0% |

### `instr-souple` stream (registers and constants erased)

| comparison | A tokens | max (all) | max (code) | code ≥ 8: no. / cov. | code ≥ 16 | code ≥ 32 | 4-gr. | 8-gr. | 16-gr. |
|---|---|---|---|---|---|---|---|---|---|
| **our ROM vs reference** | 61,691 | 23 | **13** | 12 / 0.18% | **0** / 0.00% | 0 / 0.00% | 4.6% | 0.2% | 0.0% |
| tiers vs reference | 166,017 | 51 | 18 | 14 / 0.09% | 1 / 0.01% | 0 / 0.00% | 2.8% | 0.1% | 0.0% |
| our ROM vs tiers | 61,691 | 24 | 8 | 2 / 0.03% | 0 / 0.00% | 0 / 0.00% | 5.6% | 0.1% | 0.0% |
| commodore vs reference | 129,075 | 257 | 257 | 1,511 / 11.63% | 161 / 3.56% | 32 / 1.91% | 12.3% | 3.7% | 1.8% |
| our ROM vs commodore | 61,691 | 23 | 7 | 0 / 0.00% | 0 / 0.00% | 0 / 0.00% | 3.8% | 0.1% | 0.0% |
| aros vs reference | 364,095 | 51 | 28 | 42 / 0.10% | 2 / 0.01% | 0 / 0.00% | 3.0% | 0.0% | 0.0% |
| our ROM vs aros | 61,691 | 19 | 10 | 18 / 0.15% | 0 / 0.00% | 0 / 0.00% | 8.3% | 0.2% | 0.0% |

### Dev ROM

The dev ROM adds the test harness. It gives the same conclusions:
- `mots` stream: max code 19, no code match ≥ 32;
- `instr` stream: max code 13;
- `instr-souple` stream: max code 13;
- same list of data above the threshold, give or take address shifts.

### Self-check

12 relocated fragments of the reference out of 12 are found (seed 1). Normalisation and
matching therefore detect a relocated copy of 32 words or more.

## Interpretation

- **Our ROM behaves like unrelated code, not like Commodore code.** Across the three streams,
  its longest code match with the reference (20 words, 13 instructions) stays below that
  of the third-party programs (39 words, 18 instructions). None of its code matches reaches
  32 words or 16 instructions.
- Conversely, the Commodore code outside the ROM shares with the reference:
  - matches of up to 121 words or 96 exact instructions, i.e. 257 instructions in loose
    mode;
  - 3.8% of its code covered by matches of 8 words or more, and 11.6% in loose mode;
  - this is the signature of a same toolchain, in particular compiler runtime routines
    linked into several executables.

  Memorising the Commodore code would produce this profile: it is not ours.
- **The short overlaps (4-grams) are higher for our ROM (2.4%) than for the third parties
  (0.9%).** This is expected for an OS reimplementation: we call the same library vectors
  (LVOs), on the same structure fields and the same hardware registers. These
  ABI constants show up in 4-token windows, and the same effect appears for AROS
  (2.6% with our ROM). From 8 and 16 tokens on, this overlap falls back below 1%. It is then explained
  by the data tables below.

## Matches above the threshold: data only

The locations and symbols are those of our production ROM. They come from the vlink table
above; the source file is deduced from the object name.

| offset | address | bytes | longest (tokens) | symbol | source | nature |
|---|---|---|---|---|---|---|
| `$0B0F8` | `$FCB0F8` | 116 | 58 | `expansion_inittab+$4` | `src/exec/expansion.s` | the library's function vector table |
| `$0B9C8` | `$FCB9C8` | 80 | 40 | `mathffp_inittab+$4` | `src/exec/mathffp.s` | function vector table |
| `$0D3A2` | `$FCD3A2` | 452 | 218 | `graphics_inittab+$4` | `src/graphics/graphics_lib.s` | function vector table |
| `$1025A` | `$FD025A` | 132 | 66 | `layers_inittab+$4` | `src/graphics/layers.s` | function vector table |
| `$21902` | `$FE1902` | 328 | 164 | `intuition_inittab+$4` | `src/intuition/intuition_lib.s` | function vector table |
| `$266B6` | `$FE66B6` | 154 | 76 | `dos_rtinit+$42` | `src/dos/dos_lib.s` | pointer table (`dos` vectors) |
| `$2009A` | `$FE009A` | 388 | 194 | `topaz8_loc` | `src/graphics/text.s` | character-location table of a fixed-width font: arithmetic progression (position = 8 × rank, width 8) |

**Why these matches are mandated:**
- **Vector tables.** After normalisation, a table of pointers into the ROM is nothing more than a
  sequence of `ADDR` tokens. Their equality only reveals the **number of functions** of the library, which
  the public `.fd` files fix.
- **Font location table.** It is entirely computed from the geometry
  (8 × 8). The AROS ROM contains the same table: it is the longest "aros vs
  reference" match, 282 words. The glyph **bitmaps** (`src/graphics/font8x8.s`), which would be the
  expressive part, do not match.

In the `instr-souple` stream, two other ranges exceed the threshold. They are classified low
entropy:
- `rf_outline+$44` (`src/graphics/draw.s`, 50 bytes, 20 tokens): four identical segment-drawing
  calls, which loose mode reduces to a repeated pattern;
- `bcpl_rtdata+$8` (`src/dos/bcpl.s`, 46 bytes, 23 tokens): BCPL runtime data.

### For transparency: the longest code matches below the threshold

None reaches the unrelated baseline (39 words, 18 instructions). They are listed with their nature:

| offset | address | words | instr. | symbol | source | nature |
|---|---|---|---|---|---|---|
| `$23FC0` | `$FE3FC0` | 20 | — | `mn_chk_hi` | `src/intuition/menus.s` | two `struct Image` descriptors (menu checkmark and Amiga symbol): dimensions observable on screen, pointers masked |
| `$0B1D0` | `$FCB1D0` | 19 | 13 | `exp_cpbinding+$22` | `src/exec/expansion.s` | two minimal relays to obtaining and releasing a semaphore (`ObtainConfigBinding`/`ReleaseConfigBinding`); offsets and LVOs fixed by the ABI |
| `$0B800` | `$FCB800` | 18 | — | `romboot_romtag+$C` | `src/exec/romboot.s` | end of RomTag + public library names |
| `$0B0B0` | `$FCB0B0` | 17 | — | `gameport_end+$2` | `src/exec/expansion.s` | RomTag + public name |
| `$08D98` | `$FC8D98` | 16 | — | `trackdisk_romtag+$C` | `src/exec/trackdisk.s` | end of RomTag + public name |
| `$0C0C2` | `$FCC0C2` | 16 | — | `potgo_end+$C` | `src/exec/kbddev.s` | end of RomTag + public name |
| `$0D37E` | `$FCD37E` | 15 | — | `graphics_romtag+$C` | `src/graphics/graphics_lib.s` | end of RomTag + public name |
| `$24C48` | `$FE4C48` | 14 | — | `pf_defaults` | `src/intuition/prefs.s` | default preference values (observable through `GetPrefs`) |
| `$0889C` | `$FC889C` | 13 | — | `timer_romtag+$C` | `src/exec/timer.s` | end of RomTag + public name |
| `$10462` | `$FD0462` | 13 | 9 | `ly_WhichLayer+$6` | `src/graphics/layers.s` | point-in-rectangle test (four comparisons against the bounds of the structure) |
| `$23962` | `$FE3962` | 13 | — | `sc_palette+$8` | `src/intuition/screens.s` | default colour table (observable through `GetRGB4`) |
| `$03138` | `$FC3138` | 11 | — | `d3c_client+$16` | `src/exec/boot.s` | public, cleared memory allocation, then test of the result |
| `$2D09E` | `$FED09E` | 11 | — | `sh_run_startup+$1A` | `src/dos/shell.s` | same allocation idiom |
| `$0DADA` | `$FCDADA` | 10 | — | `gfx_WaitBlit` | `src/graphics/graphics_lib.s` | wait for blitter completion (idiom from the *Hardware Reference Manual*) |
| `$0E6F2` | `$FCE6F2` | 10 | 8 | `rf_outline+$4E` | `src/graphics/draw.s` | successive drawing calls (rectangle outline) |
| `$0E706` | `$FCE706` | 10 | 8 | `rf_outline+$62` | `src/graphics/draw.s` | same |
| `$28EC4` | `$FE8EC4` | 10 | — | `bcpl_call` | `src/dos/bcpl.s` | BCPL call linkage (convention imposed by the 1.3 BCPL code) |

The `instr-souple` stream has twelve code matches of 8 to 13 instructions, including
`exp_cpbinding` and `ly_WhichLayer` above, all below the baseline of 18. They are bounds tests, drawing loops and library call sequences
(`exec_AvailMem`, `exec_ObtainSemaphore`, `dr_line`, `dr_rect`, `gfx_ReadPixel`, `gfx_Animate`,
`exp_makedosnode`, `intuition_AllocRemember`, `rgt_hl`).

**Data mandated by the ABI and the hardware, reported separately.** They are not code:
- the ROM header: jump at reset, version 34;
- the ROM footer: size, vectors `$0018`–`$001F`;
- the RomTag structures (`$4AFC`, flags, version, type, priority);
- the public names (`exec.library`, `timer.device`...) and the version strings;
- the messages displayed on screen (Workbench, requesters), reproduced identically for
  compatibility;
- the function vector tables;
- the observable default values (palette, preferences).

The tool classifies them as `texte` (text), `RomTag`, `table d'adresses` (address table), `faible entropie` (low entropy) or `en-tête/pied ROM` (ROM header/footer).

## Limits: what the measurement proves and does not prove

- **It proves** the absence of binary reuse, even relocated or with renamed registers, of sequences
  of more than 13 instructions (or 20 words) of the **34.5** ROM in our ROM. It also places
  our coincidence level at the level of unrelated programs.
- **A single reference version.** The leaked sources cover other versions (2.x, 3.x)
  whose code differs. Reuse from those versions would only be detected here if the code concerned
  has remained identical since 1.3. To close this point, the measurement would have to be redone against
  2.04 and 3.1 ROMs with the same tool.
- **Binary measurement, not semantic.** A paraphrase leaves no binary trace beyond
  idioms: logic copied then rewritten with another instruction order, other registers
  and other addressing modes. The same holds for an assembly translation of a C source:
  intuition and graphics were largely written in C, dos in BCPL. The measurement does not rule this out.
  That is the role of the clean-room wall (`docs/CLEANROOM.md`) and of the review of the analysis specs.
- **Linear disassembly.** The `instr` streams also run through data. The `mots` stream, without
  a decoder, is there to cover possible misalignments. The "code/table" classification does not
  distinguish a small data table from a code fragment: it is deliberately
  conservative, and these cases were qualified by hand above.
- **Empirical threshold.** It depends on the `tiers` corpus (about 600 KB). A larger corpus would raise
  the baseline. The verdict does not depend on the exact threshold: the longest code match of our
  ROM stays clearly below the baseline (20 words against 39, 13 instructions against 18), and it
  is already explained by the ABI.
- **AROS control.** Our implementation consults the AROS sources (read-only). The low
  binary similarity with the AROS ROM (max code 12 words, 8 instructions) does not prove the absence
  of inspiration: AROS is C compiled by gcc, and inspiration leaves no binary trace.

## Clean-room review

This document was reviewed before publication to confirm:
- that it contains **no byte, no disassembly and no offset of the original ROM**;
- that each match is described only by its location in **our** ROM (offset, symbol,
  source file), its length and a neutral nature;
- that no instruction sequence is transcribed, neither from the original ROM nor from our matched
  ranges (which are identical to it);
- that the only information about the original ROM is its size, its sha1 fingerprint (public,
  identifying revision 34.5) and aggregate statistics.

The tool `tests/audit_rom_similarity.py` follows the same rule: it only displays statistics and
locations in the **first** ROM. It contains no byte of the reference and no machine-specific
path. The document may be read by the implementation track.
