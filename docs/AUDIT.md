# Clean-room audit — 2026-10-29

*Version française : [AUDIT.fr.md](AUDIT.fr.md).*

This audit answers a GitHub issue asking for evidence behind the README statement that the repository contains no
Commodore code. The concern is legitimate: the code in `src/` was written with an LLM, and LLMs may have memorised
leaked Kickstart sources during training. The clean-room wall (see [CLEANROOM.md](CLEANROOM.md)) controls what is read
*during* the project. It cannot control what a model memorised beforehand. Such reuse can only be measured after the
fact, and that is what this audit does.

Three independent checks were run, each by a separate agent with its own scope. The detailed reports are in French
under [`docs/audit/`](audit/), and the tools are in `tests/` so that anyone can rerun them.

| Check | Question | Tool | Detailed report |
|---|---|---|---|
| 1. Binary similarity | Does our ROM contain code sequences from the original Kickstart 1.3 ROM? | `tests/audit_rom_similarity.py` | [rom-similarity.md](audit/rom-similarity.md) |
| 2. Source similarity | Does `src/` contain code copied from AROS? | `tests/audit_aros_similarity.py` | [aros-similarity.md](audit/aros-similarity.md) |
| 3. Specification review | Do the analysis notes (`docs/analysis/`) leak ROM code, and what ROM *data* ends up in `src/`? | manual review | [specs-review.md](audit/specs-review.md) |

## 1. Binary comparison with the original ROM

**Method.**
- The comparison runs on 16-bit words, decoded instructions, and a loose variant that ignores registers and
  constants.
- Absolute ROM addresses and branch or PC-relative displacements are masked, so that a relocated copy is still found.
- The tool searches for maximal common runs with a suffix automaton and counts shared 4-, 8- and 16-grams.
- The baseline is unrelated 68000 code: game executables and SysInfo extracted from the test disks.
- Two further reference groups are measured separately: Commodore code that is not in the ROM (Workbench 1.3.3
  commands) and AROS.

**Positive control.** Twelve relocated fragments of the original ROM were planted into our ROM, and the tool found all
twelve. The method therefore detects real copying.

**Results** (production ROM):

| Comparison | Longest common code run | Coverage by runs ≥ 8 words |
|---|---|---|
| **our ROM vs original ROM** | **20 words / 13 instructions** | 0.69 % (≥ 16 words: 0.09 %, ≥ 32 words: 0) |
| unrelated games vs original ROM (baseline) | 39 words / 18 instructions | — |
| Commodore Workbench code vs original ROM (related code) | 121 words / 96 instructions | 3.8 % |
| our ROM vs AROS ROM | 12 words / 8 instructions | — |

**What is above the threshold.**
- Function vector tables, whose length is fixed by the public `.fd` files.
- The character location table of a fixed-width 8-pixel font. It is an arithmetic progression, and the AROS ROM
  contains the same table.
- The font bitmaps themselves do **not** match.

**Verdict:** no reuse of Kickstart 1.3 code was found. Our longest code match is shorter than what unrelated games
share with the original ROM.

**Limits.**
- Only one reference version (1.3, 34.5) was available. Most known leaks concern 2.x and 3.x sources, so the
  measurement should be repeated against 2.04 and 3.1 ROMs.
- The comparison is binary, not semantic: it cannot detect a paraphrase or a C-to-assembly translation.

## 2. Comparison with AROS

**Corpus.**
- The local `third_party/aros` copy was too partial, so a sparse clone of the official AROS repository was used
  (commit `4dbf6509`): `arch/m68k-*`, `rom/*`, `workbench/{libs,devs,c,fs,system}` and `compiler/include`.
- Our side is `src/` (75 files, 221,721 tokens). AROS is almost entirely C, so the comparable AROS 68000 assembly only
  amounts to 22,757 tokens.

**Method.**
- **Assembly against assembly:** token fingerprints with winnowing (MOSS-style), at three normalisation levels.
- **Assembly against C:** comments, non-ABI identifiers and "magic" constants.
- **Positive control:** two AROS files transliterated to vasm, with labels renamed and comments replaced, are found
  at 62 to 100 % coverage.

**Results.**

| k-gram size | `src` → comparable AROS | `src` → unrelated Amiga code of similar size |
|---|---|---|
| 20 tokens, exact | 0.06 % | 0.004 % |
| 30 tokens, exact | 0.031 % (2 passages) | 0 % |

Only one passage is notable: `bcpl_call`/`bcpl_ret` in `src/dos/bcpl.s` (8 instructions) is identical to AROS
`BCPL_jsr`/`BCPL_rts`.
- The BCPL ABI fixes this 16-byte entry: multiply must sit at +$10, divide at +$12, and the frame layout is
  -12/-8/-4. AROS itself comments "This MUST be at BCPL_jsr+0x10".
- The multiply and divide routines themselves differ. The source now documents the identity.

On the C side, nothing distinctive is shared. One English sentence quoted as "AutoDoc" in `src/dos/dos_lib.s` also
appears in the AROS autodoc; it was rewritten as a plain French comment.

**Limit:** a C-to-assembly transcription leaves no lexical trace, so only the clean-room discipline addresses it.

## 3. Review of the analysis notes and of ROM-derived data

**Analysis notes (`docs/analysis/`, 50 files).**
- 19 older notes lacked the clean-room review section. They were re-read line by line and 9 were corrected.
- A second pass removed about 194 ROM routine and data addresses that remained in 13 other notes, mostly in
  "landmarks" headers.
- The only remaining ROM addresses are generic: the ROM base and range, the header offsets, and the `$F80000` base
  that software probes.
- All 50 notes now end with a dated clean-room review section.

**ROM-derived data that reaches `src/`.**

| Item | Status |
|---|---|
| Default palette, default Preferences, ~50 user-visible strings (Guru, CLI, requesters, Workbench) | Kept on purpose: observable values needed for compatibility. |
| Keymap | **Not a copy of the layout**: hand-authored by `tests/mk_keymaps.py`, no Alt column and no dead keys. The 16 key strings (cursor keys, F1-F10, Help, Shift-Tab) are the CSI sequences documented for console.device, in the public `struct KeyMap` format. That table matches the ROM over 76 words; it is mandated data (see the 2026-10-30 update in [rom-similarity.md](audit/rom-similarity.md)). |
| Font bitmaps | Hand-drawn; they do not match the ROM (check 1). |
| **Menu check mark** | **Fixed.** The first version, drawn right after reading a note that showed the ROM image, shared 4 of 8 rows with it. It was replaced by an unrelated motif (a cat paw print). |
| **System gadget pictograms** (close, depth, size) | **Open.** They follow the pixel geometry described in `intuition-frame-v34.md` §5.3 and therefore render like the 1.3 originals. Compatibility does not require this; a redesign is proposed. |
| Workbench "Discard" warning strings | **Open.** No source trace in the notes; they were most likely recalled by the model. They are public user-interface text, but their provenance is undocumented. |
| Minor items (reduced copper list, SetPatch-compatible exception handler, RESET word) | Imposed by hardware or by external software; see report §3. |

The notes still contain a few reproduced ROM *data* items that would be better described than copied: the check
mark and Amiga symbol images (`intuition-input-menus-v34.md`), the gadget pictogram geometry
(`intuition-frame-v34.md` §5.3), and two code bytes visible through SetPatch (`setpatch-disk-resource.md`). They are
listed in report §2.

## Conclusion

- No Kickstart code reuse was measured in the binary.
- No AROS code reuse was measured beyond one 8-instruction ABI-dictated sequence.
- The audit did find places where ROM **data** or imagery leaked into the implementation through the analysis notes
  or through the model's memory. One is fixed (the check mark); two are listed as open (gadget pictograms, Discard
  strings).
- The README statement "no Commodore code" holds for code. ROM data that is kept for compatibility (default values,
  user-visible strings) is listed above.

## Reproducing

```sh
# 1. Binary similarity (needs your own Kickstart 1.3 ROM; capstone optional)
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom <kick13.rom> --selftest
# 2. AROS similarity (sparse clone of AROS: see aros-similarity.md, "Commands")
python3 -I tests/audit_aros_similarity.py src <aros-clone>
```

Both tools print only statistics and locations in the first argument (our code), never content from the reference.

Measured on the builds of commit `ec9f9ab` (2026-10-29). The fixes listed above came after the measurement and only
make our data more different from the original.
