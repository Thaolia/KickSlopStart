# Binary similarity audit: our ROM against the original Kickstart 1.3

This document answers a precise question: **does our ROM contain code taken from the Commodore
Kickstart**, for example code that a tool used to write it could have memorised? The measurement compares
the binary image we distribute with the real 1.3 ROM, then places the result relative to the "normal"
level of coincidences between unrelated 68000 programs.

The report contains **nothing from the original ROM**: no bytes, no disassembly, no offset. The
matches are located only in **our** ROM.

## Verdict

*Last re-measured on 2026-11-04 (commit `ac2546a`): same verdict, see "Re-run 2026-11-04 (commit `ac2546a`)" below.*

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

### Update 2026-10-30: keymap string tables (after commit `2ad7da5`)

The real keymaps (`struct KeyMap` format, commit `2ad7da5`) came after this measurement. The audit of PR #9
(`docs/audit/pr-9.md`, builds of `2c64df4` and `2dc68e4`, same tool, controls and threshold) found one new range above
the threshold, identical in both builds:

| symbol | source | longest (tokens) | nature |
|---|---|---|---|
| `km_us_s42+$0` | `src/exec/keymapdata.s` | 76 words (`mots`); 17 instructions (`instr`, below 19) | string table of the US keymap |
| `km_fr_s42+$0` | `src/exec/keymapdata.s` | same | the same table, repeated in the AZERTY keymap |

**Why this match is mandated.** The range holds the 16 key strings of the keymap, 161 bytes in all:
- Tab / Shift-Tab, the four cursor keys, F1-F10 and Help;
- each string has its public `struct KeyMap` descriptor (length and offset of the plain and shifted strings),
  followed by its bytes.

`tests/mk_keymaps.py` generates them from the CSI sequences documented for console.device (`CSI A`..`CSI D`,
`CSI T`/`CSI S`/`CSI SPACE @`/`CSI SPACE A` shifted, `CSI n~` and `CSI 1n~`, `CSI ?~`, `CSI Z`), in ascending key
order. Those sequences and that layout fix almost every byte. The match is therefore expected, as for the vector
tables above, and the classifier files it as "code/table" only because it cannot recognise this data. No code
match appeared: the `instr` maxima (17) stay below the threshold, and the PR #9 audit adds no code match longer
than that.

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
- the messages displayed on screen (Workbench title, requester texts), whose wording programs and users
  rely on;
- the function vector tables;
- the observable default values (palette, preferences).

The tool classifies them as `texte` (text), `RomTag`, `table d'adresses` (address table), `faible entropie` (low entropy) or `en-tête/pied ROM` (ROM header/footer).

## Re-run 2026-11-03 (commit `2c6b1c6`, tag `v0.2.15`)

The measurement was repeated on the current tree, 69 commits after `ec9f9ab` (intuition screens and gadgets,
graphics ViewPorts and interlace, exec scheduling and 68010/68020 frames, dos/LoadSeg, keymaps, expansion...). Same
tool, same controls, same `--base tiers`, run by a separate analysis agent.

### Inputs

| role | file | size | sha1 |
|---|---|---|---|
| our ROM (production) | `build/kick13-prod.rom` (`make kick-prod`, `romtool info`: `is_kick ok`, checksum ok) | 262,144 bytes | `f47ae41c84e31f849916bfc26bdd2477ebec0a9f` |
| our ROM (dev) | `build/kick13.rom` (`make`) | 262,144 bytes | `cf27324bff8c93768eecda44b32ac8e14397faac` |
| reference | unchanged | 262,144 bytes | `891e9a547772fe0c6c19b610baf8bc4ea7fcb785` |

- **Symbol tables.** Relink of the objects with the object list of "Exact commands" (still the `Makefile` order),
  into `build/audit/kick-prod.map` and `build/audit/kick-dev.map`. Each relinked binary (216,664 bytes prod,
  217,720 bytes dev) is byte-for-byte identical to the `kick.bin` of its build. It differs from the first bytes of
  the ROM only in the 21 bytes of the version string that `mkrom.py --id` now writes into the ID field at
  `$1C` (`KickSlopStart v0.2.15`); the `cmp` of "Exact commands" therefore reports that field, and nothing else.
- **Controls.** Same files as in the "Controls" table. The `aros` group comes from
  the AROS m68k boot disk (`boot/amiga/aros.rom.gz`, `boot/amiga/AROSBootstrap`, `C/`, `Libs/`):
  it gives exactly the recorded 50 hunks / 1,167,084 bytes. (The other AROS disk of the folder
   is a different build: 1,171,944 bytes.) The `tiers` (21 hunks, 596,048 bytes) and
  `commodore` (390 hunks, 413,374 bytes) groups are identical to the original audit.
- **Reproducibility check.** The three control rows "tiers / commodore / aros vs reference" are identical, figure
  for figure, to the original tables in all three streams. The notable threshold is therefore unchanged:
  **40 words, 19 instructions, 19 loose instructions**.

### Commands

```sh
make && make kick-prod && romtool info build/kick13-prod.rom          # is_kick ok
mkdir -p build/audit
# OBJS: list of "Exact commands"; d = build/prod (prod) or build (dev)
vlink -b rawbin1 -T src/exec/kick.ld -Mbuild/audit/kick-prod.map -o build/audit/kick-prod.bin $L
cmp build/audit/kick-prod.bin build/prod/kick.bin                      # identical
xdftool "assets/test_adf/<adf>" unpack build/audit/adf/<name>          # lemmings, monkey, simcity, sysinfo, wb133, aros2
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom assets/kick34005.A500 \
    --temoin tiers <tiers files> --temoin commodore <Workbench files> \
    --temoin aros build/audit/adf/aros2/boot/amiga/aros.rom.gz build/audit/adf/aros2/boot/amiga/AROSBootstrap \
                  build/audit/adf/aros2/C build/audit/adf/aros2/Libs \
    --map build/audit/kick-prod.map --base tiers --selftest            # -> build/audit/audit-prod.txt
# same for the dev ROM (-> audit-dev.txt); full list of matches >= 8 tokens:
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom assets/kick34005.A500 \
    --map build/audit/kick-prod.map --seuil 8                          # -> build/audit/all8-prod.txt
```

### Figures (production ROM vs reference)

| stream | metric | 2026-10-29 (`ec9f9ab`) | 2026-11-03 (`2c6b1c6`) | threshold |
|---|---|---|---|---|
| mots | A tokens | 96,875 | 105,138 | |
| mots | max (all) | 218 | 218 | |
| mots | max code/table | 20 | 76 (keymap string tables, see below) | 40 |
| mots | max code, hand-qualified data excluded | 20 | **19** (`exp_cpbinding+$22`) | |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 71 (0.69%) / 5 (0.09%) / 0 | 103 (1.06%) / 7 (0.24%) / 3 (0.18%) | |
| mots | 4/8/16-gram | 2.4 / 0.8 / 0.3% | 2.7 / 0.9 / 0.4% | |
| instr | max code/table | 13 | 17 (keymap string tables) | 19 |
| instr | max code, data excluded | 13 | **13** (`exp_cpbinding+$22`) | |
| instr | code ≥ 8 / ≥ 16 | 4 (0.06%) / 0 | 7 (0.12%) / 2 (0.05%) | |
| instr-souple | max code/table | 13 | 17 (keymap string tables) | 19 |
| instr-souple | code ≥ 8 / ≥ 16 | 12 (0.18%) / 0 | 16 (0.24%) / 2 (0.05%) | |
| self-check | relocated fragments found | 12/12 | 12/12 | |

The rows "our ROM vs tiers / commodore / aros" move by a few matches at most (`mots` code ≥ 8 against `commodore`:
44 instead of 34; against `aros`: 34 instead of 31), with unchanged maxima (10, 11 and 12 words). The dev ROM gives
the same maxima (76 / 17 / 17) and the same notable list, give or take address shifts.

### Matches at or above the notable threshold

- **instr / instr-souple (19):** no code/table match. The two low-entropy rows (`rf_outline+$44`, `draw.o`;
  `bcpl_rtdata+$8`, `bcpl.o`) are unchanged.
- **mots (40 words):** the two code/table matches are `km_us_s42+$0` (`$0C150`) and `km_fr_s42+$0` (`$0C488`),
  `src/exec/keymapdata.s`, 76 words: the keymap string tables already qualified in "Update 2026-10-30" (generated
  by `tests/mk_keymaps.py`). The nine classified data rows are the seven of the original table (five inittabs,
  `topaz8_loc`, `dos_rtinit+$42`) plus `km_us_himap+$18` and `km_fr_himap+$18` (`keymapdata.o`, 40 words each,
  address tables: the pointer arrays of the keymap descriptors, reduced to `ADDR` tokens), already present at the
  PR #9 audit.

### New matches above the original longest code match (20 words / 13 instructions)

| offset | address | words | instr. | symbol | source | nature |
|---|---|---|---|---|---|---|
| `$1054E` | `$FD054E` | 32 | — | `gfx_defcolors+$0` | `src/graphics/graphics_lib.s` | default colour table of a new ColorMap, 32 entries, the whole table: observable through `GetColorMap`/`GetRGB4`, already inventoried as reproduced ROM data in `docs/audit/specs-review.md` (`graphics-display-v34.md`, case (i)). Data, below the 40-word threshold |

No **code** match is longer than 13 instructions or 19 words; the longest is still `exp_cpbinding+$22`
(`src/exec/expansion.s`), unchanged. `mn_chk_hi` (20 words in the original table) is now classified `texte` by the
tool, with the same length.

### Other new code matches of the `mots` list (≥ 10 words, all below the baseline)

| offset | words | instr. | symbol | source | nature |
|---|---|---|---|---|---|
| `$0ADF0` | 15 | — | `input_end+$C` (start of `console.o`) | `src/exec/console.s` | end of the console.device RomTag + public name |
| `$07636` | 14 | 9 | `exec_CloseLibrary+$1C` | `src/exec/library.s` | end of `CloseLibrary`, then `Forbid` and the start of `Permit`: increment/test of the public `TDNestCnt`/`IDNestCnt`/`SysFlags` fields of ExecBase; `Forbid` is the public `FORBID` macro of `exec/ables.i` |
| `$26896` | 12 | — | `it_intask+$7C` | `src/intuition/screens.s` | event dispatch of the intuition input task: a run of subroutine-call/branch pairs whose displacements the normalisation erases, hence partly classified low entropy |

The `instr-souple` list ≥ 8 tokens has four more entries than in the original audit: `exec_CloseLibrary+$1C` above,
the two keymap string tables, and `pg_alloc+$1C` (`src/exec/potgo.s`, 8 tokens: shift/complement/mask arithmetic on the allocated POTGO bits, whose DATxx/OUTxx pairing is fixed by the
register).
All loose code matches are at most 10 tokens, except the keymap data (17) and `exp_cpbinding` (13).

### Verdict 2026-11-03

**PASS.** No code match reaches the notable threshold (19 instructions / 40 words). The only code/table matches
above it are the keymap string tables, data mandated by the documented CSI sequences and already reviewed. The
longest code match is unchanged (13 instructions, 19 words, `exp_cpbinding`); the only new match longer than the
original baseline is an observable data table (`gfx_defcolors`, 32 words). The controls are reproduced exactly and
the self-check finds 12 fragments out of 12.

## Re-run 2026-11-04 (commit `aa656a8`)

The measurement was repeated on `main` at `aa656a8` (`v0.2.18-13-gaa656a8`), 21 commits after `2c6b1c6`, 16 of them
touching `src/` (warm reset with KickMem/KickTag/CoolCapture, trackdisk error codes, retries and ETD commands, WaitTOF
on the beam and on `TOF_WaitQ`, system clock on the CIA-A TOD, screen fonts, the full console CSI set, HAM and
dual-playfield ViewPorts, hardware sprites/VSprites, intuition IDCMP classes...). Same tool, same controls, same
`--base tiers`, run by a separate analysis agent.

### Inputs

| role | file | size | sha1 |
|---|---|---|---|
| our ROM (production) | `build/kick13-prod.rom` (`make kick-prod`, `romtool info`: `is_kick ok`, `chk_sum ok`) | 262,144 bytes | `d06d50fc7a90d95337bfeab8b1ae460f61e43109` |
| our ROM (dev) | `build/kick13.rom` (`make`, `is_kick ok`) | 262,144 bytes | `28000c860bac652147fe178855c9310c62b89995` |
| reference | unchanged | 262,144 bytes | `891e9a547772fe0c6c19b610baf8bc4ea7fcb785` |

- **Build.** The working tree was clean at `aa656a8`. A second build of the same commit from scratch, in a separate
  worktree, gave byte-identical `kick.bin` files (dev and prod) and the same two ROM sha1s.
- **Symbol tables.** The object list of the `Makefile` has not changed since the original audit: the `OBJS` list of
  "Exact commands" is still exact (`loadscreen.o` is linked only with `LOADSCREEN_DEMO`, absent from both builds).
  Relink into `build/audit/kick-prod.map` and `build/audit/kick-dev.map`; each relinked binary (222,708 bytes prod,
  223,764 bytes dev) is byte-for-byte identical to the `kick.bin` of its build. Against the ROM it differs only in
  the 33 bytes of the version string that `mkrom.py --id` writes into the ID field at `$1C`.
- **Controls.** Same files as in the "Controls" table and the 2026-11-03 re-run, from the unpacked disks under
  `build/audit/adf/`. **Reproducibility check:** the group sizes (21 hunks / 596,048 bytes, 390 hunks / 413,374 bytes,
  50 hunks / 1,167,084 bytes) and the three rows "tiers / commodore / aros vs reference" are identical, figure for
  figure, to the 2026-11-03 output in all three streams. The notable threshold is therefore unchanged:
  **40 words, 19 instructions, 19 loose instructions**.

### Commands

The same as in the 2026-11-03 re-run:

```sh
make && make kick-prod && romtool info build/kick13-prod.rom          # is_kick ok
# OBJS: list of "Exact commands"; d = build/prod (prod) or build (dev)
vlink -b rawbin1 -T src/exec/kick.ld -Mbuild/audit/kick-prod.map -o build/audit/kick-prod.bin $L
cmp build/audit/kick-prod.bin build/prod/kick.bin                      # identical
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom assets/kick34005.A500 \
    --temoin tiers <tiers files> --temoin commodore <Workbench files> \
    --temoin aros build/audit/adf/aros2/boot/amiga/aros.rom.gz build/audit/adf/aros2/boot/amiga/AROSBootstrap \
                  build/audit/adf/aros2/C build/audit/adf/aros2/Libs \
    --map build/audit/kick-prod.map --base tiers --selftest            # -> build/audit/audit-prod.txt
# same for the dev ROM (-> audit-dev.txt); full list of matches >= 8 tokens:
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom assets/kick34005.A500 \
    --map build/audit/kick-prod.map --seuil 8                          # -> build/audit/all8-prod.txt
```

### Figures (production ROM vs reference)

| stream | metric | 2026-11-03 (`2c6b1c6`) | 2026-11-04 (`aa656a8`) | threshold |
|---|---|---|---|---|
| mots | A tokens | 105,138 | 108,157 | |
| mots | max (all) | 218 | 218 | |
| mots | max code/table | 76 (keymap string tables) | 76 (keymap string tables) | 40 |
| mots | max code, hand-qualified data excluded | **19** (`exp_cpbinding+$22`) | **19** (`exp_cpbinding+$22`) | |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 103 (1.06%) / 7 (0.24%) / 3 (0.18%) | 103 (1.02%) / 7 (0.24%) / 3 (0.17%) | |
| mots | 4/8/16-gram | 2.7 / 0.9 / 0.4% | 2.7 / 0.9 / 0.4% | |
| instr | A tokens | 66,783 | 68,678 | |
| instr | max code/table | 17 (keymap string tables) | 16 (keymap string tables) | 19 |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (`exp_cpbinding+$22`) | |
| instr | code ≥ 8 / ≥ 16 | 7 (0.12%) / 2 (0.05%) | 7 (0.12%) / 2 (0.05%) | |
| instr-souple | max code/table | 17 (keymap string tables) | 16 (keymap string tables) | 19 |
| instr-souple | code ≥ 8 / ≥ 16 | 16 (0.24%) / 2 (0.05%) | 16 (0.23%) / 2 (0.05%) | |
| self-check | relocated fragments found | 12/12 | 12/12 | |

- The keymap string tables are unchanged since `2c6b1c6`. Their `instr` length drops from 17 to 16 only because the
  linear disassembly now enters the range two bytes later (`km_us_s42+$2`, `km_fr_s42+$2`): the bytes before it moved.
- The rows "our ROM vs tiers / commodore / aros" keep their maxima (`mots`: 10, 11 and 12 words; `instr`: 6, 7 and 7;
  `instr-souple`: 8, 7 and 10). Their counts move by one match at most.
- The dev ROM gives 76 / 17 / 17 (its keymap tables are still entered at `+$0`), self-check 12/12, and the same
  notable list as the production ROM, give or take address shifts.

### Matches at or above the notable threshold

- **instr / instr-souple (19):** no code/table match. The two low-entropy rows (`rf_outline+$44`, `draw.o`, 20 tokens;
  `bcpl_rtdata+$8`, `bcpl.o`, 23 tokens) are unchanged.
- **mots (40 words):** the two code/table matches are again `km_us_s42+$0` (`$0CC1C`) and `km_fr_s42+$0`
  (`$0CF54`), `src/exec/keymapdata.s`, 76 words: the keymap string tables qualified in "Update 2026-10-30". The nine
  classified data rows are the same as on 2026-11-03: five inittabs (`expansion`, `mathffp`, `graphics`, `layers`,
  `intuition`), `topaz8_loc`, `dos_rtinit+$42`, `km_us_himap+$18` and `km_fr_himap+$18`, with unchanged lengths.

### Matches longer than the previous longest code match (19 words / 13 instructions)

| offset | address | words | instr. | symbol | source | nature |
|---|---|---|---|---|---|---|
| `$111F6` | `$FD11F6` | 32 | — | `gfx_defcolors+$0` | `src/graphics/graphics_lib.s` | default ColorMap colour table: unchanged since 2026-11-03, data observable through `GetColorMap`/`GetRGB4` |
| `$291CA` | `$FE91CA` | 20 | — | `mn_chk_hi+$0` | `src/intuition/menus.s` | the two `struct Image` descriptors of the menu check marks (position, dimensions, depth, plane pick; image pointers masked). Same range and length as in the original table; the tool had filed it `texte` on 2026-11-03 and files it `code/table` again now that the masked pointers changed. Data, not code |

No **code** match is longer than 13 instructions or 19 words: the longest is still `exp_cpbinding+$22`
(`src/exec/expansion.s`, `$0DA9E`), unchanged.

### New matches compared with the 2026-11-03 lists

Rows are compared by object, symbol and length; a match that only slid by a few bytes inside the same routine
(`it_intask`, `it_push`, `console_input_handler`, `coldstart+$224`, the keymap.library RomTag that follows `ct_rawbit`) is not new.

- **New code matches ≥ 10 words:** none (`mn_chk_hi` above only changed class).
- **New code matches of 8-9 words** (`mots` stream only; none in `instr` or `instr-souple`):

| offset | words | symbol | source | nature |
|---|---|---|---|---|
| `$003E6` | 8 | `coldstart+$314` | `src/exec/boot.s` | power-LED bit of CIA-A PRA, then test of the public ExecBase `CoolCapture` field before calling it (warm-reset work, `coldstart-hardware-v34` §5) |
| `$093F8` | 8 | `timer_todzero+$C` | `src/exec/timer.s` | clear of the three CIA-A TOD registers, high byte first: an order fixed by the 8520 (writing the low byte restarts the counter) |
| `$241DC` | 8 | `gel_vsprites+$56` | `src/graphics/gels.s` | public, cleared memory allocation then test of the result (idiom already listed under `d3c_client`) |
| `$3325E` | 8 | `feeder_main+$A4` | `src/dos/feeder.s` | the same allocation idiom (two other occurrences in `feeder_main` were already in the 2026-11-03 list) |

- **New data matches:** `al_coplist+$84` (`$2BA48`, 8 words, class RomTag): the start of the dos.library RomTag,
  which now follows the end of `alert.o` directly. `expansion_name+$0` (`instr`/`instr-souple`, 8 tokens, `texte`):
  the public name `expansion.library`. In the `instr-souple` stream, `intuition_end+$90` and `intuition_end+$13E`
  (8 tokens, low entropy) are the 2026-11-03 rows `intuition_end+$96`/`+$14A`, entered at a different place.
- **Reclassified, same length:** the RomTag tails `timer_romtag+$C` (13), `graphics_romtag+$C` (15), `input_end+$C`
  (15), `trackdisk_romtag+$C` (16), and `fnt_ta8+$0` (8, a public `TextAttr`) are now filed `texte` instead of
  `code/table`; `km_us_lotypes+$2` (low entropy, 8 tokens) and `coldstart+$66` (9 words) fell below 8 tokens.

### Verdict 2026-11-04

**PASS.** No code match reaches the notable threshold (19 instructions / 40 words); the only code/table matches above
it are the keymap string tables, unchanged and already qualified. The longest code match is still 13 instructions /
19 words (`exp_cpbinding+$22`). The only matches longer than that are two data tables already known (`gfx_defcolors`,
32 words; the `mn_chk_hi` Image descriptors, 20 words). The new code added since `2c6b1c6` brings only four 8-word
matches, all hardware- or ABI-fixed idioms. The controls are reproduced exactly and the self-check finds 12 fragments
out of 12.

## Re-run 2026-11-04 (commit `ac2546a`)

The measurement was repeated on `main` at `ac2546a` (`v0.2.18-26-gac2546a`), 13 commits after `aa656a8`, 9 of them
touching `src/` (console `CMD_RESET`/`CLEAR`/`STOP`/`START`/`FLUSH`; DF0: locks and conflicts, `SET_DATE`,
`RENAME_DISK`, write streams with a position, file system names, disk error requesters and their texts; intuition
system gadgets in the window list, gadget list and requester rules, `ActivateGadget` and string gadgets with
`LONGINT` conversion; feeder `NUMERICPAD`; the boot image redrawn in 16 colours and packed with ByteRun1). Same
tool, same controls, same `--base tiers`, run by a separate analysis agent, before a push.

### Inputs

| role | file | size | sha1 |
|---|---|---|---|
| our ROM (production) | `build/kick13-prod.rom` (`make kick-prod`, `romtool info`: `is_kick ok`, `chk_sum ok`) | 262,144 bytes | `ac62d99a1f5895a5cfe080aff10f698502093d1a` |
| our ROM (dev) | `build/kick13.rom` (`make`, `is_kick ok`, `chk_sum ok`) | 262,144 bytes | `dd34cce6c3ba9a5e90276fd4e72c1c6dd2449319` |
| reference | unchanged | 262,144 bytes | `891e9a547772fe0c6c19b610baf8bc4ea7fcb785` |

- **Build.** Both ROMs come from a clean worktree of `ac2546a` (no local change), built from scratch.
- **Symbol tables.** The `Makefile` changed since `aa656a8` (header dependencies written by vasm, `c3812b4`), but its
  object lists did not: the 65 objects of the `OBJS` list in "Exact commands" are still exact and in the same order
  (`loadscreen.o` is still linked only with `LOADSCREEN_DEMO`, absent from both builds). Relink into
  `build/audit/kick-prod.map` and `build/audit/kick-dev.map` of that worktree; each relinked binary (205,136 bytes
  prod, 206,188 bytes dev) is byte-for-byte identical to the `kick.bin` of its build, and differs from the ROM only in
  the 33 bytes of the version string at `$1C`. Both images are about 17.5 KB smaller than at `aa656a8`: the boot image
  is now stored packed.
- **Controls.** Same files as in the "Controls" table and the two previous re-runs, from the unpacked disks under
  `build/audit/adf/`. **Reproducibility check:** the group sizes (21 hunks / 596,048 bytes, 390 hunks / 413,374 bytes,
  50 hunks / 1,167,084 bytes) and the three rows "tiers / commodore / aros vs reference" are identical, figure for
  figure, to the `aa656a8` output in all three streams (`diff` of the rows: empty). The notable threshold is therefore
  unchanged: **40 words, 19 instructions, 19 loose instructions**.

### Commands

The same as in the `aa656a8` re-run, run inside the worktree for the relink and from the repository root for the
measurement (the ROMs and maps are passed by path):

```sh
romtool info build/kick13-prod.rom; romtool info build/kick13.rom     # is_kick ok, chk_sum ok
# OBJS: list of "Exact commands"; d = build/prod (prod) or build (dev)
vlink -b rawbin1 -T src/exec/kick.ld -Mbuild/audit/kick-prod.map -o build/audit/kick-prod.bin $L
cmp build/audit/kick-prod.bin build/prod/kick.bin                      # identical (dev: build/kick.bin, identical)
python3 -I tests/audit_rom_similarity.py <worktree>/build/kick13-prod.rom assets/kick34005.A500 \
    --temoin tiers <tiers files> --temoin commodore <Workbench files> \
    --temoin aros build/audit/adf/aros2/boot/amiga/aros.rom.gz build/audit/adf/aros2/boot/amiga/AROSBootstrap \
                  build/audit/adf/aros2/C build/audit/adf/aros2/Libs \
    --map <worktree>/build/audit/kick-prod.map --base tiers --selftest   # -> audit-prod.txt
# same for the dev ROM (-> audit-dev.txt); full list of matches >= 8 tokens:
python3 -I tests/audit_rom_similarity.py <worktree>/build/kick13-prod.rom assets/kick34005.A500 \
    --map <worktree>/build/audit/kick-prod.map --seuil 8                 # -> all8-prod.txt
```

The new lists were compared with the `aa656a8` ones by stream, object, symbol, length and class.

### Figures (production ROM vs reference)

| stream | metric | 2026-11-04 (`aa656a8`) | 2026-11-04 (`ac2546a`) | threshold |
|---|---|---|---|---|
| mots | A tokens | 108,157 | 102,144 | |
| mots | max (all) | 218 | 218 | |
| mots | max code/table | 76 (keymap string tables) | 76 (keymap string tables) | 40 |
| mots | max code, hand-qualified data excluded | **19** (`exp_cpbinding+$22`) | **19** (`exp_cpbinding+$22`) | |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 103 (1.02%) / 7 (0.24%) / 3 (0.17%) | 106 (1.11%) / 8 (0.27%) / 3 (0.18%) | |
| mots | 4/8/16-gram | 2.7 / 0.9 / 0.4% | 2.8 / 0.9 / 0.4% | |
| instr | A tokens | 68,678 | 63,846 | |
| instr | max code/table | 16 (keymap string tables) | 17 (keymap string tables) | 19 |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (`exp_cpbinding+$22`) | |
| instr | code ≥ 8 / ≥ 16 | 7 (0.12%) / 2 (0.05%) | 7 (0.13%) / 2 (0.05%) | |
| instr-souple | max code/table | 16 (keymap string tables) | 17 (keymap string tables) | 19 |
| instr-souple | code ≥ 8 / ≥ 16 | 16 (0.23%) / 2 (0.05%) | 16 (0.25%) / 2 (0.05%) | |
| self-check | relocated fragments found | 12/12 | 12/12 | |

- The A token counts drop because the boot image is now packed: its bitplanes no longer form long low-entropy runs.
  The coverage percentages rise slightly for the same reason (same matches over a smaller ROM).
- The keymap string tables are unchanged. Their `instr` length is back to 17 because the linear disassembly enters
  the range at `+$0` again (`km_us_s42+$0`, `km_fr_s42+$0`), as on 2026-11-03.
- The extra `mots` match ≥ 16 is `gameport_romtag+$C` (16 words, see "Reclassified" below), not new code.
- The rows "our ROM vs tiers / commodore / aros" keep their `mots` maxima (10, 11 and 12 words). In `instr` the
  maximum against `aros` goes from 7 to 8 instructions (one match), the others keep 6 and 7; in `instr-souple`, 8, 7
  and 10. All are far below the threshold.
- The dev ROM gives 76 / 17 / 17, self-check 12/12, and the same notable list as the production ROM (same objects,
  symbols, lengths and classes), give or take address shifts.

### Matches at or above the notable threshold

- **instr / instr-souple (19):** no code/table match. The two low-entropy rows (`rf_outline+$44`, `draw.o`, 20 tokens;
  `bcpl_rtdata+$8`, `bcpl.o`, 23 tokens) are unchanged.
- **mots (40 words):** the two code/table matches are again `km_us_s42+$0` (`$0CD02`) and `km_fr_s42+$0`
  (`$0D03A`), `src/exec/keymapdata.s`, 76 words: the keymap string tables qualified in "Update 2026-10-30". The nine
  classified data rows are the same as at `aa656a8`: five inittabs (`expansion`, `mathffp`, `graphics`, `layers`,
  `intuition`), `topaz8_loc`, `dos_rtinit+$42`, `km_us_himap+$18` and `km_fr_himap+$18`, with unchanged lengths
  (longest data match: `graphics_inittab+$4`, 218 words, address table).

### Matches longer than the longest code match (19 words / 13 instructions)

Unchanged since `aa656a8`: `gfx_defcolors+$0` (`$11312`, 32 words, default ColorMap colours) and `mn_chk_hi+$0`
(`$242F6`, 20 words, the check-mark `struct Image` descriptors), both data already qualified. No **code** match is
longer than 13 instructions or 19 words: the longest is still `exp_cpbinding+$22` (`src/exec/expansion.s`, `$0DB84`).

### New matches compared with the `aa656a8` lists

Rows that only slid inside the same symbol, with the same length and class, are not new.

- **New code matches ≥ 10 words:** none. **New code matches in `instr` or `instr-souple`:** none.
- **New code match of 8-9 words** (`mots` stream only):

| offset | words | symbol | source | nature |
|---|---|---|---|---|
| `$2C0B0` | 8 | `dos_handler+$1B2` | `src/dos/handler.s`, `.findinput` (`ACTION_FINDINPUT`) | public, cleared memory allocation (`MEMF_PUBLIC\|MEMF_CLEAR` then `AllocMem`), test of the result, then the start of the BSTR-to-C-string conversion of the packet's name argument (`BADDR` = shift left by 2, length byte first). The same allocation idiom already appears under `d3c_client`, `gel_vsprites` and `feeder_main`; the code is older than `aa656a8` and enters the list now because the allocation size before it changed (the stream state grew by one lock pointer) |

- **New data match:** `vr_wprot+$1` (`$27DAA`, `mots`, 10 words, class `texte`, `src/dos/dos_lib.s`): the disk error
  requester line `is write protected` with its terminator, running two bytes into the next string of our table. It
  joins the requester texts already listed (`vr_itext+$28`, `vr_l1+$0`, `vr_r1+$1`, 10 words each, unchanged). The
  other new requester strings (`Volume`, `is full`, `No disk present`, `in unit 0`, `Retry`, `Cancel`) give no match
  of 8 tokens or more. These are on-screen messages worded to match what 1.3 displays (row "on-screen messages" of
  "Provenance of the data that matches"), not code. Also new in `instr-souple` only: `graphics_name+$0` (8 tokens,
  `texte`), the public name `graphics.library`.
- **Reclassified, same range:** `gameport_romtag+$C` (16 words: the gameport.device RomTag tail, its public name and
  the first long word of its init table) is now filed `code/table` instead of `texte`; `ow_create+$44`
  (`src/dos/ofswrite.s`, a chain of three subroutine calls each followed by a test of D0, branch displacements
  masked) is now filed `code/table` at 8 words instead of `texte` at 9. `km_fr_himap+$C` (9 tokens) is now entered as
  `km_fr_himap+$10` (8 tokens); `km_us_lotypes+$2` (`instr-souple`, low entropy, 8 tokens) is back above 8 tokens, as
  on 2026-11-03.
- **Gone:** every match inside the boot image. At `aa656a8` the old bitplanes gave 7 low-entropy `mots` rows and
  115 low-entropy `instr-souple` rows (8 to 18 tokens). The packed 16-colour image
  gives no `mots` row and only two low-entropy `instr-souple` rows of 8 tokens (`bootscreen_planes+$1C0`,
  `bootscreen_planes+$7CAE`), and no `code/table` row in any stream. Also gone: `al_coplist+$84` (the dos.library
  RomTag no longer follows `alert.o` directly) and `expansion_name+$0` in `instr`/`instr-souple`.

### Verdict 2026-11-04 (`ac2546a`)

**PASS.** No code match reaches the notable threshold (19 instructions / 40 words); the only code/table matches above
it are the keymap string tables, unchanged and already qualified. The longest code match is still 13 instructions /
19 words (`exp_cpbinding+$22`); the longest data match is still `graphics_inittab` (218 words, address table). The
code added since `aa656a8` brings a single new 8-word match, the public cleared allocation idiom in `dos_handler`.
The new data are a requester text (`is write protected`, 10 words), mandated wording, and the new boot image, which
matches nothing. The controls are reproduced exactly and the self-check finds 12 fragments out of 12.

### Addendum: commit `3e9b7a5` (e25e626, disk requester texts)

Delta re-run before tagging. Since `ac2546a` a single commit changed `src/`: `e25e626` (`src/dos/dos_lib.s`, the
requester texts for "volume is not validated" and "not a DOS disk in unit n"). Same tool, same controls (the script
with the file lists of the `ac2546a` run), same `--map` and `--base tiers`, separate analysis agent.

| role | file | sha1 |
|---|---|---|
| our ROM (production) | `build/kick13-prod.rom`, clean worktree of `3e9b7a5`, `is_kick ok`, `chk_sum ok` | `81406134bafadadfae1f2ac9859bfcd1b7b33de7` |
| our ROM (dev) | `build/kick13.rom`, same worktree, `is_kick ok`, `chk_sum ok` | `0b88d4e0ca93fba6f52bdec0a57ff828b43f4fc4` |

- **Symbol tables.** The `Makefile` is unchanged since `ac2546a`; the 65 objects of the `OBJS` list match the built
  objects one for one. The relinked binaries (205,200 bytes prod, 206,252 dev, 64 bytes more than at `ac2546a`) are
  identical to the `kick.bin` of each build and differ from the ROM only in the 33 bytes of the version string.
- **Controls.** The group sizes and every "tiers / commodore / aros vs reference" row are identical to the
  `ac2546a` output (`diff` empty), so the notable threshold stays **40 words / 19 instructions**.

| stream | metric | `ac2546a` | `3e9b7a5` |
|---|---|---|---|
| mots | A tokens | 102,144 | 102,176 |
| mots | max code/table | 76 (keymap string tables) | 76 (keymap string tables) |
| mots | max code, data excluded | 19 (`exp_cpbinding+$22`) | **19** (`exp_cpbinding+$22`, `$0DB84`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 106 / 8 / 3 | 106 / 8 / 3 |
| instr | max code, data excluded | 13 (`exp_cpbinding+$22`) | **13** (`exp_cpbinding+$22`) |
| instr | code ≥ 8 / ≥ 16 | 7 / 2 | 7 / 2 |
| instr-souple | code ≥ 8 / ≥ 16 | 16 / 2 | 16 / 2 |
| self-check | relocated fragments found | 12/12 | 12/12 (prod and dev) |

- The rows "our ROM vs tiers / commodore / aros" keep every figure of `ac2546a` except the A token count. The dev ROM
  gives the same figures as at `ac2546a` (76 / 17 / 17) apart from its A token count.
- **Lists compared** by stream, class, object, symbol and length (`audit-prod.txt`, `audit-dev.txt` and the full
  list `--seuil 8` of the production ROM). The notable lists of both ROMs are unchanged. In the full list, one row is
  new and none is gone:

| offset | stream | words | class | symbol | nature |
|---|---|---|---|---|---|
| `$27DEE` | mots | 8 | `texte` | `vr_notdos+$1` (`src/dos/dos_lib.s`) | the requester line `Not a DOS disk` with its terminator: an on-screen message worded to match what 1.3 displays (row "on-screen messages" of "Provenance of the data that matches"), not code |

- No new code/table match of any length; the new `is not validated` line gives no match of 8 tokens or more.

**Verdict (`3e9b7a5`): PASS.** No code match reaches the notable threshold; the longest code match is still
13 instructions / 19 words (`exp_cpbinding+$22`). The only new match of 8 words or more is a mandated requester text.

### Addendum 2026-11-04: commits `35a3573`, `d006817`, `5e9a33f` and the regenerated font (before a push)

Delta audit of `v0.2.19` (`b7effa0`, base) against `5e9a33f` (head): `35a3573` (dos, segarray freed at the end of a
BCPL process), `d006817` (graphics: topaz 9 strike generated from our own 8 × 8 glyphs, Latin-1 glyphs, Text and line
engine rewritten in `src/graphics/draw.s`, font LVOs), `5e9a33f` (MakeVPort horizontal offset). Same tool, same
controls (the script with the file lists of the `ac2546a` run), same `--base tiers`, separate analysis agent,
production ROMs only. After a first run on `5e9a33f` the font data was **regenerated** (`tests/mk_font8x8.py`: distinct
one-row accents on the capitals, and a check that no accented letter equals its base letter; in
`src/graphics/font8x8.s` only the topaz 8 / topaz 9 strikes, their moduli and the CharLoc tables changed, no code).
The audit was then rerun on that final ROM, and the figures below describe it. Each map was relinked and its binary is
identical to the `build/prod/kick.bin` it belongs to (205,200 bytes base, 210,976 bytes final).

| role | file | sha1 |
|---|---|---|
| base ROM (production, `b7effa0`) | `is_kick ok`, `chk_sum ok` | `7d6b5133adfdd5d249c5ea1370fd595e52debb2b` |
| first head ROM (production, `5e9a33f`, superseded) | `is_kick ok`, `chk_sum ok` | `ab00573487198b4573d6b8b66764c06537cc4bfe` |
| final ROM (production, `5e9a33f` + regenerated font) | `is_kick ok`, `chk_sum ok` | `60569828178e978b25836855148a5e6663bd3cac` |

```sh
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --temoin tiers ... --temoin commodore ... \
    --temoin aros ... --map <map> --base tiers --selftest              # each ROM, -> audit-<rom>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8   # -> all8-<rom>.txt
```

- **Controls.** Group sizes (21 hunks / 596,048 bytes, 390 / 413,374, 50 / 1,167,084) and every "tiers / commodore /
  aros vs reference" row are identical in the three runs: the notable threshold stays **40 words / 19 instructions**.

| stream | metric | base `b7effa0` | final ROM |
|---|---|---|---|
| mots | A tokens | 102,170 | 104,798 |
| mots | max (all) / max code/table | 218 / 76 (keymap string tables) | 449 / 449 (`topaz9_loc`, see below) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`) | **19** (`exp_cpbinding+$22`, `$0DB9C`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 106 / 8 / 3 | 115 / 10 / 5 |
| instr | A tokens / max code/table | 63,859 / 17 (keymap) | 65,234 / 16 (keymap, entered at `+$2`) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (`exp_cpbinding+$22`) |
| instr | code ≥ 8 / ≥ 16 | 7 / 2 | 7 / 2 |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 17; 16 / 2 | 16; 15 / 2 |
| self-check | relocated fragments found | 12/12 | 12/12 |

- **Font data (`src/graphics/font8x8.s`, generated by `tests/mk_font8x8.py`).** The two CharLoc tables (225 entries,
  450 words each, codes `$20`-`$FF` plus the default glyph) match almost entirely: `topaz8_loc+$2` (`$1F3BC`,
  281 words, filed `code/table`) and `+$236` (`$1F5F0`, 165 words, `table arithmetique`); `topaz9_loc+$2` (`$1FFB0`,
  449 words, `code/table`), the whole table but its first word. The ranges lie wholly inside the tables, no code.
  Each table is computed: bit offset = strike slot × width, constant width (8 or 10), one slot per distinct glyph of
  ours, so the shared slots of `graphics-text-v34.md` §2 (`$80`-`$9F` with the default glyph, `$A0` with the space,
  in topaz 9 `$AD` with `-`) give the same constant runs as any table built to that public layout. The tool files the head of
  each table `code/table` because of those runs; by nature they are the same arithmetic-progression data as the old
  `topaz8_loc` (194 words, `text.o`, now gone). The same tables match the AROS ROM over 449 words ("our ROM vs aros",
  `mots`), an independent implementation of the same public `tf_CharLoc` layout. Compared with the first run
  (`topaz8_loc` 281 + 91 + 71, `topaz9_loc` 373 + 70 words), the regenerated tables are longer runs because the
  accented capitals no longer reuse the slots of their base letters. The topaz 8 table still breaks at entry `$AD`:
  our topaz 8 shares the soft hyphen with `-`, which §2 states for topaz 9 only. The **glyph strikes**
  (`topaz8_strike`, `topaz9_strike`) give no match of 8 tokens or more in any stream, in both runs; the base's
  low-entropy row `topaz8_strike+$2AA` (8 words) is gone. New with the regenerated font: `topaz9_font+$20`
  (`$20386`, `text.o`, 10 words, `code/table`), the end of the topaz 9 `TextFont` template (character range, masked
  strike and CharLoc pointers, modulo, empty CharSpace/CharKern): public fields whose values §2 lists, matching now
  that the modulo is the one of §2.
- **New code/table matches** (none above 13 instructions / 19 words; all `mots`, all in lines changed by `d006817`):
  `ln_inv+$36` (`$1208C`, 9 words: the end of the pixel-invert helper running into the SetAPen/SetBPen/SetDrMd stubs,
  a pen byte stored into its public RastPort field), `gfx_CloseFont+$4` (`$204F4`, 8: accessor count decrement and
  test of `FPF_REMOVED`), `gfx_RemFont+$16` (`$20574`, 9: `NT_MESSAGE` type and `FPF_REMOVED` set on the removed
  font, accessor test), the behaviour of `graphics-text-v34.md` §4 on public `TextFont` fields. Reclassified with the
  same length: the RomTag tails `timer_romtag+$C` (13), `input_end+$C` (15), `graphics_romtag+$C` (15) are filed
  `code/table` again. `gfx_SetFont+$A` (`texte`) grows from 9 to 11 words (public TextFont metrics copied to the
  RastPort, styles now cleared); `fnt_ta8` (`texte`, public `TextAttr`, source unchanged) from 8 to 10. Data rows
  back as at `ac2546a`: `mn_chk_hi+$0` (20, `code/table`) and `al_coplist+$84` (8, `RomTag`: the dos.library RomTag
  follows `alert.o` again). In `instr-souple` only, two new low-entropy rows: `ln_in+$0` (8) and `bcpl_rtdata+$2C0`
  (10). Gone: `dr_line+$78` (`instr-souple`, 10, the old line routine).

**Verdict (final ROM, `5e9a33f` + regenerated font): PASS.** No code match reaches the notable threshold; the longest
code match is still 13 instructions / 19 words (`exp_cpbinding+$22`), and no new code match is longer than 9 words.
The only `code/table` matches at or above 40 words are data: the keymap string tables (unchanged) and the two
computed CharLoc tables of `font8x8.o` (281 and 449 words), qualified above and in "Provenance of the data that
matches".

### Addendum 2026-11-04: commits `1d6c386` to `46cd744` (before a push)

Delta audit of `b0b4eb7` (base, last pushed) against `46cd744` (head): `1d6c386` (graphics: Region functions,
`src/graphics/regions.s`), `1e7e105` (intuition: rendering and window functions, `screens.s`, `menus.s`,
`gadgets.s`), `9ec3a02` (exec: ramlib loading, serialisation and expunge, `src/exec/ramlib.s`, `library.s`, `io.s`,
`memory.s`), `46cd744` (graphics: GELs and animation rewritten in `src/graphics/gels.s`, a self-test tweak in
`src/exec/boot.s`). Same tool, same `tiers` and `commodore` file lists, same `--base tiers`, separate analysis agent,
production ROMs only. The head ROM was built in a clean worktree at `46cd744`; each map was relinked and its binary is
identical to the `build/prod/kick.bin` it belongs to (210,976 bytes base, 213,916 bytes head).

| role | file | sha1 |
|---|---|---|
| base ROM (production, `b0b4eb7`) | `is_kick ok`, `chk_sum ok` | `60569828178e978b25836855148a5e6663bd3cac` |
| head ROM (production, `46cd744`) | `is_kick ok`, `chk_sum ok` | `6a52f3700f71ec0343acd8c98f2a9134b33a2164` |

```sh
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --temoin tiers ... --temoin commodore ... \
    --temoin aros build/audit/adf/aros2/boot/amiga/aros.rom.gz build/audit/adf/aros2/boot/amiga/AROSBootstrap \
                  build/audit/adf/aros2/C build/audit/adf/aros2/Libs \
    --map <map> --base tiers --selftest                                # each ROM, -> out-<rom>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8   # -> all8-<rom>.txt
```

- **Controls.** A first pass was run with the `aros` group taken from the *other* AROS disk of the folder (50 hunks /
  1,171,944 bytes, see the 2026-11-03 re-run); its "aros vs reference" rows differ from the recorded ones, so it was
  discarded and both ROMs were measured again with the recorded `aros2` files. With those, the group sizes
  (21 hunks / 596,048 bytes, 390 / 413,374, 50 / 1,167,084) and every "tiers / commodore / aros vs reference" row are
  identical in the base and head runs, and the base output is byte-identical to the final-ROM output of the previous
  addendum (same ROM). The notable threshold stays **40 words / 19 instructions**. Self-check: 12/12 in both runs.

| stream | metric | base `b0b4eb7` | head `46cd744` |
|---|---|---|---|
| mots | A tokens | 104,798 | 106,265 |
| mots | max (all) / max code/table | 449 / 449 (`topaz9_loc`) | 449 / 449 (`topaz9_loc`, unchanged) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`) | **19** (`exp_cpbinding+$22`, `$0DDDA`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 115 / 10 / 5 | 114 / 10 / 5 |
| instr | A tokens / max code/table | 65,234 / 16 (keymap, entered at `+$2`) | 66,277 / 17 (keymap, entered at `+$0`) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (`exp_cpbinding+$22`) |
| instr | code ≥ 8 / ≥ 16 | 7 / 2 | 8 / 2 |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 16; 15 / 2 | 17; 17 / 2 |
| self-check | relocated fragments found | 12/12 | 12/12 |

- **Notable lists.** Identical to the base in all three streams once the offsets are ignored (pure slides): the
  keymap string tables `km_us_s42`/`km_fr_s42` (76 words), the computed CharLoc tables `topaz8_loc+$2` (281) and
  `topaz9_loc+$2` (449), the classified init/address tables and `topaz8_loc+$236`, and the two low-entropy
  `instr-souple` rows. No code match reaches 40 words or 19 instructions.
- **Keymap row in `instr`.** `km_fr_s42` (`src/exec/keymapdata.s`, unchanged source) is now decoded from `+$0`
  instead of `+$2` and gives 17 instead of 16 tokens in `instr`/`instr-souple`, as at `b7effa0` (17): the layout
  shift changes where the instruction decoder enters this data table. Same qualified data, below 19.
- **New code matches** (all below 13 instructions / 19 words, so none needs the baseline review):

| offset | stream: tokens | symbol | source, commit | nature |
|---|---|---|---|---|
| `$140F4` | mots 17, instr 11, instr-souple 11 | `rg_overlap+$0` | `src/graphics/regions.s`, new in `1d6c386` | private helper: do two rectangles share a pixel. Four comparisons of the public `Rectangle` fields (MinX/MinY/MaxX/MaxY, edges included), each one leaving early on "no overlap", then a true result; the match covers the four tests and the true result, i.e. the whole helper but its false exit. The textbook closed-interval intersection test in the public field order |
| `$080EA` | mots 8 | `rl_load+$2` | `src/exec/ramlib.s`, new in `9ec3a02` | first step of the module load (`ramlib-v34`): `FindResident` on the base name, test of the result, then `InitResident` of the found resident with an empty segment list; public LVOs and their `.fd` registers |
| `$215A6` | instr-souple 10 (several overlapping runs over 62 bytes, mixed class) | `gfx_AddAnimOb+$3C` | `src/graphics/gels.s`, rewritten in `46cd744` | end of `AddAnimOb` (return 0, register restore) and the start of the private component-placement helper: the component's Bob, then its VSprite, the AnimOb position plus the component translation, rounded with the public `ANFRACSIZE` (6 fraction bits) and stored into the public VSprite `Y` field; registers and constants erased in this stream |

- **Same matches, entered at a different offset** (code before them in the same symbol changed):
  `exec_CloseLibrary+$1C` → `+$2A` (`$0777E`, mots 14, instr 9, instr-souple 9: the end of `CloseLibrary` running
  into `Forbid`/`Permit`, already described in the 2026-11-03 re-run; `CloseLibrary` itself grew in `9ec3a02` and the
  matched lines are unchanged); `gel_vsprites+$56` → `+$62` (`$21928`, mots 8: the public cleared `AllocMem` idiom
  and its result test, the block's size stored in its first long word and the pointer in the public ViewPort
  `SprIns` field); `intuition_end+$90`/`+$13E` → `+$96`/`+$144` (`instr-souple`, 8 tokens, low entropy).
- **Reclassified, same length:** the RomTag tails `trackdisk_romtag+$C` (16, now `code/table+texte`),
  `gameport_romtag+$C` (16, now `texte`), `potgo_end+$C` (`kbddev.o`, 16, now `texte`), `input_romtag+$2` (14, now
  `table d'adresses+texte`, data) and `gfx_display_init+$12C` (10, now `texte+RomTag`): public RomTag fields, module
  names and init-table pointers, as in the earlier runs. Back in `instr-souple` only: `graphics_name+$0` (8,
  `texte`, the public name `graphics.library`, also listed at `ac2546a`).
- **Gone:** `exec_CloseDevice+$6` (mots, 8 words; `io.s` changed in `9ec3a02`). No new match of 8 tokens or more in
  the intuition files of `1e7e105` (`screens.s`, `menus.s`, `gadgets.s`) nor in `boot.s`, other than the slides above.

**Verdict (head ROM, `46cd744`): PASS.** No code match reaches the notable threshold; the longest code match is still
13 instructions / 19 words (`exp_cpbinding+$22`). The longest new code match is `rg_overlap+$0` (17 words /
11 instructions), a rectangle intersection test on public fields, below the baseline. The only `code/table` matches at
or above 40 words are the already-qualified data (keymap string tables and computed CharLoc tables), unchanged.

### Addendum 2026-11-04 (2): commits 2987398 to b573796 (before a push)

Delta audit of `2987398` (base, last pushed) against `b573796` (head): `67fab75` (intuition: CDE colour theme, issue
#24: `SC_BGCOLOR` in `src/intuition/intuition.i`, colours 0-3 and pointer colours in `pf_defaults`
(`src/intuition/prefs.s`) and `sc_palette` (`src/intuition/screens.s`), comments in `src/dos/shell.s` and
`src/exec/console.s`), `7d27d34` (graphics/intuition, #22/#25: `gfx_LoadView` in `src/graphics/graphics_lib.s` no
longer restarts a running copper; `it_remake` in `src/intuition/screens.s` merges into new copper lists, loads them,
waits for a frame and frees the old ones; `LVO_FREECPRLIST` added to `src/graphics/graphics.i`), `b573796` (palette
constants again, same files as `67fab75`). Same tool, same `tiers`, `commodore` and `aros2` file lists, same
`--base tiers`, separate analysis agent, production ROMs only, each with the vlink map of the same build. The base
binary (213,916 bytes) and its map are byte-identical to the `46cd744` head of the previous addendum; the two ROM
images differ only in 12 bytes (build identifier and checksum). Head binary: 214,008 bytes (+92).

| role | file | sha1 |
|---|---|---|
| base ROM (production, `2987398`) | `is_kick ok`, `chk_sum ok` | `7fdf268d1e92c4330b4ad8b7cf32b1ebef6b94f8` |
| head ROM (production, `b573796`) | `is_kick ok`, `chk_sum ok` | `f35101461353591075f6a695c493a8212d9e008b` |

```sh
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --temoin tiers ... --temoin commodore ... \
    --temoin aros build/audit/adf/aros2/boot/amiga/aros.rom.gz build/audit/adf/aros2/boot/amiga/AROSBootstrap \
                  build/audit/adf/aros2/C build/audit/adf/aros2/Libs \
    --map <map> --base tiers --selftest                                # each ROM, -> out-<rom>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8   # -> all8-<rom>.txt
```

- **Controls.** Group sizes (21 hunks / 596,048 bytes, 390 / 413,374, 50 / 1,167,084) and every "tiers / commodore /
  aros vs reference" row are identical in the base and head runs. The base output is identical, apart from the ROM
  sha1 line, to the head output of the previous addendum. The notable threshold stays **40 words / 19 instructions**.
  Self-check: 12/12 in both runs.

| stream | metric | base `2987398` | head `b573796` |
|---|---|---|---|
| mots | A tokens | 106,265 | 106,311 |
| mots | max (all) / max code/table | 449 / 449 (`topaz9_loc`) | 449 / 449 (`topaz9_loc`, unchanged) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`) | **19** (`exp_cpbinding+$22`, `$0DDDA`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 114 / 10 / 5 | 113 / 9 / 5 |
| instr | A tokens / max code/table | 66,277 / 17 (keymap) | 66,286 / 17 (keymap) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (`exp_cpbinding+$22`) |
| instr | code ≥ 8 / ≥ 16 | 8 / 2 | 8 / 2 |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 17; 19 / 2 (17 rows in the `--seuil 8` list) | 17; 19 / 2 (17 rows) |
| self-check | relocated fragments found | 12/12 | 12/12 |

- **Notable lists.** Identical to the base in all three streams once the offsets are ignored: the keymap string
  tables `km_us_s42`/`km_fr_s42` (76 words), the computed CharLoc tables `topaz8_loc+$2` (281) and `topaz9_loc+$2`
  (449), the classified init/address tables and `topaz8_loc+$236`, and the two low-entropy `instr-souple` rows
  (`rf_outline+$46`, `bcpl_rtdata+$8`). No code match reaches 40 words or 19 instructions.
- **`--seuil 8` lists compared** (rows keyed by stream, class, object, symbol and length, offsets ignored): every row
  of the head lists exists in the base lists except two, both data:
  - `mn_chk_hi+$0` (`$26532`, mots 20, `src/intuition/menus.s`, unchanged source): the two `struct Image`
    descriptors of the menu check marks, filed `texte` again instead of `code/table` because the masked image
    pointers moved with the layout. Same range and length; this class flip-flop was already recorded at `ac2546a`
    and in the previous addendum. It is the reason for the drop from 114 to 113 / 10 to 9 code rows in `mots`.
  - `pf_defaults+$74` (10 words) → `pf_defaults+$76` (`$273A2`, 9 words, `texte`): the default Preferences fields
    after the Workbench colours. `b573796` changed colours 0 and 2 of the same table (project theme), and the matched
    run of public default values now starts one word later and is one word shorter. Data, observable through
    `GetDefPrefs`.
- **Changed code.** No row of 8 tokens or more, in any stream, falls in `gfx_LoadView` (`$112BA`) or `it_remake`
  (`$23262`), the two routines changed by `7d27d34`, nor in `cu_setpens` or `sh_sysconfig` (comments only). In the
  palette tables changed by `67fab75`/`b573796`, the rows `sc_palette+$8` (13 words), `sc_palette+$28` (12),
  `sc_wbnewscreen+$C` (10), `pf_defaults+$0` (14) and `pf_defaults+$A4` (8) keep their range and length: they lie
  outside the changed colour words (colours 4-16 and the non-themed Preferences fields, already qualified in
  "Provenance of the data that matches").
- **New code matches:** none. No match longer than 13 instructions / 19 words appears, so no baseline review is
  needed.

**Verdict (head ROM, `b573796`): PASS.** No code match reaches the notable threshold; the longest code match is still
13 instructions / 19 words (`exp_cpbinding+$22`), and the commits add no new match of 8 tokens or more. The only
`code/table` matches at or above 40 words are the already-qualified data (keymap string tables and computed CharLoc
tables), unchanged; the longest data rows below that (`gfx_defcolors`, 32 words; `mn_chk_hi`, 20 words) are unchanged
in range and length.

### Addendum 2026-11-04 (3): commits b573796 to 81c5105 (before a push)

Delta audit up to `81c5105` (head). The base of the push, `023475a` (already on `origin/main`), was not itself audited:
after the `b573796` head of the previous addendum came `1a0da17` (docs only) and `023475a` (another session:
expansion.library reset memo, `exp_memosave`, `xm_sum` and `exp_memoload` added at the end of
`src/exec/expansion.s`, one call to `exp_memoload` at the end of `expansion_initfunc`, one call to `exp_memosave` in
`disk_watch` in `src/exec/boot.s`, `RESET_MEMO` in `src/exec/exec.i`). So this addendum covers two deltas:
`b573796` → `023475a` (compared with the head figures of the previous addendum) and `023475a` → `81c5105`:
`f9a5c5b` (`src/dos/workbench.s`: the NewWindow flag constants of `wb_desktop` and `wb_opendrawer` gain
`SIMPLE_REFRESH`; `src/intuition/intuition.i`: new `SIMPLE_REFRESH` EQU) and `81c5105` (docs only). Same tool, same
`tiers`, `commodore` and `aros2` file lists, same `--base tiers`, separate analysis agent, production ROMs only, each
with the vlink map of the same build.

Binary sizes: `b573796` 214,008 bytes, `023475a` 214,404 bytes (+396: `boot.o` +12, `expansion.o` +384),
`81c5105` 214,404 bytes (+0). The `023475a` and `81c5105` maps give the same address to every symbol; the two ROM
images differ in 14 bytes only: the build identifier and the checksum, plus one byte at `$316D7` (inside
`wb_desktop`, `$31676`-`$31730`) and one at `$32A27` (inside `wb_opendrawer`, `$32964`-`$32A7A`), the two flag
constants changed by `f9a5c5b`.

| role | file | sha1 |
|---|---|---|
| previous head ROM (production, `b573796`) | `is_kick ok`, `chk_sum ok` | `f35101461353591075f6a695c493a8212d9e008b` |
| base ROM (production, `023475a`) | `is_kick ok`, `chk_sum ok` | `d31849a002b7fc4e89d2818df4340198e8d8030a` |
| head ROM (production, `81c5105`) | `is_kick ok`, `chk_sum ok` | `7f634848064ef1b7442bde47d42f9c045aa16ada` |

```sh
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --temoin tiers ... --temoin commodore ... \
    --temoin aros build/audit/adf/aros2/boot/amiga/aros.rom.gz build/audit/adf/aros2/boot/amiga/AROSBootstrap \
                  build/audit/adf/aros2/C build/audit/adf/aros2/Libs \
    --map <map> --base tiers --selftest                                # each ROM, -> out-<rom>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8   # -> all8-<rom>.txt
```

- **Controls.** Group sizes (21 hunks / 596,048 bytes, 390 / 413,374, 50 / 1,167,084) and every "tiers / commodore /
  aros vs reference" row are identical in the previous head, base and head runs. The notable threshold stays
  **40 words / 19 instructions**. Self-check: 12/12 in both runs.

| stream | metric | previous head `b573796` | base `023475a` | head `81c5105` |
|---|---|---|---|---|
| mots | A tokens | 106,311 | 106,509 | 106,509 |
| mots | max (all) / max code/table | 449 / 449 (`topaz9_loc`) | 449 / 449 (`topaz9_loc`) | 449 / 449 (`topaz9_loc`) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`) | **19** (`exp_cpbinding+$22`, `$0DDE6`) | **19** (same) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 113 / 9 / 5 | 113 / 10 / 5 | 113 / 10 / 5 |
| instr | A tokens / max code/table | 66,286 / 17 (keymap) | 66,408 / 16 (keymap) | 66,407 / 16 (keymap) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (`exp_cpbinding+$22`) | **13** (same) |
| instr | code ≥ 8 / ≥ 16 | 8 / 2 | 8 / 2 | 8 / 2 |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 17; 19 / 2 | 16; 19 / 2 | 16; 19 / 2 |
| `--seuil 8` list | rows (mots / instr / instr-souple) | 265 / 46 / 84 | 265 / 44 / 81 | 265 / 44 / 81 |
| self-check | relocated fragments found | 12/12 | 12/12 | 12/12 |

- **Notable lists.** Identical in the three runs once the offsets are ignored: the keymap string tables
  `km_us_s42`/`km_fr_s42` (76 words), the computed CharLoc tables `topaz8_loc+$2` (281) and `topaz9_loc+$2` (449),
  the classified init/address tables and `topaz8_loc+$236`, and the two low-entropy `instr-souple` rows
  (`rf_outline+$46`, `bcpl_rtdata+$8`). No code match reaches 40 words or 19 instructions.
- **`023475a` against the previous head** (`--seuil 8` lists keyed by stream, class, object, symbol and length,
  offsets ignored). Every changed row lies in an unchanged source file and is data or a layout effect; none is in
  the code added by `023475a`:
  - `km_fr_s42+$0` (17 instructions, `instr` and `instr-souple`) → `km_fr_s42+$2` (`$0D29E`, 16): the French keymap
    string table, already qualified; the matched run now starts one word later, like the `km_us_s42+$2` row
    (16, unchanged). This is the drop of the `instr` max code/table from 17 to 16.
  - `mn_chk_hi+$0` (`$266BE`, mots 20): the menu check-mark `struct Image` descriptors flip back from `texte` to
    `code/table` as the layout moved (same range and length; the flip-flop already recorded at `ac2546a` and in the
    two previous addenda). It accounts for the rise of mots code ≥ 16 from 9 to 10.
  - `graphics_romtag+$C` (mots 15): filed `texte` instead of `code/table+texte` (`$1064C`); `gfx_display_init+$12C`
    (mots 10, `$1062C`): `texte` instead of `texte+RomTag`. Same symbols and lengths, class only. The first one
    offsets the `mn_chk_hi` change in mots code ≥ 8 (113 both).
  - 8- and 9-instruction text rows on the resident names (`trackdisk_name`, `gameport_dev_name`, `intuition_name`,
    `console_name`, `graphics_name`) and the low-entropy `km_us_lotypes+$2` (`$0CCF0`, `instr-souple` 8): rows that
    appear, disappear or move by one word because the instruction streams re-segment the ROM strings and tables
    after the layout shift. Data only; 5 rows fewer in total.
- **Code changed by `023475a`.** No row of 8 tokens or more, in any stream, lies in `exp_memosave`, `xm_sum`,
  `exp_memoload` (`$0E40E`-`$0E58A`, up to `expansion_end`) or in `disk_watch` (`$042BC`-`$042F8`). The only row in
  `expansion_initfunc` is `expansion_initfunc+$E` (`$0E3BC`, mots 8, `code/table`), present at the same symbol offset
  and length in the previous head (`$0E3B0`); it ends before the inserted call near the end of the routine.
- **`023475a` → `81c5105`.** The two `--seuil 8` lists are identical row for row (offsets included); the notable
  lists too. The instr streams count one token fewer; no row changes. No row of 8 tokens or more lies in
  `wb_desktop` or `wb_opendrawer`.
- **New code matches:** none in either delta. No match longer than 13 instructions / 19 words appears, so no
  baseline review is needed.

**Verdict (head ROM, `81c5105`, and base `023475a`): PASS.** No code match reaches the notable threshold; the longest
code match is still 13 instructions / 19 words (`exp_cpbinding+$22`), and neither `023475a` nor `f9a5c5b` adds a new
code match of 8 tokens or more. The only `code/table` matches at or above 40 words are the already-qualified data
(keymap string tables and computed CharLoc tables), unchanged; the longest data rows below that (`gfx_defcolors`,
32 words; `mn_chk_hi`, 20 words) keep their range and length.

### Addendum 2026-11-05: d153179..532cc3a, then 532cc3a + rf_outline rewrite (before a push)

Two runs. Run 1 audits `532cc3a` and fails in the `instr-souple` stream; the implementation track then rewrote the
outline path of `rf_outline`, and run 2 audits that tree. The final verdict is at the end of run 2.

#### Run 1: head `532cc3a` (history)

Delta audit of the local commits about to be pushed: base `d153179` (`origin/main`, docs only on top of `81c5105`,
audited above), head `532cc3a`. Source changes: `1c0faca` (BorderTop 11 and icon names, `src/dos/workbench.s`,
`src/intuition/screens.s`), `fc546be` (potgo.resource boot proof dev-only, `src/exec/boot.s`), `c3405b0` and
`a2769b9` (ROM file system on any block device: `src/dos/handler.s`, `ofs.s`, `ofswrite.s`, `ofs.i`, `bcpl.s`,
`dos_lib.s`; expansion.library cold init, `src/exec/expansion.s`, `resident.s`, `boot.s`), `d6e091d` (SetRast,
RectFill, ScrollRaster, pen/mode setters and minterm table, `src/graphics/draw.s`), `c4e40ac` (disk validator bitmap
rebuild, `src/dos/diskvalidator.s`), `5f7964e` (write-back, `src/dos/ofswrite.s`, `handler.s`); the other commits
are docs or the amiberry skill. Same tool, same `tiers`, `commodore` and `aros2` file lists, same `--base tiers`,
separate analysis agent, production ROMs (`make kick-prod`) only, each with the vlink map of the same build.

Binary sizes: `d153179` 214,404 bytes, `532cc3a` 216,836 bytes (+2,432).

| role | file | sha1 |
|---|---|---|
| base ROM (production, `d153179`) | `is_kick ok`, `chk_sum ok` | `cfdf2dcc8063fb5e7e73eb1c0be229fa1019c364` |
| head ROM (production, `532cc3a`) | `is_kick ok`, `chk_sum ok` | `388392aaff730e70f4bdc3e5bb708ba8c87eb435` |

```sh
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --temoin tiers ... --temoin commodore ... \
    --temoin aros build/audit/adf/aros2/boot/amiga/aros.rom.gz build/audit/adf/aros2/boot/amiga/AROSBootstrap \
                  build/audit/adf/aros2/C build/audit/adf/aros2/Libs \
    --map <map> --base tiers --selftest                                # each ROM, -> out-<rom>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8   # -> all8-<rom>.txt
```

- **Controls.** Group sizes (21 hunks / 596,048 bytes, 390 / 413,374, 50 / 1,167,084) and every "tiers / commodore /
  aros vs reference" row are identical in the base and head runs. The notable threshold stays **40 words /
  19 instructions / 19 loose instructions** (`tiers` maxima 39 / 18 / 18, plus one). Self-check: 12/12 in both runs.

| stream | metric | base `d153179` | head `532cc3a` |
|---|---|---|---|
| mots | A tokens | 106,504 | 107,718 |
| mots | max (all) / max code/table | 449 / 449 (`topaz9_loc`) | 449 / 449 (`topaz9_loc`) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`, `$0DDE6`) | **19** (same, `$0DCC8`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 113 / 10 / 5 | 114 / 9 / 5 |
| instr | A tokens / max code/table | 66,407 / 16 (keymap) | 67,281 / 17 (keymap, `km_fr_s42+$0`) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| instr | code ≥ 8 / ≥ 16 | 8 / 2 | 8 / 2 |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 16; 19 / 2 | **26** (`rf_outline+$4E`); 21 / 3 |
| `--seuil 8` list | rows (mots / instr / instr-souple) | 265 / 44 / 81 | 267 / 45 / 86 |
| self-check | relocated fragments found | 12/12 | 12/12 |

Against the controls, our head ROM's longest `instr-souple` code match is 8 tokens (`tiers`), 7 (`commodore`) and
11 (`aros`), as in the base.

- **Notable lists, `mots` (40) and `instr` (19).** Unchanged once offsets are ignored, except one row: the
  `expansion_inittab+$4` address table (58 words) becomes `expansion_vectors+$0` (`$0DBFC`, 52 words, `table
  d'adresses`), because `c3405b0` removed the AUTOINIT init table in front of the vector table (the resident now
  calls MakeLibrary itself); the vector table, whose normalised form only gives the number of LVOs, is unchanged.
  The other rows are the qualified data already listed (keymap string tables, computed CharLoc tables, classified
  init/address tables, `topaz8_loc+$236`). No `instr` row.
- **Notable list, `instr-souple` (19): one code/table row.**

| offset | address | bytes | loose tokens | symbol | source | changed by these commits |
|---|---|---|---|---|---|---|
| `$1268C` | `$FD268C` | 72 | **26** | `rf_outline+$4E` to the end of `rf_outline` (`gfx_SetRast` follows at `$126D4`) | `src/graphics/draw.s` | partly: last 6 of the 26 tokens (`d6e091d`) |

`rf_outline` is RectFill's AREAOUTLINE path. The range covers the outline drawing (one Move and four Draw calls
through the graphics LVOs, each preceded by the RastPort and the two coordinates loaded into the argument
registers) and the routine's epilogue (the saved DrawMode, FgPen and the two minterm longwords popped back into
the RastPort, register restore, return). The order and arguments of the five calls follow
`docs/analysis/graphics-raster-v34.md` §3.7 step 2, and the restored fields follow §3.7 step 3. The first
20 tokens (the five calls) are the low-entropy row recorded since the original audit (`rf_outline+$44`/`+$46`,
20 tokens, `faible entropie`); in the base it is `rf_outline+$42`, 20 tokens, still low entropy. `d6e091d`
replaced the old epilogue (SetDrMd and SetAPen calls) with direct stores of the saved fields, after pushing the two
minterm longwords as well. With that epilogue the loose match runs 6 tokens further, to the `rts`. Because the
range now holds more than three distinct tokens, it is classified `code/table`, no longer low entropy. In the exact
streams the same range matches only in short pieces: `instr` 8 instructions (`rf_outline+$58` and `+$6C`, two
Draw calls each), `mots` 10 words (same two places). The 26-token run therefore exists only once registers and
constants (field offsets, LVOs) are erased.
- **New matches above the baseline (13 instructions / 19 words).** Only the row above. In `mots` and `instr`, no new
  code match exceeds the baseline. `km_fr_s42+$0` (`instr` 17) is the qualified French keymap string table, back
  to its `b573796` start and length after a layout shift.
- **Other changes in the `--seuil 8` lists** (keyed by stream, class, object, symbol and length, offsets ignored).
  All are below the baseline:
  - New code in these commits: `expansion_coldinit+$6` (`$0E296`, mots 8, instr-souple 8), the MakeLibrary
    call of the new cold init (arguments in the registers the `.fd` fixes) and its result test.
  - Same symbol and length, start shifted inside routines edited or moved by these commits: `expansion_initfunc+$E`
    → `+$C` (mots 8), `ofs_dir_next`, `ofs_name_to_block`, `ofs_read_file`, `ow_create` (mots 8 each),
    `dr_rect+$5A` → `+$40` (instr-souple 9), `rf_outline+$50`/`+$64` → `+$58`/`+$6C` (mots 10, instr 8),
    `bcpl_rtdata+$48` → `+$3C` (low entropy 10), `sr_vert+$316` → `+$25C` (`texte` 10).
  - Class or range flips from the layout shift, already seen in earlier runs: `potgo_end+$C` (16, RomTag end and
    public name) now `code/table`, `mn_chk_hi+$0` (20) now `texte`, `fnt_ta8+$0` (10) now `code/table+texte`,
    `gameport_end+$2` (17) → `+$C` (15, followed by the expansion RomTag whose flags byte changed).
  - New data: the disk validator requester texts `dv_err1+$1` and `dv_corrupt+$1` (mots 10 and 11, `texte`). There
    are also low-entropy rows in `bcpl_rtdata` (8) and the resident-name text rows (`trackdisk_name`,
    `gameport_dev_name`, `console_name`, 8) that the instruction streams re-segment.
  - Gone: `hnd_init+$12` (mots 8), `rf_outline+$42` (merged into the row above).

**Run 1 verdict (head ROM, `532cc3a`): FAIL under the mechanical rule, in the `instr-souple` stream only.** One
`code/table` match, `rf_outline+$4E` (26 loose instructions, `src/graphics/draw.s`), reaches the 19-token loose
threshold. Its last 6 tokens come from the epilogue that `d6e091d` rewrote. The `mots` and `instr` streams pass: the
longest code match is still 19 words / 13 instructions (`exp_cpbinding+$22`), and the only matches at or above
40 words are the already-qualified data. The base (`d153179`) passes: its row in the same routine is 20 tokens,
classified low entropy. The match is a loose-only coincidence of the five spec-ordered outline calls and the restore
of the spec-listed fields; the exact streams share at most 8 instructions there. The rule still calls for review on
the implementation side before the push. The loose row would most likely fall back to the base's low-entropy
20 tokens if the restore of the saved fields were again written in a way that leaves the five-call run without the
same epilogue, for example through the setter calls as before `d6e091d`. That is a design choice for the
implementation track, which should rerun this audit afterwards.

#### Run 2: head `532cc3a` + rf_outline rewrite (working tree, since committed as `4965827`)

The implementation track rewrote the outline path of `rf_outline` (`src/graphics/draw.s`, the only source file
changed on top of `532cc3a`): the Move and the four Draws now run in a loop over a small table of corner selectors,
the new local symbol `ro_path` (10 bytes, between `rf_outline` and `gfx_SetRast`). The order and arguments of the
five calls are unchanged (spec §3.7 step 2). Same tool, same control lists, same `--base tiers`, separate analysis
agent, production ROM (`make kick-prod`); the map comes from a vlink relink of the same `build/prod` objects with
`-M`, whose output is byte-identical to `build/prod/kick.bin`.

| role | file | sha1 |
|---|---|---|
| head ROM (production, `532cc3a` + rewrite) | `is_kick ok`, `chk_sum ok` | `e0cf99e85c43a4b0a9c2eb8dde69c3e8c75ed4be` |

Binary size 216,844 bytes (+8 against `532cc3a`). `rf_outline` keeps its start and its 150-byte extent; every
symbol after it moves by 10 bytes.

- **Controls.** Group sizes, every "tiers / commodore / aros vs reference" row and the notable threshold (40 words /
  19 instructions / 19 loose instructions) are identical to run 1. Self-check: 12/12. Against the controls, our
  ROM's longest `instr-souple` code match is still 8 (`tiers`), 7 (`commodore`) and 11 (`aros`).

| stream | metric | base `d153179` | run 1 `532cc3a` | run 2 `532cc3a` + rewrite |
|---|---|---|---|---|
| mots | A tokens | 106,504 | 107,718 | 107,725 |
| mots | max (all) / max code/table | 449 / 449 (`topaz9_loc`) | 449 / 449 | 449 / 449 (`topaz9_loc`) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`) | **19** (same) | **19** (same, `$0DCC8`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 113 / 10 / 5 | 114 / 9 / 5 | 112 / 9 / 5 |
| instr | A tokens / max code/table | 66,407 / 16 (keymap) | 67,281 / 17 (keymap) | 67,287 / 17 (keymap, `km_fr_s42+$0`) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** | **13** (same) |
| instr | code ≥ 8 / ≥ 16 | 8 / 2 | 8 / 2 | 6 / 2 |
| instr-souple | max (all) | 23 (`bcpl_rtdata+$8`, low entropy) | 26 | 23 (same row) |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 16; 19 / 2 | **26** (`rf_outline+$4E`); 21 / 3 | **17** (keymap, `km_fr_s42+$0`); 20 / 2 |
| `--seuil 8` list | rows (mots / instr / instr-souple) | 265 / 44 / 81 | 267 / 45 / 86 | 264 / 43 / 85 |
| self-check | relocated fragments found | 12/12 | 12/12 | 12/12 |

- **Notable lists.** `mots` (40): the same 13 rows as in run 1 (4 `code/table`: the two keymap string tables and the
  two CharLoc tables; 9 classified data), offsets shifted by 10 after `rf_outline`. `instr` (19): no row.
  `instr-souple` (19): **no `code/table` row**; the only row is the classified low-entropy `bcpl_rtdata+$8`
  (23 tokens, `$2DFB8`), present in the base and in run 1.
- **`rf_outline` and `ro_path`.** Neither has any row of 8 tokens or more in any stream. A `--seuil 5` listing
  shows that the longest match left inside `rf_outline` is 5 tokens (`mots` at `rf_outline+$80`, and a
  low-entropy `instr-souple` row at `rf_outline+$12`); `ro_path` has none.
- **`--seuil 8` lists against run 1** (keyed by stream, class, object, symbol and length, offsets ignored): nothing
  new. Gone: the five `rf_outline` rows (`instr-souple` 26 at `+$4A`; `instr` 8 and `mots` 10 at `+$58` and
  `+$6C`), and `al_coplist+$84` (`mots` 8, a `RomTag`-classified data row that the 10-byte shift re-segments).
  Against the base, the differences are those listed for run 1, minus the `rf_outline` rows and plus the loss of
  `al_coplist+$84` above.
- **New matches above the baseline (13 instructions / 19 words).** None. The only code matches above 13 in the
  instruction streams are the keymap string tables (`km_us_s42`, `km_fr_s42`, 16-17), qualified data.

**Final verdict (head ROM, `532cc3a` + rf_outline rewrite): PASS.** No code/table match reaches 40 words,
19 instructions or 19 loose instructions in any stream; the longest code match, data excluded, is 19 words /
13 instructions (`exp_cpbinding+$22`), the base's baseline; the run 1 FAIL row is gone and the rewritten outline
path matches the reference on at most 5 tokens. While this run was in progress the audited source was committed as
`4965827` (its `src/` and `Makefile` are identical to the audited tree, and `draw.o` predates the commit); a rebuild
of that commit differs from the audited ROM only by the embedded ROM ID string (`git describe --dirty`). Any later
source change needs a new run.

### Addendum 2026-11-05: c4a3519..bad9952 (before a push)

Delta audit of the local commits about to be pushed: base `c4a3519` (`origin/main`, audited as the base of PR #27 in
`docs/audit/pr-27.md`), head `bad9952`. Source changes (`git diff c4a3519 bad9952 -- src/`): `b1e4503` (console
geometry recomputed after a window resize, issue #26: new `cu_resize` and `cu_edges` in `src/exec/console.s`, one
line in `cu_geom`, a width test at the top of `cu_write`), `1309b24` (`src/exec/rawdofmt.s` rewritten to
`docs/analysis/exec-rawdofmt-v34.md`, rank 11, and the expected string of the RawDoFmt self-test in
`src/exec/boot.s`), `3e62aa5` (`src/dos/feeder.s`: the keyboard ring is drained before the timer/repeat step); the
other commits are docs, the analysis page and a test probe. Same tool, same `tiers`, `commodore` and `aros2` file
lists, same `--base tiers`, separate analysis agent, production ROMs (`make kick-prod`) only, each with the vlink map
of the same build.

| role | linked bytes | `romtool info` | sha1 |
|---|---|---|---|
| base ROM (production, `c4a3519`) | 216,844 | `is_kick ok`, `chk_sum ok` | `269c924f16d3c1811d4390ebdc78898c49a60d54` |
| head ROM (production, `bad9952`) | 217,024 (+180) | `is_kick ok`, `chk_sum ok` | `5ebd05825adb32c3dfa7df363cb340c39060ffb9` |

The base ROM file is the one audited for PR #27 (same md5, same map), so its `--selftest` run and its `--seuil 8`
list from that audit were reused; only the head was run anew. `rawdofmt.o` shrinks from 506 to 426 bytes.

```sh
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --temoin tiers ... --temoin commodore ... \
    --temoin aros build/audit/adf/aros2/boot/amiga/aros.rom.gz build/audit/adf/aros2/boot/amiga/AROSBootstrap \
                  build/audit/adf/aros2/C build/audit/adf/aros2/Libs \
    --map <map> --base tiers --selftest                                # head ROM, -> out-head.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8   # -> all8-head.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 4   # base and head, -> all4-*.txt
```

The `--seuil 8` and `--seuil 4` lists were compared by (stream, class, object, symbol + offset, length), absolute
offsets ignored. Rows touching the changed code were found by overlapping each row's range with the extents of the
changed routines in our own maps (`rawdofmt.o`; `cu_geom` to the start of `cu_write`'s loop; `feeder_main`;
`rdf_selftest` and its strings).

- **Controls.** Group sizes (21 hunks / 596,048 bytes, 390 / 413,374, 50 / 1,167,084) and every "tiers / commodore /
  aros vs reference" row are identical in the base and head runs. The notable threshold stays **40 words /
  19 instructions / 19 loose instructions** (`tiers` maxima 39 / 18 / 18, plus one). Self-check: 12/12 in both runs.
  Against the controls, our head ROM's longest code match is unchanged: `mots` 10 / 11 / 449 (tiers / commodore /
  aros, the last being the computed CharLoc table), `instr` 6 / 7 / 7, `instr-souple` 8 / 7 / 11.

| stream | metric | base `c4a3519` | head `bad9952` |
|---|---|---|---|
| mots | A tokens | 107,716 | 107,811 |
| mots | max (all) / max code/table | 449 / 449 (`topaz9_loc`) | 449 / 449 (`topaz9_loc`) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`) | **19** (same, `$0DD7A`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 112 / 9 / 5 | 109 / 9 / 5 |
| instr | A tokens / max (all) / max code/table | 67,281 / 17 / 17 (`km_fr_s42+$0`) | 67,319 / 17 / 17 (`km_fr_s42+$0`, `km_us_s42+$0`) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| instr | code ≥ 8 / ≥ 16 | 6 / 2 | 6 / 2 |
| instr-souple | max (all) | 23 (`bcpl_rtdata+$8`, low entropy) | 23 (same row, `$2E06C`) |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 17 (keymap); 20 / 2 | 17 (keymap); 20 / 2 |
| instr-souple | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| `--seuil 8` list | rows (mots / instr / instr-souple) | 264 / 43 / 85 | 264 / 44 / 86 |
| self-check | relocated fragments found | 12/12 | 12/12 |

- **Notable lists.** `mots` (40): the same 13 rows as in the base, offsets shifted by the layout (4 `code/table`: the
  two keymap string tables and the two computed CharLoc tables; 9 classified data). `instr` (19): no row.
  `instr-souple` (19): no `code/table` row; the only row is the classified low-entropy `bcpl_rtdata+$8` (23 tokens),
  as in the base.
- **New matches above the baseline (13 instructions / 19 words).** None from new code. The only `--seuil 8` rows
  new to the head are class or range flips of unchanged data, already seen in earlier runs: `mn_chk_hi+$0`
  (`$268EC`, mots 20, `src/intuition/menus.s`, not changed) flips from `texte` back to `code/table` (the qualified
  menu check-mark `struct Image` descriptors, see "Provenance" below); `gameport_romtag+$C` (16) and
  `input_romtag+$2` (14) become `code/table` while `potgo_end+$C` (16), `trackdisk_romtag+$C` (16), `input_end+$C`
  (15), `timer_romtag+$C` (13) and `topaz9_font+$20` (10) become `texte` (RomTag tails and resident names, all
  below the baseline; this is why mots code ≥ 8 falls from 112 to 109); `romboot_romtag+$C` (18) changes its mixed
  class; the keymap string table `km_us_s42` (instr / instr-souple) is back to its `+$0` start at 17 tokens (from
  `+$2`, 16), qualified data; the resident-name rows `trackdisk_name` (9) and `intuition_name` (8) are re-segmented
  `texte` rows in the instruction streams.
- **Rewritten `exec_RawDoFmt` (`rawdofmt.o`, entirely changed by `1309b24`).** No row of 8 tokens or more in any
  stream, before or after. Longest matches from the `--seuil 4` lists:

| stream | base `c4a3519` (old RawDoFmt) | head `bad9952` (rewrite) |
|---|---|---|
| mots | 7 (`exec_RawDoFmt+$AC`, low entropy); code/table 5 (`+$14`) | 4 (`exec_RawDoFmt+$BE`, low entropy); no code/table row of 4 |
| instr | 4 (`+$14`, code/table) | none of 4 or more |
| instr-souple | 6 (`+$22`, code/table + low entropy); code/table alone 4 | 5 (`+$30`, low entropy); code/table 4 (`+$16`, `+$FA`) |

  The formatter, a classic place for convergent code, shares at most 4 code/table tokens with the reference in any
  stream after the rewrite (shorter than before). The self-test change in `src/exec/boot.s` only edits two strings
  (`rdf_expect`, `msg_rdf_ok`); neither has a row, and the rows inside `rdf_selftest` (unchanged code) are at most
  6 words.
- **Console resize (`cu_resize`, `cu_edges`, `cu_geom`, `cu_write`, `b1e4503`).** No row of 8 tokens or more. From
  the `--seuil 4` list, the longest rows in or next to the changed code are `mots` 5 (`cu_write+$22`, low entropy,
  the base's 4-word low-entropy row at `cu_write+$12` re-segmented by the inserted width test) and 4 (`cu_resize+$32`,
  low entropy), no `instr` row, and `instr-souple` 5 (`cu_resize+$5C`, low entropy) and 4 (`code/table` at
  `cu_resize+$AC` and `cu_edges+$1C`; `texte`-classified rows of 4 at `cu_resize+$84`, `+$98`).
- **Feeder loop (`feeder_main`, `3e62aa5`).** The `code/table` rows of `feeder_main` in the `--seuil 4` lists keep
  the base's symbol offsets and lengths (longest: mots 8 at `+$8`, `+$64`, `+$A4`; instr-souple 6 at `+$9A`), except
  one 4-word row whose start moves from `+$166` to `+$168` after the reordered branch; two low-entropy rows of 4-5
  words move inside the routine (`+$F2`, `+$14E` → `+$14A`, `+$15A`). Nothing new of 6 tokens or more.
- **Other `--seuil 4` changes** (all below 8 tokens, outside the changed files except the layout): re-segmented
  resident-name and RomTag `texte` rows, `pointer_input_handler+$14`/`+$40` (mots 6) and `misc_init+$8`
  (instr-souple 6) in files not changed by these commits, appearing as the 180-byte shift moves word boundaries.

**Verdict (head ROM, `bad9952`): PASS.** No code/table match reaches 40 words, 19 instructions or 19 loose
instructions in any stream. The longest code match, data excluded, is still 19 words / 13 instructions
(`exp_cpbinding+$22`), the base's baseline, and no new code match exceeds it. The only new row above the baseline
is the 20-word `mn_chk_hi+$0`, qualified `struct Image` data in a file these commits do not touch, which changed
class only. The rewritten RawDoFmt matches the reference on at most 4 code/table tokens (5 low-entropy loose
tokens), the console resize code on at most 5 low-entropy tokens, and the feeder change adds nothing. Any later
source change needs a new run.

## Re-run 2026-11-05 (merge of PR #27, `6d85d6b..f9ca145`)

The merge commit's tree is identical to the PR head `f9ca145` (`git diff --quiet f9ca145 <merge>`). The binary
audit of that head against `6d85d6b` was run by a separate analysis agent with this page's controls, `--base tiers`
and `--seuil 8`, on production ROMs and their maps. Its full figures are in `docs/audit/pr-27.md`, section 6.1.

**Verdict: PASS.**
- No code/table match reaches 40 words, 19 instructions or 19 loose instructions.
- The longest code match, data excluded, stays 19 words / 13 instructions (`exp_cpbinding+$22`), and no new code
  match exceeds it.
- `--seuil 8` rows go from 264 / 44 / 86 to 266 / 44 / 91 (words / instr / instr-souple).
- The new rows are seven bound-test or call runs of at most 10 tokens in PR-added code (`dr_directdraw`,
  `ln_boxhits`, `ln_blit`, `ae_update_visible`, `gfx_AreaEnd`).
- One class flip: `topaz9_font+$20`, 10 words, `texte` → `code/table`.
- Self-check: 12/12.

## Re-run 2026-11-05 (`a525205..f907844`, before the push)

Delta: one source change, `src/intuition/screens.s`, routine `wn_scrtitle` (two instructions added: compare the new
title pointer with `Screen.Title`, return early when equal); the other commit of the range only touches
`docs/analysis/`. Run by a separate analysis agent on production ROMs (`make kick-prod`, `romtool info`:
`is_kick ok`, checksum ok) built in two worktrees, each with the vlink map of the same build.

Commands (repo root; `run.sh` is the full command of "Commands" above, same `tiers` / `commodore` / `aros`
controls, `--base tiers --selftest`):

```
bash run.sh <base|head>.rom <base|head>.map > out-<base|head>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8 > all8-<base|head>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 4 > all4-<base|head>.txt
```

The `--seuil 8` and `--seuil 4` lists were compared by (stream, class, object, symbol+offset, length), absolute
offsets ignored.

- **Layout.** Only `screens.o` changes size (+6 bytes); every later object shifts by 6 bytes, then by 8 from
  `dos_lib.o` on (one extra alignment word). The ROM ID string grows by 12 bytes (`git describe` of a non-tagged
  commit), which with the 3 words of the added instructions accounts for the +9 word tokens.
- **Controls.** Group sizes (21 hunks / 596,048 bytes, 390 / 413,374, 50 / 1,167,084) and every "tiers / commodore /
  aros vs reference" row are identical in the base and head runs. The notable threshold stays **40 words /
  19 instructions / 19 loose instructions** (`tiers` maxima 39 / 18 / 18, plus one). Against the controls, our head
  ROM's longest code match is unchanged: `mots` 10 / 11 / 449 (tiers / commodore / aros, the last being the computed
  CharLoc table), `instr` 6 / 7 / 7, `instr-souple` 8 / 7 / 11.

| stream | metric | base `a525205` | head `f907844` |
|---|---|---|---|
| mots | A tokens | 109,956 | 109,965 |
| mots | max (all) / max code/table | 449 / 449 (`topaz9_loc`) | 449 / 449 (`topaz9_loc`) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`) | **19** (same, `$0DD80`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 111 / 9 / 5 | 111 / 9 / 5 |
| instr | A tokens / max (all) / max code/table | 68,714 / 17 / 17 (`km_fr_s42+$0`, `km_us_s42+$0`) | 68,721 / 17 / 17 (same) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| instr | code ≥ 8 / ≥ 16 | 6 / 2 | 6 / 2 |
| instr-souple | max (all) | 23 (`bcpl_rtdata+$8`, low entropy) | 23 (same row, `$2F140`) |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 17 (keymap); 21 / 2 | 17 (keymap); 21 / 2 |
| instr-souple | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| `--seuil 8` list | rows (mots / instr / instr-souple) | 266 / 44 / 91 | 267 / 44 / 91 |
| self-check | relocated fragments found | 12/12 | 12/12 |

- **Notable lists.** `mots` (40): the same 13 rows as in the base (4 `code/table`: the two keymap string tables
  and the two computed CharLoc tables; 9 classified data), offsets shifted by the layout. `instr` (19): no row.
  `instr-souple` (19): only the classified low-entropy `bcpl_rtdata+$8` (23 tokens), as in the base.
- **`--seuil 8` differences.** One row only, new in the head: `mots`, class `RomTag`, `al_coplist+$84` (`$2A3F0`,
  8 words). It is the base's 7-word `RomTag` row at the same symbol offset (in the base's `--seuil 4` list only),
  one word longer: the new alignment
  word before `dos_lib.o` now sits between the last word of `al_coplist` and the mandated `dos_romtag` header
  (match word and normalised self/end pointers). Classified data, below the baseline. No row disappears.
- **Changed routine (`wn_scrtitle`).** No row of 8 tokens or more in or next to it in any stream. In the
  `--seuil 4` lists the only row in the routine is the base's `instr-souple` 4-token row at `wn_scrtitle+$8`
  (`$244D2`, 12 bytes): same start, same length, its class flips from `texte` to `code/table` because the added
  compare replaces a store in the covered bytes. The neighbouring rows (`sc_drawbar+$40`, `+$6E`, 4 loose
  instructions, low entropy) are unchanged.
- **Other `--seuil 4` changes** (all below 8 tokens, data, caused by the shift): the ROM footer rows
  (`en-tete/pied ROM`) re-anchored, two `workbench.o` low-entropy rows (`wbm_i04+$E` 4 → 5, `wbm_i23t+$E` 4),
  and the `al_coplist+$84` `RomTag` row above.

**Verdict (head ROM, `f907844`): PASS.** No code/table match reaches 40 words, 19 instructions or 19 loose
instructions in any stream. The longest code match, data excluded, is still 19 words / 13 instructions
(`exp_cpbinding+$22`), and no new code match exceeds it; the only new `--seuil 8` row is an 8-word RomTag data row
lengthened by an alignment word. The changed `wn_scrtitle` matches the reference on at most 4 loose instructions,
as before the change. Any later source change needs a new run.

## Re-run 2026-11-05 (`d22c5d2..17da6ee`, before the push)

Delta (`src/` only): rank 12 (`src/exec/ports.s` rewritten; `io.s`, `library.s`, `execmisc.s`, `resident.s`, the
`ln_Type` store moved from exec's SendIO/DoIO into the `BeginIO` of `audio.s`, `console.s`, `gameport.s`;
`boot.s`), rank 13 (`memory.s`, `semaphores.s`, CopyMem/CopyMemQuick in `io.s`, removals in `execmisc.s`), rank 15
(`src/exec/mathffp.s` rewritten from the arithmetic rules of `docs/analysis/mathffp-v34.md`, with an ID string;
`trackdisk.s` `td_cachebuf`; `boot.s`), `libinit.s` (MakeLibrary: one line) and `trackdisk.s` `td_lowmem` with
its call from `memory.s`. Run by a separate analysis agent on production ROMs (`make kick-prod`, `romtool info`:
`is_kick ok`, checksum ok) built in two worktrees (`d22c5d2`, `17da6ee`), each with the vlink map of the same build.

Commands (repo root; `run.sh` is the full command of "Commands" above, same `tiers` / `commodore` / `aros`
controls, `--base tiers --selftest`):

```
bash run.sh <base|head>.rom <base|head>.map > out-<base|head>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8 > all8-<base|head>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 4 > all4-<base|head>.txt
```

The `--seuil 8` and `--seuil 4` lists were compared by (stream, class, object, symbol+offset, length), absolute
offsets ignored. The one new row of 40 tokens or more was bracketed with `--seuil 30` to `41` on the head ROM.

- **Layout.** Object size changes: `boot.o` −4, `memory.o` +250, `library.o` +50, `ports.o` +6, `io.o` +34,
  `resident.o` −2, `trackdisk.o` +104, `console.o` +6, `gameport.o` +6, `mathffp.o` +272, `audio.o` +6,
  `semaphores.o` +168, `execmisc.o` −186 bytes. Everything from `gfx.o` on moves by +$2C6, then by +$2C4 from
  `dos_lib.o` on (the alignment word before `dos_lib.o` is gone). Several unchanged name strings now sit at an
  address that is 2 mod 4 instead of 0 mod 4, which flips their class (below).
- **Controls.** Group sizes (21 hunks / 596,048 bytes, 390 / 413,374, 50 / 1,167,084) and every "tiers / commodore /
  aros vs reference" row are identical in the base and head runs. The notable threshold stays **40 words /
  19 instructions / 19 loose instructions** (`tiers` maxima 39 / 18 / 18, plus one). Against the controls, our head
  ROM's longest code match is unchanged: `mots` 10 / 11 / 449 (tiers / commodore / aros, the last being the computed
  CharLoc table), `instr` 6 / 7 / 7, `instr-souple` 8 / 7 / 11.

| stream | metric | base `d22c5d2` | head `17da6ee` |
|---|---|---|---|
| mots | A tokens | 109,965 | 110,320 |
| mots | max (all) / max code/table | 449 / 449 (`topaz9_loc`) | 449 / 449 (`topaz9_loc`) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`) | **19** (same, `$0DF42`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 111 / 9 / 5 | 113 / 10 / 5 |
| instr | A tokens / max (all) / max code/table | 68,720 / 17 / 17 (`km_fr_s42+$0`, `km_us_s42+$0`) | 68,987 / 17 / 17 (same) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| instr | code ≥ 8 / ≥ 16 | 6 / 2 | 6 / 2 |
| instr-souple | max (all) | 23 (`bcpl_rtdata+$8`, low entropy) | 23 (same row, `$2F404`) |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 17 (keymap); 21 / 2 | 17 (keymap); 21 / 2 |
| instr-souple | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| `--seuil 8` list | rows (mots / instr / instr-souple) | 267 / 44 / 91 | 264 / 44 / 92 |
| self-check | relocated fragments found | 12/12 | 12/12 |

- **Notable lists.** `mots` (40): 13 rows in both ROMs, 4 `code/table` (the two keymap string tables and the two
  computed CharLoc tables, unchanged) and 9 classified data. One classified row is replaced: the base's
  `mathffp_inittab` vector-table row (40 words, `table d'adresses`) gives way to `rb_romboot+$6E` (`$0E8B6`,
  **41 words**, 82 bytes, class `texte` when isolated with `--seuil 39`; `texte+table d'adresses` once merged with
  its neighbours). That run covers the last word of `romboot.o`, the whole `mathffp_romtag` (match word, normalised
  self/end pointers, flags, version, type, name/ID/init pointers), `mathffp_name`, the new `mathffp_id` string and
  the first two longwords of `mathffp_inittab` (1 + 13 + 8 + 15 + 4 words). In the base the same RomTag + name run
  stopped at 22 words because no ID string followed the name. The ID string is the `lib_IdString` value of
  `docs/analysis/mathffp-v34.md` §1 (a value any program reads from the library base). The vector-table run that
  follows is now 38 words (base 40): the head's init table has no data-table pointer. `instr` (19): no row.
  `instr-souple` (19): only the classified low-entropy `bcpl_rtdata+$8` (23 tokens), as in the base.
- **`--seuil 8` differences, code rows.**
  - `exec_SendIO+$0` (`$07ED2`, 9 words / 6 instructions / 6 loose), new: the whole 6-instruction SendIO (clear
    `io_Flags`, then call the device's `BeginIO` vector with A6 saved), the sequence the AutoDocs define. In the
    base an extra `ln_Type` store split it (`io_beginio+$6`, 7 words / 5 instructions, `--seuil 4` only); rank 12
    moved that store into the devices.
  - `exec_CloseLibrary+$2A` → `+$34` (14 words / 9 / 9): the same run, 10 bytes later because of the NULL-base
    guard added at the routine's entry.
  - `exec_AvailMem+$1A` → `+$12` (9 loose) and new `exec_AllocMem+$20` (8 loose): the walk of the exec memory
    header list with the `mh_Attributes` subset test, the same idiom in both routines.
  - Gone: `exec_ObtainSemaphore+$28` (9 words) and `+$22` (8 loose), `exec_Procure+$0` (10 words, `texte`).
- **`--seuil 8` differences, data rows** (same symbol and length unless stated): class flips from the 2-mod-4 shift
  of unchanged strings, `timer_romtag+$C` (13, `texte` → `code/table`), `graphics_romtag+$C` (15) and
  `trackdisk_romtag+$C` (16, `texte` → `code/table+texte`; the extra `code ≥ 16` count), `ct_rawbit+$1A` (23,
  `RomTag` → `texte`), `gameport_end+$C` (15, → `texte`); `trackdisk_name+$0` 9 → `+$2` 8 (instr, loose);
  `graphics_name+$0` (8 loose, `texte`) new; the `mathffp.o` tail row before the `diskres` RomTag (`ffp_floor+$48`
  23 → `mf_floor+$62` 21, `RomTag+texte`); `mathffp_initfunc+$A` → `+$26` (9 words, `texte`: the last `rts` of the
  init function and the minimal Open/Close entries); `al_coplist+$84` (8, `RomTag`) gone with the alignment word.
- **Rewritten routines, longest rows of the `--seuil 4` lists** (base → head; code = class `code/table`):

| object | mots: longest code row | instr: longest code row | instr-souple: longest code row | longest row, any class |
|---|---|---|---|---|
| `mathffp.o` | 4 → 5 (`mf_expunge+$6`) | none → none | 5 → 6 (`mf_mul+$2E`) | 23 → 21 words (`mf_floor+$62`, tail + `diskres` RomTag); 7 instr `texte` (name, ID, Open/Close) |
| `ports.o` | 6 (`exec_RemPort+$C`) → 4 (`pm_queue+$4`, `exec_GetMsg+$4`, `exec_ReplyMsg+$E`) | none → none | 4 → 5 (`pm_queue+$46`) | 6 words → 6 words (`exec_RemPort+$4`, `texte`) |
| `memory.o` | 9 → 9 (`mem_owner+$0`) | 7 → 7 (`mem_owner+$0`) | 9 → 9 (`exec_AvailMem+$12`) | as code |
| `semaphores.o` | 10 → 10 (`exec_Vacate+$A`) | 7 → 7 (`exec_Vacate+$A`) | 8 (`exec_ObtainSemaphore+$22`) → 7 (`exec_Vacate+$A`) | 10 words `exec_Procure+$0` → 7 (`texte`) |
| `io.o` | 8 → 9 (`exec_SendIO+$0`) | 6 → 6 | 7 → 7 (`exec_WaitIO+$3E`, `texte+code/table`) | as code |
| `library.o` | 14 → 14 (`exec_CloseLibrary`) | 9 → 9 | 9 → 9 | as code |

  `resident.o`, `libinit.o`, `execmisc.o` and `trackdisk.o` keep their longest rows (`execmisc.o`: 15 words,
  `exec_ExitIntr+$0`, `texte`; `libinit.o`: 20 words, `exec_InitStruct+$AC`, `RomTag`).

**Verdict (head ROM, `17da6ee`): PASS.** No `code/table` match reaches 40 words, 19 instructions or 19 loose
instructions in any stream. The longest code match, data excluded, is still 19 words / 13 instructions
(`exp_cpbinding+$22`), and no new code match exceeds it: the new or moved code rows are at most 14 words /
9 instructions (`exec_CloseLibrary`, unchanged) and 9 words (`exec_SendIO`). The rewritten `mathffp.o`, `ports.o`,
`memory.o` and `semaphores.o` match the reference on at most 10 words / 7 instructions / 9 loose instructions of
code. One classified data row reaches the notable list, `rb_romboot+$6E` (41 words: RomTag, library name, ID
string and init-table head of `mathffp.library`); its ID string comes from `docs/analysis/mathffp-v34.md` §1 and
should be added to "Provenance of the data that matches". Any later source change needs a new run.

## Re-run 2026-11-05 (`0340006..4db512c`, before the push)

Delta (`src/` only): the keyboard feeder runs inside the intuition input task (`src/dos/feeder.s` reworked,
`src/intuition/screens.s` `it_intask`, `intuition.i`, `src/exec/input.s`, `boot.s`); the boot console handler ends
lines with LF, the initial CLI closes its FileHandle, console handler stack 2,048 bytes (`conhandler.s`, `shell.s`,
`boot.s`); low chip RAM `$1000`-`$3500` joins the chip heap and the supervisor stack moves to the top of slow RAM
(`boot.s`, `exec.i`, `interrupts.s`, `memory.s` `add_low_chip`, `tasks.s`). Run by a separate analysis agent on
production ROMs (`make kick-prod`, `romtool info`: `is_kick ok`, checksum ok) built in two worktrees (`0340006`,
`4db512c`), each with the vlink map of the same build.

Commands (repo root; `run.sh` is the full command of "Commands" above, same `tiers` / `commodore` / `aros`
controls, `--base tiers --selftest`):

```
bash run.sh <base|head>.rom <base|head>.map > out-<base|head>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8 > all8-<base|head>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 4 > all4-<base|head>.txt
```

The `--seuil 8` and `--seuil 4` lists were compared by (stream, class, object, symbol+offset, length), absolute
offsets ignored.

- **Layout.** Object size changes: `boot.o` +4, `memory.o` +34, `tasks.o` −4, `screens.o` +46, `conhandler.o` +8,
  `shell.o` +60, `feeder.o` −46 bytes (`interrupts.o` and `input.o` keep their size). The shift grows from +$4
  (`lists.o`) to +$26/+$22/+$24 through exec, +$52 from `menus.o`, +$54 from `dos_lib.o` (the alignment word before
  `dos_lib.o` is back), +$5C, +$98 after `shell.o`, and ends at +$6C after `feeder.o`.
- **Controls.** Group sizes (21 hunks / 596,048 bytes, 390 / 413,374, 50 / 1,167,084) and every "tiers / commodore /
  aros vs reference" row are identical in the base and head runs. The notable threshold stays **40 words /
  19 instructions / 19 loose instructions** (`tiers` maxima 39 / 18 / 18, plus one). Against the controls, our head
  ROM's longest code match is unchanged: `mots` 10 / 11 / 449 (tiers / commodore / aros, the last being the computed
  CharLoc table), `instr` 6 / 7 / 7, `instr-souple` 8 / 7 / 11.

| stream | metric | base `0340006` | head `4db512c` |
|---|---|---|---|
| mots | A tokens | 110,314 | 110,374 |
| mots | max (all) / max code/table | 449 / 449 (`topaz9_loc`) | 449 / 449 (`topaz9_loc`) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`) | **19** (same, `$0DF64`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 113 / 10 / 5 | 111 / 10 / 5 |
| instr | A tokens / max (all) / max code/table | 68,983 / 17 / 17 (`km_us_s42+$0`, `km_fr_s42+$0`) | 68,999 / 17 / 17 (`km_us_s42+$0`) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| instr | code ≥ 8 / ≥ 16 | 6 / 2 | 6 / 2 |
| instr-souple | max (all) | 23 (`bcpl_rtdata+$8`, low entropy) | 23 (same row, `$2F458`) |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 17 (keymap); 21 / 2 | 17 (keymap); 21 / 2 |
| instr-souple | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| `--seuil 8` list | rows (mots / instr / instr-souple) | 264 / 44 / 92 | 263 / 43 / 91 |
| self-check | relocated fragments found | 12/12 | 12/12 |

- **Notable lists.** `mots` (40): the same 13 rows as in the base (4 `code/table`: the two keymap string tables and
  the two computed CharLoc tables; 9 classified data, among them `rb_romboot+$6E`, 41 words, unchanged), offsets
  shifted by the layout. `instr` (19): no row. `instr-souple` (19): only the classified low-entropy
  `bcpl_rtdata+$8` (23 tokens), as in the base. No new data row reaches 40 words, so no provenance row is needed.
- **`--seuil 8` differences, code rows.**
  - `feeder.o`: the base's three 8-word rows `feeder_main+$8`, `+$64`, `+$A4` are gone; one 8-word row
    `fd_init+$8` (`$32F8E`) is new. All four are the same 16 bytes of our code: an exec AllocMem call with
    MEMF_PUBLIC|MEMF_CLEAR followed by the NULL test and its branch (only the branch displacement differs). The
    reworked feeder allocates once instead of three times. Longest `feeder.o` code row: 8 words / 4 instructions /
    5 loose (base 8 / 4 / 6).
  - `screens.o` `it_intask+$B2` → `+$DC` (12 words, 8 instructions and 8 loose, `faible entropie`): the input task's
    dispatch run of short branches and subroutine calls, now followed by the added call into the feeder; the word
    run stays 12 words, its merged span grows from 26 to 38 bytes and its class becomes `code/table+table
    d'adresses`.
  - `boot.o` `coldstart+$314` → `+$338` (8 words): the same 16 bytes, moved by the code added to `coldstart`.
- **`--seuil 8` differences, data rows.** `boot.o` `coldstart+$224` → `+$242` (12 words, `table d'adresses`, values
  relocated); `al_coplist+$84` (8 words, `RomTag`) is back with the alignment word before `dos_lib.o`;
  `ct_rawbit+$1A` (23 words) flips `texte` → `RomTag`; `km_fr_s42+$0` 17 → `km_fr_s42+$2` 16 (instr, loose: keymap
  table, mots row unchanged at 76); `km_us_himap+$C` 9 → `+$10` 8 (instr, loose); `trackdisk_name+$2` 8 →
  `+$0` 9 (instr, loose, `texte`); `gameport_dev_name+$0` (8, instr and loose, `texte`) drops below 8. These are
  2-mod-4 alignment flips of unchanged data.
- **Changed objects, longest rows of the `--seuil 4` lists** (code = class `code/table`; base → head):

| object | mots: longest code row | instr: longest code row | instr-souple: longest code row | longest row, any class |
|---|---|---|---|---|
| `boot.o` | 11 → 11 (`d3c_client+$16`) | 5 → 5 (`coldstart+$68`) | 9 → 9 (`rgt_hl+$4`) | 26 words → 26 (`df0_environ+$0`, `texte`) |
| `feeder.o` | 8 → 8 (`fd_init+$8`) | 4 → 4 | 6 → 5 (`fd_timed+$5A`) | 13 words → 13 (`fd_conname+$1`, `texte`) |
| `screens.o` | 13 → 13 (`sc_palette+$8`) | 5 → 5 | 8 → 8 | 13 words (code) |
| `conhandler.o` | 7 → 7 (`con_closewin+$14`) | 5 → 5 | 7 → 7 | 10 words → 10 (`con_win_emit+$14`, `texte`) |
| `shell.o` | 8 → 8 (`sh_exec_cmd+$3C`) | 5 → 5 | 6 → 6 | 10 words → 10 (`sh_conname+$2`, `texte`) |
| `memory.o` | 9 → 9 (`mem_owner+$0`) | 7 → 7 | 9 → 9 (`exec_AvailMem+$12`) | as code |
| `tasks.o` | 10 → 10 (`exec_SetTaskPri+$12`) | 5 → 5 | 6 → 6 | 12 words → 12 (`exec_AddTask+$2E`, `texte`) |
| `interrupts.o` | 11 → 11 (`schedule_body+$4`) | 5 → 5 | 5 → 5 | 16 → 16 (`exc_table+$0`, low entropy) |

  New `--seuil 4` rows of 6 tokens or more in these objects are shifted or merged data rows of `coldstart`
  (6-7 words, address tables and low entropy), `coldstart+$2CE` (6 words, code: the base's `coldstart+$2AA` row
  moved), `fd_timed+$8C` (7 instructions, `texte`), `fd_service+$6A` (6 words, low entropy),
  `shell_main+$104` (6 words, data) and `it_intask+$136` (6 words, low entropy + code).

**Verdict (head ROM, `4db512c`): PASS.** No `code/table` match reaches 40 words, 19 instructions or 19 loose
instructions in any stream. The longest code match, data excluded, is still 19 words / 13 instructions
(`exp_cpbinding+$22`), and no new code match exceeds it: the new or moved code rows are at most 12 words /
8 instructions (`it_intask`, low entropy) and 8 words (`fd_init+$8`, `coldstart+$338`). The changed `feeder.o`,
`screens.o`, `boot.o`, `conhandler.o`, `shell.o`, `memory.o`, `tasks.o` and `interrupts.o` keep their longest code
rows. No new data row reaches the notable list. Any later source change needs a new run.

## Re-run 2026-11-06 (`8582d3e..b55d177`, before the push)

Delta (`src/` only): line editing in the boot console READ (Backspace, Ctrl-X, Ctrl-\, CSI sequences skipped, a
`con_echo` helper) in `src/dos/conhandler.s` and `conwin.s`; end of file ends the initial CLI (`src/dos/shell.s`);
coldstart clears low RAM up to `$1000` instead of `$800` (`src/exec/boot.s`). Run by a separate analysis agent on
production ROMs (`make kick-prod`, `romtool info`: `is_kick ok`, checksum ok) built in two worktrees (`8582d3e`,
`b55d177`), each with the vlink map of the same build.

Commands (repo root; `run.sh` is the full command of "Commands" above, same `tiers` / `commodore` / `aros`
controls, `--base tiers --selftest`):

```
bash run.sh <base|head>.rom <base|head>.map > out-<base|head>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 8 > all8-<base|head>.txt
python3 -I tests/audit_rom_similarity.py <rom> assets/kick34005.A500 --map <map> --seuil 4 > all4-<base|head>.txt
```

The `--seuil 8` and `--seuil 4` lists were compared by (stream, class, object, symbol+offset, length), absolute
offsets ignored.

- **Layout.** Object size changes: `conhandler.o` +138, `conwin.o` +40, `shell.o` +24 bytes. `boot.o` keeps its
  size (the clear bound is a constant). Everything up to and including `conhandler.o` keeps its address; the shift
  is +$8C at `conwin.o`, +$B4 at `shell.o` and +$CC from `diskvalidator.o` to the end of the image.
- **Controls.** Group sizes (21 hunks / 596,048 bytes, 390 / 413,374, 50 / 1,167,084) and every "tiers / commodore /
  aros vs reference" row are identical in the base and head runs. The notable threshold stays **40 words /
  19 instructions / 19 loose instructions** (`tiers` maxima 39 / 18 / 18, plus one). Against the controls, our head
  ROM's longest code match is unchanged: `mots` 10 / 11 / 449 (tiers / commodore / aros, the last being the computed
  CharLoc table), `instr` 6 / 7 / 7, `instr-souple` 8 / 7 / 11.

| stream | metric | base `8582d3e` | head `b55d177` |
|---|---|---|---|
| mots | A tokens | 110,368 | 110,475 |
| mots | max (all) / max code/table | 449 / 449 (`topaz9_loc`) | 449 / 449 (`topaz9_loc`) |
| mots | max code, data excluded | **19** (`exp_cpbinding+$22`) | **19** (same, `$0DF64`) |
| mots | code ≥ 8 / ≥ 16 / ≥ 32 | 111 / 10 / 5 | 111 / 10 / 5 |
| instr | A tokens / max (all) / max code/table | 68,997 / 17 / 17 (`km_us_s42+$0`) | 69,062 / 17 / 17 (same) |
| instr | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| instr | code ≥ 8 / ≥ 16 | 6 / 2 | 6 / 2 |
| instr-souple | max (all) | 23 (`bcpl_rtdata+$8`, low entropy) | 23 (same row, `$2F458`) |
| instr-souple | max code/table; code ≥ 8 / ≥ 16 | 17 (keymap); 21 / 2 | 17 (keymap); 21 / 2 |
| instr-souple | max code, data excluded | **13** (`exp_cpbinding+$22`) | **13** (same) |
| `--seuil 8` list | rows (mots / instr / instr-souple) | 263 / 43 / 91 | 263 / 43 / 91 |
| self-check | relocated fragments found | 12/12 | 12/12 |

- **Notable lists.** Identical to the base, offsets included (all notable rows sit before `conhandler.o`). `mots`
  (40): 13 rows (4 `code/table`: the two keymap string tables and the two computed CharLoc tables; 9 classified
  data, among them `rb_romboot+$6E`, 41 words). `instr` (19): no row. `instr-souple` (19): only the classified
  low-entropy `bcpl_rtdata+$8` (23 tokens). No new data row reaches 40 words, so no provenance row is needed.
- **`--seuil 8` differences.** None: the two lists contain the same rows by (stream, class, object, symbol+offset,
  length). The only differences are the absolute offsets of the rows in `conwin.o`, `shell.o`, `feeder.o`,
  `diskvalidator.o` and `workbench.o`, moved by the layout shift above. No row of the new `conhandler.o` /
  `conwin.o` / `shell.o` code reaches 8 tokens.
- **Changed objects, longest rows of the `--seuil 4` lists** (code = class `code/table`; base → head):

| object | mots: longest code row | instr: longest code row | instr-souple: longest code row | longest row, any class |
|---|---|---|---|---|
| `boot.o` | 11 → 11 (`d3c_client+$16`) | 5 → 5 (`coldstart+$68`) | 9 → 9 (`rgt_hl+$4`) | 26 words → 26 (`df0_environ+$0`, `texte`) |
| `conhandler.o` | 7 → 7 (`con_openwin+$C2`) | 5 → 5 (`con_openwin+$C2`) | 7 → 7 (`con_closewin+$10`) | 10 words → 10 (`con_win_emit+$14`, `texte`) |
| `conwin.o` | 10 → 10 (`cw_parse+$94`) | 9 → 9 (`cw_parse+$94`) | 9 → 9 (`cw_parse+$94`) | as code (`code/table+texte`) |
| `shell.o` | 8 → 8 (`sh_exec_cmd+$20`) | 5 → 5 (`shell_main+$E`) | 6 → 6 (`shell_main+$E`) | 10 words → 10 (`sh_conname+$2`, `texte`) |

  New `--seuil 4` rows in these objects are at most 6 tokens: code rows `cw_start+$32` (6 words, the base's row,
  class `texte+code/table` → `code/table`), `con_handler+$1B0` (4 words, the base's `+$1AC` moved), `cw_key+$CA`
  (4 words, the base's `+$A2` moved), and two new 4-token loose rows `cw_key+$3E` and `con_echo+$A` (the new
  editing code; `con_echo+$A` also appears as a 5-word `texte` row); data rows `shell_main+$13C` (6 words, low
  entropy, the base's 5-word `shell_main+$126` code row moved and reclassified), `con_handler+$198` (5 words,
  address table, was `+$194`), `con_cdevname+$E` and `cw_start+$AC` (reclassified text), plus a few 4-5 token
  low-entropy rows in `con_handler`, `shell_main` and the unchanged `workbench.o` icon data (`wbm_i*`), and the ROM
  footer row, whose `wb_end+…` label offset moves with the layout.

**Verdict (head ROM, `b55d177`): PASS.** No `code/table` match reaches 40 words, 19 instructions or 19 loose
instructions in any stream. The longest code match, data excluded, is still 19 words / 13 instructions
(`exp_cpbinding+$22`), and no new code match exceeds it: the `--seuil 8` list is unchanged, and the new code rows
of the changed objects are at most 6 words / 4 loose instructions. `conhandler.o`, `conwin.o`, `shell.o` and
`boot.o` keep their longest code rows. No new data row reaches the notable list. Any later source change needs a new
run.

## Provenance of the data that matches

Every match longer than the longest code match (19 words / 13 instructions), and the smaller default-value tables
listed above, is **data**. None was copied out of the ROM image: each value was either computed, written from public
documentation, or taken from an analysis spec that describes a value any program can read back through a public
function. This table states, for each one, where its values come from and how anyone can check them without the ROM.

| symbol (our ROM) | longest match | what it holds | where the values come from | public check |
|---|---|---|---|---|
| `km_us_s42`, `km_fr_s42` (`src/exec/keymapdata.s`) | 76 words | the 16 key strings of a keymap (cursor keys, F1-F10, Help, Tab/Shift-Tab) | generated by `tests/mk_keymaps.py` from the CSI sequences documented for console.device, in the public `struct KeyMap` format | `RawKeyConvert`, or the bytes a console window receives for each key |
| `km_us_himap`, `km_fr_himap` | 40 words | pointer arrays of our own keymap descriptors | our layout; after normalisation only the number of entries is left, fixed by `struct KeyMap` | — |
| `*_inittab`, `dos_rtinit+$42` | up to 218 words | function vector tables | our own routines; after normalisation only the number of functions is left, fixed by the public `.fd` files | the `.fd` files |
| `topaz8_loc`, `topaz9_loc` (`src/graphics/font8x8.s`, since `d006817`) | 281 / 449 words | character locations of the topaz 8 and topaz 9 fonts, codes `$20`-`$FF` plus the default glyph | generated by `tests/mk_font8x8.py`: bit offset = slot × width (8 or 10), one slot per distinct glyph of ours, the slot sharing of `graphics-text-v34.md` §2; the glyph bitmaps are our own and do not match (until `d006817`: `src/graphics/text.s`, a `REPT` loop, 194 words) | `TextFont.tf_CharLoc` of `OpenFont("topaz.font", 8/9)` |
| `gfx_defcolors` (`src/graphics/graphics_lib.s`) | 32 words | the 32 default colours of a new ColorMap | spec `graphics-display-v34.md` §3, where the table is both read by the analysis agent and confirmed by a black-box probe (`tests/gdisp_probe.s`) | `GetColorMap(32)`, then `GetRGB4` on each entry |
| `mn_chk_hi` (`src/intuition/menus.s`) | 20 words | the two `struct Image` descriptors of the menu check mark (position, 15 × 8 size, depth) | the size of the mark seen on screen; the image itself is our own design (a cat paw print) and does not match | the check mark of a `CHECKIT` menu item |
| `pf_defaults` (`src/intuition/prefs.s`) | 14 words | default Preferences | layout of the public `preferences.h`; values from spec `intuition-prefs-v34.md` §4.3, read by the analysis agent and confirmed by a black-box probe (`tests/defprefs_probe.s`, 2026-11-04: every non-themed field is byte-identical on both ROMs); the colours and the pointer are the project's own | `GetDefPrefs` |
| `sc_palette` (`src/intuition/screens.s`) | 13 words | default screen palette | colours 0-3 and the pointer colours are the project's own theme; colours 4-15 repeat the ColorMap defaults above | `GetRGB4` on the Workbench screen |
| `mathffp_romtag`, `mathffp_name`, `mathffp_id` (`src/exec/mathffp.s`, since the rank 15 merge) | 41 words (`rb_romboot+$6E`, class texte) | the RomTag fields, the library name and the ID string "mathffp 34.1 (18 Aug 1987)" | RomTag layout from the public `exec/resident.h`; name and ID string from spec `mathffp-v34.md` §1, the `lib_IdString`/`rt_IdString` that any program reads from the library base | `OpenLibrary("mathffp.library", 0)`, then the base's `lib_IdString` |
| on-screen messages (Workbench title, requesters) | text | strings shown to the user | worded to match the text that 1.3 displays, which programs and users rely on | visible on screen |

Since 2026-11-04 no table rests on a reading of the ROM alone: the probe `tests/defprefs_probe.s` (run through
`tests/defprefs_probe.sh`) dumps the 232 bytes returned by `GetDefPrefs` on both ROMs, and every field outside the
project's theme (pointer image, pointer colours, colours 0-3, pointer offset) is byte-identical. The `pf_defaults`
match is therefore public API output that compatible software can read back.

## Limits: what the measurement proves and does not prove

- **It proves** the absence of binary reuse, even relocated or with renamed registers, of sequences
  of more than 13 instructions (or 20 words) of the **34.5** ROM in our ROM. It also places
  our coincidence level at the level of unrelated programs.
- **A single reference version.** Later Kickstart versions (2.x, 3.x) have different
  code. Reuse from those versions would only be detected here if the code concerned
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
  ranges;
- that the only information about the original ROM is its size, its sha1 fingerprint (public,
  identifying revision 34.5) and aggregate statistics.

The tool `tests/audit_rom_similarity.py` follows the same rule: it only displays statistics and
locations in the **first** ROM. It contains no byte of the reference and no machine-specific
path. The document may be read by the implementation track.
