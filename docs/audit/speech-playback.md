# Speech playback and completion: audit (2026-11-10)

Verdict: **PASS within the measured scope** for implementation `7a416aa` against
base `4e991f6`. The historical unrelated binary corpus remains unavailable; the established
fixed thresholds are retained without recalibration.

## Scope and provenance

Fred Fish #1's Speech uses translator.library and the disk-loaded narrator.device. Two Exec behaviors
prevented it from completing normally:

- AddTask built the initial frame from tc_SPUpper, overwriting the device argument narrator.device had
  placed below that boundary. It now uses the caller's tc_SPReg. Zero retains the existing fallback for
  internal callers that provide only stack bounds.
- The Initial CLI ran at priority 2 instead of the original ROM's priority 0. Restoring priority zero
  permits the ordinary equal-priority worker handoffs needed between the sample's speech requests.

The implementation was authored from the existing code, public task/process layouts, the existing behavioral
specification, and runtime observations of caller-supplied stack arguments and task priorities. Official-ROM
runs supplied black-box regression oracles and speech-output comparisons. No original-ROM disassembly or
AROS implementation text was used to author the changes. The binary tool publishes aggregate statistics
and locations in our image only. The original demo, translator/narrator files, Workbench preferences,
reference ROM, disk images and audio captures remain private, uncommitted test inputs.

Both ROMs used a bootable copy of the same Fred Fish disk with the same Workbench dependencies and saved
Preferences on A500/68000 with 512 KiB CHIP and 512 KiB slow RAM. The source disk was preserved.

## Reproducible build snapshot

Exact committed base and candidate sources were archived into separate temporary directories. Development
and production variants were built from fresh object directories with GNU Make, installed vasm/vlink and
fixed identification `audit-speech`. All four images are 262,144 bytes and pass romtool's `is_kick` and
`chk_sum` checks. Production maps came from the actual logged link object lists. Raw-link bytes match the
ROM prefixes outside the generated identification field at offsets 28 through 91.

| Artifact | SHA-256 |
|---|---|
| Base production ROM | `6adf52f35b34e5332718be327af6cf19ccfdbdc4ab111f7aa1650f525ea9d5c4` |
| Candidate production ROM | `8832b52f56f4682abfceb313510db3bfdef230e3c65ce5d6ef0d32ed520022cc` |
| Candidate raw implementation link | `62dfe2bbb2ea365f03166c8377574d0781596fba037a7aff77f143635381a2f0` |
| Candidate `src/exec/tasks.s` | `949ef8a7e5338f1a7f3a89d78f391e500150d9e9bd2b8c2e990929d6a78c78ee` |
| Candidate `src/exec/boot.s` | `94783f07d2ea8bc4524bfa18c9666e5a647d339ccc9382c3a625cb1485079c33` |

The source hashes and raw link exactly match the build that passed the complete 16-check quick suite and
application validation. Git-generated identification or a documentation-only commit may change the image
checksum; implementation hashes must remain equal. Local manifests, commands and results are retained in
`build/audit/speech/`; application captures are in `build/speech-investigation/`.

## Implementation and regression review

The AddTask review checked preservation of the supplied argument area, the zero-pointer fallback, frame
size and alignment, the finalPC/default-exit choice, zero register initialization and unchanged ready-list
insertion/rescheduling. The CLI change restores a standard process default. No CPU conditionals or new
platform dependencies were introduced. Existing edited files have no copyright ending years to extend;
license wording and V34 compatibility versions remain unchanged, and dated component notes were updated.

Two authored native tests are registered beneath both normal and quick Exec groups:

- TASKARGS supplies four distinct stack positions below tc_SPUpper, including word-only alignment.
  Children record their actual entry stack and arguments; the test checks untouched argument/padding
  guards, ordinary RTS/default exit and a custom finalPC. It fails on the original implementation and
  passes on the corrected and official Kickstart 1.3 ROMs.
- CLIPRI checks the Initial CLI's public priority and requires a newly readied ordinary priority-zero
  worker to run before the parent continues after Permit. It fails on the priority-two implementation
  and passes on the corrected and official ROMs.

`gmake -j3 test-quick` passed all 16 native checks, including existing pixel/state and performance gates.
The original build's Speech capture is silent and the program waits indefinitely. The corrected build
produces the full spoken sequence and returns to the shell; a second interactive invocation also returns.
A separate visible fixed session was verified with live host audio and normal pacing. Existing user windows
were preserved, and owned headless diagnostic sessions were closed.

## AROS source comparison

Both changed assembly files were compared against AROS commit `4dbf6509` with:

```sh
python3 -I tests/audit_aros_similarity.py <base-or-candidate-changed-src> <aros-corpus> \
  -k 12 20 30 --limit 100 --json <results.json>
```

The unchanged corpus includes 65 comparable assembly files / 22,757 tokens, 202 unrelated assembly files /
374,229 tokens, 2,439 comparable C files, 1,308 unrelated C files, and 599 public-header/function-list files
for the ABI whitelist. The third-party Amiga subset has 86 files / 52,214 tokens.

| Exact-match metric | Base | Candidate |
|---|---:|---:|
| Comparable AROS matched tokens, k=12 | 223 | 223 |
| Comparable AROS longest run, k=12 | 17 | 17 |
| Unrelated matched tokens, k=12 | 257 | 257 |
| Unrelated longest run, k=12 | 17 | 17 |
| Matched tokens in any target group, exact k=20 or k=30 | 0 | 0 |

All normalized and structural k=20/k=30 counts and maxima are unchanged. At structural k=12 only, short
common shapes add 14 matched tokens against comparable AROS and five against the unrelated group, without
increasing a maximum. Shared comment shingles decrease from seven to six; non-ABI identifier groups remain
10 comparable and nine unrelated. No distinctive new source/comment reuse was found.

## Binary comparison

Complete production images were compared against Kickstart 1.3, SHA-1
`891e9a547772fe0c6c19b610baf8bc4ea7fcb785`, with Capstone-enabled word, exact-instruction and loose-instruction
streams. Identical available controls were used: Workbench's 512 CODE hunks / 472,284 bytes and AROS's
50 hunks/images / 1,155,856 bytes.

```sh
python3 -I tests/audit_rom_similarity.py <base-or-candidate.rom> <reference256.rom> \
  --map <matching.map> --temoin wb13-available <workbench-controls> \
  --temoin aros-available <aros-controls> --base tiers --seuil 8 --selftest
# Repeat with --seuil 4, without --selftest.
```

The historical unrelated `tiers` corpus is absent. Workbench/AROS controls do not replace that baseline;
the established fixed gates of 40 words / 19 exact instructions / 19 loose instructions are retained.

| Qualified-code metric | Base | Candidate |
|---|---:|---:|
| Global maximum, words | 19 | 19 |
| Global maximum, exact instructions | 13 | 13 |
| Global maximum, loose instructions | 13 | 13 |
| `tasks.o` word/exact/loose maxima | 10 / 5 / 6 | 10 / 5 / 6 |
| `boot.o` word/exact/loose maxima | 11 / 5 / 9 | 11 / 5 / 9 |
| Relocated-fragment positive control | 12/12 | 12/12 |

Qualification uses the established generated/public-data exclusions: fixed-width font-location tables,
keymap string records, default colors and public image descriptors, plus the tool's own text/header/
low-entropy classifications. Their declarations are unchanged and no new exclusion was added. Raw code/table
maxima remain 449 words / 17 exact instructions / 17 loose instructions because linear decoding includes data.

No new qualified match reaches eight tokens. The apparent new 17-instruction rows fall in the unchanged
public keymap string table and are covered by the existing exclusion. At threshold four, the only added
qualified matches in the changed code are one four-word row and one four-loose-instruction row in AddTask.
No qualified peak increases or reaches a fixed gate. No source, binary or implementation objection remains.

This verdict is limited to the stated corpora and checks. Similarity measurements cannot exclude arbitrary
semantic rewriting; provenance and manual implementation review remain part of the result. Only the fixes,
authored regressions, documentation and this report are committed.
