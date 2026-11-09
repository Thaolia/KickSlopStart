# DSS channel refresh: binary clean-room audit (2026-11-09)

Verdict: **PASS within the measured scope**, against upstream `71c318c` and candidate `b585902`.
The comparison ran in an isolated analysis context. This report contains only aggregate measurements,
our symbols and artifact hashes; no reference ROM bytes, disassembly, routine addresses or artwork.

## Inputs and reproducibility

Base and candidate source snapshots were independently built as development and production ROMs with the same
fixed identification, `audit-dss-refresh`. All four images are 262,144 bytes and pass `romtool info`
(`is_kick` and `chk_sum`). Production maps were generated from each build's actual object list and order.
Their raw links match the ROM prefixes outside the generated identification field; `mkrom.py` also supplies
padding and the footer/checksum. Both complete production images were measured.

| Artifact | SHA-256 |
|---|---|
| Base production ROM | `315ec5bcf72b6514dcd7c5dcc3db63ea5e53f6fd6cbf632b6eb57decd76932bf` |
| Candidate production ROM | `e3eec8de3920fba16fbf9cee8a5d3ea5af702bd06aef8aac12012af478be689b` |
| Candidate raw implementation link | `44c27c253ab3008660b1f00748886457c720582d2b0202bd0ca5d18177014102` |

The reference is the 256 KiB Kickstart 1.3 revision identified by SHA-1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`. It was compared statically, without emulation.
Capstone enabled all three streams: words, exact instructions and loose instructions.

The paired runs reused exactly the same available diagnostic controls: 138 Workbench paths yielding
512 CODE hunks / 472,284 bytes, and four AROS paths yielding 50 hunks / 1,155,856 bytes. All six control-versus-
reference metric rows are identical between the two runs.

The original unrelated `tiers` binary corpus remains unavailable. Consequently, its empirical maxima were
not recalibrated. The established fixed gates of **40 words / 19 exact instructions / 19 loose instructions**
were applied explicitly. This is not a full rerun of the historical unrelated-corpus comparison.

Commands, with private paths replaced by placeholders:

```sh
python3 -I tests/audit_rom_similarity.py <base-or-candidate.rom> <reference256.rom> \
  --map <matching.map> --temoin wb13-available <same-workbench-controls> \
  --temoin aros-available <same-aros-controls> --base tiers --seuil 8 --selftest
python3 -I tests/audit_rom_similarity.py <base-or-candidate.rom> <reference256.rom> \
  --map <matching.map> --temoin wb13-available <same-workbench-controls> \
  --temoin aros-available <same-aros-controls> --base tiers --seuil 4
```

## Measurements and data qualification

| Metric | Base | Candidate |
|---|---:|---:|
| Useful word tokens | 113,761 | 113,855 |
| Useful instruction tokens | 71,151 | 71,220 |
| Raw code/table maximum, words | 449 | 449 |
| Raw code/table maximum, exact instructions | 17 | 17 |
| Raw code/table maximum, loose instructions | 17 | 17 |
| Qualified code maximum, words | **19** | **19** |
| Qualified code maximum, exact instructions | **13** | **13** |
| Qualified code maximum, loose instructions | **13** | **13** |
| Relocated-fragment self-check | 12/12 | 12/12 |

Qualification applies the established generated/public-data exclusions described in
[rom-similarity.md](rom-similarity.md) and [graphics-2026-11-05.md](graphics-2026-11-05.md):

- Generated fixed-width character-location tables `topaz8_loc` and `topaz9_loc` account for 281- and 449-word
  matches. Their source and generator are unchanged.
- Existing public-format keymap string records beginning at `km_us_s42` and `km_fr_s42` account for 76-word
  matches and the raw 17-instruction peaks produced by linearly decoding data. Their source is unchanged.
- Existing palette `gfx_defcolors` contributes 32 words. Unchanged public-layout Image descriptors beginning
  at `mn_chk_hi` and `mn_cat_hi` contribute 20-word data matches. These records are distinct from their authored
  cat artwork; their source declarations are identical in both snapshots.
- The tool separately classifies address tables, arithmetic tables, text, low-entropy regions, RomTags and
  header/footer data. Its overlapping-match presentation can merge classes: the unchanged `wb_renmsg` text
  and adjacent declaration appear in a mixed 23-word row. Qualified peaks were therefore also computed directly
  from the underlying, unmerged `code/table` matches, rather than treating that mixed row as a code sequence.

After these data exclusions, the longest code match remains the unchanged `exp_cpbinding` relay:
19 words and 13 instructions. No remaining code match reaches a fixed notable gate or exceeds the base peak.

## Base-to-candidate delta

Location rows were compared by stream, object, symbol-relative offset, class and length, ignoring absolute
layout movement. At threshold eight, base/candidate row counts are 262/262 for words, 41/42 for exact
instructions and 89/90 for loose instructions.

There is **no new code row in the changed object `draw.o` at threshold eight**. The only added word
`code/table` row is the unchanged 20-word Image descriptor range at our `mn_cat_hi+$0`: the corresponding
base range was classified as text. Its normalized words are identical between snapshots, and its source is
unchanged. The other two added rows are eight-token text classifications in `intuition_name`, also unchanged.

At threshold four, both lists contain 5,657 location rows, with 13 added and 13 lost location identities.
Only two added rows belong to `draw.o`: four words classified as text at `gfx_ReadPixel+$A2`, and four loose
instructions classified as low entropy at `dr_bits+$C2`. No added unclassified code row belongs to `draw.o`.
Its qualified peaks are unchanged: **9 words / 6 exact instructions / 9 loose instructions**.

No binary-audit objection was found. The live implementation source hash still matches the audited manifest.
Subsequent documentation or Git-identification changes may alter the ROM ID/checksum; the implementation source
and raw link must remain consistent with the measured snapshot. Binary similarity cannot exclude semantic
copying after arbitrary rewriting; provenance, AROS textual comparison and implementation review remain
separate checks.
