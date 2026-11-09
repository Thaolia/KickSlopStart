# DSS module channel refresh: Kickstart 1.3 behavior (2026-11-09)

This is an isolated analysis-track report. Measurements used Copperline 1.0.1, an A500/68000/OCS,
512 KiB CHIP RAM, 512 KiB slow RAM and no fast RAM, with the user's prepared Workbench-compatible
Amiga Dream disk and DSS_TRACKER_DEMO. No implementation or original-ROM instruction sequence is
transcribed. All coordinates and bitmap dimensions below are public call arguments or structure fields,
not geometry reconstructed from a screenshot.

## Reproduction and playback-state check

The requested route is: launch DSS, click through its information/title screens, choose module mode with
the musical-notes control, load DSS_TRACKER_DEMO through Projet / Chanson / Charger, and press the
control immediately above Stop.

The existing visible original-ROM session already had the module loaded. Its checkpoint initially showed
an insufficient-memory banner. One left click dismissed that banner and moved the DSS screen upward.
The module display alone did **not** establish playback: it remained static until Play was explicitly
clicked. Confirm that song/pattern position or displayed channel rows advance before collecting a profile.

A separate headless session loaded a checkpoint of the visible session with an identical copied floppy.
After dismissing the banner and pressing Play, pattern/song positions visibly advanced over ten emulated
seconds. Only that private clone was stepped or profiled; the user's visible sessions were left running.

## Main channel-panel copy [observed public graphics calls]

A recurring `graphics.library/ClipBlit` has the following arguments and public RastPort/BitMap state:

| Field | Observed value |
|---|---|
| Source RastPort | Separate from destination, no Layer |
| Destination RastPort | No Layer |
| Source BitMap | 58 bytes/row, 737 rows, depth 1, CHIP plane |
| Destination BitMap | 80 bytes/row, 256 rows, depth 1, CHIP plane |
| Source position | x=0; y advances in steps of 10 and wraps at a song/display boundary |
| Destination position | x=74, y=39 |
| Extent | width=456, height=107 |
| Minterm | `$C0` |
| Both RastPorts | Mask `$FF`, FgPen `$FF`, BgPen 0, JAM2 |

Fifty successive observed calls had identical destination/extent/minterm. Their median entry-to-entry
interval was approximately **80.0 ms**, or **12.5 updates per second**, in this portion of the module.
Occasional shorter spacing appeared at a source-cycle boundary; this is not a fixed-rate API guarantee.
Song playback can change its tick/speed state, so compare equivalent module phases when measuring cadence.

Inclusive durations were measured from the public ClipBlit entry to its saved caller return address,
conditioned on restoration of the entry stack pointer plus four bytes. Nine consecutive copies with
source y=190 through 270 took **9.55–9.95 ms**, median **9.7474 ms**. An earlier copy at source y=400
measured **8.2007 ms**. These figures include interrupt and chip-bus contention at the observed phases;
they are not a universal constant or a CPU-only routine cost.

## Active-playback profile [500 PAL fields]

The private active-playback capture recorded approximately ten emulated seconds:

- 1,244,438 retired instructions across the 500 recorded fields.
- 711 recorded blits, spread over 171 fields; 128 of the recorded blits were 30 words wide by 107 rows.
- 2,429,045 blitter-busy colour clocks, with 976,898 CPU chip-bus wait clocks.
- Public WaitBlit and immediately following polling locations together accounted for approximately 24.6%
  of weighted retired-instruction clocks. This percentage excludes time with no retired instruction and
  must not be interpreted as 24.6% of total guest wall time.

Other blits include narrow 2-word by 102-row and 2-word by 4-row operations. This is hardware activity
observed during the display updates, not a prescription for a replacement implementation.

## Suggested independent regression/benchmark

An implementation-side probe can author two one-plane CHIP BitMaps with the strides/row counts above,
attach independent layerless RastPorts initialized through InitRastPort, and call ClipBlit with the stated
arguments. Fill the source with an authored repeating pattern, independently verify the copied pixels and
untouched destination edge bits/guards, and time through WaitBlit in PAL scanline or colour-clock units.
No DSS executable, music data, proprietary glyphs or screen-derived replacement geometry is required.

The differing row strides and destination's non-word-aligned x coordinate are material to this case.
A broader correctness probe should exercise source/destination alignments, edge masks, plane masks,
non-DMA memory and overlap separately. The concrete observed DSS call is between distinct BitMaps;
its benchmark need not assume overlap.

## Limits

This establishes the original system's observable call shape, refresh cadence and sample inclusive timings.
It does not measure the replacement ROM or establish its bottleneck. The active profile is from a resumed
floppy-only checkpoint; module advancement was verified after restore. Host-filesystem checkpoint behavior
was not involved. The memory-warning/stopped screen was excluded from the active measurement.
