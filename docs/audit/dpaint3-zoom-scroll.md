# Deluxe Paint III narrow-copy performance audit (2026-11-16)

Verdict: **PASS for measured source/binary similarity and targeted native regressions**.
Pan and zoom selection complete substantially sooner, with identical completed canvas pixels.
The candidate remains slower than the official-ROM behavior oracle. The unavailable historical
unrelated corpus and Linux pre-push harness remain explicit limitations.

This is the performance follow-up to `adf8bca` on `fix/dpaint3-zoom`. It inherits the provenance
qualification in [the preceding zoom audit](dpaint3-zoom.md); this follow-up does not erase or
recertify the earlier procedural exception. This audit was performed by a separate documentation
agent, which authored no implementation, test, build-system or probe-script changes. Only metrics
and locations in our own code are reported; no proprietary-ROM bytes, instruction sequences,
routine addresses or extracted data are reproduced.

## Reviewed change

The production diff adds six decision lines in `src/graphics/draw.s`. Ordinary C0 copies retain
the 64-word DMA threshold. A smaller copy can use the existing rectangle engine only when its
DMA row spans at most two words, its height is at least eight rows, and its total is at least
16 words. The existing validation, source/destination limits, alias handling, alignment checks,
phase selection and odd-address CPU fallback are unchanged. No architecture conditional or new
platform dependency is introduced.

COPYMIN grows from 481 to 530 authored cases: 48 phase/shape cases, plus a column case used for
a 40-copy workload. The phase/shape matrix combines eight source/destination phase pairs,
heights 8/16/49 and widths 1/17. The existing per-pixel Boolean oracle fingerprints the complete
allocation, including guards; the native test also checks RastPort state, preserved arguments
and the bitmap plane-count result. The repeated workload checks the same observable pixels and
state after 40 idempotent copies, then enforces a 3,120-PAL-scanline timing limit. Its existing
graphics component registration supplies both normal and quick targets, without attaching a
child test to the global targets. The edited source and test files contain no copyright notice,
embedded component version/date or HISTORY section requiring an update.

## Exact inputs and maps

Private frozen inputs, command arrays, maps, raw relinks and measurement outputs are beneath
`build/audit/dpaint-zoom-scroll/`. Each ROM is 262,144 bytes and independently passes
`romtool info` (`is_kick` and `chk_sum`).

| Image | SHA-256 |
|---|---|
| Base production | `49422314289ae0e43fa9000a3608bd7ff5d2268206ec4d4e1cb44e6e0ffd250c` |
| Candidate production | `0f8cf591508d0c75720f4aafb3fd0e4c07f4fe3306fba34b3604d2113070c240` |
| Base development | `7abd4f7397e7fdba2c37a6726ba177e1d8284c5ed94a150b2d9e0eb36d7580cf` |
| Candidate development | `1913bbc19f2331cb891afdb95d9b2b5e64e24787429d31f02d17ab783ae16dfb` |

The base uses the previously audited finalized `adf8bca` implementation payload, whose frozen
image retains its earlier dirty identification header. Base maps are identical to the exact
maps from that audit, and the raw-link prefixes match the frozen ROMs outside the generated
identification field. The candidate maps were independently reproduced by relinking the actual
ordered build objects: maps and raw outputs match exactly, and the raw prefixes match the ROMs
outside that same field. Later commit identification/checksum changes are outside the payload.

| Raw linked payload | Bytes | SHA-256 |
|---|---:|---|
| Base production | 218,648 | `997e64f7201b3871c9b0dee3685d786f0c0407159dfbb23da72764acc4db69ea` |
| Candidate production | 218,672 | `e2b50cbe5094f67cc53820029866c92b911dfa3bab5cbe656debffc22c045a19` |
| Base development | 220,204 | `9c251dcc6067803ae95d71d59afcc17b2ec84f52b2283d09e190aba3a50c5248` |
| Candidate development | 220,228 | `989d34f1d6a04fd4fb22fd462f82b0400ffcf0d02abe6b15bdaf82884a729d17` |

The final audited `draw.s` SHA-256 is
`5de2b8c1e35d5fccf95d635bfce09618f403e471f12c0c30e8fff0ba0125d92d`.

## Binary similarity

All four images were compared with the same reference and controls as the preceding audit:
138 Workbench paths yielding 512 CODE hunks/images and 472,284 bytes, plus four AROS paths
yielding 50 hunks/images and 1,155,856 bytes. The reference is identified by SHA-1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`. The unrelated historical `tiers` corpus is absent;
the established **40-word / 19-exact-instruction / 19-loose-instruction** gates are retained
without recalibration. Available controls are diagnostic controls, not a full historical rerun.

Each image was run at sensitivity eight with the relocated-fragment self-test, then at
sensitivity four. All four self-tests recover **12/12** fragments. Qualification uses the
preceding audit's unchanged exclusions: generated fixed-width character-location tables,
public-format keymap string records, default palette and existing checkmark descriptors, plus
the tool's text, low-entropy, arithmetic/address-table and header/footer classifications.
Individual code/table matches were qualified before calculating maxima, so a merged output row
containing both classified data and code is not treated as one longer code match.

| Metric | Base production | Candidate production | Base development | Candidate development |
|---|---:|---:|---:|---:|
| Useful word tokens | 108,322 | 108,339 | 109,091 | 109,108 |
| Useful instruction tokens | 68,444 | 68,459 | 68,885 | 68,882 |
| Raw code/table maximum, words | 449 | 449 | 449 | 449 |
| Raw code/table maximum, exact / loose instructions | 17 / 17 | 17 / 17 | 17 / 17 | 17 / 17 |
| Qualified code maximum, words | 19 | 19 | 19 | 19 |
| Qualified code maximum, exact / loose instructions | 13 / 13 | 13 / 13 | 13 / 13 | 13 / 13 |
| `draw.o` qualified maximum, words / exact / loose | 10 / 6 / 9 | 10 / 6 / 9 | 10 / 6 / 9 | 10 / 6 / 9 |

At sensitivity four, comparison by stream, object, symbol-relative offset and match length
finds **no new qualified `draw.o` match** in either build. The qualified whole-image maximum
remains `exp_cpbinding+$22`. No code match reaches a fixed notable gate or raises the base
instruction maximum. The binary similarity gate passes for development and production.

## AROS source comparison

The base `draw.s` was taken directly from `adf8bca`, and both versions were compared against
the same sparse AROS commit `4dbf6509f4fea9a48643ec39565f60c9a6acac9a`, using k=12/20/30,
w=8 and a passage limit of 100. Corpus sizes remain 65 comparable assembler files / 22,757
tokens, 202 unrelated assembler files / 374,229 tokens, 86 third-party Amiga assembler files /
52,214 tokens, 2,439 comparable C files, 1,308 unrelated C files and 599 ABI-whitelist files.

| Comparable-AROS metric | Base | Candidate |
|---|---:|---:|
| Our exact tokens | 33,155 | 33,176 |
| Exact covered tokens / longest, k=12 | 701 / 18 | 701 / 18 |
| Exact covered tokens, k=20 / k=30 | 0 / 0 | 0 / 0 |
| Normalized covered tokens / longest, k=20 | 87 / 24 | 87 / 24 |
| Structural covered tokens / longest, k=12 | 5,617 / 30 | 5,617 / 30 |
| Structural covered tokens / longest, k=20 | 617 / 30 | 617 / 30 |
| Shared comment five-word shingles | 3 | 3 |
| Non-ABI identifiers, comparable / unrelated | 4 / 6 | 4 / 6 |
| Non-whitelisted constants, comparable / unrelated | 1 / 2 | 1 / 2 |

Covered-token counts and longest runs remain unchanged at all tested levels and k values,
including the unrelated baselines. Listed passage signatures add nothing after ignoring our
line-number shifts. No new distinctive identifier, comment quotation or private constant was
found. Manual diff review found no proprietary-ROM address, transcribed sequence or extracted
data. The source comparison passes within the documented limitations of lexical comparison.

## Native pixel, state and timing evidence

The expanded COPYMIN executable reproduces the performance failure on the base: its log has
`COPYMIN PIXELS OK`, a column total of **22,363 scanlines**, then FAIL and END. The candidate
has PIXELS OK, **2,106 scanlines**, OK and END, with zero FAIL occurrences. Thus the failure
reproduced by this follow-up is the timing gate; the pixel/state oracle passes on both versions.
The workload becomes approximately 10.6 times faster and finishes below its 3,120-line gate.
The final native screenshot was inspected alongside the serial evidence.

All six other final targeted logs (`copyshift`, `rectpens`, `drawblit`, `rasterfree`, `menupens`,
`borderless`) contain their END markers and zero FAIL occurrences. The aggregate record is
`build/dpaint-zoom-scroll/verification.log`; final COPYMIN A/B evidence is in that directory's
`native-before` and `native-fixed` subdirectories. Other logs remain under their usual
`build/<test>-results/` directories.

The existing production-ROM application captures use Copperline 1.0.1 with the same A500,
68000, PAL, 512 KiB CHIP + 512 KiB slow and no-fast-memory configuration as the independent
[official behavior oracle](../analysis/dpaint3-zoom-latency-v34.md). Input is a 120 ms RIGHT-key
hold with the pointer at `(200,80)`, or zoom focus selection at `(90,110)`. These are effective
actions; the oracle's separate toolbar-pointer key no-op is excluded from the comparison.

| Action | Base completion bound, ms | Candidate completion bound, ms | Official bound, ms |
|---|---:|---:|---:|
| Active enlarged-pane RIGHT pan | (1840.701, 1860.733] | (480.925, 500.957] | (200.001, 300.638] |
| Zoom focus selection | (2160.002, 2180.000] | (800.012, 820.001] | (300.000, 500.004] |

Bounds are the last incomplete and first completed captures, measured from input in emulated
time, not exact completion instants. Candidate pan improves by approximately 3.7 times and
selection by approximately 2.7 times. Both still exceed the oracle bounds; this audit does not
claim performance parity.

The starting canvases were independently compared with the matching official starting scenes:
all four have zero differing pixels. Full scenes were visually inspected: pan starts in the
established split view with a continuous enlarged diagonal and the pointer in the enlarged pane;
selection starts with the focus rectangle on the unzoomed authored diagonal. The final scenes
show the completed continuous enlarged diagonal, without a residual cursor block.

At six seconds, each before/fixed action was independently compared with its corresponding
official final capture at native 320-by-256 resolution, without registration, scaling or palette
remapping. Each comparison has zero RGB mismatches in all three regions:

| Half-open source region | Pixels per comparison | Mismatches in each of four comparisons |
|---|---:|---:|
| Normal pane `(0,11)`–`(98,256)` | 24,010 | 0 |
| Divider `(98,11)`–`(104,256)` | 1,470 | 0 |
| Enlarged pane `(104,11)`–`(296,256)` | 47,040 | 0 |

All **290,080 compared final RGB pixels** agree. Metrics are retained privately in
`reference-frame-metrics.json` under the audit artifacts. Screenshots are verification evidence
only; none supplied replacement geometry or assets. No reference emulator instance was launched
for this audit, and the user's visible session was left untouched.

## Commands and limitations

Exact command arrays and outputs are retained privately. Public command forms are:

```sh
romtool info <base-or-candidate.rom>
<native-vlink> -b rawbin1 -T src/exec/kick.ld -M<matching.map> -o <raw.bin> <ordered-build-objects>
python3 -I tests/audit_rom_similarity.py <base-or-candidate.rom> <reference256.rom> \
  --temoin wb13-available <same-workbench-controls> \
  --temoin aros-available <same-aros-controls> --map <matching.map> \
  --base tiers --seuil 8 --selftest
python3 -I tests/audit_rom_similarity.py <base-or-candidate.rom> <reference256.rom> \
  --temoin wb13-available <same-workbench-controls> \
  --temoin aros-available <same-aros-controls> --map <matching.map> \
  --base tiers --seuil 4
python3 -I tests/audit_aros_similarity.py <base-or-candidate-changed-src> build/audit/aros \
  -k 12 20 30 --limit 100 --json <result.json>
```

The legacy Amiberry Linux `prepush-check` remains unavailable on this macOS host, including
its Linux dependencies and required boot/Lemmings fixture aliases, as documented in the preceding
audit. It was neither changed nor replaced and is **not recorded as passed**. Native Copperline
checks supply the targeted evidence above. The historical unrelated binary corpus is also absent.
Similarity statistics cannot establish procedural provenance or exclude semantic reuse, and the
application timing evidence covers these two prepared scenes rather than all drawing workloads.
