# Clock performance with Kickstart 1.3

Analysis dates: 2026-11-04 to 2026-11-05.

This report records black-box observations of the unchanged Workbench 1.3
Utilities/Clock program running with original Kickstart 1.3, revision 34.5.
It contains behavioral measurements and public API inputs, with no ROM code,
routine addresses, disassembly, or extracted ROM data.

## Test conditions

The reference used Copperline 1.0.1 with a PAL A500, a 68000 at the stock
7.09 MHz clock, explicit OCS Agnus and Denise, 512 KiB chip RAM, 512 KiB slow
RAM, and 1 MiB fast RAM. The Copperline identification board was disabled.
Floppy speed was set to 0. All durations below are emulated time, independent
of host execution speed.

Clock was copied unchanged from the Workbench 1.3 disk to a disposable OFS
disk. Its startup sequence launched `df0:Clock` directly from the CLI, without
SetPatch, FastFonts, or Workbench. Both ROMs used copies of the same test disk.
The separate original-ROM diagnostics did not disturb the user's visible
Workbench reference session.

## Measurement method

An unnamed LoadSeg catch identified Clock's loaded segments. A breakpoint at
the first segment's entry established the application-entry timestamp. API
breakpoints were restricted to the Clock task, excluding other tasks' waits
and drawing.

Inclusive API durations were measured from each API entry to its saved return
PC, with a matching stack pointer at return. Deterministic checkpoint replay
reproduced every measured entry at the same emulated timestamp and PC. Return
registers were checked. Nested calls are included in their callers' durations,
so overlapping API totals must not be added as independent costs.

For Copperline 1.0.1 return-breakpoint conditions, the register name `sp`
worked. The accepted alias `a7` failed to match in this investigation. An
unconditional return breakpoint independently confirmed the OpenWindow
duration obtained with the `sp` condition.

Completed drawing was checked by inspecting framebuffer captures at the
Clock task's first relevant `exec.library/Wait`. The resized result was also
checked two video frames later and was visually unchanged. No framebuffer
data is reproduced here.

## Initial face

Original Kickstart opened Clock at left 10, top 15, with a 170 by 90 pixel
Window. The first Wait followed the completed face and tick marks. The hands
appeared on the following timer update, so these are separate milestones.

| Interval | Original Kickstart |
|----------|-------------------:|
| Application entry to first Wait, face and ticks complete | 396.837 ms |
| OpenWindow entry to first Wait | 391.878 ms |
| First face AreaEnd entry to first Wait | 300.980 ms |
| Application entry to first hands-complete Wait | 643.378 ms |

Clock's direct selected drawing calls before the first Wait were OpenWindow
once, AreaEnd 13 times, and Draw 228 times. DrawEllipse was not called.

| Direct API | Calls | Inclusive total | Median per call | Maximum per call |
|------------|------:|----------------:|----------------:|-----------------:|
| OpenWindow | 1 | 84.327 ms | 84.327 ms | 84.327 ms |
| Draw | 228 | 110.650 ms | 0.463 ms | 2.944 ms |
| AreaEnd | 13 | 40.081 ms | 2.548 ms | 10.318 ms |

The following table includes nested graphics calls and window-decoration
work performed in the Clock task. Its Draw count includes six additional
calls beyond the 228 calls made directly by Clock.

| Observed graphics API | Calls | Inclusive total |
|-----------------------|------:|----------------:|
| Draw | 234 | 114.048 ms |
| AreaEnd | 13 | 40.081 ms |
| BltPattern | 23 | 25.405 ms |
| RectFill | 10 | 14.611 ms |
| BltBitMap | 7 | 6.234 ms |
| BltTemplate | 2 | 0.942 ms |
| WritePixel | 3 | 0.275 ms |
| DrawEllipse | 0 | — |

## Drawing inputs

All 228 direct initial Draw calls used JAM1 with a solid LinePtrn of all one
bits. ONE_DOT was clear throughout. RastPort Flags contained FRST_DOT on
58 calls and were zero on 170 calls; continuation behavior therefore matters.

The maximum absolute coordinate delta of each initial line ranged from
2 through 27, corresponding to inclusive raster lengths of 3 through 28
pixels. Euclidean endpoint distances ranged from 2 through 27.166 pixels.

At AreaEnd, Clock supplied a TmpRas structure on its own stack, with a
16,000-byte buffer in chip RAM. The first AreaEnd had 18 vectors and an
AreaInfo capacity of 20. These observations describe caller-supplied
resources, rather than an allocation strategy inferred from ROM code.

## Resize to 340 by 180

The size gadget was dragged from the initial 170 by 90 Window to a 340 by
180 Window. The button press was allowed to reach Intuition before moving
the pointer; the reference timestamp for mouse release was taken after the
target size had been outlined. Public Window fields confirmed the final
dimensions.

Clock performed two refresh passes before returning to Wait:

| Interval | Original Kickstart |
|----------|-------------------:|
| Mouse release to first post-resize Wait | 692.198 ms |
| First BeginRefresh entry to first post-resize Wait | 505.197 ms |
| First BeginRefresh entry to its EndRefresh entry | 298.056 ms |
| Second BeginRefresh entry to its EndRefresh entry | 202.523 ms |

The two per-pass intervals above end at EndRefresh entry; their endpoint
definition is distinct from the inclusive EndRefresh call durations below.

| Observed API across both passes | Calls | Inclusive total |
|--------------------------------|------:|----------------:|
| Draw | 456 | 165.444 ms |
| AreaEnd | 28 | 98.497 ms |
| BltPattern | 28 | 17.901 ms |
| BltTemplate | 4 | 1.719 ms |
| WritePixel | 14 | 1.285 ms |
| BeginRefresh | 2 | 7.332 ms |
| EndRefresh | 2 | 0.980 ms |
| DrawEllipse, RectFill, BltBitMap | 0 | — |

The enlarged Draw calls still used JAM1, a solid LinePtrn, and ONE_DOT clear.
Their maximum absolute coordinate deltas ranged from 4 through 56,
corresponding to inclusive raster lengths of 5 through 57 pixels.

## Implementation snapshot and geometry caveat

The implementation snapshot measured during this investigation took
763.089 ms from application entry to its first Clock-task Wait. Its selected
direct API counts matched the original: Draw 228, AreaEnd 13, OpenWindow 1.
The snapshot's MD5 was `71d59a9cd9871dfeb6aabb58823dd86d`; later builds
require new measurements.

| Direct API | Original inclusive total | Implementation snapshot |
|------------|-------------------------:|------------------------:|
| OpenWindow | 84.327 ms | 108.127 ms |
| Draw | 110.650 ms | 290.776 ms |
| AreaEnd | 40.081 ms | 182.651 ms |
| First AreaEnd only | 10.318 ms | 125.506 ms |

The public Window fields revealed a material difference: the original opened
a 170 by 90 Window, whereas this implementation snapshot opened a 170 by
105 Window. Both used left 10 and top 15. The same executable and startup
disk therefore did not produce identical initial drawing geometry. Mask
dimensions and line lengths can affect the comparison; these measurements
must not be described as geometry-matched performance parity.

## Public display inputs

The display comparison was completed on 2026-11-05 using saved initial
Draw-entry checkpoints. The implementation values below belong to the fixed
after-fastmem snapshot, MD5 `62a27340c9127768c292b769c0ac7d7f`.

Launch metadata and saved beam positions establish that both emulators used
PAL timing: 313 beam rows, 227 colour clocks per row, and 71,051 colour clocks
per frame. The original emulator therefore remained PAL even though its
graphics.library public defaults selected NTSC. This distinction is between
the emulated beam timing and guest display defaults.

| Public input | Original Kickstart | Implementation after-fastmem |
|--------------|-------------------:|-----------------------------:|
| Actual emulator video standard | PAL | PAL |
| Actual beam rows per frame | 313 | 313 |
| Colour clocks per beam row | 227 | 227 |
| GfxBase.DisplayFlags | 0x0001, NTSC | 0x0004, PAL |
| GfxBase.NormalDisplayRows | 200 | 256 |
| GfxBase.NormalDisplayColumns | 640 | 640 |
| GfxBase.NormalDPMX | 1280 | 1226 |
| GfxBase.NormalDPMY | 1098 | 1299 |
| Clock Screen.Width | 640 | 640 |
| Clock Screen.Height | 200 | 256 |
| Clock Screen.ViewPort.Modes | 0xC000, HIRES and SPRITES | 0x8000, HIRES |
| Clock RPort font tf_XSize | 10 | 10 |
| Clock RPort font tf_YSize | 9 | 9 |

Matching Clock's Window dimensions alone did not match screen DMA geometry:
the original screen had 200 rows, while the implementation screen had 256.
The ViewPort mode bits also differed. Equal PAL beam timing and a 340 by 180
Window therefore do not establish equal display DMA load. No exact speed
parity claim follows from these comparisons.

## Recommended parity gate

Use an explicitly verified 340 by 180 Window on both ROMs, then measure
from the first BeginRefresh entry for the resize to the first Clock-task Wait
after both refresh passes. The original reference for that gate is
505.197 ms. This excludes loader time and pointer-motion duration while
including both observed refresh passes and the completed repaint.

For a speed-parity comparison, also match the Screen dimensions, ViewPort
modes, public display defaults, and font metrics listed above. Check the
realized Window dimensions, task filter, two-pass behavior, drawing call mix,
and completed visible result alongside the duration. Passing a time limit
with different geometry or incomplete drawing does not establish parity.
The original initial-face milestone of 396.837 ms is an additional gate once
the initial 170 by 90 geometry is matched.

## Clean-room review — 2026-11-05

This document was reviewed in the sealed analysis track. It contains
observable timing, emulator settings, public API names, and public structure
field values. It contains no original-ROM bytes, routine addresses,
instruction listings, transcribed implementation, or extracted font, keymap,
or image data. The fingerprints identify implementation snapshots only.

Original-ROM execution and checkpoint inspection remained in the separate
analysis context. Raw original logs, screenshots, memory captures, and
disassembly were not transferred to the implementation track. The report is
suitable for consumption there as a behavioral specification.

Black-box behavioral analysis deliberately occurred and may inform
compatibility and performance work. This review concerns the content crossing
the clean-room boundary; it does not claim that no reverse engineering took
place or prove the historical origin of implementation code.
