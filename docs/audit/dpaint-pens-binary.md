# DPaint chooser pens: binary clean-room audit (2026-11-09)

Verdict: **PASS** for the measured implementation snapshot against upstream `21ed998`.
The comparison ran in a separate analysis context. This report contains only aggregate measurements,
our symbols and artifact hashes; it contains no reference ROM bytes, disassembly, addresses or artwork.

## Inputs and reproducibility

Base and candidate were independently built as development and production ROMs with the fixed build ID
`audit-dpaint-pens`. All four images are 262,144 bytes and pass `romtool info` (`is_kick` and `chk_sum`).
Production maps came from relinking the same objects, in the build's order. The mapped raw links match
their ROM prefixes outside the build-generated identification field; `mkrom.py` also supplies padding and
the footer/checksum. The audit measured both complete production images.

| Artifact | SHA-256 |
|---|---|
| Base production ROM | `67dbd59b6e530fdfd9eea9fda870f0a60627a37b428d465c0c22b46c420ad155` |
| Candidate production ROM | `859ccb7e5d9c8628df054faf9774f702acd1e61873754106d473eb2994477e30` |
| Candidate raw implementation link | `a50c25ac8d9f53f3b2accb121d6238ae6b344c4ef643157802e22c6a7fe504f5` |

The reference is the 256 KiB Kickstart 1.3 revision identified by SHA-1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`. It was compared statically, without emulation.
Capstone 5.0.7 enabled the word, exact-instruction and loose-instruction streams.

Both runs used the identical existing available control selections: 138 Workbench paths yielding 512 CODE
hunks / 472,284 bytes, and four AROS paths yielding 50 hunks / 1,155,856 bytes. These are diagnostic controls,
not the original unrelated `tiers` corpus. That original corpus remains unavailable here. The established
fixed gates of **40 words / 19 exact instructions / 19 loose instructions** were applied; their empirical
baseline was not recalibrated. This is not a full rerun of the historical `tiers` comparison.

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
| Useful word tokens | 113,391 | 113,415 |
| Useful instruction tokens | 70,909 | 70,914 |
| Raw code/table maximum, words | 449 | 449 |
| Raw code/table maximum, exact instructions | 17 | 17 |
| Raw code/table maximum, loose instructions | 17 | 17 |
| Qualified code maximum, words | **19** | **19** |
| Qualified code maximum, exact instructions | **13** | **13** |
| Qualified code maximum, loose instructions | **13** | **13** |
| Relocated-fragment self-check | 12/12 | 12/12 |

The qualified maxima apply the established data exclusions described in
[rom-similarity.md](rom-similarity.md) and [graphics-2026-11-05.md](graphics-2026-11-05.md):

- Generated fixed-width character-location tables `topaz8_loc` and `topaz9_loc` account for the 281- and
  449-word matches. Their source and generators are unchanged.
- Existing public-format keymap string records `km_us_s42` and `km_fr_s42` account for the 76-word matches
  and the raw 17-instruction maxima produced by linear decoding of data. Their source is unchanged.
- Existing default palette data `gfx_defcolors` contributes 32 words. The unchanged checkmark Image
  descriptors beginning at `mn_chk_hi` contribute a 20-word data match; their source declarations are identical.
- The tool separately classifies address/function tables, arithmetic tables, text, low-entropy regions,
  RomTags and header/footer data. In particular, the loose-stream 23-token maximum at `bcpl_rtdata` is
  classified low-entropy runtime data, not an added code match.

After those exclusions the maximum remains the unchanged `exp_cpbinding` relay: 19 words and 13 instructions.
No code/table match remaining after these data exclusions reaches the fixed notable gate, and no new code match
exceeds the base peak.

## Base-to-candidate delta

Location rows were compared by stream, object, symbol-relative offset, class and length, ignoring absolute
layout movement. At threshold eight the base/candidate row counts are respectively 264/263 for words,
43/42 for exact instructions and 92/91 for loose instructions.

The only new code/table row at that threshold is nine loose instructions at our `rc_start+$20`
(candidate offset `0x11FEC`). It replaces the base's nine-instruction row at `dr_rect+$44`
(base offset `0x11FAC`). The two nine-token loose sequences were independently compared and are identical:
this is the existing rectangle-walking body under its new shared label. Other lost rows concern unchanged
classified metadata/text after layout shifts.

At threshold four, the complete location lists contain 5,657 base rows and 5,656 candidate rows. Eighteen
new rows are attributed to changed objects. Apart from that relocated nine-instruction row, new unclassified
word rows are at most four words; the remaining new rows are short text/low-entropy classifications.
There are no new exact-instruction rows in changed objects. Qualified code maxima within the changed
objects are unchanged:

| Object | Words, base/candidate | Exact instructions, base/candidate | Loose instructions, base/candidate |
|---|---|---|---|
| `draw.o` | 9/9 | 6/6 | 9/9 |
| `gadgets.o` | 5/5 | none/none | 7/7 |
| `menus.o` | 5/5 | none/none | 5/5 |

No binary-audit objection was found. The unavailable unrelated corpus and the limits of binary comparison
remain material: these measurements cannot exclude semantic copying after arbitrary rewriting. Source
provenance, AROS textual comparison and implementation review are separate checks. Subsequent documentation
or Git-ID changes may alter ROM identification/checksum; the implementation source and raw link must remain
consistent with the measured snapshot.
