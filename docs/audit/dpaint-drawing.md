# DPaint input and crosshair fixes: clean-room audit (2026-11-09)

Verdict: **PASS within the measured scope** against upstream `71c318c`.
The isolated binary comparison is recorded in [dpaint-drawing-binary.md](dpaint-drawing-binary.md), including
its unavailable unrelated-corpus limitation. This PR is independent of the pending pen-color and DSS PRs.

## Scope and provenance

DPaint III polls Window mouse coordinates while drawing without subscribing to MOUSEMOVE. The input task
previously stopped receiving movements in that configuration, freezing those fields between button events.
Movement now wakes coordinate maintenance whenever screens exist; the existing REPORTMOUSE/IDCMP gates still
control message delivery. Native tests verify all four subscription combinations, active/inactive window
coordinates, intact button notifications and suppression of unrequested move messages.

The rectangle tool sets cached per-plane minterms to XOR while leaving its ordinary pen/mode fields at JAM2.
Draw previously regenerated operations from the pens, painting crosshair lines instead of erasing them.
Line-mode DMA and CPU rendering now use the stored minterms, with pattern inversion encoded only once.
Pen-based axis/short-line shortcuts remain eligible only when each active plane's solid operation agrees
with the foreground pen; custom operations use the general engines. This removes the dependency on the
pending RectFill pen implementation while preserving the required drawing behavior.

The fixes were authored from our implementation, public structures, the existing behavior specifications and
DPaint on our replacement ROM. The implementation context did not inspect or run the original ROM for these
fixes. The binary comparison stayed in a separate analysis context. Synthetic test patterns/geometry were
authored independently; no proprietary glyphs, music, executable or screenshot-derived replacement geometry
is included. Screenshots serve only as verification evidence.

The manual review checked even stack sizes, matching register saves/restores, predicate flags, active-plane
selection, truth-table decoding, pattern inversion, alias-free cursor erasure and preservation of documented
cursor/phase state. No CPU conditionals or new target-specific dependencies were introduced. Tests are native
68000/Amiga executables registered beneath normal and quick component groups. Edited existing files contain
no copyright notice requiring a year extension; license wording and public compatibility versions are retained.
Dated component notes in ARCHITECTURE and PLAN were updated.

## Reproducible build snapshot

The standalone implementation snapshot is `324328c`, rebased directly onto `71c318c`. Base and candidate were
built independently as development and production ROMs with the fixed ID `audit-dpaint-drawing`. All four are
262,144 bytes and pass romtool's `is_kick` and `chk_sum` checks. Production maps came from the actual object
lists; their raw bytes match the ROM prefix outside the generated identification field at offsets 28–91.
Source hashes and the raw production-link hash are recorded in the audit manifest. Later documentation/Git-ID
changes may alter identification/checksum; implementation bytes must remain identical to this snapshot.

## AROS source comparison

The two edited implementation files, `draw.s` and `screens.s`, were compared with the existing AROS corpus:
65 comparable assembler files / 22,757 tokens, 202 unrelated assembler files / 374,229 tokens, 2,439 comparable
C files, 1,308 unrelated C files and 599 public-header/function-list files for the ABI whitelist.

```sh
python3 -I tests/audit_aros_similarity.py <base-or-candidate-changed-src> <aros-corpus> \
  -k 12 20 30 --limit 30 --json <result.json>
# Expanded exact-pass listings resolve the short new register-restore idiom:
python3 -I tests/audit_aros_similarity.py <base-or-candidate-changed-src> <aros-corpus> \
  -k 12 --levels exact --limit 400 --json <exact-all.json>
```

| Exact comparable-AROS match metric | Base | Candidate |
|---|---:|---:|
| Matched tokens, k=12 | 1,267 | 1,279 |
| Longest run, k=12 (tokens) | 18 | 18 |
| Matched tokens, k=20 | 0 | 0 |
| Matched tokens, k=30 | 0 | 0 |

The added 12 tokens are one register-restore instruction at the new predicate's return: a normal 68000 stack
idiom, not distinctive AROS logic. Exact matched-token counts/maxima against both unrelated groups are unchanged.
The top normalized/structural passages do not intersect changed lines. Common comment shingles decrease from
15 to 14; non-ABI identifier counts remain 8 comparable / 7 unrelated, and the magic-constant count remains 8.
No new notable source similarity was found.

## Behavioral validation

- Fresh upstream fails both new regressions; the candidate passes both. `MOUSEPOLL` checks a held-button
  rectangle with every REPORTMOUSE/MOUSEMOVE subscription combination and active/inactive window state.
- `LINEPENS` independently rasterizes 33 authored cases in CHIP and non-DMA memory: both axis directions,
  all octants, points, patterns, masks, odd planes, translated layers, two/five planes, custom minterms and
  all eight mode values. Complete-buffer fingerprints include guards; RastPort state is checked separately.
  Drawing the XOR line set twice must restore the initial allocation.
- Complete `make test-quick` on the standalone audit candidate passes all eleven native tests, including
  graphics pixel/state comparisons and timing gates. Every native serial log contains its END marker and
  zero FAIL markers.
- Initial DPaint validation on the integration build confirmed continuous freehand spirals with default
  tools/colors. On the old Draw implementation, a closed rectangle-tool hover path changes the screen bitmap;
  the fixed build restores all five complete plane digests on return to its starting point. The user inspected
  and accepted the freehand fix; the cursor result was inspected in screenshots and made available in a new
  visible session. Existing user sessions were preserved.
- A fresh cold boot of the standalone audited candidate repeated default-resolution freehand drawing and
  rectangle-tool hovering using bounded raw mouse counts, checked against public coordinates. A continuous
  spiral was inspected, and all five complete 10,240-byte bitmap planes have identical digests before and after
  a closed hover path. Both the start and final rectangle screenshots were inspected. The trusted raw-input
  replay rejected every RPC error; a preliminary sprite-servo replay was excluded after a positioning error.

The legacy Amiberry pre-push suite remains unavailable because its boot/Lemmings disk fixtures are absent and
its session helper assumes Linux tools. Native Copperline validation is reported separately and does not imply
that legacy suite passed. The GNU-stat-based `make verify` target is incompatible with macOS stat; equivalent
exact-size and romtool checks were performed directly. Original unrelated binary controls remain unavailable,
as documented in the binary report; the established fixed thresholds were used without recalibration.

Binary/textual similarity cannot rule out arbitrary semantic rewriting. Clean-room provenance and review
remain part of the verdict. No reference ROM, disk image or captured artwork is committed.
