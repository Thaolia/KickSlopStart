# DPaint III curve-preview restore: clean-room audit (2026-11-10)

Verdict: **PASS within the measured scope** against upstream `f273bd4`. The isolated
[binary audit](dpaint-curve-binary.md) records the binary comparison and its corpus limitations.

## Scope and provenance

After dragging and releasing the curve tool's chord, DPaint III repeatedly restores a five-plane canvas
rectangle through ClipBlit with minterm `$CC`. The replacement implementation only selected its copy
shortcut for `$C0`, sending the equivalent `$CC` operation through its generic Boolean engine. Profiling
on our ROM identified that engine as the dominant cost. Changing only the minterm at the same checkpoint
confirmed the dispatch cause before the implementation changed.

The public bitmap-copy entry points now normalize the unused low minterm nibble: A is one inside the
masked area, so only the high nibble participates in the Boolean operation. BltBitMapRastPort additionally
uses advancing row pointers and register-block copies for sufficiently large disjoint byte-aligned
rectangles. All active planes are validated before writing. Existing clipping, masks, pending-blit
barriers, layer locking and fallback behavior remain in place. Equal odd alignment gets a leading byte;
odd strides or different parity retain byte transfers. No new DMA ownership is introduced.

Implementation was authored from our source, public structures and Boolean semantics, and DPaint running
on our ROM. Original Kickstart observation was isolated in a documentation-only analysis context; its
[behavioral report](../analysis/dpaint-curve-preview-v34.md) contains public arguments, statistics and
ABI observations, with no original instructions or implementation addresses. The implementation context
never inspected or ran the original ROM. Binary comparison used a separate analysis context as required.
No proprietary executable, glyph, music, framebuffer or screenshot-derived replacement geometry is included.

## Reproducible snapshot and manual review

Implementation snapshot `1fbff73` is based directly on `f273bd4`, which includes the earlier chooser-pen,
DSS refresh, polled-mouse and crosshair fixes. Base and candidate were independently built as development
and production ROMs with fixed identification `audit-dpaint-curve`. All four are 262,144 bytes and pass
romtool's `is_kick` and `chk_sum` checks. Each production map was linked from its exact object list;
raw implementation bytes match the ROM outside the generated identification field at offsets 28–91.
Source, ROM and raw-link SHA-256 hashes are retained in the local audit manifest and binary report.
Documentation or Git-ID changes must not change the audited implementation bytes.

Manual review checked bounded geometry, address-addition carry checks, overlap rejection, enabled-plane
validation before the first write, odd/even row parity, block/tail bounds, advancing row modulos, positive
row counters and end-pointer termination. MOVEM save/restore sets match, stack frames are even, and helper
return flags survive register restoration. Public minterm registers and RastPort state remain intact.
No CPU conditionals or new target-specific dependencies were added. Tests are native Amiga/68000 programs
under normal and quick Graphics groups. Existing edited files have no copyright notice requiring a year
extension; licenses and public compatibility versions are unchanged. Dated component notes were updated.

## AROS source comparison

The changed implementation file, `src/graphics/draw.s`, was compared against the same existing AROS corpus:
65 comparable assembler files / 22,757 tokens, 202 unrelated assembler files / 374,229 tokens, 2,439 comparable
C files, 1,308 unrelated C files and 599 public-header/function-list files for the ABI whitelist.

```sh
python3 -I tests/audit_aros_similarity.py <base-or-candidate-changed-src> <aros-corpus> \
  -k 12 20 30 --limit 30 --json <result.json>
python3 -I tests/audit_aros_similarity.py <base-or-candidate-changed-src> <aros-corpus> \
  -k 12 --levels exact --limit 400 --json <exact-all.json>
```

| Exact match metric | Base | Candidate |
|---|---:|---:|
| Comparable AROS matched tokens, k=12 | 663 | 676 |
| Comparable AROS longest run, k=12 | 18 | 18 |
| Unrelated / third-party Amiga matched tokens, k=12 | 629 | 646 |
| Unrelated / third-party Amiga longest run, k=12 | 19 | 19 |
| Matched tokens in any target group, k=20 or k=30 | 0 | 0 |

The added exact matches are the helper's stack-frame release and register restore: 13 tokens against
comparable AROS and 17 against the unrelated groups. These are ordinary 68000 stack idioms, with no new
maximum. Normalized k=20 counts and all k=30 counts/maxima are unchanged. Two new 22-token structural
passages are the word/byte tail-bit tests; the comparable structural maximum remains 30 tokens. Their
simple remainder handling is independently authored, and exact k=20 matches remain zero. The one new
non-ABI identifier match is the generic block-loop label `.bc_blocks`, normalized against an unrelated
C structure field `bc_Blocks`. The sole comment shingle and shared magic constants are unchanged.
No source-audit objection was found.

## Regression and application validation

- `COPYMIN` supplies an independent per-pixel Boolean oracle over authored data. Its 267 cases run through
  BltBitMap, BltBitMapRastPort and ClipBlit in CHIP and non-DMA memory. Coverage includes all 256 minterms,
  clipping, masks, constants, safe leftward aliasing, shifted bits, odd strides/planes, mixed parity and
  multi-block tails. Whole-buffer fingerprints include untouched source/destination areas and guards;
  RastPort state, preserved minterm register and BltBitMap plane count are checked separately.
- The same final executable passes pixel checks on current upstream but fails its restore timing gate.
  Four complete five-plane C0/CC restores take 13,895 / 215,031 PAL scanlines on upstream. The candidate
  takes 4,103 / 4,069 in CHIP and 4,109 / 4,070 in non-DMA memory. Timing includes public WaitBlit and
  excludes buffer generation and pixel checking. Both four-copy totals must stay below 4,800 scanlines,
  and CC must take no more than 125% of C0. Final pixels are checked after both timed workloads.
- Full `make -j3 test-quick` passes all fourteen native targets, including the merged chooser-pen and DSS
  tests. Serial logs contain their END markers and zero FAIL markers. Graphics pixel/state comparisons
  and existing performance gates also pass.
- A fresh cold boot of the audited candidate on A500/68000/OCS, 512 KiB CHIP plus 512 KiB slow RAM, accepted
  the default resolution, selected the curve tool, dragged and released a chord, and moved its control
  point. The initial chord and final curved preview were inspected. The earlier visible build was also
  tested and accepted by the user; existing user windows were preserved.

The historical unrelated binary corpus is unavailable, so the established fixed binary thresholds are
used without recalibration; the isolated report gives the detailed qualification. The legacy Amiberry
pre-push suite cannot run because its boot/Lemmings fixtures are absent and its helper assumes Linux tools.
Native Copperline validation is reported separately and does not imply that legacy suite passed. Exact
size and romtool checks replace the GNU-stat-based `make verify` command on macOS.

Similarity measurements do not establish absence of arbitrary semantic rewriting. Provenance, isolated
analysis and manual review remain part of this verdict. No reference ROM or disk image is committed.
