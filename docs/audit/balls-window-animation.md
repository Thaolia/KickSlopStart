# Balls window controls and animation: audit (2026-11-10)

Verdict: **PASS within the measured scope** against base `4e991f6`.
The audited implementation is `05a1474`, including the close-gadget boundary correction
found during this review. The historical unrelated binary corpus remains unavailable; its established fixed
thresholds are used without recalibration.

## Scope and provenance

Fred Fish #1's Balls requests a title and close gadget on a BORDERLESS BACKDROP window. Its animation clears
an old image with a same-position `$20` ClipBlit, then copies a new 40-by-40, five-plane image with `$C0`.
The changes preserve explicitly requested window decorations and input, calculate the top border from the
screen's requested font size, reduce Boolean operations when source and destination are the same pixels,
and use the blitter's B-channel shift for eligible disjoint CHIP-memory RastPort copies.

The implementation was authored from the project's existing code, public structures and hardware register
semantics, existing behavioral specifications, and the demo's locally available source/API usage. Official
Kickstart supplied black-box geometry, pixel, font and timing observations. No original-ROM disassembly or
AROS implementation text was used to author these changes. The automated binary tool outputs aggregate
statistics and locations in our image only; no original instructions or reference locations are published.
The demo, Workbench files, original ROM, disk images and captured frames remain outside the commit.

The standalone test disk initially omitted Workbench's saved Preferences and consequently selected the
larger Topaz 9 default. Copying the reference disk's `devs/system-configuration` selects Topaz 8 on both ROMs;
public Screen, screen-bar and Window font metrics were verified. This was a private fixture correction.
Authored font and gadget artwork differences are not replaced with reference-ROM pixels.

## Finding resolved before approval

The first implementation commit, `cba76e2`, correctly recognized the ten-line close box on button down,
but still compared button-up Y against BorderTop. With Topaz 8, a borderless title has BorderTop 9, so the
last gadget row armed without producing CLOSEWINDOW on release.

A native test of that last row fails at stage 8 on `cba76e2` and passes on official Kickstart 1.3. Commit
`05a1474` uses the ten-line box for both edges of the gesture. The registered regression now repeats plain,
close-only and BACKDROP cases with the default font and explicit Topaz 8, tests middle and last-row clicks,
and requires exactly one CLOSEWINDOW per click. The expanded fixture passes on the corrected ROM and the
original-ROM oracle, and fails on the pre-correction image. No unresolved implementation finding remains.

## Reproducible builds and implementation review

Base and candidate were extracted from their exact commits into separate temporary source directories.
Development and production variants were built from fresh object directories with GNU Make, the installed
vasm/vlink tools and fixed identification `audit-balls`. All four ROMs are 262,144 bytes and pass romtool's
`is_kick` and `chk_sum` checks. Production maps were linked from the actual logged object lists. Raw-link
bytes match their ROM prefixes outside the generated identification field at offsets 28 through 91.
The full native suite used the candidate ROM and raw link with these same hashes.

| Artifact | SHA-256 |
|---|---|
| Base production ROM | `637d15d9fd997c644fbe029bfdd846af79d8efff7bd0f273cbcd8877ee914ec2` |
| Candidate production ROM | `b8b22f00e8a71710c8ff4d1ed9efabf9dd2ce4dfb0f818ad9312eef137b8e697` |
| Candidate raw implementation link | `9467db62690a2a0474f8b465df244583024ba46d0cc681fb6923e14b22171951` |
| Candidate `src/graphics/draw.s` | `228ec64afb87692cbec30bbdbb807235dd44c25b0e7fe13fd5b3512dae974eea` |
| Candidate `src/intuition/screens.s` | `b5c5b1501abcf7835c12b178f950f1705123dd1efee9b32ebb39a1a8a7d110d1` |

The local manifest and raw results are retained under `build/audit/balls/`. Later documentation commits or
Git-generated identification may change the ROM checksum; the implementation source and raw link must match.

Manual review covered clipping and positive dimensions; word/row hardware limits and zero size encodings;
even DMA addresses/strides; the final masked source fetch; CHIP-memory validation; enabled-plane masks;
cross-plane alias rejection before any write; row modulos; nonblocking blitter acquisition and final waits;
paired register/stack saves and preserved condition flags; unchanged public minterm registers and RastPorts;
and borderless decoration, refresh and gadget press/release geometry. Unsupported copies retain CPU paths.
No CPU conditionals or target-specific dependencies were added to generic code. Native tests remain beneath
normal and quick component groups. Existing edited files have no copyright ending years to extend; license
wording and V34 compatibility versions are preserved, and dated component notes were updated.

## AROS source comparison

Both changed assembly files were compared against AROS commit `4dbf6509` using
`tests/audit_aros_similarity.py -k 12 20 30 --limit 100 --json <result.json>`.
The existing corpus contains 65 comparable assembly files / 22,757 tokens, 202 unrelated assembly files /
374,229 tokens, 2,439 comparable C files, 1,308 unrelated C files and 599 public-header/function-list files
for the ABI whitelist. The third-party Amiga subset contains 86 files / 52,214 tokens.

| Exact-match metric | Base | Candidate |
|---|---:|---:|
| Comparable AROS tokens, k=12 | 1306 | 1319 |
| Comparable AROS longest run, k=12 | 18 | 18 |
| Unrelated tokens, k=12 | 1416 | 1433 |
| Unrelated longest run, k=12 | 19 | 19 |
| Matched tokens against any target group, exact k=20 or k=30 | 0 | 0 |

The small k=12 increases are ordinary stack-frame/register-restore idioms in the added drawing helper.
The comparable normalized k=20 token count remains 157; the comparable structural maximum remains 31.
Additional structural matches are generic bounds/CHIP validation and blitter setup shapes. Shared comment
shingles remain 16 and non-ABI identifier groups remain 9 comparable / 7 unrelated. No distinctive new
source or comment reuse was found.

## Binary comparison

The complete production ROMs were measured with Capstone-enabled word, exact-instruction and loose-instruction
streams, both at notable threshold eight with `--selftest` and at threshold four. Both runs reused the same
available controls: Workbench's 512 CODE hunks / 472,284 bytes and AROS's 50 hunks/images / 1,155,856 bytes.
The reference is Kickstart 1.3, SHA-1 `891e9a547772fe0c6c19b610baf8bc4ea7fcb785`.

```sh
python3 -I tests/audit_rom_similarity.py <base-or-candidate.rom> <reference256.rom> \
  --map <matching.map> --temoin wb13-available <workbench-controls> \
  --temoin aros-available <aros-controls> --base tiers --seuil 8 --selftest
# Repeat with --seuil 4, without --selftest.
```

The absent historical `tiers` group is not reconstructed from Workbench/AROS controls. The existing fixed
notable gates remain 40 words / 19 exact instructions / 19 loose instructions. This is a qualified rerun,
not a recalibration of the unrelated-code baseline.

| Metric | Base | Candidate |
|---|---:|---:|
| Qualified code maximum, words | 19 | 19 |
| Qualified code maximum, exact instructions | 13 | 13 |
| Qualified code maximum, loose instructions | 13 | 13 |
| `draw.o` qualified word/exact/loose maxima | 9 / 6 / 9 | 9 / 6 / 9 |
| `screens.o` qualified word/exact/loose maxima | 13 / 5 / 8 | 13 / 5 / 8 |
| Relocated-fragment positive control | 12/12 | 12/12 |

Qualification retains only the established public/generated-data exclusions: fixed-width font location
tables, keymap string records, default colors and public-layout image descriptors, in addition to the tool's
text/header/low-entropy classifications. None of their declarations changed and no new exclusion was added.
Raw code/table peaks remain 449 words / 17 exact instructions / 17 loose instructions because linear streams
also contain these tables. No newly added unclassified code/table row reaches threshold eight. At threshold
four, new unclassified rows are at most five words or four loose instructions, with no new exact-instruction
row. No qualified peak reaches a fixed gate or exceeds its base peak.

## Validation and outcome

`gmake -j3 test-quick` passed all 15 native checks on the audited production image, including all component
pixel/state checks and existing performance gates. The expanded COPYMIN fixture covers 371 authored cases,
all Boolean minterms, same-port reductions, masks, aliases, constant planes, clipping, shifted phases,
odd/non-DMA fallbacks and hardware dimension limits, plus clear/copy and canvas-restore timing gates.
BORDERLESS covers frame geometry/pixels, refresh and both close-hit rows with two font sizes.

The old upstream production ROM passes the authored bitmap pixel checks but fails the new small-copy timing
gate and fails decorated-borderless geometry. Application validation on A500/68000, 512 KiB CHIP plus 512 KiB
slow RAM showed the title/close strip and responsive animation. A matched logical animation state had zero
ball-region pixel mismatches against the original ROM; the subsequent review correction changes only the
release hit box. Existing visible emulator sessions were preserved during this audit.

The source, binary and corrected implementation checks pass within these stated limits. Similarity tools
cannot exclude arbitrary semantic rewriting; the reference-corpus limitation and provenance review remain
part of the verdict. Only implementation, authored tests, documentation and this report are committed.
