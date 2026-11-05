# PR #27: audit after upstream c4a3519 — 2026-11-05

**PASS for this binary/source delta under the fixed historical gate, with
the control-corpus limitation below.** Both relocated-copy self-tests found
12/12 fragments. Qualified code peaks remain 19 words / 13 instructions in
both new builds. No new unqualified code match exceeds the new base peak or
reaches the 40-word / 19-instruction gate. The paired AROS audit adds no exact
passage of 20 or more tokens.

This is a fresh audit of the final rebased candidate, including the
rectangle-mode and scrolling conflict resolution and the AreaEnd inverted-mode
mapping correction. The earlier
[graphics audit](graphics-2026-11-05.md) remains historical and was not
automatically applied to these changed binaries.

The later review fixes and rebase onto `6d85d6b` are measured separately in
the [PR #27 review follow-up](pr-27-review-followup.md); the frozen inputs
below remain the inputs of this historical run.

## Frozen inputs

| Role | Revision | Production ROM SHA-256 | Linked bytes |
|------|----------|-----------------------|-------------:|
| New upstream base | `c4a35194d43a504fa9f3e917c878ad3080e10a37` | `1ea3af038605d2a2dcc50993684903de5a3da2a1dcb49fde9a394544e7d7da64` | 216,844 |
| Final rebased candidate | `8abf7c3059bbc5042184dcde01cc3c6585ccd600` | `bbe43047cd9ae028e3e89a24c5b709e0000946b1fbf73723c374a7171fddeb3d` | 221,100 |

The rebased component commits are graphics `4b31076` and memory `31c08b6`,
followed by AreaEnd correction `8abf7c3`; `7c207b3` carries preceding audit
documentation. The earlier candidate's outputs are preserved separately and
are not the final verdict. Both ROMs are 262,144
bytes, built with the shared identifier `audit-upstream-c4a3519`. The manifest,
ROMs, raw images, same-build maps, and exact Git source archives are under
`build/audit/upstream-c4a3519/`. This analysis verified ROM and raw-image
hashes against the manifest and every selected source file against its Git
revision. Both ROMs pass `romtool info` size, checksum, and `is_kick` checks.

The private canonical reference is unchanged: Kickstart 1.3 revision 34.5,
262,144 bytes, SHA-1 `891e9a547772fe0c6c19b610baf8bc4ea7fcb785`. No
original bytes, instructions, routine addresses, or reference-side match
locations appear in this report.

## Controls and reproduction

Both builds use the same available controls and Capstone 5.0.7:

| Group measured now | Hunks/images | CODE/image bytes |
|--------------------|-------------:|-----------------:|
| `wb13-available` | 512 | 472,284 |
| `aros-available` | 50 | 1,155,856 |

The historical unrelated `tiers` group, 21 hunks / 596,048 bytes, remains
unavailable. The exact historical Commodore and AROS binary controls were
also not reproduced: their recorded sizes were 390 / 413,374 and
50 / 1,167,084. Historical baseline statistics are not presented as rerun.
The available group selection is documented in the preceding audit; its
complete paths and counts are copied into this run's `available-controls.json`.
The control-versus-reference rows agree between the two new runs.

For each variant, the existing tools were run as follows; complete argument
arrays are retained as `<variant>-binary-command.json`,
`<variant>-threshold8-command.json`, and `<variant>-aros-command.json` in the
ignored audit directory:

```sh
python3 -I tests/audit_rom_similarity.py <variant>/kick.rom <canonical-reference> \
  --temoin wb13-available <selected-workbench-files> \
  --temoin aros-available <aros.rom.gz> <AROSBootstrap> <C> <Libs> \
  --map <variant>/kick.map --base tiers --seuil 19 --selftest
python3 -I tests/audit_rom_similarity.py <variant>/kick.rom <canonical-reference> \
  --map <variant>/kick.map --seuil 8
python3 -I tests/audit_aros_similarity.py <variant-changed-src> build/audit/aros \
  -k 12 20 30 --limit 20 --json <variant>-aros.json
```

No `tiers` group is supplied. `--base tiers` excludes the related available
controls from baseline calibration; explicit `--seuil 19` fixes the
instruction-list threshold. The historical word gate of 40 is applied to
word results separately. This gate is retained, not recalibrated from the
replacement controls.

## Binary comparison with the new base

| Against original reference | New base | Rebased candidate |
|----------------------------|---------:|------------------:|
| Useful word tokens | 107,723 | 109,851 |
| Raw word code/table maximum | 449 | 449 |
| Qualified code peak, words | 19 | 19 |
| Useful instruction tokens | 67,235 | 68,599 |
| Raw exact/loose instruction code/table maximum | 17 / 17 | 16 / 16 |
| Qualified exact/loose code peak, instructions | 13 / 13 | 13 / 13 |
| Word code/table counts at least 8 / 16 / 32 | 112 / 9 / 5 | 114 / 10 / 5 |
| Exact code/table counts at least 8 / 16 | 6 / 2 | 6 / 2 |
| Loose code/table counts at least 8 / 16 | 20 / 2 | 21 / 2 |
| Relocated positive-control fragments found | 12 / 12 | 12 / 12 |

The qualified executable peak remains the unchanged `exp_cpbinding` relay.
The tool's code/table class also contains known data. Matches at or above
40 words are unchanged qualified keymap string tables, 76 words each;
computed `topaz8_loc` / `topaz9_loc` character-location tables, 281 / 449;
and classified function/address tables. The 32-word `gfx_defcolors` values
and 20-word `mn_chk_hi` descriptors are existing data below that word gate.
Their provenance is recorded in [rom-similarity.md](rom-similarity.md).

The only loose match at or above 19 in the paired `--seuil 19` outputs is
`bcpl_rtdata+0x8`, 23 tokens of runtime data, classified low entropy in both
builds. Qualified code peaks exclude that data range. Neither these outputs
nor the paired threshold-8 lists contain an `rf_outline` row. No new
unqualified instruction match reaches 19.

Documentation correction after PR #27 review: the previous wording also
listed `rf_outline+0x46` at 20 loose tokens. That row belongs to the earlier
[graphics audit](graphics-2026-11-05.md), where it is present in both saved
`--seuil 19` outputs. Carrying that qualification into this record was an
error: upstream `4965827`, included in this base, removed the overlap. The
correction follows this run's saved base/candidate binary and threshold-8
rows; its original inputs, measurements, and verdict are unchanged. The
threshold-8 lists locate the same 23-token runtime-data overlap at
`bcpl_rtdata+0x4`; the different threshold merges/selects its starting point.

The threshold-8 lists contain 264 / 43 / 85 rows for the new base and
267 / 44 / 91 for the candidate, for words / exact / loose streams. Comparing
stream, class, object, symbol-relative location, and length removes absolute
layout shifts. Candidate-side code/table differences are:

| Candidate offset | Candidate symbol | Match | Qualification |
|------------------|------------------|-------|---------------|
| `0x12EAC` | `dr_directdraw+0x150` | 8 words | New short overlap, below base peak and gate |
| `0x233E0` | `ae_update_visible+0x5E` | 8 loose instructions | New short structural overlap, below base peak and gate |
| `0x11BF4` | `dr_rect+0x44` | 9 loose instructions | Same length as base overlap at symbol offset `0x40` |
| `0x14BA8` | `gfx_ReadPixel+0x32` | 8 loose instructions | Same length as base overlap at symbol offset `0x2E` |

Other new graphics rows are classified text or low entropy and have lengths
of 8–10 tokens: `gfx_AreaEnd+0xFC`, `ln_boxhits+0x20`, `ln_blit+0x3E`,
and `dr_directdraw+0x112` / `+0x13C`. No threshold-8 row is attributed to
`rc_blit` in either build. No new threshold-8 row is attributed to the
changed memory, Gels, or layers objects.

Remaining differences are data/classification effects: `mn_chk_hi` changes
from text to code/table at the same 20-word length; the unchanged French
keymap string table changes linear segmentation from 17 to 16 instruction
tokens; short rows on public library-name strings appear or disappear; and
an eight-word row at unchanged `al_coplist+0x84` is classified as RomTag.
These do not constitute new executable peaks or require escalation above
the new base's 13-instruction / 19-word code peak.

## Paired AROS source comparison

Both source archives were compared on the same seven changed paths:
`exec/memory.s`, `graphics/area.s`, `draw.s`, `gels.s`, `graphics.i`,
`graphics_lib.s`, and `layers.s`. Selection directories contain only
symlinks to those frozen archive files; no implementation was edited here.

The clean pinned AROS checkout remains
`4dbf6509f4fea9a48643ec39565f60c9a6acac9a`, with the documented sparse
corpus: 65 comparable assembly files / 22,757 tokens, 202 unrelated assembly
files / 374,229 tokens, including 86 third-party Amiga files / 52,214 tokens;
2,439 comparable and 1,308 unrelated C files; and 599 whitelist files.

| Comparable AROS metric | New base | Rebased candidate |
|------------------------|---------:|------------------:|
| Selected exact source tokens | 54,237 | 61,315 |
| Exact k20 covered tokens / coverage | 20 / 0.037% | 20 / 0.033% |
| Longest exact passage | 20 | 20 |
| Exact k30 covered tokens | 0 | 0 |
| Longest normalized / structural passage | 33 / 35 | 33 / 35 |
| Normalized k30 covered tokens | 158 | 158 |
| Structural k30 covered tokens | 378 | 411 |
| Shared comment word 5-grams | 16 | 16 |
| Comparable non-whitelisted identifier overlaps | 10 | 11 |
| Shared non-whitelisted numeric constants | 3 | 3 |

The exact 20-token passage is an existing register-convention
epilogue/prologue in `layers.s`; no new exact passage at that length appears.
The additional 33-token structural passage in `graphics/area.s:1014-1022`
matches generic stack/register epilogue/prologue shape in AROS
`arch/m68k-all/exec/cachecontrol_.S:146-151`, below the existing structural
peak. The one new identifier collision is the generic local `.ac_next`
against `acnext`; shared comment phrases and numeric constants do not
increase. No new distinctive exact AROS passage or private constant was
identified.

## Provenance, limits, and clean-room review

The reported implementation inputs remain the project's own code, public
hardware/ABI documentation, upstream corrections, and the sanitized Clock
behavior report. Original-ROM access stayed in the sealed analysis context.
Black-box behavior analysis intentionally occurred; this audit distinguishes
that permitted work from copied ROM implementation code.

The implementation track separately reports the exact final candidate passed
all 156 upstream raster vectors, the Exec memory regression, and all five
native graphics speed gates with pixel/state/guard checks, including the
eight-mode AreaEnd-versus-RectFill regression. Functional checks do not
establish code provenance and are separate from this similarity verdict.

The verdict applies only to the new revisions and hashes above. Missing
historical binary controls limit baseline reproduction. Only Kickstart 34.5
was measured; linear decoding includes data; source comparison covers seven
changed files rather than all project source; and binary/text similarity
cannot prove derivation history or exclude semantic paraphrase, translated
algorithms, or prior model memorization. The positive control establishes
sensitivity to relocated fragments, not every possible derivation.

This report contains only aggregate reference statistics, implementation-side
symbols/offsets, and findings. No original-ROM bytes, instruction listings,
routine addresses, raw logs, or reference-side offsets are reproduced. The
old audit report was not edited, and no emulator session was disturbed.
