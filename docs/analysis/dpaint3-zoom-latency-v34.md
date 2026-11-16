# Deluxe Paint III zoom response timing (V34)

Observed on 2026-11-16 by a dedicated documentation-only analysis agent, using
black-box native screenshots with official Kickstart 1.3 revision 34.5 in
Copperline 1.0.1. The machine is an A500 with a 68000, 512 KiB CHIP memory,
512 KiB slow memory and no fast memory. The default A500 chipset selection
is retained. The prepared program disk is read-only. All times below are
emulated time, measured from the scheduled input event.

## Effective pan and selection probes

The existing probe tool was extended outside the analysis agent to select
pointer position and action. Two further runs used a 120 ms hold, the same
capture schedule as below, and the same official-ROM checkpoints.

| Action | First visible response | Completed frame | Stable observation |
|---|---|---|---|
| RIGHT key, pointer in enlarged pane at `(200,80)` | After 20.001 ms and by 40.001 ms | After 200.001 ms and by 300.638 ms | Identical completed captures from 300.638 ms through just over 6000 ms |
| Select focus `(90,110)` after choosing zoom | After 20.002 ms and by 43.723 ms | After 300.000 ms and by 500.004 ms | Identical completed captures from 500.004 ms through just over 6000 ms |

These are capture bounds, not exact completion instants. The earliest pan
feedback changes the cursor and normal-pane indication; the enlarged diagonal
is visibly being redrawn at 200.001 ms and is continuous in its new position
at 300.638 ms. During selection, the first feedback changes the focus outline.
The 300 ms capture is still transitional; the 500 ms capture shows the complete
split display and continuous enlarged diagonal. The six-second capture window
settles both actions adequately. The measured native redraws take hundreds of
milliseconds on this configuration, rather than several seconds.

The entire pre-input scenes were inspected. The pan probe starts from the
established split view, with the authored diagonal continuous in the enlarged
pane and the pointer inside that pane. The selection probe starts from the
unzoomed authored diagonal with its focus rectangle already positioned, and
the pointer at the chosen focus. The two starting scenes are different stages
of the same input route; they are not interchangeable latency baselines.
Comparison with a replacement ROM must align the full scene, zoom state,
focus, tool and pointer position before applying the same action. In particular,
the toolbar-pointer no-op below must not be compared with an active-pane pan.

## Toolbar-pointer cursor-key probe

The existing `keybench.py` tool restored the official-ROM hover checkpoint,
moved the pointer to toolbar coordinate `(302,37)`, waited another 1.5 seconds,
and captured a baseline before scheduling one RIGHT raw-key tap (`78` decimal)
with an 80 ms hold. The checkpoint contains the established authored diagonal:
the normal pane at left and a continuous enlarged diagonal at right. Thus this
probe starts after the zoom entry and drawing operations have settled.

The 16 native captures requested at 20, 40, 60, 80, 100, 150, 200, 300, 500,
750, 1000, 1500, 2000, 3000, 4000 and 6000 ms are each pixel-identical to the
baseline, including the entire scene. The input was accepted as two scheduled
key events, and execution advanced past each requested capture time. The
last capture is just over 6000 ms after the scheduled key event.

This is an observed no-op for this scene and pointer position, not evidence
that a visible zoom-pan redraw finishes within 20 ms. There is no first visible
response or completed-redraw bound to report from this probe. The six-second
interval is adequate to show that no delayed visible change appeared during
that interval; it does not establish that the intended zoom-pan action was
activated. An effective input and scene must be demonstrated before comparing
redraw latency with a replacement ROM.

## Evidence and clean-room review

The uniquely named private runs `official-key-latency-20261116`,
`official-pan-latency-20261116` and `official-select-latency-20261116` record
the selected emulator, machine configuration, immutable inputs, PIDs, input
schedules, native captures and successful shutdown in their session ledgers. Raw logs,
profiling output, checkpoints and captures remain private and uncommitted.
Only observable timing and scene-state conclusions are reported here.

No original-ROM instructions, routine addresses, internal offsets, embedded
strings, graphics, fonts or other ROM data were inspected or reproduced for
this observation. The document contains no transcribed code or proprietary-ROM
address or data. Screenshots were used only as verification evidence, never
as a source of replacement geometry or image assets. No implementation,
regression-test, build-system or probe-script changes were authored by the
analysis agent.
