# Tests & test bench

## MakeVPort window probe

`tests/mvport_probe.sh <out_dir> [rom]` runs `tests/mvport_probe.s` (CLI command, our ROM under Amiberry): for each of
the 13 probed configurations of `docs/analysis/graphics-display-v34.md` §4.4 it calls MakeVPort and prints the
copper fragment; `tests/mvport_check.py` decodes DIWSTRT/DIWSTOP, DDFSTRT/DDFSTOP, BPLCON1, the modulos, the plane
pointers, the BPLCON0 at the top of the ViewPort, the number of colours and the lead-in line, and compares them with
the spec. Success: `MVPORT OK`.

## MrgCop merge probe

`tests/mrgcop_probe.sh <out_dir> [rom]` runs `tests/mrgcop_probe.s` (CLI command, our ROM under Amiberry): nine Views
of one or two ViewPorts (the lists of `docs/analysis/graphics-display-v34.md` §5.3, line 255 crossed at $DE and,
HIRES 4 planes with DDFSTOP $D4, at DDFSTRT, a UCopList inside and below its ViewPort, stacked and contiguous
ViewPorts of §5.4, an interlaced View, and one View shown with LoadView then patched by SetRGB4 and ScrollVPort) go
through MakeVPort and MrgCop and their hardware lists are printed. `tests/mrgcop_check.py` cuts each list into WAITs
and the MOVEs after them and compares them with the spec. Success: `OK: 9 cases ...`. A line damaged by lost serial
characters is reported as such: run the probe again.

## exec scheduling probe

`tests/sched_probe.sh <out_dir> [rom]` runs `tests/sched_probe.s` (CLI command, our ROM under Amiberry): ExecBase
Quantum and Elapsed read by a busy loop on 8 frames (timer.device's quantum, `timer-v34.md` §3), the D0 that Signal
returns (the previous tc_SigRecvd, `exec-scheduling-v34.md` §2.7), and SR and INTENAR inside a software interrupt
(SR $2000, SOFTINT off, §8). Success: `SCHED OK`.

## ClipBlit within one RastPort

`tests/clipblit_probe.sh <out_dir> [rom]` runs `tests/clipblit_probe.s`: a borderless SMART_REFRESH window filled
with 8-pixel columns of pens, partly covered by a second window, is ClipBlitted onto itself 8 pixels to the right,
then the cover window closes and every pixel of the destination is read back (`graphics-blitter-v34.md` §5.3 step
3). Prints `CB FILL` (the fill, 0 expected) and `CB BAD` (wrong pixels after the copy). Success: `CLIPBLIT OK`.

## Large files, moved disks, clipped lines, WaitTOF

- `tests/bigfile_probe.sh <out_dir> [rom]`: a 40 MiB hardfile (DH0:) holding `huge`, 33,600,000 bytes whose long at
  byte offset 4n is n, written on the host; `tests/bigfile_probe.s` prints Examine's size and block count, reads 8
  bytes after Seek at five offsets (four past 65,535 data blocks), then writes 8 bytes in place (MODE_READWRITE). The
  host checks the values, the written bytes and the partition with `ofs_check`. Success: `BIGFILE OK`.
- `tests/fhmove_probe.sh <out_dir> [rom]`: three drives; `tests/fhmove_probe.s` reads DF1:longfile by 2 KB blocks,
  then writes DF1:w in two lines 20 s apart, while the harness moves the data disk DF1 -> DF2 -> DF1 through IPC
  during each part (`docs/analysis/disk-change-v34.md` §2.4.1). Screenshots `read_in_df2.png` / `write_in_df2.png`
  must show "Please replace volume / Data3 / in unit  1"; the host checks the byte count and sum of the read and the
  file w. Success: `FHMOVE OK`.
- `tests/lineclip_probe.sh <out_dir> [rom]`: 1,000 pseudo-random lines in five modes (patterns, JAM2, COMPLEMENT,
  ONE_DOT) in a window covered by two others; prints the drawing time (`LC TICKS`) and the plane fingerprints after
  the covers close (`LC CKS`), to compare between two ROMs.
- `tests/waittof_probe.sh <out_dir> [rom]`: runs `tests/waittof_probe.s` (WaitTOF return lines, VERTB chain cost;
  `graphics-display-v34.md` §7.2/§7.4) and keeps its `WT` lines.

## trackdisk error codes

`tests/tdcode_probe.sh <out_dir> [rom]` runs `tests/tdcode_probe.s` from the boot disk and ejects it through
Amiberry's IPC when the probe prints `TC EJECT`: CMD_READ beyond the disk (−4), ETD_READ with an old and a current
change count (29, 0), CMD_READ and TD_FORMAT without a floppy (29, io_Actual 0) (`trackdisk-write-v34.md` §5.2, §7).
Success: `TDCODE OK`.

## Native rectangle-pen regression

`make test-graphics-rectpens` (also included through the normal and quick Graphics groups) supplies per-plane
minterms independently of the RastPort pens and drawing mode. An authored selective XOR reproduces DPaint III's
chooser highlight; other cases check clear, invert, preserve, set, patterned and multicolour operations, partial
plane masks, untouched edge pixels, allocation guards and unchanged RastPort state. Small and large rectangles
exercise the CPU and eligible blitter paths in CHIP memory, and repeat in non-DMA RAM. Expected pixel values
are checked independently rather than accepting agreement between the two engines. Text-clear cases also check
that SetRast ignores cached minterms and ClearEOL/ClearScreen select the background pen and restore coherent
pen state. Logs and screenshots are in `build/rectpens-results/`; success requires `RECTPENS OK` and `RECTPENS END`.
The selective-XOR test fails on the pre-fix ROM.

## Native shifted-copy regression and speed gate

`make test-graphics-copyshift` (also included through the normal and quick Graphics groups) exercises ClipBlit
between authored bitmaps. The generator `mk_copyshift_cases.py` creates independent per-pixel expected results,
reduced to complete-buffer fingerprints. Coverage includes all source/destination byte phases, masked edge
bits, plane masks, unequal/odd strides, odd addresses, constant planes, a second destination plane, safe
leftward aliasing and a non-copy minterm. The entire allocation is checked, including guards and source data;
destination RastPort state must remain unchanged. CHIP and non-DMA allocations run the same cases.

Eight large shifted panel copies are timed in native PAL scanlines. Each must average less than 1,024 lines,
comfortably below an 80 ms display-update interval. The pre-fix ROM passes the pixel checks but fails this
performance gate. Logs and screenshots are in `build/copyshift-results/`; success requires `COPYSHIFT OK` and
`COPYSHIFT END`. No DSS executable, music or glyph data is part of the fixture.

Measured on the 512 KiB CHIP / 512 KiB slow-RAM fixture, eight large copies take 35,630 PAL scanlines before
the fix and 6,105 afterward (about 5.8 times faster). In the initial playback validation, 60 panel-call entries have a median
interval of 322.49 ms before the fix and 80.00 ms afterward, matching the approximately 80 ms reference cadence
in the tested song section. This is display-cadence parity, not copy-routine speed parity: an inclusive fixed
ClipBlit still takes about 54.6 ms where the original reference measured approximately 9.7 ms. Tempo changes
within the module can change the requested update interval.

## Native bitmap-minterm and curve-restore regression

`make test-graphics-copymin` (also included through the normal and quick Graphics groups) tests authored
bitmap patterns through `BltBitMap`, `BltBitMapRastPort` and `ClipBlit` in CHIP and non-DMA memory. The independent
per-pixel Boolean oracle in `mk_copymin_cases.py` generates whole-buffer fingerprints, including untouched
rows, columns, masked planes and allocation guards. The 267 cases cover all 256 minterms, constant source
planes, safe leftward aliasing, negative destination clipping, zero/partial/full masks, shifted bit phases,
odd strides, odd plane addresses, different source/destination parity and multi-block row tails. The fixture
also verifies preserved destination RastPort state, the minterm register and the BltBitMap plane count.

A five-plane, 40-byte-stride, 256-row workload restores `(0,11)` to `(0,11)` over 296 by 245 pixels. Four
`ClipBlit` restores followed by `WaitBlit` are measured for each of `$C0` and `$CC`, first in CHIP and then
non-DMA memory, with pixel fingerprints checked after each workload. Both four-copy totals must stay below
4800 PAL scanlines (average below about 77 ms per restore); `$CC` must take no more than 125% of `$C0`.
Timing excludes buffer generation and fingerprints. The pre-fix production ROM passes pixels but fails this
latency gate. Success requires `COPYMIN PIXELS OK`, two `COPYMIN RESTORE` timing records (hex scanlines),
`COPYMIN OK` and `COPYMIN END`. Logs/screenshots are in `build/copymin-results/`.

## Native line-pen and cursor-erasure regression

`make test-graphics-linepens` (also included through the normal and quick Graphics groups) supplies custom
per-plane Draw minterms independently of FgPen/BgPen/DrawMode. Authored lines exercise both axis directions,
all eight octants and single points; the per-pixel oracle in `mk_linepens_cases.py` generates whole-buffer
fingerprints including allocation guards. Thirty-three cases run in CHIP and non-DMA memory, with two/five
planes, odd plane addresses, translated layers, partial plane masks, line patterns and all eight drawing modes.
RastPort state is checked independently of its documented cursor/phase updates. A final case draws the full
XOR line set twice and requires the allocation to return to its original contents. This catches DPaint III's
rectangle-tool hover trails in the CPU, rectangle and line-mode paths. The pre-fix ROM fails; success requires
`LINEPENS OK` and `LINEPENS END`. Logs/screenshots are in `build/linepens-results/`.

## Native polled-mouse regression

`make test-intuition-mousepoll` (also included through the normal and quick Intuition groups) opens a screen
with active and inactive windows, holds the left button and injects a rectangle of raw mouse movements through
input.device. Screen/Window coordinates must follow every point regardless of REPORTMOUSE or IDCMP MOUSEMOVE.
All four combinations are tested, with exactly one down/up notification per gesture and move notifications
only when both subscriptions are enabled. This catches the frozen polled coordinates that prevented DPaint III
from drawing continuous strokes. The pre-fix ROM fails the probe; success requires `MOUSEPOLL OK` and
`MOUSEPOLL END`. Logs and screenshots are in `build/mousepoll-results/`.

## Native menu-font regression

`make test-intuition-menufont` (also included through the normal and quick Intuition groups) registers an authored
six-pixel font, opens a screen using it while the global font differs, and drives real right-button input to show
the menu bar, item box and submenu. Solid test glyphs give observable text widths without depending on proprietary
font pixels or exact frame placement. Logs and screenshots are in `build/menufont-results/`; success requires
`MENUFONT OK` and `MENUFONT END` after all three drawing stages.
It also checks disabled-gadget stipple pixels and preserved pens/minterms, then disables the menu and verifies
that the title loses exactly one quarter of its solid authored glyph pixels. This catches stale pen minterms
in internal ghost drawing after RectFill starts honoring the stored per-plane operations.

## Native proportional-knob drawing state

`make test-intuition-propstate` (also included through the normal and quick Intuition groups) injects actual raw
mouse events through `input.device` to press, drag and release an AUTOKNOB gadget. The probe requires both IDCMP
button messages, verifies that the client's pens, drawing mode and per-plane minterms survive the interaction,
then redraws an opposite template pattern to check that old pixels are replaced rather than accumulated.
Logs and screenshots are in `build/propstate-results/`; success requires `PROPSTATE OK` and `PROPSTATE END`.

## Native string-gadget drawing bounds

`make test-intuition-stringbounds` (also included through the normal and quick Intuition groups) refreshes
empty and nonempty string gadgets whose declared boxes exceed complete font cells. Authored guards verify that
extra bottom rows, partial right columns and cells beyond the buffer's padding capacity remain untouched.
A second refresh checks that shortening the text clears old characters within the permitted cells. Logs and
screenshots are in `build/stringbounds-results/`; success requires `STRBOUNDS OK` and `STRBOUNDS END`.

## Native window-font regression

`make test-intuition-windowfont` (also included through `test-intuition` and `test-intuition-quick`) opens
borderless, decorated and GIMMEZEROZERO windows on an eight-pixel-font screen while the global default font
is different. It checks ordinary and border RastPort fonts, `IFont`, and the GZZ inner port's separate global
default. For ordinary windows it checks text metrics and advance, then verifies
that `Text` leaves authored guard lines beside and below its expected drawing area intact. This catches labels
overflowing their buttons and text erasing nearby borders because a new window retained the global font.
Logs and screenshots are in `build/windowfont-results/`; success requires `WINFONT OK` and `WINFONT END`.

## Native short-window regression

`make test-intuition-smallwindow` (also included through `test-intuition` and `test-intuition-quick`) opens
close-only windows with requested heights 10, 1, 8, 15 and 16. It checks the returned height, the layer's inclusive
bounds, and sentinel pixels below the requested bottom edge. This catches an unwanted minimum height expanding
a helper window over the application beneath it. Logs and screenshots are in `build/smallwindow-results/`;
success requires `SMALLWIN OK` and `SMALLWIN END`.

## Native PAL long-frame regression

`make test-graphics-longframe` (also included in `test-graphics` and `test-graphics-quick`) checks that graphics
initialization selects a long PAL frame. It then forces a short frame, calls the public `LoadView(NULL)` vector,
and verifies that the beam actually reaches scanline 312 within a bounded polling interval. This catches the
display-takeover stall when a program waits for a scanline absent from short PAL frames. The native 68000/OCS
probe reports `LONGFRAME OK` and `LONGFRAME END`; logs and screenshots are in `build/longframe-results/`.

## Native blitter drawing regression and speed gate

`make test-graphics` (also `test-graphics-quick`, through `test` / `test-quick`) builds the production ROM and
`tests/drawblit.s`, then boots a generated OFS disk in Copperline. Requires `vasmm68k_mot`, `vlink`, `romtool`,
Python 3, `copperline` and `copperline-ctl` in PATH. Override `VASM`, `VLINK`, `COPPERLINE` and `COPPERLINE_CTL`
for local installations. The test is native Amiga 68000/OCS code; no host rendering model substitutes for Agnus.

The same public graphics calls render into CHIP and non-DMA RAM. The entire buffers, including guard bytes,
and the pens, flags, phase and current point must match. Coverage includes all eight line octants, ties and
reverse directions, shared COMPLEMENT vertices, all eight drawing modes, patterns and ONE_DOT, plane masks,
odd plane addresses and row strides, layer offsets, multiple visible ClipRects, hidden SMART backing stores,
and blitter ownership by another task. Limit cases cover 64-word and 1024-row encodings and the wider/taller
CPU fallbacks. Masked non-CHIP planes must not prevent eligible CHIP planes from using DMA.

The benchmark measures 32 diagonal lines, 32 unaligned solid rectangle fills and 32 source=destination
`BltBitMap` clears over three planes, with a
WaitBlit before stopping the timer. Elapsed time uses a VBlank counter plus the beam position (PAL scanline
units), not host execution time. Each acceleration workload must be at least **1.25x faster** in CHIP memory than the CPU
reference. Outputs, screenshot and session PID/command ledger are in `build/drawblit-results/`.
Upstream integration also checks 32 solid-rectangle cases covering all draw modes and every foreground/background
plane-bit pair, including preserve and INVERSVID operations, against the updated CPU engine. A separate
eight-mode check compares a rectangular AreaEnd directly with RectFill, including guards and RastPort state.
Caller-owned TmpRas contents are scratch and are excluded from that public-operation comparison. This test
fails before the area compositor is adapted to upstream's corrected INVERSVID/background-pen rules.
Four independent whole-buffer fingerprints also verify the source-independent clear/set/invert/preserve
minterms, their ignored low nibble, selected plane counts, edge masks and unchanged guard bytes.
The suite also compares short one/two-plane strokes, all octants and drawing modes, template shifts, odd
scratch rasters, polygon slopes and mixed ellipse/line recording against the non-DMA CPU paths. It checks a
client-owned blitter lease, busy ownership, caller-owned update clipping and balanced Forbid nesting. `SHORT`
times 228 authored small two-plane strokes; `AREA` times thirteen authored eighteen-vertex two-plane polygon fills. Each must
also satisfy the 1.25x gate. These fixtures contain no Workbench executable or ROM-derived geometry.

For an older CPU ROM, collect the expected failing performance gate with the same executable:

```sh
python3 -I tests/drawblit_test.py --rom build/kick13-baseline.rom --exe build/drawblit --out build/drawblit-before
# --allow-slow records a baseline without enforcing the speed gate.
```

On 2026-11-04, Copperline 1.0.1, A500/68000/OCS, 512 KiB CHIP + 512 KiB slow, the pre-change production ROM
passed pixel checks but failed the speed gate (both workloads approximately 1.00x). The accelerated ROM passed:
diagonal lines **2273 vs 39985** scanlines (**17.59x**), fills **16671 vs 34667** (**2.08x**). Results describe these
workloads and this emulator, not all drawing calls or a measurement on physical hardware.

Additional before/after checks: `garea_probe.s` output matched exactly; `gline_probe.s` matched except for
DMACONR's BLTZERO status after the newly hardware-drawn line. All 22 `drawcheck.s` screen/window fingerprint
lines matched, including restoration of the covered SMART window. Its output was sent to serial with a
temporary output-only adapter, since Copperline's floppy image was write-protected.

The window-close follow-up (2026-11-04) reproduced layers' `BltBitMap` clear going through source-row snapshots
and the CPU truth-table loop. That operation now shares the rectangle engine. The same 32-clear workload went
from **1892063** scanlines before the fix to **16890** afterward in CHIP RAM (about **112x**). The previous ROM
passes correctness and the line/fill gates but fails the new clear speed gate. Capturing that slow baseline
requires `--seconds 600`; the fixed ROM completes within the normal 240-second capture. Existing blitter and
area probe output and screen/window fingerprints also match across this fix.
The actual Workbench 1.3 disk drawer was opened and closed on both ROMs with the same A500/OCS setup
(512 KiB CHIP, 512 KiB slow, 1 MiB fast). `CloseWindow` entry-to-caller-return timing fell from **0.815 s**
to **0.051 s** (about **16x**); the return PC and stack position were verified, and the opened and repaired
desktop captures were inspected. These are emulated times, including scheduling and interrupts.

## PR review regressions (2026-11-05)

`HORIZ` times 100 horizontal two-plane Draw calls. Its CHIP time must be no more than 10% above the
non-DMA CPU row-fill reference; the five acceleration workloads retain their 1.25x minimum speed gate.
Horizontal Draw bypasses the common line-mode setup, retaining row fills and eligible rectangle blits.
The full native suite uses a bounded 360-second emulated capture to include this additional workload.
The repository's `drawperf.s` workload was also run against upstream and the corrected production ROM, with
only its output redirected to serial in an ignored local adapter. Screen and covered-window horizontal times
were both within 5% of upstream, using the same A500/OCS setup and emulated beam timestamps.

`make test-graphics-lifetime`, included beneath both normal and quick graphics groups, runs `rasterfree.s`.
It starts real OCS DMA into an AllocRaster allocation and an OpenScreen plane, then observes public FreeMem
handoff during FreeRaster and CloseScreen. BBUSY must already be clear at handoff. The test drains DMA inside
its observer on a failing ROM to prevent allocator corruption. It fails on the pre-fix ROM and passes once
raster releases synchronize. Owned layer bitmap and GEL-buffer release paths also wait before freeing memory.
Paula audio is left available; generated emulator configurations disable floppy-drive effects.

## Clock application measurements (2026-11-05)

The unchanged `Utilities/Clock` executable was extracted locally from the user's Workbench 1.3 ADF into an
ignored test disk. Its first-hunk entry and Clock-task Wait/BeginRefresh boundaries were measured in
Copperline 1.0.1 on a PAL A500/68000/OCS, 512 KiB CHIP, 512 KiB slow and 1 MiB fast RAM. The original ROM was
measured separately by the clean-room analysis track; see `docs/analysis/clock-performance-v34.md`.

Initial face painting fell from about **1.449 s** before this update to about **0.52 s**. The original reference
is **0.397 s**. Their logical display defaults differ (ours PAL/256 lines and 170x105 Clock; original NTSC/200
lines and 170x90 Clock, although both physical beams are PAL). A separate test matching our public display
inputs to the reference still measured about **0.518 s**. **This is an improvement, not a claim of exact speed
parity.** No CPU overclock or production display-mode change was used. Pending setup and clipping overhead
remain visible in the application measurements.

The normal and quick exec test groups run `mempriority.s` with actual Zorro fast RAM present. Its public
allocation must land there rather than in slow RAM; an explicit CHIP allocation must remain in CHIP. The
pre-fix ROM fails that test, while the updated ROM passes. `drawblit_test.py` provides the shared native runner.

## boot_test.sh - headless boot of a ROM under FS-UAE

Starts FS-UAE in an Xvfb virtual display, lets the ROM boot, captures the emulated screen and reports the
dominant colours. For the M0 hello-ROM, a **green background** confirms that the coldstart wrote COLOR00
(hence that our code runs on the emulated A500).

```sh
tests/boot_test.sh [path/to/rom] [boot_seconds]
# default: build/kick13-hello.rom, 10 s
```

Prerequisites: `fs-uae`, `Xvfb`, `xwd`, `convert` (ImageMagick). Outputs in `build/boot/`:
`hello.fs-uae` (generated config), `fs-uae.log`, `screen.png` (capture).

Expected M0 result: dominant colour `#00FF00` (green) over the active area, FS-UAE log
"KS ROM ... (262144 bytes)" without errors.

## Coming next (from M2)

Capture of the **serial log** (SERDAT register) as the primary assertion channel, serial markers per
milestone, and black-box oracle comparison against the real KS 1.3 (targeted behavioural probes).

## Clean-room audit - audit_rom_similarity.py, audit_aros_similarity.py

Similarity measurements published in [docs/AUDIT.md](../docs/AUDIT.md) (summary) and `docs/audit/` (details). Both
tools only print statistics and locations in the first argument (our code).

```sh
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom <reference_kick13_rom> [--temoin NAME files...] [--selftest]
python3 -I tests/audit_aros_similarity.py src <aros_clone>
```
