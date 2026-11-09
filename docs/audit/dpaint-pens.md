# DPaint III chooser pens: clean-room audit (2026-11-09)

Verdict: **PASS within the measured scope** against the branch base `21ed998`.
The isolated binary analysis is recorded in [dpaint-pens-binary.md](dpaint-pens-binary.md), including the
unavailable unrelated binary corpus and the resulting fixed-threshold limitation.

## Scope and provenance

DPaint III supplies custom per-plane RastPort minterms while highlighting its screen-format choices.
RectFill previously regenerated operations from FgPen/BgPen/DrawMode, erasing selected labels. It now snapshots
and uses the stored minterms in both CPU and eligible solid-blitter rendering. Private explicit-pen fills retain
their generated operations. Text clearing, internal gadget/menu ghost rendering and the source-independent
bitmap fast path synchronize their temporary drawing state before calling RectFill.

The implementation was authored from public structures, the existing behavior specifications and debugging
DPaint III on our own ROM. The implementation context did not access or run the official ROM. The binary
comparison was performed in a separate analysis context. All regression pixels, patterns and glyphs are
authored data; no proprietary image, font or executable is included.

The manual review checked register preservation, paired stack saves/restores, even stack sizes, per-plane mask
and minterm indexing, layer/wrapped-coordinate paths, and internal callers that previously changed pen fields
directly. No new target-specific CPU conditionals or dependencies were introduced. This is an Amiga-only ROM;
its regression executables are selected through the native component test groups, including normal and quick
Graphics targets. Edited source files contain no copyright notices requiring an ending-year change. Existing
license wording and public compatibility version numbers are preserved; dated component notes were updated.

## Reproducible build snapshot

Base and candidate source snapshots were built as development and production ROMs with the same fixed build
identification, `audit-dpaint-pens`. All four images are 262,144 bytes and pass `romtool info` (`is_kick` and
`chk_sum`). Production link maps were generated from each build's actual object list. Their raw link bytes
match the ROM prefix outside the generated identification field at offsets 28 through 91.

The audit manifest records hashes of all four edited source files. The implementation source and raw link must
remain identical to this snapshot after committing; Git-generated identification and ROM checksum changes are
expected when building with the final commit name.

## AROS source comparison

The four edited `src/` files were compared against the same existing AROS corpus as the previous audit:
65 comparable assembly files / 22,757 tokens, 202 unrelated assembly files / 374,229 tokens, 2,439 comparable
C files, 1,308 unrelated C files and 599 public-header/function-list files for the ABI whitelist.

```sh
python3 -I tests/audit_aros_similarity.py <base-or-candidate-changed-src> <aros-corpus> \
  -k 12 20 30 --limit 20 --json <result.json>
```

| Exact comparable-AROS match metric | Base | Candidate |
|---|---:|---:|
| Matched tokens, k=12 | 1,176 | 1,176 |
| Longest run, k=12 (tokens) | 18 | 18 |
| Matched tokens, k=20 | 0 | 0 |
| Matched tokens, k=30 | 0 | 0 |

Exact matched-token counts and maxima are also unchanged against both unrelated control groups. The 12 common
comment shingles, four comparable non-ABI identifiers and magic-constant set remain unchanged. The reported
normalized/structural passages intersecting changed lines are field copies, shift/compare branches and stack
restores in the unrelated corpora. They were reviewed; none indicates distinctive source reuse, and none of
the reported comparable-AROS passages intersects a changed line. Token normalization deliberately removes field
names, constants and registers and therefore also matches short independent 68000 idioms.

## Behavioral validation

- The authored `RECTPENS` regression fails on the base ROM and passes on the candidate. It checks independent
  pixel expectations for selective XOR, clear/invert/preserve/set, monochrome/multicolour patterns, plane masks,
  guards and unchanged RastPort state in CHIP and non-DMA RAM. It also checks SetRast and text clearing.
- The extended `MENUFONT` regression passes, checking original font widths plus disabled gadget/menu stipples
  and preserved drawing state. It also fails on the intermediate ROM with unsynchronized ghost minterms.
- The complete `make test-quick` suite passes on the audited candidate: all ten native tests, including blitter
  pixel/state comparisons and timing gates. All ten serial logs contain zero `FAIL` markers.
- Targeted Copperline 1.0.1 A500/OCS tests confirmed readable selected labels, correct selection changes, and
  successful entry into DPaint III's painting screen. The chooser and paint screenshots were inspected.

The legacy Amiberry pre-push suite remains unavailable: its boot and Lemmings disk fixtures are absent, and
its existing session helper assumes Linux tools. The native suite and targeted Copperline evidence above
are separate checks, not a claim that the legacy suite passed. The GNU-stat-based `make verify` target is
also incompatible with macOS stat; equivalent exact-size and romtool checks were performed directly.

Binary and textual similarity checks cannot establish independent origin after arbitrary semantic rewriting;
the clean-room provenance review remains part of this verdict.
