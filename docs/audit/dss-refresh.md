# DSS channel refresh: clean-room audit (2026-11-09)

Verdict: **PASS within the measured scope** against upstream `71c318c`.
The isolated reference-ROM comparison is recorded in [dss-refresh-binary.md](dss-refresh-binary.md), including
its unavailable unrelated-corpus limitation. This change is independent of the pending DPaint pen fix.

## Scope and provenance

The implementation change is confined to `src/graphics/draw.s`. Real-plane `$C0` bitmap copies whose source
and destination have different byte phases now stream complete middle bytes after computing alignment once.
Masked edge bytes preserve outside pixels; equal address parity permits paired output bytes from longword
source fetches. Mixed-parity rows use byte accesses. Source/destination row-range aliasing retains the original
forward path, and constant planes and other minterms retain their existing paths. Public register preservation,
RastPort state and blitter ownership are unchanged.

The optimization was authored from the project's existing copy engine and profiling DSS on our replacement
ROM. The reference observations in [dss-channel-refresh-v34.md](../analysis/dss-channel-refresh-v34.md) were
produced in a separate analysis context and contain only public call arguments, bitmap fields and behavior.
The implementation context did not read or execute the original ROM. Synthetic test pixels and expected
fingerprints are generated from authored patterns and an independent per-pixel public-operation oracle;
no DSS code, music, proprietary glyphs or screenshot-derived replacement geometry is included.

The manual review checked equal save/restore lists, even stack sizes, all shift phases, edge masks, source
lookahead, odd-address handling, row-alias fallback and the public-call return path. No CPU conditionals or
new target-specific dependencies were added. The native regression is registered under both normal and quick
Graphics groups, not directly under the global test targets. Edited existing files contain no copyright notices
requiring year changes. License wording and public compatibility versions remain unchanged; the dated component
notes in ARCHITECTURE and PLAN were updated.

## Reproducible builds

The implementation was rebased onto `71c318c` before measurement. Base and candidate were built independently
as development and production ROMs using the same fixed identification `audit-dss-refresh`. All four images
are 262,144 bytes and pass `romtool info` (`is_kick` and `chk_sum`). Production maps were relinked from each
build's exact object list; their raw bytes match the ROM prefixes except for mkrom's generated identification
field at offsets 28 through 91.

The audit manifest records the implementation source hash and raw production-link hash. Documentation and
Git-ID changes after the audit can alter identification/checksum; the implementation source and raw link must
remain identical to the audited snapshot.

## AROS source comparison

`draw.s` was compared with the same existing AROS corpus used by the previous audit: 65 comparable assembler
files / 22,757 tokens, 202 unrelated assembler files / 374,229 tokens, 2,439 comparable C files, 1,308 unrelated
C files and 599 ABI whitelist files.

```sh
python3 -I tests/audit_aros_similarity.py <base-or-candidate-changed-src> <aros-corpus> \
  -k 12 20 30 --limit 30 --json <result.json>
```

| Exact comparable-AROS match metric | Base | Candidate |
|---|---:|---:|
| Matched tokens, k=12 | 651 | 651 |
| Longest run, k=12 (tokens) | 18 | 18 |
| Matched tokens, k=20 | 0 | 0 |
| Matched tokens, k=30 | 0 | 0 |

Exact matched-token counts and maxima are also unchanged for both unrelated control groups. The single common
comment shingle and non-ABI identifier counts are unchanged. The only reported passage intersecting changed
lines is a 14-token normalized return/register-save sequence at the boundary with the existing BltBitMap entry:
a normal 68000 Amiga calling-convention idiom. No new notable source similarity was found.

## Behavioral validation

- The fresh upstream base passes all COPYSHIFT pixel/state fingerprints, then fails the native speed gate.
  The candidate passes both correctness and speed checks. Seventy cases execute in both CHIP and non-DMA RAM,
  covering source/destination byte phases, masked edges, guards, plane masks, unequal and odd strides, odd
  addresses, constant planes, safe aliasing and a non-copy minterm.
- On the audited 512 KiB CHIP / 512 KiB slow-RAM configuration, eight large panel copies take 35,630 CHIP
  scanlines before the fix and 6,105 afterward. Slow-RAM results are 35,618 and 6,114. The speed gate requires
  fewer than 8,192 scanlines for each group of eight copies.
- Complete `make test-quick` on the rebased audit candidate passes all ten native tests, including blitter
  pixel/state comparisons and timing gates. All ten serial logs contain zero `FAIL` markers.
- Initial DSS validation found median panel-call intervals of 322.49 ms before and 80.00 ms after the fix.
  The original-ROM behavior report gives approximately 80 ms in the tested song section. This establishes
  display-cadence parity for that section, not copy-routine timing parity: the fixed inclusive call was about
  54.6 ms, while the reference measured about 9.7 ms. Module tempo changes can alter update cadence.
- The user inspected the fixed visible playback and accepted the result. Existing user-visible emulator
  sessions were preserved throughout the audit.
- A fresh boot and replay on the rebased audit candidate verified advancing channel rows and the song's
  changing cadence: 60 panel entries at tempo 6 have a median 120.00 ms interval; the following 60 entries,
  mostly at tempo 4, have a median 80.00 ms interval. The targeted screenshot was inspected after each stage.

The legacy Amiberry pre-push suite is unavailable because its boot/Lemmings disk fixtures are absent and its
session helper assumes Linux tools. Native Copperline checks are reported separately and do not claim that
legacy suite passed. The GNU-stat-based `make verify` target is incompatible with macOS stat; equivalent exact
size and romtool checks were performed directly.

Binary/textual similarity cannot rule out arbitrary semantic rewriting; the clean-room provenance review
remains part of the verdict. No reference ROM or disk image is committed.
