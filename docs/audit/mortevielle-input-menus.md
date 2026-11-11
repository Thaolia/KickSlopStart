# Mortevielle input and menu rendering: audit (2026-11-11)

Verdict: **PASS within the measured scope** for implementation `f906dd9` against
base `4e991f6`. Established binary gates are unchanged. The historical unrelated binary corpus
is unavailable, so the available Workbench/AROS controls are reported without recalibrating those gates.

## Scope and provenance

Mortevielle replaced its VBlank dispatcher with a RAM wrapper. AddIntServer treated a changed code pointer as
an uninitialized chain, discarded the graphics/gameport/timer servers, and ultimately disabled mouse polling
after speech. The fix preserves the active public list header and dispatcher.

Custom menus also used screen colors instead of window colors, truncated proportional titles, and redrew
hovered text in the larger global font. The changes use the window pens and screen font/style, refresh item
bounds, compose complete boxes offscreen, and retain validated plain-text surfaces only during the held-menu
session. Source changes invalidate them; unsupported items use the ordinary renderer; closing or allocation
pressure releases cached storage. Glyph composition, shared scratch space and DMA backing copies reduce latency.

Implementation came from the existing code, public Amiga/68000 structures and interfaces, existing behavioral
notes, profiling, and black-box reference runs. No original-ROM instruction listing or AROS implementation text
was used to author the changes. The audit ran after the implementation commit. Its outputs describe matches
and locations in our code; private ROMs, disks, game binaries, font data and captures are not committed.

The manual review checked shared interrupt-chain lifetime, caller register preservation, bitmap bounds and
masks, CPU fallbacks, cache validation/capacity limits, source-color invalidation, surface ownership, and
allocation-failure eviction/retry. No new CPU conditionals or platform dependencies were introduced. Native
tests stay beneath their normal and quick Exec/Graphics/Intuition groups. Existing edited files have no copyright
ending years to extend; license text and V34 compatibility identifiers remain unchanged, with dated component
notes updated in `docs/PLAN.md`.

## Fresh build and test identity

Committed base and candidate sources were archived into separate temporary directories and built from fresh
object directories in development and production modes with fixed ID `audit-mortevielle`. All four ROMs are
262,144 bytes and pass romtool's `is_kick` and `chk_sum` checks. Production maps use the actual logged object
lists. Raw links match ROM prefixes outside the generated ID at offsets 28–91.

| Artifact | SHA-256 |
|---|---|
| Base production ROM | `c9bcbf91031c2447e34105a612ed03dee44b31b9b8e889337775fdb612b21dff` |
| Candidate production ROM | `e08f2a2fe73c9166370a27464caf57ddb4edf94824854d1694d452358c7b794d` |
| Candidate raw implementation link | `349c92f51409def057b69bb03dcda391f1dadc6fc30aad652dc166a62fa1c57b` |
| `src/exec/interrupts.s` | `eaee71c6b4d3c1d76b94e4844f999222efff66d8212ac54d84e189de4125c765` |
| `src/graphics/draw.s` | `723fbd6e27edbf71518c3cded553319b6b2bf858683f605cce70f1b807bdb567` |
| `src/graphics/layers.s` | `1eb6977770e78febc57222362258af07c2eb15f77aaf26b7df4327b923303379` |
| `src/intuition/intuition.i` | `776f822adc7ed8dfccaba594f43faa95562f22c4e5d78b1ea14b50480e41fe11` |
| `src/intuition/menucache.s` | `6885f2563884330e770e9c57435a104f21b4074c883a01e62dc8408bb13af1e5` |
| `src/intuition/menus.s` | `401259b26bfaafd04c73984c1f1c57bbd9b2cfeb518055cb1b0473f1483e59ed` |
| `src/intuition/screens.s` | `60b01e877760e2cf1801f141908492cf357cb3773b13fc1acb1ebd6a328ff338` |

The audited raw candidate exactly matches the production link that passed **18 native quick checks**. A
Git-derived ID or a documentation-only commit can change the final ROM checksum without changing that link.
Local manifests, exact commands and aggregate outputs are retained under `build/audit/mortevielle/`.

Regression evidence includes:

- IRQCHAIN: the old ROM fails; corrected and official Kickstart 1.3 retain both server callbacks across a RAM
  dispatcher wrapper and removal of one server.
- MENUPENS: colors, proportional glyphs, frame/ghost phases, repeated HIGHIMAGE selection/restoration, twenty
  long items, source-color invalidation and CHIP-storage release pass on the corrected and official ROMs.
  The previous production ROM exceeds the repeated-menu latency bound.
- TEXTCOMPOSE: 2,304 independent pixel-model cases, each in CHIP and non-DMA destination memory, cover widths,
  phases, varied pens/modes, masks, kerning, spacing and odd strike layouts. Baseline KSS passes the pixels but
  exceeds the repeated-line bound; the candidate passes both. The original ROM did not complete this odd-layout
  stress fixture locally, so it is not claimed as an original-ROM parity oracle.
- Expanded bitmap-copy fingerprints exercise five-plane menu backups, masked edges and congruent bit phases.

Full-game comparisons used a production ROM combining this implementation with the still-pending **PR #36**
(bitmap/window fixes) and **PR #37** (speech/task fixes), on the same A500/68000, 512 KiB CHIP + 512 KiB slow
profile. The branch's own uncombined production ROM passed the 18-check native suite. All six menu bars and
popups, plus repeated hover/unhover captures, have zero differing pixels in their registered native regions.
Injected surface and popup-layer allocation failures evict/retry successfully and preserve exact pixels.

Act input-to-idle latency in one deterministic production run changed from 601 to 424 ms on the first visit,
and 560 to 220 ms on returning while RMB remains held. The official ROM measured 198 and 190 ms respectively.
The first-open gap remains. These are emulated-time observations, not a claim of general performance parity.

## AROS source comparison

The seven candidate implementation files were compared against the unchanged sparse AROS corpus at
`4dbf6509f4fea9a48643ec39565f60c9a6acac9a`, with six existing files as the base subset. The comparable assembly
has 22,757 tokens, the unrelated group 374,229, and the Amiga third-party subset 52,214. Public headers and
interfaces use the existing whitelist; no new exclusion was added.

```sh
python3 -I tests/audit_aros_similarity.py <changed-source-snapshot> <aros-corpus> \
  -k 12 20 30 --limit 100 --json <result.json>
```

Exact 20-token coverage against comparable AROS changes from 0.028% to 0.027%; the longest exact passage stays
at 20 tokens, an unchanged stack-cleanup/register-restore epilogue in layers. Exact 30-token coverage remains
zero. The normalized peak remains 33 tokens. New short fingerprints are ordinary register saves/restores and
byte-copy plumbing, with no distinctive new implementation passage. Shared comment shingles stay at 25.
Non-ABI identifier groups change 14→15 comparable and 10→11 unrelated: the added names are the generic local
labels `.db_flags` and `.discard`.

## Original-ROM binary comparison

Both complete production ROMs were compared against Kickstart 1.3, SHA-1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`, in word, exact-instruction and loose-instruction streams. The same
available controls were used: Workbench 512 CODE hunks / 472,284 bytes and AROS 50 hunks/images / 1,155,856 bytes.

```sh
python3 -I tests/audit_rom_similarity.py <image.rom> <reference256.rom> \
  --map <matching.map> --temoin wb13-available <workbench-controls> \
  --temoin aros-available <aros-controls> --base tiers --seuil 8 --selftest
# Repeat at --seuil 4 without --selftest.
```

| Qualified code metric | Base | Candidate | Fixed gate |
|---|---:|---:|---:|
| Global maximum, words | 19 | 19 | 40 |
| Global maximum, exact instructions | 13 | 13 | 19 |
| Global maximum, loose instructions | 13 | 13 | 19 |
| Changed-object maximum, words/exact/loose | 13 / 9 / 9 | 13 / 9 / 9 | — |
| Relocated-fragment positive control | 12/12 | 12/12 | 12/12 |

Qualification retains the established generated/public-data exclusions: fixed-width font-location tables,
keymap string records, default colors and public image descriptors, alongside the tool's text/header/low-entropy
classes. Their declarations are unchanged, and no new exclusion was added. Raw code/table peaks are
449 / 17 / 17 in the base and 449 / 16 / 16 in the candidate because linear decoding also sees data.

No new qualified code match reaches eight tokens. The new 16-instruction raw row is inside the unchanged public
keymap string records; the changed vector-table row follows the existing address-table classification. At the
four-token sensitivity, newly added qualified matches in edited objects peak at seven words or five exact/loose
instructions, below the unchanged global maxima and fixed gates. No source or binary similarity objection remains.

This verdict applies to these corpora and measurements. Lexical/binary comparisons do not exclude arbitrary
semantic rewriting, and one original ROM version cannot represent all historical leaked sources. Provenance,
implementation review and the existing clean-room rules remain part of the audit.
