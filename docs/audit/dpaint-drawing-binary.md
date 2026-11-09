# DPaint drawing and crosshair fixes: binary clean-room audit (2026-11-09)

Verdict: **PASS within the measured scope**, against upstream `71c318c` and candidate `324328c`.
The comparison ran in a separate analysis context. This report contains only aggregate measurements,
our symbols and artifact hashes; no reference ROM bytes, disassembly, routine addresses or artwork.

## Inputs and reproducibility

Base and candidate were independently built as development and production ROMs with the same fixed build
identification, `audit-dpaint-drawing`. All four images are 262,144 bytes and pass `romtool info`
(`is_kick` and `chk_sum`). Production maps came from each build's exact object list and order. The mapped
raw links match their ROM prefixes outside the generated identification field; mkrom supplies identification,
padding and footer/checksum. Both complete production images were measured.

| Artifact | SHA-256 |
|---|---|
| Base production ROM | `2c0479192b7c275fa6a08042c24dcb183de3c7a2b7ae513619ffd864e585b3e5` |
| Candidate production ROM | `2babab1c2a3bd2b412add95c0636d1e53e9553b3d22bae08cacd7378335c294c` |
| Candidate raw implementation link | `906794440195ec614a05b8cc50d0656ab216fd5881cf134c880f1ac87aa53e4d` |

The static reference is the 256 KiB Kickstart 1.3 revision identified by SHA-1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`. No reference-ROM emulation was performed. Capstone enabled
word, exact-instruction and loose-instruction streams.

Both runs reused identical available diagnostic controls: 138 Workbench paths yielding 512 CODE hunks /
472,284 bytes, and four AROS paths yielding 50 hunks / 1,155,856 bytes. All six control-versus-reference
metric rows are identical between the paired runs.

The original unrelated `tiers` binary corpus remains unavailable. Its empirical maxima were not recalibrated;
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

## Measurements and data qualification

| Metric | Base | Candidate |
|---|---:|---:|
| Useful word tokens | 113,762 | 113,798 |
| Useful instruction tokens | 71,153 | 71,180 |
| Raw code/table maximum, words | 449 | 449 |
| Raw code/table maximum, exact instructions | 17 | 17 |
| Raw code/table maximum, loose instructions | 17 | 17 |
| Qualified code maximum, words | **19** | **19** |
| Qualified code maximum, exact instructions | **13** | **13** |
| Qualified code maximum, loose instructions | **13** | **13** |
| Relocated-fragment self-check | 12/12 | 12/12 |

Qualification follows the established generated/public-data exclusions in
[rom-similarity.md](rom-similarity.md) and [graphics-2026-11-05.md](graphics-2026-11-05.md):

- The unchanged generated fixed-width character-location tables `topaz8_loc` and `topaz9_loc` account for
  281- and 449-word matches. Their source and generator are unchanged.
- Unchanged public-format keymap string records beginning at `km_us_s42` and `km_fr_s42` account for 76-word
  matches and the raw 17-instruction peaks caused by linearly decoding data.
- The unchanged default palette `gfx_defcolors` contributes 32 words. Unchanged public-layout Image
  descriptors beginning at `mn_chk_hi` contribute a 20-word data match; these records are distinct from the
  project's authored cat artwork.
- The tool separately classifies address/arithmetic tables, text, low-entropy data, RomTags and ROM header/
  footer data. Its presentation merges overlapping matches, sometimes combining text and code/table classes;
  qualified peaks were therefore also calculated from the underlying unmerged `code/table` matches.

After those data exclusions, the longest code match remains the unchanged `exp_cpbinding` relay:
19 words and 13 instructions. No remaining code match reaches the fixed notable gate, and no new match
exceeds the base's qualified code peak.

## Base-to-candidate delta

Location identities were compared by stream, object, symbol-relative offset, class, length and span, ignoring
absolute layout movement. At threshold eight the base/candidate row counts are 262/263 for words,
41/42 for exact instructions and 89/90 for loose instructions.

There is **no added unclassified code/table row at threshold eight**. The three added rows are a classified
RomTag range at our `al_coplist+$84` and eight-token text rows in `intuition_name` in the two instruction
streams. The RomTag range straddles the end of the unchanged alert object and the following DOS resident
metadata after alignment changes. The DOS resident record itself is identical after address normalization;
the neighboring merged range need not have identical boundaries between layouts.

At threshold four the lists contain 5,657 base rows and 5,660 candidate rows: 48 added and 45 lost location
identities. New unclassified rows within changed objects are at most **6 words / 4 exact instructions /
5 loose instructions**, below both the fixed gates and the existing changed-object peaks. Other new short
rows are text/low-entropy classifications or belong to unchanged source objects. The qualified peaks of the
two edited objects are unchanged:

| Object | Words, base/candidate | Exact instructions, base/candidate | Loose instructions, base/candidate |
|---|---|---|---|
| `draw.o` | 9/9 | 6/6 | 9/9 |
| `screens.o` | 13/13 | 5/5 | 8/8 |

No binary-audit objection was found. Live implementation source hashes still match the audited manifest.
Subsequent documentation or Git-ID changes may alter ROM identification/checksum; source hashes and the raw
implementation link must remain consistent with this snapshot. The unavailable unrelated corpus and the
limits of binary similarity remain material: arbitrary semantic rewriting cannot be ruled out by these
measurements. Source provenance, AROS textual comparison and implementation review are separate checks.
