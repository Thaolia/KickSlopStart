# PR #27 review follow-up: clean-room audit — 2026-11-05

**PASS for the frozen binary/source delta under the fixed historical gate,
with the control-corpus limitation below.** Both relocated-copy self-tests
found 12/12 fragments. Qualified executable peaks remain 19 words /
13 instructions. No new unqualified match exceeds those base peaks or
reaches 40 words / 19 instructions. The nine-file paired AROS comparison
adds no exact passage of 20 or more tokens.

## Frozen inputs and method

| Role | Revision | Production ROM SHA-256 | Linked bytes |
|------|----------|-----------------------|-------------:|
| Upstream base | `6d85d6bc296c0b5e1c6fabee307f3f73603f469e` | `54e28dd788db948720b4adaf3bb672177a809dc7f1c442488df39533bb11d255` | 217,024 |
| Final candidate | `28ece514e34482031c12795fecab825d2e90151c` | `8ed380b97f569b828804131c323e8ca9ada8780a39cc1e48491d68c3155b5cc4` | 221,324 |

Both ROMs are 262,144 bytes, use `KSS_VERSION=audit-pr27-review`, and pass
`romtool info` size, checksum, and `is_kick` checks. ROM/raw-image hashes
were verified against `build/audit/pr27-review/manifest.json`; all nine
selected archived source files were verified byte-for-byte against their
exact Git revisions. Same-build maps, source archives, commands and results
are retained in that ignored directory. The unchanged base results were
reused after hash/source verification when the final candidate was frozen.

The private reference is Kickstart 1.3 revision 34.5, 262,144 bytes, SHA-1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`. Both variants use Capstone
5.0.7 and identical available binary controls: `wb13-available`, 512 CODE
hunks / 472,284 bytes; `aros-available`, 50 hunks/images / 1,155,856 bytes.
All control-versus-reference rows agree between the paired runs.

The historical `tiers` corpus (21 hunks / 596,048 bytes) remains unavailable.
The historical Commodore and AROS binary corpora (390 / 413,374 and
50 / 1,167,084) were not reproduced either. These available controls are
the replacements documented in the [c4a3519 audit](pr-27-upstream-c4a3519.md).
The historical gate is retained explicitly, not recalibrated from them:
40 words / 19 exact or loose instructions. No `tiers` group is supplied;
`--base tiers` excludes related controls from baseline calibration, while
`--seuil 19` fixes the instruction-list threshold. The 40-word gate is
applied separately to word results.

Commands for each variant, with the private reference and control lists
expanded in the saved argument arrays:

```sh
python3 -I tests/audit_rom_similarity.py <variant>/kick.rom <private-reference> \
  --temoin wb13-available <selected-workbench-files> \
  --temoin aros-available <aros.rom.gz> <AROSBootstrap> <C> <Libs> \
  --map <variant>/kick.map --base tiers --seuil 19 --selftest
python3 -I tests/audit_rom_similarity.py <variant>/kick.rom <private-reference> \
  --map <variant>/kick.map --seuil 8
python3 -I tests/audit_aros_similarity.py <variant-changed-src> build/audit/aros \
  -k 12 20 30 --limit 20 --json <variant>-aros.json
```

Exact invocations are `<variant>-binary-command.json`,
`<variant>-threshold8-command.json` and `<variant>-aros-command.json`;
`available-controls.json` retains the complete reused control selection.

## Paired binary results

| Metric against reference | Base | Final candidate |
|--------------------------|-----:|----------------:|
| Useful word / instruction tokens | 107,811 / 67,272 | 109,961 / 68,670 |
| Raw word code/table maximum | 449 | 449 |
| Raw exact / loose code/table maximum | 17 / 17 | 17 / 17 |
| Qualified executable words / exact / loose peak | 19 / 13 / 13 | 19 / 13 / 13 |
| Word code/table counts ≥8 / ≥16 / ≥32 | 109 / 9 / 5 | 111 / 9 / 5 |
| Exact code/table counts ≥8 / ≥16 | 6 / 2 | 6 / 2 |
| Loose code/table counts ≥8 / ≥16 | 20 / 2 | 21 / 2 |
| Threshold-8 rows: words / exact / loose | 264 / 44 / 86 | 266 / 44 / 91 |
| Relocated positive-control fragments found | 12 / 12 | 12 / 12 |

The executable peak remains `exp_cpbinding+0x22`. The raw code/table class
also includes existing data: keymap string tables, 76 words each; computed
`topaz8_loc` / `topaz9_loc` tables, 281 / 449 words; `gfx_defcolors`,
32 words; and `mn_chk_hi`, 20 words. The ≥40-word rows are those unchanged
keymap/character-location tables and classified function/address tables.
Their provenance is recorded in [rom-similarity.md](rom-similarity.md).
The 17-instruction raw peaks are linear decodings of keymap data.

The sole loose row ≥19 in each new `--seuil 19` output is
`bcpl_rtdata+0x8`, 23 tokens, classified low-entropy runtime data. Neither
new binary output nor either threshold-8 list contains an `rf_outline` row.
No historical `rf_outline` exception is applied to these measurements.

Threshold-8 rows were compared by stream, class, object, symbol-relative
offset and length, ignoring absolute layout movement. The candidate's new
or shifted code/table rows are:

| Candidate offset | Symbol | Match | Assessment |
|------------------|--------|-------|------------|
| `0x12F70` | `dr_directdraw+0x150` | 8 words | New short executable overlap |
| `0x234BE` | `ae_update_visible+0x5E` | 8 loose instructions | New short executable overlap |
| `0x11CA4` | `dr_rect+0x44` | 9 loose instructions | Same length as base at `+0x40` |
| `0x14C6C` | `gfx_ReadPixel+0x32` | 8 loose instructions | Same length as base at `+0x2E` |
| `0x21838` | `topaz9_font+0x20` | 10 words | Unchanged TextFont descriptor, text → code/table |

The remaining new rows are classified low entropy or text:
`gfx_AreaEnd+0xFC` (10 words), `ln_boxhits+0x20` (8 loose instructions),
`ln_blit+0x3E` (8), and `dr_directdraw+0x112` / `+0x13C` (10 / 8).
All are below the base's executable peaks and gate. No new threshold-8 row
is attributed to the memory, Gels, layers or screen objects, the modified
FreeRaster path, or `rc_blit`. Full differences are retained in
`threshold8-delta.json`.

## Paired AROS source results

Both selections contain the same nine changed paths: `src/exec/memory.s`;
`src/graphics/{area.s,draw.s,gels.s,graphics.i,graphics_lib.s,layers.s,text.s}`;
and `src/intuition/screens.s`. Selection directories contain only symlinks
to their verified frozen source archives.

The clean AROS checkout is pinned to
`4dbf6509f4fea9a48643ec39565f60c9a6acac9a`: 65 comparable assembly files /
22,757 tokens; 202 unrelated assembly files / 374,229 tokens, including
86 third-party Amiga files / 52,214 tokens; 2,439 comparable and 1,308
unrelated C files; 599 whitelist files.

| Comparable AROS metric | Base | Final candidate |
|------------------------|-----:|----------------:|
| Selected exact source tokens | 75,385 | 82,547 |
| Exact k20 covered tokens / coverage | 20 / 0.027% | 20 / 0.024% |
| Longest exact / normalized / structural passage | 20 / 33 / 35 | 20 / 33 / 35 |
| Exact k30 covered tokens | 0 | 0 |
| Normalized / structural k30 covered tokens | 158 / 439 | 158 / 472 |
| Shared comment word 5-grams | 26 | 26 |
| Non-whitelisted comparable identifier overlaps | 14 | 15 |
| Shared non-whitelisted numeric constants | 5 | 5 |

The exact 20-token match is the existing stack/register return in
`graphics/layers.s` (base lines 1523–1526, candidate 1530–1533). The added
33-token structural passage at `graphics/area.s:1014–1022` is generic
register/stack epilogue and adjacent prologue shape, below the unchanged
35-token structural peak. The additional identifier overlap is the generic
local `.ac_next`. No new distinctive exact passage, shared comment phrase
or private constant was identified.

## Historical correction and limits

The [c4a3519 record](pr-27-upstream-c4a3519.md) now removes its stale
`rf_outline+0x46` qualification. That row exists in the older graphics
run's saved outputs but is absent from both c4a3519 outputs after upstream
`4965827`. It had been carried forward into the report incorrectly; the
actual paired rows establish the correction. The
[older graphics record](graphics-2026-11-05.md) is prominently marked
historical and superseded, preserving its original hashes and measurements.

This verdict concerns the exact frozen inputs above. Functional performance
and raster-lifetime tests are separate implementation-side validation.
Missing historical controls limit baseline reproduction; only Kickstart
34.5 was measured; linear decoding includes data; AROS source comparison
covers nine changed files; and similarity cannot establish derivation
history or exclude semantic paraphrase, translated algorithms or prior
model memorization. The positive controls establish sensitivity to planted
relocated fragments, not every possible derivation.

Original-ROM access remained in this sealed analysis context. This report
contains aggregate statistics and implementation-side symbols/offsets only,
with no original bytes, instruction listings, routine addresses or
reference-side locations. No emulator session was needed or disturbed.
