# DPaint III curve preview: binary clean-room audit (2026-11-10)

Verdict: **PASS within the measured scope**, against upstream `f273bd4` and implementation candidate
`1fbff73`. This comparison ran in a separate analysis context. The report contains aggregate statistics,
our map symbols and artifact hashes only; no reference-ROM bytes, disassembly, routine addresses or artwork.

## Inputs and reproducibility

Base and candidate were independently built as development and production ROMs using the fixed identification
`audit-dpaint-curve`. All four are 262,144 bytes and pass `romtool info` (`is_kick` and `chk_sum`). Production
maps were generated from each build's actual objects in link order. The raw links match their ROM prefixes
outside the generated identification field at offsets 28–91; mkrom supplies identification, padding and footer.
Both complete production ROMs were measured.

| Artifact | SHA-256 |
|---|---|
| Base production ROM | `f5f5d5a2668faad555af314b9278b7b316bbc4020ff4d196da693ef31ddad1f4` |
| Candidate production ROM | `f3f3db3b9388c880eb590da0ecd67c15dadce3512c3bb4a43556cf416a3c42cc` |
| Candidate raw implementation link | `b73f5b7661a4cba1814e77e7cd3543cb10e9fda7982fad833fe61c9fea609ac3` |

The static reference is the 256 KiB Kickstart 1.3 revision with SHA-1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`. No reference-ROM emulation was performed. Capstone enabled
word, exact-instruction and loose-instruction streams.

The paired runs reused identical available diagnostic controls: 138 Workbench paths yielding 512 CODE hunks /
472,284 bytes, and four AROS paths yielding 50 hunks / 1,155,856 bytes. All six control-versus-reference metric
rows are identical between the base and candidate runs.

The historical unrelated `tiers` corpus remains unavailable. Its empirical maxima were not recalibrated;
the established fixed gates of **40 words / 19 exact instructions / 19 loose instructions** were applied.
This is not a full rerun of the historical unrelated-corpus comparison.

Commands, with private paths replaced by placeholders:

```sh
python3 -I tests/audit_rom_similarity.py <base-or-candidate.rom> <reference256.rom> \
  --map <matching.map> --temoin wb13-available <same-workbench-controls> \
  --temoin aros-available <same-aros-controls> --base tiers --seuil 8 --selftest
python3 -I tests/audit_rom_similarity.py <base-or-candidate.rom> <reference256.rom> \
  --map <matching.map> --temoin wb13-available <same-workbench-controls> \
  --temoin aros-available <same-aros-controls> --base tiers --seuil 4
```

## Measurements and public-data qualification

| Metric | Base | Candidate |
|---|---:|---:|
| Useful word tokens | 113,915 | 114,295 |
| Useful instruction tokens | 71,267 | 71,536 |
| Raw code/table maximum, words | 449 | 449 |
| Raw code/table maximum, exact instructions | 17 | 17 |
| Raw code/table maximum, loose instructions | 17 | 17 |
| Qualified code maximum, words | **19** | **19** |
| Qualified code maximum, exact instructions | **13** | **13** |
| Qualified code maximum, loose instructions | **13** | **13** |
| Relocated-fragment self-check | 12/12 | 12/12 |

Qualification follows the established public/generated-data exclusions in
[rom-similarity.md](rom-similarity.md) and [dss-refresh-binary.md](dss-refresh-binary.md):

- Generated fixed-width character-location tables `topaz8_loc` and `topaz9_loc` account for 281- and
  449-word matches. Their source and generator are unchanged.
- Public-format keymap string records beginning at `km_us_s42` and `km_fr_s42` account for 76-word matches
  and the raw 17-instruction peaks caused by linearly decoding data.
- The unchanged default palette `gfx_defcolors` contributes 32 words. Public-layout Image descriptor pairs
  at `mn_chk_hi` and `mn_cat_hi` contribute 20-word data matches. Only descriptors are excluded, not their
  separate authored bitmap payloads. Both source declarations are unchanged.
- The tool separately classifies text, low-entropy data, address/arithmetic tables, RomTags and ROM header/
  footer data. Because presentation merges overlapping classifications, qualified peaks were also checked
  against the underlying unmerged `code/table` matches.

After these exclusions, the longest code match remains the unchanged `exp_cpbinding` relay: 19 words and
13 instructions. No qualified match reaches a fixed notable gate or exceeds its base peak.

## Base-to-candidate delta

Location identities use stream, object, symbol-relative offset, classification, token length and byte span,
so absolute relocation is not treated as a new match. At threshold eight the base/candidate row counts are
262/262 for words, 42/41 for exact instructions and 90/89 for loose instructions. There are **zero added
rows** and two lost rows; no new unclassified code/table match occurs at this threshold.

At threshold four, the reports contain 5,659 base rows and 5,665 candidate rows: 23 added and 17 lost
location identities. Six added unclassified rows occur in `draw.o`, all in the word stream, with a maximum
of **5 words**. They lie in `br_copy`, `gfx_BltBitMapRastPort` and `gfx_BltBitMap`. The longest is at our
`gfx_BltBitMap+$A4`; the others are four-word matches. No added unclassified instruction row occurs at this
threshold. Other added rows are classified data/text/low-entropy ranges. All are below the existing
changed-object peaks and fixed gates.

| Changed object | Words, base/candidate | Exact instructions, base/candidate | Loose instructions, base/candidate |
|---|---|---|---|
| `draw.o` | 9/9 | 6/6 | 9/9 |

No binary-audit objection was found. The live `src/graphics/draw.s` hash matches the audit manifest:
`7a7ae52fd35566ae958f6fd04c6b510aabc75c7651947505c685b9d3021bdd52`. Documentation or Git-ID changes can
alter ROM identification/checksum; implementation source and raw-link hashes must remain consistent with
this snapshot. Binary similarity cannot rule out arbitrary semantic rewriting. Source provenance, AROS
textual comparison and implementation review remain separate checks, and the unavailable unrelated corpus
remains a material scope limit.
