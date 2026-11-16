# Deluxe Paint III zoom audit (2026-11-16)

Verdict: **PASS for measured binary/source similarity**, with the explicit provenance and
unavailable-harness limitations below. This is not a claim that the sealed-track procedure was
followed throughout the investigation.

The audit compares the finalized zoom implementation with base `fc5582c` (`v0.2.64`).
Binary measurements and official-ROM behavior observations were performed by a separate
documentation agent. The report contains only metrics, public ABI behavior and locations in
our code; it contains no original-ROM bytes, instructions, routine addresses or artwork.

## Scope and provenance

The change handles a zero source `BytesPerRow` as a repeated backing row, including requests
whose source Y/height exceed the descriptor's nominal `Rows`. It also routes supported Boolean
bitmap operations through the existing minterm-aware rectangle engines and lowers their small
non-copy DMA threshold. The copy threshold is retained. Destination-zero extensions and new
self-blit semantics are outside the final change.

The authored COPYMIN regression adds repeated-source cases with independently evaluated whole
allocation fingerprints, including guards, plus small and zoom-sized Boolean-combine timing
workloads. Word-aligned native semantics and the replacement's odd-address CPU extension are
distinguished. The test already belongs to the normal and quick graphics component groups.
No CPU conditional or new architecture dependency is introduced. The edited implementation and
test files have no copyright notice requiring an ending-year update, embedded component date,
version or HISTORY section. Project progress metadata is maintained in ARCHITECTURE and PLAN.

There is a procedural exception: before recognizing the stricter dedicated-agent rule, the
implementation context ran official-ROM black-box comparisons. It reports that it did not read
original-ROM instructions or disassembly. Therefore this investigation did **not** follow the
sealed-track procedure throughout. The dedicated documentation agent independently repeated the
essential behavior observations and wrote the reviewed
[behavior specification](../analysis/dpaint3-zoom-stride-v34.md). That repetition does not erase
the earlier exception. The quantitative similarity verdict below is separate from this
provenance limitation and cannot certify procedural compliance or exclude arbitrary semantic reuse.

## Reproducible artifacts

The base was independently rebuilt in a detached `fc5582c` worktree with the native vasm/vlink
toolchain and `KSS_VERSION=v0.2.64`. Its production image is byte-identical to the pre-fix
behavioral reference. Candidate development and production images were frozen after the
implementation was declared final, with build ID `v0.2.64-dirty`.
All four images are 262,144 bytes and pass `romtool info` (`is_kick` and `chk_sum`).

| Artifact | SHA-256 |
|---|---|
| Base production ROM | `538b97e54abb21f258ce5474d3bb26fa59e12eca2c57412556a18c7d97dc7372` |
| Candidate production ROM | `49422314289ae0e43fa9000a3608bd7ff5d2268206ec4d4e1cb44e6e0ffd250c` |
| Base development ROM | `f15e09ad3a446c52c71f2de56be6c767128c180131b2033101ca42fc689057bc` |
| Candidate development ROM | `7abd4f7397e7fdba2c37a6726ba177e1d8284c5ed94a150b2d9e0eb36d7580cf` |
| Candidate production raw link | `997e64f7201b3871c9b0dee3685d786f0c0407159dfbb23da72764acc4db69ea` |
| Candidate development raw link | `9c251dcc6067803ae95d71d59afcc17b2ec84f52b2283d09e190aba3a50c5248` |

Matching maps were independently relinked using each Makefile's actual ordered object list.
The raw links match the build's `kick.bin` byte for byte and each ROM prefix outside the generated
identification field at offsets 28–91. Candidate raw links contain 218,648 production bytes and
220,204 development bytes, each 28 bytes longer than the base. Later commit-derived identification
and checksum changes do not change the implementation snapshot covered here.

Private artifacts, exact maps, command inputs and tool outputs remain beneath
`build/audit/dpaint-zoom/`. Public command forms omit private paths:

```sh
make VASM=<native-vasm> VLINK=<native-vlink> KSS_VERSION=v0.2.64 kick kick-prod
<native-vlink> -b rawbin1 -T src/exec/kick.ld -M<matching.map> -o <relink.bin> <ordered-objects>
romtool info <rom>
python3 -I tests/audit_rom_similarity.py <base-or-candidate.rom> <reference256.rom> \
  --temoin wb13-available <same-workbench-controls> \
  --temoin aros-available <same-aros-controls> --map <matching.map> \
  --base tiers --seuil 8 --selftest
python3 -I tests/audit_rom_similarity.py <base-or-candidate.rom> <reference256.rom> \
  --temoin wb13-available <same-workbench-controls> \
  --temoin aros-available <same-aros-controls> --map <matching.map> \
  --base tiers --seuil 4
python3 -I tests/audit_aros_similarity.py <base-or-candidate-changed-src> <aros-corpus> \
  -k 12 20 30 --limit 100 --json <result.json>
```

The reference is the 256 KiB Kickstart 1.3 revision identified by SHA-1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`. All binary runs use identical available controls:
138 Workbench paths yielding 512 CODE hunks/images and 472,284 bytes, plus four AROS paths
yielding 50 hunks/images and 1,155,856 bytes. The original unrelated `tiers` corpus remains
unavailable. The established gates of **40 words / 19 exact instructions / 19 loose instructions**
are retained without recalibration; these diagnostic controls do not constitute a full historical
`tiers` rerun.

## Binary measurements and changed locations

| Metric | Base production | Candidate production | Base development | Candidate development |
|---|---:|---:|---:|---:|
| Useful word tokens | 108,305 | 108,322 | 109,074 | 109,091 |
| Useful instruction tokens | 68,433 | 68,444 | 68,874 | 68,885 |
| Raw code/table maximum, words | 449 | 449 | 449 | 449 |
| Raw code/table maximum, exact / loose instructions | 17 / 17 | 17 / 17 | 17 / 17 | 17 / 17 |
| Qualified code maximum, words | 19 | 19 | 19 | 19 |
| Qualified code maximum, exact / loose instructions | 13 / 13 | 13 / 13 | 13 / 13 | 13 / 13 |
| Changed object `draw.o`: words / exact / loose maximum | 10 / 6 / 9 | 10 / 6 / 9 | 10 / 6 / 9 | 10 / 6 / 9 |
| Relocated-fragment self-check | 12/12 | 12/12 | 12/12 | 12/12 |

Qualification uses the established unchanged data exclusions from
[rom-similarity.md](rom-similarity.md) and [dpaint-pens-binary.md](dpaint-pens-binary.md): generated
fixed-width character-location tables (281/449 words), public-format keymap string records
(76 words and the raw instruction peaks), default palette data (32 words) and existing checkmark
image descriptors (20 words), together with the tool's text, arithmetic/address-table, low-entropy
and header/footer classifications. No new data exclusion was introduced for this change.
The qualified whole-image maximum remains `exp_cpbinding+$22`, at our production offset
`0x0F254` or development offset `0x0F738`.

At sensitivity four, location rows were compared by stream, object, symbol-relative offset,
classification and match length, ignoring absolute layout movement. The only new qualified
`draw.o` word rows in either build are:

| Our symbol | Words | Our production offset | Our development offset |
|---|---:|---|---|
| `gfx_BltBitMap+$B2` | 5 | `0x17462` | `0x17946` |
| `gfx_BltBitMap+$170` | 4 | `0x17520` | `0x17A04` |
| `gfx_BltBitMap+$1CA` | 4 | `0x1757A` | `0x17A5E` |
| `bb_copy+$76` | 4 | `0x17608` | `0x17AEC` |

There are no new qualified exact- or loose-instruction rows in `draw.o`, even at this sensitivity.
New classified low-entropy rows do not raise its code maxima. No qualified code match reaches
the fixed notable gates or exceeds the base instruction peak. The quantitative binary comparison
therefore passes for both builds, subject to the unavailable unrelated-corpus limitation.

## AROS source comparison

The changed implementation file `src/graphics/draw.s` was compared against the same sparse AROS
commit `4dbf6509f4fea9a48643ec39565f60c9a6acac9a`: 65 comparable assembler files / 22,757 tokens,
202 unrelated assembler files / 374,229 tokens, including 86 third-party Amiga assembler files /
52,214 tokens; 2,439 comparable C files, 1,308 unrelated C files and 599 ABI-whitelist files.

| Comparable-AROS metric | Base | Candidate |
|---|---:|---:|
| Our exact tokens | 33,114 | 33,155 |
| Exact covered tokens / longest, k=12 | 701 / 18 | 701 / 18 |
| Exact covered tokens, k=20 and k=30 | 0 / 0 | 0 / 0 |
| Normalized covered tokens / longest, k=20 | 87 / 24 | 87 / 24 |
| Structural covered tokens / longest, k=20 | 617 / 30 | 617 / 30 |
| Shared comment five-word shingles | 3 | 3 |
| Non-ABI identifiers, comparable / unrelated | 4 / 6 | 4 / 6 |
| Non-whitelisted constants, comparable / unrelated | 1 / 2 | 1 / 2 |

The structural k=12 count grows from 5,605 to 5,617 tokens; the longest run stays 30 and the
k=20/30 counts are unchanged. Reviewed matches at edited boundaries are pre-existing register
save/restore and function-boundary idioms. Exact and normalized passage signatures add no new
listed match. Shared comments remain ordinary graphics descriptions, and no new distinctive
identifier or private constant appears. The source comparison finds no new notable AROS reuse.

Manual provenance review found no original-ROM addresses, instruction transcriptions or extracted
tables in the diff. The new geometry and Boolean fingerprints are authored test inputs.
The analysis page was reviewed for the same forbidden content before implementation consumption.

## Independent native behavior and frame comparison

The separate analysis agent ran the authored zero-source oracle on official Kickstart in Copperline
1.0.1, with 512 KiB CHIP + 512 KiB slow memory and no fast memory. All 48 aligned cases pass with
source stride zero, source `Rows=1`, source Y=1 and a five-row output request, across all sixteen
Boolean high-nibble minterms and masks 0/1/3. `COPYMIN PIXELS OK`, `COPYMIN OK` and `COPYMIN END`
are present, with no FAIL. Its screenshot was inspected. An earlier destination-zero diagnostic
failed and is explicitly excluded from the final native compatibility claim and implementation scope.

The official application was independently replayed from its canvas checkpoint through line
creation, zoom entry and pointer refresh. The freehand replay was then repeated with small held
movements in each pane. Both panes update while held. The finalized candidate's six logical stages
(refreshed hover, left held/released, right held/released and settled) match the independent reference
at native 320-by-256 resolution:

| Region, half-open source coordinates | Pixels per stage | Mismatches, all six stages | Foreground IoU |
|---|---:|---:|---:|
| Normal pane: x `[0,98)`, y `[11,256)` | 24,010 | 0 | 1 |
| Divider: x `[98,104)`, y `[11,256)` | 1,470 | 0 | 1 |
| Enlarged pane: x `[104,296)`, y `[11,256)` | 47,040 | 0 | 1 |

All **435,120 compared RGB pixels** agree. No rescaling or phase selection was applied; palette
colors agree directly. There are no palette confusions, mismatch rows or mismatch columns.
Full frames, the affected pane areas and diagnostic differences were inspected. No residual enlarged
cursor block remains in the finalized captures. Private metrics and zero-difference images remain
under `build/dpaint-zoom/`; screenshots supply verification evidence only.

## Replacement-ROM regressions

The implementation context ran the final seven targeted native regressions: `copymin`,
`copyshift`, `rectpens`, `drawblit`, `rasterfree`, `menupens` and `borderless`. The audit independently
checked their final per-test serial logs: every END marker is present and all seven contain zero
`FAIL` occurrences. Their aggregate command/output record is
`build/dpaint-zoom/final-verification.log`; per-test records are in `build/<test>-results/`.

The expanded COPYMIN executable contains 481 authored cases: the actual base count of 383 plus
96 repeated-source cases and two OR workloads. Of the repeated-source cases, 48 aligned cases
have the independent official-ROM confirmation above; 48 odd-address cases exercise the existing
CPU extension. Running the expanded probe on the unmodified base produces `COPYMIN FAIL` and
`COPYMIN END`. The finalized candidate produces `COPYMIN PIXELS OK`, four `COPYMIN MOTION`
records, `COPYMIN OK` and `COPYMIN END`. The four timing totals are 203, 559, 250 and 202 scanlines,
all below the existing 1,000-scanline four-update gate. The final regression screenshot was inspected.

## Harness availability

The required legacy Amiberry `prepush-check` wrapper is unavailable on this macOS host: its Linux
dependencies (`gdb-multiarch`, `socat`, `Xvfb`, `xwd`, `convert`, `flock`, `ss`) and its boot/Lemmings
fixture aliases are absent. Native macOS Amiberry 8.2.2 being installed does not make that wrapper
usable. The harness was not changed or replaced, and this report does **not** label it passed.
Native Copperline regressions are recorded separately by the implementation context.
