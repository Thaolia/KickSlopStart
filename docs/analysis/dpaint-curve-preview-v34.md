# DPaint III curve preview: Kickstart 1.3 observations (2026-11-09)

This is an isolated analysis-track report using Copperline 1.0.1, A500/68000/OCS, 512 KiB CHIP RAM,
512 KiB slow RAM and no fast RAM. The original Kickstart 1.3 ROM was executed only in this context.
Only public interfaces, observable behavior and aggregate timings are described. No original-ROM
instruction sequence, routine address, glyph, artwork or private implementation is transcribed.

## Reproduction and playback-state check

A fresh copy of the prepared DPaint III program disk boots the application directly. Accept the default
screen format, select the right-column curved-line/arc tool, hold the left button and drag a straight
chord, then release. Subsequent mouse movement changes the curve preview without holding the button.

The initial straight chord was visible promptly after release on the reference system. During control-
point motion the preview changed shape and followed the pointer; the final captured image was inspected.
These checks distinguish the actual curve-editing phase from ordinary freehand drawing or tool selection.
No user-visible emulator session was modified; all measurements used a separate tracked headless instance.

The reference pointer response was calibrated from public IntuitionBase fields: a bounded injection of
40 raw counts changed each high-resolution/interlaced coordinate by 40 units. The resulting one-count-per-
IntuitionBase-unit mapping was used for subsequent bounded raw input. No replacement-ROM private preference
offsets were used on the reference.

## Large preview restore [observed public calls]

The repeated top-level public call is `graphics.library/ClipBlit`:

| Field | Observed value |
|---|---|
| Source position | x=0, y=11 |
| Destination position | x=0, y=11 |
| Extent | 296 pixels by 245 rows |
| Minterm | `$CC` |
| Source BitMap | 40 bytes/row, 256 rows, depth 5, real CHIP planes |
| Destination BitMap | 40 bytes/row, 256 rows, depth 5 |
| Source RastPort | No layer |
| Destination RastPort | Layered |

A breakpoint on the original public BltBitMapRastPort entry did not catch this operation. ClipBlit did.
Thus a replacement implementation's nested BltBitMapRastPort call should not be mistaken for the original
application's public dispatch boundary when comparing inclusive timings.

## Copy timing and completion

Times use emulated time. Entry-to-return measurements stop at ClipBlit's saved caller return address,
conditioned on the restored stack pointer. All seven sampled calls returned with blitter busy still set.
A first separate observation gave 36.49 ms to return and 44.71 ms through completion.

For seven further valid samples:

| Timing boundary | Median | Range |
|---|---:|---:|
| ClipBlit entry to caller return | 36.21 ms | 35.73–40.05 ms |
| ClipBlit entry through explicit public WaitBlit | 45.50 ms | 43.56–48.43 ms |

The completion measurement invokes the public WaitBlit entry by reusing the already-present caller return
stack through debugger register changes; no probe machine code was written. The caller's registers are
restored afterward. This omits only the tiny caller-side instruction overhead of making a normal WaitBlit
call. Busy-clear was checked at the second return. A native benchmark should time through WaitBlit rather
than comparing a synchronous implementation against the earlier asynchronous return boundary.

The inserted completion barrier can remove overlap with the application's subsequent curve calculations.
Those timed samples therefore do not establish natural preview cadence. An eighth requested movement did
not trigger another full-size call within its bound and was excluded.

## Minterm equivalence [observed]

From the same saved public ClipBlit entry, changing only the low-byte minterm from `$CC` to `$C0` produces
identical complete destination-plane digests after WaitBlit, across all five planes. Both branches from that
checkpoint complete at 44.7107 ms. This directly confirms copy equivalence for the actual preview restore;
it is not merely an assumption based on the names of the operations.

## Natural preview profile [separate unmodified replay]

The chord checkpoint was restored before profiling so the explicit timing barriers and register changes
were absent. Bounded raw control-point movements were scheduled every 40 ms for approximately eight seconds.
The requested path stayed inside the canvas, and the final curved preview was inspected.

- 57 matching full-size ClipBlit entries were observed during the motion.
- Median start-to-start interval: **143.09 ms**, approximately **7 updates/second** for this workload.
- Observed start-to-start range: **75.51–161.75 ms**. Input events can be coalesced while drawing takes place.
- A 500-field capture recorded 4,644,062 retired instructions, with zero dropped precise samples.
- There were **285 unique blits**, all 19 words wide by 245 rows: five restore blits per matching copy.
  Per-frame blit records were deduplicated by blit ID because a long blit can span multiple frames.
- Aggregate blitter-busy time was 8,878,853 colour clocks; CPU chip-bus wait time was 3,784,486 clocks.

The interval is a driven-workload observation, not a fixed API rate or a universal DPaint performance claim.
The application also spends time calculating and rasterizing its curve between restores. A future comparison
should use the same control-point path and timing, not infer whole-preview performance from the copy alone.

## Independent regression/benchmark suggestion

An implementation-side test can author two five-plane BitMaps with 40-byte strides and 256 rows, attach
layerless and layered RastPorts, then copy `(0,11)` to `(0,11)` over 296 by 245 pixels through ClipBlit and
WaitBlit. Author the source/destination bytes independently and check copied pixels, untouched top/right
regions, plane masks and allocation guards. Compare `$C0` through `$CF` independently: their low nibble should
not change the requested copy result. The observed real preview uses `$CC`.

All geometry above is from public call arguments and bitmap structure fields, not reconstructed replacement
artwork. No DPaint executable, music, proprietary font or captured framebuffer is needed in such a fixture.

## Limits and session lifecycle

Reference timings include interrupt and chip-bus contention at the sampled phases. They are not guaranteed
on every physical Amiga or another emulator release. The minterm equivalence replay is from a floppy-only
checkpoint with an unchanged copied disk. The natural replay was independently restored and checked visually.
The tracked private reference instance was shut down after measurement; the user's existing visible sessions
remain untouched.
