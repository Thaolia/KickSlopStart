# Deluxe Paint III zoom and zero-stride bitmaps (V34)

Observed on 2026-11-16 with official Kickstart 1.3 revision 34.5 in Copperline 1.0.1,
using an A500 configuration with 512 KiB CHIP, 512 KiB slow memory and no fast memory.
This document contains black-box observations and public ABI values only. No original-ROM
instructions, routine addresses, embedded data or artwork are reproduced.

## Public interface

`BltBitMap` receives source and destination `BitMap` pointers, source and destination coordinates,
width, height, Boolean minterm, plane mask and optional temporary storage. The public `BitMap`
layout begins with the unsigned word fields `BytesPerRow` and `Rows`, followed by byte fields
`Flags` and `Depth`, a reserved word and the plane pointers. `BytesPerRow` describes the row
address increment; it must not automatically be treated as the allocation's horizontal extent
when it is zero. The caller remains responsible for valid backing storage.

The public minterm truth table identifies channel A with rectangle coverage, B with source pixels
and C with destination pixels. Inside the rectangle, high-nibble value `$C` copies the source and
`$E` combines source and destination with OR. Plane-mask bits select participating planes.
These interface facts were checked against the public declarations and AutoDoc material retained
in the read-only AROS corpus, rather than recovered from original-ROM implementation code.

## Repeated source rows

An independently run authored native probe tested source `BytesPerRow = 0` with an ordinary
8-byte destination stride. Its 48 cases cover all 16 Boolean high-nibble minterms and masks
0, 1 and 3, with two planes, word-aligned backing storage, a non-byte-aligned source/destination
position and a 37-by-5 rectangle. A decisive follow-up declares source `Rows = 1` while requesting
source Y coordinate 1 and five output rows. All 48 complete-allocation fingerprint checks pass;
the serial output includes `COPYMIN PIXELS OK`, `COPYMIN OK` and `COPYMIN END`, with no failure.
The source's row address repeats while the destination advances. Neither zero source stride nor
the nominal source row count makes this raw bitmap operation empty or truncates its requested
height. Masked-out storage and allocation guards are part of the fingerprints.

The probe was authored outside the documentation agent, using an independently evaluated pixel
model. The analysis agent only executed the existing artifacts. An earlier broader probe did not
finish successfully; its repeated-source cases completed before the later failure below, and the
follow-up isolates the supported source-zero behavior in a complete successful run.

## Repeated destination rows are a separate question

The same diagnostic reports its first failure at selected case 65: source stride 8, destination
stride 0, mask 1, minterm `$1F`. This case repeatedly modifies overlapping destination storage.
Its complete-allocation fingerprint differs from the authored model's forward row-update order.
Consequently, success with a repeated source row does **not** establish universal native
equivalence for zero-stride destinations, overlapping planes, every update order or self-blits.
The observation does not identify the original implementation's traversal strategy.

The full replacement-ROM regression also includes intentional CPU-fallback and ordinary clipping
extensions. Its overall failure on the official ROM is not evidence against the isolated repeated
source-row result, and it is not recorded as a native compatibility pass.

## Deluxe Paint III behavior

An independent replay restored an established canvas checkpoint, selected the line tool, drew
an authored diagonal, enabled zoom and selected its focus. After pointer movement completed the
application's refresh, the normal view remained visible at the left, a narrow divider separated
it from the enlarged view, and the enlarged diagonal was continuous. An early capture during
zoom entry could show a partially refreshed enlarged pane; it is not a suitable completed-frame
oracle.

Observation at the public `BltBitMap` entry during zoom independently confirmed a source bitmap
with `BytesPerRow = 0`, five planes and `Rows = 49`, copied into the ordinary 40-byte-stride screen
bitmap. A sampled call requests a 192-by-5 rectangle, minterm `$CC` and mask `$FF`. Its source
coordinates are `(0,0)`: the repeated source row supplies a five-row enlarged band. This is a
public API-call observation, not an account of the ROM routine's implementation. Temporary
bitmap descriptors can change during the operation; a descriptor read after a later call must
not be retroactively attributed to an earlier call.

The existing freehand replay was independently repeated with the official ROM. It selects the
freehand tool, holds the button while submitting several small normal-pane movements, then
does the same in the enlarged pane. Inspected captures show the normal-pane stroke reflected
in the enlarged pane while the button is held, and the enlarged-pane stroke reflected in the
normal pane while held. Releasing the button preserves both strokes. Verification must inspect
these held states, rather than rely only on a later unrelated redraw.

## Evidence and procedural limits

Private evidence remains beneath `build/dpaint-zoom/official/`, `official-zero/`,
`official-zero-diagnostic/` and `official-zero-source/`: tracked session ledgers, native captures, public-entry observations
and probe serial output. The official ROM and all disk/program assets remain uncommitted.
Screenshots are verification evidence only and supply no replacement geometry or image data.

The implementation context had already performed official-ROM black-box observations earlier
in this investigation, before recognizing the repository's stricter dedicated-agent rule.
It reports that it did not inspect original-ROM instructions or disassembly. Those earlier
observations were a procedural exception; the sealed-track rule was not followed throughout.
The essential observations above were independently repeated by the separate documentation
agent. This repetition does not erase the earlier exception. Quantitative code-similarity
findings are reported separately in the audit record.
